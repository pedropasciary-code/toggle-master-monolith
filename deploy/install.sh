#!/bin/sh
# One-time EC2 setup (Amazon Linux 2023). Run as root from the repo cloned at /opt/togglemaster.
set -eu

APP_DIR="/opt/togglemaster"
APP_USER="ec2-user"

if [ "$(id -u)" -ne 0 ]; then
  echo "Execute com sudo: sudo $APP_DIR/deploy/install.sh" >&2
  exit 1
fi

echo "==> Pacotes do sistema"
dnf install -y python3 python3-pip nginx postgresql16

echo "==> Ambiente Python da aplicação"
chown -R "$APP_USER:$APP_USER" "$APP_DIR"
sudo -u "$APP_USER" python3 -m venv "$APP_DIR/venv"
sudo -u "$APP_USER" "$APP_DIR/venv/bin/pip" install --upgrade pip
sudo -u "$APP_USER" "$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements.txt"

echo "==> Serviço systemd"
install -m 0644 "$APP_DIR/deploy/togglemaster.service" /etc/systemd/system/togglemaster.service

echo "==> nginx (porta 80 -> gunicorn 127.0.0.1:5000)"
sed -i 's/ default_server//' /etc/nginx/nginx.conf
install -m 0644 "$APP_DIR/deploy/nginx-togglemaster.conf" /etc/nginx/conf.d/togglemaster.conf
nginx -t

echo "==> Habilitando e iniciando"
systemctl daemon-reload
systemctl enable --now nginx togglemaster
systemctl reload nginx
systemctl restart togglemaster

systemctl --no-pager status togglemaster | head -n 5
