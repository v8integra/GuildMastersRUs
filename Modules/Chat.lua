-- Guild Masters R Us - chat features:
--  * main tag: alts get their main's name after their own in chat, e.g.  [Bobalt] (Bob): hi
--    (uses Blizzard's sender-name filter; skipped automatically when the name is secret)
--  * !note: a member types "!note my text" in guild chat and your addon sets their public note
--    (only when you've switched it on and your rank can edit public notes)
local _, GM = ...
local L = GM.L
local U = GM.U
local DB = GM.DB

local index = {}   -- lower-case full name -> guid

local function Rebuild(G)
	index = {}
	if not G then return end
	for guid, m in pairs(G.members) do
		local k = U.NameKey(m.name)
		if k then index[k] = guid end
	end
end
GM:Listen("ROSTER_UPDATED", Rebuild)
GM:Listen("ALTS_CHANGED", function(G) Rebuild(G) end)

local TAG_EVENTS = {
	CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true, CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
	CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true,
	CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
	CHAT_MSG_WHISPER = true, CHAT_MSG_WHISPER_INFORM = true, CHAT_MSG_SAY = true, CHAT_MSG_YELL = true,
	CHAT_MSG_GUILD_ACHIEVEMENT = true,
}

function GM.MainTagFor(senderName)
	local s = GM.settings
	local G = GM.G
	if not (s and s.mainTag and G) then return nil end
	local guid = index[U.NameKey(senderName) or ""]
	if not guid then return nil end
	local main = GM.Alts.GetMain(G, guid)
	local color = s.mainTagColor or "ff9d9d9d"
	if main and main ~= guid then
		local mm = DB.Find(G, main)
		if mm then return "|c" .. color .. "(" .. U.ShortName(mm.name) .. ")|r" end
	elseif main == guid and s.mainTagOnMains then
		return "|c" .. color .. "(" .. L["M"] .. ")|r"
	end
	return nil
end

local function SenderFilter(event, decorated, text, senderName)
	if not TAG_EVENTS[event] then return nil end
	if GM.IsSecret(senderName) or GM.IsSecret(decorated) or type(senderName) ~= "string" or type(decorated) ~= "string" then return nil end
	local tag = GM.MainTagFor(senderName)
	if not tag then return nil end
	return decorated .. " " .. tag
end

if ChatFrameUtil and ChatFrameUtil.AddSenderNameFilter then
	ChatFrameUtil.AddSenderNameFilter(SenderFilter)
	GM.mainTagAvailable = true
end

---------------------------------------------------------------------------
-- !note
---------------------------------------------------------------------------
local recent = {}
GM:On("CHAT_MSG_GUILD", function(_, text, sender)
	local s = GM.settings
	if not (s and s.noteTrigger) then return end
	if GM.IsSecret(text) or GM.IsSecret(sender) or type(text) ~= "string" then return end
	local note = text:match("^!note%s+(.+)$")
	if not note then return end
	if not GM.Notes.CanEdit("public") then return end
	local G = GM.G
	local m = G and DB.FindByName(G, sender)
	if not m then return end
	note = U.Truncate(U.Trim(note), GM.Notes.NOTE_MAX)
	local key = m.guid .. note
	if recent[key] and GetTime() - recent[key] < 10 then return end
	recent[key] = GetTime()
	-- small random wait so several officers don't all write at once; skip if someone already did
	C_Timer.After(math.random() * 3, function()
		if m.note == note then return end
		if GM.Notes.Set(m.guid, "public", note) then
			m.note = note
			GM:Print(L["Set %s's public note to \"%s\" (!note)."]:format(U.DisplayName(m.name), note))
		end
	end)
end)
