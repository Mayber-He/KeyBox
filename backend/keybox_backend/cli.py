import argparse
import getpass
import time
from uuid import uuid4

from sqlalchemy import insert, select, update

from .auth import password_hasher
from .config import Settings
from .db import create_database_engine, migrate, transaction
from .models import accounts, devices


def validate_credentials(username, password):
    if not username or username != username.strip() or len(username) > 128:
        raise ValueError('Username must be 1 to 128 characters without surrounding spaces')
    if len(password) < 12 or len(password) > 1024:
        raise ValueError('Password must be 12 to 1024 characters')


def create_account(settings, username, password):
    validate_credentials(username, password)
    encoded = password_hasher.hash(password)
    migrate(settings)
    engine = create_database_engine(settings)
    try:
        with transaction(engine) as connection:
            if connection.execute(select(accounts.c.id)).first():
                raise ValueError('A personal account already exists')
            connection.execute(insert(accounts).values(id=str(uuid4()), username=username,
                password_hash=encoded, created_at=int(time.time())))
    finally:
        engine.dispose()


def reset_password(settings, username, password):
    validate_credentials(username, password)
    encoded = password_hasher.hash(password)
    migrate(settings)
    engine = create_database_engine(settings)
    try:
        with transaction(engine) as connection:
            account_id = connection.execute(select(accounts.c.id).where(accounts.c.username == username)).scalar()
            if account_id is None:
                raise ValueError('Account does not exist')
            connection.execute(update(accounts).where(accounts.c.id == account_id).values(password_hash=encoded))
            connection.execute(update(devices).where(devices.c.account_id == account_id).values(revoked=True))
    finally:
        engine.dispose()


def main():
    parser = argparse.ArgumentParser(description='KeyBox account administration')
    parser.add_argument('command', choices=['create-account', 'reset-password'])
    parser.add_argument('username')
    args = parser.parse_args()
    password = getpass.getpass('Password: ')
    if password != getpass.getpass('Confirm password: '):
        parser.error('Passwords do not match')
    try:
        action = create_account if args.command == 'create-account' else reset_password
        action(Settings(), args.username, password)
    except ValueError as error:
        parser.error(str(error))
    print('Account created.' if args.command == 'create-account' else 'Password reset; all sessions revoked.')


if __name__ == '__main__':
    main()
