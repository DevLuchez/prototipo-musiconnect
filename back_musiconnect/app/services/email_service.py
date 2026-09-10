"""
Envio de e-mail transacional via Resend (https://resend.com).

Sem domínio próprio verificado no Resend, o remetente é obrigatoriamente
onboarding@resend.dev, e só é possível enviar para o e-mail da própria
conta cadastrada no Resend (modo sandbox) — suficiente para testar o
fluxo de confirmação de cadastro no protótipo.
"""

import logging

import httpx

from app.config import settings

logger = logging.getLogger("services.email")

_RESEND_URL = "https://api.resend.com/emails"

# Esquema de URL customizado do app — sem domínio próprio verificado,
# Universal Links/App Links não são possíveis; um link com esse esquema
# abre o app diretamente no celular (se instalado), sem precisar de
# hospedagem nem verificação de domínio.
CONFIRM_DEEP_LINK_SCHEME = "musiconnect://confirm"
RESET_PASSWORD_DEEP_LINK_SCHEME = "musiconnect://reset-password"


def build_confirmation_link(token: str) -> str:
    return f"{CONFIRM_DEEP_LINK_SCHEME}?token={token}"


def build_reset_password_link(token: str) -> str:
    return f"{RESET_PASSWORD_DEEP_LINK_SCHEME}?token={token}"


async def _send_email(*, to_email: str, subject: str, html: str) -> bool:
    """Chamada de baixo nível pra API do Resend. Retorna True se aceito
    (não garante entrega, só que a API aceitou o envio)."""

    if not settings.resend_api_key:
        logger.warning(
            "[EmailService] RESEND_API_KEY não configurada — e-mail não enviado "
            "(assunto=%s, destino=%s)",
            subject,
            to_email,
        )
        return False

    try:
        async with httpx.AsyncClient(timeout=15) as client:
            response = await client.post(
                _RESEND_URL,
                headers={
                    "Authorization": f"Bearer {settings.resend_api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "from": f"MusiConnect <{settings.resend_from_email}>",
                    "to": [to_email],
                    "subject": subject,
                    "html": html,
                },
            )
        if response.status_code >= 400:
            logger.error(
                "[EmailService] Resend recusou o envio (status=%s): %s",
                response.status_code,
                response.text,
            )
            return False
        logger.info("[EmailService] E-mail '%s' enviado para %s", subject, to_email)
        return True
    except httpx.HTTPError as e:
        logger.error("[EmailService] Exceção ao enviar e-mail: %s", e)
        return False


def _button_html(link: str, label: str) -> str:
    return f"""
      <p>
        <a href="{link}"
           style="display:inline-block;background:#DF2881;color:#fff;
                  padding:12px 24px;border-radius:24px;text-decoration:none;
                  font-weight:bold;">
          {label}
        </a>
      </p>
    """


async def send_confirmation_email(*, to_email: str, token: str) -> bool:
    """Envia o e-mail de confirmação de cadastro."""
    link = build_confirmation_link(token)
    html = f"""
    <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto;">
      <h2 style="color:#DF2881;">MusiConnect</h2>
      <p>Confirme seu e-mail para concluir seu cadastro no MusiConnect.</p>
      {_button_html(link, "Confirmar e-mail")}
      <p style="color:#888;font-size:12px;">
        Se você não criou uma conta no MusiConnect, ignore este e-mail.
      </p>
    </div>
    """
    return await _send_email(
        to_email=to_email, subject="Confirme seu e-mail — MusiConnect", html=html
    )


async def send_password_reset_email(*, to_email: str, token: str) -> bool:
    """Envia o e-mail de redefinição de senha (link válido por 30min)."""
    link = build_reset_password_link(token)
    html = f"""
    <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto;">
      <h2 style="color:#DF2881;">MusiConnect</h2>
      <p>Recebemos um pedido para redefinir a senha da sua conta no MusiConnect.</p>
      {_button_html(link, "Redefinir senha")}
      <p style="color:#888;font-size:12px;">
        Esse link expira em 30 minutos. Se você não pediu essa redefinição,
        ignore este e-mail — sua senha continua a mesma.
      </p>
    </div>
    """
    return await _send_email(
        to_email=to_email, subject="Redefinir sua senha — MusiConnect", html=html
    )
