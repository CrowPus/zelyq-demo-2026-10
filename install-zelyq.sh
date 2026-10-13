#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
  echo 'Run as root: sudo bash install-zelyq.sh' >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
APP_USER=zelyq
APP_HOME=/home/zelyq
APP_DIR="$APP_HOME/Zelyq"

printf '\n==> Installing OS dependencies\n'
apt-get update
apt-get install -y ca-certificates curl gnupg git build-essential python3 openssh-client

printf '\n==> Installing Node.js 22\n'
if ! command -v node >/dev/null 2>&1 || [[ "$(node -p 'process.versions.node.split(".")[0]')" -lt 22 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/zelyq-nodesource.sh
  bash /tmp/zelyq-nodesource.sh
  apt-get install -y nodejs
  rm -f /tmp/zelyq-nodesource.sh
fi
node --version

printf '\n==> Installing pnpm 9.15.0\n'
npm install -g pnpm@9.15.0
pnpm --version

printf '\n==> Creating zelyq Linux user\n'
if ! id "$APP_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$APP_USER"
fi
install -d -o "$APP_USER" -g "$APP_USER" -m 0750 "$APP_HOME"

printf '\n==> Cloning Zelyq\n'
if [[ -d "$APP_DIR/.git" ]]; then
  echo "Existing checkout at $APP_DIR; leaving its changes intact."
elif [[ -e "$APP_DIR" ]]; then
  echo "Cannot clone: $APP_DIR exists but is not a Git checkout." >&2
  exit 1
else
  runuser -u "$APP_USER" -- git clone https://github.com/CrowPus/Zelyq.git "$APP_DIR"
fi

printf '\n==> Installing dependencies\n'
runuser -u "$APP_USER" -- bash -c 'cd "$1" && pnpm install --frozen-lockfile' bash "$APP_DIR"

printf '\n==> Creating systemd service\n'
cat > /etc/systemd/system/zelyq.service <<'UNIT'
[Unit]
Description=Zelyq development stack (web, server, agent)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=zelyq
Group=zelyq
WorkingDirectory=/home/zelyq/Zelyq
Environment=HOME=/home/zelyq
Environment=NODE_ENV=development
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/bin/env pnpm dev
Restart=on-failure
RestartSec=10
TimeoutStopSec=30
KillMode=control-group
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now zelyq.service
printf '\n==> Service status\n'
systemctl --no-pager --full status zelyq.service || true
printf '\nZelyq installed.\n'
printf 'Logs: sudo journalctl -u zelyq -f\n'
printf 'Restart: sudo systemctl restart zelyq\n'
printf 'SSH tunnel from your computer: ssh -L 5173:127.0.0.1:5173 -L 8787:127.0.0.1:8787 -L 8788:127.0.0.1:8788 USER@VM_IP\n'
printf 'Then open http://localhost:5173\n'
