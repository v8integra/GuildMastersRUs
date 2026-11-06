-- Guild Masters R Us - options page in Blizzard's Options > AddOns (Settings API, proxy settings
-- over GM.settings, so slash commands and this page always agree). /gmru options opens it.
local _, GM = ...
local L = GM.L

local category

local function Round(v) return math.floor(v + 0.5) end

local function AddSetting(key, varType, name, default, transform, apply)
	local function Get() return GM.settings[key] end
	local function Set(v)
		if transform then v = transform(v) end
		GM.settings[key] = v
		if apply then apply(v) end
	end
	return Settings.RegisterProxySetting(category, "GMRU_" .. key:upper(), varType, name, default, Get, Set)
end

local function Check(key, name, tooltip, apply)
	local setting = AddSetting(key, Settings.VarType.Boolean, name, GM.DB.DEFAULTS[key], nil, apply)
	Settings.CreateCheckbox(category, setting, tooltip)
end

local function Slider(key, name, tooltip, min, max, step, fmt, apply)
	local setting = AddSetting(key, Settings.VarType.Number, name, GM.DB.DEFAULTS[key], Round, apply)
	local opts = Settings.CreateSliderOptions(min, max, step)
	opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt or Round)
	Settings.CreateSlider(category, setting, opts, tooltip)
end

local function Dropdown(key, name, tooltip, choices)
	local setting = AddSetting(key, Settings.VarType.String, name, GM.DB.DEFAULTS[key])
	local function Options()
		local c = Settings.CreateControlTextContainer()
		for _, ch in ipairs(choices) do c:Add(ch[1], ch[2]) end
		return c:GetData()
	end
	Settings.CreateDropdown(category, setting, Options, tooltip)
end

local function Header(layout, text)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function Button(layout, name, text, onClick, tooltip)
	layout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tooltip, true))
end

local function Days(v) return L["%d days"]:format(Round(v)) end
local function DaysOrOff(v) v = Round(v) return v == 0 and L["Off"] or L["%d days"]:format(v) end
local function Seconds(v) return L["%d sec"]:format(Round(v)) end

local function Build()
	local layout
	category, layout = Settings.RegisterVerticalLayoutCategory(L["Guild Masters R Us"])

	Button(layout, L["Main window"], L["Open"], function() GM.UI.Open() end, L["Log, roster, audit, bans, tools, events, sync and export. Also /gmru."])

	Header(layout, L["Log and alerts"])
	Check("showLogOnLogin", L["Open the log when you log in"], L["Opens the Log tab after the first roster scan."])
	Check("showLogOnlyIfNew", L["...only if there are new entries"])
	Slider("scanInterval", L["Roster refresh"], L["How often to ask the server for a fresh roster. Changes are also picked up whenever the game sends a roster update."], 20, 300, 10, Seconds, function() GM.RestartScanTicker() end)
	Slider("inactiveReturnDays", L["\"Back from inactivity\" after"], L["Logs a member coming online after being offline at least this long."], 1, 180, 1, Days)
	Slider("kickRecommendDays", L["Kick recommendation after"], L["Logs a recommendation once a member (and all their alts) have been offline this long. 0 = off."], 0, 730, 5, DaysOrOff)
	Slider("levelMin", L["Report level-ups from level"], L["Level-ups below this level aren't logged."], 1, 80, 1)
	Check("levelMilestones", L["Only report every 10th level"], L["Plus the max level."])
	Button(layout, L["Which changes go to chat"], L["Choose"], function() GM.UI.Show("log") end, L["On the Log tab, use the Chat alerts and Record menus."])

	Header(layout, L["Roster and chat"])
	Check("cardOnMouseover", L["Member card on mouseover"], L["Hovering a name in the guild roster shows its card. Click to keep it open."])
	Check("mainTag", L["Show the main's name after alts in chat"], L["Guild, officer, party, raid, instance, say, yell and whispers."])
	Check("mainTagOnMains", L["Also tag mains with (M)"])
	Check("noteTrigger", L["!note sets a member's public note"], L["When a member types \"!note text\" in guild chat, your addon writes it into their public note. Needs a rank that can edit public notes."])
	Dropdown("joinNote", L["Write join date into a note"], L["When someone joins, put the date in their public or officer note. The guild master's guild-wide setting (Sync tab) wins if set."],
		{ { "off", L["Off"] }, { "public", L["Public note"] }, { "officer", L["Officer note"] } })
	local fmts = {}
	for _, d in ipairs(GM.Notes.DATE_FORMATS) do fmts[#fmts + 1] = { d.id, d.label } end
	Dropdown("dateFormat", L["Date format"], L["Used everywhere in the addon and for dates written into notes."], fmts)
	Check("noteDayFirst", L["Notes use day/month order"], L["When reading dates like 05/06/2026 from notes: on = 5 June, off = May 6."])

	Header(layout, L["Events and groups"])
	Check("announceEvents", L["Announce anniversaries and birthdays"], L["In your chat at login."])
	Slider("announceDays", L["Announce this many days ahead"], nil, 0, 14, 1, Days)
	Check("birthdays", L["Track birthdays"])
	Check("groupNotices", L["Warn about former/banned guildies in my group"])
	Check("tradeDots", L["Trade-range dots in the group window"], L["/gmru group"])

	Header(layout, L["Sync"])
	Check("syncEnabled", L["Sync with guildmates running the addon"], L["Shares join dates, promotion dates, alts, custom notes, birthdays and bans."])
	Slider("syncMinRank", L["Accept general data from rank"], L["1 = guild master only. Higher numbers include lower ranks. The guild master's guild-wide setting wins if set."], 1, 10, 1)
	Slider("syncBanMinRank", L["Accept bans from rank"], nil, 1, 10, 1)
	Slider("syncCustomMinRank", L["Accept custom notes from rank"], nil, 1, 10, 1)
	Check("syncMessages", L["Show sync messages"])

	Header(layout, L["Other"])
	local mm = Settings.RegisterProxySetting(category, "GMRU_MINIMAP", Settings.VarType.Boolean, L["Minimap button"], true,
		function() return GM.settings.minimap.show end,
		function(v) GM.settings.minimap.show = v GM.UpdateMinimapButton() end)
	Settings.CreateCheckbox(category, mm)
	Button(layout, L["Window positions"], L["Reset"], function() GM.UI.ResetWindows() GM:Print(L["Window positions reset. /reload to apply."]) end)

	Settings.RegisterAddOnCategory(category)
end

function GM.OpenOptions()
	if not category then GM:Print(L["The options page failed to load. Use /gmru help."]) return end
	if InCombatLockdown() then GM:Print(L["Options open after combat."]) return end
	Settings.OpenToCategory(category:GetID())
end

GM:OnDBReady(function()
	local ok, err = pcall(Build)
	if not ok then
		category = nil
		GM:Print("|cffff4444" .. L["options page failed to load - "] .. tostring(err) .. "|r")
	end
end)

GM:Command({ "options", "opt", "config" }, L["open the options page"], function() GM.OpenOptions() end)
