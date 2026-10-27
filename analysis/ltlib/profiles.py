"""Sport profiles: profiles/sport_profiles.yaml, each profile deep-merged over `general`."""

import copy
from pathlib import Path
from typing import Any

import yaml

DEFAULT_PROFILES_PATH = Path(__file__).resolve().parents[2] / "profiles" / "sport_profiles.yaml"
BASE_PROFILE = "general"


def deep_merge(base: dict, override: dict) -> dict:
    out = copy.deepcopy(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = deep_merge(out[key], value)
        else:
            out[key] = copy.deepcopy(value)
    return out


def load_profiles(path: str | Path = DEFAULT_PROFILES_PATH) -> dict[str, dict[str, Any]]:
    raw = yaml.safe_load(Path(path).read_text())["profiles"]
    base = raw[BASE_PROFILE]
    return {name: (base if name == BASE_PROFILE else deep_merge(base, body or {})) | {"name": name}
            for name, body in raw.items()}


def get_profile(name: str | None, path: str | Path = DEFAULT_PROFILES_PATH) -> dict[str, Any]:
    profiles = load_profiles(path)
    name = name or BASE_PROFILE
    if name not in profiles:
        raise KeyError(f"unknown sport profile {name!r}; available: {', '.join(sorted(profiles))}")
    return profiles[name]


def effort_params(profile: dict[str, Any], placement: str | None) -> dict[str, Any]:
    """Effort settings for one placement: the profile's `effort` block plus any placement override."""
    params = dict(profile["effort"])
    params.update((profile.get("placements") or {}).get(placement or "", {}) or {})
    return params
