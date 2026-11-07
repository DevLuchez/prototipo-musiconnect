"""
Router de autenticação — cadastro do app Flutter com confirmação por e-mail
e sessão persistida por token.

Endpoints:
  POST /api/auth/signup           — cria/atualiza o usuário pendente e envia o e-mail
  POST /api/auth/resend           — reenvia o e-mail de confirmação
  POST /api/auth/confirm          — confirma o e-mail a partir do token (deep link)
  GET  /api/auth/status           — consulta se um e-mail já foi confirmado
  POST /api/auth/login            — autentica e devolve um token de sessão
  POST /api/auth/forgot-password  — envia o e-mail de redefinição de senha
  POST /api/auth/reset-password   — efetiva a nova senha a partir do token
  GET  /api/auth/me               — dados do usuário logado (valida o token salvo no app)
  PATCH /api/auth/me              — edita o perfil (nome/instrumentos/ramo/localização)
  POST /api/auth/change-password  — troca de senha logado (pede a senha atual)
  POST /api/auth/logout           — invalida o token de sessão
  DELETE /api/auth/me             — exclui a conta (pede confirmação de senha)

O token de sessão é opaco e não expira (mesmo padrão dos outros tokens
deste router) — invalidado só no logout ou ao trocar de senha por
qualquer via.
"""

import logging
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

import bcrypt
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import DeviceToken, User
from app.openapi_docs import UNAUTHORIZED, error
from app.schemas import (
    ChangePasswordIn,
    ConfirmIn,
    ConfirmStatusOut,
    DeleteAccountIn,
    ForgotPasswordIn,
    LoginIn,
    PrivacyAcceptIn,
    ProfileUpdateIn,
    ResendIn,
    ResetPasswordIn,
    SignupIn,
    StatusOut,
    UserOut,
)
from app.services.email_service import send_confirmation_email, send_password_reset_email

# Tempo de validade dos links dos e-mails. O de confirmação é mais longo
# porque a pessoa pode abrir o e-mail bem depois (ou achá-lo no spam), e
# ele só confirma o e-mail — não dá acesso à conta.
PASSWORD_RESET_EXPIRY = timedelta(minutes=15)
CONFIRMATION_EXPIRY = timedelta(hours=24)

# Versão da Política de privacidade registrada quando o app não informa qual
# a pessoa leu: o app v1.0.0, que mostra o texto de 2026-10-30. Os apps
# seguintes enviam a versão que exibiram (kPrivacyPolicyVersion) — é ela que
# fica registrada. Por isso este valor NÃO muda quando a política muda: se
# mudasse, quem usa um app antigo aceitaria uma versão e o app esperaria
# outra, pedindo o aceite sem parar.
LEGACY_PRIVACY_POLICY_VERSION = "2026-10-30"

logger = logging.getLogger("routers.auth")

router = APIRouter(prefix="/api/auth", tags=["Autenticação"])

_bearer_scheme = HTTPBearer(auto_error=False)


def _hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def _verify_password(password: str, password_hash: str) -> bool:
    return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))


def _generate_token() -> str:
    return secrets.token_urlsafe(32)


def _expired(sent_at: datetime | None, expiry: timedelta) -> bool:
    if sent_at is None:
        return True
    if sent_at.tzinfo is None:
        sent_at = sent_at.replace(tzinfo=timezone.utc)
    return datetime.now(timezone.utc) - sent_at > expiry


def _confirmation_link_valid(user: User) -> bool:
    return bool(user.confirmation_token) and not _expired(
        user.confirmation_sent_at, CONFIRMATION_EXPIRY
    )


def _record_privacy_consent(user: User, now: datetime, version: Optional[str] = None) -> None:
    """Guarda a prova do consentimento (LGPD): quando e qual versão da
    Política de privacidade o usuário aceitou — a que o app exibiu."""
    user.privacy_accepted_at = now
    user.privacy_policy_version = version or LEGACY_PRIVACY_POLICY_VERSION


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    """Resolve o usuário logado a partir do header `Authorization: Bearer
    <token>` — usado por toda rota que precisa saber "quem está logado"."""
    if credentials is None:
        raise HTTPException(status_code=401, detail="Sessão ausente. Faça login novamente.")
    user = db.query(User).filter(User.session_token == credentials.credentials).first()
    if not user:
        raise HTTPException(status_code=401, detail="Sessão inválida. Faça login novamente.")
    return user


def get_current_user_optional(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> User | None:
    """Mesma resolução de `get_current_user`, mas devolve `None` (em vez de
    401) quando o token está ausente ou inválido — usado por rotas que
    continuam acessíveis sem login, mas se comportam diferente com um
    usuário identificado (ex: match_percentage nas oportunidades)."""
    if credentials is None:
        return None
    return db.query(User).filter(User.session_token == credentials.credentials).first()


@router.post(
    "/signup",
    status_code=201,
    summary="Criar conta",
    description="Cadastra o usuário e envia o e-mail de confirmação (link válido por 24 horas). Exige o aceite da política de privacidade. O login só é liberado após a confirmação.",
    responses={201: {"model": StatusOut, "description": "Conta criada e e-mail de confirmação enviado."}, 409: error("E-mail já cadastrado."), 422: error("Dados inválidos (ex.: senha fraca ou política não aceita).")},
)
async def signup(data: SignupIn, db: Session = Depends(get_db)):
    """
    Cria o usuário como pendente de confirmação (email_confirmed=False) e
    dispara o e-mail com o link de confirmação.

    Se o e-mail já existir mas ainda não tiver sido confirmado, os dados
    são atualizados e um novo token é gerado (permite refazer o cadastro
    se o usuário desistiu no meio do fluxo antes). Se já estiver
    confirmado, recusa — já existe uma conta de verdade com esse e-mail.
    O link de confirmação continua o mesmo (ver `resend_confirmation`).
    """
    existing = db.query(User).filter(User.email == data.email).first()
    if existing and existing.email_confirmed:
        raise HTTPException(status_code=409, detail="E-mail já cadastrado.")

    keep_link = existing is not None and _confirmation_link_valid(existing)
    token = existing.confirmation_token if keep_link else _generate_token()
    now = datetime.now(timezone.utc)

    if existing:
        user = existing
    else:
        user = User(email=data.email)
        db.add(user)

    user.password_hash = _hash_password(data.password)
    user.name = data.name
    user.instruments = data.instruments
    user.is_professional = data.is_professional
    user.is_student = data.is_student
    user.country = data.country
    user.state = data.state
    user.city = data.city
    user.confirmation_token = token
    user.confirmation_sent_at = now
    user.email_confirmed = False
    _record_privacy_consent(user, now, data.privacy_policy_version)

    db.commit()

    sent = await send_confirmation_email(to_email=data.email, token=token)
    return {"status": "sent" if sent else "user_created_email_failed", "email": data.email}


@router.post(
    "/resend",
    summary="Reenviar o e-mail de confirmação",
    description="Gera um novo link de confirmação e o envia ao e-mail informado.",
    responses={200: {"model": StatusOut, "description": "E-mail reenviado."}, 404: error("Usuário não encontrado."), 409: error("E-mail já confirmado.")},
)
async def resend_confirmation(data: ResendIn, db: Session = Depends(get_db)):
    """Reenvia o e-mail de confirmação com o mesmo link (com mais 24h), se
    ele ainda vale: um token novo invalidaria o link do e-mail anterior, e
    a pessoa costuma tocar no primeiro e-mail que encontra."""
    user = db.query(User).filter(User.email == data.email).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuário não encontrado.")
    if user.email_confirmed:
        raise HTTPException(status_code=409, detail="E-mail já confirmado.")

    if not _confirmation_link_valid(user):
        user.confirmation_token = _generate_token()
    user.confirmation_sent_at = datetime.now(timezone.utc)
    db.commit()

    sent = await send_confirmation_email(to_email=user.email, token=user.confirmation_token)
    return {"status": "sent" if sent else "email_failed", "email": user.email}


def confirm_by_token(db: Session, token: str) -> tuple[str, User | None]:
    """Confirma o cadastro dono do token. Devolve ("confirmed" |
    "already_confirmed" | "invalid" | "expired", usuário). Usada pela API
    (app) e pela página /confirmar (navegador)."""
    user = db.query(User).filter(User.confirmation_token == token).first()
    if not user:
        return "invalid", None
    if user.email_confirmed:
        return "already_confirmed", user
    if _expired(user.confirmation_sent_at, CONFIRMATION_EXPIRY):
        return "expired", None

    user.email_confirmed = True
    user.confirmed_at = datetime.now(timezone.utc)
    # Invalida o token — cada link só confirma uma vez.
    user.confirmation_token = None
    db.commit()

    logger.info("[Auth] E-mail confirmado: %s", user.email)
    return "confirmed", user


@router.post(
    "/confirm",
    summary="Confirmar o e-mail",
    description="Confirma o e-mail a partir do código recebido no link.",
    responses={200: {"model": StatusOut, "description": "E-mail confirmado."}, 400: error("Link de confirmação inválido ou expirado.")},
)
def confirm_email(data: ConfirmIn, db: Session = Depends(get_db)):
    """
    Confirma o e-mail a partir do token do link (chamado pelo app assim
    que o link do e-mail abre o app).
    """
    status, user = confirm_by_token(db, data.token)
    if status == "invalid":
        raise HTTPException(status_code=400, detail="Link de confirmação inválido.")
    if status == "expired":
        raise HTTPException(
            status_code=400,
            detail="Esse link de confirmação expirou. Entre no app com seu e-mail "
            "e senha para receber um novo.",
        )
    return {"status": status, "email": user.email}


@router.get(
    "/status",
    response_model=ConfirmStatusOut,
    summary="Consultar a confirmação do e-mail",
    response_description="Situação da confirmação.",
    description="Informa se o e-mail já foi confirmado. Usada pelo aplicativo enquanto aguarda a confirmação.",
    responses={404: error("Usuário não encontrado.")},
)
def confirmation_status(email: str, db: Session = Depends(get_db)):
    """
    Consulta se um e-mail já foi confirmado — usado pelo botão "Já
    confirmei" quando o usuário volta pro app sem ter passado pelo deep
    link nesta sessão (ex: confirmou em outro dispositivo).
    """
    user = db.query(User).filter(User.email == email).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuário não encontrado.")
    return ConfirmStatusOut(confirmed=user.email_confirmed)


@router.post(
    "/login",
    response_model=UserOut,
    summary="Entrar na conta",
    response_description="Dados do usuário, com o token de sessão.",
    description="Autentica o usuário e retorna os seus dados com o token de sessão, que deve ser enviado nas demais rotas no cabeçalho `Authorization: Bearer <token>`.",
    responses={401: error("E-mail ou senha inválidos."), 403: error("E-mail ainda não confirmado.")},
)
def login(data: LoginIn, db: Session = Depends(get_db)):
    """
    Autentica um usuário e devolve um token de sessão (o app guarda esse
    token localmente pra abrir direto logado nas próximas vezes).

    Mensagem de erro genérica quando e-mail ou senha não batem (não
    revela qual dos dois — evita enumeração de e-mails cadastrados).
    E-mail encontrado + senha certa, mas ainda não confirmado, ganha uma
    mensagem própria: não é um problema de segurança dizer isso a quem já
    sabe a senha da própria conta.
    """
    user = db.query(User).filter(User.email == data.email).first()
    if not user or not _verify_password(data.password, user.password_hash):
        raise HTTPException(status_code=401, detail="E-mail ou senha inválidos.")
    if not user.email_confirmed:
        raise HTTPException(
            status_code=403, detail="Confirme seu e-mail antes de entrar."
        )

    user.session_token = _generate_token()
    db.commit()

    result = UserOut.model_validate(user)
    result.token = user.session_token
    return result


@router.post(
    "/forgot-password",
    summary="Solicitar a redefinição de senha",
    description="Envia um link de redefinição (válido por 15 minutos), se o e-mail estiver cadastrado. A resposta é sempre a mesma, para não revelar quais e-mails existem.",
    responses={200: {"model": StatusOut, "description": "Pedido recebido."}},
)
async def forgot_password(data: ForgotPasswordIn, db: Session = Depends(get_db)):
    """
    Envia o e-mail de redefinição de senha (link válido por 15min).

    Resposta sempre genérica, exista o e-mail ou não — revelar isso
    permitiria descobrir quais e-mails têm conta só tentando redefinir a
    senha deles (enumeração de usuários).

    Pedir de novo com um link ainda válido reenvia o mesmo link (com mais
    15min): um token novo invalidaria o do e-mail anterior, e a pessoa
    costuma tocar no primeiro e-mail que encontra.
    """
    user = db.query(User).filter(User.email == data.email).first()
    if user:
        status, _ = find_valid_reset_user(db, user.password_reset_token or "")
        if status != "ok":
            user.password_reset_token = _generate_token()
        user.password_reset_sent_at = datetime.now(timezone.utc)
        db.commit()
        await send_password_reset_email(
            to_email=user.email, token=user.password_reset_token
        )

    return {
        "status": "sent",
        "message": "Se esse e-mail estiver cadastrado, enviamos um link de redefinição.",
    }


def find_valid_reset_user(db: Session, token: str) -> tuple[str, User | None]:
    """Usuário dono de um link de redefinição ainda válido. Devolve
    ("ok" | "invalid" | "expired", usuário)."""
    user = db.query(User).filter(User.password_reset_token == token).first()
    if not user or user.password_reset_sent_at is None:
        return "invalid", None

    if _expired(user.password_reset_sent_at, PASSWORD_RESET_EXPIRY):
        return "expired", None
    return "ok", user


def reset_by_token(db: Session, token: str, new_password: str) -> str:
    """Troca a senha pelo link de redefinição. Devolve "reset" |
    "invalid" | "expired". Usada pela API (app) e pela página
    /redefinir-senha (navegador)."""
    status, user = find_valid_reset_user(db, token)
    if status != "ok":
        return status

    user.password_hash = _hash_password(new_password)
    # Invalida o token — cada link só redefine uma vez.
    user.password_reset_token = None
    user.password_reset_sent_at = None
    # Invalida qualquer sessão ativa (nesse ou em outro dispositivo) —
    # boa prática de segurança ao trocar a senha.
    user.session_token = None
    db.commit()

    logger.info("[Auth] Senha redefinida: %s", user.email)
    return "reset"


@router.post(
    "/reset-password",
    summary="Redefinir a senha",
    description="Define uma nova senha a partir do código recebido no link e encerra as sessões abertas.",
    responses={200: {"model": StatusOut, "description": "Senha redefinida."}, 400: error("Link de redefinição inválido ou expirado."), 422: error("Senha fraca.")},
)
def reset_password(data: ResetPasswordIn, db: Session = Depends(get_db)):
    """
    Efetiva a nova senha a partir do token do link (chamado pela tela de
    definir nova senha do app, aberta pelo link do e-mail).
    """
    status = reset_by_token(db, data.token, data.password)
    if status == "invalid":
        raise HTTPException(status_code=400, detail="Link de redefinição inválido.")
    if status == "expired":
        raise HTTPException(
            status_code=400,
            detail="Esse link de redefinição expirou. Solicite um novo.",
        )
    return {"status": "reset"}


@router.get(
    "/me",
    response_model=UserOut,
    summary="Consultar o perfil",
    response_description="Dados do usuário.",
    description="Retorna os dados do usuário autenticado.",
    responses=UNAUTHORIZED,
)
def get_me(user: User = Depends(get_current_user)):
    """Dados do usuário logado — chamado na abertura do app pra validar o
    token salvo localmente e carregar o perfil atual."""
    return user


@router.patch(
    "/me",
    response_model=UserOut,
    summary="Editar o perfil",
    response_description="Perfil atualizado.",
    description="Atualiza nome, instrumentos, ramo de atuação e localização do usuário autenticado.",
    responses=UNAUTHORIZED,
)
def update_me(
    data: ProfileUpdateIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Edita o perfil do usuário logado. E-mail não é editável aqui."""
    user.name = data.name
    user.instruments = data.instruments
    user.is_professional = data.is_professional
    user.is_student = data.is_student
    user.country = data.country
    user.state = data.state
    user.city = data.city
    db.commit()
    return user


@router.post(
    "/change-password",
    response_model=UserOut,
    summary="Trocar a senha",
    response_description="Senha trocada; dados do usuário com o novo token de sessão.",
    description="Troca a senha do usuário autenticado, mediante a senha atual. Gera um novo token de sessão, retornado na resposta.",
    responses={401: error("Sessão inválida ou senha atual incorreta."), 422: error("Nova senha fraca.")},
)
def change_password(
    data: ChangePasswordIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Troca de senha estando logado — diferente do "esqueci minha senha",
    pede a senha atual em vez de um link por e-mail.

    Gera um novo token de sessão (o antigo é invalidado por tabela — o
    app atualiza o token salvo localmente com o valor devolvido aqui, sem
    precisar deslogar o usuário no meio do processo).
    """
    if not _verify_password(data.current_password, user.password_hash):
        raise HTTPException(status_code=401, detail="Senha atual incorreta.")

    user.password_hash = _hash_password(data.new_password)
    user.session_token = _generate_token()
    db.commit()

    result = UserOut.model_validate(user)
    result.token = user.session_token
    return result


@router.post(
    "/accept-privacy",
    response_model=UserOut,
    summary="Aceitar a política de privacidade atualizada",
    response_description="Aceite registrado.",
    description="Registra o aceite de uma nova versão da política de privacidade.",
    responses=UNAUTHORIZED,
)
def accept_privacy(
    data: Optional[PrivacyAcceptIn] = None,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Novo aceite da Política de privacidade por quem já tem conta — o app
    pede ao abrir quando a versão aceita é anterior à dele."""
    _record_privacy_consent(
        user, datetime.now(timezone.utc), data.privacy_policy_version if data else None
    )
    db.commit()
    return user


@router.post(
    "/logout",
    summary="Sair da conta",
    description="Invalida o token de sessão e desvincula o aparelho das notificações.",
    responses={200: {"model": StatusOut, "description": "Sessão encerrada."}, **UNAUTHORIZED},
)
def logout(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Invalida o token de sessão no servidor e para as notificações do
    aparelho — quem saiu não recebe mais (num celular compartilhado, a
    próxima pessoa não vê as oportunidades de quem saiu)."""
    user.session_token = None
    db.query(DeviceToken).filter(DeviceToken.user_id == user.id).delete()
    db.commit()
    return {"status": "logged_out"}


@router.delete(
    "/me",
    summary="Excluir a conta",
    description="Exclui a conta e todos os dados do usuário (favoritos, aparelhos e histórico de notificações), mediante a senha. A ação é irreversível.",
    responses={200: {"model": StatusOut, "description": "Conta excluída."}, 401: error("Sessão inválida ou senha incorreta.")},
)
def delete_account(
    data: DeleteAccountIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Exclui a conta do usuário logado permanentemente. Pede confirmação de
    senha — ação irreversível, não basta ter uma sessão válida (que pode
    ter ficado salva num dispositivo esquecido/emprestado).
    """
    if not _verify_password(data.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Senha incorreta.")

    email = user.email
    db.delete(user)
    db.commit()

    logger.info("[Auth] Conta excluída: %s", email)
    return {"status": "deleted"}
