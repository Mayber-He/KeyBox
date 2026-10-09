import json
import time
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import insert, select, update

from .auth import authenticated, digest, timestamp
from .db import transaction
from .models import items, operations, vault_metadata
from .schemas import ItemWrite, MetadataWrite

router = APIRouter(prefix='/api/v1')


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'))


def item_record(row, item_id=None):
    if row is None:
        return {'id': item_id, 'version': 0, 'deleted': False, 'payload': None, 'updated_at': None}
    return {'id':row['id'], 'version':row['version'], 'deleted':row['deleted'],
        'payload':json.loads(row['payload']) if row['payload'] is not None else None,
        'updated_at':timestamp(row['updated_at'])}


def conflict(current):
    raise HTTPException(409, detail={'code':'conflict', 'current':current})


def cached_operation(connection, account_id, data, target):
    request_hash = digest(canonical({'target':target, 'body':data.model_dump(mode='json')}))
    row = connection.execute(select(operations).where(operations.c.account_id == account_id,
        operations.c.id == str(data.operation_id))).mappings().first()
    if row:
        if row['request_hash'] != request_hash:
            raise HTTPException(409, detail={'code':'operation_id_reused'})
        return request_hash, json.loads(row['response'])
    return request_hash, None


def save_operation(connection, account_id, operation_id, request_hash, result):
    connection.execute(insert(operations).values(account_id=account_id, id=str(operation_id),
        request_hash=request_hash, response=canonical(result)))


@router.get('/vault')
def get_vault(request: Request, device=Depends(authenticated)):
    # SQLite needs an explicit BEGIN for a shared snapshot across separate SELECTs.
    with request.app.state.engine.connect() as connection:
        connection.exec_driver_sql('BEGIN')
        try:
            metadata = connection.execute(select(vault_metadata).where(
                vault_metadata.c.account_id == device['account_id'])).mappings().first()
            rows = connection.execute(select(items).where(items.c.account_id == device['account_id'])
                .order_by(items.c.id)).mappings().all()
            result = {'metadata':json.loads(metadata['payload']) if metadata else None,
                'metadata_version':metadata['version'] if metadata else 0,
                'items':[item_record(row) for row in rows]}
        finally:
            connection.rollback()
        return result


@router.put('/vault/metadata')
def put_metadata(data: MetadataWrite, request: Request, device=Depends(authenticated)):
    account_id = device['account_id']
    with transaction(request.app.state.engine) as connection:
        request_hash, cached = cached_operation(connection, account_id, data, 'metadata')
        if cached is not None:
            return cached
        current = connection.execute(select(vault_metadata).where(
            vault_metadata.c.account_id == account_id)).mappings().first()
        version = current['version'] if current else 0
        if data.base_version != version:
            conflict({'payload':json.loads(current['payload']) if current else None, 'version':version})
        payload = data.payload.model_dump(mode='json')
        if current and json.loads(current['payload'])['vault_id'] != payload['vault_id']:
            raise HTTPException(409, detail={'code':'vault_mismatch'})
        values = {'version':version + 1, 'payload':canonical(payload)}
        if current:
            connection.execute(update(vault_metadata).where(vault_metadata.c.account_id == account_id).values(**values))
        else:
            connection.execute(insert(vault_metadata).values(account_id=account_id, **values))
        result = {'version':version + 1}
        save_operation(connection, account_id, data.operation_id, request_hash, result)
        return result


@router.put('/items/{item_id}')
def put_item(item_id: UUID, data: ItemWrite, request: Request, device=Depends(authenticated)):
    account_id, item_id = device['account_id'], str(item_id)
    with transaction(request.app.state.engine) as connection:
        request_hash, cached = cached_operation(connection, account_id, data, 'item:' + item_id)
        if cached is not None:
            return cached
        metadata = connection.execute(select(vault_metadata.c.payload).where(
            vault_metadata.c.account_id == account_id)).scalar()
        if metadata is None or json.loads(metadata)['vault_id'] != str(data.vault_id):
            raise HTTPException(409, detail={'code':'vault_mismatch'})
        current = connection.execute(select(items).where(items.c.account_id == account_id,
            items.c.id == item_id)).mappings().first()
        version = current['version'] if current else 0
        if data.base_version != version:
            conflict(item_record(current, item_id))
        if current and current['deleted'] and not data.deleted:
            raise HTTPException(409, detail={'code':'deleted', 'current':item_record(current)})
        values = {'version':version + 1, 'deleted':data.deleted,
            'payload':canonical(data.payload.model_dump(mode='json')) if data.payload else None,
            'updated_at':int(time.time())}
        if current:
            connection.execute(update(items).where(items.c.account_id == account_id, items.c.id == item_id).values(**values))
        else:
            connection.execute(insert(items).values(account_id=account_id, id=item_id, **values))
        result = item_record({'id':item_id, **values})
        save_operation(connection, account_id, data.operation_id, request_hash, result)
        return result
