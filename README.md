# Synkronus Quickstart

Welcome! This repository provides a ready-to-run setup of **ODE: Synkronus**, including a Postgres database, so you can try it out quickly or use it as a starting point for your own deployments.

---

## Features

* Fully containerized Synkronus server
* Includes Postgres database
* Supports local usage and GitHub Codespaces
* Easy environment variable configuration

---

## Quick Start

### Local Installation

1. Clone this repo:

```bash
git clone https://github.com/OpenDataEnsemble/synkronus-quickstart.git
cd synkronus-quickstart
```

1. Adjust env variables the `docker-compose.yml` file.

  - In the postgres service:
    - POSTGRES_PASSWORD
  - In the synkronus service:
    - DB_CONNECTION (update to match POSTGRES_PASSWORD)
    - JWT_SECRET (generate a new one with: 'openssl rand -base64 32')
    - ADMIN_USERNAME
    - ADMIN_PASSWORD

Optionally you can choose to map the volumes to specific mountpoints on the host.

1. Start the services:

```bash
docker compose up -d
```

1. Verify the server is running:

```bash
curl http://localhost:8080/health
# Should return "OK"
```

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
> * No UI yet — the API is used with 'Formulus' or 'synkronus-cli'.
> * Perfect for experimenting or as a base for production setups.

---

## Contributing / Feedback

We welcome feedback! Feel free to open issues or pull requests. If you’re trying this out for the first time, check the **Codespaces** instructions for the quickest setup.

---

Enjoy exploring Synkronus!
