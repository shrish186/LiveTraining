import json
import threading
import time
from urllib.parse import parse_qs

import httpx
import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app

GOOD_CSV = """t_ms,source,kind,x,y,z,value
0,phone,event,,,,session_start
4,phone,acc,0.1214,9.7902,0.3311,
5,phone,gyro,0.0012,-0.0031,0.0004,
14,phone,acc,0.1301,9.8012,0.3254,
812,whoop_hr,hr,,,,72
812,whoop_hr,rr,,,,833.98
1800,whoop_hr,hr,,,,151
15032,phone,event,,,,sync_jumps
"""


def make_metadata(**overrides):
    meta = {
        "format_version": 1,
        "session_id": "4f6c2b0e-3f7a-4d2f-9f0e-6a1f5d2b7c11",
        "athlete_id": None,
        "sport": "soccer",
        "session_type": "training",
        "started_at": "2026-10-27T18:02:11Z",
        "app_version": "0.1.0",
        "device_model": "test",
        "sources": [{"id": "phone", "kinds": ["acc", "gyro"], "sample_rate_hz": 100}],
        "placement": "phone_armband",
        "notes": "",
    }
    meta.update(overrides)
    return meta


class FakeWhoop:
    """Stands in for WHOOP's OAuth and API servers behind httpx.MockTransport."""

    def __init__(self):
        self.refresh_count = 0
        self.valid_refresh_token = "refresh-0"
        self.valid_access_token = "access-0"
        self.expires_in = 3600
        self.refresh_delay = 0.0
        self.rate_limited = False
        self.reject_next_api_call = False
        self.recovery_pages = [[{"cycle_id": 1, "score_state": "SCORED", "score": {"recovery_score": 66}}]]
        self.cycle_records: list[dict] = []
        self.requests: list[httpx.Request] = []
        self._lock = threading.Lock()

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        if self.rate_limited:
            return httpx.Response(429, headers={"Retry-After": "17"})
        if request.url.path == "/oauth/oauth2/token":
            return self._token(parse_qs(request.content.decode()))
        auth = request.headers.get("Authorization", "")
        if self.reject_next_api_call or auth != f"Bearer {self.valid_access_token}":
            self.reject_next_api_call = False
            return httpx.Response(401)
        path = request.url.path.removeprefix("/developer")
        if path == "/v2/user/profile/basic":
            return httpx.Response(200, json={"user_id": 10129, "email": "a@b.c", "first_name": "Sam", "last_name": "Kerr"})
        if path == "/v2/recovery":
            token = request.url.params.get("nextToken")
            index = int(token) if token else 0
            next_token = str(index + 1) if index + 1 < len(self.recovery_pages) else None
            return httpx.Response(200, json={"records": self.recovery_pages[index], "next_token": next_token})
        if path == "/v2/cycle":
            return httpx.Response(200, json={"records": self.cycle_records, "next_token": None})
        if path == "/v2/activity/sleep":
            return httpx.Response(200, json={"records": [{"id": "s1", "score_state": "SCORED"}], "next_token": None})
        return httpx.Response(404)

    def _token(self, form: dict[str, list[str]]) -> httpx.Response:
        grant = form["grant_type"][0]
        if grant == "authorization_code":
            if form["code"][0] != "good-code":
                return httpx.Response(400, json={"error": "invalid_grant"})
            return httpx.Response(200, json=self._issue())
        if grant == "refresh_token":
            assert form["scope"] == ["offline"]
            assert form["client_secret"] == ["secret"]
            if self.refresh_delay:
                time.sleep(self.refresh_delay)
            with self._lock:
                if form["refresh_token"][0] != self.valid_refresh_token:
                    # WHOOP: an already-used refresh token is invalid
                    return httpx.Response(400, json={"error": "invalid_grant"})
                self.refresh_count += 1
                return httpx.Response(200, json=self._issue())
        return httpx.Response(400)

    def _issue(self) -> dict:
        n = self.refresh_count
        self.valid_access_token = f"access-{n}"
        self.valid_refresh_token = f"refresh-{n}"
        return {
            "access_token": self.valid_access_token,
            "refresh_token": self.valid_refresh_token,
            "expires_in": self.expires_in,
            "scope": "offline read:recovery",
            "token_type": "bearer",
        }


@pytest.fixture
def fake_whoop():
    return FakeWhoop()


@pytest.fixture
def settings(tmp_path):
    return Settings(
        whoop_client_id="client",
        whoop_client_secret="secret",
        whoop_redirect_uri="http://localhost:8000/auth/whoop/callback",
        database_url=f"sqlite:///{tmp_path / 'test.db'}",
        data_dir=tmp_path / "data",
    )


@pytest.fixture
def app(settings, fake_whoop):
    return create_app(settings, transport=httpx.MockTransport(fake_whoop))


@pytest.fixture
def client(app):
    return TestClient(app, follow_redirects=False)


def upload(client, csv_text=GOOD_CSV, meta=None):
    return client.post(
        "/sessions",
        files={"file": ("s.csv", csv_text.encode(), "text/csv")},
        data={"metadata": json.dumps(meta or make_metadata())},
    )
