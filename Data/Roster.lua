-- Guild Masters R Us - reads the live guild roster into plain tables.
-- Prefers C_Club (what Forever's own guild UI uses); falls back to the legacy
-- GetGuildRosterInfo globals if C_Club comes back short. Secret values are dropped.
local _, GM = ...
local U = GM.U
local Safe = GM.Safe
local Roster = {}
GM.Roster = Roster

local P = Enum and Enum.ClubMemberPresence or {}
local OFFLINE = P.Offline or 3
local MOBILE = P.OnlineMobile or 2
local AWAY = P.Away or 4
local BUSY = P.Busy or 5
local UNKNOWN = P.Unknown or 0

local function FromClub(now)
	if not (C_Club and C_Club.GetGuildClubId and C_Club.GetClubMembers and C_Club.GetMemberInfo) then return nil end
	local ok, clubId = pcall(C_Club.GetGuildClubId)
	if not ok or not clubId or GM.IsSecret(clubId) then return nil end
	local okM, ids = pcall(C_Club.GetClubMembers, clubId)
	if not okM or type(ids) ~= "table" then return nil end
	local list = {}
	for _, memberId in ipairs(ids) do
		local okI, info = pcall(C_Club.GetMemberInfo, clubId, memberId)
		if okI and type(info) == "table" and not GM.IsSecret(info) then
			local guid = Safe(info.guid)
			local name = U.FullName(Safe(info.name))
			if guid and name then
				local presence = Safe(info.presence)
				local online = presence ~= nil and presence ~= OFFLINE and presence ~= UNKNOWN
				local r = {
					guid = guid,
					name = name,
					rank = Safe(info.guildRank),
					rankOrder = Safe(info.guildRankOrder),
					level = Safe(info.level),
					classID = Safe(info.classID),
					zone = Safe(info.zone),
					note = Safe(info.memberNote),
					oNote = Safe(info.officerNote),
					online = online,
					status = (presence == MOBILE and "mobile") or (presence == AWAY and "afk") or (presence == BUSY and "dnd") or (online and "online") or "offline",
					achievement = Safe(info.achievementPoints),
					prof1 = Safe(info.profession1Name), prof1Rank = Safe(info.profession1Rank),
					prof2 = Safe(info.profession2Name), prof2Rank = Safe(info.profession2Rank),
				}
				r.classFile = U.ClassFile(r.classID)
				if online then
					r.lastOnline = now
				else
					local y, m, d, h = Safe(info.lastOnlineYear), Safe(info.lastOnlineMonth), Safe(info.lastOnlineDay), Safe(info.lastOnlineHour)
					if y or m or d or h then r.lastOnline = U.ElapsedToTime(now, y, m, d, h) end
				end
				list[#list + 1] = r
			end
		end
	end
	return list
end

local function FromLegacy(now)
	if not (GetNumGuildMembers and GetGuildRosterInfo) then return nil end
	local ok, total = pcall(GetNumGuildMembers)
	if not ok or type(total) ~= "number" or GM.IsSecret(total) then return nil end
	local list = {}
	for i = 1, total do
		local okR, name, rank, rankIndex, level, _, zone, note, oNote, isOnline, status, classFile, achievement, _, isMobile, _, _, guid =
			pcall(GetGuildRosterInfo, i)
		guid = okR and Safe(guid)
		name = okR and U.FullName(Safe(name))
		if guid and name then
			rankIndex = Safe(rankIndex)
			local online = Safe(isOnline) and true or false
			status = Safe(status)
			local r = {
				guid = guid, name = name,
				rank = Safe(rank),
				rankOrder = rankIndex and (rankIndex + 1) or nil,
				level = Safe(level), zone = Safe(zone),
				note = Safe(note), oNote = Safe(oNote),
				online = online,
				status = (Safe(isMobile) and "mobile") or (status == 1 and "afk") or (status == 2 and "dnd") or (online and "online") or "offline",
				classFile = Safe(classFile),
				achievement = Safe(achievement),
			}
			if online then
				r.lastOnline = now
			elseif GetGuildRosterLastOnline then
				local okL, y, m, d, h = pcall(GetGuildRosterLastOnline, i)
				if okL and (y or m or d or h) and not (GM.IsSecret(y) or GM.IsSecret(d)) then
					r.lastOnline = U.ElapsedToTime(now, y, m, d, h)
				end
			end
			list[#list + 1] = r
		end
	end
	return list
end

-- Returns the roster list, or nil plus a reason when it can't be read reliably right now.
function Roster.Read(now)
	now = now or U.Now()
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
		local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
		if ok and locked == true then return nil, "lockdown" end
	end
	local club = FromClub(now)
	local count = club and #club or 0
	local total = 0
	if GetNumGuildMembers then
		local ok, n = pcall(GetNumGuildMembers)
		if ok and type(n) == "number" and not GM.IsSecret(n) then total = n end
	end
	if count == 0 or (total > 0 and count < total) then
		local legacy = FromLegacy(now)
		if legacy and #legacy > count then
			Roster.source = "legacy"
			return legacy
		end
	end
	if count == 0 then return nil, "empty" end
	Roster.source = "club"
	-- C_Club may leave notes out (the probe saw no officer notes even for the guild master);
	-- fill missing ones from the legacy roster, matched by GUID.
	local missing = false
	for _, r in ipairs(club) do
		if r.oNote == nil or r.note == nil then missing = true break end
	end
	if missing then
		local legacy = FromLegacy(now)
		if legacy then
			local byGuid = {}
			for _, r in ipairs(legacy) do byGuid[r.guid] = r end
			for _, r in ipairs(club) do
				local l = byGuid[r.guid]
				if l then
					if r.note == nil then r.note = l.note end
					if r.oNote == nil then r.oNote = l.oNote end
				end
			end
		end
	end
	return club
end

-- Current rank names by order (1 = guild master).
function Roster.RankNames()
	local names = {}
	if not GuildControlGetNumRanks then return names end
	local ok, n = pcall(GuildControlGetNumRanks)
	if not ok or type(n) ~= "number" or GM.IsSecret(n) then return names end
	for i = 1, n do
		local okR, name = pcall(GuildControlGetRankName, i)
		names[i] = okR and Safe(name) or nil
	end
	return names
end

-- Asks the server for a fresh roster (it answers with GUILD_ROSTER_UPDATE).
function Roster.Request()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		pcall(C_GuildInfo.GuildRoster)
	elseif GuildRoster then
		pcall(GuildRoster)
	end
end
