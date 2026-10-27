from app.main import lan_ip
from app.models import Athlete, WhoopToken, utcnow


def test_index_without_athletes(client, settings):
    r = client.get("/")
    assert r.status_code == 200
    assert "Server is running." in r.text
    assert "WHOOP credentials configured: <b>yes</b>" in r.text
    assert 'href="/auth/whoop/login"' in r.text
    assert "No athletes yet" in r.text
    assert settings.whoop_client_secret not in r.text
    assert settings.whoop_client_id not in r.text


def test_index_lists_athletes_with_ids(client, app):
    with app.state.db_factory() as db:
        a = Athlete(whoop_user_id=1, first_name="Sam", last_name="<Kerr>")
        b = Athlete(whoop_user_id=2, first_name="Alex", last_name="Morgan")
        db.add_all([a, b])
        db.commit()
        db.add(WhoopToken(athlete_id=a.id, access_token="t", refresh_token="r", expires_at=utcnow()))
        db.commit()
    r = client.get("/")
    assert "<td><code>1</code></td><td>Sam &lt;Kerr&gt;</td><td>yes</td>" in r.text
    assert "<td><code>2</code></td><td>Alex Morgan</td><td>no, reconnect</td>" in r.text


def test_lan_ip_is_not_loopback():
    ip = lan_ip()
    assert ip is None or not ip.startswith("127.")
