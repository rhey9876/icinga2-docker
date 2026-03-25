#!/bin/bash
# check_rpi_temp.sh — Nagios/Icinga2 plugin for Raspberry Pi CPU temperature
# Reads /sys/class/thermal/thermal_zone0/temp (millidegrees Celsius)
# Usage: check_rpi_temp.sh [-w warn] [-c crit]
# Defaults: warn=65, crit=75

WARN=65
CRIT=75

while getopts "w:c:" opt; do
    case $opt in
        w) WARN=$OPTARG ;;
        c) CRIT=$OPTARG ;;
    esac
done

TEMP_FILE=/sys/class/thermal/thermal_zone0/temp
if [ ! -r "$TEMP_FILE" ]; then
    echo "UNKNOWN: Cannot read $TEMP_FILE"
    exit 3
fi

RAW=$(cat "$TEMP_FILE")
# Convert millidegrees to degrees with one decimal
TEMP=$(awk "BEGIN {printf \"%.1f\", $RAW/1000}")

if awk "BEGIN {exit !($TEMP >= $CRIT)}"; then
    echo "CRITICAL: CPU temp ${TEMP}°C | temp=${TEMP};${WARN};${CRIT};0;"
    exit 2
elif awk "BEGIN {exit !($TEMP >= $WARN)}"; then
    echo "WARNING: CPU temp ${TEMP}°C | temp=${TEMP};${WARN};${CRIT};0;"
    exit 1
else
    echo "OK: CPU temp ${TEMP}°C | temp=${TEMP};${WARN};${CRIT};0;"
    exit 0
fi
