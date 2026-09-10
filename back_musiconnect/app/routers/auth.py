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

import bcrypt
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import User
from app.schemas import (
    ChangePasswordIn,
    ConfirmIn,
    ConfirmStatusOut,
    DeleteAccountIn,
    ForgotPasswordIn,
    LoginIn,
    ProfileUpdateIn,
    ResendIn,
    ResetPasswordIn,
    SignupIn,
    UserOut,
)
from app.services.email_service import send_confirmation_email, send_password_reset_email

# Tempo de validade do link de redefinição de senha.
PASSWORD_RESET_EXPIRY = timedelta(minutes=30)

logger = logging.getLogger("routers.auth")

router = APIRouter(prefix="/api/auth", tags=["auth"])

_bearer_scheme = HTTPBearer(auto_error=False)


def _hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def _verify_password(password: str, password_hash: str) -> bool:
    return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))


def _generate_token() -> str:
    return secrets.token_urlsafe(32)


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


@router.post("/signup", status_code=201)
async def signup(data: SignupIn, db: Session = Depends(get_db)):
    """
    Cria o usuário como pendente de confirmação (email_confirmed=False) e
    dispara o e-mail com o link de confirmação.

    Se o e-mail já existir mas ainda não tiver sido confirmado, os dados
    são atualizados e um novo token é gerado (permite refazer o cadastro
    se o usuário desistiu no meio do fluxo antes). Se já estiver
    confirmado, recusa — já existe uma conta de verdade com esse e-mail.
    """
    existing = db.query(User).filter(User.email == data.email).first()
    if existing and existing.email_confirmed:
        raise HTTPException(status_code=409, detail="E-mail já cadastrado.")

    token = _generate_token()
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

    db.commit()

    sent = await send_confirmation_email(to_email=data.email, token=token)
    return {"status": "sent" if sent else "user_created_email_failed", "email": data.email}


@router.post("/resend")
async def resend_confirmation(data: ResendIn, db: Session = Depends(get_db)):
    """Gera um novo token e reenvia o e-mail de confirmação."""
    user = db.query(User).filter(User.email == data.email).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuário não encontrado.")
    if user.email_confirmed:
        raise HTTPException(status_code=409, detail="E-mail já confirmado.")

    user.confirmation_token = _generate_token()
    user.confirmation_sent_at = datetime.now(timezone.utc)
    db.commit()

    sent = await send_confirmation_email(to_email=user.email, token=user.confirmation_token)
    return {"status": "sent" if sent else "email_failed", "email": user.email}


@router.post("/confirm")
def confirm_email(data: ConfirmIn, db: Session = Depends(get_db)):
    """
    Confirma o e-mail a partir do token do link (chamado pelo app assim
    que o deep link `musiconnect://confirm?token=...` é recebido).
    """
    user = db.query(User).filter(User.confirmation_token == data.token).first()
    if not user:
        raise HTTPException(status_code=400, detail="Link de confirmação inválido.")
    if user.email_confirmed:
        return {"status": "already_confirmed", "email": user.email}

    user.email_confirmed = True
    user.confirmed_at = datetime.now(timezone.utc)
    # Invalida o token — cada link só confirma uma vez.
    user.confirmation_token = None
    db.commit()

    logger.info("[Auth] E-mail confirmado: %s", user.email)
    return {"status": "confirmed", "email": user.email}


@router.get("/status", response_model=ConfirmStatusOut)
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


@router.post("/login", response_model=UserOut)
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


@router.post("/forgot-password")
async def forgot_password(data: ForgotPasswordIn, db: Session = Depends(get_db)):
    """
    Envia o e-mail de redefinição de senha (link válido por 30min).

    Resposta sempre genérica, exista o e-mail ou não — revelar isso
    permitiria descobrir quais e-mails têm conta só tentando redefinir a
    senha deles (enumeração de usuários).
    """
    user = db.query(User).filter(User.email == data.email).first()
    if user:
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


@router.post("/reset-password")
def reset_password(data: ResetPasswordIn, db: Session = Depends(get_db)):
    """
    Efetiva a nova senha a partir do token do link (chamado pelo app assim
    que o deep link `musiconnect://reset-password?token=...` é recebido,
    ou pela tela de definir nova senha).
    """
    user = db.query(User).filter(User.password_reset_token == data.token).first()
    if not user or user.password_reset_sent_at is None:
        raise HTTPException(status_code=400, detail="Link de redefinição inválido.")

    sent_at = user.password_reset_sent_at
    if sent_at.tzinfo is None:
        sent_at = sent_at.replace(tzinfo=timezone.utc)
    if datetime.now(timezone.utc) - sent_at > PASSWORD_RESET_EXPIRY:
        raise HTTPException(
            status_code=400,
            detail="Esse link de redefinição expirou. Solicite um novo.",
        )

    user.password_hash = _hash_password(data.password)
    # Invalida o token — cada link só redefine uma vez.
    user.password_reset_token = None
    user.password_reset_sent_at = None
    # Invalida qualquer sessão ativa (nesse ou em outro dispositivo) —
    # boa prática de segurança ao trocar a senha.
    user.session_token = None
    db.commit()

    logger.info("[Auth] Senha redefinida: %s", user.email)
    return {"status": "reset", "email": user.email}


@router.get("/me", response_model=UserOut)
def get_me(user: User = Depends(get_current_user)):
    """Dados do usuário logado — chamado na abertura do app pra validar o
    token salvo localmente e carregar o perfil atual."""
    return user


@router.patch("/me", response_model=UserOut)
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


@router.post("/change-password", response_model=UserOut)
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


@router.post("/logout")
def logout(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Invalida o token de sessão no servidor."""
    user.session_token = None
    db.commit()
    return {"status": "logged_out"}


@router.delete("/me")
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
