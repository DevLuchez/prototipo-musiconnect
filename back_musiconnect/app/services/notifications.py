"""
Notificações diárias (09h, depois da coleta das 06h) pelo Firebase Cloud
Messaging. Dois avisos, cada um com sua chave no Perfil:

  - Novas para você: oportunidades que entraram nos últimos dias com match
    >= HIGH_MATCH_THRESHOLD (o mesmo corte de "Minhas oportunidades"). Uma
    só → abre a oportunidade; várias → abre "Minhas oportunidades".
  - Prazos dos favoritos: favorita a menos de URGENT_DEADLINE_DAYS do prazo
    (mesma regra do "Última chance" do Início e da data vermelha no card) e
    no último dia. Várias no mesmo dia → uma notificação só, que abre os
    favoritos.

No máximo uma notificação de cada tipo por dia, e cada aviso uma única vez
por oportunidade (NotificationLog). Só recebe quem está conectado num
aparelho que permitiu as notificações (DeviceToken).
"""

import logging
import os
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from typing import Callable, Optional

from sqlalchemy.orm import Session

from app.config import settings
from app.database import SessionLocal
from app.models import DeviceToken, FavoriteOpportunity, NotificationLog, Opportunity, User
from app.routers.opportunities import _apply_filters, _only_open
from app.services.matching import (
    HIGH_MATCH_THRESHOLD,
    URGENT_DEADLINE_DAYS,
    compute_match_percentage,
)

logger = logging.getLogger("services.notifications")

# Janela de "nova": cobre um dia sem notificação (servidor fora do ar) e a
# oportunidade que só foi enriquecida no dia seguinte (cota do Gemini). O
# NotificationLog garante que a mesma não seja avisada duas vezes.
NEW_WINDOW = timedelta(days=3)


@dataclass
class Push:
    """Uma notificação para uma pessoa. `data` diz ao app o que abrir ao
    tocar: {"open": "opportunity", "opportunity_id": "12"}, {"open":
    "matches"} ou {"open": "favorites"}."""

    user_id: int
    title: str
    body: str
    data: dict
    # (opportunity_id, kind) registrados no NotificationLog se o envio sair.
    logged: list = field(default_factory=list)


def _days_left_text(days: int) -> str:
    return "Falta 1 dia" if days == 1 else f"Faltam {days} dias"


def _new_matches_push(user: User, opportunities: list[Opportunity]) -> Optional[Push]:
    if not opportunities:
        return None
    logged = [(o.id, "new_match") for o in opportunities]
    if len(opportunities) == 1:
        opp = opportunities[0]
        return Push(
            user_id=user.id,
            title="Nova oportunidade para você",
            body=f"{opp.title} · {opp.match_percentage}% de match",
            data={"open": "opportunity", "opportunity_id": str(opp.id)},
            logged=logged,
        )
    return Push(
        user_id=user.id,
        title=f"{len(opportunities)} novas oportunidades para você",
        body=f"Com {HIGH_MATCH_THRESHOLD}% ou mais de match. Toque para ver.",
        data={"open": "matches"},
        logged=logged,
    )


def _deadlines_push(user: User, soon: list[Opportunity], last: list[Opportunity],
                    today: date) -> Optional[Push]:
    logged = [(o.id, "deadline_soon") for o in soon] + [(o.id, "deadline_last") for o in last]
    total = len(soon) + len(last)
    if total == 0:
        return None
    if total > 1:
        return Push(
            user_id=user.id,
            title=f"{total} favoritas com prazo acabando",
            body="Toque para ver.",
            data={"open": "favorites"},
            logged=logged,
        )
    if last:
        opp = last[0]
        return Push(
            user_id=user.id,
            title="Último dia!",
            body=f"As inscrições de {opp.title} fecham hoje.",
            data={"open": "opportunity", "opportunity_id": str(opp.id)},
            logged=logged,
        )
    opp = soon[0]
    return Push(
        user_id=user.id,
        title="O prazo está acabando",
        body=f"{_days_left_text((opp.deadline - today).days)} para se inscrever em: {opp.title}",
        data={"open": "opportunity", "opportunity_id": str(opp.id)},
        logged=logged,
    )


def build_daily_pushes(db: Session, today: Optional[date] = None,
                       now: Optional[datetime] = None) -> list[Push]:
    """Monta as notificações do dia (sem enviar). Só para quem tem aparelho
    registrado e a chave correspondente ligada."""
    today = today or date.today()
    now = now or datetime.now(timezone.utc).replace(tzinfo=None)

    users = (
        db.query(User)
        .filter(User.id.in_(db.query(DeviceToken.user_id)))
        .filter(User.notify_new_matches | User.notify_deadlines)
        .all()
    )
    if not users:
        return []

    visible = _only_open(_apply_filters(db.query(Opportunity))).all()
    recent = [o for o in visible if o.created_at and o.created_at >= now - NEW_WINDOW]
    sent = {
        (row.user_id, row.opportunity_id, row.kind)
        for row in db.query(NotificationLog).filter(
            NotificationLog.user_id.in_([u.id for u in users])
        )
    }
    favorites: dict[int, set[int]] = {}
    for fav in db.query(FavoriteOpportunity).filter(
        FavoriteOpportunity.user_id.in_([u.id for u in users])
    ):
        favorites.setdefault(fav.user_id, set()).add(fav.opportunity_id)

    pushes: list[Push] = []
    for user in users:
        if user.notify_new_matches:
            new = []
            for opp in recent:
                if (user.id, opp.id, "new_match") in sent:
                    continue
                opp.match_percentage = compute_match_percentage(user, opp)
                if opp.match_percentage >= HIGH_MATCH_THRESHOLD:
                    new.append(opp)
            new.sort(key=lambda o: o.match_percentage, reverse=True)
            push = _new_matches_push(user, new)
            if push:
                pushes.append(push)

        if user.notify_deadlines:
            saved = favorites.get(user.id, set())
            soon, last = [], []
            for opp in visible:
                if opp.id not in saved or not opp.deadline:
                    continue
                days = (opp.deadline - today).days
                if days == 0 and (user.id, opp.id, "deadline_last") not in sent:
                    last.append(opp)
                elif 0 < days < URGENT_DEADLINE_DAYS and (user.id, opp.id, "deadline_soon") not in sent:
                    soon.append(opp)
            push = _deadlines_push(user, soon, last, today)
            if push:
                pushes.append(push)
    return pushes


# ── Envio (Firebase Admin) ───────────────────────────────────────────────

# Recebe (token, Push) e devolve "ok", "invalid" (aparelho não existe mais)
# ou "error". Trocável nos testes.
Sender = Callable[[str, Push], str]


def _firebase_sender() -> Optional[Sender]:
    """Sender real, ou None se a chave de serviço não estiver no servidor."""
    path = settings.firebase_credentials_file
    if not os.path.isfile(path):
        logger.warning(f"[Notificações] Chave do Firebase ausente ({path}); nada enviado.")
        return None

    import firebase_admin
    from firebase_admin import credentials, messaging

    if not firebase_admin._apps:
        firebase_admin.initialize_app(credentials.Certificate(path))

    def send(token: str, push: Push) -> str:
        message = messaging.Message(
            token=token,
            notification=messaging.Notification(title=push.title, body=push.body),
            data=push.data,
            android=messaging.AndroidConfig(priority="high"),
        )
        try:
            messaging.send(message)
            return "ok"
        except (messaging.UnregisteredError, messaging.SenderIdMismatchError):
            return "invalid"
        except Exception as exc:  # noqa: BLE001 — um aparelho com erro não para os outros
            logger.warning(f"[Notificações] Falha ao enviar: {exc}")
            return "error"

    return send


def send_daily_notifications(sender: Optional[Sender] = None, today: Optional[date] = None,
                             now: Optional[datetime] = None) -> dict:
    """Monta e envia as notificações do dia. Registra no NotificationLog o
    que foi entregue a ao menos um aparelho e apaga os aparelhos que o
    Firebase diz não existirem mais."""
    db = SessionLocal()
    try:
        pushes = build_daily_pushes(db, today=today, now=now)
        stats = {"pushes": len(pushes), "sent": 0, "failed": 0, "invalid_tokens": 0}
        if not pushes:
            return stats
        sender = sender or _firebase_sender()
        if sender is None:
            stats["failed"] = len(pushes)
            return stats

        tokens: dict[int, list[str]] = {}
        for row in db.query(DeviceToken).filter(
            DeviceToken.user_id.in_({p.user_id for p in pushes})
        ):
            tokens.setdefault(row.user_id, []).append(row.token)

        for push in pushes:
            delivered = False
            for token in tokens.get(push.user_id, []):
                result = sender(token, push)
                if result == "ok":
                    delivered = True
                elif result == "invalid":
                    db.query(DeviceToken).filter(DeviceToken.token == token).delete()
                    stats["invalid_tokens"] += 1
            if delivered:
                for opportunity_id, kind in push.logged:
                    db.add(NotificationLog(
                        user_id=push.user_id, opportunity_id=opportunity_id, kind=kind))
                stats["sent"] += 1
            else:
                stats["failed"] += 1
            db.commit()
        return stats
    finally:
        db.close()


async def run_daily_notifications() -> dict:
    """Job do agendador (09h)."""
    logger.info("[Notificações] Montando as notificações do dia...")
    stats = send_daily_notifications()
    logger.info(
        f"[Notificações] {stats['sent']} enviadas, {stats['failed']} sem entrega, "
        f"{stats['invalid_tokens']} aparelhos removidos"
    )
    return stats
