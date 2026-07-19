#!/bin/sh

. /lib/functions.sh
. /usr/share/libubox/jshn.sh

SERVICE_NAME="passwall-snell"
RUNTIME_DIR="/tmp/passwall-snell"
CORE="$RUNTIME_DIR/mihomo"
CORE_GZ="$RUNTIME_DIR/mihomo.gz"
CORE_TMP="$RUNTIME_DIR/mihomo.tmp"
CONFIG_FILE="$RUNTIME_DIR/config.json"
PID_FILE="/var/run/passwall-snell.pid"
MIGRATOR="/usr/share/passwall-snell/migrate-config.sh"
LOCAL_PORT=17890
MIHOMO_VERSION="1.19.28"
MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/v${MIHOMO_VERSION}/mihomo-linux-arm64-v${MIHOMO_VERSION}.gz"
MIHOMO_SHA256="2474450cd1c41dfa53036a54a4e85579f493d3af524d86c3d4b8e2b240b56cd2"

log() {
	logger -t "$SERVICE_NAME" "$*"
}

collect_node() {
	[ -n "$first_node" ] || first_node="$1"
	[ "$1" = "$active_node" ] && selected_node="$1"
}

load_settings() {
	local legacy_server

	[ ! -x "$MIGRATOR" ] || "$MIGRATOR" >/dev/null 2>&1
	config_load passwall_snell
	config_get active_node main active_node
	first_node=""
	selected_node=""
	config_foreach collect_node node
	[ -n "$selected_node" ] || selected_node="$first_node"

	if [ -z "$selected_node" ]; then
		config_get legacy_server main server
		[ -z "$legacy_server" ] || selected_node="main"
	fi
	if [ -z "$selected_node" ]; then
		log "No Snell node is configured"
		return 1
	fi

	config_get node_remarks "$selected_node" remarks "$selected_node"
	config_get server "$selected_node" server
	config_get port "$selected_node" port
	config_get psk "$selected_node" psk
	config_get version "$selected_node" version 4
	config_get_bool udp "$selected_node" udp 1
	config_get_bool reuse "$selected_node" reuse 1
	config_get_bool tfo "$selected_node" tfo 1
	config_get obfs "$selected_node" obfs none
	config_get obfs_host "$selected_node" obfs_host
	config_get shadow_tls_password "$selected_node" shadow_tls_password
	config_get shadow_tls_sni "$selected_node" shadow_tls_sni
	config_get shadow_tls_version "$selected_node" shadow_tls_version 3

	case "$version" in
		1|2) udp=0 ;;
		3|4|5) ;;
		*) version=4 ;;
	esac
}

check_architecture() {
	case "$(uname -m)" in
		aarch64|arm64) return 0 ;;
		*)
			log "Unsupported architecture: $(uname -m). Release v1.0.0 supports arm64 only"
			return 1
			;;
	esac
}

download_core_once() {
	rm -f "$CORE_GZ" "$CORE_TMP"
	log "Downloading Mihomo v${MIHOMO_VERSION} to RAM"
	curl -fL --connect-timeout 15 --retry 2 --retry-delay 2 -o "$CORE_GZ" "$MIHOMO_URL" || return 1
	echo "$MIHOMO_SHA256  $CORE_GZ" | sha256sum -c - >/dev/null 2>&1 || return 1
	gzip -dc "$CORE_GZ" > "$CORE_TMP" || return 1
	chmod 0755 "$CORE_TMP"
	"$CORE_TMP" -v >/dev/null 2>&1 || return 1
	mv "$CORE_TMP" "$CORE"
	rm -f "$CORE_GZ"
	return 0
}

ensure_core() {
	mkdir -p "$RUNTIME_DIR"
	if [ -x "$CORE" ] && "$CORE" -v >/dev/null 2>&1; then
		return 0
	fi

	while ! download_core_once; do
		log "Mihomo download or verification failed; retrying in 30 seconds"
		rm -f "$CORE_GZ" "$CORE_TMP"
		sleep 30
	done
}

build_config() {
	local udp_value reuse_value tfo_value
	[ "$udp" = "1" ] && udp_value=1 || udp_value=0
	[ "$reuse" = "1" ] && reuse_value=1 || reuse_value=0
	[ "$tfo" = "1" ] && tfo_value=1 || tfo_value=0

	json_init
	json_add_int "mixed-port" "$LOCAL_PORT"
	json_add_boolean "allow-lan" 0
	json_add_string "bind-address" "127.0.0.1"
	json_add_string "mode" "rule"
	json_add_string "log-level" "warning"

	json_add_array "proxies"
	json_add_object ""
	json_add_string "name" "snell-out"
	json_add_string "type" "snell"
	json_add_string "server" "$server"
	json_add_int "port" "$port"
	json_add_string "psk" "$psk"
	json_add_int "version" "$version"
	json_add_boolean "udp" "$udp_value"
	json_add_boolean "reuse" "$reuse_value"
	json_add_boolean "tfo" "$tfo_value"
	if [ "$obfs" = "http" ] || [ "$obfs" = "tls" ]; then
		json_add_object "obfs-opts"
		json_add_string "mode" "$obfs"
		[ -n "$obfs_host" ] && json_add_string "host" "$obfs_host"
		json_close_object
	elif [ "$obfs" = "shadow-tls" ]; then
		json_add_object "obfs-opts"
		json_add_string "mode" "shadow-tls"
		json_add_string "password" "$shadow_tls_password"
		json_add_string "host" "$shadow_tls_sni"
		json_add_int "version" "$shadow_tls_version"
		json_close_object
	fi
	json_close_object
	json_close_array

	json_add_array "proxy-groups"
	json_add_object ""
	json_add_string "name" "SNELL"
	json_add_string "type" "select"
	json_add_array "proxies"
	json_add_string "" "snell-out"
	json_close_array
	json_close_object
	json_close_array

	json_add_array "rules"
	json_add_string "" "MATCH,SNELL"
	json_close_array

	json_dump > "$CONFIG_FILE.tmp"
	mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
	chmod 0600 "$CONFIG_FILE"
}

load_settings || exit 1
if [ -z "$server" ] || [ -z "$port" ] || [ -z "$psk" ]; then
	log "Node ${node_remarks}: server, port, and PSK must be configured"
	exit 1
fi
if [ "$obfs" = "shadow-tls" ] && { [ -z "$shadow_tls_password" ] || [ -z "$shadow_tls_sni" ]; }; then
	log "Node ${node_remarks}: ShadowTLS password and SNI must be configured"
	exit 1
fi
check_architecture || exit 1

ensure_core
build_config

if [ "${1:-}" = "--check" ]; then
	exec "$CORE" -t -f "$CONFIG_FILE"
fi

echo $$ > "$PID_FILE"
log "Starting node ${node_remarks} on 127.0.0.1:${LOCAL_PORT}"
exec "$CORE" -f "$CONFIG_FILE"
