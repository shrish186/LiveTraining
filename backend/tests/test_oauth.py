from datetime import timedelta
from urllib.parse import parse_qs, urlparse

from app.config import WHOOP_SCOPES
from app.models import Athlete, OAuthState, WhoopToken, utcnow
from app.whoop import new_state, state_is_fresh


def login_state(client) -> str:
    r = client.get("/auth/whoop/login")
    assert r.status_code == 302
    url = urlparse(r.headers["location"])
    assert f"{url.scheme}://{url.netloc}{url.path}" == "https://api.prod.whoop.com/oauth/oauth2/auth"
    query = parse_qs(url.query)
    assert query["scope"] == [WHOOP_SCOPES]
    assert query["client_id"] == ["client"]
    assert query["redirect_uri"] == ["http://localhost:8000/auth/whoop/callback"]
    assert query["response_type"] == ["code"]
    return query["state"][0]


def test_new_state_is_8_random_chars():
    states = {new_state() for _ in range(50)}
    assert len(states) == 50
    assert all(len(s) == 8 and s.isalnum() for s in states)


def test_state_freshness():
    now = utcnow()
    assert state_is_fresh(now - timedelta(minutes=9, seconds=59), now)
    assert not state_is_fresh(now - timedelta(minutes=10, seconds=1), now)


def test_login_stores_state(client, app):
    state = login_state(client)
    assert len(state) == 8
    with app.state.db_factory() as db:
        assert db.get(OAuthState, state) is not None


def test_callback_rejects_unknown_state(client):
    login_state(client)
    r = client.get("/auth/whoop/callback?code=good-code&state=WRONG123")
    assert r.status_code == 400
    assert "expired or invalid" in r.text


def test_callback_rejects_missing_state(client):
    assert client.get("/auth/whoop/callback?code=good-code").status_code == 400


def test_callback_rejects_expired_state(client, app):
    state = login_state(client)
    with app.state.db_factory() as db:
        db.get(OAuthState, state).created_at = utcnow() - timedelta(minutes=11)
        db.commit()
    assert client.get(f"/auth/whoop/callback?code=good-code&state={state}").status_code == 400


def test_callback_success_creates_athlete_and_tokens(client, app):
    state = login_state(client)
    r = client.get(f"/auth/whoop/callback?code=good-code&state={state}")
    assert r.status_code == 200, r.text
    assert "Connected as Sam Kerr." in r.text
    assert "Athlete ID: <code>1</code>" in r.text
    with app.state.db_factory() as db:
        athlete = db.get(Athlete, 1)
        assert athlete.whoop_user_id == 10129
        token = db.get(WhoopToken, 1)
        assert token.access_token == "access-0"
        assert token.refresh_token == "refresh-0"
        assert db.get(OAuthState, state) is None  # single use
    # State can't be replayed
    assert client.get(f"/auth/whoop/callback?code=good-code&state={state}").status_code == 400
    assert client.get("/athletes").json() == [
        {"id": 1, "name": "Sam Kerr", "whoop_user_id": 10129, "whoop_connected": True}
    ]


def test_reconnect_updates_same_athlete(client):
    for _ in range(2):
        state = login_state(client)
        assert client.get(f"/auth/whoop/callback?code=good-code&state={state}").status_code == 200
    assert len(client.get("/athletes").json()) == 1


def test_callback_shows_whoop_error(client):
    r = client.get("/auth/whoop/callback?error=access_denied&error_description=User+said+no")
    assert r.status_code == 400
    assert "User said no" in r.text


def test_login_without_credentials(settings, fake_whoop):
    import dataclasses

    import httpx
    from fastapi.testclient import TestClient

    from app.main import create_app

    app = create_app(dataclasses.replace(settings, whoop_client_id=""), transport=httpx.MockTransport(fake_whoop))
    r = TestClient(app, follow_redirects=False).get("/auth/whoop/login")
    assert r.status_code == 500
    assert "not configured" in r.text
