-- Guild Masters R Us - Phase 0 probe.
-- /gmru probe : asks the server for the roster and event log, then reports what came back.
-- Everything is also saved to GuildMastersRusDB.probe so the SavedVariables file can be reviewed.
local _, GM = ...
GM = GM or _G.GuildMastersRus

local issecret = GM.IsSecret
local Try = GM.Try
local OFFLINE = (Enum and Enum.ClubMemberPresence and Enum.ClubMemberPresence.Offline) or 3
local TIMEOUT = 6

-- Values that are safe to store in SavedVariables (secrets become a marker string).
local function Clean(v, depth)
	if issecret(v) then return "<secret>" end
	local t = type(v)
	if t == "table" then
		if (depth or 0) > 2 then return "<table>" end
		local out = {}
		for k, val in pairs(v) do
			if not issecret(k) then out[k] = Clean(val, (depth or 0) + 1) end
		end
		return out
	elseif t == "function" or t == "userdata" or t == "thread" then
		return "<" .. t .. ">"
	end
	return v
end
GM.Clean = Clean

local function Pack(ok, ...)
	if not ok then return nil, (...) end
	return { n = select("#", ...), ... }
end

local function CleanPacked(p)
	if not p then return nil end
	local out = {}
	for i = 1, p.n do out[i] = Clean(p[i]) end
	if p.n == 0 then out[1] = "<no returns>" end
	return out
end

local function Line(report, ...)
	report.lines[#report.lines + 1] = table.concat({ ... }, " ")
end

local function Bool(v)
	if v == nil then return "nil" end
	if issecret(v) then return "<secret>" end
	return tostring(v)
end

local function Call(report, label, fn, ...)
	local ok, res = Try(fn, ...)
	if fn == nil then
		Line(report, label .. ": |cffff6666missing|r")
		report.data.calls[label] = "missing"
	elseif not ok then
		Line(report, label .. ": |cffff6666error|r " .. tostring(res))
		report.data.calls[label] = "error: " .. tostring(res)
	else
		Line(report, label .. ": " .. Bool(res))
		report.data.calls[label] = Clean(res)
	end
	return ok and res
end

---------------------------------------------------------------------------
-- Sections
---------------------------------------------------------------------------

local CLUB_FIELDS = {
	"guid", "name", "guildRank", "guildRankOrder", "level", "classID", "race", "zone",
	"memberNote", "officerNote", "lastOnlineYear", "lastOnlineMonth", "lastOnlineDay",
	"lastOnlineHour", "profession1Name", "achievementPoints",
}

function GM.ProbeClub(report)
	Line(report, "|cffffd100-- Roster (C_Club) --|r")
	local d = { fields = {}, samplesOffline = {}, samplesOnline = {} }
	report.data.club = d
	if not (C_Club and C_Club.GetGuildClubId) then
		Line(report, "C_Club.GetGuildClubId: |cffff6666missing|r")
		return
	end
	local ok, clubId = Try(C_Club.GetGuildClubId)
	d.clubId = ok and Clean(clubId) or "error"
	if not ok or clubId == nil or issecret(clubId) then
		Line(report, "guild clubId: " .. tostring(d.clubId))
		return
	end
	local okM, ids = Try(C_Club.GetClubMembers, clubId)
	if not okM or type(ids) ~= "table" then
		Line(report, "GetClubMembers: |cffff6666" .. tostring(ids) .. "|r")
		d.membersError = tostring(ids)
		return
	end

	local total, online, offline, nilInfo, secretInfo = 0, 0, 0, 0, 0
	for _, f in ipairs(CLUB_FIELDS) do d.fields[f] = { on = 0, off = 0, secret = 0 } end
	for _, memberId in ipairs(ids) do
		total = total + 1
		local okI, info = Try(C_Club.GetMemberInfo, clubId, memberId)
		if not okI or info == nil then
			nilInfo = nilInfo + 1
		elseif issecret(info) then
			secretInfo = secretInfo + 1
		else
			local isOff = info.presence == OFFLINE
			if isOff then offline = offline + 1 else online = online + 1 end
			for _, f in ipairs(CLUB_FIELDS) do
				local v = info[f]
				local c = d.fields[f]
				if issecret(v) then
					c.secret = c.secret + 1
				elseif v ~= nil and v ~= "" then
					if isOff then c.off = c.off + 1 else c.on = c.on + 1 end
				end
			end
			local list = isOff and d.samplesOffline or d.samplesOnline
			if #list < 5 then list[#list + 1] = Clean(info) end
		end
	end
	d.total, d.online, d.offline, d.nilInfo, d.secretInfo = total, online, offline, nilInfo, secretInfo
	Line(report, ("members %d (online %d, offline %d, no info %d, secret info %d)"):format(
		total, online, offline, nilInfo, secretInfo))
	Line(report, "field: filled online / filled offline / secret")
	for _, f in ipairs(CLUB_FIELDS) do
		local c = d.fields[f]
		local color = (c.secret > 0 and "|cffff6666") or ((c.on + c.off == 0) and "|cffaaaaaa") or "|cff66ff66"
		Line(report, ("  %s%s|r: %d / %d / %d"):format(color, f, c.on, c.off, c.secret))
	end
end

function GM.ProbeLegacy(report)
	Line(report, "|cffffd100-- Legacy roster globals --|r")
	local d = {}
	report.data.legacy = d
	local p, err = Pack(Try(_G.GetNumGuildMembers))
	d.GetNumGuildMembers = CleanPacked(p) or err
	Line(report, "GetNumGuildMembers: " .. (p and table.concat(d.GetNumGuildMembers, ", ") or tostring(err)))
	p, err = Pack(Try(_G.GetGuildRosterInfo, 1))
	d.GetGuildRosterInfo1 = CleanPacked(p) or err
	Line(report, "GetGuildRosterInfo(1): " .. (p and (p.n .. " returns, name=" .. tostring(d.GetGuildRosterInfo1[1])) or tostring(err)))
	p, err = Pack(Try(_G.GetGuildRosterLastOnline, 1))
	d.GetGuildRosterLastOnline1 = CleanPacked(p) or err
	Line(report, "GetGuildRosterLastOnline(1): " .. (p and table.concat(d.GetGuildRosterLastOnline1, ", ") or tostring(err)))
end

function GM.ProbeEventLog(report)
	Line(report, "|cffffd100-- Guild event log --|r")
	local d = { types = {}, samples = {} }
	report.data.eventLog = d
	local ok, n = Try(_G.GetNumGuildEvents)
	if not ok then
		Line(report, "GetNumGuildEvents: |cffff6666" .. tostring(n) .. "|r")
		d.error = tostring(n)
		return
	end
	d.count = Clean(n)
	if issecret(n) or type(n) ~= "number" then
		Line(report, "GetNumGuildEvents: " .. tostring(d.count))
		return
	end
	local oldestHours, newestHours, withRealm, secretCount = nil, nil, 0, 0
	for i = 1, n do
		local p = Pack(Try(_G.GetGuildEventInfo, i))
		if p then
			local typ, p1, p2, rank, y, m, dd, h = p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8]
			local anySecret = false
			for j = 1, p.n do if issecret(p[j]) then anySecret = true end end
			if anySecret then
				secretCount = secretCount + 1
			else
				d.types[tostring(typ)] = (d.types[tostring(typ)] or 0) + 1
				if (type(p1) == "string" and p1:find("-", 1, true)) or (type(p2) == "string" and p2:find("-", 1, true)) then
					withRealm = withRealm + 1
				end
				-- Elapsed time ("how long ago"), approximated in hours.
				local hours = (tonumber(y) or 0) * 8760 + (tonumber(m) or 0) * 730 + (tonumber(dd) or 0) * 24 + (tonumber(h) or 0)
				if not oldestHours or hours > oldestHours then oldestHours = hours end
				if not newestHours or hours < newestHours then newestHours = hours end
			end
			if #d.samples < 25 then d.samples[#d.samples + 1] = CleanPacked(p) end
		end
	end
	d.oldestHoursAgo, d.newestHoursAgo, d.namesWithRealm, d.secretEntries = oldestHours, newestHours, withRealm, secretCount
	local typeText = {}
	for k, v in pairs(d.types) do typeText[#typeText + 1] = k .. "=" .. v end
	table.sort(typeText)
	Line(report, ("entries %d, secret %d, names with realm %d"):format(n, secretCount, withRealm))
	Line(report, "types: " .. (#typeText > 0 and table.concat(typeText, " ") or "none"))
	if oldestHours then
		Line(report, ("newest ~%dh ago, oldest ~%dd ago"):format(newestHours, math.floor(oldestHours / 24)))
	end
end

function GM.ProbePermissions(report)
	Line(report, "|cffffd100-- Guild, ranks, permissions --|r")
	report.data.calls = report.data.calls or {}
	local p = Pack(Try(_G.GetGuildInfo, "player"))
	report.data.guildInfo = CleanPacked(p)
	Line(report, "GetGuildInfo: " .. (p and table.concat(report.data.guildInfo, ", ") or "missing/error"))
	local gi = C_GuildInfo or {}
	Call(report, "IsGuildLeader", _G.IsGuildLeader)
	Call(report, "C_GuildInfo.IsGuildOfficer", gi.IsGuildOfficer)
	Call(report, "C_GuildInfo.CanViewOfficerNote", gi.CanViewOfficerNote)
	Call(report, "C_GuildInfo.CanEditOfficerNote", gi.CanEditOfficerNote)
	Call(report, "CanEditPublicNote", _G.CanEditPublicNote)
	Call(report, "CanGuildInvite", _G.CanGuildInvite)
	Call(report, "CanGuildPromote", _G.CanGuildPromote)
	Call(report, "CanGuildDemote", _G.CanGuildDemote)
	Call(report, "CanGuildRemove", _G.CanGuildRemove)
	Call(report, "C_ChatInfo.InChatMessagingLockdown", C_ChatInfo and C_ChatInfo.InChatMessagingLockdown)
	Call(report, "C_GuildInfo.SetNote exists", function() return type(gi.SetNote) == "function" end)
	Call(report, "C_GuildInfo.RemoveFromGuild exists", function() return type(gi.RemoveFromGuild) == "function" end)

	local ok, num = Try(_G.GuildControlGetNumRanks)
	local ranks = {}
	if ok and type(num) == "number" then
		for i = 1, num do
			local okR, name = Try(_G.GuildControlGetRankName, i)
			ranks[i] = okR and Clean(name) or "?"
		end
	end
	report.data.ranks = ranks
	Line(report, "ranks (" .. tostring(ok and Clean(num) or "error") .. "): " .. table.concat(ranks, ", "))
end

function GM.ProbeAddonMessage(report)
	Line(report, "|cffffd100-- Addon messages --|r")
	local d = {}
	report.data.addonMessage = d
	d.prefixResult = Clean(GM.prefixResult)
	Line(report, "RegisterAddonMessagePrefix(GMRU): " .. tostring(d.prefixResult))
	local result = GM.SendPing()
	d.sendResult = Clean(result)
	Line(report, "SendAddonMessage GUILD: " .. tostring(d.sendResult) .. " (0 = Success)")
	Line(report, "Pings and replies from guildmates print here as they arrive.")
end

---------------------------------------------------------------------------
-- Addon-message ping
---------------------------------------------------------------------------

function GM.SendPing()
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return "missing" end
	local ok, res = Try(C_ChatInfo.SendAddonMessage, GM.PREFIX, "PING:" .. GM.VERSION, "GUILD")
	if not ok then return "error: " .. tostring(res) end
	return res
end

GM:On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
	if issecret(prefix) or prefix ~= GM.PREFIX then return end
	if not issecret(text) and type(text) == "string" and text:sub(1, 5) ~= "PING:" and text:sub(1, 5) ~= "PONG:" then return end -- sync traffic isn't ours
	if issecret(text) or issecret(sender) then
		GM:Print("addon message received, but text or sender is secret")
		return
	end
	local db = GM.db
	if db then
		db.probeReceived = db.probeReceived or {}
		local list = db.probeReceived
		if #list < 50 then
			list[#list + 1] = { text = text, channel = Clean(channel), sender = sender, time = time() }
		end
	end
	local me = UnitName("player")
	local isSelf = sender == me or (type(sender) == "string" and sender:match("^([^-]+)") == me)
	GM:Print(("received %s from %s via %s%s"):format(text, sender, tostring(channel), isSelf and " (your own echo)" or ""))
	if not isSelf and text:sub(1, 5) == "PING:" then
		Try(C_ChatInfo.SendAddonMessage, GM.PREFIX, "PONG:" .. GM.VERSION, "WHISPER", sender)
	end
end)

---------------------------------------------------------------------------
-- Probe driver
---------------------------------------------------------------------------

local pending

local function Finish(reason)
	if not pending then return end
	local report = pending
	pending = nil
	report.data.waitedFor = reason
	report.data.rosterEvents = report.rosterEvents
	report.data.eventLogEvents = report.eventLogEvents
	Line(report, ("(roster update events %d, event log events %d, finished by %s)"):format(
		report.rosterEvents, report.eventLogEvents, reason))

	GM.ProbePermissions(report)
	GM.ProbeClub(report)
	GM.ProbeLegacy(report)
	GM.ProbeEventLog(report)
	GM.ProbeAddonMessage(report)

	for _, l in ipairs(report.lines) do GM:Print(l) end
	if GM.db then GM.db.probe = report.data end
	GM:Print("Saved to GuildMastersRusDB.probe. /reload or log out to write the file.")
	return report
end
GM.ProbeFinish = Finish

local function CheckDone()
	if pending and pending.rosterEvents > 0 and pending.eventLogEvents > 0 then Finish("events") end
end

GM:On("GUILD_ROSTER_UPDATE", function()
	if pending then pending.rosterEvents = pending.rosterEvents + 1; CheckDone() end
end)
GM:On("GUILD_EVENT_LOG_UPDATE", function()
	if pending then pending.eventLogEvents = pending.eventLogEvents + 1; CheckDone() end
end)

function GM.StartProbe()
	if pending then GM:Print("Probe already running...") return end
	if not IsInGuild() then GM:Print("You're not in a guild, so there's nothing to probe.") return end
	local build, buildNum, _, iface = GetBuildInfo()
	pending = {
		lines = {},
		rosterEvents = 0,
		eventLogEvents = 0,
		data = { time = time(), build = build, buildNum = buildNum, interface = iface, calls = {} },
	}
	Line(pending, ("|cffffd100== Probe: build %s (%s), interface %s ==|r"):format(
		tostring(build), tostring(buildNum), tostring(iface)))
	GM:Print("Probing... asking the server for the roster and event log (up to " .. TIMEOUT .. "s).")
	if C_GuildInfo and C_GuildInfo.GuildRoster then Try(C_GuildInfo.GuildRoster) end
	Try(_G.QueryGuildEventLog)
	local started = pending
	C_Timer.After(TIMEOUT, function()
		if pending == started then Finish("timeout") end
	end)
end

GM:Command("probe", "check what guild data this client gives addons (for bug reports)", GM.StartProbe)
GM:Command("ping", "send a test addon message to the guild", function()
	GM:Print("ping sent, result " .. tostring(GM.SendPing()) .. " (0 = Success)")
end)
