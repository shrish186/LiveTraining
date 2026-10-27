import html
import json
import shutil
import tempfile
from datetime import timedelta
from pathlib import Path
from typing import Any

import httpx
from fastapi import Depends, FastAPI, File, Form, HTTPException, Query, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, RedirectResponse
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from .config import Settings
from .db import make_engine, make_sessionmaker
from .models import Athlete, OAuthState, TrainingSession, WhoopToken, utcnow
from .session_format import SessionFormatError, parse_started_at, validate_and_summarize, validate_metadata
from .whoop import STATE_TTL, WhoopClient, WhoopError, WhoopRateLimited, new_state, state_is_fresh

MAX_RECOVERY_DAYS = 90


def recovery_view(record: dict[str, Any]) -> dict[str, Any]:
    """Flattens a WHOOP v2 recovery record into the fields the app needs."""
    score = record.get("score") or {}
    return {
        "cycle_id": record.get("cycle_id"),
        "sleep_id": record.get("sleep_id"),
        "created_at": record.get("created_at"),
        "score_state": record.get("score_state"),
        "recovery_score": score.get("recovery_score"),
        "resting_heart_rate": score.get("resting_heart_rate"),
        "hrv_rmssd_milli": score.get("hrv_rmssd_milli"),
        "spo2_percentage": score.get("spo2_percentage"),
        "skin_temp_celsius": score.get("skin_temp_celsius"),
        "user_calibrating": score.get("user_calibrating"),
    }


def session_view(s: TrainingSession, full: bool = False) -> dict[str, Any]:
    view = {
        "id": s.id,
        "athlete_id": s.athlete_id,
        "sport": s.sport,
        "session_type": s.session_type,
        "placement": s.placement,
        "started_at": s.started_at.isoformat() + "Z",
        "duration_ms": s.duration_ms,
        "sample_count": s.sample_count,
        "sources": s.sources,
        "hr_min": s.hr_min,
        "hr_max": s.hr_max,
        "event_count": len(s.events),
        "uploaded_at": s.uploaded_at.isoformat() + "Z",
    }
    if full:
        view["events"] = s.events
        view["metadata"] = s.metadata_json
    return view


def _page(title: str, body: str, status: int = 200) -> HTMLResponse:
    return HTMLResponse(
        f"<!doctype html><html><head><meta charset='utf-8'>"
        f"<meta name='viewport' content='width=device-width, initial-scale=1'>"
        f"<title>{html.escape(title)}</title>"
        f"<style>body{{font-family:system-ui,sans-serif;max-width:32rem;margin:3rem auto;padding:0 1rem;line-height:1.5}}"
        f"code{{font-size:1.4rem;background:#eee;padding:.1rem .4rem;border-radius:4px}}</style></head>"
        f"<body>{body}</body></html>",
        status_code=status,
    )


def create_app(settings: Settings | None = None, transport: httpx.BaseTransport | None = None) -> FastAPI:
    """App factory. Tests pass their own Settings and an httpx.MockTransport."""
    settings = settings or Settings.from_env()
    sessions_dir = settings.data_dir / "sessions"
    sessions_dir.mkdir(parents=True, exist_ok=True)
    db_factory = make_sessionmaker(make_engine(settings.database_url))
    whoop = WhoopClient(settings, httpx.Client(transport=transport, timeout=20.0), db_factory)

    app = FastAPI(title="Live Training Intelligence")
    app.state.db_factory = db_factory
    app.state.whoop = whoop

    def get_db():
        with db_factory() as db:
            yield db

    def require_athlete(athlete_id: int, db: Session) -> Athlete:
        athlete = db.get(Athlete, athlete_id)
        if athlete is None:
            raise HTTPException(404, "athlete not found")
        return athlete

    @app.exception_handler(WhoopError)
    def whoop_error(_: Request, exc: WhoopError):
        headers = {"Retry-After": str(exc.retry_after)} if isinstance(exc, WhoopRateLimited) else None
        return JSONResponse({"detail": str(exc)}, status_code=exc.status_code, headers=headers)

    @app.get("/health")
    def health():
        return {"status": "ok"}

    # ---- WHOOP OAuth -------------------------------------------------------

    @app.get("/auth/whoop/login")
    def whoop_login(db: Session = Depends(get_db)):
        if not settings.whoop_client_id or not settings.whoop_client_secret:
            return _page("Not configured", "<h1>WHOOP not configured</h1><p>Set WHOOP_CLIENT_ID and "
                         "WHOOP_CLIENT_SECRET in backend/.env and restart the server.</p>", 500)
        db.execute(delete(OAuthState).where(OAuthState.created_at < utcnow() - STATE_TTL))
        state = new_state()
        db.add(OAuthState(state=state))
        db.commit()
        return RedirectResponse(whoop.authorize_url(state), status_code=302)

    @app.get("/auth/whoop/callback")
    def whoop_callback(
        code: str | None = None,
        state: str | None = None,
        error: str | None = None,
        error_description: str | None = None,
        db: Session = Depends(get_db),
    ):
        if error:
            msg = html.escape(error_description or error)
            return _page("WHOOP error", f"<h1>WHOOP connection failed</h1><p>{msg}</p>", 400)
        stored = db.get(OAuthState, state) if state else None
        if stored is None or not state_is_fresh(stored.created_at):
            if stored:
                db.delete(stored)
                db.commit()
            return _page("Invalid state", "<h1>Link expired or invalid</h1>"
                         "<p><a href='/auth/whoop/login'>Start again</a>.</p>", 400)
        db.delete(stored)  # single use
        db.commit()
        if not code:
            return _page("Missing code", "<h1>WHOOP did not return a code</h1>", 400)

        tokens = whoop.exchange_code(code)
        profile = whoop.fetch_profile(tokens["access_token"])
        athlete = db.scalar(select(Athlete).where(Athlete.whoop_user_id == profile["user_id"]))
        if athlete is None:
            athlete = Athlete(whoop_user_id=profile["user_id"])
            db.add(athlete)
        athlete.first_name = profile.get("first_name", "")
        athlete.last_name = profile.get("last_name", "")
        db.commit()
        whoop.save_tokens(athlete.id, tokens)

        name = html.escape(athlete.name or "WHOOP member")
        return _page("Connected", f"<h1>Connected as {name}.</h1><p>Athlete ID: <code>{athlete.id}</code></p>"
                     "<p>Enter this ID in the app under Settings.</p>")

    # ---- athletes and WHOOP data -----------------------------------------

    @app.get("/athletes")
    def list_athletes(db: Session = Depends(get_db)):
        connected = set(db.scalars(select(WhoopToken.athlete_id)))
        return [
            {"id": a.id, "name": a.name, "whoop_user_id": a.whoop_user_id, "whoop_connected": a.id in connected}
            for a in db.scalars(select(Athlete).order_by(Athlete.id))
        ]

    @app.get("/athletes/{athlete_id}/whoop/recovery/latest")
    def latest_recovery(athlete_id: int, db: Session = Depends(get_db)):
        require_athlete(athlete_id, db)
        records = whoop.get_collection(athlete_id, "/v2/recovery", limit=1)
        if not records:
            raise HTTPException(404, "no recovery yet")
        return recovery_view(records[0])

    @app.get("/athletes/{athlete_id}/whoop/recovery")
    def recovery_history(athlete_id: int, days: int = Query(14, ge=1, le=MAX_RECOVERY_DAYS),
                         db: Session = Depends(get_db)):
        require_athlete(athlete_id, db)
        records = whoop.get_collection(athlete_id, "/v2/recovery", start=utcnow() - timedelta(days=days))
        return [recovery_view(r) for r in records]

    @app.get("/athletes/{athlete_id}/whoop/sleep/latest")
    def latest_sleep(athlete_id: int, db: Session = Depends(get_db)):
        require_athlete(athlete_id, db)
        records = whoop.get_collection(athlete_id, "/v2/activity/sleep", limit=1)
        if not records:
            raise HTTPException(404, "no sleep yet")
        return records[0]

    # ---- sessions --------------------------------------------------------------

    @app.post("/sessions", status_code=201)
    def upload_session(file: UploadFile = File(...), metadata: str = Form(...), db: Session = Depends(get_db)):
        try:
            meta = validate_metadata(json.loads(metadata))
        except json.JSONDecodeError:
            raise HTTPException(422, {"errors": ["metadata is not valid JSON"]})
        except SessionFormatError as exc:
            raise HTTPException(422, {"errors": exc.errors})

        session_id = meta["session_id"]
        if db.get(TrainingSession, session_id):
            raise HTTPException(409, "session already uploaded")
        if meta.get("athlete_id") is not None and db.get(Athlete, meta["athlete_id"]) is None:
            raise HTTPException(422, {"errors": [f"unknown athlete_id {meta['athlete_id']}"]})

        # Copy to a temp file first, then validate by streaming, never the whole file in memory.
        with tempfile.NamedTemporaryFile("wb", dir=sessions_dir, suffix=".part", delete=False) as tmp:
            shutil.copyfileobj(file.file, tmp)
            tmp_path = Path(tmp.name)
        try:
            with open(tmp_path, newline="", encoding="utf-8") as f:
                summary = validate_and_summarize(f)
        except (SessionFormatError, UnicodeDecodeError) as exc:
            tmp_path.unlink(missing_ok=True)
            errors = exc.errors if isinstance(exc, SessionFormatError) else ["file is not UTF-8 text"]
            raise HTTPException(422, {"errors": errors})

        csv_path = (sessions_dir / f"{session_id}.csv").resolve()
        tmp_path.replace(csv_path)
        (sessions_dir / f"{session_id}.json").write_text(json.dumps(meta, indent=2))

        row = TrainingSession(
            id=session_id,
            athlete_id=meta.get("athlete_id"),
            sport=meta["sport"],
            session_type=meta["session_type"],
            placement=meta.get("placement"),
            started_at=parse_started_at(meta["started_at"]),
            duration_ms=summary.duration_ms,
            sample_count=summary.sample_count,
            sources=summary.sources,
            hr_min=summary.hr_min,
            hr_max=summary.hr_max,
            events=summary.events,
            metadata_json=meta,
            csv_path=str(csv_path),
        )
        db.add(row)
        db.commit()
        return session_view(row, full=True)

    @app.get("/sessions")
    def list_sessions(athlete_id: int | None = None, sport: str | None = None, db: Session = Depends(get_db)):
        query = select(TrainingSession).order_by(TrainingSession.started_at.desc())
        if athlete_id is not None:
            query = query.where(TrainingSession.athlete_id == athlete_id)
        if sport:
            query = query.where(TrainingSession.sport == sport)
        return [session_view(s) for s in db.scalars(query)]

    def _get_session(session_id: str, db: Session) -> TrainingSession:
        s = db.get(TrainingSession, session_id)
        if s is None:
            raise HTTPException(404, "session not found")
        return s

    @app.get("/sessions/{session_id}")
    def get_session(session_id: str, db: Session = Depends(get_db)):
        return session_view(_get_session(session_id, db), full=True)

    @app.get("/sessions/{session_id}/csv")
    def get_session_csv(session_id: str, db: Session = Depends(get_db)):
        s = _get_session(session_id, db)
        return FileResponse(s.csv_path, media_type="text/csv", filename=f"{s.id}.csv")

    return app

