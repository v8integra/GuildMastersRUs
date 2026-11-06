-- Guild Masters R Us - Sync tab: who's running the addon, and the guild master's guild-wide settings.
local _, GM = ...
local L = GM.L
local U = GM.U
local UI = GM.UI
local Sync = GM.Sync

local draft = {}

local function RankName(G, order)
	return order and ((G.rankNames and G.rankNames[order]) or ("#" .. order)) or "?"
end

local function RankPicker(parent, label, key)
	local t = UI.Text(parent, label, "GameFontHighlightSmall")
	local dd = UI.Dropdown(parent, 150, function()
		local G = GM.G
		return G and RankName(G, draft[key]) or "?"
	end, function(root, refresh)
		local G = GM.G
		for i, name in ipairs(G and G.rankNames or {}) do
			root:CreateRadio(i .. ". " .. name .. (i > 1 and (" " .. L["and higher"]) or ""), function() return draft[key] == i end, function() draft[key] = i refresh() end)
		end
	end)
	dd:SetPoint("LEFT", t, "RIGHT", 8, 0)
	return t, dd
end

local function LoadDraft(G)
	local gs = G.guildSettings or {}
	local s = GM.settings
	draft = {
		syncMinRank = gs.syncMinRank or s.syncMinRank,
		banMinRank = gs.banMinRank or s.syncBanMinRank,
		customMinRank = gs.customMinRank or s.syncCustomMinRank,
		joinNote = gs.joinNote or s.joinNote,
		dateFormat = gs.dateFormat or s.dateFormat,
	}
end

local function Build(f)
	f.body = CreateFrame("Frame", nil, f)
	f.body:SetAllPoints()
	local b = f.body

	f.enable = UI.Check(b, L["Sync with guildmates"], function(v) GM.settings.syncEnabled = v UI.QueueRefresh() end)
	f.enable:SetPoint("TOPLEFT", 4, 0)
	local now = UI.Button(b, L["Sync now"], 100, 22, function() Sync.Hello(true) end)
	now:SetPoint("LEFT", f.enable.label, "RIGHT", 14, 0)
	f.msgs = UI.Check(b, L["Show sync messages"], function(v) GM.settings.syncMessages = v end)
	f.msgs:SetPoint("LEFT", now, "RIGHT", 14, 0)
	f.mine = UI.Text(b, "", "GameFontHighlightSmall")
	f.mine:SetPoint("TOPLEFT", 6, -28)
	f.mine:SetPoint("RIGHT", -6, 0)

	local list = UI.List(b, {
		{ key = "name", title = L["Addon user"], width = 160 },
		{ key = "ver", title = L["Version"], width = 100 },
		{ key = "rank", title = L["Rank"], width = 120 },
		{ key = "status", title = L["Status"], width = 200 },
	})
	list:SetPoint("TOPLEFT", 0, -46)
	list:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 120)
	f.list = list

	local head = UI.Text(b, L["Guild-wide settings (set by the guild master, used by everyone running the addon)"], "GameFontNormal")
	head:SetPoint("BOTTOMLEFT", 6, 100)
	f.gsInfo = UI.Text(b, "", "GameFontDisableSmall")
	f.gsInfo:SetPoint("LEFT", head, "RIGHT", 10, 0)

	local t1, d1 = RankPicker(b, L["Join/promo dates, alts, birthdays:"], "syncMinRank")
	t1:SetPoint("BOTTOMLEFT", 8, 74)
	local t2, d2 = RankPicker(b, L["Ban list:"], "banMinRank")
	t2:SetPoint("BOTTOMLEFT", 380, 74)
	local t3, d3 = RankPicker(b, L["Custom notes:"], "customMinRank")
	t3:SetPoint("BOTTOMLEFT", 8, 46)

	local t4 = UI.Text(b, L["Join date in note:"], "GameFontHighlightSmall")
	t4:SetPoint("BOTTOMLEFT", 380, 46)
	local where = UI.Dropdown(b, 110, function()
		return ({ off = L["Off"], public = L["Public note"], officer = L["Officer note"] })[draft.joinNote or "off"] or L["Off"]
	end, function(root, refresh)
		for _, opt in ipairs({ { "off", L["Off"] }, { "public", L["Public note"] }, { "officer", L["Officer note"] } }) do
			root:CreateRadio(opt[2], function() return draft.joinNote == opt[1] end, function() draft.joinNote = opt[1] refresh() end)
		end
	end)
	where:SetPoint("LEFT", t4, "RIGHT", 8, 0)
	local fmt = UI.Dropdown(b, 110, function()
		for _, d in ipairs(GM.Notes.DATE_FORMATS) do if d.id == draft.dateFormat then return d.label end end
		return "?"
	end, function(root, refresh)
		for _, d in ipairs(GM.Notes.DATE_FORMATS) do
			root:CreateRadio(d.label, function() return draft.dateFormat == d.id end, function() draft.dateFormat = d.id refresh() end)
		end
	end)
	fmt:SetPoint("LEFT", where, "RIGHT", 6, 0)
	f.pickers = { where, fmt, d1, d2, d3 }

	f.send = UI.Button(b, L["Send to the guild"], 150, 22, function()
		local G = GM.G
		if not Sync.IsGuildMaster(G) then GM:Print(L["Only the guild master can send guild-wide settings."]) return end
		Sync.SetGuildSettings(G, draft)
		GM:Print(L["Guild-wide settings saved and sent."])
	end)
	f.send:SetPoint("BOTTOMLEFT", 8, 12)
	local revert = UI.Button(b, L["Undo changes"], 110, 22, function() LoadDraft(GM.G) UI.QueueRefresh() end)
	revert:SetPoint("LEFT", f.send, "RIGHT", 6, 0)
	f.gsNote = UI.Text(b, "", "GameFontDisableSmall")
	f.gsNote:SetPoint("LEFT", revert, "RIGHT", 10, 0)
	f.gsNote:SetPoint("RIGHT", -6, 0)
	f.loaded = false
end

local function Refresh(f, G)
	if not UI.GuildReady(f, G) then return end
	if not f.loaded then LoadDraft(G) f.loaded = true end
	f.enable:SetChecked(GM.settings.syncEnabled)
	f.msgs:SetChecked(GM.settings.syncMessages)
	local users, canSend = Sync.UserList(G)
	local myOrder = Sync.MyRankOrder(G)
	f.mine:SetText(canSend and L["Your edits are shared with everyone online running the addon."] or
		("|cffffd100" .. L["Your rank (%s) is below the sync rank, so your edits stay on your computer. You still receive everyone else's."]:format(RankName(G, myOrder)) .. "|r"))
	f.list:SetRows(users, function(u)
		return { U.DisplayName(u.name), u.ver or "?", RankName(G, u.rankOrder), u.status }
	end)
	local gs = G.guildSettings
	f.gsInfo:SetText(gs and L["last set by %s, %s"]:format(U.DisplayName(gs.by), U.FormatAgo(gs.ts)) or L["not set yet - your own options are used"])
	local isGM = Sync.IsGuildMaster(G)
	if isGM then f.send:Enable() else f.send:Disable() end
	f.gsNote:SetText(isGM and L["You're the guild master: choose, then Send."] or L["Only the guild master can change these."])
	for _, p in ipairs(f.pickers) do p:Refresh() end
end

UI.RegisterTab({ id = "sync", title = L["Sync"], order = 7, build = Build, refresh = Refresh })
