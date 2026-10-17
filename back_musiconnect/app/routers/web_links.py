"""
Destinos dos links dos e-mails (https://musiconnect.app.br/...).

Com o app instalado, o Android abre o app direto nesses links (App Links,
verificados por /.well-known/assetlinks.json) e estas páginas nem chegam a
aparecer. Sem o app (ex: e-mail lido no computador), elas resolvem tudo no
navegador:

  GET  /.well-known/assetlinks.json — autoriza o app Android a abrir os links
  GET  /confirmar?token=...         — página com o botão "Confirmar e-mail"
  POST /confirmar                   — confirma o cadastro
  GET  /redefinir-senha?token=...   — formulário de nova senha
  POST /redefinir-senha             — troca a senha

Abrir o link (GET) nunca muda nada: confirmar/trocar exige o envio do
formulário (POST) — leitores de e-mail e antivírus às vezes "visitam" os
links sozinhos.
"""

from html import escape

from fastapi import APIRouter, Depends, Form
from fastapi.responses import HTMLResponse, JSONResponse
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.routers.auth import confirm_by_token, find_valid_reset_user, reset_by_token
from app.services.passwords import is_strong_password

router = APIRouter(tags=["links dos e-mails"], include_in_schema=False)

_EXPIRED_MESSAGE = "Esse link de redefinição expirou. Peça um novo no app, em “Esqueci minha senha”."
_INVALID_RESET_MESSAGE = "Esse link de redefinição é inválido ou já foi usado. Peça um novo no app."


@router.get("/.well-known/assetlinks.json")
def assetlinks():
    fingerprints = [
        f.strip() for f in settings.android_cert_fingerprints.split(",") if f.strip()
    ]
    return JSONResponse([
        {
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": settings.android_package_name,
                "sha256_cert_fingerprints": fingerprints,
            },
        }
    ])


# ── Confirmação de cadastro ──────────────────────────────────────────────

@router.get("/confirmar", response_class=HTMLResponse)
def confirm_page(token: str = ""):
    return _page(
        "Confirmar e-mail",
        f"""
        <p>Falta só um passo para concluir seu cadastro no MusiConnect.</p>
        <form method="post" action="/confirmar">
          <input type="hidden" name="token" value="{escape(token)}">
          <button type="submit">Confirmar e-mail</button>
        </form>
        """,
    )


@router.post("/confirmar", response_class=HTMLResponse)
def confirm_submit(token: str = Form(""), db: Session = Depends(get_db)):
    status, _ = confirm_by_token(db, token)
    if status == "invalid":
        return _page(
            "Link inválido",
            "<p>Esse link de confirmação é inválido ou já foi usado. "
            "Se ainda não confirmou, peça um novo e-mail no app.</p>",
            status_code=400,
        )
    return _page(
        "Cadastro confirmado!",
        "<p>Seu e-mail foi confirmado. Abra o app MusiConnect e faça login.</p>",
    )


# ── Redefinição de senha ─────────────────────────────────────────────────

@router.get("/redefinir-senha", response_class=HTMLResponse)
def reset_page(token: str = "", db: Session = Depends(get_db)):
    status, _ = find_valid_reset_user(db, token)
    if status != "ok":
        message = _EXPIRED_MESSAGE if status == "expired" else _INVALID_RESET_MESSAGE
        return _page("Link inválido", f"<p>{message}</p>", status_code=400)
    return _reset_form(token)


@router.post("/redefinir-senha", response_class=HTMLResponse)
def reset_submit(
    token: str = Form(""),
    password: str = Form(""),
    password_confirm: str = Form(""),
    db: Session = Depends(get_db),
):
    if password != password_confirm:
        return _reset_form(token, error="As senhas não coincidem.", status_code=400)
    if not is_strong_password(password):
        return _reset_form(
            token,
            error="A senha precisa ter 8 ou mais caracteres e pelo menos 2 destes: "
            "letras maiúsculas e minúsculas, número, caractere especial.",
            status_code=400,
        )

    status = reset_by_token(db, token, password)
    if status != "reset":
        message = _EXPIRED_MESSAGE if status == "expired" else _INVALID_RESET_MESSAGE
        return _page("Link inválido", f"<p>{message}</p>", status_code=400)
    return _page(
        "Senha alterada!",
        "<p>Sua senha foi alterada. Abra o app MusiConnect e faça login com a nova senha.</p>",
    )


def _reset_form(token: str, error: str | None = None, status_code: int = 200) -> HTMLResponse:
    error_html = f'<p class="error">{escape(error)}</p>' if error else ""
    return _page(
        "Nova senha",
        f"""
        <p>Escolha uma nova senha para sua conta no MusiConnect.</p>
        {error_html}
        <form method="post" action="/redefinir-senha">
          <input type="hidden" name="token" value="{escape(token)}">
          <label>Nova senha
            <input type="password" name="password" required minlength="8" autocomplete="new-password">
          </label>
          <label>Confirme a nova senha
            <input type="password" name="password_confirm" required minlength="8" autocomplete="new-password">
          </label>
          <p class="hint">8 ou mais caracteres e pelo menos 2 destes: letras maiúsculas e
          minúsculas, número, caractere especial.</p>
          <button type="submit">Salvar nova senha</button>
        </form>
        """,
        status_code=status_code,
    )


def _page(title: str, body: str, status_code: int = 200) -> HTMLResponse:
    """Página simples no visual do app (rosa #DF2881, cartão branco)."""
    html = f"""<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex">
  <title>{escape(title)} — MusiConnect</title>
  <style>
    body {{ margin: 0; font-family: Roboto, Arial, sans-serif; background: #f6f6f8;
           color: #1f2937; display: flex; justify-content: center; padding: 32px 16px; }}
    .card {{ background: #fff; max-width: 420px; width: 100%; border-radius: 16px;
            padding: 28px 24px; box-shadow: 0 4px 16px rgba(0,0,0,.06); }}
    .logo {{ font-weight: 800; font-size: 22px; margin: 0 0 20px; }}
    .logo span {{ color: #DF2881; }}
    h1 {{ font-size: 22px; margin: 0 0 12px; }}
    p {{ line-height: 1.5; color: #4b5563; }}
    label {{ display: block; font-weight: 700; font-size: 14px; margin: 16px 0 0; }}
    input[type=password] {{ display: block; width: 100%; box-sizing: border-box; margin-top: 6px;
            padding: 12px; border: 1px solid #d1d5db; border-radius: 10px; font-size: 15px; }}
    button {{ margin-top: 20px; width: 100%; padding: 14px; border: 0; border-radius: 24px;
             background: #DF2881; color: #fff; font-size: 15px; font-weight: 700; cursor: pointer; }}
    .hint {{ font-size: 12.5px; }}
    .error {{ color: #b91c1c; font-weight: 600; }}
  </style>
</head>
<body>
  <main class="card">
    <p class="logo">Musi<span>Connect</span></p>
    <h1>{escape(title)}</h1>
    {body}
  </main>
</body>
</html>"""
    return HTMLResponse(html, status_code=status_code)
