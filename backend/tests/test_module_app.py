import asyncio
import dataclasses

import httpx
from fastapi.testclient import TestClient

import app.main
from app.main import LazyApp, create_app


def test_module_exposes_app_for_uvicorn():
    """`uvicorn app.main:app` needs a module-level ASGI app."""
    assert hasattr(app.main, "app")
    assert callable(app.main.app)


def test_import_has_no_side_effects():
    assert app.main.app._app is None  # nothing built (no DB, no credential check) just by importing


def test_lazy_app_serves_requests(settings, fake_whoop):
    lazy = LazyApp(lambda: create_app(settings, transport=httpx.MockTransport(fake_whoop)))
    with TestClient(lazy) as client:  # runs lifespan startup
        assert client.get("/health").json() == {"status": "ok"}
        assert "Server is running." in client.get("/").text


async def run_lifespan(asgi_app) -> list[dict]:
    """Drives the ASGI lifespan the way uvicorn does and returns what the app sent."""
    incoming = [{"type": "lifespan.startup"}, {"type": "lifespan.shutdown"}]
    sent: list[dict] = []

    async def receive():
        return incoming.pop(0)

    async def send(message):
        sent.append(message)

    await asgi_app({"type": "lifespan", "asgi": {"version": "3.0"}}, receive, send)
    return sent


def test_lazy_app_reports_startup_failure_without_credentials(settings):
    lazy = LazyApp(lambda: create_app(dataclasses.replace(settings, whoop_client_secret="")))
    sent = asyncio.run(run_lifespan(lazy))
    assert sent[0]["type"] == "lifespan.startup.failed"
    assert "WHOOP_CLIENT_SECRET not set" in sent[0]["message"]


def test_lazy_app_lifespan_ok(settings, fake_whoop):
    lazy = LazyApp(lambda: create_app(settings, transport=httpx.MockTransport(fake_whoop)))
    sent = asyncio.run(run_lifespan(lazy))
    assert [m["type"] for m in sent] == ["lifespan.startup.complete", "lifespan.shutdown.complete"]
