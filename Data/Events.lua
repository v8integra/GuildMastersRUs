-- Guild Masters R Us - guild join anniversaries and birthdays.
-- (Forever restricts addons from adding calendar events, so these are announced in chat.)
local _, GM = ...
local L = GM.L
local U = GM.U
local Events = {}
GM.Events = Events

-- First time this member joined (earliest known join).
function Events.OriginalJoin(m)
	local best = m.joined and m.joined.t
	for _, h in ipairs(m.history or {}) do
		if h.k == "join" and h.t and (not best or h.t < best) then best = h.t end
	end
	return best
end

local function NextOccurrence(month, day, now)
	local today = date("*t", now)
	local t = time({ year = today.year, month = month, day = day, hour = 12 })
	local todayNoon = time({ year = today.year, month = today.month, day = today.day, hour = 12 })
	if t < todayNoon then t = time({ year = today.year + 1, month = month, day = day, hour = 12 }) end
	return t, (t - todayNoon) / U.DAY
end

-- Upcoming events within `days`: list of { m, kind = "anniversary"|"birthday", t, inDays, years }.
function Events.Upcoming(G, now, days)
	now = now or U.Now()
	days = days or 30
	local out = {}
	for _, m in pairs(G.members) do
		local joined = Events.OriginalJoin(m)
		if joined and m.joined and m.joined.src ~= "unknown" then
			local j = date("*t", joined)
			local t, inDays = NextOccurrence(j.month, j.day, now)
			local years = date("*t", t).year - j.year
			if years >= 1 and inDays <= days then
				out[#out + 1] = { m = m, kind = "anniversary", t = t, inDays = math.floor(inDays + 0.5), years = years }
			end
		end
		if GM.settings.birthdays and m.birthday and m.birthday.m and m.birthday.d then
			local t, inDays = NextOccurrence(m.birthday.m, m.birthday.d, now)
			if inDays <= days then
				out[#out + 1] = { m = m, kind = "birthday", t = t, inDays = math.floor(inDays + 0.5) }
			end
		end
	end
	table.sort(out, function(a, b) return a.t < b.t end)
	return out
end

function Events.Text(ev)
	local name = U.ColorName(ev.m)
	local when = ev.inDays == 0 and L["today"] or (ev.inDays == 1 and L["tomorrow"] or L["in %d days"]:format(ev.inDays))
	if ev.kind == "birthday" then return L["%s's birthday is %s"]:format(name, when) end
	return L["%s's %d-year guild anniversary is %s"]:format(name, ev.years, when)
end

-- Announces each upcoming event once per year.
function Events.Announce(G, now)
	local s = GM.settings
	if not s.announceEvents then return end
	now = now or U.Now()
	local year = date("*t", now).year
	for _, ev in ipairs(Events.Upcoming(G, now, s.announceDays or 3)) do
		local key = ev.kind .. ":" .. ev.m.guid
		local evYear = date("*t", ev.t).year
		if G.announced[key] ~= evYear then
			G.announced[key] = evYear
			GM:Print(Events.Text(ev))
		end
	end
	-- forget old markers
	for key, y in pairs(G.announced) do
		if type(y) ~= "number" or y < year - 1 then G.announced[key] = nil end
	end
end
