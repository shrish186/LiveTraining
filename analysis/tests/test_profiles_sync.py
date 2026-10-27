from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_app_copy_of_profiles_matches():
    """The app bundles profiles for offline live calls. Keep it identical to the source of truth:
    cp profiles/sport_profiles.yaml mobile/assets/sport_profiles.yaml"""
    source = (ROOT / "profiles" / "sport_profiles.yaml").read_bytes()
    app_copy = (ROOT / "mobile" / "assets" / "sport_profiles.yaml").read_bytes()
    assert app_copy == source, "mobile/assets/sport_profiles.yaml is out of date; copy profiles/sport_profiles.yaml over it"
