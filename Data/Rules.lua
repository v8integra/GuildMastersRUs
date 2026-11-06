-- Guild Masters R Us - kick / promote / demote rules and the safe list.
-- G.rules = {
--   kick = { enabled, days, minRankOrder, altAware },        -- offline >= days, rank order >= minRankOrder
--   promote = { { from, days, level }, ... },                 -- in rank `from` for >= days (and level >= level)
--   demote = { { from, days }, ... },                         -- in rank `from`, offline >= days
--   safe = { [guid] = { kick = untilTime|true, promote = ..., demote = ... } },
-- }
-- A promote/demote moves one rank per click (that's how /gpromote and /gdemote work).
local _, GM = ...
local L = GM.L
local U = GM.U
local DB = GM.DB
local Rules = {}
GM.Rules = Rules

function Rules.IsSafe(G, guid, kind, now)
	local s = G.rules.safe[guid]
	local v = s and s[kind]
	if v == true then return true end
	if type(v) == "number" then
		if v > (now or U.Now()) then return true end
		s[kind] = nil
	end
	return false
end

-- days = nil for "always"
function Rules.SetSafe(G, guid, kind, days)
	G.rules.safe[guid] = G.rules.safe[guid] or {}
	G.rules.safe[guid][kind] = days and (U.Now() + days * U.DAY) or true
	GM:Fire("RULES_CHANGED", G)
end

function Rules.ClearSafe(G, guid, kind)
	local s = G.rules.safe[guid]
	if s then s[kind] = nil end
	GM:Fire("RULES_CHANGED", G)
end

local function TimeInRank(m)
	local t = (m.promoted and m.promoted.t) or (m.joined and m.joined.t)
	return t
end
Rules.TimeInRankSince = TimeInRank

-- Members matching the kick rule: list of { m, reason, cmd }.
function Rules.KickMatches(G, now)
	now = now or U.Now()
	local r = G.rules.kick
	local out = {}
	if not r or not r.enabled or (r.days or 0) <= 0 then return out end
	for guid, m in pairs(G.members) do
		if not m.online and (m.rankOrder or 99) >= (r.minRankOrder or 2) and not Rules.IsSafe(G, guid, "kick", now) then
			local last = r.altAware and GM.Alts.GroupLastOnline(G, guid) or m.lastOnline
			if last and now - last >= r.days * U.DAY then
				out[#out + 1] = { m = m, cmd = "/gremove", reason = L["offline %s"]:format(U.FormatDuration(now - last)), sort = last }
			end
		end
	end
	table.sort(out, function(a, b) return a.sort < b.sort end)
	return out
end

function Rules.PromoteMatches(G, now)
	now = now or U.Now()
	local out = {}
	for _, rule in ipairs(G.rules.promote or {}) do
		for guid, m in pairs(G.members) do
			if m.rankOrder == rule.from and rule.from > 1 and not Rules.IsSafe(G, guid, "promote", now) then
				local since = TimeInRank(m)
				local okDays = (rule.days or 0) <= 0 or (since and now - since >= rule.days * U.DAY)
				local okLevel = (rule.level or 0) <= 0 or ((m.level or 0) >= rule.level)
				if okDays and okLevel then
					local rankNames = G.rankNames or {}
					out[#out + 1] = {
						m = m, cmd = "/gpromote", sort = since or now,
						reason = L["%s → %s"]:format(m.rank or "?", rankNames[rule.from - 1] or "?") ..
							(since and (", " .. L["in rank %s"]:format(U.FormatDuration(now - since))) or ""),
					}
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.sort < b.sort end)
	return out
end

function Rules.DemoteMatches(G, now)
	now = now or U.Now()
	local out = {}
	local numRanks = #(G.rankNames or {})
	for _, rule in ipairs(G.rules.demote or {}) do
		for guid, m in pairs(G.members) do
			if m.rankOrder == rule.from and (numRanks == 0 or rule.from < numRanks) and not m.online and not Rules.IsSafe(G, guid, "demote", now) then
				local last = GM.Alts.GroupLastOnline(G, guid) or m.lastOnline
				if last and (rule.days or 0) > 0 and now - last >= rule.days * U.DAY then
					local rankNames = G.rankNames or {}
					out[#out + 1] = {
						m = m, cmd = "/gdemote", sort = last,
						reason = L["%s → %s"]:format(m.rank or "?", rankNames[rule.from + 1] or "?") .. ", " .. L["offline %s"]:format(U.FormatDuration(now - last)),
					}
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.sort < b.sort end)
	return out
end

-- Alts whose rank differs from their main's: one step toward the main's rank.
function Rules.AltRankMatches(G)
	local out = {}
	for guid, m in pairs(G.members) do
		local mainGuid = GM.Alts.GetMain(G, guid)
		local main = mainGuid and mainGuid ~= guid and G.members[mainGuid]
		if main and m.rankOrder and main.rankOrder and m.rankOrder ~= main.rankOrder and main.rankOrder > 1
			and not Rules.IsSafe(G, guid, m.rankOrder > main.rankOrder and "promote" or "demote") then
			local up = m.rankOrder > main.rankOrder
			out[#out + 1] = {
				m = m, cmd = up and "/gpromote" or "/gdemote", sort = m.rankOrder,
				reason = L["main %s is %s"]:format(U.DisplayName(main.name), main.rank or "?"),
			}
		end
	end
	table.sort(out, function(a, b) return (a.m.name or "") < (b.m.name or "") end)
	return out
end

function Rules.Matches(G, kind, now)
	if kind == "kick" then return Rules.KickMatches(G, now) end
	if kind == "promote" then return Rules.PromoteMatches(G, now) end
	if kind == "demote" then return Rules.DemoteMatches(G, now) end
	if kind == "alts" then return Rules.AltRankMatches(G) end
	return {}
end

-- Told when a member comes online: mention it if they match a promote rule.
local noticed = {}
function Rules.OnlineNotice(G, m)
	if not (CanGuildPromote and CanGuildPromote()) then return end
	if noticed[m.guid] then return end
	for _, row in ipairs(Rules.PromoteMatches(G)) do
		if row.m == m then
			noticed[m.guid] = true
			GM:Print(L["%s matches your promotion rule and is online (%s). /gmru promote"]:format(U.ColorName(m), row.reason))
			return
		end
	end
end
