-- Guild Masters R Us - Export tab (copyable text for spreadsheets) and restore points.
local _, GM = ...
local L = GM.L
local U = GM.U
local UI = GM.UI

local what, delim = "members", "\t"
local WHAT = {
	{ "members", L["Members"] }, { "former", L["Former members"] }, { "log", L["Log"] }, { "bans", L["Ban list"] },
}
local DELIMS = { { "\t", L["Tab (Excel, Google Sheets)"] }, { ",", L["Comma (CSV)"] }, { ";", L["Semicolon"] } }

local function Label(list, v)
	for _, x in ipairs(list) do if x[1] == v then return x[2] end end
	return "?"
end

local function Build(f)
	f.body = CreateFrame("Frame", nil, f)
	f.body:SetAllPoints()
	local b = f.body
	local dWhat = UI.Dropdown(b, 150, function() return Label(WHAT, what) end, function(root, refresh)
		for _, x in ipairs(WHAT) do root:CreateRadio(x[2], function() return what == x[1] end, function() what = x[1] refresh() end) end
	end)
	dWhat:SetPoint("TOPLEFT", 4, -1)
	local dDelim = UI.Dropdown(b, 200, function() return Label(DELIMS, delim) end, function(root, refresh)
		for _, x in ipairs(DELIMS) do root:CreateRadio(x[2], function() return delim == x[1] end, function() delim = x[1] refresh() end) end
	end)
	dDelim:SetPoint("LEFT", dWhat, "RIGHT", 6, 0)
	local go = UI.Button(b, L["Make export"], 110, 22, function()
		local G = GM.G
		if not G then return end
		local fn = ({ members = GM.Export.Members, former = GM.Export.Former, log = GM.Export.Log, bans = GM.Export.Bans })[what]
		local text, n = fn(G, delim)
		f.box.edit:SetText(text)
		f.box.edit:SetFocus()
		f.box.edit:HighlightText()
		f.info:SetText(L["%d rows. Press Ctrl+C to copy, then paste into a spreadsheet."]:format(n))
	end)
	go:SetPoint("LEFT", dDelim, "RIGHT", 6, 0)
	f.info = UI.Text(b, "", "GameFontHighlightSmall")
	f.info:SetPoint("LEFT", go, "RIGHT", 10, 0)

	f.box = UI.MultiLine(b, 520, 300)
	f.box:SetPoint("TOPLEFT", 8, -34)
	f.box:SetPoint("BOTTOMLEFT", 8, 8)

	-- restore points
	local head = UI.Text(b, L["Restore points"], "GameFontNormal")
	head:SetPoint("TOPLEFT", f.box, "TOPRIGHT", 36, 0)
	local hint = UI.Text(b, L["A snapshot of this guild's member data (dates, alts, bans, rules). The log isn't included. One is made automatically each week."], "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
	hint:SetPoint("RIGHT", -6, 0)
	local save = UI.Button(b, L["Save restore point"], 150, 22, function()
		GM.Backup.Save(GM.G, L["Manual"])
		UI.QueueRefresh()
	end)
	save:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
	local list = UI.List(b, {
		{ key = "t", title = L["Saved"], width = 110 },
		{ key = "label", title = L["Type"], width = 90 },
		{ key = "n", title = L["Members"], width = 60 },
	})
	list:SetPoint("TOPLEFT", save, "BOTTOMLEFT", -4, -6)
	list:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 40)
	list.onClick = function(row) list:Select(row) end
	list.keyOf = function(row) return row.b end
	f.backups = list
	local restore = UI.Button(b, L["Restore"], 90, 22, function()
		local sel = list.selected
		if not sel then GM:Print(L["Select a restore point first."]) return end
		UI.Confirm(L["Replace this guild's saved member data with the restore point from %s?"]:format(date("%Y-%m-%d %H:%M", sel.b.t)), function()
			GM.Backup.Restore(GM.G, sel.i)
		end)
	end)
	restore:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 4, -30)
	local del = UI.Button(b, L["Delete"], 80, 22, function()
		local sel = list.selected
		if sel then GM.Backup.Delete(GM.G, sel.i) list:Select(nil) UI.QueueRefresh() end
	end)
	del:SetPoint("LEFT", restore, "RIGHT", 4, 0)
	local reset = UI.Button(b, "|cffff5555" .. L["Reset guild data"] .. "|r", 130, 22, function() GM.commands.resetguild() end)
	reset:SetPoint("LEFT", del, "RIGHT", 4, 0)
end

local function Refresh(f, G)
	if not UI.GuildReady(f, G) then return end
	local rows = {}
	for i, b in ipairs(GM.Backup.List(G)) do rows[#rows + 1] = { i = i, b = b } end
	f.backups:SetRows(rows, function(r)
		return { date("%Y-%m-%d %H:%M", r.b.t), r.b.label or "", tostring(r.b.members or "?") }
	end)
end

UI.RegisterTab({ id = "export", title = L["Export"], order = 8, build = Build, refresh = Refresh })
