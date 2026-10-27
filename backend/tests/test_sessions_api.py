from app.models import Athlete
from tests.conftest import GOOD_CSV, make_metadata, upload


def add_athlete(app) -> int:
    with app.state.db_factory() as db:
        athlete = Athlete(whoop_user_id=1, first_name="Sam", last_name="Kerr")
        db.add(athlete)
        db.commit()
        return athlete.id


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_upload_list_get_download(client, settings):
    r = upload(client)
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["id"] == "4f6c2b0e-3f7a-4d2f-9f0e-6a1f5d2b7c11"
    assert body["sport"] == "soccer"
    assert body["placement"] == "phone_armband"
    assert body["duration_ms"] == 15032
    assert body["sample_count"] == 6
    assert body["sources"] == ["phone", "whoop_hr"]
    assert (body["hr_min"], body["hr_max"]) == (72, 151)
    assert [e["label"] for e in body["events"]] == ["session_start", "sync_jumps"]

    sessions_dir = settings.data_dir / "sessions"
    assert (sessions_dir / f"{body['id']}.csv").read_text() == GOOD_CSV
    assert (sessions_dir / f"{body['id']}.json").exists()
    assert not list(sessions_dir.glob("*.part"))

    listing = client.get("/sessions").json()
    assert [s["id"] for s in listing] == [body["id"]]
    assert client.get(f"/sessions/{body['id']}").json()["metadata"]["notes"] == ""

    csv = client.get(f"/sessions/{body['id']}/csv")
    assert csv.status_code == 200
    assert csv.headers["content-type"].startswith("text/csv")
    assert csv.text == GOOD_CSV


def test_filters(client, app):
    athlete_id = add_athlete(app)
    upload(client, meta=make_metadata(session_id="00000000-0000-0000-0000-000000000001", sport="soccer",
                                      athlete_id=athlete_id))
    upload(client, meta=make_metadata(session_id="00000000-0000-0000-0000-000000000002", sport="running",
                                      started_at="2026-10-28T08:00:00Z"))
    assert [s["sport"] for s in client.get("/sessions").json()] == ["running", "soccer"]  # newest first
    assert [s["sport"] for s in client.get("/sessions?sport=running").json()] == ["running"]
    assert [s["sport"] for s in client.get(f"/sessions?athlete_id={athlete_id}").json()] == ["soccer"]


def test_bad_csv_rejected_and_not_stored(client, settings):
    r = upload(client, csv_text="t_ms,source,kind,x,y,z,value\n0,phone,acc,1,,3,\n")
    assert r.status_code == 422
    assert "line 2" in r.json()["detail"]["errors"][0]
    assert client.get("/sessions").json() == []
    assert list((settings.data_dir / "sessions").iterdir()) == []


def test_bad_metadata_rejected(client):
    r = client.post("/sessions", files={"file": ("s.csv", GOOD_CSV.encode())}, data={"metadata": "{not json"})
    assert r.status_code == 422
    r = upload(client, meta=make_metadata(sport=""))
    assert r.status_code == 422


def test_unknown_athlete_rejected(client):
    assert upload(client, meta=make_metadata(athlete_id=999)).status_code == 422


def test_duplicate_upload_conflicts(client):
    assert upload(client).status_code == 201
    assert upload(client).status_code == 409


def test_missing_session_404(client):
    assert client.get("/sessions/nope").status_code == 404
    assert client.get("/sessions/nope/csv").status_code == 404
