#!/usr/bin/env bash
# Verify PostHog health, ports, workers, and S3.
set -euo pipefail

DOMAIN="posthog.nh-ai.org"
BUCKET="nhai-posthog-storage-564088812664-ap-south-1-an"
REGION="ap-south-1"

echo "==> Memory / disk"
free -h
df -h /
swapon --show || true

echo "==> Ports 80/443 (Caddy / proxy only)"
ss -tlnp | grep -E ':80|:443' || true

echo "==> Containers"
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

echo "==> Must be Up: web, worker, capture, proxy, db, clickhouse, kafka, redis"
for name in web worker capture proxy db clickhouse kafka redis; do
  if docker ps --format '{{.Names}}' | grep -qi "$name"; then
    echo "  OK  $name"
  else
    echo "  MISSING  $name"
  fi
done

echo "==> HTTPS / HTTP health"
curl -sI "https://${DOMAIN}" | head -20 || true
curl -sI "http://127.0.0.1" | head -15 || true

echo "==> S3 bucket (must stay private; list via instance role)"
aws s3 ls "s3://${BUCKET}/" --region "$REGION" || echo "S3 list failed — check hop-limit 2 and PostHogS3RuntimeAccess"
echo "--- session-recordings prefix ---"
aws s3 ls "s3://${BUCKET}/session-recordings/" --region "$REGION" || echo "(empty until a recording is captured)"
echo "--- exports prefix ---"
aws s3 ls "s3://${BUCKET}/exports/" --region "$REGION" || true

echo "==> Done. Open https://${DOMAIN} and complete first-user signup."
echo "    Then send a UAT event and re-run the S3 listing for session-recordings/."
