-- Guild Masters R Us - main window with tabs (Log, Roster, Audit, Bans, Tools, Events, Sync, Export).
local _, GM = ...
local L = GM.L
local U = GM.U
local UI = GM.UI

UI.tabs = {}
local window, current
local refreshQueued = false

-- tab = { id, title, order, build(frame), refresh(frame) }
function UI.RegisterTab(tab)
	UI.tabs[#UI.tabs + 1] = tab
	table.sort(UI.tabs, function(a, b) return (a.order or 99) < (b.order or 99) end)
end

local function Build()
	window = UI.Window("Main", L["Guild Masters R Us"], 880, 540)
	window:SetResizable(true)
	if window.SetResizeBounds then window:SetResizeBounds(760, 420, 1400, 1000) end
	window.sub = UI.Text(window, "", "GameFontDisableSmall")
	window.sub:SetPoint("LEFT", window.Title, "RIGHT", 10, 0)

	local grip = CreateFrame("Button", nil, window)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -4, 4)
	grip:SetNormalTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up]])
	grip:SetHighlightTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Highlight]])
	grip:SetScript("OnMouseDown", function() window:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function()
		window:StopMovingOrSizing()
		GM.settings.windows.MainSize = { w = window:GetWidth(), h = window:GetHeight() }
	end)
	local size = GM.settings.windows.MainSize
	if size then window:SetSize(size.w, size.h) end

	window.tabButtons = {}
	local x = 10
	for i, tab in ipairs(UI.tabs) do
		local b = UI.Button(window, tab.title, 92, 22, function() UI.Show(tab.id) end)
		b:SetPoint("TOPLEFT", x, -34)
		x = x + 96
		window.tabButtons[i] = b
		local content = CreateFrame("Frame", nil, window)
		content:SetPoint("TOPLEFT", 10, -62)
		content:SetPoint("BOTTOMRIGHT", -10, 22)
		content:Hide()
		tab.frame = content
		tab.button = b
	end
	window.status = UI.Text(window, "", "GameFontDisableSmall")
	window.status:SetPoint("BOTTOMLEFT", 12, 7)
	window:SetScript("OnShow", function() UI.RefreshCurrent() end)
end

local function TabById(id)
	for _, tab in ipairs(UI.tabs) do if tab.id == id then return tab end end
	return UI.tabs[1]
end

function UI.Show(id)
	if not window then Build() end
	local tab = TabById(id)
	for _, t in ipairs(UI.tabs) do
		t.frame:SetShown(t == tab)
		if t.button.LockHighlight then
			if t == tab then t.button:LockHighlight() else t.button:UnlockHighlight() end
		end
	end
	if not tab.built then
		tab.built = true
		local ok, err = pcall(tab.build, tab.frame)
		if not ok then GM:Print("|cffff4444" .. tostring(err) .. "|r") end
	end
	current = tab
	window:Show()
	UI.RefreshCurrent()
end

function UI.Open(id) UI.Show(id or (current and current.id) or "log") end

function UI.Toggle(id)
	if window and window:IsShown() and (not id or (current and current.id == id)) then
		window:Hide()
	else
		UI.Open(id)
	end
end

function UI.IsShown() return window and window:IsShown() end

function UI.RefreshCurrent()
	if not (window and window:IsShown() and current) then return end
	local G = GM.G
	if G then
		window.sub:SetText(("%s  ·  %d %s"):format(G.name or "", U.Count(G.members), L["members"]))
		local syncTxt = GM.settings.syncEnabled and L["Sync on"] or L["Sync off"]
		window.status:SetText(("%s  ·  %s %s  ·  %s"):format(syncTxt, L["Last scan"], G.lastScan and U.FormatAgo(G.lastScan) or L["never"], GM.VERSION))
	else
		window.sub:SetText(L["not in a guild"])
		window.status:SetText(GM.VERSION)
	end
	if current.refresh and current.built then
		local ok, err = pcall(current.refresh, current.frame, G)
		if not ok then GM:Print("|cffff4444" .. tostring(err) .. "|r") end
	end
end

local function QueueRefresh()
	if refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0.3, function()
		refreshQueued = false
		UI.RefreshCurrent()
	end)
end
UI.QueueRefresh = QueueRefresh

for _, msg in ipairs({ "ROSTER_UPDATED", "LOG_CHANGED", "BANS_CHANGED", "ALTS_CHANGED", "SYNC_APPLIED", "SYNC_USERS", "RULES_CHANGED" }) do
	GM:Listen(msg, QueueRefresh)
end

-- Common "no guild yet" message for tabs.
function UI.NoGuild(frame)
	if not frame.noGuild then
		frame.noGuild = UI.Text(frame, L["Not in a guild, or the roster hasn't been scanned yet."], "GameFontNormal", "CENTER")
		frame.noGuild:SetPoint("CENTER")
	end
	return frame.noGuild
end

-- Shows/hides a tab's children depending on whether guild data exists.
function UI.GuildReady(frame, G)
	local ready = G and G.initialized
	UI.NoGuild(frame):SetShown(not ready)
	if frame.body then frame.body:SetShown(ready and true or false) end
	return ready
end

GM:Command({ "show", "open" }, L["open the main window"], function() UI.Open() end)
GM:Command("log", L["open the guild change log"], function() UI.Show("log") end)
GM:Command("roster", L["open the roster"], function() UI.Show("roster") end)
GM:Command("audit", L["open the audit (missing dates, mains/alts)"], function() UI.Show("audit") end)
GM:Command({ "ban", "bans" }, L["open the ban list"], function() UI.Show("bans") end)
GM:Command({ "tools", "kick", "promote", "demote", "macro" }, L["open the kick/promote/demote tool"], function() UI.Show("tools") end)
GM:Command({ "events", "event" }, L["open upcoming anniversaries and birthdays"], function() UI.Show("events") end)
GM:Command({ "users", "syncusers" }, L["open the sync tab"], function() UI.Show("sync") end)
GM:Command("export", L["open export and restore points"], function() UI.Show("export") end)
GM:Command("center", L["move all windows back to the middle"], function()
	UI.ResetWindows()
	GM:Print(L["Window positions reset. /reload to apply."])
end)
