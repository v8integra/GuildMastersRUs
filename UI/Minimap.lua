-- Guild Masters R Us - minimap button and addon compartment entry.
local _, GM = ...
local L = GM.L
local UI = GM.UI

local button

local function Tooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:SetText(L["Guild Masters R Us"], 1, 0.82, 0)
	local G = GM.G
	if G then
		local new = GM.Log.NewCount(G)
		if new > 0 then GameTooltip:AddLine(L["%d new log entries"]:format(new), 0.3, 1, 0.3) end
	end
	GameTooltip:AddLine(L["Left-click: open"], 1, 1, 1)
	GameTooltip:AddLine(L["Right-click: options"], 1, 1, 1)
	GameTooltip:AddLine(L["Drag: move"], 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local function OnClick(_, mouse)
	if mouse == "RightButton" then
		if GM.OpenOptions then GM.OpenOptions() end
	else
		UI.Toggle()
	end
end

local function Place()
	local angle = math.rad(GM.settings.minimap.angle or 200)
	local r = (Minimap:GetWidth() / 2) + 6
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function Build()
	if button or not Minimap then return end
	button = CreateFrame("Button", "GuildMastersRusMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture([[Interface\Minimap\UI-Minimap-ZoomButton-Highlight]])
	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", 7, -5)
	icon:SetTexture([[Interface\AddOns\GuildMastersRus\Media\Icon\GuildMastersRus]])
	icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	border:SetTexture([[Interface\Minimap\MiniMap-TrackingBorder]])
	button:SetScript("OnClick", OnClick)
	button:SetScript("OnEnter", Tooltip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			cx, cy = cx / scale, cy / scale
			GM.settings.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
			Place()
		end)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	Place()
end

function GM.UpdateMinimapButton()
	if GM.settings.minimap.show then
		Build()
		if button then button:Show() end
	elseif button then
		button:Hide()
	end
end

GM:On("PLAYER_LOGIN", function() GM.UpdateMinimapButton() end)

-- Addon compartment (the TOC points here)
function GuildMastersRus_OnCompartmentClick(_, mouse)
	OnClick(nil, mouse)
end
function GuildMastersRus_OnCompartmentEnter(_, owner)
	Tooltip(owner or UIParent)
end
function GuildMastersRus_OnCompartmentLeave()
	GameTooltip:Hide()
end
