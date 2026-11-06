-- Guild Masters R Us - startup and the scan loop.
local _, GM = ...
local L = GM.L
local U = GM.U
local DB = GM.DB

local scanQueued, finishing = false, false
local sessionStarted = false
local lastEventLogRead = 0
local ticker

local function FirstFinishOfSession(G)
	if sessionStarted then return end
	sessionStarted = true
	GM.Events.Announce(G)
	GM.Backup.Auto(G)
	local s = GM.settings
	if s.showLogOnLogin and GM.UI and GM.UI.Open then
		if not s.showLogOnlyIfNew or GM.Log.NewCount(G) > 0 then GM.UI.Open("log") end
	elseif GM.Log.NewCount(G) > 0 then
		GM:Print(L["%d new guild change(s) since you last looked. Type /gmru log to see them."]:format(GM.Log.NewCount(G)))
	end
	C_Timer.After(20, function() GM.Sync.Hello(false) end)
end

local function Finish(G, changes, now)
	finishing = false
	local events = GM.EventLog.Read(U.Now())
	lastEventLogRead = U.Now()
	GM.Scanner.Finish(G, changes, events, now)
	FirstFinishOfSession(G)
end

function GM.ScanNow(manual)
	local G = DB.Guild()
	if not G then
		if manual then GM:Print(L["You're not in a guild (or the guild info hasn't loaded yet)."]) end
		return
	end
	if finishing then return end
	local now = U.Now()
	local roster, why = GM.Roster.Read(now)
	if not roster then
		if manual then GM:Print(L["Couldn't read the roster right now (%s). Trying again shortly."]:format(why or "?")) end
		C_Timer.After(15, function() GM.Roster.Request() end)
		return
	end
	local changes, why2 = GM.Scanner.Run(G, roster, now, GM.Roster.RankNames())
	if not changes then
		if manual then GM:Print(L["The roster came back incomplete (%s); not scanning this time."]:format(why2 or "?")) end
		C_Timer.After(10, function() GM.Roster.Request() end)
		return
	end
	local real = changes.first
	for _, c in ipairs(changes) do
		if c.k ~= "cameonline" and c.k ~= "alert" then real = true break end
	end
	if real or now - lastEventLogRead > 600 or not sessionStarted then
		-- ask for the event log so changes get "who did it" and the right time
		finishing = true
		local waiting = true
		GM._eventLogWaiter = function()
			if waiting then waiting = false Finish(G, changes, now) end
		end
		GM.EventLog.Request()
		C_Timer.After(3, function()
			if waiting then waiting = false Finish(G, changes, now) end
		end)
	else
		GM.Scanner.Finish(G, changes, {}, now)
	end
	if manual then GM:Print(L["Scan done."]) end
end

GM:On("GUILD_EVENT_LOG_UPDATE", function()
	local w = GM._eventLogWaiter
	if w then GM._eventLogWaiter = nil w() end
end)

GM:On("GUILD_ROSTER_UPDATE", function()
	if scanQueued then return end
	scanQueued = true
	C_Timer.After(2, function()
		scanQueued = false
		GM.ScanNow(false)
	end)
end)

local function StartTicker()
	if ticker then ticker:Cancel() end
	local interval = math.max(20, GM.settings.scanInterval or 60)
	ticker = C_Timer.NewTicker(interval, function()
		if IsInGuild() then GM.Roster.Request() end
	end)
end
GM.RestartScanTicker = StartTicker

GM:On("PLAYER_LOGIN", function()
	StartTicker()
	C_Timer.After(5, function()
		if IsInGuild() then GM.Roster.Request() end
	end)
end)

GM:On("PLAYER_GUILD_UPDATE", function()
	if IsInGuild() then
		C_Timer.After(3, function() GM.Roster.Request() end)
	else
		GM.G = nil
		GM:Fire("ROSTER_UPDATED", nil)
	end
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
GM:Command("scan", L["scan the roster for changes now"], function()
	GM.Roster.Request()
	C_Timer.After(1.5, function() GM.ScanNow(true) end)
end)

GM:Command("sync", L["ask guildmates running the addon for updates"], function() GM.Sync.Hello(true) end)

GM:Command({ "version", "ver" }, L["show the addon version"], function()
	GM:Print(L["Version %s"]:format(GM.VERSION))
end)

GM:Command("help", nil, GM.ShowHelp)

GM:Command("resetguild", L["delete all saved data for this guild"], function()
	local G = DB.Guild()
	if not G then return end
	GM.UI.Confirm(L["Delete ALL saved Guild Masters R Us data for %s? This can't be undone (restore points are kept)."]:format(G.name or "?"), function()
		DB.ResetGuild(G.key)
		GM:Print(L["Guild data reset."])
		GM.Roster.Request()
	end)
end)

GM:Command("resetall", L["delete ALL saved data and settings"], function()
	GM.UI.Confirm(L["Delete ALL Guild Masters R Us data for every guild, plus your settings? This can't be undone."], function()
		DB.ResetAll()
		GM:Print(L["Everything was reset. Type /reload to finish."])
	end)
end)
