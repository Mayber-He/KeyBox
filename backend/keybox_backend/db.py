from contextlib import contextmanager
from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, event

from .config import Settings


def create_database_engine(settings: Settings):
    if not settings.database_url.startswith('sqlite:///'):
        raise ValueError('Only SQLite databases are supported')
    engine = create_engine(settings.database_url, connect_args={'check_same_thread': False, 'timeout': 30})

    @event.listens_for(engine, 'connect')
    def configure_sqlite(dbapi_connection, _):
        dbapi_connection.execute('PRAGMA foreign_keys=ON')
        dbapi_connection.execute('PRAGMA journal_mode=WAL')
        dbapi_connection.execute('PRAGMA busy_timeout=30000')

    return engine


def migrate(settings: Settings):
    config = Config()
    config.set_main_option('script_location', str(Path(__file__).resolve().parent.parent / 'migrations'))
    engine = create_database_engine(settings)
    try:
        with engine.begin() as connection:
            config.attributes['connection'] = connection
            command.upgrade(config, 'head')
    finally:
        engine.dispose()


@contextmanager
def transaction(engine):
    with engine.connect() as connection:
        connection.exec_driver_sql('BEGIN IMMEDIATE')
        try:
            yield connection
            connection.commit()
        except BaseException:
            connection.rollback()
            raise
