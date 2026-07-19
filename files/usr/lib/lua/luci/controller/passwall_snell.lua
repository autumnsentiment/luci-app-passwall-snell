module("luci.controller.passwall_snell", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/passwall_snell") then
		return
	end

	local page = entry(
		{"admin", "services", "passwall_snell"},
		cbi("passwall_snell"),
		_("PassWall Snell Bridge"),
		59
	)
	page.dependent = true
end
