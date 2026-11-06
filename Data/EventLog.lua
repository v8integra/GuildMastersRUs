-- Guild Masters R Us - the server's guild event log (invite/join/promote/demote/remove/quit).
-- Times come back as "how long ago" (years, months, days, hours), so they're approximate:
-- about an hour for recent entries, coarser for older ones.
local _, GM = ...
local U = GM.U
local Safe = GM.Safe
local EventLog = {}
GM.EventLog = EventLog

function EventLog.Request()
	if QueryGuildEventLog then pcall(QueryGuildEventLog) end
end

function EventLog.Signature(e)
	return table.concat({ e.type or "", (e.p1 or ""):lower(), (e.p2 or ""):lower(), e.rank or "" }, "|")
end

-- Reads every entry. Returns a list of { type, p1, p2, rank, t, sig, elapsedHours }.
function EventLog.Read(now)
	now = now or U.Now()
	local list = {}
	if not (GetNumGuildEvents and GetGuildEventInfo) then return list end
	local ok, n = pcall(GetNumGuildEvents)
	if not ok or type(n) ~= "number" or GM.IsSecret(n) then return list end
	for i = 1, n do
		local okE, typ, p1, p2, rank, y, mo, d, h = pcall(GetGuildEventInfo, i)
		if okE then
			typ, p1, p2, rank = Safe(typ), Safe(p1), Safe(p2), Safe(rank)
			y, mo, d, h = Safe(y), Safe(mo), Safe(d), Safe(h)
			if typ then
				local e = {
					type = typ,
					p1 = p1, -- kept as given (usually no realm); compared with U.SameName
					p2 = p2,
					rank = rank,
					t = U.ElapsedToTime(now, y, mo, d, h),
				}
				e.elapsedHours = (now - e.t) / 3600
				e.sig = EventLog.Signature(e)
				list[#list + 1] = e
			end
		end
	end
	return list
end

-- The event's subject (who joined/left/was promoted) for each type.
function EventLog.Target(e)
	if e.type == "join" or e.type == "quit" then return e.p1 end
	return e.p2
end

-- The person who did it (inviter, promoter, kicker), if any.
function EventLog.Actor(e)
	if e.type == "invite" or e.type == "promote" or e.type == "demote" or e.type == "remove" then return e.p1 end
	return nil
end

-- Tolerance when comparing an event time with something we saw: wider for older entries.
function EventLog.Tolerance(e, now)
	local age = (now or U.Now()) - e.t
	if age < 86400 then return 2 * 3600 end
	if age < 30 * 86400 then return 30 * 3600 end
	return 20 * 86400
end

-- Most recent event of one of `types` about `name`, optionally not older than `since`.
function EventLog.FindLatest(events, types, name, since)
	local best
	for _, e in ipairs(events) do
		if types[e.type] and U.SameName(EventLog.Target(e), name) and (not since or e.t >= since) then
			if not best or e.t > best.t then best = e end
		end
	end
	return best
end

local function Bucket(t) return math.floor(t / 86400) end

function EventLog.IsSeen(G, e)
	local b = Bucket(e.t)
	local seen = G.evSeen
	return seen[e.sig .. "@" .. b] or seen[e.sig .. "@" .. (b - 1)] or seen[e.sig .. "@" .. (b + 1)]
end

function EventLog.MarkSeen(G, e, now)
	G.evSeen[e.sig .. "@" .. Bucket(e.t)] = now or U.Now()
end

-- Drops seen-markers older than 90 days.
function EventLog.Prune(G, now)
	local limit = (now or U.Now()) - 90 * 86400
	for k, t in pairs(G.evSeen) do
		if type(t) ~= "number" or t < limit then G.evSeen[k] = nil end
	end
end
