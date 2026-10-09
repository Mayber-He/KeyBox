from pathlib import Path

from fastapi.testclient import TestClient
from sqlalchemy import inspect, text

from keybox_backend.app import create_app
from keybox_backend.config import Settings
from keybox_backend.db import create_database_engine, migrate


def test_health(tmp_path):
    settings = Settings(database_url=f"sqlite:///{tmp_path / 'app.db'}")
    with TestClient(create_app(settings)) as client:
        assert client.get('/healthz').json() == {'status': 'ok'}


def test_migration_creates_persistent_schema(tmp_path):
    settings = Settings(database_url=f"sqlite:///{tmp_path / 'app.db'}")
    migrate(settings)
    engine = create_database_engine(settings)
    assert set(inspect(engine).get_table_names()) == {
        'alembic_version', 'accounts', 'devices', 'tokens', 'login_attempts',
        'vault_metadata', 'items', 'operations',
    }
    with engine.connect() as connection:
        assert connection.execute(text('PRAGMA journal_mode')).scalar() == 'wal'
        assert connection.execute(text('PRAGMA foreign_keys')).scalar() == 1
    engine.dispose()
    migrate(settings)


def test_configuration_from_environment(monkeypatch):
    monkeypatch.setenv('KEYBOX_DATABASE_URL', 'sqlite:///custom.db')
    assert Settings().database_url == 'sqlite:///custom.db'


def test_rejects_oversized_chunked_request(tmp_path):
    settings = Settings(database_url=f"sqlite:///{tmp_path / 'app.db'}", max_body_bytes=10)
    with TestClient(create_app(settings)) as client:
        response = client.post('/anything', content=iter([b'123456', b'78901']))
        assert response.status_code == 413
