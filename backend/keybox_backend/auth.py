from datetime import datetime, timezone
from hashlib import sha256
import secrets
import time
from uuid import UUID, uuid4

from argon2 import PasswordHasher
from argon2.exceptions import VerificationError
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import delete, insert, select, update
from starlette.responses import JSONResponse

from .db import transaction
from .models import accounts, devices, login_attempts, tokens

router = APIRouter(prefix='/api/v1')
password_hasher = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=4)
dummy_hash = password_hasher.hash(secrets.token_urlsafe(32))


class StrictModel(BaseModel):
    model_config = ConfigDict(extra='forbid')


class Login(StrictModel):
    username: str = Field(min_length=1, max_length=128)
    password: str = Field(min_length=1, max_length=1024)
    device_name: str = Field(min_length=1, max_length=128)


class Refresh(StrictModel):
    refresh_token: str = Field(min_length=1, max_length=256)


def digest(value):
    return sha256(value.encode()).hexdigest()


def timestamp(value):
    return datetime.fromtimestamp(value, timezone.utc).isoformat().replace('+00:00', 'Z')


def denied(code='unauthorized', status=401):
    return JSONResponse({'detail': {'code': code}}, status_code=status)


def issue_tokens(connection, device_id, settings, now):
    result = {'device_id': device_id}
    for kind, duration in [('access', settings.access_seconds), ('refresh', settings.refresh_seconds)]:
        secret = secrets.token_urlsafe(32)
        connection.execute(insert(tokens).values(hash=digest(secret), device_id=device_id,
            kind=kind, expires_at=now + duration, used=False))
        result[f'{kind}_token'] = secret
    return result


def authenticated(request: Request):
    header = request.headers.get('authorization', '')
    if not header.startswith('Bearer ') or len(header) > 300:
        raise HTTPException(401, detail={'code': 'unauthorized'})
    now = int(time.time())
    with transaction(request.app.state.engine) as connection:
        row = connection.execute(select(devices).join(tokens).where(
            tokens.c.hash == digest(header[7:]), tokens.c.kind == 'access',
            tokens.c.expires_at > now, devices.c.revoked == False)).mappings().first()
        if row is None:
            raise HTTPException(401, detail={'code': 'unauthorized'})
        connection.execute(update(devices).where(devices.c.id == row['id']).values(last_seen=now))
        return dict(row)


@router.post('/auth/login')
def login(data: Login, request: Request):
    settings, now = request.app.state.settings, int(time.time())
    # Hash keys so invalid usernames and source IPs are not persisted as plaintext.
    keys = [digest('account:' + data.username), digest('ip:' + (request.client.host if request.client else 'unknown'))]
    with transaction(request.app.state.engine) as connection:
        attempts = {}
        for key in keys:
            row = connection.execute(select(login_attempts).where(login_attempts.c.key == key)).mappings().first()
            if row and row['started_at'] + settings.login_window_seconds > now:
                attempts[key] = dict(row)
            else:
                attempts[key] = {'key': key, 'started_at': now, 'failures': 0}
            if attempts[key]['failures'] >= settings.login_limit:
                return denied('rate_limited', 429)
        account = connection.execute(select(accounts).where(accounts.c.username == data.username)).mappings().first()
        try:
            valid = password_hasher.verify(account['password_hash'] if account else dummy_hash, data.password)
        except VerificationError:
            valid = False
        if not account or not valid:
            for entry in attempts.values():
                connection.execute(delete(login_attempts).where(login_attempts.c.key == entry['key']))
                entry['failures'] += 1
                connection.execute(insert(login_attempts).values(**entry))
            return denied()
        # Account failures reset on successful authentication; IP failures remain until window expiry.
        connection.execute(delete(login_attempts).where(login_attempts.c.key == keys[0]))
        device_id = str(uuid4())
        connection.execute(insert(devices).values(id=device_id, account_id=account['id'], name=data.device_name,
            created_at=now, last_seen=now, revoked=False))
        return issue_tokens(connection, device_id, settings, now)


@router.post('/auth/refresh')
def refresh(data: Refresh, request: Request):
    now = int(time.time())
    with transaction(request.app.state.engine) as connection:
        row = connection.execute(select(tokens).where(tokens.c.hash == digest(data.refresh_token),
            tokens.c.kind == 'refresh')).mappings().first()
        if row is None:
            return denied()
        if row['used']:
            connection.execute(update(devices).where(devices.c.id == row['device_id']).values(revoked=True))
            # Returning commits this revocation before the 401 is sent.
            return denied()
        device = connection.execute(select(devices).where(devices.c.id == row['device_id'])).mappings().one()
        if device['revoked'] or row['expires_at'] <= now:
            return denied()
        connection.execute(update(tokens).where(tokens.c.hash == row['hash']).values(used=True))
        connection.execute(update(devices).where(devices.c.id == device['id']).values(last_seen=now))
        # Previous access tokens cease working after rotation.
        connection.execute(delete(tokens).where(tokens.c.device_id == device['id'], tokens.c.kind == 'access'))
        return issue_tokens(connection, device['id'], request.app.state.settings, now)


@router.post('/auth/logout', status_code=204)
def logout(request: Request, device=Depends(authenticated)):
    with transaction(request.app.state.engine) as connection:
        connection.execute(update(devices).where(devices.c.id == device['id']).values(revoked=True))
    return Response(status_code=204)


@router.get('/devices')
def list_devices(request: Request, device=Depends(authenticated)):
    with request.app.state.engine.connect() as connection:
        rows = connection.execute(select(devices).where(devices.c.account_id == device['account_id'],
            devices.c.revoked == False).order_by(devices.c.created_at, devices.c.id)).mappings().all()
        return [{'id':row['id'], 'name':row['name'], 'created_at':timestamp(row['created_at']),
            'last_seen':timestamp(row['last_seen'])} for row in rows]


@router.delete('/devices/{device_id}', status_code=204)
def revoke_device(device_id: UUID, request: Request, device=Depends(authenticated)):
    with transaction(request.app.state.engine) as connection:
        connection.execute(update(devices).where(devices.c.id == str(device_id),
            devices.c.account_id == device['account_id']).values(revoked=True))
    return Response(status_code=204)
