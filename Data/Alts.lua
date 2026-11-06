-- Guild Masters R Us - alt groups.
-- Each member can belong to one group: m.alt = { gid, ts }. Groups: G.altGroups[gid] = { main, mainTs }.
-- Timestamps let sync pick the newest edit.
local _, GM = ...
local U = GM.U
local DB = GM.DB
local Alts = {}
GM.Alts = Alts

local function GroupOf(m)
	return m and m.alt and m.alt.gid or nil
end
Alts.GroupOf = GroupOf

-- All guids (current and former) in the group of `guid`, including itself.
function Alts.GroupMembersAll(G, guid)
	local m = DB.Find(G, guid)
	local gid = GroupOf(m)
	if not gid then return { guid } end
	local out = {}
	for _, tbl in ipairs({ G.members, G.former }) do
		for g, mm in pairs(tbl) do
			if GroupOf(mm) == gid then out[#out + 1] = g end
		end
	end
	return out
end

-- Current members only.
function Alts.GroupMembers(G, guid)
	local out = {}
	for _, g in ipairs(Alts.GroupMembersAll(G, guid)) do
		if G.members[g] then out[#out + 1] = g end
	end
	if #out == 0 then out[1] = guid end
	return out
end

function Alts.GetMain(G, guid)
	local m = DB.Find(G, guid)
	local gid = GroupOf(m)
	local grp = gid and G.altGroups[gid]
	return grp and grp.main or nil
end

function Alts.IsMain(G, guid)
	return Alts.GetMain(G, guid) == guid
end

function Alts.IsAlt(G, guid)
	local main = Alts.GetMain(G, guid)
	return main ~= nil and main ~= guid
end

function Alts.HasGroup(G, guid)
	return GroupOf(DB.Find(G, guid)) ~= nil
end

-- Most recent last-online time across the group (an alt playing counts as the person playing).
function Alts.GroupLastOnline(G, guid)
	local best
	for _, g in ipairs(Alts.GroupMembers(G, guid)) do
		local m = G.members[g]
		local t = m and (m.online and U.Now() or m.lastOnline)
		if t and (not best or t > best) then best = t end
	end
	return best
end

local function SetGroup(G, m, gid, now)
	m.alt = { gid = gid, ts = now }
	GM:Fire("ALTS_CHANGED", G, m.guid)
	if GM.Sync then GM.Sync.Broadcast(G, "AG", m.guid) end
end

-- Puts altGuid into mainGuid's group (creating it if needed).
function Alts.Link(G, guid, otherGuid, now)
	now = now or U.Now()
	if guid == otherGuid then return false end
	local m, o = DB.Find(G, guid), DB.Find(G, otherGuid)
	if not m or not o then return false end
	local gid = GroupOf(m)
	if not gid then
		gid = GroupOf(o) or ("g" .. guid)
		if not GroupOf(o) then
			G.altGroups[gid] = G.altGroups[gid] or {}
		end
		SetGroup(G, m, gid, now)
	end
	G.altGroups[gid] = G.altGroups[gid] or {}
	if GroupOf(o) ~= gid then SetGroup(G, o, gid, now) end
	-- the first member of a new group becomes its main unless one is set
	local grp = G.altGroups[gid]
	if not grp.main then
		grp.main, grp.mainTs = guid, now
		if GM.Sync then GM.Sync.Broadcast(G, "AM", gid) end
	end
	return true
end

function Alts.Unlink(G, guid, now)
	now = now or U.Now()
	local m = DB.Find(G, guid)
	local gid = GroupOf(m)
	if not gid then return end
	SetGroup(G, m, nil, now)
	local grp = G.altGroups[gid]
	if grp and grp.main == guid then
		-- hand main status to another current member of the group, or clear it
		local nextMain
		for g, mm in pairs(G.members) do
			if GroupOf(mm) == gid then nextMain = g break end
		end
		grp.main, grp.mainTs = nextMain, now
		if GM.Sync then GM.Sync.Broadcast(G, "AM", gid) end
	end
end

function Alts.SetMain(G, guid, now)
	now = now or U.Now()
	local m = DB.Find(G, guid)
	if not m then return end
	local gid = GroupOf(m)
	if not gid then
		gid = "g" .. guid
		G.altGroups[gid] = G.altGroups[gid] or {}
		SetGroup(G, m, gid, now)
	end
	local grp = G.altGroups[gid]
	grp.main, grp.mainTs = guid, now
	GM:Fire("ALTS_CHANGED", G, guid)
	if GM.Sync then GM.Sync.Broadcast(G, "AM", gid) end
end

-- Main's display name for an alt, or nil.
function Alts.MainName(G, guid)
	local main = Alts.GetMain(G, guid)
	if not main or main == guid then return nil end
	local m = DB.Find(G, main)
	return m and m.name or nil
end

-- Number of distinct people (groups count once).
function Alts.CountAccounts(G)
	local groups, singles, mains = {}, 0, 0
	for guid, m in pairs(G.members) do
		local gid = GroupOf(m)
		if gid then groups[gid] = true else singles = singles + 1 end
		if Alts.IsMain(G, guid) then mains = mains + 1 end
	end
	return U.Count(groups) + singles, mains
end
