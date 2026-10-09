# KeyBox API v1

The service holds a single administrator-created personal account. There is no registration endpoint. All vault content is ciphertext encrypted and authenticated on the client. Authentication passwords are separate from vault passwords. JSON requests reject unknown fields. Times are UTC ISO-8601 strings.

## Authentication

- `POST /api/v1/auth/login`: `{username,password,device_name}`. Returns `{access_token,refresh_token,device_id}`. Access expires in 15 minutes; refresh expires in 30 days. Tokens are opaque random bearer secrets; only SHA-256 token hashes are persisted.
- `POST /api/v1/auth/refresh`: `{refresh_token}`. Returns the same shape with newly rotated tokens. A refresh secret may be used once. Reuse revokes the entire device session, including its access tokens. Clients must serialize refresh attempts and never retry a consumed refresh token.
- `POST /api/v1/auth/logout`: bearer authorization; revokes the current device session; returns HTTP 204.
- `GET /api/v1/devices`: bearer authorization; returns a JSON array of active devices `{id,name,created_at,last_seen}`.
- `DELETE /api/v1/devices/{uuid}`: bearer authorization; revokes that device; returns HTTP 204.

Invalid, expired, or revoked credentials return HTTP 401 with `{detail:{code:"unauthorized"}}`. Failed login attempts are persisted and limited by account and source IP: five failures per fifteen-minute window, then HTTP 429 `{detail:{code:"rate_limited"}}`. Forwarded headers are not trusted by the application.

## Ciphertext envelope and metadata

Envelope fields: `{version:1,nonce:base64,ciphertext:base64,tag:base64}`. Base64 is canonical padded RFC4648. Nonce is 12 bytes; tag is 16 bytes; ciphertext is at most 1 MiB decoded. AES-256-GCM encryption, decryption, AAD generation, and key handling happen exclusively on the client. The server validates structure, never decrypts.

Metadata is exactly:

```json
{"format_version":1,"vault_id":"UUID","kdf":{"algorithm":"argon2id","memory_kib":65536,"iterations":3,"parallelism":4,"salt":"base64-16-byte-salt"},"password_wrap":{"version":1,"nonce":"base64","ciphertext":"base64","tag":"base64"},"recovery_wrap":{"version":1,"nonce":"base64","ciphertext":"base64","tag":"base64"}}
```

## Vault synchronization

All endpoints require `Authorization: Bearer ACCESS_TOKEN`.

- `GET /api/v1/vault`: `{metadata:null|metadata,metadata_version:int,items:[{id,version,deleted,payload:null|envelope,updated_at}]}`. A new account has null metadata, version zero, and no items. Includes permanent tombstones. Clients merge versions and persist their pending operations until confirmed.
- `PUT /api/v1/vault/metadata`: `{base_version:int,operation_id:UUID,payload:metadata}`. Returns `{version:int}`. Initialization uses base version zero, is transactional, and can succeed only once. Later writes increment the version using compare-and-swap. The vault ID cannot change.
- `PUT /api/v1/items/{uuid}`: `{vault_id:UUID,base_version:int,operation_id:UUID,payload:null|envelope,deleted:bool}`. Returns `{id,version,deleted,payload,updated_at}`. A new ID uses version zero; writes increment versions. The request vault ID must match current metadata. Active records require payload; deletion requires null payload. A deleted ID can never be resurrected.

A stale base version returns HTTP 409 `{detail:{code:"conflict",current:record}}`. Metadata current record is `{payload:null|metadata,version:int}`. Missing item current is `{id,version:0,deleted:false,payload:null,updated_at:null}`. A vault mismatch returns HTTP 409 `{detail:{code:"vault_mismatch"}}`; an attempted resurrection returns HTTP 409 `{detail:{code:"deleted",current:record}}`.

Successful operation IDs are unique per account across metadata and item writes. Replaying an identical request returns the original successful response, even when the record subsequently changed. Reusing the ID for different target/body returns HTTP 409 `{detail:{code:"operation_id_reused"}}`. Failed operations do not consume an ID. SQLite writes acquire BEGIN IMMEDIATE locks, so version checks and cached responses commit atomically.

## Limits and operations

Request bodies are limited to 2 MiB, including chunked uploads; oversized bodies return HTTP 413 `{detail:{code:"body_too_large"}}`. Invalid fields return HTTP 422. No request bodies, passwords, bearer tokens, or vault secrets are logged. `GET /healthz` returns `{status:"ok"}` without authentication.

From `backend/`, install the locked dependencies with `../.venv/Scripts/python.exe -m pip install -r requirements.lock.txt`, then run `../.venv/Scripts/python.exe -m uvicorn keybox_backend.app:app --host 127.0.0.1 --port 8000`. Set `KEYBOX_DATABASE_URL=sqlite:///absolute/path/keybox.db` for the persistent SQLite database. Migrations run at startup and CLI invocation. TLS termination must be provided for remote use. Do not run multiple API replicas against separate database copies.

Administrator CLI: `python -m keybox_backend.cli create-account USERNAME` and `reset-password USERNAME` prompt for passwords and confirmation without command line secrets. Passwords must contain 12 to 1024 characters. Only one account may exist. Password reset revokes all sessions and does not alter encrypted vault data. Database backup/restore validation commands will use the SQLite backup API rather than copying a live WAL database file.

Validation errors return HTTP 422 `{detail:{code:"invalid_request"}}` without reflecting submitted values. Refresh also invalidates previous access tokens for that device. Successful login clears the account failure count; the source IP failure count remains until its window expires. Device deletion is idempotent and returns 204 for unknown IDs. Secrets must be stored securely by clients; no tokens are passed through URLs.
