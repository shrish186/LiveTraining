"""WHOOP official developer API client: OAuth 2.0 code exchange, token refresh, data fetches.

Token refresh rules (from WHOOP):
- every refresh INVALIDATES the previous access token and refresh token, so the new refresh token
  must always be saved;
- if two refreshes race, the second one fails. Refreshes are therefore serialised per athlete with
  a lock, and the token is re-read inside the lock before deciding to refresh.

The lock is in-process. Running several server processes would need a DB row lock
(SELECT ... FOR UPDATE on Postgres). See README "Decisions".
"""

import secrets
import string
import threading
from datetime import datetime, timedelta
from typing import Any
from urllib.parse import urlencode

import httpx
from sqlalchemy.orm import sessionmaker

from .config import WHOOP_API_BASE, WHOOP_AUTH_URL, WHOOP_SCOPES, WHOOP_TOKEN_URL, Settings
from .models import WhoopToken, utcnow

REFRESH_MARGIN = timedelta(seconds=60)
PAGE_LIMIT = 25  # WHOOP max for collection endpoints
MAX_PAGES = 20
STATE_LENGTH = 8
STATE_TTL = timedelta(minutes=10)


class WhoopError(Exception):
    status_code = 502


class WhoopAuthError(WhoopError):
    """The athlete has to reconnect WHOOP (no token, or refresh token rejected)."""

    status_code = 401


class WhoopRateLimited(WhoopError):
    status_code = 429

    def __init__(self, retry_after: int):
        super().__init__(f"WHOOP rate limit reached, retry in {retry_after}s")
        self.retry_after = retry_after


def new_state() -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(STATE_LENGTH))


def state_is_fresh(created_at: datetime, now: datetime | None = None) -> bool:
    return (now or utcnow()) - created_at <= STATE_TTL


def needs_refresh(expires_at: datetime, now: datetime | None = None) -> bool:
    return expires_at - (now or utcnow()) <= REFRESH_MARGIN


def _retry_after(response: httpx.Response) -> int:
    for header in ("Retry-After", "X-RateLimit-Reset"):
        value = response.headers.get(header)
        if value and value.strip().isdigit():
            return int(value)
    return 60


class WhoopClient:
    def __init__(self, settings: Settings, http: httpx.Client, db_factory: sessionmaker):
        self.settings = settings
        self.http = http
        self.db_factory = db_factory
        self._locks: dict[int, threading.Lock] = {}
        self._locks_guard = threading.Lock()

    # ---- OAuth -----------------------------------------------------------------

    def authorize_url(self, state: str) -> str:
        query = urlencode(
            {
                "response_type": "code",
                "client_id": self.settings.whoop_client_id,
                "redirect_uri": self.settings.whoop_redirect_uri,
                "scope": WHOOP_SCOPES,
                "state": state,
            }
        )
        return f"{WHOOP_AUTH_URL}?{query}"

    def exchange_code(self, code: str) -> dict[str, Any]:
        return self._token_request(
            {
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": self.settings.whoop_redirect_uri,
                "client_id": self.settings.whoop_client_id,
                "client_secret": self.settings.whoop_client_secret,
            }
        )

    def fetch_profile(self, access_token: str) -> dict[str, Any]:
        response = self._send("GET", "/v2/user/profile/basic", access_token)
        return self._json_or_raise(response)

    def save_tokens(self, athlete_id: int, token_response: dict[str, Any]) -> WhoopToken:
        with self.db_factory() as db:
            token = db.get(WhoopToken, athlete_id) or WhoopToken(athlete_id=athlete_id)
            self._apply_token_response(token, token_response)
            db.add(token)
            db.commit()
            return token

    # ---- tokens ----------------------------------------------------------------

    def _lock_for(self, athlete_id: int) -> threading.Lock:
        with self._locks_guard:
            return self._locks.setdefault(athlete_id, threading.Lock())

    def access_token(self, athlete_id: int, rejected_token: str | None = None) -> str:
        """Returns a usable access token, refreshing it if it expires within 60s.

        Pass `rejected_token` after a 401 to force a refresh, unless another thread already
        replaced that token.
        """
        with self.db_factory() as db:
            token = db.get(WhoopToken, athlete_id)
            if token is None:
                raise WhoopAuthError("WHOOP not connected for this athlete")
            if rejected_token is None and not needs_refresh(token.expires_at):
                return token.access_token

        with self._lock_for(athlete_id):
            with self.db_factory() as db:
                # Re-read inside the lock: another thread may have refreshed meanwhile.
                token = db.get(WhoopToken, athlete_id)
                if token is None:
                    raise WhoopAuthError("WHOOP not connected for this athlete")
                already_replaced = rejected_token is not None and token.access_token != rejected_token
                if already_replaced or (rejected_token is None and not needs_refresh(token.expires_at)):
                    return token.access_token
                if not token.refresh_token:
                    raise WhoopAuthError("no refresh token stored, reconnect WHOOP")
                data = self._token_request(
                    {
                        "grant_type": "refresh_token",
                        "refresh_token": token.refresh_token,
                        "client_id": self.settings.whoop_client_id,
                        "client_secret": self.settings.whoop_client_secret,
                        "scope": "offline",
                    }
                )
                self._apply_token_response(token, data)
                db.commit()  # the old refresh token is now dead: persist the new one immediately
                return token.access_token

    @staticmethod
    def _apply_token_response(token: WhoopToken, data: dict[str, Any]) -> None:
        token.access_token = data["access_token"]
        token.refresh_token = data.get("refresh_token") or token.refresh_token
        token.expires_at = utcnow() + timedelta(seconds=int(data.get("expires_in", 3600)))
        token.scope = data.get("scope", token.scope or "")

    def _token_request(self, form: dict[str, str]) -> dict[str, Any]:
        try:
            response = self.http.post(WHOOP_TOKEN_URL, data=form)
        except httpx.HTTPError as exc:
            raise WhoopError(f"could not reach WHOOP: {exc}") from exc
        if response.status_code == 429:
            raise WhoopRateLimited(_retry_after(response))
        if response.status_code in (400, 401, 403):
            raise WhoopAuthError("WHOOP rejected the token request, reconnect WHOOP")
        return self._json_or_raise(response)

    # ---- API -------------------------------------------------------------------

    def _send(self, method: str, path: str, access_token: str, params: dict | None = None) -> httpx.Response:
        try:
            return self.http.request(
                method,
                f"{WHOOP_API_BASE}{path}",
                params=params,
                headers={"Authorization": f"Bearer {access_token}"},
            )
        except httpx.HTTPError as exc:
            raise WhoopError(f"could not reach WHOOP: {exc}") from exc

    @staticmethod
    def _json_or_raise(response: httpx.Response) -> dict[str, Any]:
        if response.status_code == 429:
            raise WhoopRateLimited(_retry_after(response))
        if response.status_code == 401:
            raise WhoopAuthError("WHOOP rejected the access token")
        if response.status_code >= 400:
            raise WhoopError(f"WHOOP returned HTTP {response.status_code}")
        return response.json()

    def get(self, athlete_id: int, path: str, params: dict | None = None) -> dict[str, Any]:
        token = self.access_token(athlete_id)
        response = self._send("GET", path, token, params)
        if response.status_code == 401:
            # Token revoked or expired early: refresh once and retry.
            token = self.access_token(athlete_id, rejected_token=token)
            response = self._send("GET", path, token, params)
        return self._json_or_raise(response)

    def get_collection(
        self,
        athlete_id: int,
        path: str,
        start: datetime | None = None,
        end: datetime | None = None,
        limit: int | None = None,
    ) -> list[dict[str, Any]]:
        """Follows next_token until exhausted, `limit` records collected, or MAX_PAGES."""
        params: dict[str, Any] = {"limit": min(limit or PAGE_LIMIT, PAGE_LIMIT)}
        if start:
            params["start"] = start.isoformat(timespec="milliseconds") + "Z"
        if end:
            params["end"] = end.isoformat(timespec="milliseconds") + "Z"
        records: list[dict[str, Any]] = []
        for _ in range(MAX_PAGES):
            page = self.get(athlete_id, path, params)
            records.extend(page.get("records", []))
            next_token = page.get("next_token")
            if not next_token or (limit and len(records) >= limit):
                break
            params["nextToken"] = next_token
        return records[:limit] if limit else records
