-- Guild Masters R Us - core: namespace, events, internal messages, slash commands.
local ADDON, GM = ...
GM = GM or {}
_G.GuildMastersRus = GM

GM.ADDON = ADDON
GM.PREFIX = "GMRU"
GM.VERSION = "0.9.0-beta"
GM.PROTOCOL = 1

local issecret = _G.issecretvalue or function() return false end
GM.IsSecret = issecret

-- Returns v unless it's a secret value (then nil), so callers never store or compare secrets.
function GM.Safe(v)
	if issecret(v) then return nil end
	return v
end

local function ToText(v)
	if issecret(v) then return "<secret>" end
	return tostring(v)
end

function GM:Print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = ToText((select(i, ...))) end
	print("|cff33ccffGMRU|r " .. table.concat(parts, " "))
end

-- Calls fn safely; returns ok plus fn's results.
function GM.Try(fn, ...)
	if type(fn) ~= "function" then return false, "missing" end
	return pcall(fn, ...)
end

local function Report(err)
	local handler = _G.geterrorhandler and _G.geterrorhandler()
	if handler then handler(err) else print(err) end
end

---------------------------------------------------------------------------
-- Game events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
GM.eventFrame = frame
GM.handlers = {}

function GM:On(event, fn)
	local list = self.handlers[event]
	if not list then
		list = {}
		self.handlers[event] = list
		frame:RegisterEvent(event)
	end
	list[#list + 1] = fn
end

frame:SetScript("OnEvent", function(_, event, ...)
	local list = GM.handlers[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], event, ...)
		if not ok then Report(err) end
	end
end)

---------------------------------------------------------------------------
-- Internal messages (data changed, roster scanned, ...)
---------------------------------------------------------------------------
GM.listeners = {}

function GM:Listen(msg, fn)
	local list = self.listeners[msg]
	if not list then
		list = {}
		self.listeners[msg] = list
	end
	list[#list + 1] = fn
end

function GM:Fire(msg, ...)
	local list = self.listeners[msg]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then Report(err) end
	end
end

---------------------------------------------------------------------------
-- Saved variables ready
---------------------------------------------------------------------------
GM.dbReady = {}
function GM:OnDBReady(fn)
	if self.db then fn() else self.dbReady[#self.dbReady + 1] = fn end
end

GM:On("ADDON_LOADED", function(_, name)
	if name ~= ADDON then return end
	GuildMastersRusDB = GuildMastersRusDB or {}
	GM.db = GuildMastersRusDB
	if GM.DB and GM.DB.Init then GM.DB.Init(GM.db) end
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		GM.prefixResult = C_ChatInfo.RegisterAddonMessagePrefix(GM.PREFIX)
	end
	for _, fn in ipairs(GM.dbReady) do
		local ok, err = pcall(fn)
		if not ok then Report(err) end
	end
	GM.dbReady = {}
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
GM.commands = {}
GM.commandHelp = {}

function GM:Command(names, help, fn)
	if type(names) == "string" then names = { names } end
	for _, n in ipairs(names) do self.commands[n] = fn end
	if help then self.commandHelp[#self.commandHelp + 1] = "/gmru " .. names[1] .. " - " .. help end
end

function GM.ShowHelp()
	GM:Print("Guild Masters R Us " .. GM.VERSION)
	for _, line in ipairs(GM.commandHelp) do GM:Print(line) end
end

SLASH_GUILDMASTERSRUS1 = "/gmru"
SLASH_GUILDMASTERSRUS2 = "/guildmasters"
SlashCmdList.GUILDMASTERSRUS = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "" then
		if GM.UI and GM.UI.Toggle then GM.UI.Toggle() else GM.ShowHelp() end
		return
	end
	local fn = GM.commands[cmd]
	if fn then fn(rest) else GM.ShowHelp() end
end
