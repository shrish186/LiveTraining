import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

BACKEND_DIR = Path(__file__).resolve().parent.parent

WHOOP_AUTH_URL = "https://api.prod.whoop.com/oauth/oauth2/auth"
WHOOP_TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token"
WHOOP_API_BASE = "https://api.prod.whoop.com/developer"
WHOOP_SCOPES = "offline read:recovery read:cycles read:sleep read:workout read:profile read:body_measurement"


@dataclass(frozen=True)
class Settings:
    whoop_client_id: str = ""
    whoop_client_secret: str = ""
    whoop_redirect_uri: str = "http://localhost:8000/auth/whoop/callback"
    database_url: str = "sqlite:///./data/live_training.db"
    data_dir: Path = Path("./data")

    @classmethod
    def from_env(cls) -> "Settings":
        load_dotenv(BACKEND_DIR / ".env")
        defaults = cls()
        return cls(
            whoop_client_id=os.getenv("WHOOP_CLIENT_ID", ""),
            whoop_client_secret=os.getenv("WHOOP_CLIENT_SECRET", ""),
            whoop_redirect_uri=os.getenv("WHOOP_REDIRECT_URI", defaults.whoop_redirect_uri),
            database_url=os.getenv("DATABASE_URL", defaults.database_url),
            data_dir=Path(os.getenv("DATA_DIR", str(defaults.data_dir))),
        )
