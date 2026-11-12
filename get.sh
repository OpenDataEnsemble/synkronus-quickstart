#!/usr/bin/env bash
# Synkronus one-line installer
#
#   curl -fsSL https://raw.githubusercontent.com/OpenDataEnsemble/synkronus-quickstart/main/get.sh | sudo bash
#
# Sets up a complete Synkronus server (Synkronus + PostgreSQL + Caddy for HTTPS)
# on a fresh Ubuntu 24.04 / Debian 12 server, using Podman (recommended) or Docker.
#
# Everything is written to /opt/synkronus. Afterwards, manage the server with
# the `synkronus` command (status, backup, restore, update, ...).
#
# Options (all optional; each also has an environment variable form):
#   --domain NAME          Your own domain, e.g. data.example.org      (SYNK_DOMAIN)
#   --ip ADDRESS           Public IP to use if detection is wrong      (SYNK_PUBLIC_IP)
#   --tunnel-token TOKEN   Use a Cloudflare Tunnel instead of open ports (SYNK_TUNNEL_TOKEN)
#   --quick-tunnel         Try it out: a free temporary https://....trycloudflare.com
#                          address, no domain or account needed (SYNK_QUICK_TUNNEL=1)
#   --local                Local testing only: plain http://localhost  (SYNK_LOCAL=1)
#   --admin-user NAME      Admin username (default: admin)             (SYNK_ADMIN_USER)
#   --admin-password PASS  Admin password (default: generated)         (SYNK_ADMIN_PASSWORD)
#   --runtime podman|docker  Container engine (default: podman)        (SYNK_RUNTIME)
#   --version TAG          Synkronus image tag (default: latest)       (SYNK_VERSION)
#   --yes                  Never ask questions (for cloud-init / scripts) (SYNK_YES=1)
#   --help                 Show this help
#
# Re-running this script on a server that already has Synkronus changes nothing:
# it shows the status instead. Use `synkronus update` to update.

set -Eeuo pipefail

INSTALL_DIR="${SYNK_DIR:-/opt/synkronus}"
DOMAIN="${SYNK_DOMAIN:-}"
PUBLIC_IP="${SYNK_PUBLIC_IP:-}"
TUNNEL_TOKEN="${SYNK_TUNNEL_TOKEN:-}"
QUICK_TUNNEL="${SYNK_QUICK_TUNNEL:-0}"
LOCAL_ONLY="${SYNK_LOCAL:-0}"
ADMIN_USER="${SYNK_ADMIN_USER:-admin}"
ADMIN_PASSWORD="${SYNK_ADMIN_PASSWORD:-}"
RUNTIME="${SYNK_RUNTIME:-}"
IMAGE_TAG="${SYNK_VERSION:-latest}"
ASSUME_YES="${SYNK_YES:-0}"
NO_PULL="${SYNK_NO_PULL:-0}"   # testing only: use images already present
SUBNET="${SYNK_SUBNET:-10.254.247.0/24}"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  BOLD=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi
step() { printf '\n%s==>%s %s%s%s\n' "$GREEN" "$RESET" "$BOLD" "$*" "$RESET"; }
# Long messages are wrapped so they stay readable in narrow browser consoles.
wrap() { fold -s -w "${1:-60}"; }
info() { printf '%s\n' "$*" | wrap 58 | sed 's/^/    /'; }
warn() { printf '%s[!]%s ' "$YELLOW" "$RESET"; printf '%s\n' "$*" | wrap 58 | sed '2,$s/^/    /'; }
die()  { printf '\n%s[x] ' "$RED" >&2; printf '%s\n' "$*" | wrap 58 | sed '2,$s/^/    /' >&2; printf '%s' "$RESET" >&2; exit 1; }
trap 'die "Something went wrong on line $LINENO. Nothing was deleted. Run the same command again, or ask for help and include the lines above."' ERR

usage() {
  if [ -f "$0" ]; then sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
  else echo "Options are listed at https://github.com/OpenDataEnsemble/synkronus-quickstart#one-line-installer"; fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --ip) PUBLIC_IP="${2:-}"; shift 2 ;;
    --tunnel-token) TUNNEL_TOKEN="${2:-}"; shift 2 ;;
    --quick-tunnel) QUICK_TUNNEL=1; shift ;;
    --local) LOCAL_ONLY=1; shift ;;
    --admin-user) ADMIN_USER="${2:-}"; shift 2 ;;
    --admin-password) ADMIN_PASSWORD="${2:-}"; shift 2 ;;
    --runtime) RUNTIME="${2:-}"; shift 2 ;;
    --version) IMAGE_TAG="${2:-}"; shift 2 ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (use --help to see the options)" ;;
  esac
done

# Questions are read from the keyboard even when this script arrives through `curl | bash`.
can_ask() { [ "$ASSUME_YES" != "1" ] && { : </dev/tty; } 2>/dev/null; }
ask() { # ask "Question" default -> echoes answer
  local answer=""
  if can_ask; then read -r -p "$1" answer </dev/tty || true; fi
  printf '%s' "${answer:-$2}"
}

gen_secret() { # letters and digits only, so it is safe in URLs, YAML and shells
  local len="$1" out=""
  while [ "${#out}" -lt "$len" ]; do
    out="$out$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9')"
  done
  printf '%s' "${out:0:$len}"
}

# ---------------------------------------------------------------------------
# 0. Already installed?
# ---------------------------------------------------------------------------
if [ -f "$INSTALL_DIR/.installed" ]; then
  printf '\n%sSynkronus is already installed on this server.%s Nothing was changed.\n\n' "$BOLD" "$RESET"
  if command -v synkronus >/dev/null 2>&1; then synkronus status || true; fi
  printf '\nUseful commands:\n  synkronus credentials   show the address and admin login\n  synkronus update        update to the newest version (takes a backup first)\n  synkronus help          everything else\n\n'
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. Check the machine
# ---------------------------------------------------------------------------
step "Checking this server"
[ "$(id -u)" -eq 0 ] || die "Please run this as root. Put 'sudo' in front, like: curl -fsSL <link> | sudo bash"

[ -r /etc/os-release ] || die "Could not detect the operating system. Please use Ubuntu 24.04 or Debian 12."
OS_ID="$( . /etc/os-release; echo "${ID:-}")"
OS_NAME="$( . /etc/os-release; echo "${PRETTY_NAME:-unknown}")"
case "$OS_ID" in
  ubuntu|debian) ;;
  *) die "This installer supports Ubuntu and Debian (found: $OS_NAME). Please create an Ubuntu 24.04 server." ;;
esac
info "Operating system: $OS_NAME"

ARCH="$(uname -m)"
case "$ARCH" in x86_64|aarch64|arm64) ;; *) die "Unsupported processor type: $ARCH (needs x86_64 or arm64)." ;; esac

MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
info "Memory: ${MEM_MB} MB"
[ "$MEM_MB" -ge 900 ] || die "This server has ${MEM_MB} MB of memory. Synkronus needs at least 1 GB. Choose a bigger server size."

DISK_MB=$(df -Pm / | awk 'NR==2 {print $4}')
info "Free disk: ${DISK_MB} MB"
[ "$DISK_MB" -ge 5000 ] || die "Only ${DISK_MB} MB of free disk space. Please free up space or choose a server with at least 10 GB."

export DEBIAN_FRONTEND=noninteractive
apt_install() { apt-get install -y -q "$@" >/dev/null; }
if ! command -v curl >/dev/null || ! command -v openssl >/dev/null; then
  apt-get update -q >/dev/null
  apt_install curl openssl ca-certificates
fi

# Small servers: add swap so the database is not killed when memory runs low.
if [ "$MEM_MB" -lt 2000 ] && [ "$(awk '/SwapTotal/ {print $2}' /proc/meminfo)" -eq 0 ] && [ ! -e /swapfile ]; then
  info "Adding 2 GB of swap space (helps small servers stay stable)"
  if fallocate -l 2G /swapfile 2>/dev/null && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile 2>/dev/null; then
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  else
    rm -f /swapfile; warn "Could not add swap space. Continuing without it."
  fi
fi

# ---------------------------------------------------------------------------
# 2. Choose how people will reach the server
# ---------------------------------------------------------------------------
step "Choosing your server's web address"
detect_ip() {
  local ip=""
  for url in https://api.ipify.org https://ipv4.icanhazip.com https://ifconfig.me/ip; do
    ip="$(curl -4 -fsS --max-time 6 "$url" 2>/dev/null | tr -d '[:space:]')" || true
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then printf '%s' "$ip"; return 0; fi
  done
  return 1
}

if [ "$QUICK_TUNNEL" = "1" ]; then
  MODE="quick"
  info "Using a free temporary Cloudflare address. No domain, account or open ports needed."
elif [ -n "$TUNNEL_TOKEN" ]; then
  MODE="tunnel"
  info "Using a Cloudflare Tunnel. No ports need to be opened on this server."
elif [ "$LOCAL_ONLY" = "1" ]; then
  MODE="local"
  info "Local testing mode: http://localhost (no HTTPS)."
else
  if [ -z "$DOMAIN" ] && can_ask; then
    printf '\n    Do you have your own web address (domain) for this server, like data.example.org?\n'
    printf '    If not, just press Enter and you will get a free address that works right away.\n\n'
    DOMAIN="$(ask "    Your domain (or press Enter to skip): " "")"
    DOMAIN="$(printf '%s' "$DOMAIN" | tr -d '[:space:]' | sed -e 's#^https\?://##' -e 's#/.*$##' | tr 'A-Z' 'a-z')"
  fi
  if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP="$(detect_ip)" || die "Could not find this server's public IP address. Run again with: --ip YOUR.SERVER.IP"
  fi
  info "This server's public IP: $PUBLIC_IP"
  if [ -n "$DOMAIN" ]; then
    MODE="domain"; SITE_HOST="$DOMAIN"
  else
    MODE="sslip"; SITE_HOST="${PUBLIC_IP}.sslip.io"
  fi
fi

case "$MODE" in
  domain|sslip) URL="https://${SITE_HOST}" ;;
  local) URL="http://localhost" ;;
  tunnel) URL="${DOMAIN:+https://$DOMAIN}"; URL="${URL:-(the public hostname you set in Cloudflare)}" ;;
  quick) URL="(shown when the server is ready)" ;;
esac
info "Your server will be at: ${BOLD}${URL}${RESET}"

# Domain must point here, otherwise HTTPS cannot be set up.
if [ "$MODE" = "domain" ]; then
  RESOLVED="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk 'NR==1 {print $1}')" || true
  if [ "$RESOLVED" != "$PUBLIC_IP" ]; then
    warn "Your domain ${DOMAIN} does not point to this server yet (it points to: ${RESOLVED:-nothing})."
    info "Fix: at your domain provider, create an 'A record' for ${DOMAIN} with the value ${PUBLIC_IP}."
    info "If you use Cloudflare, set it to 'DNS only' (grey cloud) for now."
    info "HTTPS will start working automatically a few minutes after the record is correct."
  else
    info "Domain check: ${DOMAIN} points to this server. Good."
  fi
fi

# Ports 80 and 443 must be free for Caddy (not needed with a tunnel).
if [ "$MODE" != "tunnel" ] && [ "$MODE" != "quick" ] && command -v ss >/dev/null; then
  for p in 80 443; do
    [ "$MODE" = "local" ] && [ "$p" = "443" ] && continue
    if ss -Hltn "sport = :$p" 2>/dev/null | grep -q .; then
      die "Port $p is already used by another program on this server (often a web server like nginx or apache). Stop it first, e.g.: systemctl disable --now nginx apache2"
    fi
  done
fi

# ---------------------------------------------------------------------------
# 3. Install the container engine
# ---------------------------------------------------------------------------
step "Installing the container engine"
if [ -z "$RUNTIME" ]; then
  if command -v podman >/dev/null; then RUNTIME=podman
  elif command -v docker >/dev/null && docker info >/dev/null 2>&1; then RUNTIME=docker
  else RUNTIME=podman
  fi
fi

podman_major() { podman --version 2>/dev/null | awk '{print $3}' | cut -d. -f1; }

if [ "$RUNTIME" = "podman" ]; then
  if ! command -v podman >/dev/null || ! command -v podman-compose >/dev/null; then
    info "Installing Podman (this takes a minute or two)"
    apt-get update -q >/dev/null
    apt_install podman podman-compose || true
    apt_install aardvark-dns netavark 2>/dev/null || true
  fi
  if ! command -v podman-compose >/dev/null || [ "$(podman_major || echo 0)" -lt 4 ]; then
    warn "This system's Podman is too old or incomplete (Ubuntu 22.04 and older). Using Docker instead."
    RUNTIME=docker
  fi
fi

if [ "$RUNTIME" = "docker" ]; then
  if ! command -v docker >/dev/null; then
    info "Installing Docker (this takes a minute or two)"
    curl -fsSL https://get.docker.com | sh >/dev/null 2>&1 || die "Docker could not be installed. Check the server's internet connection and try again."
  fi
  systemctl enable --now docker >/dev/null 2>&1 || true
  docker compose version >/dev/null 2>&1 || apt_install docker-compose-plugin || die "Docker Compose is missing. Install it with: apt-get install docker-compose-plugin"
fi
info "Using: $RUNTIME"

# ---------------------------------------------------------------------------
# 4. Write the configuration
# ---------------------------------------------------------------------------
step "Writing the configuration to $INSTALL_DIR"
umask 077
mkdir -p "$INSTALL_DIR/backups"
# Data left behind by an earlier installation whose settings were deleted cannot be
# opened with new passwords, so stop instead of failing later.
if [ ! -f "$INSTALL_DIR/.env" ] && "$RUNTIME" volume inspect synkronus_pgdata >/dev/null 2>&1; then
  die "This server has Synkronus data from an earlier installation, but its settings file ($INSTALL_DIR/.env) is gone, so the data cannot be opened. If you don't need that data, remove it with: $RUNTIME volume rm synkronus_pgdata synkronus_appdata   and run the installer again."
fi

# An earlier attempt that did not finish: keep its secrets, because the database
# may already have been created with them.
PREV_DB_PASSWORD=""; PREV_JWT=""
if [ -f "$INSTALL_DIR/.env" ]; then
  info "Reusing the settings from the earlier installation"
  PREV_DB_PASSWORD="$( . "$INSTALL_DIR/.env"; echo "${POSTGRES_PASSWORD:-}")"
  PREV_JWT="$( . "$INSTALL_DIR/.env"; echo "${JWT_SECRET:-}")"
  [ -n "$ADMIN_PASSWORD" ] || ADMIN_PASSWORD="$( . "$INSTALL_DIR/.env"; echo "${ADMIN_PASSWORD:-}")"
fi
[ -n "$ADMIN_PASSWORD" ] || ADMIN_PASSWORD="$(gen_secret 20)"
DB_PASSWORD="${PREV_DB_PASSWORD:-$(gen_secret 32)}"
JWT="${PREV_JWT:-$(gen_secret 48)}"

cat > "$INSTALL_DIR/.env" <<EOF
# Synkronus settings, written by get.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ).
# Keep this file private: it holds the database password and signing secret.
SYNK_RUNTIME=$RUNTIME
SYNK_MODE=$MODE
SYNK_URL=$(printf '%q' "$URL")
SYNK_SITE_HOST=${SITE_HOST:-}
SYNK_IMAGE=ghcr.io/opendataensemble/synkronus:$IMAGE_TAG
SYNK_SUBNET=$SUBNET
POSTGRES_PASSWORD=$DB_PASSWORD
JWT_SECRET=$JWT
ADMIN_USERNAME=$(printf '%q' "$ADMIN_USER")
ADMIN_PASSWORD=$(printf '%q' "$ADMIN_PASSWORD")
TUNNEL_TOKEN=$(printf '%q' "$TUNNEL_TOKEN")
BACKUP_KEEP_DAYS=7
EOF
chmod 600 "$INSTALL_DIR/.env"

# --- The `synkronus` helper command ----------------------------------------
cat > /usr/local/bin/synkronus <<'HELPER'
#!/usr/bin/env bash
# synkronus: manage the Synkronus server installed by get.sh
set -Eeuo pipefail
DIR="${SYNK_DIR:-/opt/synkronus}"
[ -f "$DIR/.env" ] || { echo "Synkronus is not installed here ($DIR/.env not found)."; exit 1; }
[ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"
set -a; . "$DIR/.env"; set +a
RT="$SYNK_RUNTIME"
if [ "$RT" = "podman" ]; then COMPOSE=(podman-compose -p synkronus -f "$DIR/compose.yml"); else COMPOSE=(docker compose -p synkronus -f "$DIR/compose.yml"); fi
compose() { (cd "$DIR" && "${COMPOSE[@]}" "$@"); }

yq() { local v="${1//\'/\'\'}"; printf "'%s'" "$v"; } # YAML single-quoted string
render() { # writes compose.yml and Caddyfile from .env
  local ports="" caddy_ip
  case "$SYNK_MODE" in
    domain|sslip) ports=$'    ports:\n      - "80:80"\n      - "443:443"\n      - "443:443/udp"' ;;
    local) ports=$'    ports:\n      - "80:80"' ;;
    tunnel|quick) ports="" ;;
  esac
  case "$SYNK_MODE" in
    domain|sslip) cat > "$DIR/Caddyfile" <<EOF
# Written by the synkronus command. Caddy gets and renews the HTTPS certificate itself.
$SYNK_SITE_HOST {
	encode gzip
	reverse_proxy synkronus:8080 {
		header_up X-Real-IP {remote_host}
	}
}
EOF
    ;;
    local) cat > "$DIR/Caddyfile" <<EOF
# Written by the synkronus command. Local testing only, no HTTPS.
:80 {
	encode gzip
	reverse_proxy synkronus:8080 {
		header_up X-Real-IP {remote_host}
	}
}
EOF
    ;;
    tunnel|quick) cat > "$DIR/Caddyfile" <<EOF
# Written by the synkronus command. Cloudflare Tunnel sends traffic here; HTTPS is handled by Cloudflare.
:80 {
	encode gzip
	reverse_proxy synkronus:8080 {
		header_up X-Real-IP {http.request.header.Cf-Connecting-IP}
	}
}
EOF
    ;;
  esac
  local tunnel_svc=""
  local tcmd="tunnel --no-autoupdate run --token ${TUNNEL_TOKEN}"
  [ "$SYNK_MODE" = "quick" ] && tcmd="tunnel --no-autoupdate --url http://caddy:80"
  if [ "$SYNK_MODE" = "tunnel" ] || [ "$SYNK_MODE" = "quick" ]; then
    tunnel_svc="
  tunnel:
    image: docker.io/cloudflare/cloudflared:latest
    container_name: synkronus-tunnel
    command: ${tcmd}
    depends_on:
      - caddy
    restart: unless-stopped
    networks:
      - synk"
  fi
  cat > "$DIR/compose.yml" <<EOF
# Written by the synkronus command from $DIR/.env. Edit .env, then run: synkronus restart
services:
  db:
    image: docker.io/library/postgres:17
    container_name: synkronus-db
    environment:
      POSTGRES_USER: synkronus
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: synkronus
    volumes:
      - pgdata:/var/lib/postgresql/data
    restart: unless-stopped
    networks:
      - synk

  synkronus:
    image: ${SYNK_IMAGE}
    container_name: synkronus
    environment:
      PORT: "8080"
      LOG_LEVEL: info
      DB_CONNECTION: postgres://synkronus:${POSTGRES_PASSWORD}@db:5432/synkronus?sslmode=disable
      JWT_SECRET: ${JWT_SECRET}
      ADMIN_USERNAME: $(yq "$ADMIN_USERNAME")
      ADMIN_PASSWORD: $(yq "$ADMIN_PASSWORD")
      MAX_VERSIONS_KEPT: "5"
      SYNKRONUS_AUTH_TRUSTED_PROXY_CIDRS: ${SYNK_SUBNET}${SYNKRONUS_RECOVERY_CREATE_USER:+
      SYNKRONUS_RECOVERY_CREATE_USER: ${SYNKRONUS_RECOVERY_CREATE_USER}
      SYNKRONUS_RECOVERY_CREATE_PASS: ${SYNKRONUS_RECOVERY_CREATE_PASS}}
    volumes:
      - appdata:/app/data
    depends_on:
      - db
    restart: unless-stopped
    networks:
      - synk

  caddy:
    image: docker.io/library/caddy:2-alpine
    container_name: synkronus-caddy
${ports}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - synkronus
    restart: unless-stopped
    networks:
      - synk
${tunnel_svc}

networks:
  synk:
    ipam:
      config:
        - subnet: ${SYNK_SUBNET}

volumes:
  pgdata:
  appdata:
  caddy_data:
  caddy_config:
EOF
  chmod 600 "$DIR/compose.yml"
}

# A quick tunnel gets a new random address each time it starts; read the current one.
quick_url() { "$RT" logs synkronus-tunnel 2>&1 | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1; }
current_url() { if [ "$SYNK_MODE" = "quick" ]; then quick_url || true; else echo "$SYNK_URL"; fi; }
healthy() { "$RT" exec synkronus wget -qO- -T 3 http://127.0.0.1:8080/health >/dev/null 2>&1; }
wait_healthy() { # wait_healthy SECONDS
  local i=0
  while [ "$i" -lt "${1:-120}" ]; do healthy && return 0; sleep 3; i=$((i+3)); done
  return 1
}
up() { compose up -d >/dev/null 2>&1 || compose up -d; }
down() { compose down >/dev/null 2>&1 || true; }

backup() {
  local stamp tmp out
  stamp="$(date +%Y%m%d-%H%M%S)"; tmp="$(mktemp -d)"; out="$DIR/backups/synkronus-$stamp.tar.gz"
  echo "Backing up the database..."
  "$RT" exec synkronus-db pg_dump -U synkronus -d synkronus --no-owner > "$tmp/database.sql"
  echo "Backing up app bundles and attachments..."
  "$RT" exec synkronus tar czf - -C /app/data . > "$tmp/appdata.tar.gz"
  printf 'created=%s\nimage=%s\nurl=%s\n' "$stamp" "$SYNK_IMAGE" "$SYNK_URL" > "$tmp/info.txt"
  tar czf "$out" -C "$tmp" database.sql appdata.tar.gz info.txt
  rm -rf "$tmp"; chmod 600 "$out"
  find "$DIR/backups" -name 'synkronus-*.tar.gz' -mtime +"${BACKUP_KEEP_DAYS:-7}" -delete 2>/dev/null || true
  echo "Backup saved: $out ($(du -h "$out" | cut -f1))"
}

restore() {
  local file="${1:-}" tmp
  [ -f "$file" ] || { echo "Usage: synkronus restore /opt/synkronus/backups/synkronus-YYYYMMDD-HHMMSS.tar.gz"; ls -1t "$DIR/backups" 2>/dev/null | head -5; exit 1; }
  echo "This replaces ALL current data on this server with the backup:"; echo "  $file"
  if [ "${SYNK_YES:-0}" != "1" ]; then read -r -p "Type YES to continue: " ok </dev/tty; [ "$ok" = "YES" ] || { echo "Cancelled."; exit 1; }; fi
  tmp="$(mktemp -d)"; tar xzf "$file" -C "$tmp"
  echo "Restoring app bundles and attachments..."
  "$RT" exec -i synkronus sh -c 'rm -rf /app/data/* && tar xzf - -C /app/data' < "$tmp/appdata.tar.gz"
  echo "Restoring the database..."
  "$RT" stop synkronus >/dev/null
  "$RT" exec synkronus-db psql -q -U synkronus -d postgres -c 'DROP DATABASE IF EXISTS synkronus WITH (FORCE);' -c 'CREATE DATABASE synkronus OWNER synkronus;'
  "$RT" exec -i synkronus-db psql -q -U synkronus -d synkronus -v ON_ERROR_STOP=1 < "$tmp/database.sql" >/dev/null
  "$RT" start synkronus >/dev/null
  rm -rf "$tmp"
  wait_healthy 90 && echo "Restore finished. Synkronus is running." || { echo "Restore finished but Synkronus is not healthy yet. Check: synkronus logs"; exit 1; }
}

case "${1:-help}" in
  status)
    echo "Address:   $(current_url)"
    echo "Version:   $SYNK_IMAGE"
    if healthy; then echo "Synkronus: running"; else echo "Synkronus: NOT responding (try: synkronus restart, then synkronus logs)"; fi
    "$RT" ps --format '{{.Names}}\t{{.Status}}' 2>/dev/null | grep '^synkronus' | sed 's/^/  /' || true
    last="$(ls -1t "$DIR"/backups/synkronus-*.tar.gz 2>/dev/null | head -1 || true)"
    echo "Last backup: ${last:-none yet}"
    echo "Free disk:  $(df -Ph / | awk 'NR==2 {print $4}')"
    ;;
  credentials)
    if [ "$SYNK_MODE" = "quick" ]; then echo "Current address: $(current_url)  (temporary, changes after a restart)"; fi
    cat "$DIR/CREDENTIALS.txt" 2>/dev/null || { echo "Address: $SYNK_URL"; echo "Admin username: $ADMIN_USERNAME"; echo "Admin password: $ADMIN_PASSWORD"; }
    ;;
  start) render; up; wait_healthy 120 && echo "Synkronus is running at $(current_url)" ;;
  stop) compose stop >/dev/null 2>&1 || compose stop; echo "Stopped." ;;
  restart) render; down; up; wait_healthy 120 && echo "Synkronus is running at $(current_url)" || { echo "Synkronus did not start. See: synkronus logs"; exit 1; } ;;
  logs) shift; "$RT" logs --tail "${1:-100}" synkronus 2>&1; echo "--- web server (caddy) ---"; "$RT" logs --tail 20 synkronus-caddy 2>&1 ;;
  backup) backup ;;
  restore) shift; restore "${1:-}" ;;
  update)
    echo "Taking a backup first..."; backup
    old="$("$RT" image inspect --format '{{.Id}}' "$SYNK_IMAGE" 2>/dev/null || true)"
    echo "Downloading the newest version..."; compose pull
    render; down; up
    if wait_healthy 150; then echo "Updated. Synkronus is running at $(current_url)"; "$RT" image prune -f >/dev/null 2>&1 || true
    else
      echo "The new version did not start. Going back to the previous version..."
      [ -n "$old" ] && "$RT" tag "$old" "$SYNK_IMAGE"; down; up
      wait_healthy 120 && echo "Back on the previous version. Please report the problem." || echo "Still not running. See: synkronus logs"
      exit 1
    fi
    ;;
  reset-admin-password)
    user="${2:-$ADMIN_USERNAME}"; pass="${3:-$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-20)}"
    echo "Setting a new password for '$user'..."
    SYNKRONUS_RECOVERY_CREATE_USER="$user" SYNKRONUS_RECOVERY_CREATE_PASS="$pass" render
    down; up; wait_healthy 120 || { echo "Synkronus did not start. See: synkronus logs"; exit 1; }
    unset SYNKRONUS_RECOVERY_CREATE_USER SYNKRONUS_RECOVERY_CREATE_PASS; render; down; up; wait_healthy 120 || true
    if [ "$user" = "$ADMIN_USERNAME" ]; then
      sed -i "s/^ADMIN_PASSWORD=.*/ADMIN_PASSWORD=$pass/" "$DIR/.env"
      sed -i "s/^Admin password: .*/Admin password: $pass/" "$DIR/CREDENTIALS.txt" 2>/dev/null || true
    fi
    echo "Done. New login -> username: $user  password: $pass"
    ;;
  uninstall)
    echo "This stops Synkronus and removes it from this server."
    if [ "${2:-}" = "--delete-data" ]; then
      if [ "${SYNK_YES:-0}" != "1" ]; then read -r -p "ALL data will be deleted forever. Type DELETE to continue: " ok </dev/tty; [ "$ok" = "DELETE" ] || { echo "Cancelled."; exit 1; }; fi
      compose down -v >/dev/null 2>&1 || true; rm -rf "$DIR"
    else
      compose down >/dev/null 2>&1 || true; rm -f "$DIR/.installed"
      echo "Your data and backups are kept in $DIR and in the container volumes."
      echo "Running the installer again brings Synkronus back with the same data."
    fi
    systemctl disable --now synkronus.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/synkronus.service /etc/cron.d/synkronus-backup /usr/local/bin/synkronus
    echo "Removed."
    ;;
  render) render ;;
  boot) render; up ;;
  help|-h|--help|*)
    cat <<EOF
synkronus <command>

  status                 Is the server running? Address, version, last backup
  credentials            Show the address and admin login again
  backup                 Back up the database and all files now
  restore FILE           Put back a backup (replaces current data)
  update                 Back up, then update to the newest version
  reset-admin-password   Set a new admin password and show it
  logs                   Show recent server messages
  start | stop | restart
  uninstall              Remove Synkronus (keeps data unless --delete-data)

Settings: $DIR/.env      Backups: $DIR/backups (daily at 02:00, kept ${BACKUP_KEEP_DAYS:-7} days)
EOF
    ;;
esac
HELPER
chmod 755 /usr/local/bin/synkronus
umask 022

# Start on boot (Podman does not restart containers after a reboot by itself).
if [ -d /run/systemd/system ]; then
  cat > /etc/systemd/system/synkronus.service <<EOF
[Unit]
Description=Synkronus server
Wants=network-online.target
After=network-online.target $( [ "$RUNTIME" = docker ] && echo docker.service )

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/synkronus boot
ExecStop=/usr/local/bin/synkronus stop
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable synkronus.service >/dev/null 2>&1 || true
fi

# Nightly backup at 02:00.
cat > /etc/cron.d/synkronus-backup <<'EOF'
# Nightly Synkronus backup (written by get.sh)
0 2 * * * root /usr/local/bin/synkronus backup >> /var/log/synkronus-backup.log 2>&1
EOF
chmod 644 /etc/cron.d/synkronus-backup
command -v cron >/dev/null || apt_install cron >/dev/null 2>&1 || warn "Could not install cron; nightly backups need it."

# Open the firewall if one is active (never turned on by us, so SSH cannot be locked out).
if [ "$MODE" != "tunnel" ] && [ "$MODE" != "quick" ] && command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null; ufw allow 443/udp >/dev/null
  info "Firewall: opened ports 80 and 443"
fi

# ---------------------------------------------------------------------------
# 5. Start
# ---------------------------------------------------------------------------
# Another program already using our container names would be overwritten or break; stop first.
for c in synkronus synkronus-db synkronus-caddy synkronus-tunnel; do
  if "$RUNTIME" container inspect "$c" >/dev/null 2>&1; then
    proj="$("$RUNTIME" container inspect -f '{{index .Config.Labels "com.docker.compose.project"}}{{index .Config.Labels "io.podman.compose.project"}}' "$c" 2>/dev/null || true)"
    if [ "$proj" != "synkronus" ]; then
      die "A container named '$c' already exists on this server and was not created by this installer. To keep it safe, nothing was started. Rename or remove that container, or install on a fresh server."
    fi
  fi
done

step "Starting Synkronus (the first start downloads about 500 MB, please wait)"
synkronus render
if [ "$NO_PULL" != "1" ]; then
  (cd "$INSTALL_DIR" && if [ "$RUNTIME" = podman ]; then podman-compose -p synkronus -f compose.yml pull; else docker compose -p synkronus -f compose.yml pull; fi) >/dev/null 2>&1 \
    || die "Could not download the Synkronus software. Check the server's internet connection and run the same command again."
fi
synkronus boot >/dev/null 2>&1 || synkronus boot

info "Waiting for Synkronus to be ready..."
ok=0
for _ in $(seq 1 60); do
  if "$RUNTIME" exec synkronus wget -qO- -T 3 http://127.0.0.1:8080/health >/dev/null 2>&1; then ok=1; break; fi
  sleep 3
done
[ "$ok" = 1 ] || die "Synkronus did not start within 3 minutes. See what happened with: synkronus logs"
info "Synkronus is running."

HTTPS_NOTE=""
if [ "$MODE" = "quick" ]; then
  info "Getting your temporary web address from Cloudflare..."
  URL=""
  for _ in $(seq 1 40); do
    URL="$("$RUNTIME" logs synkronus-tunnel 2>&1 | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1)" || true
    [ -n "$URL" ] && break
    sleep 3
  done
  [ -n "$URL" ] || die "Could not get a temporary address from Cloudflare. Check the server's internet connection, then run: synkronus restart"
  info "Waiting for the address to come online..."
  for _ in $(seq 1 30); do curl -fsS --max-time 5 "$URL/health" >/dev/null 2>&1 && break; sleep 3; done
fi
if [ "$MODE" = "domain" ] || [ "$MODE" = "sslip" ]; then
  info "Getting the HTTPS certificate (up to 2 minutes)..."
  ok=0
  for i in $(seq 1 40); do
    if curl -fsS --max-time 5 --resolve "${SITE_HOST}:443:127.0.0.1" "https://${SITE_HOST}/health" >/dev/null 2>&1; then ok=1; break; fi
    [ "$i" = 20 ] && "$RUNTIME" restart synkronus-caddy >/dev/null 2>&1 || true
    sleep 3
  done
  if [ "$ok" = 1 ]; then info "HTTPS is working."
  else
    HTTPS_NOTE="HTTPS is not ready yet. Make sure ports 80 and 443 are open in your provider's firewall$( [ "$MODE" = domain ] && echo " and that ${DOMAIN} points to ${PUBLIC_IP}" ). It will start working by itself once they are."
    warn "$HTTPS_NOTE"
  fi
fi

# ---------------------------------------------------------------------------
# 6. Save and show the result
# ---------------------------------------------------------------------------
umask 077
{
  echo "Synkronus server"
  echo "Address: $URL$( [ "$MODE" = quick ] && echo " (temporary: see the current one with synkronus status)")"
  echo "Admin username: $ADMIN_USER"
  echo "Admin password: $ADMIN_PASSWORD"
  echo
  echo "Log in to the Portal at the address above. Then create a separate"
  echo "Read/Write user for phones (Users > Create user); keep the admin login for yourself."
} > "$INSTALL_DIR/CREDENTIALS.txt"
date -u +%Y-%m-%dT%H:%M:%SZ > "$INSTALL_DIR/.installed"
umask 022

line="============================================================"
printf '\n%s%s%s\n' "$GREEN" "$line" "$RESET"
printf '%s  Your Synkronus server is ready%s\n\n' "$BOLD" "$RESET"
printf '  Address:         %s%s%s\n' "$BOLD" "$URL" "$RESET"
printf '  Admin username:  %s%s%s\n' "$BOLD" "$ADMIN_USER" "$RESET"
printf '  Admin password:  %s%s%s\n\n' "$BOLD" "$ADMIN_PASSWORD" "$RESET"
printf '  Copy these somewhere safe. They are also saved in\n  %s/CREDENTIALS.txt\n  (show them again with: synkronus credentials)\n' "$INSTALL_DIR"
if [ "$MODE" = "quick" ]; then
  printf '\n  This address is temporary: it changes when the\n  server restarts (see it with: synkronus status).\n  For a permanent address, use a domain.\n'
fi
if [ "$MODE" = "tunnel" ]; then
  printf '\n  Last step, in Cloudflare: in your tunnel add a\n  Public Hostname for %s\n  with Service type HTTP and URL  caddy:80\n' "${DOMAIN:-your address}"
fi
[ -n "$HTTPS_NOTE" ] && printf '\n  %sNote:%s %s\n' "$YELLOW" "$RESET" "$(printf '%s' "$HTTPS_NOTE" | fold -s -w 52 | sed '2,$s/^/  /')"
printf '\n  Next:\n  1. Open the address in your browser and log in.\n  2. Under Users, create a Read/Write user\n     for your phones.\n  3. Upload your app bundle, then connect\n     Formulus with that user.\n\n  Manage the server with: synkronus help\n'
printf '%s%s%s\n\n' "$GREEN" "$line" "$RESET"
