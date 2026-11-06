-- Guild Masters R Us - Audit tab: who's missing a join date, promotion date or main/alt setting,
-- plus the join date tool (compare saved dates with dates written in notes).
local _, GM = ...
local L = GM.L
local U = GM.U
local UI = GM.UI
local Notes = GM.Notes

local onlyIncomplete = true

local function DateCell(rec)
	if not rec then return "|cffff6666" .. L["missing"] .. "|r" end
	if not rec.t then return "|cff999999" .. L["unknown"] .. "|r" end
	return Notes.FormatDate(rec.t)
end

local function NeedsPromo(G, m)
	local n = #(G.rankNames or {})
	return m.rankOrder and n > 0 and m.rankOrder < n
end

local function Incomplete(G, m)
	if not m.joined then return true end
	if NeedsPromo(G, m) and not m.promoted then return true end
	if not GM.Alts.HasGroup(G, m.guid) then return true end
	return false
end

local function MarkUnknown(G)
	local now, n = U.Now(), 0
	for guid, m in pairs(G.members) do
		if not m.joined then m.joined = { src = "unknown", ts = now } n = n + 1 if GM.Sync then GM.Sync.Broadcast(G, "J", guid) end end
		if NeedsPromo(G, m) and not m.promoted then m.promoted = { src = "unknown", ts = now } n = n + 1 if GM.Sync then GM.Sync.Broadcast(G, "P", guid) end end
	end
	GM:Fire("ROSTER_UPDATED", G)
	return n
end

local function ClearUnknown(G)
	for _, m in pairs(G.members) do
		if m.joined and not m.joined.t then m.joined = nil end
		if m.promoted and not m.promoted.t then m.promoted = nil end
	end
	GM:Fire("ROSTER_UPDATED", G)
end

local function Build(f)
	f.body = CreateFrame("Frame", nil, f)
	f.body:SetAllPoints()
	local b = f.body

	f.only = UI.Check(b, L["Only show incomplete"], function(v) onlyIncomplete = v UI.QueueRefresh() end)
	f.only:SetPoint("TOPLEFT", 4, 0)
	f.totals = UI.Text(b, "", "GameFontHighlightSmall")
	f.totals:SetPoint("LEFT", f.only.label, "RIGHT", 16, 0)

	local unknown = UI.Button(b, L["Set missing to unknown"], 160, 22, function()
		local G = GM.G
		UI.Confirm(L["Mark every missing join/promotion date as \"unknown\"? They'll stop counting as incomplete. Real dates can still be set later."], function()
			GM:Print(L["%d date(s) marked unknown."]:format(MarkUnknown(G)))
		end)
	end, L["For members whose dates nobody knows, so the audit can be completed."])
	unknown:SetPoint("TOPRIGHT", -150, -1)
	local clear = UI.Button(b, L["Clear unknown"], 140, 22, function() ClearUnknown(GM.G) end, L["Turns every \"unknown\" date back into missing."])
	clear:SetPoint("LEFT", unknown, "RIGHT", 6, 0)

	local list = UI.List(b, {
		{ key = "name", title = L["Name"], width = 140 },
		{ key = "rank", title = L["Rank"], width = 100 },
		{ key = "joined", title = L["Join date"], width = 86 },
		{ key = "promo", title = L["Promotion date"], width = 96 },
		{ key = "main", title = L["Main / alt"], width = 110 },
		{ key = "note", title = L["Date in note"], width = 86 },
		{ key = "status", title = L["Note check"], width = 100 },
	})
	list:SetPoint("TOPLEFT", 0, -28)
	list:SetPoint("BOTTOMRIGHT", 0, 64)
	list.onClick = function(row, button, r)
		if button == "RightButton" then UI.MemberMenu(r, GM.G, row.m) else GM.Card.Show(row.m.guid, true) end
	end
	f.list = list

	-- Join date tool
	local tool = UI.Text(b, L["Join date tool"], "GameFontNormal")
	tool:SetPoint("BOTTOMLEFT", 6, 44)
	f.toolInfo = UI.Text(b, "", "GameFontHighlightSmall")
	f.toolInfo:SetPoint("LEFT", tool, "RIGHT", 10, 0)
	local imp = UI.Button(b, L["Import dates from notes"], 170, 22, function()
		local n = Notes.ImportFromNotes(GM.G, false)
		GM:Print(L["Imported %d join date(s) from notes."]:format(n))
	end, L["Members with no saved join date get the date found in their note (common date formats are recognized)."])
	imp:SetPoint("BOTTOMLEFT", 4, 12)
	local exp = UI.Button(b, L["Write dates into notes"], 170, 22, function()
		local where = GM.DB.JoinNoteSetting(GM.G)
		local n, err = Notes.ExportToNotes(GM.G, false)
		if err == "rank" then GM:Print(L["Your rank can't edit that note."]) return end
		GM:Print(L["Writing %d join date(s) into %s notes, one every half second."]:format(n, where == "officer" and L["officer"] or L["public"]))
	end, L["Members with a saved join date but none in their note get it written in (the note chosen in options; public if off)."])
	exp:SetPoint("LEFT", imp, "RIGHT", 6, 0)
	local fixNotes = UI.Button(b, L["Fix notes from saved"], 160, 22, function()
		UI.Confirm(L["Overwrite the date in notes that don't match the saved join date?"], function()
			local n, err = Notes.ExportToNotes(GM.G, true)
			if err == "rank" then GM:Print(L["Your rank can't edit that note."]) return end
			GM:Print(L["Updating %d note(s)."]:format(n))
		end)
	end)
	fixNotes:SetPoint("LEFT", exp, "RIGHT", 6, 0)
	local fixSaved = UI.Button(b, L["Fix saved from notes"], 160, 22, function()
		UI.Confirm(L["Replace saved join dates that don't match the date in the note?"], function()
			GM:Print(L["Updated %d saved date(s)."]:format(Notes.ImportFromNotes(GM.G, true)))
		end)
	end)
	fixSaved:SetPoint("LEFT", fixNotes, "RIGHT", 6, 0)
end

local STATUS = {
	match = "|cff33ff33" .. L["matches"] .. "|r",
	mismatch = "|cffff6666" .. L["different"] .. "|r",
	noteOnly = "|cffffd100" .. L["note only"] .. "|r",
	savedOnly = "|cffaaaaaa" .. L["not in note"] .. "|r",
	none = "",
}

local function Refresh(f, G)
	if not UI.GuildReady(f, G) then return end
	f.only:SetChecked(onlyIncomplete)
	local audit = Notes.Audit(G)
	local items, incomplete, total = {}, 0, 0
	local counts = { match = 0, mismatch = 0, noteOnly = 0, savedOnly = 0 }
	for _, row in ipairs(audit) do
		total = total + 1
		local inc = Incomplete(G, row.m)
		if inc then incomplete = incomplete + 1 end
		if counts[row.status] then counts[row.status] = counts[row.status] + 1 end
		if not onlyIncomplete or inc then items[#items + 1] = row end
	end
	local people, mains = GM.Alts.CountAccounts(G)
	f.totals:SetText(incomplete == 0 and ("|cff33ff33" .. L["All complete!"] .. "|r") or
		L["Incomplete: %d / %d   ·   Mains: %d   ·   People: %d"]:format(incomplete, total, mains, people))
	f.toolInfo:SetText(L["%d match, %d different, %d only in notes, %d not in notes"]:format(counts.match, counts.mismatch, counts.noteOnly, counts.savedOnly))
	f.list:SetRows(items, function(row)
		local m = row.m
		local main = GM.Alts.GetMain(G, m.guid)
		local ma = main == m.guid and L["Main"] or (main and L["Alt"]) or ("|cffff6666" .. L["not set"] .. "|r")
		return {
			U.ColorName(m), m.rank or "", DateCell(m.joined),
			NeedsPromo(G, m) and DateCell(m.promoted) or "|cff777777" .. L["n/a"] .. "|r",
			ma, row.noteDate and Notes.FormatDate(row.noteDate) or "", STATUS[row.status] or "",
		}
	end)
end

UI.RegisterTab({ id = "audit", title = L["Audit"], order = 3, build = Build, refresh = Refresh })
