import argparse
from contextlib import closing
import getpass
from pathlib import Path
import sqlite3
import time
from uuid import uuid4

from sqlalchemy import insert, select, update
from sqlalchemy.engine import make_url

from .auth import password_hasher
from .config import Settings
from .db import create_database_engine, migrate, transaction
from .models import accounts, devices


def validate_database(connection):
    if connection.execute('PRAGMA integrity_check').fetchall() != [('ok',)]:
        raise ValueError('Database integrity check failed')
    if connection.execute('PRAGMA foreign_key_check').fetchall():
        raise ValueError('Database foreign key check failed')
    if connection.execute('SELECT version_num FROM alembic_version').fetchall() != [('0001',)]:
        raise ValueError('Unsupported database schema revision')
    expected = {'accounts', 'devices', 'tokens', 'login_attempts', 'vault_metadata', 'items', 'operations', 'alembic_version'}
    tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    if tables != expected:
        raise ValueError('Invalid database schema')


def copy_database(source, target, revoke_sessions=False):
    source, target = Path(source).resolve(), Path(target).resolve()
    if not source.is_file():
        raise ValueError('Source database does not exist')
    if target.exists():
        raise ValueError('Target already exists; choose a new path')
    created = False
    try:
        with closing(sqlite3.connect(source.as_uri() + '?mode=ro', uri=True)) as original:
            validate_database(original)
            # Exclusive file creation also protects against races with another restore.
            with target.open('xb'):
                created = True
            with closing(sqlite3.connect(target)) as destination:
                original.backup(destination)
                validate_database(destination)
                if revoke_sessions:
                    destination.execute('UPDATE devices SET revoked=1')
                    destination.commit()
                    validate_database(destination)
    except (sqlite3.Error, OSError, ValueError) as error:
        if created:
            target.unlink(missing_ok=True)
        raise ValueError(f'Database copy failed: {error}') from error


def backup_database(settings, target):
    url = make_url(settings.database_url)
    if url.drivername != 'sqlite' or not url.database or url.database == ':memory:':
        raise ValueError('Backup requires a persistent SQLite database')
    copy_database(url.database, target)


def restore_database(source, target):
    copy_database(source, target, revoke_sessions=True)


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
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ['create-account', 'reset-password']:
        commands.add_parser(name).add_argument('username')
    commands.add_parser('backup').add_argument('target', type=Path)
    restore = commands.add_parser('restore', help='Offline restore to a NEW database path; stop the API first')
    restore.add_argument('source', type=Path)
    restore.add_argument('target', type=Path)
    args = parser.parse_args()
    if args.command in ['backup', 'restore']:
        try:
            if args.command == 'backup':
                backup_database(Settings(), args.target)
            else:
                restore_database(args.source, args.target)
        except ValueError as error:
            parser.error(str(error))
        print('Backup verified.' if args.command == 'backup' else 'Restore verified; all sessions revoked.')
        return
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
