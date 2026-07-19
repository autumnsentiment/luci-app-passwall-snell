#!/bin/sh

. /lib/functions.sh

CONFIG="passwall_snell"
MAIN_SECTION="main"

inspect_node() {
	[ -n "$first_node" ] || first_node="$1"
	[ "$1" = "$active_node" ] && active_exists=1
}

copy_option() {
	local option="$1"
	local value

	config_get value "$MAIN_SECTION" "$option"
	[ -z "$value" ] || uci -q set "${CONFIG}.${new_node}.${option}=${value}"
}

config_load "$CONFIG"
config_get active_node "$MAIN_SECTION" active_node
first_node=""
active_exists=0
config_foreach inspect_node node

if [ -n "$first_node" ]; then
	if [ "$active_exists" != "1" ]; then
		uci -q set "${CONFIG}.${MAIN_SECTION}.active_node=${first_node}"
		uci -q commit "$CONFIG"
	fi
	chmod 0600 "/etc/config/${CONFIG}"
	exit 0
fi

config_get legacy_server "$MAIN_SECTION" server
config_get legacy_port "$MAIN_SECTION" port
config_get legacy_psk "$MAIN_SECTION" psk
[ -n "$legacy_server" ] && [ -n "$legacy_port" ] && [ -n "$legacy_psk" ] || exit 0

new_node="$(uci -q add "$CONFIG" node)" || exit 1
uci -q set "${CONFIG}.${new_node}.remarks=Migrated node"
for option in server port psk version udp reuse tfo obfs obfs_host shadow_tls_password shadow_tls_sni shadow_tls_version; do
	copy_option "$option"
done
uci -q set "${CONFIG}.${MAIN_SECTION}.active_node=${new_node}"
uci -q set "${CONFIG}.${MAIN_SECTION}.schema_version=2"
uci -q commit "$CONFIG" || exit 1
chmod 0600 "/etc/config/${CONFIG}"
logger -t passwall-snell "Migrated the legacy Snell configuration into node ${new_node}"
