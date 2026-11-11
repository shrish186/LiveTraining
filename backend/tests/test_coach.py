"""AI coach endpoint. Never calls the real Claude API: a fake client records the request."""

import dataclasses
from types import SimpleNamespace

import anthropic
import httpx
import pytest
from fastapi.testclient import TestClient

from app import coach_ai
from app.main import create_app


class FakeMessages:
    def __init__(self, reply: str = "Cut the spell at 5 overs.", stop_reason: str = "end_turn", error=None):
        self.reply, self.stop_reason, self.error = reply, stop_reason, error
        self.calls: list[dict] = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        return SimpleNamespace(
            content=[SimpleNamespace(type="thinking", thinking=""), SimpleNamespace(type="text", text=self.reply)],
            stop_reason=self.stop_reason,
            model=coach_ai.MODEL,
        )


def make_client(settings, fake: FakeMessages | None):
    app = create_app(settings, coach_client=SimpleNamespace(messages=fake) if fake else None)
    return TestClient(app)


CONTEXT = {"sport": "cricket", "sessions": [{"date": "2026-11-10", "deliveries": 36, "landing_drift_pct": -14}]}


def test_answers_with_the_athletes_data(settings):
    fake = FakeMessages()
    r = make_client(settings, fake).post("/coach/ask", json={
        "question": "How long should my next spell be?",
        "context": CONTEXT,
        "history": [{"role": "user", "content": "Hi"}, {"role": "assistant", "content": "Hello"}],
    })
    assert r.status_code == 200
    assert r.json() == {"answer": "Cut the spell at 5 overs.", "model": coach_ai.MODEL}
    call = fake.calls[0]
    assert call["model"] == "claude-opus-5-5"
    assert call["fallbacks"] == "default" and call["betas"] == ["server-side-fallback-2026-07-01"]
    assert "Never predict or diagnose injuries" in call["system"]
    msgs = call["messages"]
    assert [m["role"] for m in msgs] == ["user", "assistant", "user"]
    assert '"deliveries":36' in msgs[-1]["content"] and msgs[-1]["content"].endswith("How long should my next spell be?")


def test_off_without_a_key(settings, monkeypatch):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)  # a key in the developer's shell would turn it on
    client = make_client(settings, None)
    assert client.get("/coach").json()["available"] is False
    r = client.post("/coach/ask", json={"question": "Hi", "context": {}})
    assert r.status_code == 503 and "ANTHROPIC_API_KEY" in r.json()["detail"]


@pytest.mark.parametrize("body", [{"question": "  ", "context": {}}, {"question": 3}, {"question": "x" * 2001}])
def test_rejects_bad_questions(settings, body):
    assert make_client(settings, FakeMessages()).post("/coach/ask", json=body).status_code == 422


def test_refusal_and_api_errors_become_502(settings):
    r = make_client(settings, FakeMessages(reply="", stop_reason="refusal")).post(
        "/coach/ask", json={"question": "?", "context": {}})
    assert r.status_code == 502 and "can't answer" in r.json()["detail"]
    request = httpx.Request("POST", "https://api.anthropic.com/v1/messages")
    err = anthropic.RateLimitError("slow down", response=httpx.Response(429, request=request), body=None)
    r = make_client(settings, FakeMessages(error=err)).post("/coach/ask", json={"question": "?", "context": {}})
    assert r.status_code == 502 and "busy" in r.json()["detail"]


def test_history_is_trimmed_and_starts_with_the_athlete():
    history = [{"role": "assistant", "content": "orphan"}] + [
        {"role": r, "content": f"{r} {i}"} for i in range(20) for r in ("user", "assistant")
    ] + [{"role": "user", "content": "unanswered"}]
    msgs = coach_ai.build_messages("next?", {}, history)
    assert msgs[0]["role"] == "user" and msgs[-1]["content"].endswith("next?")
    assert all(a["role"] != b["role"] for a, b in zip(msgs, msgs[1:]))
    assert len(msgs) <= coach_ai.MAX_HISTORY_TURNS + 1


def test_runs_without_whoop(settings):
    no_whoop = dataclasses.replace(settings, whoop_client_id="", whoop_client_secret="")
    client = TestClient(create_app(no_whoop))
    assert client.get("/health").status_code == 200
    assert client.get("/auth/whoop/login", follow_redirects=False).status_code == 503
    assert client.get("/athletes/1/whoop/recovery/latest").status_code == 503
