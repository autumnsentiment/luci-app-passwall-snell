local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()

local function first_section(config, section_type)
	local name
	uci:foreach(config, section_type, function(section)
		if not name then
			name = section[".name"]
		end
	end)
	return name
end

local m = Map(
	"passwall_snell",
	translate("PassWall Snell Bridge"),
	translate("Runs Mihomo in RAM as a Snell client and exposes SOCKS5 on 127.0.0.1:17890 for PassWall. The core is downloaded and SHA-256 verified after each reboot.")
)

local status = m:section(SimpleSection)
local state = status:option(DummyValue, "_status", translate("Status"))
state.rawhtml = true
function state.cfgvalue()
	if sys.call("pgrep -f '^/tmp/passwall-snell/mihomo .*config.json' >/dev/null 2>&1") == 0 then
		return '<span style="color:#2e7d32">' .. translate("Running") .. '</span>'
	end
	return '<span style="color:#c62828">' .. translate("Stopped") .. '</span>'
end

local main = m:section(NamedSection, "main", "main", translate("General settings"))
main.addremove = false

local option = main:option(Flag, "enabled", translate("Enable"))
option.default = 0
option.rmempty = false

local active_node = main:option(
	ListValue,
	"active_node",
	translate("Active node"),
	translate("Add and save a node before selecting it here.")
)
local node_count = 0
uci:foreach("passwall_snell", "node", function(node)
	local label = node.remarks
	if not label or label == "" then
		label = node.server or node[".name"]
	end
	active_node:value(node[".name"], label)
	node_count = node_count + 1
end)
if node_count == 0 then
	active_node:value("", translate("No nodes configured"))
end
active_node.rmempty = node_count == 0

option = main:option(
	Flag,
	"_ipv6_proxy",
	translate("IPv6 proxy (PassWall TProxy)"),
	translate("Enable only when the Snell server has working IPv6 egress. When disabled, proxy-domain AAAA records are filtered to keep clients on IPv4.")
)
option.default = 0
option.rmempty = false
function option.cfgvalue()
	local forwarding = first_section("passwall", "global_forwarding")
	return forwarding and uci:get("passwall", forwarding, "ipv6_tproxy") or "0"
end
function option.write(self, section_id, value)
	local enabled = value == "1" and "1" or "0"
	local forwarding = first_section("passwall", "global_forwarding")
	local global = first_section("passwall", "global")
	if forwarding then
		uci:set("passwall", forwarding, "ipv6_tproxy", enabled)
		uci:set("passwall", forwarding, "tcp_proxy_way", enabled == "1" and "tproxy" or "redirect")
	end
	if global then
		uci:set("passwall", global, "filter_proxy_ipv6", enabled == "1" and "0" or "1")
	end
	uci:commit("passwall")
end

local nodes = m:section(
	TypedSection,
	"node",
	translate("Snell nodes"),
	translate("Add multiple nodes here, then choose one in Active node. Switching nodes restarts the bridge and PassWall.")
)
nodes.anonymous = true
nodes.addremove = true
nodes.sortable = true
nodes.addbtntitle = translate("Add Snell node")

option = nodes:option(Value, "remarks", translate("Name"))
option.placeholder = translate("Snell node")
option.rmempty = true

option = nodes:option(Value, "server", translate("Server"))
option.datatype = "host"
option.rmempty = true

option = nodes:option(Value, "port", translate("Port"))
option.datatype = "port"
option.rmempty = true

option = nodes:option(Value, "psk", translate("PSK"))
option.password = true
option.rmempty = true

option = nodes:option(ListValue, "version", translate("Protocol version"))
option:value("1", "Snell v1")
option:value("2", "Snell v2")
option:value("3", "Snell v3")
option:value("4", "Snell v4")
option:value("5", "Snell v5")
option.default = "4"
option.rmempty = false

option = nodes:option(Flag, "udp", translate("UDP"))
option.default = 1
option:depends("version", "3")
option:depends("version", "4")
option:depends("version", "5")

option = nodes:option(Flag, "reuse", translate("Connection reuse"))
option.default = 1
option:depends("version", "2")
option:depends("version", "4")
option:depends("version", "5")

option = nodes:option(Flag, "tfo", "TCP Fast Open")
option.default = 1

option = nodes:option(ListValue, "obfs", translate("Obfuscation"))
option:value("none", translate("None"))
option:value("http", "HTTP")
option:value("tls", "TLS")
option:value("shadow-tls", "ShadowTLS")
option.default = "shadow-tls"
option.rmempty = false

option = nodes:option(Value, "obfs_host", translate("Obfuscation host"))
option:depends("obfs", "http")
option:depends("obfs", "tls")
option.rmempty = true

option = nodes:option(Value, "shadow_tls_password", "ShadowTLS password")
option.password = true
option:depends("obfs", "shadow-tls")
option.rmempty = true

option = nodes:option(Value, "shadow_tls_sni", "ShadowTLS SNI")
option.datatype = "host"
option:depends("obfs", "shadow-tls")
option.rmempty = true

option = nodes:option(ListValue, "shadow_tls_version", "ShadowTLS version")
option:value("1", "ShadowTLS v1")
option:value("2", "ShadowTLS v2")
option:value("3", "ShadowTLS v3")
option.default = "3"
option:depends("obfs", "shadow-tls")

m.on_after_commit = function()
	sys.call("(/etc/init.d/passwall-snell restart; sleep 1; /etc/init.d/passwall restart) >/dev/null 2>&1 &")
end

return m
