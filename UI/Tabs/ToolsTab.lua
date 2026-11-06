-- Guild Masters R Us - Tools tab: kick / promote / demote / alt-rank helper.
-- Addons can't kick or change ranks themselves, so the big button runs /gremove, /gpromote
-- or /gdemote for ONE member per click (a secure button, like a macro you click).
local _, GM = ...
local L = GM.L
local U = GM.U
local UI = GM.UI
local Rules = GM.Rules

local mode = "kick"
local done = {}   -- [guid] = true once clicked this session
local MODES = {
	{ id = "kick", label = L["Kick inactive"], perm = function() return CanGuildRemove and CanGuildRemove() end },
	{ id = "promote", label = L["Promote"], perm = function() return CanGuildPromote and CanGuildPromote() end },
	{ id = "demote", label = L["Demote"], perm = function() return CanGuildDemote and CanGuildDemote() end },
	{ id = "alts", label = L["Alt ranks"], perm = function() return (CanGuildPromote and CanGuildPromote()) or (CanGuildDemote and CanGuildDemote()) end },
}

local function RankName(G, order) return (G.rankNames and G.rankNames[order]) or ("#" .. tostring(order)) end

local function RankDropdown(parent, width, get, set)
	return UI.Dropdown(parent, width, function()
		local G = GM.G
		local v = get()
		return v and RankName(G, v) or L["Choose rank"]
	end, function(root, refresh)
		local G = GM.G
		for i, name in ipairs(G and G.rankNames or {}) do
			root:CreateRadio(i .. ". " .. name, function() return get() == i end, function() set(i) refresh() UI.QueueRefresh() end)
		end
	end)
end

local function NumberBox(parent, width, get, set)
	local e = UI.Edit(parent, width, 5)
	e:SetNumeric(true)
	e:SetScript("OnEditFocusLost", function(self)
		local v = tonumber(self:GetText())
		if v then set(v) UI.QueueRefresh() else self:SetText(tostring(get() or "")) end
	end)
	e.Load = function(self) self:SetText(tostring(get() or "")) end
	return e
end

local function FindRule(list, from)
	for i, r in ipairs(list) do if r.from == from then return r, i end end
end

local function Build(f)
	f.body = CreateFrame("Frame", nil, f)
	f.body:SetAllPoints()
	local b = f.body

	f.modeButtons = {}
	local x = 4
	for _, md in ipairs(MODES) do
		local btn = UI.Button(b, md.label, 110, 22, function() mode = md.id UI.QueueRefresh() end)
		btn:SetPoint("TOPLEFT", x, -1)
		x = x + 114
		f.modeButtons[md.id] = btn
	end
	f.perm = UI.Text(b, "", "GameFontDisableSmall")
	f.perm:SetPoint("LEFT", f.modeButtons.alts, "RIGHT", 12, 0)

	-- rule editors ---------------------------------------------------------
	local rules = CreateFrame("Frame", nil, b)
	rules:SetPoint("TOPLEFT", 0, -28)
	rules:SetPoint("TOPRIGHT", 0, -28)
	rules:SetHeight(56)
	f.rules = rules

	-- kick
	local kick = CreateFrame("Frame", nil, rules)
	kick:SetAllPoints()
	f.kickPanel = kick
	f.kickOn = UI.Check(kick, L["Kick rule on"], function(v) GM.G.rules.kick.enabled = v UI.QueueRefresh() end)
	f.kickOn:SetPoint("TOPLEFT", 4, 0)
	local t1 = UI.Text(kick, L["Offline at least"], "GameFontHighlightSmall")
	t1:SetPoint("LEFT", f.kickOn.label, "RIGHT", 16, 0)
	f.kickDays = NumberBox(kick, 46, function() return GM.G.rules.kick.days end, function(v) GM.G.rules.kick.days = v end)
	f.kickDays:SetPoint("LEFT", t1, "RIGHT", 8, 0)
	local t2 = UI.Text(kick, L["days, rank"], "GameFontHighlightSmall")
	t2:SetPoint("LEFT", f.kickDays, "RIGHT", 6, 0)
	f.kickRank = RankDropdown(kick, 140, function() return GM.G.rules.kick.minRankOrder end, function(v) GM.G.rules.kick.minRankOrder = v end)
	f.kickRank:SetPoint("LEFT", t2, "RIGHT", 6, 0)
	local t3 = UI.Text(kick, L["or lower"], "GameFontHighlightSmall")
	t3:SetPoint("LEFT", f.kickRank, "RIGHT", 6, 0)
	f.kickAlt = UI.Check(kick, L["Count alts (skip if any alt played recently)"], function(v) GM.G.rules.kick.altAware = v UI.QueueRefresh() end)
	f.kickAlt:SetPoint("TOPLEFT", 4, -26)

	-- promote / demote share one editor
	local rank = CreateFrame("Frame", nil, rules)
	rank:SetAllPoints()
	f.rankPanel = rank
	f.editFrom = nil
	local r1 = UI.Text(rank, L["Rule for rank"], "GameFontHighlightSmall")
	r1:SetPoint("TOPLEFT", 6, -4)
	f.ruleRank = RankDropdown(rank, 140, function() return f.editFrom end, function(v)
		f.editFrom = v
		local list = GM.G.rules[mode]
		local r = FindRule(list, v)
		f.ruleDays:SetText(tostring(r and r.days or ""))
		f.ruleLevel:SetText(tostring(r and r.level or ""))
	end)
	f.ruleRank:SetPoint("LEFT", r1, "RIGHT", 6, 0)
	f.ruleDaysLabel = UI.Text(rank, "", "GameFontHighlightSmall")
	f.ruleDaysLabel:SetPoint("LEFT", f.ruleRank, "RIGHT", 8, 0)
	f.ruleDays = UI.Edit(rank, 46, 5)
	f.ruleDays:SetNumeric(true)
	f.ruleDays:SetPoint("LEFT", f.ruleDaysLabel, "RIGHT", 6, 0)
	f.ruleLevelLabel = UI.Text(rank, L["min level"], "GameFontHighlightSmall")
	f.ruleLevelLabel:SetPoint("LEFT", f.ruleDays, "RIGHT", 10, 0)
	f.ruleLevel = UI.Edit(rank, 36, 3)
	f.ruleLevel:SetNumeric(true)
	f.ruleLevel:SetPoint("LEFT", f.ruleLevelLabel, "RIGHT", 6, 0)
	local save = UI.Button(rank, L["Save rule"], 90, 22, function()
		local G = GM.G
		if not f.editFrom then GM:Print(L["Choose a rank first."]) return end
		local list = G.rules[mode]
		local r = FindRule(list, f.editFrom)
		if not r then r = { from = f.editFrom } list[#list + 1] = r end
		r.days = tonumber(f.ruleDays:GetText()) or 0
		r.level = mode == "promote" and (tonumber(f.ruleLevel:GetText()) or 0) or nil
		UI.QueueRefresh()
	end)
	save:SetPoint("LEFT", f.ruleLevel, "RIGHT", 10, 0)
	local del = UI.Button(rank, L["Delete rule"], 90, 22, function()
		local list = GM.G.rules[mode]
		local _, i = FindRule(list, f.editFrom or -1)
		if i then table.remove(list, i) UI.QueueRefresh() end
	end)
	del:SetPoint("LEFT", save, "RIGHT", 4, 0)
	f.ruleSummary = UI.Text(rank, "", "GameFontDisableSmall")
	f.ruleSummary:SetPoint("TOPLEFT", 6, -30)
	f.ruleSummary:SetPoint("RIGHT", -6, 0)

	local altInfo = CreateFrame("Frame", nil, rules)
	altInfo:SetAllPoints()
	f.altPanel = altInfo
	local ai = UI.Text(altInfo, L["Alts whose rank is different from their main's. Each click moves one rank toward the main's rank."], "GameFontHighlightSmall")
	ai:SetPoint("TOPLEFT", 6, -6)
	ai:SetPoint("RIGHT", -6, 0)

	-- matches ----------------------------------------------------------------
	local list = UI.List(b, {
		{ key = "name", title = L["Name"], width = 150 },
		{ key = "rank", title = L["Rank"], width = 110 },
		{ key = "reason", title = L["Why"], width = 260 },
		{ key = "state", title = L["Status"], width = 100 },
	})
	list:SetPoint("TOPLEFT", 0, -88)
	list:SetPoint("BOTTOMRIGHT", 0, 40)
	list.onClick = function(row, button, r)
		local G = GM.G
		if button == "RightButton" then
			local kind = mode == "alts" and (row.cmd == "/gpromote" and "promote" or "demote") or mode
			UI.Menu(r, function(root)
				root:CreateTitle(U.DisplayName(row.m.name))
				root:CreateButton(L["Skip for 30 days"], function() Rules.SetSafe(G, row.m.guid, kind, 30) end)
				root:CreateButton(L["Always skip"], function() Rules.SetSafe(G, row.m.guid, kind, nil) end)
				root:CreateButton(L["Open member card"], function() GM.Card.Show(row.m.guid, true) end)
			end)
		else
			GM.Card.Show(row.m.guid, true)
		end
	end
	f.list = list

	-- the secure action button
	-- Parented to UIParent (not our window) so our window can still open and close in combat.
	-- It's emptied and hidden the moment combat starts, so a stray click can't do anything.
	local act = CreateFrame("Button", "GuildMastersRusActionButton", UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
	act:SetSize(260, 28)
	act:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 4, 6)
	act:SetFrameStrata("HIGH")
	act:SetFrameLevel(b:GetFrameLevel() + 20)
	act:Hide()
	b:HookScript("OnShow", function() if not U.InCombat() then act:Show() end end)
	b:HookScript("OnHide", function() if not U.InCombat() then act:Hide() end end)
	act:RegisterForClicks("AnyUp", "AnyDown")
	act:SetAttribute("type", "macro")
	act:SetText(L["Nothing to do"])
	act:HookScript("PostClick", function(self)
		if self.guid then
			done[self.guid] = true
			C_Timer.After(1.5, function() GM.Roster.Request() UI.QueueRefresh() end)
			UI.QueueRefresh()
		end
	end)
	f.act = act
	f.actInfo = UI.Text(b, "", "GameFontHighlightSmall")
	f.actInfo:SetPoint("LEFT", act, "RIGHT", 10, 0)
	f.actInfo:SetPoint("RIGHT", -10, 0)
	local reset = UI.Button(b, L["Reset clicked"], 110, 22, function() done = {} UI.QueueRefresh() end, L["Shows members you already clicked this session again."])
	reset:SetPoint("BOTTOMRIGHT", -4, 9)
end

local function SetAction(f, row)
	local act = f.act
	if U.InCombat() then
		f.actInfo:SetText("|cffff6666" .. L["Not in combat."] .. "|r")
		return
	end
	if f.body:IsVisible() then act:Show() end
	if not row then
		act.guid = nil
		act:SetAttribute("macrotext", nil)
		act:SetText(L["Nothing to do"])
		act:Disable()
		return
	end
	local verb = (row.cmd == "/gremove" and L["Kick %s"]) or (row.cmd == "/gpromote" and L["Promote %s"]) or L["Demote %s"]
	act.guid = row.m.guid
	act:SetAttribute("macrotext", row.cmd .. " " .. row.m.name)
	act:SetText(verb:format(U.DisplayName(row.m.name)))
	act:Enable()
end

local function Refresh(f, G)
	if not UI.GuildReady(f, G) then return end
	for _, md in ipairs(MODES) do
		local btn = f.modeButtons[md.id]
		if md.id == mode then btn:LockHighlight() else btn:UnlockHighlight() end
	end
	local md
	for _, x in ipairs(MODES) do if x.id == mode then md = x end end
	local allowed = md.perm()
	f.perm:SetText(allowed and "" or ("|cffff6666" .. L["Your rank can't do this."] .. "|r"))

	f.kickPanel:SetShown(mode == "kick")
	f.rankPanel:SetShown(mode == "promote" or mode == "demote")
	f.altPanel:SetShown(mode == "alts")
	if mode == "kick" then
		local k = G.rules.kick
		f.kickOn:SetChecked(k.enabled)
		f.kickAlt:SetChecked(k.altAware)
		f.kickDays:Load()
		f.kickRank:Refresh()
	elseif mode == "promote" or mode == "demote" then
		f.ruleDaysLabel:SetText(mode == "promote" and L["days in rank"] or L["days offline"])
		f.ruleLevelLabel:SetShown(mode == "promote")
		f.ruleLevel:SetShown(mode == "promote")
		f.ruleRank:Refresh()
		local parts = {}
		for _, r in ipairs(G.rules[mode]) do
			if mode == "promote" then
				parts[#parts + 1] = L["%s → %s after %d days%s"]:format(RankName(G, r.from), RankName(G, r.from - 1), r.days or 0,
					(r.level or 0) > 0 and (" " .. L["(level %d+)"]:format(r.level)) or "")
			else
				parts[#parts + 1] = L["%s → %s after %d days offline"]:format(RankName(G, r.from), RankName(G, r.from + 1), r.days or 0)
			end
		end
		f.ruleSummary:SetText(#parts > 0 and (L["Rules: "] .. table.concat(parts, "; ")) or L["No rules yet - pick a rank, enter days, Save rule."])
	end

	local rows = Rules.Matches(G, mode)
	local todo
	for _, row in ipairs(rows) do
		if not done[row.m.guid] and not todo then todo = row end
	end
	f.list:SetRows(rows, function(row)
		local state = done[row.m.guid] and ("|cff33ff33" .. L["clicked"] .. "|r") or (row == todo and ("|cffffd100" .. L["next"] .. "|r") or "")
		return { U.ColorName(row.m), row.m.rank or "", row.reason or "", state }
	end)
	if allowed then SetAction(f, todo) else SetAction(f, nil) end
	local left = 0
	for _, row in ipairs(rows) do if not done[row.m.guid] then left = left + 1 end end
	f.actInfo:SetText(todo and L["%d left. Click the button once per member (it works like a macro)."]:format(left) or L["No members match right now."])
end

GM:On("PLAYER_REGEN_DISABLED", function()
	local act = _G.GuildMastersRusActionButton
	if act then
		act:SetAttribute("macrotext", nil)
		act.guid = nil
		act:Hide()
	end
end)
GM:On("PLAYER_REGEN_ENABLED", function()
	local act = _G.GuildMastersRusActionButton
	if act and act:GetParent() and UI.IsShown() then
		local tab
		for _, t in ipairs(UI.tabs) do if t.id == "tools" then tab = t end end
		if tab and tab.frame and tab.frame:IsVisible() then act:Show() end
		UI.QueueRefresh()
	end
end)

UI.RegisterTab({ id = "tools", title = L["Tools"], order = 5, build = Build, refresh = Refresh })
