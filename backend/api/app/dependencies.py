from collections.abc import Iterator
from dataclasses import dataclass
from typing import Annotated, cast

from fastapi import Depends, Request
from sqlalchemy.orm import Session

from app.config import Settings
from app.db import Database
from app.services.storage import PhotoStorage
from app.services.verifier_client import VerifierClient


@dataclass
class Services:
    settings: Settings
    database: Database
    storage: PhotoStorage
    verifier: VerifierClient


def get_services(request: Request) -> Services:
    return cast(Services, request.app.state.services)


ServicesDep = Annotated[Services, Depends(get_services)]


def get_session(services: ServicesDep) -> Iterator[Session]:
    with services.database.sessions() as session:
        yield session


SessionDep = Annotated[Session, Depends(get_session)]
