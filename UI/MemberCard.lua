-- Guild Masters R Us - member card: everything about one member, with editing.
-- Opens on mouseover (Blizzard's guild roster or ours) and stays open ("pinned") on click. Esc closes.
local _, GM = ...
local L = GM.L
local U = GM.U
local UI = GM.UI
local DB = GM.DB
local Notes = GM.Notes
local Card = {}
GM.Card = Card

local card
local WIDTH = 330

local function G() return GM.G end

---------------------------------------------------------------------------
-- Prompts (also used by the roster/audit menus)
---------------------------------------------------------------------------
function Card.PromptDate(Gd, m, field)
	local label = field == "joined" and L["Join date for %s"] or L["Promotion date for %s"]
	local cur = m[field] and m[field].t
	UI.Prompt(label:format(U.DisplayName(m.name)) .. "\n" .. L["Any common format works (for example 2026-11-05 or 11/05/2026). Type \"unknown\" if nobody knows, or leave empty to clear."],
		cur and Notes.FormatDate(cur) or "", function(text)
			local now = U.Now()
			if text == "" then
				m[field] = nil
			elseif text:lower() == L["unknown"]:lower() or text:lower() == "unknown" then
				m[field] = { src = "unknown", ts = now }
			else
				local t = Notes.ParseDate(text)
				if not t then return L["That doesn't look like a date."] end
				if t > now + U.DAY then return L["That date is in the future."] end
				m[field] = { t = t, src = "manual", ts = now }
			end
			if GM.Sync then GM.Sync.Broadcast(Gd, field == "joined" and "J" or "P", m.guid) end
			GM:Fire("ROSTER_UPDATED", Gd)
		end, 40)
end

function Card.PromptBirthday(Gd, m)
	local cur = m.birthday and m.birthday.m and ("%02d/%02d"):format(m.birthday.m, m.birthday.d)
	UI.Prompt(L["Birthday for %s as month/day (for example 07/23). Leave empty to clear."]:format(U.DisplayName(m.name)), cur or "", function(text)
		local now = U.Now()
		if text == "" then
			m.birthday = { ts = now }
		else
			local mo, d = text:match("^(%d%d?)%s*[/%-%.]%s*(%d%d?)$")
			mo, d = tonumber(mo), tonumber(d)
			if not mo or mo < 1 or mo > 12 or not d or d < 1 or d > 31 then return L["Use month/day, like 07/23."] end
			m.birthday = { m = mo, d = d, ts = now }
		end
		if GM.Sync then GM.Sync.Broadcast(Gd, "BD", m.guid) end
		GM:Fire("ROSTER_UPDATED", Gd)
	end, 10)
end

function Card.PromptAddAlt(Gd, m)
	UI.Prompt(L["Name of %s's alt (start typing to pick from the guild):"]:format(U.DisplayName(m.name)), "", function(text)
		if text == "" then return L["Please enter a name."] end
		local alt = DB.FindByName(Gd, text, true)
		if not alt then return L["No guild member called %s."]:format(text) end
		if alt.guid == m.guid then return L["That's the same character."] end
		GM.Alts.Link(Gd, m.guid, alt.guid)
		GM:Fire("ROSTER_UPDATED", Gd)
	end, 60, UI.MemberCompleter(Gd, true, function(o)
		if o.guid == m.guid then return true end
		local gid = GM.Alts.GroupOf(m)
		return gid ~= nil and GM.Alts.GroupOf(o) == gid
	end))
end

function Card.PromptBan(Gd, m)
	local alts = 0
	for _, g in ipairs(GM.Alts.GroupMembersAll(Gd, m.guid)) do if g ~= m.guid then alts = alts + 1 end end
	UI.Prompt(L["Ban %s? Reason (optional):"]:format(U.DisplayName(m.name)), "", function(reason)
		if alts > 0 then
			C_Timer.After(0, function()
				UI.Confirm(L["Also ban their %d alt(s)?"]:format(alts), function()
					GM.Bans.Add(Gd, m.guid, m.name, reason, true)
				end, L["Ban alts too"])
				-- the dialog's Cancel bans only the main
				local d = _G.GuildMastersRusDialog
				if d and d.no then
					d.no:SetText(L["Just them"])
					d.no:SetScript("OnClick", function()
						d:Hide()
						GM.Bans.Add(Gd, m.guid, m.name, reason, false)
					end)
				end
			end)
		else
			GM.Bans.Add(Gd, m.guid, m.name, reason, false)
		end
		if not m.leftAt and CanGuildRemove and CanGuildRemove() then
			GM:Print(L["%s is banned in the addon. To remove them from the guild, use the Tools tab (Kick) or type /gremove %s"]:format(U.DisplayName(m.name), U.DisplayName(m.name)))
		end
	end, GM.Bans.REASON_MAX)
end

---------------------------------------------------------------------------
-- Building the card
---------------------------------------------------------------------------
local function Line(parent, y, label)
	local l = UI.Text(parent, label, "GameFontNormalSmall")
	l:SetPoint("TOPLEFT", 12, y)
	local v = UI.Text(parent, "", "GameFontHighlightSmall")
	v:SetPoint("TOPLEFT", 112, y)
	v:SetPoint("RIGHT", parent, "RIGHT", -12, 0)
	v:SetWordWrap(false)
	return v, l
end

local function SmallButton(parent, text, onClick, tooltip)
	local b = UI.Button(parent, text, 60, 18, onClick, tooltip)
	b:SetNormalFontObject("GameFontNormalSmall")
	b:SetHighlightFontObject("GameFontHighlightSmall")
	return b
end

local function NoteEditor(parent, y, label, which)
	local l = UI.Text(parent, label, "GameFontNormalSmall")
	l:SetPoint("TOPLEFT", 12, y)
	local e = UI.Edit(parent, 200, Notes.NOTE_MAX)
	e:SetPoint("TOPLEFT", 112, y + 4)
	local count = UI.Text(parent, "", "GameFontDisableSmall")
	count:SetPoint("LEFT", e, "RIGHT", 4, 0)
	e:SetScript("OnTextChanged", function(self) count:SetText(("%d/%d"):format(U.CharCount(self:GetText()), Notes.NOTE_MAX)) end)
	e:SetScript("OnEditFocusGained", function() card.pinned = true Card.UpdatePin() end)
	e:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		local m = card.m
		if not m or m.leftAt then return end
		local text = self:GetText() or ""
		local ok, err = Notes.Set(m.guid, which, text)
		if ok then
			if which == "public" then m.note = text else m.oNote = text end
			GM:Print(L["Note saved."])
		else
			GM:Print(err == "rank" and L["Your rank can't edit that note."] or (L["Couldn't save the note: "] .. tostring(err)))
		end
	end)
	e.label, e.count = l, count
	return e
end

local function Build()
	card = UI.Window("Card", "", WIDTH, 600)
	card:SetFrameStrata("DIALOG")
	card:SetScript("OnHide", function() card.pinned = false end)
	local y = -34
	card.sub = UI.Text(card, "", "GameFontHighlightSmall")
	card.sub:SetPoint("TOPLEFT", 12, y)
	card.sub:SetPoint("RIGHT", -12, 0)
	y = y - 16
	card.banned = UI.Text(card, "", "GameFontNormal")
	card.banned:SetPoint("TOPLEFT", 12, y)
	card.banned:SetPoint("RIGHT", -12, 0)
	card.banned:SetTextColor(1, 0.2, 0.2)
	y = y - 18
	card.rank = Line(card, y, L["Rank"]) y = y - 16
	card.status = Line(card, y, L["Status"]) y = y - 16
	card.last = Line(card, y, L["Last online"]) y = y - 16
	card.zone = Line(card, y, L["Zone"]) y = y - 20

	card.joined = Line(card, y, L["Joined"])
	card.joinedEdit = SmallButton(card, L["Edit"], function() Card.PromptDate(G(), card.m, "joined") end)
	card.joinedEdit:SetPoint("TOPRIGHT", -12, y + 3)
	y = y - 16
	card.history = Line(card, y, L["Membership"]) y = y - 16
	card.invited = Line(card, y, L["Invited by"]) y = y - 18
	card.promoted = Line(card, y, L["Promoted"])
	card.promotedEdit = SmallButton(card, L["Edit"], function() Card.PromptDate(G(), card.m, "promoted") end)
	card.promotedEdit:SetPoint("TOPRIGHT", -12, y + 3)
	y = y - 16
	card.inRank = Line(card, y, L["Time in rank"]) y = y - 18
	card.birthday = Line(card, y, L["Birthday"])
	card.birthdayEdit = SmallButton(card, L["Set"], function() Card.PromptBirthday(G(), card.m) end)
	card.birthdayEdit:SetPoint("TOPRIGHT", -12, y + 3)
	y = y - 22

	card.pub = NoteEditor(card, y, L["Public note"], "public") y = y - 22
	card.off = NoteEditor(card, y, L["Officer note"], "officer") y = y - 24

	local cl = UI.Text(card, L["Custom note"], "GameFontNormalSmall")
	cl:SetPoint("TOPLEFT", 12, y)
	card.customCount = UI.Text(card, "", "GameFontDisableSmall")
	card.customCount:SetPoint("LEFT", cl, "RIGHT", 8, 0)
	card.customSave = SmallButton(card, L["Save"], function()
		local m, Gd = card.m, G()
		local text = U.Truncate(U.Trim(card.custom.edit:GetText() or ""), Notes.CUSTOM_MAX)
		local old = m.custom and m.custom.text or ""
		if text == old then return end
		m.custom = { text = text, ts = U.Now() }
		GM.Log.Add(Gd, { k = "custom", n = m.name, g = m.guid, x = { old = old, new = text } })
		if GM.Sync then GM.Sync.Broadcast(Gd, "C", m.guid) end
		card.custom.edit:ClearFocus()
		GM:Print(L["Custom note saved."])
	end, L["Only addon users see this note. It's shared through sync."])
	card.customSave:SetPoint("TOPRIGHT", -12, y + 3)
	y = y - 16
	card.custom = UI.MultiLine(card, WIDTH - 50, 40, Notes.CUSTOM_MAX)
	card.custom:SetPoint("TOPLEFT", 16, y - 4)
	card.custom.edit:SetScript("OnTextChanged", function(self)
		card.customCount:SetText(("%d/%d"):format(U.CharCount(self:GetText()), Notes.CUSTOM_MAX))
	end)
	card.custom.edit:SetScript("OnEditFocusGained", function() card.pinned = true Card.UpdatePin() end)
	y = y - 54

	local al = UI.Text(card, L["Alts"], "GameFontNormalSmall")
	al:SetPoint("TOPLEFT", 12, y)
	card.addAlt = SmallButton(card, L["Add"], function() Card.PromptAddAlt(G(), card.m) end, L["Link another character to this one's alt group."])
	card.addAlt:SetPoint("TOPRIGHT", -140, y + 3)
	card.setMain = SmallButton(card, L["Main"], function() GM.Alts.SetMain(G(), card.m.guid) end, L["Make this character the main of its group."])
	card.setMain:SetPoint("LEFT", card.addAlt, "RIGHT", 4, 0)
	card.unlink = SmallButton(card, L["Unlink"], function() GM.Alts.Unlink(G(), card.m.guid) end, L["Take this character out of its alt group."])
	card.unlink:SetPoint("LEFT", card.setMain, "RIGHT", 4, 0)
	y = y - 18
	card.altButtons = {}
	card.altY = y
	y = y - 4 * 16 - 6

	local hl = UI.Text(card, L["History"], "GameFontNormalSmall")
	hl:SetPoint("TOPLEFT", 12, y)
	y = y - 14
	card.hist = UI.Text(card, "", "GameFontHighlightSmall")
	card.hist:SetPoint("TOPLEFT", 16, y)
	card.hist:SetPoint("RIGHT", -12, 0)
	card.hist:SetJustifyV("TOP")
	card.hist:SetHeight(84)
	y = y - 90

	card.aOn = UI.Check(card, L["Tell me when online"], function(v) Card.SetAlert("online", v) end)
	card.aOn:SetPoint("TOPLEFT", 8, y)
	card.aActive = UI.Check(card, L["...back from inactivity"], function(v) Card.SetAlert("active", v) end)
	card.aActive:SetPoint("TOPLEFT", 170, y)
	y = y - 22
	card.aOff = UI.Check(card, L["Tell me when offline"], function(v) Card.SetAlert("offline", v) end)
	card.aOff:SetPoint("TOPLEFT", 8, y)
	y = y - 28

	card.invite = UI.Button(card, L["Invite"], 70, 22, function()
		local m = card.m
		if m and C_PartyInfo and C_PartyInfo.InviteUnit then pcall(C_PartyInfo.InviteUnit, m.name) end
	end)
	card.invite:SetPoint("TOPLEFT", 10, y)
	card.whisper = UI.Button(card, L["Whisper"], 70, 22, function()
		local m = card.m
		if not m then return end
		if ChatFrameUtil and ChatFrameUtil.SendTell then ChatFrameUtil.SendTell(m.name)
		elseif ChatFrame_SendTell then ChatFrame_SendTell(m.name) end
	end)
	card.whisper:SetPoint("LEFT", card.invite, "RIGHT", 4, 0)
	card.ban = UI.Button(card, L["Ban"], 70, 22, function()
		local m, Gd = card.m, G()
		local ban, key = GM.Bans.Check(Gd, m.guid, m.name)
		if ban then
			UI.Confirm(L["Remove %s from the ban list?"]:format(U.DisplayName(m.name)), function() GM.Bans.Remove(Gd, key) end)
		else
			Card.PromptBan(Gd, m)
		end
	end)
	card.ban:SetPoint("LEFT", card.whisper, "RIGHT", 4, 0)
	card.pinText = UI.Text(card, "", "GameFontDisableSmall", "RIGHT")
	card.pinText:SetPoint("BOTTOMRIGHT", -12, 10)
	card:SetHeight(-y + 40)
end

function Card.SetAlert(what, v)
	local m = card and card.m
	if not m then return end
	m.alerts = m.alerts or {}
	m.alerts[what] = v or nil
end

function Card.UpdatePin()
	if not card then return end
	card.pinText:SetText(card.pinned and L["Pinned - Esc closes"] or L["Click to pin"])
end

local function AltButton(i)
	local b = card.altButtons[i]
	if not b then
		b = CreateFrame("Button", nil, card)
		b:SetHeight(16)
		b:SetPoint("TOPLEFT", 16, card.altY - (i - 1) * 16)
		b:SetPoint("RIGHT", card, "RIGHT", -12, 0)
		b.text = UI.Text(b, "", "GameFontHighlightSmall")
		b.text:SetAllPoints()
		b:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
		b:SetScript("OnClick", function(self) if self.guid then Card.Show(self.guid, true) end end)
		card.altButtons[i] = b
	end
	return b
end

local function HistoryText(Gd, m, now)
	local lines = {}
	for _, h in ipairs(m.history or {}) do
		local what = (h.k == "join" and L["Joined"]) or (h.k == "kick" and L["Kicked"]) or L["Left"]
		if h.by then what = what .. " " .. L["by %s"]:format(U.DisplayName(h.by)) end
		lines[#lines + 1] = { t = h.t or 0, text = Notes.FormatDate(h.t) .. "  " .. what }
	end
	for _, h in ipairs(m.rankHist or {}) do
		local what = (h.up and L["Promoted"] or L["Demoted"]) .. " " .. (h.from and (h.from .. " → ") or "") .. (h.to or "?")
		if h.by then what = what .. " " .. L["by %s"]:format(U.DisplayName(h.by)) end
		lines[#lines + 1] = { t = h.t or 0, text = Notes.FormatDate(h.t) .. "  " .. what }
	end
	for _, n in ipairs(m.prevNames or {}) do
		lines[#lines + 1] = { t = 0, text = L["Previously named %s"]:format(U.DisplayName(n)) }
	end
	table.sort(lines, function(a, b) return a.t > b.t end)
	local out = {}
	for i = 1, math.min(6, #lines) do out[i] = lines[i].text end
	if #lines > 6 then out[#out + 1] = L["(+%d older)"]:format(#lines - 6) end
	return #out > 0 and table.concat(out, "\n") or L["Nothing recorded yet."]
end

local function DateWithSource(rec)
	if not rec then return "|cffff6666" .. L["not set"] .. "|r" end
	if not rec.t then return "|cff999999" .. L["unknown"] .. "|r" end
	local src = rec.src == "log" and (" |cff999999" .. L["(from guild log)"] .. "|r") or (rec.src == "seen" and "" or "")
	return Notes.FormatDate(rec.t) .. " |cff999999(" .. U.FormatAgo(rec.t) .. ")|r" .. src
end

function Card.Refresh()
	if not card or not card:IsShown() or not card.guid then return end
	local Gd = G()
	local m, former = DB.Find(Gd, card.guid)
	if not m then card:Hide() return end
	card.m = m
	local now = U.Now()
	local classFile = m.classFile
	local _, className = U.ClassFile(m.classID)
	card.Title:SetText(U.ColorName(m))
	local main = GM.Alts.GetMain(Gd, m.guid)
	local role = main == m.guid and ("|cffffd100" .. L["Main"] .. "|r") or (main and L["alt of %s"]:format(U.DisplayName((DB.Find(Gd, main) or {}).name)) or "")
	card.sub:SetText(L["Level %s %s"]:format(tostring(m.level or "?"), className or (classFile or "")) .. (role ~= "" and ("  ·  " .. role) or ""))
	local ban = GM.Bans.Check(Gd, m.guid, m.name)
	card.banned:SetText(ban and (L["BANNED"] .. (ban.reason ~= "" and (": " .. ban.reason) or "")) or (former and ("|cffff9933" .. L["Former member"] .. "|r") or ""))
	card.rank:SetText(m.rank or "?")
	if former then
		card.status:SetText(L["Left %s"]:format(Notes.FormatDate(m.leftAt)) .. (m.leftHow == "kick" and (" (" .. L["kicked"] .. ")") or ""))
	else
		card.status:SetText(m.online and ("|cff33ff33" .. L["Online"] .. "|r" .. ((m.status == "afk" and " (AFK)") or (m.status == "dnd" and " (DND)") or (m.status == "mobile" and " (" .. L["mobile"] .. ")") or "")) or L["Offline"])
	end
	card.last:SetText(m.online and L["now"] or (m.lastOnline and (U.FormatAgo(m.lastOnline, now)) or "?"))
	card.zone:SetText(m.zone or "")
	card.joined:SetText(DateWithSource(m.joined))
	local first = GM.Events.OriginalJoin(m)
	local joins = 0
	for _, h in ipairs(m.history or {}) do if h.k == "join" then joins = joins + 1 end end
	card.history:SetText(joins > 1 and L["joined %d times, first %s"]:format(joins, Notes.FormatDate(first)) or L["first membership"])
	card.invited:SetText(m.invitedBy and U.DisplayName(m.invitedBy) or "?")
	card.promoted:SetText(DateWithSource(m.promoted))
	local since = GM.Rules.TimeInRankSince(m)
	card.inRank:SetText(since and U.FormatDuration(now - since) or "?")
	local bd = ""
	if m.birthday and m.birthday.m then
		bd = date("%B ", time({ year = 2000, month = m.birthday.m, day = 1, hour = 12 })) .. tostring(m.birthday.d or "")
	end
	card.birthday:SetText(bd)

	local canPub, canOff, viewOff = Notes.CanEdit("public"), Notes.CanEdit("officer"), Notes.CanViewOfficer()
	if not card.pub:HasFocus() then card.pub:SetText(m.note or "") end
	if not card.off:HasFocus() then card.off:SetText(viewOff and (m.oNote or "") or "") end
	card.pub:SetEnabled(canPub and not former)
	card.off:SetEnabled(canOff and not former)
	card.off:SetShown(viewOff)
	card.off.label:SetText(viewOff and L["Officer note"] or (L["Officer note"] .. " |cff777777" .. L["(hidden)"] .. "|r"))
	if not card.custom.edit:HasFocus() then card.custom.edit:SetText(m.custom and m.custom.text or "") end

	local alts = GM.Alts.GroupMembersAll(Gd, m.guid)
	local shown = 0
	for _, g in ipairs(alts) do
		if g ~= m.guid and shown < 4 then
			local a, aFormer = DB.Find(Gd, g)
			if a then
				shown = shown + 1
				local b = AltButton(shown)
				b.guid = g
				local tag = (main == g) and (" |cffffd100(" .. L["main"] .. ")|r") or ""
				local st = aFormer and (" |cff999999" .. L["(left)"] .. "|r") or (a.online and " |cff33ff33●|r" or "")
				b.text:SetText(U.ColorName(a) .. " " .. (a.level or "") .. tag .. st)
				b:Show()
			end
		end
	end
	if shown == 0 then
		local b = AltButton(1)
		b.guid = nil
		b.text:SetText("|cff777777" .. L["No alts linked."] .. "|r")
		b:Show()
		shown = 1
	end
	for i = shown + 1, #card.altButtons do card.altButtons[i]:Hide() end
	if GM.Alts.HasGroup(Gd, m.guid) then card.unlink:Enable() else card.unlink:Disable() end

	card.hist:SetText(HistoryText(Gd, m, now))
	local al = m.alerts or {}
	card.aOn:SetChecked(al.online)
	card.aOff:SetChecked(al.offline)
	card.aActive:SetChecked(al.active)
	card.ban:SetText(ban and L["Unban"] or L["Ban"])
	if former then card.invite:Disable() else card.invite:Enable() end
	Card.UpdatePin()
end

-- host: a window to sit next to (optional; ignored once the card has been dragged somewhere)
function Card.Show(guid, pinned, host)
	local Gd = G()
	if not Gd or not guid or not DB.Find(Gd, guid) then return end
	if not card then Build() end
	if card.pinned and not pinned and card.guid ~= guid then return end -- a pinned card stays put
	card.guid = guid
	card.pinned = pinned or (card.pinned and card.guid == guid)
	if host and not GM.settings.windows.Card then
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, 0)
	end
	card:Show()
	card:Raise()
	Card.Refresh()
end

function Card.HideIfNotPinned()
	if card and card:IsShown() and not card.pinned then card:Hide() end
end

function Card.Current() return card and card:IsShown() and card.guid end

for _, msg in ipairs({ "ROSTER_UPDATED", "ALTS_CHANGED", "BANS_CHANGED", "SYNC_APPLIED" }) do
	GM:Listen(msg, function() if card and card:IsShown() then C_Timer.After(0.1, Card.Refresh) end end)
end

GM:Command("card", L["open a member's card: /gmru card Name"], function(name)
	local Gd = G()
	if not Gd then return end
	local m = DB.FindByName(Gd, name ~= "" and name or U.MyName(), true)
	if m then Card.Show(m.guid, true) else GM:Print(L["No guild member called %s."]:format(name)) end
end)
