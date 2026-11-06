-- Guild Masters R Us - sync between guild members running the addon.
--
-- Synced: join dates (J), promotion dates (P), alt group membership (AG), group mains (AM),
-- custom notes (C), birthdays (BD), bans (B), guild-wide settings from the guild master (GS).
-- Every record carries the time it was edited (ts); the newest edit wins.
-- A record is only accepted when the sender's guild rank is allowed to send that kind.
--
-- Messages (prefix GMRU, GUILD channel unless noted):
--   H:ver:proto:syncOn:since    hello / request everything edited since `since`
--   I:ver:proto:syncOn          reply to a hello (whisper), for the sync users list
--   D:round:rec~rec~...         records; round = "live" or the requester's round id
-- Record: kind^field^field...  (fields escaped with U.Escape)
local _, GM = ...
local L = GM.L
local U = GM.U
local DB = GM.DB
local Sync = {}
GM.Sync = Sync

local MAX_MSG = 245
local SEND_INTERVAL = 0.5

Sync.users = {}
Sync.stats = { sent = 0, received = 0, applied = 0, rejected = 0 }

local queue = {}
local heard = {}        -- [kind:id] = ts, records seen on the channel this session
local rounds = {}       -- [round] = true when we scheduled a reply
local myRound           -- { id, since, started, got }

local function Enabled()
	return GM.settings and GM.settings.syncEnabled and GM.G and GM.G.initialized
end

local function Locked()
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
		local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
		return ok and locked == true
	end
	return false
end

local function MyRankOrder(G)
	local me = U.MyName()
	local m = DB.FindByName(G, me)
	if m and m.rankOrder then return m.rankOrder end
	local _, _, idx = GetGuildInfo("player")
	idx = GM.Safe(idx)
	return idx and (idx + 1) or 99
end

local function SenderRankOrder(G, sender)
	local m = DB.FindByName(G, sender)
	return m and m.rankOrder or nil
end

local function KindRank(G, kind)
	if kind == "B" then return DB.SyncRank(G, "ban") end
	if kind == "C" then return DB.SyncRank(G, "custom") end
	if kind == "GS" then return 1 end
	return DB.SyncRank(G, "general")
end

local function Allowed(G, kind, rankOrder)
	return rankOrder ~= nil and rankOrder <= (KindRank(G, kind) or 1)
end

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------
local function Join(kind, ...)
	local parts = { kind }
	for i = 1, select("#", ...) do parts[#parts + 1] = U.Escape((select(i, ...))) end
	return table.concat(parts, "^")
end

local function B(v) return v and "1" or "0" end

-- Returns encoded record, ts for (kind, id), or nil.
function Sync.Encode(G, kind, id)
	if kind == "GS" then
		local s = G.guildSettings
		if not s or not s.ts then return nil end
		return Join("GS", s.syncMinRank or "", s.banMinRank or "", s.customMinRank or "", s.joinNote or "", s.dateFormat or "", s.ts, s.by or ""), s.ts
	elseif kind == "B" then
		local b = G.bans[id]
		if not b or not b.ts then return nil end
		return Join("B", id, b.name or "", b.guid or "", b.reason or "", b.by or "", b.t or 0, b.ts, B(b.removed)), b.ts
	elseif kind == "AM" then
		local g = G.altGroups[id]
		if not g or not g.mainTs then return nil end
		return Join("AM", id, g.main or "", g.mainTs), g.mainTs
	end
	local m = DB.Find(G, id)
	if not m then return nil end
	if kind == "J" and m.joined and m.joined.ts then
		return Join("J", id, m.joined.t or 0, m.joined.ts, m.joined.src or ""), m.joined.ts
	elseif kind == "P" and m.promoted and m.promoted.ts then
		return Join("P", id, m.promoted.t or 0, m.promoted.ts), m.promoted.ts
	elseif kind == "AG" and m.alt and m.alt.ts then
		return Join("AG", id, m.alt.gid or "", m.alt.ts), m.alt.ts
	elseif kind == "C" and m.custom and m.custom.ts then
		return Join("C", id, m.custom.text or "", m.custom.ts), m.custom.ts
	elseif kind == "BD" and m.birthday and m.birthday.ts then
		return Join("BD", id, m.birthday.m or 0, m.birthday.d or 0, m.birthday.ts), m.birthday.ts
	end
	return nil
end

-- Every record edited after `since`, that our rank may send: list of { kind, id, ts }.
function Sync.Collect(G, since, myOrder)
	since = since or 0
	local out = {}
	local function Add(kind, id, ts)
		if ts and ts > since and (not myOrder or Allowed(G, kind, myOrder)) then out[#out + 1] = { kind = kind, id = id, ts = ts } end
	end
	for _, tbl in ipairs({ G.members, G.former }) do
		for guid, m in pairs(tbl) do
			Add("J", guid, m.joined and m.joined.ts)
			Add("P", guid, m.promoted and m.promoted.ts)
			Add("AG", guid, m.alt and m.alt.ts)
			Add("C", guid, m.custom and m.custom.ts)
			Add("BD", guid, m.birthday and m.birthday.ts)
		end
	end
	for gid, g in pairs(G.altGroups) do Add("AM", gid, g.mainTs) end
	for key, b in pairs(G.bans) do Add("B", key, b.ts) end
	if G.guildSettings then Add("GS", "gs", G.guildSettings.ts) end
	table.sort(out, function(a, b) return a.ts < b.ts end)
	return out
end

local function Num(s) return tonumber(s) end
local function Str(s) if s == nil or s == "" then return nil end return s end

-- Applies one decoded record. Returns true if it changed our data.
function Sync.Apply(G, f, senderOrder)
	local kind = f[1]
	if not Allowed(G, kind, senderOrder) then
		Sync.stats.rejected = Sync.stats.rejected + 1
		return false
	end
	if kind == "GS" then
		local ts = Num(f[7])
		if not ts or (G.guildSettings and (G.guildSettings.ts or 0) >= ts) then return false end
		G.guildSettings = {
			syncMinRank = Num(f[2]), banMinRank = Num(f[3]), customMinRank = Num(f[4]),
			joinNote = Str(f[5]), dateFormat = Str(f[6]), ts = ts, by = Str(f[8]),
		}
		return true
	elseif kind == "B" then
		local key, ts = f[2], Num(f[8])
		if not key or not ts then return false end
		local old = G.bans[key]
		if old and (old.ts or 0) >= ts then return false end
		G.bans[key] = { name = Str(f[3]), guid = Str(f[4]), reason = f[5] or "", by = Str(f[6]), t = Num(f[7]), ts = ts, removed = f[9] == "1" }
		return true
	elseif kind == "AM" then
		local gid, ts = f[2], Num(f[4])
		if not gid or not ts then return false end
		local g = G.altGroups[gid] or {}
		if (g.mainTs or 0) >= ts then return false end
		g.main, g.mainTs = Str(f[3]), ts
		G.altGroups[gid] = g
		return true
	end
	local m = DB.Find(G, f[2])
	if not m then return false end
	if kind == "J" then
		local ts = Num(f[4])
		if not ts or (m.joined and (m.joined.ts or 0) >= ts) then return false end
		local t = Num(f[3])
		m.joined = { t = (t and t > 0) and t or nil, ts = ts, src = Str(f[5]) or "sync" }
	elseif kind == "P" then
		local ts = Num(f[4])
		if not ts or (m.promoted and (m.promoted.ts or 0) >= ts) then return false end
		local t = Num(f[3])
		m.promoted = { t = (t and t > 0) and t or nil, ts = ts, src = "sync" }
	elseif kind == "AG" then
		local ts = Num(f[4])
		if not ts or (m.alt and (m.alt.ts or 0) >= ts) then return false end
		local gid = Str(f[3])
		m.alt = { gid = gid, ts = ts }
		if gid then G.altGroups[gid] = G.altGroups[gid] or {} end
	elseif kind == "C" then
		local ts = Num(f[4])
		if not ts or (m.custom and (m.custom.ts or 0) >= ts) then return false end
		m.custom = { text = U.Truncate(f[3] or "", GM.Notes.CUSTOM_MAX), ts = ts }
	elseif kind == "BD" then
		local ts = Num(f[5])
		if not ts or (m.birthday and (m.birthday.ts or 0) >= ts) then return false end
		local mo, d = Num(f[3]), Num(f[4])
		m.birthday = { m = (mo and mo > 0) and mo or nil, d = (d and d > 0) and d or nil, ts = ts }
	else
		return false
	end
	return true
end

function Sync.Decode(rec)
	local f = {}
	for part in (rec .. "^"):gmatch("(.-)%^") do f[#f + 1] = U.Unescape(part) end
	return f
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local function Send(msg, channel, target)
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
	local ok, res = pcall(C_ChatInfo.SendAddonMessage, GM.PREFIX, msg, channel or "GUILD", target)
	if not ok then return false end
	local throttled = Enum and Enum.SendAddonMessageResult and res == Enum.SendAddonMessageResult.AddonMessageThrottle
	if res == 3 or throttled then return false end
	Sync.stats.sent = Sync.stats.sent + 1
	return true
end

-- Packs queued records into one message, skipping ones someone else already sent.
local function PackRecords(G, job)
	local head = "D:" .. job.round .. ":"
	local parts, size = {}, #head
	while job.idx <= #job.list do
		local r = job.list[job.idx]
		local enc, ts = Sync.Encode(G, r.kind, r.id)
		local key = r.kind .. ":" .. r.id
		if enc and not (heard[key] and heard[key] >= ts) then
			if size + #enc + 1 > MAX_MSG and #parts > 0 then break end
			if #head + #enc <= MAX_MSG then
				parts[#parts + 1] = enc
				size = size + #enc + 1
				heard[key] = ts
			end
		end
		job.idx = job.idx + 1
	end
	if #parts == 0 then return nil end
	return head .. table.concat(parts, "~")
end

local function Pump()
	local job = queue[1]
	if not job or Locked() then return end
	local G = GM.G
	if job.raw then
		if Send(job.raw, job.channel, job.target) then table.remove(queue, 1) end
		return
	end
	if not G then table.remove(queue, 1) return end
	local saveIdx = job.idx
	local msg = PackRecords(G, job)
	if not msg then table.remove(queue, 1) return Pump() end
	if not Send(msg, "GUILD") then
		job.idx = saveIdx -- throttled, try again next tick
		return
	end
	if job.idx > #job.list then table.remove(queue, 1) end
end

local function Enqueue(job)
	queue[#queue + 1] = job
	if not Sync.ticker and C_Timer and C_Timer.NewTicker then
		Sync.ticker = C_Timer.NewTicker(SEND_INTERVAL, Pump)
	end
end
Sync.Pump = Pump
Sync.Queue = queue

-- Sends one changed record to everyone online right away.
function Sync.Broadcast(G, kind, id)
	if not Enabled() or G ~= GM.G then return end
	if not Allowed(G, kind, MyRankOrder(G)) then return end
	local last = queue[#queue]
	if last and not last.raw and last.round == "live" then
		last.list[#last.list + 1] = { kind = kind, id = id }
	else
		Enqueue({ round = "live", list = { { kind = kind, id = id } }, idx = 1 })
	end
end

-- Hello: announces us and asks for everything edited since our last sync.
function Sync.Hello(manual)
	local G = GM.G
	if not Enabled() then
		if manual then GM:Print(L["Sync is off (options) or the guild hasn't been scanned yet."]) end
		return
	end
	local since = G.lastSync or 0
	local id = U.ShortName(U.MyName()) .. tostring(U.Now() % 100000)
	myRound = { id = id, since = since, started = U.Now(), got = 0 }
	Enqueue({ raw = table.concat({ "H", GM.VERSION, GM.PROTOCOL, "1", since, id }, ":") })
	if manual then GM:Print(L["Sync requested from guildmates running the addon."]) end
	C_Timer.After(90, function()
		if myRound and myRound.id == id then
			if myRound.got > 0 then G.lastSync = myRound.started - 300 end
			if GM.settings.syncMessages or manual then
				GM:Print(L["Sync finished: %d update(s) received."]:format(myRound.got))
			end
			myRound = nil
			GM:Fire("SYNC_APPLIED", G)
		end
	end)
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function OnHello(G, sender, ver, proto, syncOn, since, roundId)
	Sync.users[sender] = { ver = ver, proto = tonumber(proto), syncOn = syncOn == "1", seen = U.Now() }
	GM:Fire("SYNC_USERS", G)
	Enqueue({ raw = table.concat({ "I", GM.VERSION, GM.PROTOCOL, GM.settings.syncEnabled and "1" or "0" }, ":"), channel = "WHISPER", target = sender })
	if not Enabled() or tonumber(proto) ~= GM.PROTOCOL or syncOn ~= "1" then return end
	roundId = roundId or sender
	if rounds[roundId] then return end
	rounds[roundId] = true
	local delay = 2 + math.random() * 8
	C_Timer.After(delay, function()
		local list = Sync.Collect(G, tonumber(since) or 0, MyRankOrder(G))
		if #list > 0 then Enqueue({ round = roundId, list = list, idx = 1 }) end
	end)
end

local function OnRecords(G, sender, round, payload)
	local user = Sync.users[sender]
	if user and user.proto and user.proto ~= GM.PROTOCOL then return end
	local order = SenderRankOrder(G, sender)
	local changed = 0
	for rec in (payload .. "~"):gmatch("(.-)~") do
		if rec ~= "" then
			Sync.stats.received = Sync.stats.received + 1
			local f = Sync.Decode(rec)
			local key = (f[1] or "") .. ":" .. (f[2] or "")
			local ts = tonumber(f[1] == "GS" and f[7] or f[1] == "B" and f[8] or f[1] == "BD" and f[5] or f[1] == "J" and f[4] or f[4])
			if ts and (not heard[key] or heard[key] < ts) then heard[key] = ts end
			if order and Sync.Apply(G, f, order) then
				changed = changed + 1
				Sync.stats.applied = Sync.stats.applied + 1
			end
		end
	end
	if myRound and round == myRound.id then myRound.got = myRound.got + changed end
	if changed > 0 then
		if GM.settings.syncMessages then GM:Print(L["Sync: %d update(s) from %s."]:format(changed, U.DisplayName(sender))) end
		GM:Fire("SYNC_APPLIED", G)
		GM:Fire("ROSTER_UPDATED", G)
	end
end

function Sync.OnMessage(text, channel, sender)
	local G = GM.G
	if not G or not G.initialized then return end
	sender = U.FullName(sender)
	if not sender or U.SameName(sender, U.MyName()) then return end
	local kind = text:sub(1, 1)
	if kind == "H" then
		local _, ver, proto, syncOn, since, roundId = strsplit(":", text)
		OnHello(G, sender, ver, proto, syncOn, since, roundId)
	elseif kind == "I" then
		local _, ver, proto, syncOn = strsplit(":", text)
		Sync.users[sender] = { ver = ver, proto = tonumber(proto), syncOn = syncOn == "1", seen = U.Now() }
		GM:Fire("SYNC_USERS", G)
	elseif kind == "D" and GM.settings.syncEnabled then
		local round, payload = text:match("^D:([^:]*):(.*)$")
		if round and payload then OnRecords(G, sender, round, payload) end
	end
end

GM:On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
	if GM.IsSecret(prefix) or prefix ~= GM.PREFIX then return end
	if GM.IsSecret(text) or GM.IsSecret(sender) or type(text) ~= "string" then return end
	if text:sub(1, 5) == "PING:" or text:sub(1, 5) == "PONG:" then return end -- handled by the probe
	Sync.OnMessage(text, channel, sender)
end)

-- Users list for the sync tab: sorted { name, ver, syncOn, rank, ok, status }.
function Sync.UserList(G)
	local out = {}
	local myOrder = MyRankOrder(G)
	for name, u in pairs(Sync.users) do
		local order = SenderRankOrder(G, name)
		local status
		if u.proto ~= GM.PROTOCOL then status = L["Different version"]
		elseif not u.syncOn then status = L["Sync off"]
		elseif not Allowed(G, "J", order) then status = L["Their rank is too low to send"]
		else status = L["OK"] end
		out[#out + 1] = { name = name, ver = u.ver, status = status, rankOrder = order, seen = u.seen }
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out, Allowed(G, "J", myOrder)
end

-- Guild master sets guild-wide settings and sends them out.
function Sync.SetGuildSettings(G, values)
	G.guildSettings = {
		syncMinRank = values.syncMinRank, banMinRank = values.banMinRank, customMinRank = values.customMinRank,
		joinNote = values.joinNote, dateFormat = values.dateFormat, ts = U.Now(), by = U.MyName(),
	}
	Sync.Broadcast(G, "GS", "gs")
	GM:Fire("SYNC_APPLIED", G)
end

function Sync.IsGuildMaster(G)
	return MyRankOrder(G) == 1
end
Sync.MyRankOrder = MyRankOrder
