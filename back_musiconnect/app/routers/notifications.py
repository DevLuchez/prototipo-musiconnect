"""
Router de notificações — aparelho que recebe e chaves do Perfil.

Endpoints:
  PUT /api/notifications/device       — registra o aparelho (identificador do FCM)
  PUT /api/notifications/preferences  — chaves "Novas para você", "Prazos dos
                                        favoritos" e "Novas versões do app"

O "Sair" (POST /api/auth/logout) apaga o aparelho; excluir a conta também
(ON DELETE CASCADE). O envio diário fica em services/notifications.py.
"""

from fastapi import APIRouter, Depends, Response
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import DeviceToken, User
from app.routers.auth import get_current_user
from app.schemas import DeviceTokenIn, NotificationPreferencesIn, UserOut

router = APIRouter(prefix="/api/notifications", tags=["notifications"])


@router.put("/device", status_code=204)
def register_device(
    data: DeviceTokenIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Registra o aparelho em que a pessoa está conectada. Idempotente.

    A sessão é uma só por conta (entrar em outro celular derruba a
    anterior), então o aparelho novo substitui os antigos da conta. E o
    mesmo aparelho só pertence a uma conta: num celular compartilhado, ele
    passa para quem entrou por último.

    O app pode registrar o mesmo aparelho duas vezes quase juntas (logo
    depois do login): o ON CONFLICT faz a segunda só confirmar a primeira.
    """
    db.query(DeviceToken).filter(
        DeviceToken.user_id == user.id, DeviceToken.token != data.token
    ).delete(synchronize_session=False)
    db.execute(
        insert(DeviceToken)
        .values(token=data.token, user_id=user.id, app_version=data.app_version)
        .on_conflict_do_update(
            index_elements=[DeviceToken.token],
            set_={"user_id": user.id, "app_version": data.app_version},
        )
    )
    db.commit()
    return Response(status_code=204)


@router.put("/preferences", response_model=UserOut)
def update_preferences(
    data: NotificationPreferencesIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Liga/desliga cada tipo de notificação (chaves do Perfil)."""
    user.notify_new_matches = data.notify_new_matches
    user.notify_deadlines = data.notify_deadlines
    if data.notify_app_updates is not None:
        user.notify_app_updates = data.notify_app_updates
    db.commit()
    return user
