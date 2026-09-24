#!/usr/bin/env bash
# Point PostHog object + session-recording storage at the private NHAI S3 bucket.
# Run as root after 01-install-docker-posthog.sh
set -euo pipefail

BUCKET="nhai-posthog-storage-564088812664-ap-south-1-an"
REGION="ap-south-1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Hobby installer typically leaves compose files under /opt/posthog or /root
COMPOSE_DIR=""
for d in /opt/posthog /root /home/ubuntu /home/ubuntu/posthog; do
  if [[ -f "$d/docker-compose.hobby.yml" ]] || [[ -f "$d/docker-compose.yml" ]]; then
    COMPOSE_DIR="$d"
    break
  fi
done

if [[ -z "$COMPOSE_DIR" ]]; then
  echo "ERROR: cannot find PostHog docker-compose files. Install first."
  exit 1
fi

echo "==> Using compose directory: $COMPOSE_DIR"
cp -f "$SCRIPT_DIR/compose.s3.override.yml" "$COMPOSE_DIR/compose.s3.override.yml"

cd "$COMPOSE_DIR"

# Prefer hobby + generated compose if both exist
FILES=()
[[ -f docker-compose.yml ]] && FILES+=(-f docker-compose.yml)
[[ -f docker-compose.hobby.yml ]] && FILES+=(-f docker-compose.hobby.yml)
FILES+=(-f compose.s3.override.yml)

echo "==> Recreate app services with S3 env (IAM role, no public bucket)"
docker compose "${FILES[@]}" up -d web worker plugins ingestion-sessionreplay recording-api capture replay-capture cymbal temporal-django-worker || \
  docker compose "${FILES[@]}" up -d

echo "==> Instance-role S3 smoke test from the host"
if command -v aws >/dev/null 2>&1; then
  echo "posthog-s3-probe $(date -u +%FT%TZ)" > /tmp/posthog-s3-probe.txt
  aws s3 cp /tmp/posthog-s3-probe.txt "s3://${BUCKET}/exports/s3-probe.txt" --region "$REGION"
  aws s3 ls "s3://${BUCKET}/exports/" --region "$REGION"
else
  echo "aws CLI not on host; install amazon-cli or use SSM role from a container later."
fi

echo "==> Next: bash 03-verify.sh"
