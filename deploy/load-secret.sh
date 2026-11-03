#!/bin/sh
# Fetches DB credentials from AWS Secrets Manager (instance role) into a root-only env file in /run.
set -eu

SECRET_ID="${SECRET_ID:-togglemaster/db}"
REGION="${AWS_REGION:-us-east-2}"
OUT_FILE="/run/togglemaster/env"

umask 077
mkdir -p "$(dirname "$OUT_FILE")"

aws secretsmanager get-secret-value \
  --region "$REGION" \
  --secret-id "$SECRET_ID" \
  --query SecretString \
  --output text \
| python3 -c '
import json, sys
secret = json.load(sys.stdin)
for key in ("DB_HOST", "DB_PORT", "DB_NAME", "DB_USER", "DB_PASSWORD"):
    print(f"{key}={secret[key]}")
' > "$OUT_FILE.tmp"

mv "$OUT_FILE.tmp" "$OUT_FILE"
echo "Credenciais carregadas de $SECRET_ID em $OUT_FILE"
