"""Staff response allowlists; wire schemas remain compatible with existing clients."""

from typing import Annotated, TypedDict

from pydantic import Field, SecretStr

from app.schemas import StrictModel
from app.security import USERNAME_PATTERN, StaffRole


class StaffIdentityOut(TypedDict):
    username: str
    role: str


class IdentityOut(TypedDict):
    user: StaffIdentityOut


class UserOut(StaffIdentityOut):
    id: str
    disabled: bool


class UserListOut(TypedDict):
    items: list[UserOut]


Username = Annotated[str, Field(pattern=f"^{USERNAME_PATTERN}$")]


class LoginIn(StrictModel):
    username: Annotated[str, Field(min_length=1, max_length=64)]
    password: Annotated[SecretStr, Field(min_length=1, max_length=1024)]


class CreateUserIn(StrictModel):
    username: Username
    password: Annotated[SecretStr, Field(min_length=12, max_length=1024)]
    role: StaffRole


class UpdateUserIn(StrictModel):
    disabled: bool | None = None
    password: Annotated[SecretStr | None, Field(min_length=12, max_length=1024)] = None
    role: StaffRole | None = None
