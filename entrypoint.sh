#!/bin/bash
# Container entrypoint — runs init scripts then hands off to supervisord.
set -euo pipefail

export TZ="${TZ:-Europe/Berlin}"
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# ── MySQL: initialize data directory on first run ─────────────────────────────
if [ ! -d /var/lib/mysql/mysql ]; then
    echo "[entrypoint] Initializing MySQL data directory..."
    mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql > /dev/null
fi

# ── Start MySQL temporarily for init scripts ──────────────────────────────────
echo "[entrypoint] Starting MySQL for initialization..."
mysqld_safe --skip-networking &
MYSQL_PID=$!

/setup/mysql-init.sh
/setup/icinga2-init.sh

# ── Stop temporary MySQL (supervisord will restart it) ────────────────────────
echo "[entrypoint] Stopping init MySQL..."
mysqladmin shutdown 2>/dev/null || true
wait $MYSQL_PID 2>/dev/null || true

echo "[entrypoint] Handing off to supervisord..."
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
