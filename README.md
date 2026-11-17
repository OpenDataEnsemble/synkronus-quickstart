# Synkronus Quickstart

Welcome! This repository provides a ready-to-run setup of **ODE: Synkronus**, including a Postgres database, so you can try it out quickly or use it as a starting point for your own deployments.

---

## Features

- Fully containerized Synkronus server
- Includes Postgres database
- Supports local usage and GitHub Codespaces
- Single named volume for all Synkronus mutable data (`/app/data` in the container)

---

## One-line installer

The fastest way to a working server with HTTPS. You need a fresh **Ubuntu 24.04** (or Debian 12) server with at least **1 GB of memory**, for example a $6/month DigitalOcean Droplet. Pick the route that fits you; all three use the same installer, `get.sh`.

| Route | Best for | What you do |
|-------|----------|-------------|
| **A. Paste one line** (recommended) | Anyone who can open the server's console | Paste the command below and press Enter |
| **B. No terminal** | People who have never used a command line | Paste [`cloud-init.sh`](./cloud-init.sh) into the "User data" box when you create the server |
| **C. Cloudflare Tunnel** | Servers without a public IP, or teams already using Cloudflare | Paste the command below with your tunnel token |

**A. Paste one line**

```bash
curl -fsSL https://raw.githubusercontent.com/OpenDataEnsemble/synkronus-quickstart/main/get.sh | sudo bash
```

It asks one question (your domain, or press Enter for a free `https://<server-ip>.sslip.io` address), then prints your address and admin login.

**B. No terminal:** when creating the server, open *Advanced Options → Add Initialization scripts* (DigitalOcean) or *Cloud config* (Hetzner), paste [`cloud-init.sh`](./cloud-init.sh) after changing the password in it, and create the server. After 5–10 minutes, open `https://<server-ip>.sslip.io` and log in as `admin`.

**C. Cloudflare Tunnel:** in the Cloudflare dashboard go to *Zero Trust → Networks → Tunnels → Create a tunnel* (type Cloudflared), copy the token from the install command it shows, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/OpenDataEnsemble/synkronus-quickstart/main/get.sh | sudo bash -s -- --tunnel-token YOUR_TOKEN --domain data.example.org
```

Finally, in the tunnel add a *Public hostname* `data.example.org` with service type **HTTP** and URL **`caddy:80`**. No ports need to be opened.

### What the installer does

- Uses **Podman** (recommended; installed for you). Docker is used instead if it is already installed or on systems where Podman is too old (pass `--runtime docker` to choose it).
- Generates all passwords and secrets and saves them in `/opt/synkronus/.env` (root only).
- Runs PostgreSQL, Synkronus and Caddy. Caddy gets and renews the HTTPS certificate. Synkronus and the database are not reachable from outside.
- Checks memory, disk, free ports and (for a domain) the DNS record first, and explains any problem in plain words.
- Adds swap on 1 GB servers, starts everything again after a reboot, and takes a backup every night at 02:00 (kept 7 days).
- Running it again on the same server changes nothing; it shows the status instead.

### Options

| Option | Meaning |
|--------|---------|
| `--domain NAME` | Your own domain (must already point to the server) |
| `--tunnel-token TOKEN` | Use a Cloudflare Tunnel instead of opening ports 80/443 |
| `--admin-user NAME` / `--admin-password PASS` | Choose the admin login (default `admin` with a generated password) |
| `--runtime podman\|docker` | Container engine (default `podman`) |
| `--version TAG` | Synkronus image tag (default `latest`) |
| `--ip ADDRESS` | Public IP, if detection is wrong |
| `--quick-tunnel` | Try it out with no domain, account or open ports: a free temporary `https://….trycloudflare.com` address (changes when the server restarts) |
| `--local` | Local testing only, plain `http://localhost` |
| `--yes` | Never ask questions (for scripts and cloud-init) |

Every option can also be given as an environment variable (`SYNK_DOMAIN`, `SYNK_TUNNEL_TOKEN`, `SYNK_ADMIN_PASSWORD`, ...).

### Managing the server

After installing, use the `synkronus` command on the server:

| Command | What it does |
|---------|--------------|
| `synkronus status` | Is it running? Address, version, last backup, free disk |
| `synkronus credentials` | Show the address and admin login again |
| `synkronus backup` | Back up the database and all files (app bundles, attachments) now |
| `synkronus restore FILE` | Put back a backup from `/opt/synkronus/backups` |
| `synkronus update` | Back up, update to the newest version, and roll back if it does not start |
| `synkronus reset-admin-password` | Set a new admin password and show it |
| `synkronus logs` | Recent server messages |
| `synkronus start` / `stop` / `restart` | |
| `synkronus uninstall` | Remove Synkronus (keeps data unless `--delete-data`) |

After logging in to the Portal, create a separate **Read/Write** user for phones under *Users*, and keep the admin login for yourself.

---

## Quick Start (manual, from a clone)

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
