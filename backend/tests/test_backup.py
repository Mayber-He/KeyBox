import json
import sqlite3

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import insert, select

from keybox_backend.app import create_app
from keybox_backend.cli import backup_database, create_account, restore_database
from keybox_backend.config import Settings
from keybox_backend.models import devices, items, vault_metadata


def test_backup_restores_data_and_revokes_sessions(tmp_path):
    settings=Settings(database_url=f"sqlite:///{tmp_path/'source.db'}")
    create_account(settings,'owner','correct horse battery staple')
    with TestClient(create_app(settings)) as client:
        token=client.post('/api/v1/auth/login',json={'username':'owner','password':'correct horse battery staple','device_name':'phone'}).json()['access_token']
        with client.app.state.engine.begin() as connection:
            account_id=connection.execute(select(devices.c.account_id)).scalar()
            connection.execute(insert(vault_metadata).values(account_id=account_id,version=3,payload=json.dumps({'encrypted':'metadata'})))
            connection.execute(insert(items).values(account_id=account_id,id='item',version=4,deleted=True,payload=None,updated_at=1))
        backup=tmp_path/'backup.db'
        backup_database(settings,backup)
    target=tmp_path/'restored.db'
    restore_database(backup,target)
    restored=Settings(database_url=f'sqlite:///{target}')
    with TestClient(create_app(restored)) as client:
        assert client.get('/api/v1/devices',headers={'Authorization':'Bearer '+token}).status_code==401
        with client.app.state.engine.connect() as connection:
            assert connection.execute(select(vault_metadata.c.version)).scalar()==3
            assert connection.execute(select(items.c.deleted)).scalar() is True
            assert connection.execute(select(devices.c.revoked)).scalar() is True


def test_backup_and_restore_refuse_overwrite(tmp_path):
    settings=Settings(database_url=f"sqlite:///{tmp_path/'source.db'}")
    create_account(settings,'owner','correct horse battery staple')
    target=tmp_path/'existing.db'
    target.write_bytes(b'keep this')
    with pytest.raises(ValueError):
        backup_database(settings,target)
    with pytest.raises(ValueError):
        restore_database(tmp_path/'source.db',target)
    assert target.read_bytes()==b'keep this'


def test_restore_rejects_corrupt_or_unknown_schema(tmp_path):
    source=tmp_path/'bad.db'
    source.write_bytes(b'not SQLite')
    target=tmp_path/'target.db'
    with pytest.raises(ValueError):
        restore_database(source,target)
    assert not target.exists()
    source.unlink()
    with sqlite3.connect(source) as connection:
        connection.execute('CREATE TABLE alembic_version(version_num TEXT)')
        connection.execute("INSERT INTO alembic_version VALUES ('future')")
    with pytest.raises(ValueError):
        restore_database(source,target)
    assert not target.exists()


def test_backup_missing_source_does_not_create_database(tmp_path):
    source=tmp_path/'missing.db'
    with pytest.raises(ValueError):
        backup_database(Settings(database_url=f'sqlite:///{source}'),tmp_path/'backup.db')
    assert not source.exists()


def test_backup_rejects_foreign_key_damage(tmp_path):
    source=tmp_path/'source.db'
    settings=Settings(database_url=f'sqlite:///{source}')
    create_account(settings,'owner','correct horse battery staple')
    connection=sqlite3.connect(source)
    try:
        connection.execute("INSERT INTO devices VALUES ('orphan','missing','phone',1,1,0)")
        connection.commit()
    finally:
        connection.close()
    target=tmp_path/'backup.db'
    with pytest.raises(ValueError):
        backup_database(settings,target)
    assert not target.exists()


def test_backup_cli_subcommand_keeps_password_off_command_line(tmp_path,monkeypatch):
    from keybox_backend import cli
    source=tmp_path/'source.db'
    create_account(Settings(database_url=f'sqlite:///{source}'),'owner','correct horse battery staple')
    target=tmp_path/'backup.db'
    monkeypatch.setenv('KEYBOX_DATABASE_URL',f'sqlite:///{source}')
    monkeypatch.setattr('sys.argv',['keybox','backup',str(target)])
    cli.main()
    assert target.is_file()
