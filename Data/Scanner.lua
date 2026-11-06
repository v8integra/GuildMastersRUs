-- Guild Masters R Us - roster change detection.
-- Run() diffs the live roster against what we stored and returns the changes;
-- Finish() matches them with the server's event log (who did it, and when) and logs them.
local _, GM = ...
local L = GM.L
local U = GM.U
local DB = GM.DB
local EventLog = GM.EventLog
local Scanner = {}
GM.Scanner = Scanner

local RECENT = 2 * 3600 -- an event older than this happened before we saw the change

-- Event-log names have no realm; use the member's full name when we know them.
local function Who(G, name)
	if not name then return nil end
	local m = DB.FindByName(G, name, true)
	return m and m.name or name
end

local FIELDS = { "name", "rank", "rankOrder", "level", "classID", "classFile", "zone", "online", "status", "achievement", "prof1", "prof1Rank", "prof2", "prof2Rank" }

local function NewMember(r)
	return { guid = r.guid, name = r.name, history = {}, rankHist = {}, prevNames = {}, timesJoined = 1 }
end

local function UpdateFields(m, r, now)
	for _, f in ipairs(FIELDS) do
		if r[f] ~= nil then m[f] = r[f] end
	end
	m.online = r.online and true or false
	if r.note ~= nil then m.note = r.note end
	if r.oNote ~= nil then m.oNote = r.oNote end
	if r.lastOnline then m.lastOnline = r.lastOnline elseif r.online then m.lastOnline = now end
	m.lastSeen = now
end

local function CountJoins(m)
	local n = 0
	for _, h in ipairs(m.history or {}) do if h.k == "join" then n = n + 1 end end
	return n
end

-- A guild with mostly the same members under another name is the same guild, renamed.
local function MigrateRenamed(G, roster, now)
	local db = GM.db
	if not db or not db.guilds then return end
	local ids = {}
	for _, r in ipairs(roster) do ids[r.guid] = true end
	for key, old in pairs(db.guilds) do
		if old ~= G and old.realm == G.realm and old.initialized then
			local total, shared = 0, 0
			for guid in pairs(old.members) do
				total = total + 1
				if ids[guid] then shared = shared + 1 end
			end
			if total >= 5 and shared >= total * 0.8 then
				for k, v in pairs(old) do
					if k ~= "key" and k ~= "name" and k ~= "realm" then G[k] = v end
				end
				db.guilds[key] = nil
				if db.backups then db.backups[G.key], db.backups[key] = db.backups[key], nil end
				return old.name
			end
		end
	end
end

-- Diffs the roster into G. Returns changes (list), or nil + reason if the roster looks incomplete.
function Scanner.Run(G, roster, now, rankNames)
	now = now or U.Now()
	if not roster or #roster == 0 then return nil, "empty" end
	local changes = {}

	if not G.initialized then
		local oldName = MigrateRenamed(G, roster, now)
		if oldName then
			changes[#changes + 1] = { k = "guildname", t = now, x = { old = oldName, new = G.name } }
		end
	end

	if not G.initialized then
		for _, r in ipairs(roster) do
			local m = NewMember(r)
			UpdateFields(m, r, now)
			G.members[r.guid] = m
		end
		G.rankNames = rankNames or G.rankNames or {}
		G.trackStart = now
		G.initialized = true
		G.lastScan = now
		changes.first = true
		changes[#changes + 1] = { k = "info", t = now, x = { text = L["Started tracking %d members of %s."]:format(#roster, G.name or "?") } }
		return changes
	end

	local stored = U.Count(G.members)
	if stored >= 10 and #roster < stored * 0.5 then return nil, "partial" end

	local s = GM.settings
	local present = {}
	for _, r in ipairs(roster) do
		present[r.guid] = true
		local m = G.members[r.guid]
		if not m then
			local f = G.former[r.guid]
			if f then
				m = f
				G.former[r.guid] = nil
				G.members[r.guid] = m
				local c = { k = "rejoin", m = m, t = now, x = { times = math.max(1, CountJoins(m)), gone = m.leftAt and (now - m.leftAt) or nil, level = r.level } }
				if m.name and not U.SameName(m.name, r.name) then c.x.prevName = m.name end
				m.timesJoined = (m.timesJoined or 1) + 1
				m.leftAt, m.leftHow = nil, nil
				changes[#changes + 1] = c
			else
				m = NewMember(r)
				G.members[r.guid] = m
				changes[#changes + 1] = { k = "join", m = m, t = now, x = { level = r.level } }
			end
			m.joined = { t = now, src = "seen", ts = now }
			m.history = m.history or {}
			m.history[#m.history + 1] = { k = "join", t = now }
			UpdateFields(m, r, now)
		else
			-- rename (same GUID, new name)
			if r.name and m.name and not U.SameName(m.name, r.name) then
				m.prevNames = m.prevNames or {}
				m.prevNames[#m.prevNames + 1] = m.name
				changes[#changes + 1] = { k = "rename", m = m, t = now, x = { old = m.name, new = r.name } }
			end
			-- rank change (lower order = higher rank)
			if r.rankOrder and m.rankOrder and r.rankOrder ~= m.rankOrder then
				local up = r.rankOrder < m.rankOrder
				local h = { from = m.rank, to = r.rank, t = now, up = up }
				m.rankHist = m.rankHist or {}
				m.rankHist[#m.rankHist + 1] = h
				m.promoted = { t = now, src = "seen", ts = now }
				changes[#changes + 1] = { k = up and "promote" or "demote", m = m, t = now, h = h, x = { from = m.rank, to = r.rank } }
			end
			-- level
			if r.level and m.level and r.level > m.level then
				changes[#changes + 1] = { k = "level", m = m, t = now, x = { from = m.level, to = r.level } }
			end
			-- notes (only when both old and new are known)
			if r.note ~= nil and m.note ~= nil and r.note ~= m.note then
				changes[#changes + 1] = { k = "note", m = m, t = now, x = { old = m.note, new = r.note } }
			end
			if r.oNote ~= nil and m.oNote ~= nil and r.oNote ~= m.oNote then
				changes[#changes + 1] = { k = "onote", m = m, t = now, x = { old = m.oNote, new = r.oNote } }
			end
			-- came online after a long time away (only trusted when they were offline at our last scan)
			if r.online and m.online == false and m.lastOnline then
				local away = now - m.lastOnline
				if away >= (s.inactiveReturnDays or 14) * U.DAY then
					changes[#changes + 1] = { k = "return", m = m, t = now, x = { away = away } }
				end
				if m.alerts and m.alerts.active and away >= (s.inactiveReturnDays or 14) * U.DAY then
					changes[#changes + 1] = { k = "alert", m = m, x = { what = "active" } }
				end
			end
			if m.alerts then
				if r.online and m.online == false and m.alerts.online then
					changes[#changes + 1] = { k = "alert", m = m, x = { what = "online" } }
				elseif not r.online and m.online == true and m.alerts.offline then
					changes[#changes + 1] = { k = "alert", m = m, x = { what = "offline" } }
				end
			end
			if r.online and m.online == false then
				changes[#changes + 1] = { k = "cameonline", m = m }
			end
			UpdateFields(m, r, now)
		end
	end

	-- leaves
	for guid, m in pairs(G.members) do
		if not present[guid] then
			G.members[guid] = nil
			G.former[guid] = m
			m.leftAt = now
			m.leftHow = "left"
			m.online = false
			m.history = m.history or {}
			local h = { k = "leave", t = now }
			m.history[#m.history + 1] = h
			changes[#changes + 1] = { k = "leave", m = m, t = now, h = h, x = {} }
		end
	end

	-- rank renames (only when the number of ranks didn't change)
	if rankNames and #rankNames > 0 then
		local old = G.rankNames or {}
		if #old == #rankNames then
			for i, name in ipairs(rankNames) do
				if old[i] and name and old[i] ~= name then
					changes[#changes + 1] = { k = "rankname", t = now, x = { old = old[i], new = name } }
				end
			end
		end
		G.rankNames = rankNames
	end

	G.lastScan = now
	return changes
end

---------------------------------------------------------------------------
-- Finish: event-log attribution, back-fill, logging, side effects
---------------------------------------------------------------------------
local JOIN = { join = true }
local INVITE = { invite = true }
local LEAVE = { quit = true, remove = true }
local RANK = { promote = true, demote = true }

local function Attribute(G, c, events, now)
	local m = c.m
	if not m then return end
	local since = (G.prevScan or G.trackStart or now) - 3600
	if c.k == "join" or c.k == "rejoin" then
		local e = EventLog.FindLatest(events, JOIN, m.name, since)
		if e then
			EventLog.MarkSeen(G, e, now)
			if now - e.t > RECENT then
				c.t = e.t
				m.joined.t, m.joined.ts = e.t, e.t
				m.history[#m.history].t = e.t
			end
		end
		local inv = EventLog.FindLatest(events, INVITE, m.name, since)
		if inv then
			EventLog.MarkSeen(G, inv, now)
			c.a = Who(G, inv.p1)
			m.invitedBy = c.a
		end
	elseif c.k == "leave" then
		local e = EventLog.FindLatest(events, LEAVE, m.name, since)
		if e then
			EventLog.MarkSeen(G, e, now)
			if e.type == "remove" then
				c.k = "kick"
				c.a = Who(G, e.p1)
				m.leftHow = "kick"
				if c.h then c.h.k, c.h.by = "kick", c.a end
			end
			if now - e.t > RECENT then
				c.t = e.t
				m.leftAt = e.t
				if c.h then c.h.t = e.t end
			end
		end
	elseif c.k == "promote" or c.k == "demote" then
		local e = EventLog.FindLatest(events, RANK, m.name, since)
		if e then
			EventLog.MarkSeen(G, e, now)
			c.a = Who(G, e.p1)
			if c.h then c.h.by = c.a end
			if now - e.t > RECENT then
				c.t = e.t
				if c.h then c.h.t = e.t end
				m.promoted.t, m.promoted.ts = e.t, e.t
			end
		end
	end
end

local function HasNear(list, kinds, t, tol)
	for _, h in ipairs(list or {}) do
		if (not kinds or kinds[h.k or "rank"]) and h.t and math.abs(h.t - t) <= tol then return true end
	end
	return false
end

-- Fills in missing join/promotion dates from the event log (first install, or members we never saw join).
local function Backfill(G, events, now)
	for _, m in pairs(G.members) do
		if not m.joined then
			local e = EventLog.FindLatest(events, JOIN, m.name)
			if e then
				m.joined = { t = e.t, src = "log", ts = e.t }
				m.history = m.history or {}
				if not HasNear(m.history, JOIN, e.t, EventLog.Tolerance(e, now)) then
					table.insert(m.history, 1, { k = "join", t = e.t })
				end
				local inv = EventLog.FindLatest(events, INVITE, m.name)
				if inv and not m.invitedBy then m.invitedBy = Who(G, inv.p1) end
			end
		end
		if not m.promoted then
			local e = EventLog.FindLatest(events, RANK, m.name)
			if e then
				m.promoted = { t = e.t, src = "log", ts = e.t }
				m.rankHist = m.rankHist or {}
				if not HasNear(m.rankHist, nil, e.t, EventLog.Tolerance(e, now)) then
					table.insert(m.rankHist, 1, { to = e.rank, t = e.t, by = Who(G, e.p1), up = e.type == "promote", fromLog = true })
				end
			end
		end
	end
end

-- Event-log entries for things that happened while nobody here was watching
-- (for example, someone joined and left while you were offline).
local function AwayEntries(G, events, now)
	local out = {}
	local start = (G.trackStart or now) - 3600
	for _, e in ipairs(events) do
		if e.t >= start and now - e.t <= 30 * U.DAY and not EventLog.IsSeen(G, e) and e.type ~= "invite" then
			local target = EventLog.Target(e)
			local m = DB.FindByName(G, target, true)
			local tol = EventLog.Tolerance(e, now)
			local skip = false
			if e.type == "join" then
				skip = m ~= nil and HasNear(m.history, JOIN, e.t, tol)
			elseif LEAVE[e.type] then
				skip = m ~= nil and HasNear(m.history, { leave = true, kick = true }, e.t, tol)
			elseif RANK[e.type] then
				skip = m ~= nil and HasNear(m.rankHist, nil, e.t, tol)
			end
			if not skip and target then
				local entry = { t = e.t, n = m and m.name or target, g = m and m.guid, x = { fromLog = true } }
				if e.type == "join" then
					entry.k = "join"
					local inv = EventLog.FindLatest(events, INVITE, target)
					if inv then entry.a = Who(G, inv.p1) end
				elseif e.type == "quit" then
					entry.k = "leave"
				elseif e.type == "remove" then
					entry.k, entry.a = "kick", Who(G, e.p1)
				else
					entry.k, entry.a = e.type, Who(G, e.p1)
					entry.x.from, entry.x.to = "?", e.rank
				end
				out[#out + 1] = entry
			end
			EventLog.MarkSeen(G, e, now)
		end
	end
	table.sort(out, function(a, b) return a.t < b.t end)
	return out
end

local function LevelWanted(level)
	local s = GM.settings
	if not level or level < (s.levelMin or 1) then return false end
	if s.levelMilestones then
		local max = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()
		return level % 10 == 0 or (max and level == max)
	end
	return true
end

local function AltNamesInGuild(G, m)
	local names = {}
	if GM.Alts then
		for _, guid in ipairs(GM.Alts.GroupMembers(G, m.guid)) do
			local alt = G.members[guid]
			if alt and guid ~= m.guid then names[#names + 1] = U.DisplayName(alt.name) end
		end
	end
	return names
end

local function KickRecommendations(G, now)
	local s = GM.settings
	local days = s.kickRecommendDays or 0
	if days <= 0 then return end
	for guid, m in pairs(G.members) do
		if not m.online then
			local last = GM.Alts and GM.Alts.GroupLastOnline(G, guid) or m.lastOnline
			if last and now - last >= days * U.DAY then
				local bucket = math.floor(last / U.DAY)
				local safe = G.rules and G.rules.safe and G.rules.safe[guid]
				if m.kickRec ~= bucket and not (safe and safe.kick) then
					m.kickRec = bucket
					GM.Log.Add(G, { k = "inactive", n = m.name, g = guid, t = now, x = { away = now - last } })
				end
			end
		end
	end
end

function Scanner.Finish(G, changes, events, now)
	now = now or U.Now()
	events = events or {}
	local Log = GM.Log
	local liveJoins = {}

	for _, c in ipairs(changes) do Attribute(G, c, events, now) end
	if #events > 0 then
		Backfill(G, events, now)
		if not changes.first then
			for _, e in ipairs(AwayEntries(G, events, now)) do Log.Add(G, e) end
		else
			for _, e in ipairs(events) do EventLog.MarkSeen(G, e, now) end
		end
		EventLog.Prune(G, now)
	end

	for _, c in ipairs(changes) do
		local m = c.m
		if c.k == "alert" then
			local what = c.x.what
			local text = (what == "online" and L["%s is now online."]) or (what == "offline" and L["%s went offline."]) or L["%s is active again."]
			GM:Print(text:format(U.ColorName(m)))
		elseif c.k == "cameonline" then
			if GM.Rules and GM.Rules.OnlineNotice then GM.Rules.OnlineNotice(G, m) end
		elseif c.k == "level" and not LevelWanted(c.x.to) then
			-- filtered out
		else
			local e = { k = c.k, t = c.t, n = m and m.name, g = m and m.guid, a = c.a, x = c.x }
			if (c.k == "leave" or c.k == "kick") and m then e.x.alts = AltNamesInGuild(G, m) end
			Log.Add(G, e)
			if (c.k == "join" or c.k == "rejoin") and m then
				local ban = GM.Bans and GM.Bans.Check(G, m.guid, m.name)
				if ban then
					Log.Add(G, { k = "banwarn", n = m.name, g = m.guid, t = c.t, x = { reason = ban.reason } })
					if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
						pcall(RaidNotice_AddMessage, RaidWarningFrame, L["GMRU: %s is on your guild's ban list!"]:format(U.DisplayName(m.name)), ChatTypeInfo.RAID_WARNING)
					end
				end
				if now - c.t <= RECENT then liveJoins[#liveJoins + 1] = m end
			end
		end
	end

	for _, m in ipairs(liveJoins) do
		if GM.Notes and GM.Notes.WriteJoinDate then GM.Notes.WriteJoinDate(G, m) end
	end
	KickRecommendations(G, now)
	G.prevScan = now
	GM:Fire("ROSTER_UPDATED", G)
end
