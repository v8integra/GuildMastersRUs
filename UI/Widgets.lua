-- Guild Masters R Us - small UI toolkit (windows, buttons, lists, dialogs).
-- Everything is our own frames; nothing here touches Blizzard's frames.
local _, GM = ...
local L = GM.L
local U = GM.U
local UI = {}
GM.UI = UI

UI.BACKDROP = {
	bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
	edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
	edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

function UI.Backdrop(f, alpha)
	if f.SetBackdrop then
		f:SetBackdrop(UI.BACKDROP)
		f:SetBackdropColor(0.05, 0.05, 0.07, alpha or 0.95)
		f:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
	end
end

function UI.Tooltip(frame, title, text)
	frame:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 0.82, 0)
		if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Movable window that remembers its position; Esc closes it.
function UI.Window(key, title, width, height, parent)
	local f = CreateFrame("Frame", "GuildMastersRus" .. key, parent or UIParent, "BackdropTemplate")
	f:SetSize(width, height)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	UI.Backdrop(f)
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		GM.settings.windows[key] = { point = point, relPoint = relPoint, x = x, y = y }
	end)
	local pos = GM.settings and GM.settings.windows[key]
	if pos and pos.point then
		f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
	else
		f:SetPoint("CENTER")
	end
	f.Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.Title:SetPoint("TOPLEFT", 12, -10)
	f.Title:SetText(title)
	f.Close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.Close:SetPoint("TOPRIGHT", -2, -2)
	f:Hide()
	tinsert(UISpecialFrames, f:GetName())
	return f
end

function UI.ResetWindows()
	GM.settings.windows = {}
end

function UI.Button(parent, text, width, height, onClick, tooltip)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 100, height or 22)
	b:SetText(text)
	if onClick then b:SetScript("OnClick", onClick) end
	if tooltip then UI.Tooltip(b, text, tooltip) end
	return b
end

function UI.Text(parent, text, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	fs:SetJustifyH(justify or "LEFT")
	if text then fs:SetText(text) end
	return fs
end

function UI.Check(parent, text, onClick, tooltip)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetSize(24, 24)
	c.label = UI.Text(c, text, "GameFontHighlightSmall")
	c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
	if onClick then c:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end) end
	if tooltip then UI.Tooltip(c, text, tooltip) end
	return c
end

function UI.Edit(parent, width, maxChars, onEnter)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	e:SetSize(width or 120, 20)
	e:SetAutoFocus(false)
	if maxChars then e:SetMaxLetters(maxChars) end
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if onEnter then onEnter(self:GetText()) end
	end)
	return e
end

-- Search box: calls onChange(text) as you type.
function UI.Search(parent, width, onChange)
	local e = UI.Edit(parent, width)
	e.hint = UI.Text(e, L["Search..."], "GameFontDisableSmall")
	e.hint:SetPoint("LEFT", 2, 0)
	e:SetScript("OnTextChanged", function(self)
		local t = self:GetText() or ""
		self.hint:SetShown(t == "")
		onChange(t)
	end)
	return e
end

-- Multi-line text box in a scroll frame.
function UI.MultiLine(parent, width, height, maxChars)
	local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	sf:SetSize(width, height)
	local bg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	bg:SetPoint("TOPLEFT", sf, -5, 5)
	bg:SetPoint("BOTTOMRIGHT", sf, 26, -5)
	UI.Backdrop(bg, 0.6)
	bg:SetFrameLevel(math.max(0, sf:GetFrameLevel() - 1))
	local e = CreateFrame("EditBox", nil, sf)
	e:SetMultiLine(true)
	e:SetFontObject("ChatFontNormal")
	e:SetWidth(width - 4)
	e:SetAutoFocus(false)
	if maxChars then e:SetMaxLetters(maxChars) end
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	sf:SetScrollChild(e)
	sf:EnableMouse(true)
	sf:SetScript("OnMouseDown", function() e:SetFocus() end)
	sf.edit = e
	sf.bg = bg
	return sf
end

-- Opens a context menu built by generator(root).
function UI.Menu(owner, generator)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root) generator(root) end)
	end
end

-- Button that shows its current value and opens a menu.
function UI.Dropdown(parent, width, getLabel, generator)
	local b = UI.Button(parent, "", width, 22)
	function b:Refresh() self:SetText(getLabel() .. " |TInterface\\ChatFrame\\ChatFrameExpandArrow:12|t") end
	b:SetScript("OnClick", function(self)
		UI.Menu(self, function(root)
			generator(root, function() self:Refresh() end)
		end)
	end)
	b:Refresh()
	return b
end

---------------------------------------------------------------------------
-- List: columns, header sorting, mouse-wheel scrolling, row clicks.
-- columns = { { key, title, width, justify }, ... }; the last column fills the rest.
-- list:SetRows(items, getCells) where getCells(item) returns { text, text, ... } and optional color.
---------------------------------------------------------------------------
local ROW_H = 18

function UI.List(parent, columns, opts)
	opts = opts or {}
	local list = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	UI.Backdrop(list, 0.5)
	list.columns = columns
	list.rowH = opts.rowHeight or ROW_H
	list.rows, list.items, list.offset = {}, {}, 0
	list.headerH = opts.noHeader and 0 or 20

	list.header = CreateFrame("Frame", nil, list)
	list.header:SetPoint("TOPLEFT", 6, -4)
	list.header:SetPoint("TOPRIGHT", -22, -4)
	list.header:SetHeight(list.headerH)
	list.headButtons = {}
	if not opts.noHeader then
		for i, col in ipairs(columns) do
			local hb = CreateFrame("Button", nil, list.header)
			hb:SetHeight(list.headerH)
			hb.text = UI.Text(hb, col.title, "GameFontNormalSmall", col.justify)
			hb.text:SetAllPoints()
			hb:SetScript("OnClick", function()
				if list.onSort then list.onSort(col.key) end
			end)
			hb:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
			list.headButtons[i] = hb
		end
	end

	local bar = CreateFrame("Slider", nil, list)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(14)
	bar:SetPoint("TOPRIGHT", -5, -6 - list.headerH)
	bar:SetPoint("BOTTOMRIGHT", -5, 6)
	bar:SetThumbTexture([[Interface\Buttons\UI-ScrollBar-Knob]])
	local thumb = bar:GetThumbTexture()
	if thumb then thumb:SetSize(18, 24) end
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(0, 0, 0, 0.35)
	bar:SetMinMaxValues(0, 0)
	bar:SetValueStep(1)
	bar:SetObeyStepOnDrag(true)
	bar:SetScript("OnValueChanged", function(_, v)
		v = math.floor(v + 0.5)
		if v ~= list.offset then list.offset = v list:Render() end
	end)
	list.bar = bar

	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		local step = IsShiftKeyDown() and 10 or 3
		bar:SetValue(math.max(0, list.offset - delta * step))
	end)

	function list:Layout()
		local width = self:GetWidth() - 34
		local x = 0
		for i, col in ipairs(self.columns) do
			local w = col.width
			if i == #self.columns then w = math.max(40, width - x) end
			col._x, col._w = x, w
			local hb = self.headButtons[i]
			if hb then
				hb:ClearAllPoints()
				hb:SetPoint("TOPLEFT", self.header, "TOPLEFT", x, 0)
				hb:SetWidth(w)
			end
			x = x + w + 4
		end
		local count = math.max(1, math.floor((self:GetHeight() - self.headerH - 10) / self.rowH))
		for i = 1, count do
			local row = self.rows[i] or self:CreateRow(i)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", self, "TOPLEFT", 6, -6 - self.headerH - (i - 1) * self.rowH)
			row:SetPoint("RIGHT", self, "RIGHT", -22, 0)
			for c, col in ipairs(self.columns) do
				local fs = row.cells[c]
				fs:ClearAllPoints()
				fs:SetPoint("LEFT", row, "LEFT", col._x, 0)
				fs:SetWidth(col._w)
			end
		end
		for i = count + 1, #self.rows do self.rows[i]:Hide() end
		self.visible = count
		self:Render()
	end

	function list:CreateRow(i)
		local row = CreateFrame("Button", nil, self)
		row:SetHeight(self.rowH)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
		row.sel = row:CreateTexture(nil, "BACKGROUND")
		row.sel:SetAllPoints()
		row.sel:SetColorTexture(0.2, 0.5, 0.9, 0.25)
		row.sel:Hide()
		row.cells = {}
		for c, col in ipairs(self.columns) do
			local fs = UI.Text(row, "", "GameFontHighlightSmall", col.justify)
			fs:SetWordWrap(false)
			fs:SetHeight(self.rowH)
			row.cells[c] = fs
		end
		row:SetScript("OnClick", function(r, button)
			if r.item and self.onClick then self.onClick(r.item, button, r) end
		end)
		row:SetScript("OnEnter", function(r)
			if r.item and self.onEnter then self.onEnter(r.item, r) end
		end)
		row:SetScript("OnLeave", function(r)
			GameTooltip:Hide()
			if r.item and self.onLeave then self.onLeave(r.item, r) end
		end)
		self.rows[i] = row
		return row
	end

	function list:SetRows(items, getCells)
		self.items = items or {}
		if getCells then self.getCells = getCells end
		if not self.visible then self:Layout() end
		if self.selected and self.keyOf then
			local k = self.keyOf(self.selected)
			self.selected = nil
			for _, it in ipairs(self.items) do
				if self.keyOf(it) == k then self.selected = it break end
			end
		end
		local max = math.max(0, #self.items - (self.visible or 1))
		self.bar:SetMinMaxValues(0, max)
		if self.offset > max then self.offset = max end
		self.bar:SetValue(self.offset)
		self:Render()
	end

	function list:Render()
		if not self.visible then return end
		for i = 1, self.visible do
			local row = self.rows[i]
			local item = self.items[i + self.offset]
			if item and self.getCells then
				row.item = item
				local cells, r, g, b = self.getCells(item)
				for c = 1, #self.columns do
					row.cells[c]:SetText(cells[c] or "")
					if r then row.cells[c]:SetTextColor(r, g, b) else row.cells[c]:SetTextColor(1, 1, 1) end
				end
				row.sel:SetShown(self.selected ~= nil and self.selected == item)
				row:Show()
			else
				row.item = nil
				row:Hide()
			end
		end
	end

	function list:Select(item)
		self.selected = item
		self:Render()
	end

	list:SetScript("OnSizeChanged", function(self) self:Layout() end)
	return list
end

---------------------------------------------------------------------------
-- Dialogs (our own, so nothing taints Blizzard's StaticPopup)
---------------------------------------------------------------------------
local dialog
local function Dialog()
	if dialog then return dialog end
	dialog = CreateFrame("Frame", "GuildMastersRusDialog", UIParent, "BackdropTemplate")
	dialog:SetSize(380, 140)
	dialog:SetPoint("CENTER", 0, 120)
	dialog:SetFrameStrata("DIALOG")
	dialog:EnableMouse(true)
	UI.Backdrop(dialog, 1)
	dialog.text = UI.Text(dialog, "", "GameFontHighlight", "CENTER")
	dialog.text:SetPoint("TOPLEFT", 16, -16)
	dialog.text:SetPoint("TOPRIGHT", -16, -16)
	dialog.edit = UI.Edit(dialog, 300)
	dialog.edit:SetPoint("BOTTOM", 0, 44)
	dialog.yes = UI.Button(dialog, L["OK"], 110, 22)
	dialog.yes:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -6, 14)
	dialog.no = UI.Button(dialog, L["Cancel"], 110, 22, function() dialog:Hide() end)
	dialog.no:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 6, 14)
	dialog:Hide()
	tinsert(UISpecialFrames, "GuildMastersRusDialog")
	return dialog
end

local function ResetNo(d)
	d.no:SetText(L["Cancel"])
	d.no:SetScript("OnClick", function() d:Hide() end)
end

function UI.Confirm(text, onYes, yesText)
	local d = Dialog()
	ResetNo(d)
	d.text:SetText(text)
	if d.suggest then d.suggest:Hide() end
	d.edit:Hide()
	d.yes:SetText(yesText or L["Yes"])
	d:SetHeight(math.max(110, d.text:GetStringHeight() + 70))
	d.yes:SetScript("OnClick", function() d:Hide() onYes() end)
	d:Show()
end

-- Name suggestions under the prompt's text box (filled by a completer function).
local MAX_SUGGEST = 8

local function Suggestions(d)
	if d.suggest then return d.suggest end
	local box = CreateFrame("Frame", nil, d, "BackdropTemplate")
	box:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 30, 4)
	box:SetPoint("TOPRIGHT", d, "BOTTOMRIGHT", -30, 4)
	box:SetFrameStrata("FULLSCREEN_DIALOG")
	UI.Backdrop(box, 1)
	box.rows = {}
	for i = 1, MAX_SUGGEST do
		local row = CreateFrame("Button", nil, box)
		row:SetHeight(18)
		row:SetPoint("TOPLEFT", 8, -6 - (i - 1) * 18)
		row:SetPoint("RIGHT", box, "RIGHT", -8, 0)
		row.text = UI.Text(row, "", "GameFontHighlightSmall")
		row.text:SetAllPoints()
		row:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
		row.sel = row:CreateTexture(nil, "BACKGROUND")
		row.sel:SetAllPoints()
		row.sel:SetColorTexture(0.2, 0.5, 0.9, 0.35)
		row:SetScript("OnClick", function(self)
			box.selected = self.index
			d.Accept(true)
		end)
		box.rows[i] = row
	end
	box:Hide()
	d.suggest = box
	return box
end

local function ShowSuggestions(d)
	local box = Suggestions(d)
	local list = box.list or {}
	if #list == 0 then box:Hide() return end
	for i, row in ipairs(box.rows) do
		local item = list[i]
		if item then
			row.index = i
			row.text:SetText(item.label or item.value)
			row.sel:SetShown(i == box.selected)
			row:Show()
		else
			row:Hide()
		end
	end
	box:SetHeight(12 + math.min(#list, MAX_SUGGEST) * 18)
	box:Show()
end

-- Asks for text. onOk(text) returns an error message to keep the dialog open, or nil.
-- completer(text), if given, returns { { value = "Name", label = "colored text" }, ... }
-- and the dialog suggests those as you type (Up/Down to pick, Tab or Enter to take one, or click).
function UI.Prompt(text, default, onOk, maxChars, completer)
	local d = Dialog()
	ResetNo(d)
	local box = Suggestions(d)
	box.list, box.selected = {}, nil
	box:Hide()
	d.text:SetText(text)
	d.edit:Show()
	d.edit:SetMaxLetters(maxChars or 0)
	d.edit:SetText(default or "")
	d.yes:SetText(L["OK"])
	d:SetHeight(math.max(130, d.text:GetStringHeight() + 100))
	local function Submit()
		box:Hide()
		local err = onOk(U.Trim(d.edit:GetText() or ""))
		if err then d.text:SetText(text .. "\n|cffff6666" .. err .. "|r") else d:Hide() end
	end
	-- Takes the highlighted suggestion; also submits when asked (click / Enter).
	function d.Accept(submit)
		local item = box:IsShown() and box.list[box.selected or 0]
		if item then
			d.edit:SetText(item.value)
			d.edit:SetCursorPosition(#item.value)
			box.list, box.selected = {}, nil
			box:Hide()
		end
		if submit then Submit() end
		return item and true or false
	end
	d.yes:SetScript("OnClick", Submit)
	d.edit:SetScript("OnEnterPressed", function() d.Accept(true) end)
	d.edit:SetScript("OnTabPressed", function() d.Accept(false) end)
	d.edit:SetScript("OnTextChanged", function(self, userInput)
		if not completer or not userInput then return end
		local t = U.Trim(self:GetText() or "")
		box.list = t ~= "" and completer(t) or {}
		while #box.list > MAX_SUGGEST do table.remove(box.list) end
		box.selected = #box.list > 0 and 1 or nil
		ShowSuggestions(d)
	end)
	d.edit:SetScript("OnArrowPressed", function(_, key)
		if not box:IsShown() or #box.list == 0 then return end
		local n = #box.list
		if key == "DOWN" then box.selected = ((box.selected or 0) % n) + 1
		elseif key == "UP" then box.selected = (((box.selected or 1) - 2) % n) + 1 end
		ShowSuggestions(d)
	end)
	d:SetScript("OnHide", function() box:Hide() end)
	d:Show()
	d.edit:SetFocus()
	d.edit:HighlightText()
end

-- Completer over guild members (and optionally former members): names that start with the
-- typed text first, then names with a later word that does ("frost" finds "Ominegod Frostburn").
-- skip(m) leaves members out.
function UI.MemberCompleter(G, includeFormer, skip)
	return function(typed)
		local q = typed:lower()
		local pattern = "[%s%-]" .. q:gsub("%p", "%%%0")
		local starts, words = {}, {}
		local function Consider(m, former)
			if not m.name or (skip and skip(m)) then return end
			local short = U.ShortName(m.name)
			local low = short:lower()
			local item = {
				value = short, sort = low,
				label = U.ColorName(m) .. (m.level and (" |cff999999" .. m.level .. "|r") or "")
					.. (former and (" |cff999999" .. L["(left)"] .. "|r") or ""),
			}
			if low:sub(1, #q) == q then
				starts[#starts + 1] = item
			elseif low:find(pattern) then
				words[#words + 1] = item
			end
		end
		for _, m in pairs(G.members) do Consider(m, false) end
		if includeFormer then
			for _, m in pairs(G.former) do Consider(m, true) end
		end
		local function ByName(a, b) return a.sort < b.sort end
		table.sort(starts, ByName)
		table.sort(words, ByName)
		for _, it in ipairs(words) do starts[#starts + 1] = it end
		return starts
	end
end
