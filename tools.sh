#!/bin/bash

# Usage: notify_zabbix <level> <message>
# Level: 0 = OK/Cancel, 1 = Error (High), 2 = Warning (Average)
notify_zabbix() {
    local LEVEL=$1
    local MSG=$2
    local ZABBIX_SERVER="127.0.0.1" # Change to your actual Zabbix IP
    local HOSTNAME="ant-rpi"    # Should match host in Zabbix
    
    # Map levels to Zabbix status or severity
    # We send the level as a value to a specific 'trapper' item
    zabbix_sender -z "$ZABBIX_SERVER" -s "$HOSTNAME" -k "station.status.level" -o "$LEVEL"
    zabbix_sender -z "$ZABBIX_SERVER" -s "$HOSTNAME" -k "station.status.msg" -o "$MSG"
}
