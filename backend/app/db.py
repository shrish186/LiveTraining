from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.engine import Engine
from sqlalchemy.orm import sessionmaker

from .models import Base


def make_engine(database_url: str) -> Engine:
    kwargs = {}
    if database_url.startswith("sqlite"):
        # FastAPI runs sync routes in a thread pool.
        kwargs["connect_args"] = {"check_same_thread": False}
        path = database_url.split("///", 1)[-1]
        if path and path != ":memory:":
            Path(path).parent.mkdir(parents=True, exist_ok=True)
    return create_engine(database_url, **kwargs)


def make_sessionmaker(engine: Engine) -> sessionmaker:
    # No Alembic yet: create tables on startup (see README "Decisions").
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, expire_on_commit=False)
