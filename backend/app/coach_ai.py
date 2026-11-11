"""AI coach: answers an athlete's questions about their own training data with Claude.

The phone sends a compact summary of its sessions (built on the device from the session summaries
and reports) plus the question; the server adds the instructions and calls the Claude API, so the API
key stays on the server. Wording follows the product's hard rule: fatigue, readiness, load. Never
injury prediction or a medical claim.
"""

import json
from dataclasses import dataclass
from typing import Any, Protocol

import anthropic

MODEL = "claude-opus-5-5"
MAX_QUESTION_CHARS = 2000
MAX_CONTEXT_CHARS = 60_000
MAX_HISTORY_TURNS = 12

SYSTEM_PROMPT = """You are the coach inside Live Training, an app for athletes who train with a leg-worn motion \
sensor (above the ankle). Many users are cricket fast bowlers; others sprint or play field sports.

You get the athlete's own data as JSON: recent sessions (sport, duration, training load, efforts, deliveries, \
footstrikes, impact load, hardest hit in g, landing drift between the first and last deliveries, data quality), \
daily and weekly totals, and sometimes one session in detail. Answer their question from that data.

How to answer:
- Be specific: quote the numbers you are using (dates, counts, percentages) so the athlete can check them.
- Give a clear recommendation they can act on in their next session or week, then one line on why.
- Keep it short: a few sentences or a short list. No preamble.
- If the data can't answer the question (too few sessions, poor data quality, no sensor data), say so and say \
what to record to answer it next time.
- Training load language only: talk about load, fatigue, readiness, effort, recovery and technique consistency. \
Never predict or diagnose injuries and never make medical claims. If the athlete mentions pain or an injury, \
tell them to stop and see a physiotherapist or doctor, and don't give treatment advice.
- Load figures are this app's own units (motion load, impact load in g); compare them with the athlete's own \
history, not with outside norms."""


class CoachUnavailable(RuntimeError):
    """The server has no Claude API key configured."""


class CoachError(RuntimeError):
    """Claude could not answer (declined, cut off, or the API failed)."""


class MessagesClient(Protocol):
    """The slice of anthropic.Anthropic().beta that the coach uses (tests pass a fake)."""

    @property
    def messages(self) -> Any: ...


@dataclass
class CoachAnswer:
    answer: str
    model: str


def build_messages(question: str, context: dict[str, Any], history: list[dict[str, str]]) -> list[dict[str, Any]]:
    """Earlier turns as plain text, then the athlete's data and the new question in one user message."""
    question = question.strip()
    if not question:
        raise ValueError("question is empty")
    if len(question) > MAX_QUESTION_CHARS:
        raise ValueError(f"question is longer than {MAX_QUESTION_CHARS} characters")
    data = json.dumps(context, sort_keys=True, separators=(",", ":"))
    if len(data) > MAX_CONTEXT_CHARS:
        raise ValueError("training data summary is too large")
    turns = [t for t in history if t.get("role") in ("user", "assistant") and str(t.get("content", "")).strip()]
    turns = turns[-MAX_HISTORY_TURNS:]
    while turns and turns[0]["role"] != "user":  # the conversation must start with the athlete
        turns = turns[1:]
    messages: list[dict[str, Any]] = [{"role": t["role"], "content": str(t["content"])} for t in turns]
    if messages and messages[-1]["role"] == "user":  # two user turns in a row: drop the unanswered one
        messages.pop()
    messages.append({
        "role": "user",
        "content": f"<training_data>\n{data}\n</training_data>\n\n{question}",
    })
    return messages


def ask(client: MessagesClient | None, question: str, context: dict[str, Any],
        history: list[dict[str, str]] | None = None) -> CoachAnswer:
    """One coach answer. Raises ValueError for bad input, CoachUnavailable, or CoachError."""
    if client is None:
        raise CoachUnavailable("The AI coach is not set up on this server: add ANTHROPIC_API_KEY to backend/.env.")
    messages = build_messages(question, context, history or [])
    try:
        response = client.messages.create(
            model=MODEL,
            max_tokens=16000,
            system=SYSTEM_PROMPT,
            output_config={"effort": "medium"},
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
            messages=messages,
        )
    except anthropic.RateLimitError as e:
        raise CoachError("The AI coach is busy. Try again in a minute.") from e
    except anthropic.APIStatusError as e:
        raise CoachError(f"The AI coach failed (error {e.status_code}). Try again later.") from e
    except anthropic.APIConnectionError as e:
        raise CoachError("The server can't reach the AI coach. Check its internet connection.") from e
    if response.stop_reason == "refusal":
        raise CoachError("The coach can't answer that one. Try asking about your training data.")
    text = "".join(block.text for block in response.content if block.type == "text").strip()
    if not text:
        raise CoachError("The coach gave no answer. Try asking again.")
    if response.stop_reason == "max_tokens":
        text += "\n\n(Answer cut short.)"
    return CoachAnswer(text, response.model)
