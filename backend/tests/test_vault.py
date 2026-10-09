import base64
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import event, update

from keybox_backend.app import create_app
from keybox_backend.cli import create_account
from keybox_backend.config import Settings
from keybox_backend.db import transaction
from keybox_backend.models import items, vault_metadata


def envelope(value=b'encrypted bytes'):
    return {'version':1,'nonce':base64.b64encode(b'n'*12).decode(),'ciphertext':base64.b64encode(value).decode(),'tag':base64.b64encode(b't'*16).decode()}


def metadata():
    return {'format_version':1,'vault_id':str(uuid4()),'kdf':{'algorithm':'argon2id','memory_kib':65536,'iterations':3,'parallelism':4,'salt':base64.b64encode(b's'*16).decode()},'password_wrap':envelope(b'k'*32),'recovery_wrap':envelope(b'r'*32)}


@pytest.fixture
def client(tmp_path):
    settings=Settings(database_url=f"sqlite:///{tmp_path/'app.db'}")
    create_account(settings,'owner','correct horse battery staple')
    with TestClient(create_app(settings)) as client:
        auth=client.post('/api/v1/auth/login',json={'username':'owner','password':'correct horse battery staple','device_name':'phone'}).json()
        client.headers['Authorization']='Bearer '+auth['access_token']
        yield client


def initialize(client):
    value=metadata()
    assert client.put('/api/v1/vault/metadata',json={'base_version':0,'operation_id':str(uuid4()),'payload':value}).json()=={'version':1}
    return value


def item_request(vault_id,version=0,deleted=False):
    return {'vault_id':vault_id,'base_version':version,'operation_id':str(uuid4()),'deleted':deleted,'payload':None if deleted else envelope()}


def test_empty_vault_and_auth_required(client):
    assert client.get('/api/v1/vault').json()=={'metadata':None,'metadata_version':0,'items':[]}
    assert client.get('/api/v1/vault',headers={'Authorization':'bad'}).status_code==401


def test_metadata_cas_idempotency_and_fixed_vault_id(client):
    value=metadata()
    request={'base_version':0,'operation_id':str(uuid4()),'payload':value}
    assert client.put('/api/v1/vault/metadata',json=request).json()=={'version':1}
    updated={**request,'base_version':1,'operation_id':str(uuid4())}
    assert client.put('/api/v1/vault/metadata',json=updated).json()=={'version':2}
    assert client.put('/api/v1/vault/metadata',json=request).json()=={'version':1}
    response=client.put('/api/v1/vault/metadata',json={**request,'operation_id':str(uuid4())})
    assert response.status_code==409
    assert response.json()['detail']['current']=={'payload':value,'version':2}
    assert client.put('/api/v1/vault/metadata',json={**updated,'base_version':2,'operation_id':str(uuid4()),'payload':metadata()}).json()['detail']['code']=='vault_mismatch'


def test_items_cas_stable_retry_and_tombstones(client):
    value=initialize(client)
    path=f'/api/v1/items/{uuid4()}'
    request=item_request(value['vault_id'])
    original=client.put(path,json=request).json()
    assert original['version']==1
    conflict=client.put(path,json={**request,'operation_id':str(uuid4())})
    assert conflict.status_code==409 and conflict.json()['detail']['current']==original
    deleted=client.put(path,json=item_request(value['vault_id'],1,True)).json()
    assert deleted['version']==2 and deleted['deleted'] and deleted['payload'] is None
    assert client.put(path,json=request).json()==original
    resurrection=client.put(path,json=item_request(value['vault_id'],2))
    assert resurrection.status_code==409 and resurrection.json()['detail']['code']=='deleted'
    assert client.get('/api/v1/vault').json()['items']==[deleted]


def test_operation_id_namespace_and_payload_misuse(client):
    value=initialize(client)
    request=item_request(value['vault_id'])
    path=f'/api/v1/items/{uuid4()}'
    assert client.put(path,json=request).status_code==200
    assert client.put(f'/api/v1/items/{uuid4()}',json=request).json()['detail']['code']=='operation_id_reused'
    assert client.put(path,json={**request,'payload':envelope(b'different')}).json()['detail']['code']=='operation_id_reused'


def test_vault_binding_and_missing_item_conflict(client):
    value=initialize(client)
    item_id=str(uuid4())
    path='/api/v1/items/'+item_id
    assert client.put(path,json=item_request(str(uuid4()))).json()['detail']['code']=='vault_mismatch'
    response=client.put(path,json=item_request(value['vault_id'],2))
    assert response.json()['detail']['current']=={'id':item_id,'version':0,'deleted':False,'payload':None,'updated_at':None}


def test_concurrent_metadata_initialization_has_one_winner(client):
    requests=[{'base_version':0,'operation_id':str(uuid4()),'payload':metadata()} for _ in range(2)]
    with ThreadPoolExecutor(max_workers=2) as pool:
        results=list(pool.map(lambda data:client.put('/api/v1/vault/metadata',json=data),requests))
    assert sorted(result.status_code for result in results)==[200,409]


def test_concurrent_item_cas_has_one_winner(client):
    value=initialize(client)
    path=f'/api/v1/items/{uuid4()}'
    with ThreadPoolExecutor(max_workers=2) as pool:
        results=list(pool.map(lambda _:client.put(path,json=item_request(value['vault_id'])),range(2)))
    assert sorted(result.status_code for result in results)==[200,409]


@pytest.mark.parametrize('field,value',[('nonce',''),('nonce','not-base64'),('tag',base64.b64encode(b't'*15).decode()),('ciphertext',''),('version',2),('plaintext','secret-marker')])
def test_invalid_envelope_is_rejected_without_echo(client,field,value):
    vault=initialize(client)
    request=item_request(vault['vault_id'])
    request['payload'][field]=value
    response=client.put(f'/api/v1/items/{uuid4()}',json=request)
    assert response.status_code==422 and 'secret-marker' not in response.text


def test_oversize_and_invalid_metadata(client):
    value=initialize(client)
    request=item_request(value['vault_id'])
    request['payload']=envelope(b'x'*(1024*1024+1))
    assert client.put(f'/api/v1/items/{uuid4()}',json=request).status_code==422
    request['payload']=None
    assert client.put(f'/api/v1/items/{uuid4()}',json=request).status_code==422
    bad=metadata()
    bad['kdf']['memory_kib']=1
    assert client.put('/api/v1/vault/metadata',json={'base_version':1,'operation_id':str(uuid4()),'payload':bad}).status_code==422


def test_same_operation_concurrent_retry_returns_same_result(client):
    value=initialize(client)
    path=f'/api/v1/items/{uuid4()}'
    request=item_request(value['vault_id'])
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses=list(pool.map(lambda _:client.put(path,json=request),range(2)))
    assert [response.status_code for response in responses]==[200,200]
    assert responses[0].json()==responses[1].json()
    assert client.get('/api/v1/vault').json()['items'][0]['version']==1


def test_failed_operation_does_not_consume_id_and_cannot_reuse_metadata_id(client):
    value=metadata()
    operation_id=str(uuid4())
    assert client.put('/api/v1/vault/metadata',json={'base_version':1,'operation_id':operation_id,'payload':value}).status_code==409
    assert client.put('/api/v1/vault/metadata',json={'base_version':0,'operation_id':operation_id,'payload':value}).status_code==200
    request={**item_request(value['vault_id']),'operation_id':operation_id}
    assert client.put(f'/api/v1/items/{uuid4()}',json=request).json()['detail']['code']=='operation_id_reused'


def test_snapshot_remains_consistent_during_write(client):
    value=initialize(client)
    assert client.put(f'/api/v1/items/{uuid4()}',json=item_request(value['vault_id'])).status_code==200
    engine=client.app.state.engine
    fired=[]

    def mutate_after_metadata_read(connection,cursor,statement,parameters,context,executemany):
        if not fired and statement.startswith('SELECT vault_metadata.account_id'):
            fired.append(True)
            with transaction(engine) as writer:
                writer.execute(update(vault_metadata).values(version=2))
                writer.execute(update(items).values(version=2))

    event.listen(engine,'after_cursor_execute',mutate_after_metadata_read)
    try:
        snapshot=client.get('/api/v1/vault').json()
    finally:
        event.remove(engine,'after_cursor_execute',mutate_after_metadata_read)
    assert fired
    assert snapshot['metadata_version']==1 and snapshot['items'][0]['version']==1
    assert client.get('/api/v1/vault').json()['metadata_version']==2


@pytest.mark.parametrize('mutation',[
    lambda value:value['kdf'].update(extra='plaintext-marker'),
    lambda value:value['password_wrap'].update(nonce='bad'),
    lambda value:value.update(extra='plaintext-marker'),
    lambda value:value.update(format_version=True),
])
def test_metadata_rejects_unknown_nested_fields_and_wrong_types(client,mutation):
    value=metadata()
    mutation(value)
    response=client.put('/api/v1/vault/metadata',json={'base_version':0,'operation_id':str(uuid4()),'payload':value})
    assert response.status_code==422
    assert 'plaintext-marker' not in response.text
    assert client.get('/api/v1/vault').json()['metadata'] is None
