#!/bin/bash
# First-run Icinga2 + IcingaWeb2 initialisation
# Safe to run on every start — checks before acting.
set -euo pipefail

NODENAME="${ICINGA2_NODENAME:-icinga2}"
DIRECTOR_PASS="${ICINGA2_FEATURE_DIRECTOR_PASS:-changeme}"
ICINGA_DB_PASS="${ICINGA_DB_PASS:-icinga2}"
DIRECTOR_DB_PASS="${DIRECTOR_DB_PASS:-director}"

# ── Seed /etc/icinga2 from defaults if fresh volume mount ─────────────────────
if [ ! -f /etc/icinga2/icinga2.conf ]; then
    echo "[icinga2-init] Seeding /etc/icinga2 from package defaults..."
    cp -rn /etc/icinga2-default/. /etc/icinga2/
    chown -R nagios:nagios /etc/icinga2
fi

# ── Icinga2 API setup (only on first run) ──────────────────────────────────────
if [ ! -f /var/lib/icinga2/certs/${NODENAME}.crt ]; then
    echo "[icinga2-init] Setting up Icinga2 node (name: ${NODENAME})..."
    icinga2 node setup --master --cn "${NODENAME}" --zone "${NODENAME}"
fi

# ── IDO feature ────────────────────────────────────────────────────────────────
if [ ! -f /etc/icinga2/features-enabled/ido-mysql.conf ]; then
    echo "[icinga2-init] Enabling ido-mysql feature..."
    cat > /etc/icinga2/features-available/ido-mysql.conf << CONF
object IdoMysqlConnection "ido-mysql" {
  user     = "icinga2"
  password = "${ICINGA_DB_PASS}"
  host     = "localhost"
  database = "icinga2"
}
CONF
    icinga2 feature enable ido-mysql
fi

# ── API user for Director ──────────────────────────────────────────────────────
APIUSER_FILE=/etc/icinga2/conf.d/api-users.conf
if ! grep -q "icinga2-director" "${APIUSER_FILE}" 2>/dev/null; then
    echo "[icinga2-init] Adding Director API user..."
    cat >> "${APIUSER_FILE}" << CONF

object ApiUser "icinga2-director" {
  password = "${DIRECTOR_PASS}"
  permissions = [ "*" ]
}
CONF
fi

# ── IcingaWeb2 config (only on first run) ──────────────────────────────────────
if [ ! -f /etc/icingaweb2/config.ini ]; then
    echo "[icinga2-init] Bootstrapping IcingaWeb2 config..."
    mkdir -p /etc/icingaweb2/modules/monitoring \
             /etc/icingaweb2/modules/director \
             /etc/icingaweb2/enabledModules

    # Global config
    cat > /etc/icingaweb2/config.ini << CONF
[global]
show_stacktraces = "0"
show_application_state_messages = "1"
config_resource = "icingaweb2_db"
module_path = "/usr/share/icingaweb2/modules"

[logging]
log     = "syslog"
level   = "ERROR"
application = "icingaweb2"
CONF

    # Resources
    cat > /etc/icingaweb2/resources.ini << CONF
[icingaweb2_db]
type     = "db"
db       = "mysql"
host     = "localhost"
dbname   = "icingaweb2"
username = "icingaweb2"
password = "${DIRECTOR_DB_PASS}"
charset  = "utf8mb4"

[icinga_ido]
type     = "db"
db       = "mysql"
host     = "localhost"
dbname   = "icinga2"
username = "icinga2"
password = "${ICINGA_DB_PASS}"
charset  = "utf8mb4"

[director_db]
type     = "db"
db       = "mysql"
host     = "localhost"
dbname   = "director"
username = "director"
password = "${DIRECTOR_DB_PASS}"
charset  = "utf8mb4"
CONF

    # Authentication
    cat > /etc/icingaweb2/authentication.ini << CONF
[icingaweb2]
backend  = "db"
resource = "icingaweb2_db"
CONF

    # Roles
    cat > /etc/icingaweb2/roles.ini << CONF
[Administrators]
users       = "admin"
permissions = "*"
CONF

    # Monitoring module backend
    cat > /etc/icingaweb2/modules/monitoring/backends.ini << CONF
[icinga]
type     = "ido"
resource = "icinga_ido"
CONF

    cat > /etc/icingaweb2/modules/monitoring/config.ini << CONF
[security]
protected_customvars = "cvar1, cvar2"
CONF

    # Director module
    cat > /etc/icingaweb2/modules/director/config.ini << CONF
[db]
resource = "director_db"
CONF

    # Enable modules
    ln -sf /usr/share/icingaweb2/modules/monitoring \
           /etc/icingaweb2/enabledModules/monitoring
    ln -sf /usr/share/icingaweb2/modules/incubator \
           /etc/icingaweb2/enabledModules/incubator
    ln -sf /usr/share/icingaweb2/modules/director \
           /etc/icingaweb2/enabledModules/director 2>/dev/null || true

    chown -R www-data:icingaweb2 /etc/icingaweb2
    chmod 2770 /etc/icingaweb2
fi

# ── Ensure www-data is in icingaweb2 group ────────────────────────────────────
usermod -aG icingaweb2 www-data 2>/dev/null || true

echo "[icinga2-init] Done."
