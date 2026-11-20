"""Bootstrap accounts without passwords in process arguments or logs."""

import argparse
import getpass
import sys

from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError

from app.config import Settings
from app.db import Database
from app.models import AuthEvent, StaffUser
from app.security import hash_password, valid_username


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["create-admin"])
    parser.add_argument("--username", default="admin")
    args = parser.parse_args(argv)
    if not valid_username(args.username):
        print("Invalid username (3–64 lowercase ASCII characters).", file=sys.stderr)
        return 2
    if sys.stdin.isatty():
        password = getpass.getpass("Password (12–1024 characters): ")
        confirmation = getpass.getpass("Confirm password: ")
        if password != confirmation:
            print("Passwords do not match.", file=sys.stderr)
            return 2
    else:
        # Bound input; strip only the line delimiter, never password whitespace.
        password = sys.stdin.readline(1026).removesuffix("\n").removesuffix("\r")
    try:
        password_hash = hash_password(password)
    except ValueError:
        print("Password must contain 12–1024 characters.", file=sys.stderr)
        return 2
    database = Database(Settings().database_url)
    try:
        with database.sessions() as session:
            if session.scalar(
                select(StaffUser.id).where(StaffUser.username == args.username)
            ):
                print("Username already exists; no account changed.", file=sys.stderr)
                return 2
            session.add(
                StaffUser(
                    username=args.username, password_hash=password_hash, role="admin"
                )
            )
            session.add(
                AuthEvent(
                    actor="system",
                    actor_role="system",
                    action="admin_bootstrap",
                    target=args.username,
                )
            )
            session.commit()
    except SQLAlchemyError:
        print(
            "Account creation failed; check database configuration and migrations.",
            file=sys.stderr,
        )
        return 1
    finally:
        database.engine.dispose()
    print("Admin account created.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
