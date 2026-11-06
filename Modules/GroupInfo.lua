-- Guild Masters R Us - group info: who in your party/raid is a guildie, a FORMER guildie
-- (when they left, banned?, renamed?, alts still in the guild) or on the ban list,
-- plus a trade-range dot in the group window.
local _, GM = ...
local L = GM.L
local U = GM.U
local UI = GM.UI
local DB = GM.DB

local GroupInfo = {}
GM.GroupInfo = GroupInfo
local noticed = {}
local win
local queued = false

local function Units()
	local out = {}
	if IsInRaid and IsInRaid() then
		for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do out[#out + 1] = "raid" .. i end
	elseif IsInGroup and IsInGroup() then
		for i = 1, 4 do out[#out + 1] = "party" .. i end
	end
	return out
end

-- One row per other group member: { unit, name, guid, kind = "guild"|"former"|"banned"|"none", m, ban, text }
function GroupInfo.Scan(G)
	local rows = {}
	if not G then return rows end
	local me = UnitGUID("player")
	for _, unit in ipairs(Units()) do
		if UnitExists(unit) then
			local okG, guid = pcall(UnitGUID, unit)
			guid = okG and GM.Safe(guid)
			local okN, name, realm = pcall(UnitName, unit)
			name, realm = okN and GM.Safe(name), okN and GM.Safe(realm)
			if guid and name and guid ~= me then
				local full = (realm and realm ~= "") and (name .. "-" .. realm) or U.FullName(name)
				local row = { unit = unit, name = full, guid = guid, kind = "none" }
				local m, former = DB.Find(G, guid)
				local ban = GM.Bans.Check(G, guid, full)
				if ban then row.ban = ban end
				if m and not former then
					row.kind, row.m = "guild", m
					row.text = m.rank or ""
				elseif m and former then
					row.kind, row.m = "former", m
					local parts = { L["left %s"]:format(GM.Notes.FormatDate(m.leftAt)) .. (m.leftHow == "kick" and (" (" .. L["kicked"] .. ")") or "") }
					if m.name and not U.SameName(m.name, full) then parts[#parts + 1] = L["was %s"]:format(U.DisplayName(m.name)) end
					local alts = {}
					for _, g in ipairs(GM.Alts.GroupMembersAll(G, guid)) do
						if g ~= guid and G.members[g] then alts[#alts + 1] = U.DisplayName(G.members[g].name) end
					end
					if #alts > 0 then parts[#parts + 1] = L["alts in guild: %s"]:format(table.concat(alts, ", ")) end
					row.text = table.concat(parts, "; ")
				end
				if ban then
					row.kind = "banned"
					row.text = L["BANNED"] .. (ban.reason ~= "" and (": " .. ban.reason) or "") .. (row.text and ("; " .. row.text) or "")
				end
				rows[#rows + 1] = row
			end
		end
	end
	table.sort(rows, function(a, b)
		local order = { banned = 1, former = 2, guild = 3, none = 4 }
		if order[a.kind] ~= order[b.kind] then return order[a.kind] < order[b.kind] end
		return a.name < b.name
	end)
	return rows
end

local function Notify(G)
	if not GM.settings.groupNotices then return end
	for _, row in ipairs(GroupInfo.Scan(G)) do
		if (row.kind == "former" or row.kind == "banned") and not noticed[row.guid] then
			noticed[row.guid] = true
			local who = U.DisplayName(row.name)
			if row.kind == "banned" then
				GM:Print("|cffff3333" .. L["%s in your group is on the guild's ban list!"]:format(who) .. "|r " .. (row.text or ""))
			else
				GM:Print(L["%s in your group is a former guildie: %s"]:format(who, row.text or ""))
			end
		end
	end
end

local function InTradeRange(unit)
	if U.InCombat() or not CheckInteractDistance then return nil end
	local ok, r = pcall(CheckInteractDistance, unit, 2)
	if not ok or GM.IsSecret(r) then return nil end
	return r and true or false
end

local function BuildWindow()
	win = UI.Window("Group", L["Group info"], 520, 300)
	win.list = UI.List(win, {
		{ key = "dot", title = "", width = 16 },
		{ key = "name", title = L["Name"], width = 140 },
		{ key = "kind", title = L["Guild"], width = 90 },
		{ key = "text", title = L["Details"], width = 200 },
	})
	win.list:SetPoint("TOPLEFT", 8, -34)
	win.list:SetPoint("BOTTOMRIGHT", -8, 26)
	win.list.onClick = function(row) if row.m then GM.Card.Show(row.guid, true) end end
	win.hint = UI.Text(win, L["Green dot = close enough to trade."], "GameFontDisableSmall")
	win.hint:SetPoint("BOTTOMLEFT", 12, 8)
	win.elapsed = 0
	win:SetScript("OnUpdate", function(self, e)
		self.elapsed = self.elapsed + e
		if self.elapsed > 1 then self.elapsed = 0 GroupInfo.RefreshWindow() end
	end)
end

local KIND = {
	guild = "|cff33ff33" .. L["Guildie"] .. "|r", former = "|cffff9933" .. L["Former"] .. "|r",
	banned = "|cffff3333" .. L["Banned"] .. "|r", none = "|cff777777-|r",
}

function GroupInfo.RefreshWindow()
	if not win or not win:IsShown() then return end
	local rows = GroupInfo.Scan(GM.G)
	win.list:SetRows(rows, function(row)
		local dot = ""
		if GM.settings.tradeDots then
			local r = InTradeRange(row.unit)
			dot = r == true and "|cff33ff33●|r" or (r == false and "|cff555555●|r" or "")
		end
		local color = row.m and U.ColorName(row.m) or U.DisplayName(row.name)
		return { dot, color, KIND[row.kind], row.text or "" }
	end)
	if #rows == 0 then win.hint:SetText(L["You're not in a group."]) else win.hint:SetText(L["Green dot = close enough to trade."]) end
end

function GroupInfo.Toggle()
	if not win then BuildWindow() end
	if win:IsShown() then win:Hide() else win:Show() GroupInfo.RefreshWindow() end
end

GM:On("GROUP_ROSTER_UPDATE", function()
	if not (IsInGroup and IsInGroup()) then noticed = {} return end
	if queued then return end
	queued = true
	C_Timer.After(1.5, function()
		queued = false
		local G = GM.G
		if G and G.initialized then Notify(G) end
		GroupInfo.RefreshWindow()
	end)
end)

GM:Command("group", L["show who in your group is a guildie, former guildie or banned"], GroupInfo.Toggle)
