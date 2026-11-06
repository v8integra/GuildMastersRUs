-- Guild Masters R Us - hooks into Blizzard's guild roster and right-click menus.
-- Only post-hooks (HookScript / ScrollBox callbacks / Menu.ModifyMenu): nothing of Blizzard's is replaced.
local _, GM = ...
local L = GM.L
local U = GM.U

local hooked = false

local function IsGuildView(cf)
	if not (cf and cf.GetSelectedClubId and C_Club and C_Club.GetGuildClubId) then return false end
	local ok, sel = pcall(cf.GetSelectedClubId, cf)
	local ok2, guild = pcall(C_Club.GetGuildClubId)
	return ok and ok2 and sel ~= nil and sel == guild
end

local function Host(cf)
	local detail = cf.GuildMemberDetailFrame
	if detail and detail:IsShown() then return detail end
	return cf
end

local function EntryGuid(entry)
	local info = entry.GetMemberInfo and entry:GetMemberInfo()
	return info and GM.Safe(info.guid) or nil
end

local function HookEntry(entry)
	if entry.gmruHooked then return end
	entry.gmruHooked = true
	entry:HookScript("OnEnter", function(self)
		local cf = _G.CommunitiesFrame
		if not GM.settings.cardOnMouseover or not IsGuildView(cf) then return end
		local guid = EntryGuid(self)
		if guid then GM.Card.Show(guid, false, Host(cf)) end
	end)
	entry:HookScript("OnLeave", function() GM.Card.HideIfNotPinned() end)
	entry:HookScript("OnClick", function(self, button)
		local cf = _G.CommunitiesFrame
		if button ~= "LeftButton" or not IsGuildView(cf) then return end
		local guid = EntryGuid(self)
		-- let Blizzard's detail frame open first, then sit beside it
		if guid then C_Timer.After(0, function() GM.Card.Show(guid, true, Host(cf)) end) end
	end)
end

local function HookCommunities()
	if hooked then return end
	local cf = _G.CommunitiesFrame
	local list = cf and cf.MemberList
	local box = list and list.ScrollBox
	if not box then return end
	hooked = true
	if ScrollUtil and ScrollUtil.AddAcquiredFrameCallback then
		ScrollUtil.AddAcquiredFrameCallback(box, function(_, frame) HookEntry(frame) end, GM, true)
	end
	-- also catch frames on every list refresh, in case the callback isn't available
	if list.RefreshListDisplay then
		hooksecurefunc(list, "RefreshListDisplay", function(self)
			if self.ScrollBox and self.ScrollBox.ForEachFrame then self.ScrollBox:ForEachFrame(HookEntry) end
		end)
	end
	cf:HookScript("OnHide", function() GM.Card.HideIfNotPinned() end)
end

GM:On("ADDON_LOADED", function(_, name)
	if name == "Blizzard_Communities" then HookCommunities() end
end)
GM:On("PLAYER_LOGIN", function()
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Communities")
	if loaded then HookCommunities() end
end)

---------------------------------------------------------------------------
-- Right-click menus: guild roster entries, chat names, party/raid/target frames
---------------------------------------------------------------------------
local function GuidFromContext(ctx)
	if not ctx then return nil end
	local G = GM.G
	if not G then return nil end
	local guid = GM.Safe(ctx.guid)
	if guid and GM.DB.Find(G, guid) then return guid end
	if ctx.unit then
		local ok, g = pcall(UnitGUID, ctx.unit)
		g = ok and GM.Safe(g)
		if g and GM.DB.Find(G, g) then return g end
	end
	local name = GM.Safe(ctx.name)
	if name then
		local server = GM.Safe(ctx.server)
		local full = server and server ~= "" and (name .. "-" .. server) or name
		local m = GM.DB.FindByName(G, full, true)
		if m then return m.guid end
	end
	return nil
end

local function AddMenuItems(_, root, ctx)
	local guid = GuidFromContext(ctx)
	if not guid then return end
	local G = GM.G
	root:CreateDivider()
	root:CreateTitle(L["Guild Masters R Us"])
	root:CreateButton(L["Member card"], function() GM.Card.Show(guid, true) end)
	local m, former = GM.DB.Find(G, guid)
	if former and m then
		root:CreateButton("|cff999999" .. L["Former member - left %s"]:format(GM.Notes.FormatDate(m.leftAt)) .. "|r", function() GM.Card.Show(guid, true) end)
	end
end

if Menu and Menu.ModifyMenu then
	for _, tag in ipairs({ "COMMUNITIES_GUILD_MEMBER", "GUILD", "GUILD_OFFLINE", "FRIEND", "FRIEND_OFFLINE", "PARTY", "RAID_PLAYER", "PLAYER", "TARGET", "CHAT_ROSTER" }) do
		pcall(Menu.ModifyMenu, "MENU_UNIT_" .. tag, AddMenuItems)
	end
end
