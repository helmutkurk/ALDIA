from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.pool import StaticPool


class Base(DeclarativeBase):
    pass


class Database:
    def __init__(self, url: str) -> None:
        if url.startswith("sqlite"):
            self.engine: Engine = create_engine(
                url,
                connect_args={"check_same_thread": False},
                **(
                    {"poolclass": StaticPool}
                    if url in {"sqlite://", "sqlite:///:memory:"}
                    else {}
                ),
            )
        else:
            self.engine = create_engine(url, pool_pre_ping=True, hide_parameters=True)
        self.sessions = sessionmaker(
            self.engine, class_=Session, expire_on_commit=False
        )
