#!/usr/bin/env bash
# NHAI PostHog hobby install on posthog-server-datalake
# Run as root via SSM: sudo bash 01-install-docker-posthog.sh
set -euo pipefail

DOMAIN="posthog.nh-ai.org"
INSTALL_DIR="/opt/posthog"
SWAPFILE="/swapfile"

export DEBIAN_FRONTEND=noninteractive

echo "==> [1/6] Base packages"
apt-get update -y
apt-get install -y ca-certificates curl gnupg jq unzip

echo "==> [2/6] 4G swap (PostHog is memory-heavy; instance has 16G RAM)"
if ! swapon --show | grep -q .; then
  if [[ ! -f "$SWAPFILE" ]]; then
    fallocate -l 4G "$SWAPFILE"
    chmod 600 "$SWAPFILE"
    mkswap "$SWAPFILE"
  fi
  swapon "$SWAPFILE" || true
  grep -q "$SWAPFILE" /etc/fstab || echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
fi

echo "==> [3/6] Docker Engine + Compose plugin"
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker
# Persistent Docker data on encrypted root EBS
mkdir -p /var/lib/docker
docker info | grep -E 'Docker Root Dir|Storage Driver' || true

echo "==> [4/6] ClickHouse-friendly sysctl"
cat >/etc/sysctl.d/99-posthog.conf <<'EOF'
vm.max_map_count=262144
fs.file-max=1048576
EOF
sysctl --system >/dev/null

echo "==> [5/6] DNS check for TLS (Let's Encrypt via Caddy)"
RESOLVED="$(dig +short "$DOMAIN" A | tail -n1 || true)"
echo "    $DOMAIN resolves to: ${RESOLVED:-<none>}"
echo "    Expected Elastic IP: 3.108.101.197"
if [[ "$RESOLVED" != "3.108.101.197" ]]; then
  echo "WARNING: A record is not 3.108.101.197 yet. Caddy TLS will fail until DNS is correct."
fi

echo "==> [6/6] PostHog hobby installer (non-interactive)"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
if [[ ! -x "$INSTALL_DIR/hobby-installer" ]]; then
  curl -fsSL -o "$INSTALL_DIR/hobby-installer" \
    https://github.com/PostHog/posthog/releases/download/hobby-latest/hobby-installer
  chmod +x "$INSTALL_DIR/hobby-installer"
fi

# Prefer the official CI installer; fall back to deploy-hobby if the binary is unavailable.
if "$INSTALL_DIR/hobby-installer" --help >/dev/null 2>&1; then
  "$INSTALL_DIR/hobby-installer" --ci --domain="$DOMAIN"
else
  echo "hobby-installer not usable; falling back to deploy-hobby"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/posthog/posthog/HEAD/bin/deploy-hobby)"
fi

echo "==> Hobby stack started. Next: bash 02-configure-s3-override.sh"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | head -40
