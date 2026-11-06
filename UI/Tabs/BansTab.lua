-- Guild Masters R Us - Bans tab.
local _, GM = ...
local L = GM.L
local U = GM.U
local UI = GM.UI
local Bans = GM.Bans

local function PromptManualBan()
	local G = GM.G
	UI.Prompt(L["Name of the player to ban (Name or Name-Realm). Spell it exactly - it's how they'll be recognized."], "", function(name)
		if name == "" or name:find("%d") then return L["Please enter a valid name."] end
		local full = U.FullName(name:sub(1, 1):upper() .. name:sub(2))
		local m = GM.DB.FindByName(G, full, true)
		C_Timer.After(0, function()
			UI.Prompt(L["Reason for banning %s (optional):"]:format(U.DisplayName(m and m.name or full)), "", function(reason)
				Bans.Add(G, m and m.guid, m and m.name or full, reason, false)
			end, Bans.REASON_MAX)
		end)
	end, 60, UI.MemberCompleter(G, true, function(m) return GM.Bans.Check(G, m.guid, m.name) ~= nil end))
end

local function Build(f)
	f.body = CreateFrame("Frame", nil, f)
	f.body:SetAllPoints()
	local b = f.body
	local add = UI.Button(b, L["Add a ban..."], 120, 22, PromptManualBan, L["Ban someone by name, even if they were never in the guild."])
	add:SetPoint("TOPLEFT", 4, -1)
	f.remove = UI.Button(b, L["Remove selected ban"], 150, 22, function()
		local sel = f.list.selected
		if not sel then GM:Print(L["Select a ban first."]) return end
		UI.Confirm(L["Remove %s from the ban list?"]:format(U.DisplayName(sel.ban.name)), function()
			Bans.Remove(GM.G, sel.key)
			f.list:Select(nil)
		end)
	end)
	f.remove:SetPoint("LEFT", add, "RIGHT", 6, 0)
	f.total = UI.Text(b, "", "GameFontHighlightSmall")
	f.total:SetPoint("LEFT", f.remove, "RIGHT", 14, 0)
	f.syncInfo = UI.Text(b, "", "GameFontDisableSmall")
	f.syncInfo:SetPoint("TOPRIGHT", -8, -6)

	local list = UI.List(b, {
		{ key = "name", title = L["Name"], width = 150 },
		{ key = "status", title = L["Status"], width = 110 },
		{ key = "date", title = L["Ban date"], width = 86 },
		{ key = "by", title = L["Banned by"], width = 110 },
		{ key = "reason", title = L["Reason"], width = 200 },
	})
	list:SetPoint("TOPLEFT", 0, -28)
	list:SetPoint("BOTTOMRIGHT", 0, 0)
	list.onClick = function(row) list:Select(row) end
	list.keyOf = function(row) return row.key end
	list.onEnter = function(row, r)
		GameTooltip:SetOwner(r, "ANCHOR_CURSOR")
		GameTooltip:SetText(U.DisplayName(row.ban.name), 1, 0.3, 0.3)
		if row.ban.reason and row.ban.reason ~= "" then GameTooltip:AddLine(row.ban.reason, 1, 1, 1, true) end
		GameTooltip:Show()
	end
	f.list = list
end

local function Refresh(f, G)
	if not UI.GuildReady(f, G) then return end
	local rows = Bans.List(G)
	f.total:SetText(L["Total banned: %d"]:format(#rows))
	f.syncInfo:SetText(L["Shared with addon users of rank %d or higher"]:format(GM.DB.SyncRank(G, "ban")))
	f.list:SetRows(rows, function(row)
		local b = row.ban
		local m, former
		if b.guid then m, former = GM.DB.Find(G, b.guid) end
		if not m and b.name then m, former = GM.DB.FindByName(G, b.name, true) end
		local status = (m and not former) and ("|cffff3333" .. L["still in guild"] .. "|r") or (m and L["former member"] or L["never a member"])
		if b.altOf then status = status .. " " .. L["(alt)"] end
		return { U.DisplayName(b.name), status, b.t and GM.Notes.FormatDate(b.t) or "", b.by and U.DisplayName(b.by) or "", b.reason or "" }
	end)
end

UI.RegisterTab({ id = "bans", title = L["Bans"], order = 4, build = Build, refresh = Refresh })
