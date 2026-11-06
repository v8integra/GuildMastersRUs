-- Guild Masters R Us - ban list.
-- G.bans[key] = { name, guid, reason, by, t, ts, removed, classFile }
-- key is the GUID when known, otherwise "n:" .. lower-case full name.
-- Removing a ban keeps a tombstone (removed = true) so the removal syncs too.
local _, GM = ...
local U = GM.U
local DB = GM.DB
local Bans = {}
GM.Bans = Bans

Bans.REASON_MAX = 100

function Bans.Key(guid, name)
	if guid then return guid end
	local k = U.NameKey(name)
	return k and ("n:" .. k) or nil
end

-- Active ban for this person (by GUID or name), or nil.
function Bans.Check(G, guid, name)
	if not G then return nil end
	if guid then
		local b = G.bans[guid]
		if b and not b.removed then return b, guid end
	end
	local nk = name and U.NameKey(name)
	if nk then
		local b = G.bans["n:" .. nk]
		if b and not b.removed then return b, "n:" .. nk end
		for key, b2 in pairs(G.bans) do
			if not b2.removed and b2.name and U.NameKey(b2.name) == nk then return b2, key end
		end
	end
	return nil
end

function Bans.Add(G, guid, name, reason, withAlts, now)
	now = now or U.Now()
	name = U.FullName(name)
	local key = Bans.Key(guid, name)
	if not key then return 0 end
	local me = U.MyName()
	reason = U.Truncate(U.Trim(reason or ""), Bans.REASON_MAX)
	local m = guid and DB.Find(G, guid)
	-- a name ban becomes a GUID ban once we know the GUID
	if guid and name then G.bans["n:" .. (U.NameKey(name) or "")] = nil end
	G.bans[key] = { name = name or (m and m.name), guid = guid, reason = reason, by = me, t = now, ts = now, classFile = m and m.classFile }
	if GM.Sync then GM.Sync.Broadcast(G, "B", key) end
	local altCount = 0
	if withAlts and guid and GM.Alts then
		for _, g in ipairs(GM.Alts.GroupMembersAll(G, guid)) do
			if g ~= guid then
				local alt = DB.Find(G, g)
				G.bans[g] = { name = alt and alt.name, guid = g, reason = reason, by = me, t = now, ts = now, classFile = alt and alt.classFile, altOf = guid }
				if GM.Sync then GM.Sync.Broadcast(G, "B", g) end
				altCount = altCount + 1
			end
		end
	end
	GM.Log.Add(G, { k = "ban", n = name or (m and m.name), g = guid, a = me, t = now, x = { reason = reason, alts = altCount } })
	GM:Fire("BANS_CHANGED", G)
	return altCount
end

function Bans.Remove(G, key, now)
	now = now or U.Now()
	local b = G.bans[key]
	if not b or b.removed then return end
	b.removed, b.ts = true, now
	if GM.Sync then GM.Sync.Broadcast(G, "B", key) end
	GM.Log.Add(G, { k = "ban", n = b.name, g = b.guid, a = U.MyName(), t = now, x = { removed = true } })
	GM:Fire("BANS_CHANGED", G)
end

-- Active bans as a sorted list of { key, ban }.
function Bans.List(G)
	local out = {}
	for key, b in pairs(G.bans) do
		if not b.removed then out[#out + 1] = { key = key, ban = b } end
	end
	table.sort(out, function(a, b) return (a.ban.t or 0) > (b.ban.t or 0) end)
	return out
end
