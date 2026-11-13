# Synkronus Quickstart

Welcome! This repository provides a ready-to-run setup of **ODE: Synkronus**, including a Postgres database, so you can try it out quickly or use it as a starting point for your own deployments.

---

## Features

- Fully containerized Synkronus server
- Includes Postgres database
- Supports local usage and GitHub Codespaces
- Single named volume for all Synkronus mutable data (`/app/data` in the container)

---

## Quick Start

We recommend **Podman** with **podman compose** (or `podman-compose`); the same steps work with Docker and Docker Compose if you prefer.

> **Clean Ubuntu server?** Install the needed tools with:
>
> ```bash
> sudo apt update
> sudo apt install -y podman podman-compose git
> ```

### Easiest: run the installer

Clone the repo (shallow clone is enough), then from the repo root run the installer:

```bash
git clone --depth 1 https://github.com/OpenDataEnsemble/synkronus-quickstart.git server
cd server
chmod +x ./install.sh
./install.sh
podman compose up -d
```

(With Docker, use `docker compose up -d` instead.)

The installer will:

- Generate strong passwords and inject them into `docker-compose.yml`
- Ask whether you have a **domain name** for this server:
  - **Yes** → You enter your domain. **Caddy** is placed in front and will automatically obtain and renew a TLS certificate (Let’s Encrypt). No Certbot or manual steps.
  - **No** → You enter this server’s **public IP** or `localhost`:
    - **Public IP** → The installer uses **&lt;ip&gt;.sslip.io** as the hostname so Caddy can still provision a real TLS certificate. You get HTTPS with no domain.
    - **localhost** → Caddy serves local HTTP on host port `8081` (container port `80`, no TLS), for local testing.

The script prints admin username and password (save them). Once the server is up, log in with those credentials and you can create new users from the UI. Use **https://your-domain/** or **https://&lt;your-ip&gt;.sslip.io/** (with TLS), or **http://localhost:8081/** for local-only.

In localhost mode, **Caddy** listens on **http://localhost:8081/** and reverse-proxies to **Synkronus** on **http://localhost:8080/**. The Synkronus port stays published on `8080` so you can still hit the backend directly for checks like `curl http://localhost:8080/health`.

> **Podman rootless note:** rootless Podman cannot bind privileged host ports (<1024) unless you change system settings. The installer's localhost mode uses host port `8081` to avoid this.

> **Note:** If you don't see the portal but get a certificate error instead, try restarting Caddy: `podman restart synkronus_caddy`.
> On first boot, Caddy requests a Let's Encrypt certificate; validation can occasionally fail on the first attempt if the endpoint is not yet reachable. If HTTPS still isn't ready after a minute, check the Caddy logs and restart the Caddy container once.

### Data storage layout

Synkronus stores mutable files under **`/app/data`** in the container (one volume: `appdata`). You do **not** set `DATA_DIR` or `APP_BUNDLE_PATH` for the default layout. Subdirectories are:

| Path in volume         | Purpose                                 |
| ---------------------- | --------------------------------------- |
| `app-bundle/active/`   | Current app bundle (extracted)          |
| `app-bundle/versions/` | Numbered versions and `CURRENT_VERSION` |
| `attachments/`         | Attachment blobs                        |

### Utilities (`utilities/`)

| Script                                                                         | When to use                                                                                                                |
| ------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| [`utilities/backup-attachments.sh`](./utilities/backup-attachments.sh)         | Copy attachment blobs **from a running** Synkronus container to the host (see `--help`).                                   |
| [`utilities/backup-db.sh`](./utilities/backup-db.sh)                           | **`pg_dump`** the Postgres DB to a `.sql` file while **`db` / `postgres`** is running (see `--help`).                      |
| [`utilities/migrate-synkronus-data.sh`](./utilities/migrate-synkronus-data.sh) | Migrate bundle folder layout on the **volume**; run with the **stack stopped** (see [upgrade-path.md](./upgrade-path.md)). |

---

### Local Installation (manual)

1. Clone this repo:

```bash
git clone https://github.com/OpenDataEnsemble/synkronus-quickstart.git
cd synkronus-quickstart
```

2. Adjust env variables in `docker-compose.yml`.

- In the postgres service:
  - `POSTGRES_PASSWORD`
- In the synkronus service:
  - `DB_CONNECTION` (update to match `POSTGRES_PASSWORD`)
  - `JWT_SECRET` (generate a new one with: `openssl rand -base64 32`)
  - `ADMIN_USERNAME`
  - `ADMIN_PASSWORD`

Optionally map volumes to specific mount points on the host (ensure the Synkronus user can write: UID **1000** in the official image).

3. Prepare a database for Synkronus

   Start only the `db` service:

   ```bash
   podman compose up db
   ```

   (Use `docker compose up db` if you use Docker.) This keeps the database container running in the foreground.

   In a separate terminal, make the `create_sync_db.sh` script executable:

   ```bash
   chmod +x ./create_sync_db.sh
   ```

   Then run the script to create the Synkronus database and user, providing a short name for the database (e.g. `myorg`):

   ```bash
   ./create_sync_db.sh <username>
   ```

   Replace `<username>` with a short identifier (e.g. `myorg`). The script will connect to the running `db` container and set up the required database and user account.

4. Start the services:

```bash
podman compose up -d
```

(Use `docker compose up -d` with Docker.)

5. Verify the server is running:

```bash
curl http://localhost:8080/health
# Should return "OK"
```

---

### Upgrading from an older quickstart

If you previously used `APP_BUNDLE_PATH: /app/data/app-bundles` and separate version paths, see **[upgrade-path.md](./upgrade-path.md)** and **`utilities/migrate-synkronus-data.sh`** to move bundle data into **`app-bundle/active`** and **`app-bundle/versions`** safely (stop the stack first, back up the volume, then migrate).

**Attachments:** On some older setups, blobs may have lived outside the `appdata` volume. Use **`utilities/backup-attachments.sh`** while the container is **running** to copy files off the host, then merge into the volume if needed. The migrate script only changes paths **inside** the volume.

---

### Using GitHub Codespaces

1. Click **“Open in Codespaces”** on this repository.
2. Codespaces will automatically start Synkronus + Postgres.
3. Check the **Ports tab** for the forwarded port to access the API.
4. Test the server:

```bash
curl <forwarded-url>/health
```

> Notes:
>
> - Perfect for experimenting or as a base for production setups.

---

## Contributing / Feedback

We welcome feedback! Feel free to open issues or pull requests. If you’re trying this out for the first time, check the **Codespaces** instructions for the quickest setup.

---

Enjoy exploring Synkronus!
