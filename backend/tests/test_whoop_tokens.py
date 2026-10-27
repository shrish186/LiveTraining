import threading
from datetime import timedelta

import pytest

from app.models import Athlete, WhoopToken, utcnow
from app.whoop import WhoopAuthError, WhoopRateLimited, needs_refresh


@pytest.fixture
def athlete_id(app, fake_whoop):
    """An athlete with stored tokens matching FakeWhoop's current valid tokens."""
    with app.state.db_factory() as db:
        athlete = Athlete(whoop_user_id=10129, first_name="Sam", last_name="Kerr")
        db.add(athlete)
        db.commit()
        db.add(WhoopToken(athlete_id=athlete.id, access_token="access-0", refresh_token="refresh-0",
                          expires_at=utcnow() + timedelta(hours=1)))
        db.commit()
        return athlete.id


def set_expiry(app, athlete_id, delta):
    with app.state.db_factory() as db:
        db.get(WhoopToken, athlete_id).expires_at = utcnow() + delta
        db.commit()


def stored(app, athlete_id) -> WhoopToken:
    with app.state.db_factory() as db:
        return db.get(WhoopToken, athlete_id)


def test_needs_refresh_margin():
    now = utcnow()
    assert needs_refresh(now + timedelta(seconds=59), now)
    assert needs_refresh(now + timedelta(seconds=60), now)
    assert not needs_refresh(now + timedelta(seconds=61), now)


def test_fresh_token_is_not_refreshed(app, fake_whoop, athlete_id):
    assert app.state.whoop.access_token(athlete_id) == "access-0"
    assert fake_whoop.refresh_count == 0


def test_expiring_token_is_refreshed_and_new_refresh_token_saved(app, fake_whoop, athlete_id):
    set_expiry(app, athlete_id, timedelta(seconds=30))
    assert app.state.whoop.access_token(athlete_id) == "access-1"
    token = stored(app, athlete_id)
    assert token.refresh_token == "refresh-1"  # old one is dead on WHOOP's side
    assert token.expires_at > utcnow() + timedelta(minutes=59)
    refresh = fake_whoop.requests[-1]
    assert b"grant_type=refresh_token" in refresh.content
    assert b"scope=offline" in refresh.content

    # And the next refresh uses the NEW refresh token.
    set_expiry(app, athlete_id, timedelta(seconds=0))
    assert app.state.whoop.access_token(athlete_id) == "access-2"
    assert fake_whoop.refresh_count == 2


def test_concurrent_refreshes_are_serialised(app, fake_whoop, athlete_id):
    set_expiry(app, athlete_id, timedelta(seconds=-5))
    fake_whoop.refresh_delay = 0.05  # widen the race window
    results, errors = [], []

    def worker():
        try:
            results.append(app.state.whoop.access_token(athlete_id))
        except Exception as exc:  # noqa: BLE001
            errors.append(exc)

    threads = [threading.Thread(target=worker) for _ in range(8)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert errors == []
    assert fake_whoop.refresh_count == 1
    assert results == ["access-1"] * 8


def test_rejected_refresh_token_means_reconnect(app, fake_whoop, athlete_id):
    set_expiry(app, athlete_id, timedelta(seconds=0))
    fake_whoop.valid_refresh_token = "something-else"
    with pytest.raises(WhoopAuthError):
        app.state.whoop.access_token(athlete_id)


def test_401_triggers_one_refresh_and_retry(app, fake_whoop, athlete_id):
    fake_whoop.reject_next_api_call = True
    records = app.state.whoop.get_collection(athlete_id, "/v2/recovery", limit=1)
    assert records[0]["cycle_id"] == 1
    assert fake_whoop.refresh_count == 1


def test_pagination_follows_next_token(app, fake_whoop, athlete_id):
    fake_whoop.recovery_pages = [[{"cycle_id": i}] for i in range(3)]
    records = app.state.whoop.get_collection(athlete_id, "/v2/recovery")
    assert [r["cycle_id"] for r in records] == [0, 1, 2]
    api_calls = [r for r in fake_whoop.requests if r.url.path.endswith("/v2/recovery")]
    assert api_calls[0].url.params["limit"] == "25"
    assert "nextToken" not in api_calls[0].url.params
    assert api_calls[1].url.params["nextToken"] == "1"


def test_rate_limit_raises(app, fake_whoop, athlete_id):
    fake_whoop.rate_limited = True
    with pytest.raises(WhoopRateLimited) as exc:
        app.state.whoop.get(athlete_id, "/v2/recovery")
    assert exc.value.retry_after == 17


def test_recovery_endpoints(client, fake_whoop, athlete_id):
    fake_whoop.recovery_pages = [[{
        "cycle_id": 93845, "sleep_id": "abc", "created_at": "2026-10-27T07:00:00Z", "score_state": "SCORED",
        "score": {"user_calibrating": False, "recovery_score": 44, "resting_heart_rate": 64,
                  "hrv_rmssd_milli": 31.8, "spo2_percentage": 95.6, "skin_temp_celsius": 33.7},
    }]]
    latest = client.get(f"/athletes/{athlete_id}/whoop/recovery/latest").json()
    assert latest["recovery_score"] == 44
    assert latest["hrv_rmssd_milli"] == 31.8
    assert latest["user_calibrating"] is False

    history = client.get(f"/athletes/{athlete_id}/whoop/recovery?days=14")
    assert history.status_code == 200
    assert len(history.json()) == 1
    assert "start" in fake_whoop.requests[-1].url.params
    assert client.get(f"/athletes/{athlete_id}/whoop/recovery?days=0").status_code == 422

    assert client.get(f"/athletes/{athlete_id}/whoop/sleep/latest").json()["id"] == "s1"


def test_latest_cycle(client, fake_whoop, athlete_id):
    assert client.get(f"/athletes/{athlete_id}/whoop/cycle/latest").status_code == 404
    fake_whoop.cycle_records = [{
        "id": 93845, "start": "2026-10-27T06:12:00Z", "end": None, "score_state": "SCORED",
        "score": {"strain": 9.4, "kilojoule": 7300.5, "average_heart_rate": 71, "max_heart_rate": 168},
    }]
    day = client.get(f"/athletes/{athlete_id}/whoop/cycle/latest").json()
    assert day == {"cycle_id": 93845, "start": "2026-10-27T06:12:00Z", "end": None, "score_state": "SCORED",
                   "strain": 9.4, "kilojoule": 7300.5, "average_heart_rate": 71, "max_heart_rate": 168}
    assert fake_whoop.requests[-1].url.params["limit"] == "1"


def test_endpoint_returns_429_with_retry_after(client, fake_whoop, athlete_id):
    fake_whoop.rate_limited = True
    r = client.get(f"/athletes/{athlete_id}/whoop/recovery/latest")
    assert r.status_code == 429
    assert r.headers["retry-after"] == "17"


def test_unknown_or_unconnected_athlete(client, app):
    assert client.get("/athletes/42/whoop/recovery/latest").status_code == 404
    with app.state.db_factory() as db:
        db.add(Athlete(whoop_user_id=5))
        db.commit()
    assert client.get("/athletes/1/whoop/recovery/latest").status_code == 401
