-- Guild Masters R Us - Roster tab: sortable, searchable member list.
local _, GM = ...
local L = GM.L
local U = GM.U
local UI = GM.UI
local Notes = GM.Notes

local search = ""
local sortKey, sortAsc = "name", true

local function D(t) return t and Notes.FormatDate(t) or "|cff777777-|r" end

local function LastOnlineText(m)
	if m.online then return "|cff33ff33" .. L["Online"] .. "|r" end
	if not m.lastOnline then return "?" end
	return U.FormatDuration(U.Now() - m.lastOnline)
end

local function MainAltText(G, m)
	local main = GM.Alts.GetMain(G, m.guid)
	if main == m.guid then return "|cffffd100" .. L["Main"] .. "|r" end
	if main then
		local mm = GM.DB.Find(G, main)
		return L["alt of %s"]:format(mm and U.DisplayName(mm.name) or "?")
	end
	return ""
end

-- Right-click menu shared by the roster and audit tabs.
function UI.MemberMenu(owner, G, m)
	UI.Menu(owner, function(root)
		root:CreateTitle(U.DisplayName(m.name))
		root:CreateButton(L["Open member card"], function() GM.Card.Show(m.guid, true) end)
		root:CreateButton(L["Set as main"], function() GM.Alts.SetMain(G, m.guid) end)
		root:CreateButton(L["Add an alt to this group..."], function() GM.Card.PromptAddAlt(G, m) end)
		if GM.Alts.HasGroup(G, m.guid) then
			root:CreateButton(L["Remove from alt group"], function() GM.Alts.Unlink(G, m.guid) end)
		end
		root:CreateDivider()
		root:CreateButton(L["Set join date..."], function() GM.Card.PromptDate(G, m, "joined") end)
		root:CreateButton(L["Set promotion date..."], function() GM.Card.PromptDate(G, m, "promoted") end)
		root:CreateDivider()
		if GM.Bans.Check(G, m.guid, m.name) then
			root:CreateButton(L["Remove ban"], function()
				local _, key = GM.Bans.Check(G, m.guid, m.name)
				GM.Bans.Remove(G, key)
			end)
		else
			root:CreateButton("|cffff5555" .. L["Ban..."] .. "|r", function() GM.Card.PromptBan(G, m) end)
		end
	end)
end

local VALUE = {
	name = function(_, m) return (m.name or ""):lower() end,
	level = function(_, m) return m.level or 0 end,
	rank = function(_, m) return m.rankOrder or 99 end,
	main = function(G, m) return MainAltText(G, m) end,
	joined = function(_, m) return m.joined and m.joined.t or 0 end,
	promoted = function(_, m) return m.promoted and m.promoted.t or 0 end,
	last = function(_, m) return m.online and math.huge or (m.lastOnline or 0) end,
	note = function(_, m) return (m.note or ""):lower() end,
}

local function Build(f)
	f.body = CreateFrame("Frame", nil, f)
	f.body:SetAllPoints()
	local b = f.body
	local s = UI.Search(b, 200, function(t) search = t:lower() UI.QueueRefresh() end)
	s:SetPoint("TOPLEFT", 6, -2)
	UI.Tooltip(s, L["Search"], L["Matches names, public and officer notes, custom notes and ranks."])

	f.offline = UI.Check(b, L["Show offline"], function(v) GM.settings.rosterOffline = v UI.QueueRefresh() end)
	f.offline:SetPoint("LEFT", s, "RIGHT", 10, 0)
	f.group = UI.Check(b, L["Group alts with mains"], function(v) GM.settings.rosterGroup = v UI.QueueRefresh() end)
	f.group:SetPoint("LEFT", f.offline.label, "RIGHT", 14, 0)
	f.count = UI.Text(b, "", "GameFontDisableSmall")
	f.count:SetPoint("TOPRIGHT", -8, -6)

	local list = UI.List(b, {
		{ key = "name", title = L["Name"], width = 140 },
		{ key = "level", title = L["Lvl"], width = 30, justify = "RIGHT" },
		{ key = "rank", title = L["Rank"], width = 100 },
		{ key = "main", title = L["Main / alt"], width = 110 },
		{ key = "joined", title = L["Joined"], width = 78 },
		{ key = "promoted", title = L["Promoted"], width = 78 },
		{ key = "last", title = L["Last online"], width = 84 },
		{ key = "note", title = L["Note"], width = 100 },
	})
	list:SetPoint("TOPLEFT", 0, -28)
	list:SetPoint("BOTTOMRIGHT", 0, 0)
	list.onSort = function(key)
		if sortKey == key then sortAsc = not sortAsc else sortKey, sortAsc = key, true end
		UI.QueueRefresh()
	end
	list.onClick = function(m, button, row)
		local G = GM.G
		if button == "RightButton" then UI.MemberMenu(row, G, m) else GM.Card.Show(m.guid, true, _G.GuildMastersRusMain) end
	end
	list.onEnter = function(m, row)
		if GM.settings.cardOnMouseover then GM.Card.Show(m.guid, false, _G.GuildMastersRusMain) end
	end
	list.onLeave = function() GM.Card.HideIfNotPinned() end
	f.list = list
end

local function Refresh(f, G)
	if not UI.GuildReady(f, G) then return end
	f.offline:SetChecked(GM.settings.rosterOffline ~= false)
	f.group:SetChecked(GM.settings.rosterGroup and true or false)
	local showOffline = GM.settings.rosterOffline ~= false
	local items = {}
	for _, m in pairs(G.members) do
		if showOffline or m.online then
			local hay = table.concat({ m.name or "", m.note or "", m.oNote or "", m.custom and m.custom.text or "", m.rank or "" }, " "):lower()
			if search == "" or hay:find(search, 1, true) then items[#items + 1] = m end
		end
	end
	local value = VALUE[sortKey] or VALUE.name
	local cache = {}
	for _, m in ipairs(items) do cache[m] = value(G, m) end
	local function Cmp(a, b)
		local va, vb = cache[a], cache[b]
		if va == vb then return (a.name or "") < (b.name or "") end
		if sortAsc then return va < vb end
		return va > vb
	end
	if GM.settings.rosterGroup then
		-- sort by each member's group main, main first
		local key = {}
		for _, m in ipairs(items) do
			local main = GM.Alts.GetMain(G, m.guid)
			local mm = main and GM.DB.Find(G, main) or m
			key[m] = { cache[mm] ~= nil and cache[mm] or value(G, mm), mm.name or "", main == m.guid or not main }
		end
		table.sort(items, function(a, b)
			local ka, kb = key[a], key[b]
			if ka[2] ~= kb[2] then
				if ka[1] ~= kb[1] then if sortAsc then return ka[1] < kb[1] end return ka[1] > kb[1] end
				return ka[2] < kb[2]
			end
			if ka[3] ~= kb[3] then return ka[3] end
			return (a.name or "") < (b.name or "")
		end)
	else
		table.sort(items, Cmp)
	end
	f.count:SetText(L["%d shown"]:format(#items))
	f.list:SetRows(items, function(m)
		local isAlt = GM.settings.rosterGroup and GM.Alts.IsAlt(G, m.guid)
		return {
			(isAlt and "   " or "") .. U.ColorName(m),
			tostring(m.level or ""),
			m.rank or "",
			MainAltText(G, m),
			D(m.joined and m.joined.t),
			D(m.promoted and m.promoted.t),
			LastOnlineText(m),
			m.note or "",
		}
	end)
end

UI.RegisterTab({ id = "roster", title = L["Roster"], order = 2, build = Build, refresh = Refresh })
