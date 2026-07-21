local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()
local dispatcher = require "luci.dispatcher"
local http = require "luci.http"

local node_id = arg[1]
local list_url = dispatcher.build_url("admin", "services", "passwall_snell")
if not node_id or uci:get("passwall_snell", node_id) ~= "node" then
	http.redirect(list_url)
end

local m = Map(
	"passwall_snell",
	translate("Snell node configuration")
)
m.apply_on_parse = false
m.redirect = list_url

local section = m:section(NamedSection, node_id, "node", "")
section.addremove = false
section.dynamic = false

local option = section:option(Value, "remarks", translate("Name"))
option.placeholder = translate("Snell node")
option.rmempty = true

option = section:option(Value, "server", translate("Server"))
option.datatype = "host"
option.rmempty = true

option = section:option(Value, "port", translate("Port"))
option.datatype = "port"
option.rmempty = true

option = section:option(Value, "psk", translate("PSK"))
option.password = true
option.rmempty = true

option = section:option(ListValue, "version", translate("Protocol version"))
option:value("1", "Snell v1")
option:value("2", "Snell v2")
option:value("3", "Snell v3")
option:value("4", "Snell v4")
option:value("5", "Snell v5")
option.default = "4"
option.rmempty = false

option = section:option(Flag, "udp", translate("UDP"))
option.default = 1
option:depends("version", "3")
option:depends("version", "4")
option:depends("version", "5")

option = section:option(Flag, "reuse", translate("Connection reuse"))
option.default = 1
option:depends("version", "2")
option:depends("version", "4")
option:depends("version", "5")

option = section:option(Flag, "tfo", "TCP Fast Open")
option.default = 1

option = section:option(ListValue, "obfs", translate("Obfuscation"))
option:value("none", translate("None"))
option:value("http", "HTTP")
option:value("tls", "TLS")
option:value("shadow-tls", "ShadowTLS")
option.default = "shadow-tls"
option.rmempty = false

option = section:option(Value, "obfs_host", translate("Obfuscation host"))
option:depends("obfs", "http")
option:depends("obfs", "tls")
option.rmempty = true

option = section:option(Value, "shadow_tls_password", "ShadowTLS password")
option.password = true
option:depends("obfs", "shadow-tls")
option.rmempty = true

option = section:option(Value, "shadow_tls_sni", "ShadowTLS SNI")
option.datatype = "host"
option:depends("obfs", "shadow-tls")
option.rmempty = true

option = section:option(ListValue, "shadow_tls_version", "ShadowTLS version")
option:value("1", "ShadowTLS v1")
option:value("2", "ShadowTLS v2")
option:value("3", "ShadowTLS v3")
option.default = "3"
option:depends("obfs", "shadow-tls")

m.on_after_apply = function()
	sys.call("/etc/init.d/passwall-snell restart >/dev/null 2>&1")
	sys.call("/etc/init.d/passwall restart >/dev/null 2>&1")
end

return m
