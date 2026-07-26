#!/bin/sh

UCI_BIN="${UCI_BIN:-uci}"
LOGGER_BIN="${LOGGER_BIN:-logger}"
BRIDGE_CONFIG="${BRIDGE_CONFIG:-passwall_snell}"
PASSWALL_CONFIG="${PASSWALL_CONFIG:-passwall}"
PASSWALL_CONFIG_FILE="${PASSWALL_CONFIG_FILE:-/etc/config/passwall}"
MAIN_SECTION="main"
NODE_PREFIX="passwall_snell_bridge"
MARKER_OPTION="passwall_snell_managed"
MARKER_VALUE="1"
LOCAL_PORT="17890"

passwall_dirty=0
bridge_dirty=0
managed_node=""

log() {
	"$LOGGER_BIN" -t passwall-snell "$*" >/dev/null 2>&1 || true
}

uci_get() {
	"$UCI_BIN" -q get "$1" 2>/dev/null
}

mark_dirty() {
	case "$1" in
		"$PASSWALL_CONFIG") passwall_dirty=1 ;;
		"$BRIDGE_CONFIG") bridge_dirty=1 ;;
	esac
}

set_value() {
	local config="$1"
	local key="$2"
	local value="$3"
	local current

	if current="$(uci_get "$key")" && [ "$current" = "$value" ]; then
		return 0
	fi
	"$UCI_BIN" -q set "${key}=${value}" || return 1
	mark_dirty "$config"
}

delete_value() {
	local config="$1"
	local key="$2"

	uci_get "$key" >/dev/null || return 0
	"$UCI_BIN" -q delete "$key" || return 1
	mark_dirty "$config"
}

commit_config() {
	local config="$1"
	local dirty=0

	case "$config" in
		"$PASSWALL_CONFIG") dirty="$passwall_dirty" ;;
		"$BRIDGE_CONFIG") dirty="$bridge_dirty" ;;
	esac
	[ "$dirty" = "1" ] || return 0
	"$UCI_BIN" -q commit "$config" || return 1
	case "$config" in
		"$PASSWALL_CONFIG") passwall_dirty=0 ;;
		"$BRIDGE_CONFIG") bridge_dirty=0 ;;
	esac
}

is_safe_section_name() {
	case "$1" in
		""|*[!A-Za-z0-9_]*) return 1 ;;
		*) return 0 ;;
	esac
}

is_managed_node() {
	local node="$1"

	is_safe_section_name "$node" || return 1
	[ "$(uci_get "${PASSWALL_CONFIG}.${node}.${MARKER_OPTION}")" = "$MARKER_VALUE" ]
}

list_managed_nodes() {
	"$UCI_BIN" -q show "$PASSWALL_CONFIG" 2>/dev/null |
		sed -n "s/^${PASSWALL_CONFIG}\.\([^.]*\)\.${MARKER_OPTION}='${MARKER_VALUE}'$/\1/p"
}

resolve_managed_node() {
	local candidate

	candidate="$(uci_get "${BRIDGE_CONFIG}.${MAIN_SECTION}.passwall_node")"
	if is_managed_node "$candidate"; then
		managed_node="$candidate"
		return 0
	fi

	candidate="$(uci_get "${PASSWALL_CONFIG}.@global[0].tcp_node")"
	if is_managed_node "$candidate"; then
		managed_node="$candidate"
		return 0
	fi

	for candidate in $(list_managed_nodes); do
		if is_managed_node "$candidate"; then
			managed_node="$candidate"
			return 0
		fi
	done
	return 1
}

choose_managed_node() {
	local candidate
	local index=0

	if resolve_managed_node; then
		return 0
	fi

	while [ "$index" -lt 100 ]; do
		if [ "$index" -eq 0 ]; then
			candidate="$NODE_PREFIX"
		else
			candidate="${NODE_PREFIX}_${index}"
		fi
		if ! uci_get "${PASSWALL_CONFIG}.${candidate}" >/dev/null; then
			managed_node="$candidate"
			return 0
		fi
		index=$((index + 1))
	done
	return 1
}

ensure_managed_node() {
	choose_managed_node || {
		log "Unable to allocate a managed PassWall node name"
		return 1
	}

	set_value "$PASSWALL_CONFIG" "${PASSWALL_CONFIG}.${managed_node}" "nodes" || return 1
	set_value "$PASSWALL_CONFIG" "${PASSWALL_CONFIG}.${managed_node}.remarks" "PassWall Snell Bridge (managed)" || return 1
	set_value "$PASSWALL_CONFIG" "${PASSWALL_CONFIG}.${managed_node}.type" "V2ray" || return 1
	set_value "$PASSWALL_CONFIG" "${PASSWALL_CONFIG}.${managed_node}.protocol" "socks" || return 1
	set_value "$PASSWALL_CONFIG" "${PASSWALL_CONFIG}.${managed_node}.address" "127.0.0.1" || return 1
	set_value "$PASSWALL_CONFIG" "${PASSWALL_CONFIG}.${managed_node}.port" "$LOCAL_PORT" || return 1
	set_value "$PASSWALL_CONFIG" "${PASSWALL_CONFIG}.${managed_node}.tls" "0" || return 1
	set_value "$PASSWALL_CONFIG" "${PASSWALL_CONFIG}.${managed_node}.transport" "tcp" || return 1
	set_value "$PASSWALL_CONFIG" "${PASSWALL_CONFIG}.${managed_node}.mux" "0" || return 1
	set_value "$PASSWALL_CONFIG" "${PASSWALL_CONFIG}.${managed_node}.${MARKER_OPTION}" "$MARKER_VALUE" || return 1
	commit_config "$PASSWALL_CONFIG" || return 1

	set_value "$BRIDGE_CONFIG" "${BRIDGE_CONFIG}.${MAIN_SECTION}.passwall_node" "$managed_node" || return 1
	commit_config "$BRIDGE_CONFIG"
}

bridge_is_ready() {
	local active_node
	local server
	local port
	local psk
	local obfs

	[ "$(uci_get "${BRIDGE_CONFIG}.${MAIN_SECTION}.enabled")" = "1" ] || return 1
	active_node="$(uci_get "${BRIDGE_CONFIG}.${MAIN_SECTION}.active_node")"
	is_safe_section_name "$active_node" || return 1
	[ "$(uci_get "${BRIDGE_CONFIG}.${active_node}")" = "node" ] || return 1
	server="$(uci_get "${BRIDGE_CONFIG}.${active_node}.server")"
	port="$(uci_get "${BRIDGE_CONFIG}.${active_node}.port")"
	psk="$(uci_get "${BRIDGE_CONFIG}.${active_node}.psk")"
	[ -n "$server" ] && [ -n "$port" ] && [ -n "$psk" ] || return 1
	case "$port" in
		*[!0-9]*) return 1 ;;
	esac
	[ "$port" -ge 1 ] 2>/dev/null && [ "$port" -le 65535 ] 2>/dev/null || return 1

	obfs="$(uci_get "${BRIDGE_CONFIG}.${active_node}.obfs")"
	if [ "$obfs" = "shadow-tls" ]; then
		[ -n "$(uci_get "${BRIDGE_CONFIG}.${active_node}.shadow_tls_password")" ] || return 1
		[ -n "$(uci_get "${BRIDGE_CONFIG}.${active_node}.shadow_tls_sni")" ] || return 1
	fi
	return 0
}

save_passwall_option() {
	local option="$1"
	local saved_option="$2"
	local present_option="$3"
	local value

	if value="$(uci_get "${PASSWALL_CONFIG}.@global[0].${option}")"; then
		set_value "$BRIDGE_CONFIG" "${BRIDGE_CONFIG}.${MAIN_SECTION}.${saved_option}" "$value" || return 1
		set_value "$BRIDGE_CONFIG" "${BRIDGE_CONFIG}.${MAIN_SECTION}.${present_option}" "1" || return 1
	else
		delete_value "$BRIDGE_CONFIG" "${BRIDGE_CONFIG}.${MAIN_SECTION}.${saved_option}" || return 1
		set_value "$BRIDGE_CONFIG" "${BRIDGE_CONFIG}.${MAIN_SECTION}.${present_option}" "0" || return 1
	fi
}

restore_passwall_option() {
	local option="$1"
	local saved_option="$2"
	local present_option="$3"
	local value

	if [ "$(uci_get "${BRIDGE_CONFIG}.${MAIN_SECTION}.${present_option}")" = "1" ]; then
		value="$(uci_get "${BRIDGE_CONFIG}.${MAIN_SECTION}.${saved_option}")"
		set_value "$PASSWALL_CONFIG" "${PASSWALL_CONFIG}.@global[0].${option}" "$value"
	else
		delete_value "$PASSWALL_CONFIG" "${PASSWALL_CONFIG}.@global[0].${option}"
	fi
}

activate_integration() {
	[ "$(uci_get "${PASSWALL_CONFIG}.@global[0]")" = "global" ] || {
		log "PassWall global settings are unavailable"
		return 1
	}

	if [ "$(uci_get "${BRIDGE_CONFIG}.${MAIN_SECTION}.integration_active")" != "1" ]; then
		save_passwall_option "tcp_node" "saved_tcp_node" "saved_tcp_node_present" || return 1
		save_passwall_option "udp_node" "saved_udp_node" "saved_udp_node_present" || return 1
		set_value "$BRIDGE_CONFIG" "${BRIDGE_CONFIG}.${MAIN_SECTION}.integration_active" "1" || return 1
		commit_config "$BRIDGE_CONFIG" || return 1
	fi

	set_value "$PASSWALL_CONFIG" "${PASSWALL_CONFIG}.@global[0].tcp_node" "$managed_node" || return 1
	set_value "$PASSWALL_CONFIG" "${PASSWALL_CONFIG}.@global[0].udp_node" "tcp" || return 1
	commit_config "$PASSWALL_CONFIG"
}

clear_saved_state() {
	delete_value "$BRIDGE_CONFIG" "${BRIDGE_CONFIG}.${MAIN_SECTION}.integration_active" || return 1
	delete_value "$BRIDGE_CONFIG" "${BRIDGE_CONFIG}.${MAIN_SECTION}.saved_tcp_node" || return 1
	delete_value "$BRIDGE_CONFIG" "${BRIDGE_CONFIG}.${MAIN_SECTION}.saved_tcp_node_present" || return 1
	delete_value "$BRIDGE_CONFIG" "${BRIDGE_CONFIG}.${MAIN_SECTION}.saved_udp_node" || return 1
	delete_value "$BRIDGE_CONFIG" "${BRIDGE_CONFIG}.${MAIN_SECTION}.saved_udp_node_present" || return 1
}

deactivate_integration() {
	local current_tcp
	local current_udp

	[ "$(uci_get "${BRIDGE_CONFIG}.${MAIN_SECTION}.integration_active")" = "1" ] || return 0
	current_tcp="$(uci_get "${PASSWALL_CONFIG}.@global[0].tcp_node")"
	current_udp="$(uci_get "${PASSWALL_CONFIG}.@global[0].udp_node")"
	if [ -n "$managed_node" ] && [ "$current_tcp" = "$managed_node" ]; then
		restore_passwall_option "tcp_node" "saved_tcp_node" "saved_tcp_node_present" || return 1
		if [ "$current_udp" = "tcp" ]; then
			restore_passwall_option "udp_node" "saved_udp_node" "saved_udp_node_present" || return 1
		fi
	fi
	commit_config "$PASSWALL_CONFIG" || return 1
	clear_saved_state || return 1
	commit_config "$BRIDGE_CONFIG"
}

remove_managed_nodes() {
	local node

	for node in $(list_managed_nodes); do
		is_managed_node "$node" || continue
		delete_value "$PASSWALL_CONFIG" "${PASSWALL_CONFIG}.${node}" || return 1
	done
	commit_config "$PASSWALL_CONFIG"
}

cleanup_integration() {
	resolve_managed_node || managed_node=""
	deactivate_integration || return 1
	remove_managed_nodes || return 1
	delete_value "$BRIDGE_CONFIG" "${BRIDGE_CONFIG}.${MAIN_SECTION}.passwall_node" || return 1
	commit_config "$BRIDGE_CONFIG"
}

sync_integration() {
	[ -e "$PASSWALL_CONFIG_FILE" ] || {
		log "PassWall configuration is unavailable"
		return 1
	}
	ensure_managed_node || return 1
	if bridge_is_ready; then
		activate_integration
	else
		deactivate_integration
	fi
}

case "${1:-sync}" in
	sync) sync_integration ;;
	cleanup) cleanup_integration ;;
	*) echo "Usage: $0 [sync|cleanup]" >&2; exit 2 ;;
esac
