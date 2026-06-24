#!/usr/bin/env bash
set -uo pipefail

USERNAME=$(whoami)
HOME_DIR="/home/$USERNAME"

echo "=== CKAN Devstaller Uninstaller ==="
echo "Removes everything installed by ckan-devstaller."
echo "Username: $USERNAME"
echo ""

# ── 1. Stop & remove ckan-compose Docker containers ──────────────────────────
echo "[1/9] Stopping ckan-compose containers..."
if [ -d "$HOME_DIR/ckan-compose" ] && [ -f "$HOME_DIR/ahoy" ]; then
    cd "$HOME_DIR/ckan-compose"
    sudo "$HOME_DIR/ahoy" down 2>/dev/null || true
fi
sudo docker compose -f "$HOME_DIR/ckan-compose/docker-compose.yml" down --volumes --remove-orphans 2>/dev/null || true

# Remove any remaining containers with project name
sudo docker ps -aq --filter "name=ckan-devstaller" | xargs -r sudo docker rm -f 2>/dev/null || true
sudo docker rm -f ckan-compose_mailcatcher_1 2>/dev/null || true

# ── 2. Remove Docker volumes ──────────────────────────────────────────────────
echo "[2/9] Removing CKAN Docker volumes..."
sudo docker volume ls -q | grep -E "ckan" | xargs -r sudo docker volume rm 2>/dev/null || true
sudo docker system prune -f 2>/dev/null || true

# ── 3. Remove CKAN directories ────────────────────────────────────────────────
echo "[3/9] Removing /usr/lib/ckan, /etc/ckan, /var/lib/ckan..."
sudo rm -rf /usr/lib/ckan
sudo rm -rf /etc/ckan
sudo rm -rf /var/lib/ckan

# ── 4. Remove ckan-compose repo ───────────────────────────────────────────────
echo "[4/9] Removing ckan-compose repo..."
rm -rf "$HOME_DIR/ckan-compose"

# ── 5. Remove binaries ────────────────────────────────────────────────────────
echo "[5/9] Removing Ahoy and qsvdp binaries..."
rm -f "$HOME_DIR/ahoy"
sudo rm -f /usr/local/bin/qsvdp

# ── 6. Remove leftover files ──────────────────────────────────────────────────
echo "[6/9] Removing leftover install files..."
rm -f "$HOME_DIR/get-docker.sh"
rm -f "$HOME_DIR/dpp_default_config.ini"
rm -f "$HOME_DIR/ckan-devstaller"
rm -f "$HOME_DIR/permissions.sql"
rm -f "$HOME_DIR/README"
# Any leftover qsv zip/binaries
rm -f "$HOME_DIR"/qsv-*.zip
rm -f "$HOME_DIR"/qsvdp*
rm -f "$HOME_DIR"/qsv*

# ── 7. Stop services ──────────────────────────────────────────────────────────
echo "[7/9] Stopping services..."
sudo systemctl stop redis-server 2>/dev/null || true
sudo systemctl disable redis-server 2>/dev/null || true
sudo systemctl stop ssh 2>/dev/null || true
sudo systemctl disable ssh 2>/dev/null || true

# ── 8. Remove apt packages installed by ckan-devstaller ──────────────────────
echo "[8/9] Removing apt packages..."
echo "  Note: curl, git, and build-essential are left intact (common system tools)."
sudo apt remove -y \
    openssh-server \
    redis-server \
    python3-dev \
    libpq-dev \
    python3-pip \
    python3-venv \
    python3-virtualenv \
    python3-wheel \
    libxslt1-dev \
    libxml2-dev \
    zlib1g-dev \
    libffi-dev \
    uchardet \
    unzip \
    2>/dev/null || true
sudo apt autoremove -y 2>/dev/null || true

# ── 9. Docker ────────────────────────────────────────────────────────────────
echo "[9/9] Removing Docker..."
sudo systemctl stop docker 2>/dev/null || true
sudo apt remove -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    docker-compose \
    docker.io \
    2>/dev/null || true
sudo apt autoremove -y 2>/dev/null || true
sudo rm -rf /var/lib/docker
sudo rm -rf /etc/docker
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo rm -f /etc/apt/keyrings/docker.gpg
sudo rm -f /etc/apt/keyrings/docker.asc

echo ""
echo "=== Uninstall complete ==="
echo "System is clean. CKAN, ckan-compose, Ahoy, qsvdp, and related packages removed."
