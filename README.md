# icinga2-docker

Custom all-in-one Docker image for Icinga2 monitoring on ARM64 (Raspberry Pi).

## What's in the image

| Component | Version |
|-----------|---------|
| Base | Debian 12 slim |
| Icinga2 | 2.13.14 |
| IcingaWeb2 | 2.12.6 |
| Director | 1.11.6 |
| MariaDB | 10.11 |
| Apache2 | 2.4 |

All processes run under `supervisord`. Ports: **8088** (IcingaWeb2), **5665** (Icinga2 API/agent).

## Repository layout

```
Dockerfile                  — Image build
entrypoint.sh               — Container startup (runs init scripts, then supervisord)
supervisord.conf            — Process supervision (icinga2, mysqld, apache2, director-daemon)
setup/
  mysql-init.sh             — First-run DB creation and schema import
  icinga2-init.sh           — First-run Icinga2/IcingaWeb2 configuration
  icingaweb2-apache.conf    — Apache vhost for IcingaWeb2 on port 8088
icinga2/
  commands.conf             — Custom CheckCommand definitions (nrpe_tls, DNS, IMAP, broker notifs)
  vps-services.conf         — VPS-agent services (lives in zones.d/master/ on the host, outside Director)
scripts/
  check_rpi_temp.sh         — NRPE plugin: Raspberry Pi CPU temperature
grafana/
  icinga2-dashboard.json    — Grafana dashboard (push via API or import in UI)
```

## Building

```bash
docker build -t icinga2-custom:2.13.14 .
```

## Volume mounts (required)

| Host path | Container path | Purpose |
|-----------|---------------|---------|
| `.../etc-icinga2` | `/etc/icinga2` | Icinga2 config (persistent) |
| `.../lib-icinga2` | `/var/lib/icinga2` | Icinga2 state/certs (persistent) |
| `.../mysql-new` | `/var/lib/mysql` | MariaDB data (persistent) |
| `.../icingaweb2` | `/etc/icingaweb2` | IcingaWeb2 config (persistent) |
| `.../certs` | `/opt/nagios/etc/cert` | NRPE mutual TLS certs (ro) |
| `.../machine-scripts` | `/opt/Custom-Nagios-Plugins` | Custom check plugins (ro) |

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `ICINGA2_FEATURE_DIRECTOR_PASS` | `changeme` | Director API user password |
| `ICINGA_DB_PASS` | `icinga2` | Password for `icinga2` DB user |
| `DIRECTOR_DB_PASS` | `director` | Password for `director` and `icingaweb2` DB users |
| `WEB_DB_PASS` | — | Password for IcingaWeb2 DB (set same as DIRECTOR_DB_PASS) |
| `TZ` | `Europe/Berlin` | Container timezone |

## Grafana dashboard

The dashboard (`grafana/icinga2-dashboard.json`) requires an InfluxDB 1.x-compatible
datasource (InfluxDB 2.x with DBRP mapping works). Datasource UID in the JSON:
`fe6rjdv686epse` — update this to match your Grafana datasource if needed.

Push to Grafana API:
```bash
curl -u 'admin:PASSWORD' -X POST 'https://YOUR_GRAFANA/api/dashboards/db' \
  -H 'Content-Type: application/json' \
  -d @grafana/icinga2-dashboard.json
```

## NRPE temperature check

`scripts/check_rpi_temp.sh` reads `/sys/class/thermal/thermal_zone0/temp`.
Deploy to each Pi at `/opt/TheShare/machine-scripts/check_rpi_temp.sh` and add to
`/data/dockervolumes/nagios/nrpe/etc/nrpe.cfg`:

```
command[check_temperature]=/opt/TheShare/machine-scripts/check_rpi_temp.sh
```

Then reload NRPE: `sudo systemctl reload nrpe`

## Director deploys

Use `icingacli director config deploy` directly — no wrapper script needed.

```bash
docker exec $(docker ps -q -f name=mon_icinga2) icingacli director config deploy
docker exec $(docker ps -q -f name=mon_icinga2) /etc/init.d/icinga2 reload
```

The stage-switching bug present in Icinga2 r2.10.3 (circular `include "*/include.conf"` in
`active.conf`) is **fixed in r2.13.14**.

## Known Issues

### VPS services not managed by Director

Director 1.11.6 cannot model `command_endpoint` on individual service objects via apply-rules.
`icinga2/vps-services.conf` lives permanently at `/etc/icinga2/zones.d/master/vps-services.conf`
on the host, outside Director's scope, and is never touched by deploys.

### /opt/TheShare is NOT GlusterFS on the Pis

Each Pi has `/opt/TheShare` as a local directory (on `/dev/sda2`), not the GlusterFS mount
(which is at `/data/TheShare`). When adding new scripts to `machine-scripts`, copy them
directly to each Pi via `scp` in addition to writing to `/data/TheShare/machine-scripts/`.
