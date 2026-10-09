# Deploying KeyBox

The supplied container configuration serves one personal account using Python 3.12, FastAPI, SQLite, and Caddy TLS. Docker is not installed in the development environment, so the Docker image, Compose runtime, and certificate issuance have not been exercised here. The backend tests verify application behavior and SQLite backup/restore independently.

## Initial deployment

1. Install Docker Engine and the Compose plugin on the Linux server. Set your domain's DNS records to the server and allow inbound TCP 80 and 443. Keep the API port private.
2. From the repository root, copy `deploy/.env.example` to `deploy/.env` and replace `KEYBOX_DOMAIN` with your actual DNS name. There are no default accounts or passwords.
3. Run `docker compose --project-directory deploy -f deploy/compose.yaml build` and `docker compose --project-directory deploy -f deploy/compose.yaml up -d`.
4. Run `docker compose --project-directory deploy -f deploy/compose.yaml exec api python -m keybox_backend.cli create-account YOUR_USERNAME`. Enter a new authentication password at the two hidden prompts. The CLI requires 12 to 1024 characters. Do not provide passwords through arguments or environment variables.
5. Open `https://YOUR_DOMAIN/healthz`; it should return `{"status":"ok"}`. Point the KeyBox client at `https://YOUR_DOMAIN` and log in.

The API has no published host port and attaches only to an internal Docker network. Caddy is the sole public ingress and manages certificates in persistent volumes. Uvicorn trusts forwarded headers from that isolated proxy network so login rate limits see client IPs. Do not attach untrusted containers to the private network or expose port 8000. Caddy access logging and Uvicorn access logging are disabled; request bodies and secrets are never logged by the application.

The API runs one worker as UID/GID 10001, drops capabilities, and uses a read-only container filesystem with writable `/data` and temporary `/tmp`. SQLite database/WAL files and backups persist in the `keybox_data` volume. Caddy has separate data/config volumes. Never use `docker compose down -v` on a deployment whose data you need.

The base images are `python:3.12-slim` and `caddy:2`; dependency versions are fixed in `backend/requirements.lock.txt`. These image tags track upstream updates. For a production release, build/test your images on Linux, record their resolved image digests, and deploy that reviewed build. No unverified digest is supplied here.

## Password reset

Run `docker compose --project-directory deploy -f deploy/compose.yaml exec api python -m keybox_backend.cli reset-password YOUR_USERNAME`. The new password is prompted twice. This revokes every device session; it does not decrypt, replace, or reset the vault. Clients must log in again and still need their vault password or recovery material.

## Verified backup

Use a unique backup filename; existing targets are refused:

```sh
docker compose --project-directory deploy -f deploy/compose.yaml exec api python -m keybox_backend.cli backup /data/backups/keybox-2026-10-09.db
docker compose --project-directory deploy -f deploy/compose.yaml cp api:/data/backups/keybox-2026-10-09.db ./keybox-2026-10-09.db
```

The command uses SQLite's backup API to take a consistent snapshot while the service runs, then checks integrity, foreign keys, schema revision, and tables. Copy the verified backup to separately protected storage. A backup contains authentication password hashes, token hashes, and encrypted vault records; restrict access. Vault recovery material and vault passwords must be backed up separately by the user because the server never receives them. A database backup alone cannot decrypt the vault.

## Offline restore drill

Restore creates a new database path and refuses to overwrite any existing file. Stop the API before selecting a restored database for service use. This avoids replacing live WAL files and makes rollback explicit.

```sh
docker compose --project-directory deploy -f deploy/compose.yaml stop api
docker compose --project-directory deploy -f deploy/compose.yaml run --rm --no-deps api python -m keybox_backend.cli restore /data/backups/keybox-2026-10-09.db /data/keybox-restored.db
```

The restore validates source and destination integrity, foreign keys, expected tables, and Alembic revision `0001`. It revokes all restored device sessions so old bearer or refresh secrets cannot become valid again. Accounts, ciphertext, versions, tombstones, and operation responses are preserved. Invalid/corrupt sources and existing targets are refused.

For the drill, temporarily change the API's `KEYBOX_DATABASE_URL` in `deploy/compose.yaml` to `sqlite:////data/keybox-restored.db`, then run `docker compose --project-directory deploy -f deploy/compose.yaml up -d --force-recreate api`. Log in with the authentication password from the backup, verify vault unlock with the vault password/recovery key, and confirm expected items and deletions. Keep the original database until this is verified; switching the URL back permits rollback. Ensure the backup has been placed in the volume before restoring an off-host copy, using `docker compose cp` while the existing API container still exists.

Before production release, validate `docker compose ... config`, build the image, check container health and HTTPS, confirm the API is inaccessible publicly, run login/sync/recovery on two clients, and perform this restore drill. Those environment-dependent checks are not claimed as completed by local pytest results.
