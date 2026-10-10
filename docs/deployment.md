# Deploying KeyBox

The supplied container configuration serves one personal account using Python 3.12, FastAPI, SQLite, and Caddy TLS. On 2026-10-10, the host-Caddy deployment below was verified on Ubuntu with Docker: 43 backend tests passed, HTTPS authentication/refresh/logout worked, and a database backup restored into an independent copy with working authentication and revoked sessions. Android physical-device and iOS acceptance remain pending.

## maybing.top deployment with host Caddy

The client base URL is `https://maybing.top/keybox/api/`. Caddy strips `/keybox/api` before forwarding; existing API routes retain `/api/v1`, so the login URL is `/keybox/api/api/v1/auth/login`. Health is available at `/keybox/api/healthz`, and API documentation at `/keybox/api/docs`.

Source is installed at `/opt/keybox`. Use both Compose files for every operation:

```sh
cd /opt/keybox
sudo docker compose --project-directory deploy -f deploy/compose.yaml -f deploy/compose.host-caddy.yaml build api
sudo docker compose --project-directory deploy -f deploy/compose.yaml -f deploy/compose.host-caddy.yaml up -d --wait api
```

The override disables the bundled Caddy container and assigns the API `172.30.0.10` on an internal `172.30.0.0/24` bridge. Confirm this subnet does not overlap existing networks before reusing the configuration elsewhere. No API host port is published. The existing host Caddy uses these directives inside its `maybing.top` site:

```caddyfile
redir /keybox/api /keybox/api/ 308
handle_path /keybox/api/* {
    reverse_proxy 172.30.0.10:8000
}
```

Other domain responses belong in a separate `handle` block. Validate the complete Caddyfile before reloading it. The existing IP-based `/slackingoff/` site is retained. Host Caddy manages the Let's Encrypt certificate and renewal; Docker and Caddy are enabled at boot, and the API uses `unless-stopped` restart policy.

Python dependencies are installed through `https://pypi.tuna.tsinghua.edu.cn/simple`. Tsinghua's Docker CE mirror distributes Docker installation packages, not Docker Hub images. The Python base was downloaded from the Docker Official Image at `public.ecr.aws/docker/library/python:3.12-slim` and tagged locally as `python:3.12-slim`. Its verified digest is `sha256:a6e34c598f2467ed0e9a8d349809fcd8b5c603269512df273a0bb1784edc11b1`. The deployed API image `keybox/api:56f3615` has ID `sha256:da54c5c27e14e3259f15772eb75dd26a9491cb6ea7e3bf0d49741ae6d782cb49`; it includes the Tsinghua Dockerfile change on top of source commit `56f3615`.

The initial sync account is `keybox`. Its generated password was transferred to a protected local file; server temporary plaintext files were removed. Set a new password interactively using the password-reset command below, adding `-f deploy/compose.host-caddy.yaml`. Use the same extra file for backup and restore commands. The verified initial backup is `/data/backups/initial-20261010.db` in the data volume; the independent restore drill used `/data/keybox-restore-drill.db` without selecting it as the live database. The backup currently contains an empty vault.

## Standalone deployment with bundled Caddy

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
