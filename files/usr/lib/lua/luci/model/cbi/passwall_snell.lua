local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()
local dispatcher = require "luci.dispatcher"
local http = require "luci.http"

local function first_section(config, section_type)
	local name
	uci:foreach(config, section_type, function(section)
		if not name then
			name = section[".name"]
		end
	end)
	return name
end

local function restart_services()
	sys.call("/etc/init.d/passwall-snell restart >/dev/null 2>&1")
	sys.call("/etc/init.d/passwall restart >/dev/null 2>&1")
end

local m = Map(
	"passwall_snell",
	translate("PassWall Snell Bridge"),
	translate("Runs Mihomo in RAM as a Snell client and exposes SOCKS5 on 127.0.0.1:17890 for PassWall. The core is downloaded and SHA-256 verified after each reboot.")
)
m.apply_on_parse = false

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

local activate_node = main:option(Button, "_activate_node", translate("Switch node"))
activate_node.inputtitle = translate("Activate")
activate_node.inputstyle = "apply"
function activate_node.cfgvalue()
	return node_count > 0
end
function activate_node.write()
	local selected = http.formvalue("cbid.passwall_snell.main.active_node")
	if selected and uci:get("passwall_snell", selected) == "node" then
		uci:set("passwall_snell", "main", "active_node", selected)
		uci:commit("passwall_snell")
		restart_services()
	end
	http.redirect(dispatcher.build_url("admin", "services", "passwall_snell"))
end

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
	translate("Add nodes here, then choose one in Active node. Open a row to view or change its full configuration.")
)
nodes.anonymous = true
nodes.addremove = true
nodes.sortable = true
nodes.template = "cbi/tblsection"
nodes.extedit = dispatcher.build_url("admin", "services", "passwall_snell", "node", "%s")
nodes.addbtntitle = translate("Add Snell node")
function nodes.create(self, section_id)
	local created = TypedSection.create(self, section_id)
	if not m:get("main", "active_node") then
		m:set("main", "active_node", created)
	end
	http.redirect(self.extedit:format(created))
end

function nodes.remove(self, section_id)
	TypedSection.remove(self, section_id)
	if m:get("main", "active_node") == section_id then
		local first = m:get("@node[0]")
		m:set("main", "active_node", first and first[".name"] or "")
	end
end

option = nodes:option(DummyValue, "_active", translate("Status"))
function option.cfgvalue(self, section_id)
	if m:get("main", "active_node") == section_id then
		return translate("Active")
	end
	return ""
end

option = nodes:option(DummyValue, "remarks", translate("Name"))

option = nodes:option(DummyValue, "server", translate("Server"))

option = nodes:option(DummyValue, "port", translate("Port"))

option = nodes:option(DummyValue, "_protocol", translate("Protocol"))
function option.cfgvalue(self, section_id)
	return "Snell v" .. (m:get(section_id, "version") or "4")
end

option = nodes:option(DummyValue, "obfs", translate("Obfuscation"))

m.on_after_apply = function()
	restart_services()
end

return m
