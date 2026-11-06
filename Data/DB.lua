-- Guild Masters R Us - saved data layout and access.
--
-- GuildMastersRusDB = {
--   version, settings = {...},
--   guilds = { ["Realm:Guild Name"] = G },
--   backups = { [guildKey] = { {t, label, data}, ... } },
-- }
-- G (one guild) = {
--   key, name, realm, initialized, trackStart, lastScan,
--   members = { [guid] = M },   -- in the guild now
--   former  = { [guid] = M },   -- left (kept so rejoins are recognized)
--   log = { entry, ... }, logSeenAt,
--   bans = { [key] = ban }, altGroups = { [gid] = { main, mainTs } },
--   rankNames = { [order] = name }, evSeen = { [sig] = t },
--   rules = {...}, announced = { [key] = year }, guildSettings = {...}, lastSync,
-- }
-- M (one member) = {
--   guid, name, rank, rankOrder, level, classID, classFile, zone, note, oNote,
--   online, status, lastOnline, lastSeen, achievement,
--   joined = { t, src, ts }, promoted = { t, src, ts },
--   history = { { k = "join"|"leave"|"kick", t, by } }, rankHist = { { from, to, t, by, up } },
--   custom = { text, ts }, birthday = { m, d, ts }, alt = { gid, ts },
--   alerts = { online, offline, active }, prevNames = { ... }, leftAt, leftHow, kickRec, safe = {...},
-- }
local _, GM = ...
local U = GM.U
local DB = {}
GM.DB = DB

DB.DEFAULTS = {
	-- log and chat output, per entry type: { log = bool, chat = bool }
	logTypes = {
		join = { log = true, chat = true },
		rejoin = { log = true, chat = true },
		leave = { log = true, chat = true },
		kick = { log = true, chat = true },
		promote = { log = true, chat = true },
		demote = { log = true, chat = true },
		level = { log = true, chat = false },
		note = { log = true, chat = false },
		onote = { log = true, chat = false },
		custom = { log = true, chat = false },
		rankname = { log = true, chat = true },
		rename = { log = true, chat = true },
		["return"] = { log = true, chat = true },
		inactive = { log = true, chat = false },
		banwarn = { log = true, chat = true },
		ban = { log = true, chat = true },
		guildname = { log = true, chat = true },
		info = { log = true, chat = false },
	},
	logMax = 5000,
	showLogOnLogin = false,
	showLogOnlyIfNew = true,
	scanInterval = 60,          -- seconds between roster refresh requests
	inactiveReturnDays = 14,    -- "back after N days" threshold
	kickRecommendDays = 180,    -- 0 = off
	levelMin = 1,               -- don't report levels below this
	levelMilestones = false,    -- only every 10 levels and max level
	mainTag = true,             -- show the main's name next to alts in chat
	mainTagOnMains = false,     -- also tag mains with (M)
	mainTagColor = "ff9d9d9d",
	cardOnMouseover = true,
	groupNotices = true,        -- chat notice for former/banned guildies in your group
	tradeDots = true,
	announceEvents = true,
	announceDays = 3,
	birthdays = true,
	noteTrigger = false,        -- !note in guild chat sets the sender's public note
	joinNote = "off",           -- "off" | "public" | "officer": write join date into a note on join
	dateFormat = "ymd",
	noteDayFirst = false,       -- reading 05/06/2026 from notes: true = 5 June
	syncEnabled = true,
	syncMinRank = 2,            -- rank order (1 = guild master) that can send general data
	syncBanMinRank = 2,
	syncCustomMinRank = 10,
	syncMessages = false,       -- print sync progress
	minimap = { show = true, angle = 200 },
	windows = {},
}

local function ApplyDefaults(target, defaults)
	for k, v in pairs(defaults) do
		if target[k] == nil then
			target[k] = U.Copy(v)
		elseif type(v) == "table" and type(target[k]) == "table" then
			ApplyDefaults(target[k], v)
		end
	end
end
DB.ApplyDefaults = ApplyDefaults

function DB.Init(db)
	db.version = db.version or 1
	db.settings = db.settings or {}
	ApplyDefaults(db.settings, DB.DEFAULTS)
	db.guilds = db.guilds or {}
	db.backups = db.backups or {}
	GM.settings = db.settings
end

function DB.NewGuild(key, name, realm)
	return {
		key = key, name = name, realm = realm,
		initialized = false,
		members = {}, former = {}, log = {}, bans = {}, altGroups = {},
		rankNames = {}, evSeen = {}, announced = {},
		rules = {
			kick = { enabled = true, days = 180, minRankOrder = 3, altAware = true },
			promote = {},   -- { from = order, days = N, level = N }
			demote = {},    -- { from = order, days = N (offline) }
			safe = {},      -- [guid] = { kick = until|true, promote = ..., demote = ... }
		},
		guildSettings = nil,
		lastSync = 0,
	}
end

-- Current guild's key, or nil when not in a guild / guild info not loaded yet.
function DB.CurrentKey()
	if not IsInGuild or not IsInGuild() then return nil end
	local name, _, _, realm = GetGuildInfo("player")
	if not name or GM.IsSecret(name) then return nil end
	if not realm or realm == "" or GM.IsSecret(realm) then realm = U.MyRealm() end
	return realm .. ":" .. name, name, realm
end

-- The current guild's data table (created on first use).
function DB.Guild()
	local db = GM.db
	if not db then return nil end
	local key, name, realm = DB.CurrentKey()
	if not key then return nil end
	local G = db.guilds[key]
	if not G then
		G = DB.NewGuild(key, name, realm)
		db.guilds[key] = G
	end
	G.name, G.realm = name, realm
	GM.G = G
	return G
end

function DB.Find(G, guid)
	if not G or not guid then return nil end
	local m = G.members[guid]
	if m then return m, false end
	m = G.former[guid]
	if m then return m, true end
	return nil
end

-- Current member by name (full or short); falls back to former members.
function DB.FindByName(G, name, includeFormer)
	if not G or not name then return nil end
	local key = U.NameKey(name)
	local short = U.ShortName(name):lower()
	local shortHit
	for guid, m in pairs(G.members) do
		local mk = U.NameKey(m.name)
		if mk == key then return m, false end
		if not shortHit and U.ShortName(m.name):lower() == short then shortHit = m end
	end
	if shortHit then return shortHit, false end
	if includeFormer then
		for _, m in pairs(G.former) do
			if U.NameKey(m.name) == key then return m, true end
		end
		for _, m in pairs(G.former) do
			if U.ShortName(m.name):lower() == short then return m, true end
		end
	end
	return nil
end

-- Effective sync thresholds (the guild master's guild-wide settings win when present).
function DB.SyncRank(G, which)
	local s = GM.settings
	local gs = G and G.guildSettings
	if which == "ban" then return (gs and gs.banMinRank) or s.syncBanMinRank end
	if which == "custom" then return (gs and gs.customMinRank) or s.syncCustomMinRank end
	return (gs and gs.syncMinRank) or s.syncMinRank
end

function DB.JoinNoteSetting(G)
	local gs = G and G.guildSettings
	return (gs and gs.joinNote) or GM.settings.joinNote, (gs and gs.dateFormat) or GM.settings.dateFormat
end

function DB.ResetGuild(key)
	if GM.db and key then
		GM.db.guilds[key] = nil
		if GM.G and GM.G.key == key then GM.G = nil end
	end
end

function DB.ResetAll()
	if not GM.db then return end
	for k in pairs(GM.db) do GM.db[k] = nil end
	DB.Init(GM.db)
	GM.G = nil
end
