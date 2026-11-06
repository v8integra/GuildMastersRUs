-- Guild Masters R Us - our own guild change log (kept per account, not synced).
-- Entry: { t = time, k = kind, n = name, g = guid, a = actor, x = { extra } }
local _, GM = ...
local L = GM.L
local U = GM.U
local Log = {}
GM.Log = Log

Log.KINDS = {
	"join", "rejoin", "leave", "kick", "promote", "demote", "level", "note", "onote", "custom",
	"rankname", "rename", "return", "inactive", "banwarn", "ban", "guildname", "info",
}

Log.KIND_NAMES = {
	join = L["Joined"], rejoin = L["Rejoined"], leave = L["Left"], kick = L["Kicked"],
	promote = L["Promotions"], demote = L["Demotions"], level = L["Level ups"],
	note = L["Public notes"], onote = L["Officer notes"], custom = L["Custom notes"],
	rankname = L["Rank renamed"], rename = L["Name changes"], ["return"] = L["Returned from inactivity"],
	inactive = L["Kick recommendations"], banwarn = L["Banned player warnings"], ban = L["Bans"],
	guildname = L["Guild renamed"], info = L["Addon notices"],
}

local COLORS = {
	join = "ff33ff66", rejoin = "ff33ff66", leave = "ffff9933", kick = "ffff5555",
	promote = "ff66ccff", demote = "ffcc99ff", level = "ffdddddd", note = "ffffee99", onote = "ffffcc66",
	custom = "ffffee99", rankname = "ff99ccff", rename = "ff99ffcc", ["return"] = "ff66ff99",
	inactive = "ffff7777", banwarn = "ffff2222", ban = "ffff5555", guildname = "ff99ccff", info = "ffaaaaaa",
}
Log.COLORS = COLORS

local function N(name) return name and U.DisplayName(name) or L["Unknown"] end
local function Q(s) return '"' .. tostring(s or "") .. '"' end

local function NoteText(e, label)
	local x = e.x or {}
	if (x.old or "") == "" then
		return L["%s's %s added: %s"]:format(N(e.n), label, Q(x.new))
	elseif (x.new or "") == "" then
		return L["%s's %s removed (was %s)"]:format(N(e.n), label, Q(x.old))
	end
	return L["%s's %s: %s → %s"]:format(N(e.n), label, Q(x.old), Q(x.new))
end

local FORMAT = {
	join = function(e)
		local x = e.x or {}
		local s = L["%s joined the guild"]:format(N(e.n))
		if e.a then s = s .. " " .. L["(invited by %s)"]:format(N(e.a)) end
		if x.level then s = s .. " " .. L["(level %d)"]:format(x.level) end
		return s
	end,
	rejoin = function(e)
		local x = e.x or {}
		local s = L["%s rejoined the guild"]:format(N(e.n))
		if e.a then s = s .. " " .. L["(invited by %s)"]:format(N(e.a)) end
		if x.times and x.times > 0 then s = s .. " - " .. L["in the guild %d time(s) before"]:format(x.times) end
		if x.gone then s = s .. ", " .. L["gone %s"]:format(U.FormatDuration(x.gone)) end
		if x.prevName then s = s .. ", " .. L["previously named %s"]:format(N(x.prevName)) end
		return s
	end,
	leave = function(e)
		local x = e.x or {}
		local s = L["%s left the guild"]:format(N(e.n))
		if x.alts and #x.alts > 0 then s = s .. " - " .. L["alts still in the guild: %s"]:format(table.concat(x.alts, ", ")) end
		return s
	end,
	kick = function(e)
		local x = e.x or {}
		local s = e.a and L["%s was kicked by %s"]:format(N(e.n), N(e.a)) or L["%s was kicked from the guild"]:format(N(e.n))
		if x.alts and #x.alts > 0 then s = s .. " - " .. L["alts still in the guild: %s"]:format(table.concat(x.alts, ", ")) end
		return s
	end,
	promote = function(e)
		local x = e.x or {}
		local s = L["%s was promoted from %s to %s"]:format(N(e.n), x.from or "?", x.to or "?")
		if e.a then s = s .. " " .. L["by %s"]:format(N(e.a)) end
		return s
	end,
	demote = function(e)
		local x = e.x or {}
		local s = L["%s was demoted from %s to %s"]:format(N(e.n), x.from or "?", x.to or "?")
		if e.a then s = s .. " " .. L["by %s"]:format(N(e.a)) end
		return s
	end,
	level = function(e)
		local x = e.x or {}
		local s = L["%s reached level %d"]:format(N(e.n), x.to or 0)
		if x.from and x.to and x.to - x.from > 1 then s = s .. " " .. L["(+%d levels)"]:format(x.to - x.from) end
		return s
	end,
	note = function(e) return NoteText(e, L["public note"]) end,
	onote = function(e) return NoteText(e, L["officer note"]) end,
	custom = function(e) return NoteText(e, L["custom note"]) end,
	rankname = function(e)
		local x = e.x or {}
		return L["Rank renamed: %s → %s"]:format(x.old or "?", x.new or "?")
	end,
	rename = function(e)
		local x = e.x or {}
		return L["%s changed their name to %s"]:format(N(x.old), N(x.new or e.n))
	end,
	["return"] = function(e)
		local x = e.x or {}
		return L["%s came back after %s offline"]:format(N(e.n), U.FormatDuration(x.away))
	end,
	inactive = function(e)
		local x = e.x or {}
		return L["%s has been offline %s - kick recommended"]:format(N(e.n), U.FormatDuration(x.away))
	end,
	banwarn = function(e)
		local x = e.x or {}
		local s = L["WARNING: %s is on the ban list!"]:format(N(e.n))
		if x.reason and x.reason ~= "" then s = s .. " " .. L["Reason: %s"]:format(x.reason) end
		return s
	end,
	ban = function(e)
		local x = e.x or {}
		if x.removed then return L["%s removed %s from the ban list"]:format(N(e.a), N(e.n)) end
		local s = L["%s banned %s"]:format(N(e.a), N(e.n))
		if x.alts and x.alts > 0 then s = s .. " " .. L["and %d alt(s)"]:format(x.alts) end
		if x.reason and x.reason ~= "" then s = s .. " - " .. x.reason end
		return s
	end,
	guildname = function(e)
		local x = e.x or {}
		return L["The guild was renamed from %s to %s"]:format(Q(x.old), Q(x.new))
	end,
	info = function(e) return (e.x and e.x.text) or "" end,
}

function Log.Text(e)
	local f = FORMAT[e.k]
	local ok, s = pcall(f or FORMAT.info, e)
	if not ok then s = tostring(e.k) end
	if e.x and e.x.fromLog then s = s .. " " .. L["(from the guild's event log)"] end
	return s
end

function Log.ColoredText(e)
	return "|c" .. (COLORS[e.k] or "ffffffff") .. Log.Text(e) .. "|r"
end

local function TypeSetting(kind)
	local types = GM.settings and GM.settings.logTypes
	return types and types[kind] or { log = true, chat = false }
end

-- Adds an entry; prints it to chat if that type is set to.
function Log.Add(G, e, quiet)
	e.t = e.t or U.Now()
	e.added = U.Now()
	local setting = TypeSetting(e.k)
	if setting.log ~= false then
		local log = G.log
		log[#log + 1] = e
		local max = (GM.settings and GM.settings.logMax) or 5000
		if #log > max then
			local extra = #log - max
			for _ = 1, extra do table.remove(log, 1) end
		end
	end
	if setting.chat and not quiet then
		GM:Print(Log.ColoredText(e))
	end
	GM:Fire("LOG_CHANGED", G)
end

function Log.Info(G, text)
	Log.Add(G, { k = "info", x = { text = text } })
end

function Log.Remove(G, entry)
	for i = #G.log, 1, -1 do
		if G.log[i] == entry then table.remove(G.log, i) break end
	end
	GM:Fire("LOG_CHANGED", G)
end

function Log.Clear(G)
	G.log = {}
	GM:Fire("LOG_CHANGED", G)
end

-- Entries since the last time the log window was opened.
function Log.NewCount(G)
	local since = G.logSeenAt or 0
	local n = 0
	for i = #G.log, 1, -1 do
		local e = G.log[i]
		if (e.added or e.t) > since and e.k ~= "info" then n = n + 1 end
	end
	return n
end
