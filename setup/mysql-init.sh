#!/bin/bash
# First-run MySQL initialisation
# Creates icinga2 (IDO) and director databases + users if they don't exist.
set -euo pipefail

ICINGA_DB_PASS="${ICINGA_DB_PASS:-icinga2}"
DIRECTOR_DB_PASS="${DIRECTOR_DB_PASS:-director}"
WEB_DB_PASS="${WEB_DB_PASS:-icingaweb2}"

echo "[mysql-init] Waiting for MySQL to be ready..."
for i in $(seq 1 30); do
    mysqladmin ping --silent && break
    sleep 1
done

echo "[mysql-init] Creating databases and users..."
mysql -u root << SQL
CREATE DATABASE IF NOT EXISTS icinga2 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS director CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS icingaweb2 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'icinga2'@'localhost' IDENTIFIED BY '${ICINGA_DB_PASS}';
CREATE USER IF NOT EXISTS 'director'@'localhost' IDENTIFIED BY '${DIRECTOR_DB_PASS}';
CREATE USER IF NOT EXISTS 'icingaweb2'@'localhost' IDENTIFIED BY '${WEB_DB_PASS}';

GRANT ALL PRIVILEGES ON icinga2.*   TO 'icinga2'@'localhost';
GRANT ALL PRIVILEGES ON director.*  TO 'director'@'localhost';
GRANT ALL PRIVILEGES ON icingaweb2.* TO 'icingaweb2'@'localhost';
FLUSH PRIVILEGES;
SQL

# Import IDO schema if not already imported
TABLE_COUNT=$(mysql -u root -s -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='icinga2';" 2>/dev/null || echo 0)
if [ "$TABLE_COUNT" -lt 5 ]; then
    echo "[mysql-init] Importing Icinga2 IDO schema..."
    mysql -u root icinga2 < /usr/share/icinga2-ido-mysql/schema/mysql.sql
else
    echo "[mysql-init] IDO schema already present (${TABLE_COUNT} tables)."
fi

echo "[mysql-init] Done."
