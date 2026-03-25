#!/bin/bash
# director-deploy.sh — Workaround for Director stage-switching bug in Icinga2 r2.10.3
#
# Root cause: Icinga2 r2.10.3 has a broken include-deduplication for glob patterns.
# When Director creates a new stage, the active.conf ends with `include "*/include.conf"`
# which causes infinite recursion with >1 stage directories present.
#
# This script:
#   1. Runs `icingacli director config deploy` (creates a new stage)
#   2. Copies vps-services.conf (manually managed) into the new stage
#   3. Removes the include "*/include.conf" from active.conf (the fix)
#   4. Updates active-stage + active.conf to point to the new stage
#   5. Removes all OLD stages (preventing the multi-stage recursion bug)
#   6. Removes vps endpoint/zone from /etc/icinga2/zones.conf if present
#      (new stage defines them in endpoints.conf/zones.conf)
#   7. Reloads icinga2
#
# Usage (run on the docker host, not inside container):
#   bash /data/TheShare/prod-mgmt/director-deploy.sh
#
set -euo pipefail

CNAME=$(docker ps --format '{{.Names}}' | grep icinga | head -1)
PKG_DIR=/var/lib/icinga2/api/packages/director
VPS_SERVICES_SRC=/var/lib/icinga2/api/packages/director

if [ -z "$CNAME" ]; then
  echo "ERROR: Icinga2 container not found" >&2
  exit 1
fi

echo "=== Director Deploy Workaround ==="
echo "Container: $CNAME"

# Step 1: Deploy Director config (creates new stage)
echo ""
echo "1. Running Director config deploy..."
OLD_STAGE=$(docker exec "$CNAME" cat $PKG_DIR/active-stage)
docker exec "$CNAME" icingacli director config deploy
NEW_STAGE=$(docker exec "$CNAME" ls $PKG_DIR | grep -v 'active\|include\|\.conf' | grep -v "^${OLD_STAGE}$" | head -1)

if [ -z "$NEW_STAGE" ]; then
  echo "   No new stage created (already up to date?)"
  echo "   Active stage: $OLD_STAGE"
  exit 0
fi
echo "   Old stage: $OLD_STAGE"
echo "   New stage: $NEW_STAGE"

# Step 2: Copy manually managed vps-services.conf to new stage
echo ""
echo "2. Copying vps-services.conf to new stage..."
if docker exec "$CNAME" test -f $PKG_DIR/$OLD_STAGE/zones.d/master/vps-services.conf; then
  docker exec "$CNAME" cp \
    $PKG_DIR/$OLD_STAGE/zones.d/master/vps-services.conf \
    $PKG_DIR/$NEW_STAGE/zones.d/master/vps-services.conf
  echo "   Copied."
else
  echo "   No vps-services.conf in old stage — skipping."
fi

# Step 3+4: Update active.conf WITHOUT the circular include, pointing to new stage
echo ""
echo "3. Activating new stage (fixed active.conf)..."
echo -n "$NEW_STAGE" | docker exec -i "$CNAME" tee $PKG_DIR/active-stage > /dev/null
cat <<EOF | docker exec -i "$CNAME" tee $PKG_DIR/active.conf > /dev/null
if (!globals.contains("ActiveStages")) {
  globals.ActiveStages = {}
}

if (globals.contains("ActiveStageOverride")) {
  var arr = ActiveStageOverride.split(":")
  if (arr[0] == "director") {
    if (arr.len() < 2) {
      log(LogCritical, "Config", "Invalid value for ActiveStageOverride")
    } else {
      ActiveStages["director"] = arr[1]
    }
  }
}

if (!ActiveStages.contains("director")) {
  ActiveStages["director"] = "$NEW_STAGE"
}
EOF
echo "   active-stage → $NEW_STAGE"
echo "   active.conf updated (no circular include)"

# Step 5: Remove all old stages
echo ""
echo "4. Removing old stages..."
for stage in $(docker exec "$CNAME" ls $PKG_DIR | grep -v 'active\|include\|\.conf' | grep -v "^${NEW_STAGE}$"); do
  docker exec "$CNAME" rm -rf "$PKG_DIR/$stage"
  echo "   Removed stage: $stage"
done

# Step 6: Remove vps endpoint/zone from zones.conf if new stage has endpoints.conf
echo ""
echo "5. Checking zones.conf..."
if docker exec "$CNAME" test -f $PKG_DIR/$NEW_STAGE/zones.d/master/endpoints.conf; then
  # New stage manages endpoint/zone — remove from static zones.conf
  docker exec "$CNAME" bash -c '
    head -20 /etc/icinga2/zones.conf > /tmp/zones_deploy.conf
    echo "// vps endpoint and zone managed by Director stage" >> /tmp/zones_deploy.conf
    cp /tmp/zones_deploy.conf /etc/icinga2/zones.conf
  '
  echo "   vps removed from zones.conf (Director manages it)"
else
  # Old style: ensure vps is in zones.conf
  if ! docker exec "$CNAME" grep -q 'object Endpoint "vps"' /etc/icinga2/zones.conf; then
    docker exec "$CNAME" bash -c 'cat >> /etc/icinga2/zones.conf << "ZONESEOF"

object Endpoint "vps" {
  host = "192.168.203.1"
  port = 5665
}

object Zone "vps" {
  endpoints = [ "vps" ]
  parent = "master"
}
ZONESEOF'
    echo "   vps added to zones.conf (stage has no endpoints.conf)"
  else
    echo "   zones.conf already has vps — ok."
  fi
fi

# Step 7: Validate and reload
echo ""
echo "6. Validating config..."
docker exec "$CNAME" icinga2 daemon --validate 2>&1 | grep -E "Finished|critical|Error" | head -5

echo ""
echo "7. Reloading icinga2..."
docker exec "$CNAME" /etc/init.d/icinga2 reload 2>&1
sleep 3
docker exec "$CNAME" /etc/init.d/icinga2 status 2>&1 | head -2

echo ""
echo "=== Done. Active stage: $(docker exec "$CNAME" cat $PKG_DIR/active-stage) ==="
