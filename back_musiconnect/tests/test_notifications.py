"""
Notificações: registro do aparelho, chaves do Perfil e envio diário
(novas com match alto + prazos dos favoritos).
"""

from datetime import date, datetime, timedelta, timezone

import pytest

from app.models import DeviceToken, FavoriteOpportunity, NotificationLog
from app.services import notifications as notif
from tests.helpers import auth_headers, make_opportunity, make_user

# Datas reais: a visibilidade (prazo vigente) usa a data de hoje do banco.
HOJE = date.today()
AGORA = datetime.now(timezone.utc).replace(tzinfo=None)


@pytest.fixture(autouse=True)
def _same_session(monkeypatch, db_session):
    monkeypatch.setattr(notif, "SessionLocal", lambda: db_session)
    # db_session é fechada pelo envio; o fixture continua usando a conexão.
    monkeypatch.setattr(db_session, "close", lambda: None)


def _device(db, user, token="aparelho-1"):
    db.add(DeviceToken(token=token, user_id=user.id))
    db.commit()


def _opp(db, **fields):
    data = {"created_at": AGORA - timedelta(hours=3), "deadline": HOJE + timedelta(days=30)}
    data.update(fields)
    return make_opportunity(db, **data)


def _favorite(db, user, opp):
    db.add(FavoriteOpportunity(user_id=user.id, opportunity_id=opp.id))
    db.commit()


class _Sender:
    def __init__(self, result="ok"):
        self.result = result
        self.sent = []

    def __call__(self, token, push):
        self.sent.append((token, push))
        return self.result(token) if callable(self.result) else self.result


def _send(sender):
    return notif.send_daily_notifications(sender=sender, today=HOJE, now=AGORA)


# ── Rotas ────────────────────────────────────────────────────────────────

def test_registrar_aparelho_substitui_o_anterior_e_passa_de_conta(api, db_session):
    ana = make_user(db_session, email="ana@example.com")
    bia = make_user(db_session, email="bia@example.com")
    h_ana = auth_headers(db_session, ana, token="t-ana")
    h_bia = auth_headers(db_session, bia, token="t-bia")

    assert api.put("/api/notifications/device", json={"token": "cel-1"}, headers=h_ana).status_code == 204
    api.put("/api/notifications/device", json={"token": "cel-2"}, headers=h_ana)
    api.put("/api/notifications/device", json={"token": "cel-2"}, headers=h_ana)  # idempotente
    assert [(d.token, d.user_id) for d in db_session.query(DeviceToken)] == [("cel-2", ana.id)]

    # Celular compartilhado: o aparelho passa para quem entrou por último.
    api.put("/api/notifications/device", json={"token": "cel-2"}, headers=h_bia)
    assert [(d.token, d.user_id) for d in db_session.query(DeviceToken)] == [("cel-2", bia.id)]


def test_registro_simultaneo_do_mesmo_aparelho_nao_da_erro(api, db_session):
    # Depois do login o app registra o aparelho duas vezes quase juntas; a
    # outra requisição grava o token no meio desta (erro 500 em 04/11/2026).
    from sqlalchemy import event, text

    user = make_user(db_session)
    headers = auth_headers(db_session, user)

    @event.listens_for(db_session, "after_bulk_delete", once=True)
    def _outra_requisicao(_):
        db_session.execute(
            text("INSERT INTO device_tokens (token, user_id) VALUES ('cel-1', :u)"),
            {"u": user.id},
        )

    assert api.put("/api/notifications/device", json={"token": "cel-1"}, headers=headers).status_code == 204
    assert [(d.token, d.user_id) for d in db_session.query(DeviceToken)] == [("cel-1", user.id)]


def test_registrar_aparelho_exige_login(api):
    assert api.put("/api/notifications/device", json={"token": "x"}).status_code == 401


def test_sair_para_as_notificacoes_do_aparelho(api, db_session):
    user = make_user(db_session)
    headers = auth_headers(db_session, user)
    api.put("/api/notifications/device", json={"token": "cel-1"}, headers=headers)

    api.post("/api/auth/logout", headers=headers)

    assert db_session.query(DeviceToken).count() == 0


def test_excluir_conta_apaga_o_aparelho_e_o_historico(api, db_session):
    user = make_user(db_session)
    headers = auth_headers(db_session, user)
    opp = _opp(db_session)
    _device(db_session, user)
    db_session.add(NotificationLog(user_id=user.id, opportunity_id=opp.id, kind="new_match"))
    db_session.commit()

    api.request("DELETE", "/api/auth/me", json={"password": "Senha#123"}, headers=headers)

    assert db_session.query(DeviceToken).count() == 0
    assert db_session.query(NotificationLog).count() == 0


def test_chaves_do_perfil(api, db_session):
    headers = auth_headers(db_session, make_user(db_session))
    assert api.get("/api/auth/me", headers=headers).json()["notify_new_matches"] is True

    body = api.put("/api/notifications/preferences", headers=headers,
                   json={"notify_new_matches": False, "notify_deadlines": True}).json()

    assert body["notify_new_matches"] is False and body["notify_deadlines"] is True
    me = api.get("/api/auth/me", headers=headers).json()
    assert me["notify_new_matches"] is False and me["notify_deadlines"] is True


# ── Novas para você ──────────────────────────────────────────────────────

def test_uma_nova_com_match_alto_abre_a_oportunidade(db_session):
    user = make_user(db_session)
    _device(db_session, user)
    opp = _opp(db_session, title="Audição de Violino")
    _opp(db_session, title="Outro instrumento", instruments=["Tuba"])  # match baixo

    sender = _Sender()
    stats = _send(sender)

    assert stats["sent"] == 1
    token, push = sender.sent[0]
    assert token == "aparelho-1"
    assert push.title == "Nova oportunidade para você"
    assert push.body.startswith("Audição de Violino · ") and push.body.endswith("% de match")
    assert push.data == {"open": "opportunity", "opportunity_id": str(opp.id)}


def test_varias_novas_viram_uma_notificacao_que_abre_minhas_oportunidades(db_session):
    _device(db_session, make_user(db_session))
    for t in ("A", "B", "C"):
        _opp(db_session, title=t)

    sender = _Sender()
    _send(sender)

    assert len(sender.sent) == 1
    push = sender.sent[0][1]
    assert push.title == "3 novas oportunidades para você"
    assert push.body == "Com 85% ou mais de match. Toque para ver."
    assert push.data == {"open": "matches"}


def test_nova_nao_e_avisada_duas_vezes_nem_a_antiga(db_session):
    _device(db_session, make_user(db_session))
    _opp(db_session, title="Nova")
    _opp(db_session, title="Antiga", created_at=AGORA - timedelta(days=10))

    _send(_Sender())
    sender = _Sender()
    stats = _send(sender)

    assert sender.sent == [] and stats["pushes"] == 0


def test_sem_aparelho_ou_com_a_chave_desligada_nao_recebe(db_session):
    make_user(db_session, email="sem@example.com")
    desligada = make_user(db_session, email="desligada@example.com", notify_new_matches=False)
    _device(db_session, desligada)
    _opp(db_session)

    sender = _Sender()
    _send(sender)

    assert sender.sent == []


def test_oportunidade_escondida_nao_e_avisada(db_session):
    _device(db_session, make_user(db_session))
    _opp(db_session, title="Baixa confiança", llm_confidence=0.5)
    _opp(db_session, title="Vencida", deadline=HOJE - timedelta(days=1))

    sender = _Sender()
    _send(sender)

    assert [p.title for _, p in sender.sent] == []


# ── Prazos dos favoritos ────────────────────────────────────────────────

def test_favorita_perto_do_prazo_avisa_os_dias_que_faltam(db_session):
    user = make_user(db_session, notify_new_matches=False)
    _device(db_session, user)
    _favorite(db_session, user, _opp(db_session, title="Bolsa de Harpa", deadline=HOJE + timedelta(days=3)))
    _favorite(db_session, user, _opp(db_session, title="Longe", deadline=HOJE + timedelta(days=20)))

    sender = _Sender()
    _send(sender)

    push = sender.sent[0][1]
    assert push.title == "O prazo está acabando"
    assert push.body == "Faltam 3 dias para se inscrever em: Bolsa de Harpa"


def test_um_dia_no_singular(db_session):
    user = make_user(db_session, notify_new_matches=False)
    _device(db_session, user)
    _favorite(db_session, user, _opp(db_session, title="X", deadline=HOJE + timedelta(days=1)))

    sender = _Sender()
    _send(sender)

    assert sender.sent[0][1].body == "Falta 1 dia para se inscrever em: X"


def test_ultimo_dia_e_avisado_mesmo_depois_do_aviso_de_prazo(db_session):
    user = make_user(db_session, notify_new_matches=False)
    _device(db_session, user)
    opp = _opp(db_session, title="Bolsa de Harpa", deadline=HOJE)
    _favorite(db_session, user, opp)
    db_session.add(NotificationLog(user_id=user.id, opportunity_id=opp.id, kind="deadline_soon"))
    db_session.commit()

    sender = _Sender()
    _send(sender)
    again = _Sender()
    _send(again)

    push = sender.sent[0][1]
    assert push.title == "Último dia!"
    assert push.body == "As inscrições de Bolsa de Harpa fecham hoje."
    assert push.data == {"open": "opportunity", "opportunity_id": str(opp.id)}
    assert again.sent == []


def test_varias_favoritas_viram_uma_notificacao_que_abre_os_favoritos(db_session):
    user = make_user(db_session, notify_new_matches=False)
    _device(db_session, user)
    for days in (0, 2):
        _favorite(db_session, user, _opp(db_session, title=f"F{days}", deadline=HOJE + timedelta(days=days)))

    sender = _Sender()
    _send(sender)

    push = sender.sent[0][1]
    assert push.title == "2 favoritas com prazo acabando"
    assert push.data == {"open": "favorites"}


def test_novas_e_prazos_no_mesmo_dia_sao_duas_notificacoes(db_session):
    user = make_user(db_session)
    _device(db_session, user)
    _favorite(db_session, user, _opp(db_session, title="Favorita", deadline=HOJE + timedelta(days=2),
                                     created_at=AGORA - timedelta(days=10)))
    _opp(db_session, title="Nova")

    sender = _Sender()
    _send(sender)

    assert sorted(p.title for _, p in sender.sent) == [
        "Nova oportunidade para você", "O prazo está acabando"]


# ── Envio ────────────────────────────────────────────────────────────────

def test_aparelho_que_nao_existe_mais_e_apagado_e_nada_e_registrado(db_session):
    _device(db_session, make_user(db_session))
    _opp(db_session)

    stats = _send(_Sender("invalid"))

    assert stats == {"pushes": 1, "sent": 0, "failed": 1, "invalid_tokens": 1}
    assert db_session.query(DeviceToken).count() == 0
    assert db_session.query(NotificationLog).count() == 0


def test_erro_no_envio_deixa_para_tentar_de_novo(db_session):
    _device(db_session, make_user(db_session))
    _opp(db_session)

    _send(_Sender("error"))
    sender = _Sender()
    _send(sender)

    assert len(sender.sent) == 1


def test_sem_chave_do_firebase_nao_envia(db_session, monkeypatch, tmp_path):
    monkeypatch.setattr(notif.settings, "firebase_credentials_file", str(tmp_path / "nao-existe.json"))
    _device(db_session, make_user(db_session))
    _opp(db_session)

    stats = notif.send_daily_notifications(today=HOJE, now=AGORA)

    assert stats["sent"] == 0 and stats["failed"] == 1
    assert db_session.query(NotificationLog).count() == 0


def test_sem_ninguem_para_avisar_nem_procura_a_chave(db_session, monkeypatch):
    monkeypatch.setattr(notif, "_firebase_sender", lambda: pytest.fail("não devia montar o envio"))

    assert notif.send_daily_notifications(today=HOJE, now=AGORA)["pushes"] == 0


def test_job_do_agendador(db_session, monkeypatch):
    monkeypatch.setattr(notif, "send_daily_notifications",
                        lambda: {"pushes": 0, "sent": 0, "failed": 0, "invalid_tokens": 0})
    import asyncio
    assert asyncio.run(notif.run_daily_notifications())["sent"] == 0


def test_envio_real_pelo_firebase_admin(db_session, monkeypatch, tmp_path):
    """O sender de verdade monta a mensagem do FCM e traduz os erros."""
    import firebase_admin
    from firebase_admin import credentials, messaging

    key = tmp_path / "chave.json"
    key.write_text("{}")
    monkeypatch.setattr(notif.settings, "firebase_credentials_file", str(key))
    monkeypatch.setattr(firebase_admin, "_apps", {})
    monkeypatch.setattr(credentials, "Certificate", lambda path: path)
    monkeypatch.setattr(firebase_admin, "initialize_app", lambda cred: firebase_admin._apps.update(x=1))

    sent = []

    def fake_send(message):
        if message.token == "sumiu":
            raise messaging.UnregisteredError("app desinstalado")
        if message.token == "falha":
            raise RuntimeError("fora do ar")
        sent.append(message)

    monkeypatch.setattr(messaging, "send", fake_send)
    sender = notif._firebase_sender()
    push = notif.Push(user_id=1, title="T", body="B", data={"open": "matches"})

    assert sender("ok", push) == "ok"
    assert sender("sumiu", push) == "invalid"
    assert sender("falha", push) == "error"
    assert sent[0].notification.title == "T" and sent[0].data == {"open": "matches"}
