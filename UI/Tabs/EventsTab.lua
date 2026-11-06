-- Guild Masters R Us - Events tab: upcoming anniversaries and birthdays.
local _, GM = ...
local L = GM.L
local U = GM.U
local UI = GM.UI

local RANGE = 60

local function Build(f)
	f.body = CreateFrame("Frame", nil, f)
	f.body:SetAllPoints()
	local b = f.body
	local info = UI.Text(b, L["Next %d days. Forever doesn't let addons add guild calendar events, so these are announced in your chat at login instead."]:format(RANGE), "GameFontHighlightSmall")
	info:SetPoint("TOPLEFT", 6, -4)
	info:SetPoint("RIGHT", -6, 0)
	local list = UI.List(b, {
		{ key = "date", title = L["Date"], width = 100 },
		{ key = "when", title = L["When"], width = 90 },
		{ key = "what", title = L["Event"], width = 300 },
	})
	list:SetPoint("TOPLEFT", 0, -28)
	list:SetPoint("BOTTOMRIGHT", 0, 0)
	list.onClick = function(ev) GM.Card.Show(ev.m.guid, true) end
	f.list = list
end

local function Refresh(f, G)
	if not UI.GuildReady(f, G) then return end
	local rows = GM.Events.Upcoming(G, U.Now(), RANGE)
	f.list:SetRows(rows, function(ev)
		local when = ev.inDays == 0 and L["today"] or (ev.inDays == 1 and L["tomorrow"] or L["in %d days"]:format(ev.inDays))
		local what = ev.kind == "birthday" and L["%s's birthday"]:format(U.ColorName(ev.m))
			or L["%s - %d year(s) in the guild"]:format(U.ColorName(ev.m), ev.years)
		return { GM.Notes.FormatDate(ev.t), when, what }
	end)
end

UI.RegisterTab({ id = "events", title = L["Events"], order = 6, build = Build, refresh = Refresh })
