-- Guild Masters R Us - Log tab: the guild change log with filters and search.
local _, GM = ...
local L = GM.L
local U = GM.U
local UI = GM.UI
local Log = GM.Log

local search = ""

local function ViewSetting(kind)
	GM.settings.logView = GM.settings.logView or {}
	return GM.settings.logView[kind] ~= false
end

local function Build(f)
	f.body = CreateFrame("Frame", nil, f)
	f.body:SetAllPoints()
	local b = f.body

	local s = UI.Search(b, 200, function(t) search = t:lower() UI.QueueRefresh() end)
	s:SetPoint("TOPLEFT", 6, -2)

	local filter = UI.Dropdown(b, 120, function() return L["Show"] end, function(root)
		root:CreateTitle(L["Show in this list"])
		for _, kind in ipairs(Log.KINDS) do
			root:CreateCheckbox(Log.KIND_NAMES[kind] or kind, function() return ViewSetting(kind) end, function()
				GM.settings.logView[kind] = not ViewSetting(kind)
				UI.QueueRefresh()
			end)
		end
	end)
	filter:SetPoint("LEFT", s, "RIGHT", 10, 0)

	local chat = UI.Dropdown(b, 130, function() return L["Chat alerts"] end, function(root)
		root:CreateTitle(L["Also print to chat"])
		for _, kind in ipairs(Log.KINDS) do
			root:CreateCheckbox(Log.KIND_NAMES[kind] or kind, function() return GM.settings.logTypes[kind] and GM.settings.logTypes[kind].chat end, function()
				local t = GM.settings.logTypes[kind]
				if t then t.chat = not t.chat end
			end)
		end
	end)
	chat:SetPoint("LEFT", filter, "RIGHT", 6, 0)

	local record = UI.Dropdown(b, 120, function() return L["Record"] end, function(root)
		root:CreateTitle(L["Save these in the log"])
		for _, kind in ipairs(Log.KINDS) do
			root:CreateCheckbox(Log.KIND_NAMES[kind] or kind, function() return GM.settings.logTypes[kind] and GM.settings.logTypes[kind].log ~= false end, function()
				local t = GM.settings.logTypes[kind]
				if t then t.log = not (t.log ~= false) end
			end)
		end
	end)
	record:SetPoint("LEFT", chat, "RIGHT", 6, 0)

	local clear = UI.Button(b, L["Clear log"], 90, 22, function()
		local G = GM.G
		if not G then return end
		UI.Confirm(L["Clear the whole log for this guild?"], function() Log.Clear(G) end)
	end)
	clear:SetPoint("TOPRIGHT", -4, -1)

	local list = UI.List(b, {
		{ key = "t", title = L["When"], width = 120 },
		{ key = "text", title = L["Change"], width = 400 },
	})
	list:SetPoint("TOPLEFT", 0, -28)
	list:SetPoint("BOTTOMRIGHT", 0, 0)
	list.onClick = function(e, button)
		local G = GM.G
		if not G then return end
		if button == "RightButton" then
			UI.Menu(f, function(root)
				if e.g and GM.DB.Find(G, e.g) then
					root:CreateButton(L["Open member card"], function() GM.Card.Show(e.g, true) end)
				end
				root:CreateButton(L["Delete this line"], function() Log.Remove(G, e) end)
			end)
		elseif e.g and GM.DB.Find(G, e.g) then
			GM.Card.Show(e.g, true)
		end
	end
	list.onEnter = function(e, row)
		GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
		GameTooltip:SetText(date("%Y-%m-%d %H:%M", e.t), 1, 0.82, 0)
		GameTooltip:AddLine(Log.ColoredText(e), 1, 1, 1, true)
		GameTooltip:Show()
	end
	f.list = list
	f.count = UI.Text(b, "", "GameFontDisableSmall")
	f.count:SetPoint("BOTTOMRIGHT", list, "TOPRIGHT", -100, 6)
end

local function Refresh(f, G)
	if not UI.GuildReady(f, G) then return end
	G.logSeenAt = U.Now()
	local items = {}
	for _, e in ipairs(G.log) do
		if ViewSetting(e.k) then
			if search == "" or Log.Text(e):lower():find(search, 1, true) then items[#items + 1] = e end
		end
	end
	table.sort(items, function(a, b) return a.t > b.t end)
	f.count:SetText(L["%d entries"]:format(#items))
	f.list:SetRows(items, function(e)
		return { date("%Y-%m-%d %H:%M", e.t), Log.ColoredText(e) }
	end)
end

UI.RegisterTab({ id = "log", title = L["Log"], order = 1, build = Build, refresh = Refresh })
