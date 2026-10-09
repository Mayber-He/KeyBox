import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select, update
from keybox_backend.app import create_app
from keybox_backend.config import Settings
from keybox_backend.cli import create_account, reset_password
from keybox_backend.models import accounts, tokens


@pytest.fixture
def client(tmp_path):
    settings = Settings(database_url=f"sqlite:///{tmp_path / 'app.db'}")
    create_account(settings, 'owner', 'correct horse battery staple')
    with TestClient(create_app(settings)) as client:
        yield client


def login(client):
    response = client.post('/api/v1/auth/login', json={'username':'owner','password':'correct horse battery staple','device_name':'phone'})
    assert response.status_code == 200
    return response.json()


def bearer(token):
    return {'Authorization':f"Bearer {token}"}


def test_login_hashes_secrets_and_lists_devices(client):
    result = login(client)
    with client.app.state.engine.connect() as connection:
        assert connection.execute(select(accounts.c.password_hash)).scalar().startswith('$argon2id$')
        hashes = connection.execute(select(tokens.c.hash)).scalars().all()
        assert result['access_token'] not in hashes and result['refresh_token'] not in hashes
    devices = client.get('/api/v1/devices', headers=bearer(result['access_token'])).json()
    assert devices[0]['id'] == result['device_id']
    assert devices[0]['name'] == 'phone'


def test_refresh_rotates_and_replay_revokes_family(client):
    first = login(client)
    second = client.post('/api/v1/auth/refresh', json={'refresh_token':first['refresh_token']}).json()
    assert second['refresh_token'] != first['refresh_token']
    assert client.post('/api/v1/auth/refresh', json={'refresh_token':first['refresh_token']}).status_code == 401
    assert client.get('/api/v1/devices', headers=bearer(second['access_token'])).status_code == 401
    assert client.post('/api/v1/auth/refresh', json={'refresh_token':second['refresh_token']}).status_code == 401


def test_logout_and_revoke_other_device(client):
    first, second = login(client), login(client)
    assert client.delete(f"/api/v1/devices/{second['device_id']}", headers=bearer(first['access_token'])).status_code == 204
    assert client.get('/api/v1/devices', headers=bearer(second['access_token'])).status_code == 401
    assert client.post('/api/v1/auth/logout', headers=bearer(first['access_token'])).status_code == 204
    assert client.get('/api/v1/devices', headers=bearer(first['access_token'])).status_code == 401


def test_invalid_and_expired_credentials(client):
    assert client.get('/api/v1/devices').status_code == 401
    assert client.get('/api/v1/devices', headers=bearer('garbage')).json() == {'detail':{'code':'unauthorized'}}
    first = login(client)
    with client.app.state.engine.begin() as connection:
        connection.execute(update(tokens).values(expires_at=0))
    assert client.get('/api/v1/devices', headers=bearer(first['access_token'])).status_code == 401
    assert client.post('/api/v1/auth/refresh', json={'refresh_token':first['refresh_token']}).status_code == 401


def test_rate_limit_persists_across_application_restart(client):
    data = {'username':'owner','password':'wrong','device_name':'phone'}
    for _ in range(5):
        assert client.post('/api/v1/auth/login', json=data).status_code == 401
    with TestClient(create_app(client.app.state.settings)) as restarted:
        assert restarted.post('/api/v1/auth/login', json=data).status_code == 429


def test_unknown_user_and_extra_fields(client):
    assert client.post('/api/v1/auth/login', json={'username':'missing','password':'wrong','device_name':'phone'}).json() == {'detail':{'code':'unauthorized'}}
    assert client.post('/api/v1/auth/login', json={'username':'owner','password':'wrong','device_name':'phone','extra':1}).status_code == 422


def test_account_reset_revokes_sessions_and_single_account(client):
    first = login(client)
    with pytest.raises(ValueError):
        create_account(client.app.state.settings, 'second', 'another password long enough')
    reset_password(client.app.state.settings, 'owner', 'new password long enough')
    assert client.get('/api/v1/devices', headers=bearer(first['access_token'])).status_code == 401
    assert client.post('/api/v1/auth/login',json={'username':'owner','password':'new password long enough','device_name':'new'}).status_code == 200


def test_ip_rate_limit_cannot_be_bypassed_with_new_usernames(client):
    for index in range(5):
        assert client.post('/api/v1/auth/login', json={'username':f'unknown-{index}', 'password':'wrong', 'device_name':'phone'}).status_code == 401
    assert client.post('/api/v1/auth/login', json={'username':'another', 'password':'wrong', 'device_name':'phone'}).status_code == 429


def test_account_rate_limit_cannot_be_bypassed_with_new_ips(client):
    settings = client.app.state.settings
    for index in range(5):
        with TestClient(create_app(settings), client=(f'10.0.0.{index}', 1234)) as remote:
            assert remote.post('/api/v1/auth/login', json={'username':'owner', 'password':'wrong', 'device_name':'phone'}).status_code == 401
    with TestClient(create_app(settings), client=('10.1.1.1', 1234)) as remote:
        assert remote.post('/api/v1/auth/login', json={'username':'owner', 'password':'wrong', 'device_name':'phone'}).status_code == 429


def test_token_expirations_and_wrong_token_kind(client):
    result = login(client)
    with client.app.state.engine.connect() as connection:
        rows = connection.execute(select(tokens.c.kind, tokens.c.expires_at)).all()
        expiration = dict(rows)
        assert expiration['refresh'] - expiration['access'] == 30 * 24 * 3600 - 15 * 60
    assert client.get('/api/v1/devices', headers=bearer(result['refresh_token'])).status_code == 401
    assert client.post('/api/v1/auth/refresh', json={'refresh_token':result['access_token']}).status_code == 401


def test_cli_prompts_without_password_arguments(client, monkeypatch):
    from keybox_backend import cli
    calls = []
    monkeypatch.setattr('sys.argv', ['keybox', 'reset-password', 'owner'])
    monkeypatch.setenv('KEYBOX_DATABASE_URL', client.app.state.settings.database_url)
    monkeypatch.setattr(cli.getpass, 'getpass', lambda prompt: calls.append(prompt) or 'new password long enough')
    cli.main()
    assert calls == ['Password: ', 'Confirm password: ']


def test_validation_does_not_echo_password_input(client):
    secret = 'private-password-marker'
    response = client.post('/api/v1/auth/login', json={'username':'owner', 'password':{'secret':secret}, 'device_name':'phone'})
    assert response.status_code == 422
    assert secret not in response.text
