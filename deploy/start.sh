#!/bin/sh
# Mirrors entrypoint.sh for the EC2 deploy: create schema, then hand over to Gunicorn.
set -eu

APP_DIR="/opt/togglemaster"
cd "$APP_DIR"

FLASK_APP=app "$APP_DIR/venv/bin/flask" init-db

exec "$APP_DIR/venv/bin/gunicorn" \
  --workers "${WEB_CONCURRENCY:-2}" \
  --bind 127.0.0.1:5000 \
  --access-logfile - \
  app:app
