-- Guild Masters R Us - dates (format/parse) and guild note editing.
local _, GM = ...
local L = GM.L
local U = GM.U
local DB = GM.DB
local Notes = {}
GM.Notes = Notes

Notes.NOTE_MAX = 31
Notes.CUSTOM_MAX = 150

Notes.DATE_FORMATS = {
	{ id = "ymd", fmt = "%Y-%m-%d", label = "2026-11-05" },
	{ id = "mdy", fmt = "%m/%d/%Y", label = "11/05/2026" },
	{ id = "dmy", fmt = "%d/%m/%Y", label = "05/11/2026" },
	{ id = "dmy.", fmt = "%d.%m.%Y", label = "05.11.2026" },
	{ id = "dMy", fmt = "%d %b %Y", label = "05 Nov 2026" },
	{ id = "Mdy", fmt = "%b %d %Y", label = "Nov 05 2026" },
}

local MONTHS = { jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6, jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12 }

function Notes.FormatDate(t, id)
	if not t then return L["Unknown"] end
	id = id or (GM.settings and GM.settings.dateFormat) or "ymd"
	for _, f in ipairs(Notes.DATE_FORMATS) do
		if f.id == id then return date(f.fmt, t) end
	end
	return date("%Y-%m-%d", t)
end

local function Make(y, m, d)
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	if not (y and m and d) then return nil end
	if y < 100 then y = y + 2000 end
	if y < 2004 or y > 2100 or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
	return time({ year = y, month = m, day = d, hour = 12 })
end

-- Finds a date anywhere in text. Returns time, startPos, endPos (or nil).
function Notes.ParseDate(text, dayFirst)
	if type(text) ~= "string" or text == "" then return nil end
	if dayFirst == nil then dayFirst = GM.settings and GM.settings.noteDayFirst end
	local s, e, y, m, d = text:find("(%d%d%d%d)[%-/%.](%d%d?)[%-/%.](%d%d?)")
	if s then
		local t = Make(y, m, d)
		if t then return t, s, e end
	end
	local a, b
	s, e, a, b, y = text:find("(%d%d?)[%-/%.](%d%d?)[%-/%.](%d%d%d?%d?)")
	if s and (#y == 2 or #y == 4) then
		a, b = tonumber(a), tonumber(b)
		local mm, dd
		if a > 12 then dd, mm = a, b
		elseif b > 12 then mm, dd = a, b
		elseif dayFirst then dd, mm = a, b
		else mm, dd = a, b end
		local t = Make(y, mm, dd)
		if t then return t, s, e end
	end
	-- "05 Nov 2026", "5 November 2026"
	local mon
	s, e, d, mon, y = text:find("(%d%d?)%s+(%a+)%.?,?%s+(%d%d%d%d)")
	if s and MONTHS[mon:sub(1, 3):lower()] then
		local t = Make(y, MONTHS[mon:sub(1, 3):lower()], d)
		if t then return t, s, e end
	end
	-- "Nov 05 2026", "November 5, 2026"
	s, e, mon, d, y = text:find("(%a+)%.?%s+(%d%d?),?%s+(%d%d%d%d)")
	if s and MONTHS[mon:sub(1, 3):lower()] then
		local t = Make(y, MONTHS[mon:sub(1, 3):lower()], d)
		if t then return t, s, e end
	end
	return nil
end

function Notes.SameDay(a, b)
	if not a or not b then return false end
	return date("%Y-%m-%d", a) == date("%Y-%m-%d", b)
end

-- Note text with the join date put in (replacing a date that's already there).
function Notes.WithDate(note, t, fmtId, prefix)
	note = note or ""
	local stamp = (prefix or "") .. Notes.FormatDate(t, fmtId)
	local _, s, e = Notes.ParseDate(note)
	local out
	if s then
		out = note:sub(1, s - 1) .. Notes.FormatDate(t, fmtId) .. note:sub(e + 1)
	elseif U.Trim(note) == "" then
		out = stamp
	else
		out = stamp .. " " .. note
	end
	return U.Truncate(out, Notes.NOTE_MAX)
end

---------------------------------------------------------------------------
-- Permissions and writing
---------------------------------------------------------------------------
function Notes.CanEdit(which)
	if which == "officer" then
		local gi = C_GuildInfo
		return gi and gi.CanEditOfficerNote and gi.CanEditOfficerNote() or false
	end
	return CanEditPublicNote and CanEditPublicNote() or false
end

function Notes.CanViewOfficer()
	local gi = C_GuildInfo
	return gi and gi.CanViewOfficerNote and gi.CanViewOfficerNote() or false
end

-- Writes a public ("public") or officer ("officer") note. Returns true on success.
function Notes.Set(guid, which, text)
	if not guid or not (C_GuildInfo and C_GuildInfo.SetNote) then return false end
	if not Notes.CanEdit(which) then return false, "rank" end
	text = U.Truncate(text or "", Notes.NOTE_MAX)
	local ok, err = pcall(C_GuildInfo.SetNote, guid, text, which == "public")
	if not ok then return false, err end
	return true
end

-- On a live join, writes the join date into the note the guild chose (if any).
function Notes.WriteJoinDate(G, m)
	local where, fmtId = DB.JoinNoteSetting(G)
	if where ~= "public" and where ~= "officer" then return end
	if not m or not m.joined or not Notes.CanEdit(where) then return end
	local current = where == "public" and m.note or m.oNote
	local existing = Notes.ParseDate(current or "")
	if existing and Notes.SameDay(existing, m.joined.t) then return end
	local text = Notes.WithDate(current, m.joined.t, fmtId, L["Joined "])
	if Notes.Set(m.guid, where, text) then
		if where == "public" then m.note = text else m.oNote = text end
	end
end

-- Join date tool: compares saved join dates with dates found in notes.
-- Returns a list of { m, saved, noteDate, where, status } where status is
-- "match", "mismatch", "noteOnly", "savedOnly", or "none".
function Notes.Audit(G)
	local where = DB.JoinNoteSetting(G)
	if where ~= "officer" then where = "public" end
	local out = {}
	for _, m in pairs(G.members) do
		local note = where == "public" and m.note or m.oNote
		local noteDate = Notes.ParseDate(note or "")
		local otherDate = Notes.ParseDate((where == "public" and m.oNote or m.note) or "")
		local saved = m.joined and m.joined.t
		local status
		if saved and noteDate then status = Notes.SameDay(saved, noteDate) and "match" or "mismatch"
		elseif noteDate then status = "noteOnly"
		elseif saved then status = "savedOnly"
		else status = "none" end
		out[#out + 1] = { m = m, saved = saved, noteDate = noteDate, otherDate = otherDate, where = where, status = status }
	end
	table.sort(out, function(a, b) return (a.m.name or "") < (b.m.name or "") end)
	return out
end

-- Takes join dates from notes for members who have none saved (or whose saved date
-- was only guessed). Returns the count changed.
function Notes.ImportFromNotes(G, overwrite)
	local n, now = 0, U.Now()
	for _, row in ipairs(Notes.Audit(G)) do
		local d = row.noteDate or row.otherDate
		if d and (row.status == "noteOnly" or (overwrite and row.status == "mismatch") or (row.status == "none" and d)) then
			row.m.joined = { t = d, src = "note", ts = now }
			if GM.Sync then GM.Sync.Broadcast(G, "J", row.m.guid) end
			n = n + 1
		end
	end
	if n > 0 then GM:Fire("ROSTER_UPDATED", G) end
	return n
end

-- Note writes for many members go out one at a time, so the server isn't flooded.
local queue, ticking = {}, false
local function Pump()
	local job = table.remove(queue, 1)
	if not job then ticking = false return end
	if Notes.Set(job.guid, job.where, job.text) then
		local G = GM.G
		local m = G and DB.Find(G, job.guid)
		if m then if job.where == "public" then m.note = job.text else m.oNote = job.text end end
	end
	C_Timer.After(0.6, Pump)
end

function Notes.Queue(guid, where, text)
	queue[#queue + 1] = { guid = guid, where = where, text = text }
	if not ticking then
		ticking = true
		C_Timer.After(0.1, Pump)
	end
end

function Notes.QueueLength() return #queue end

-- Writes saved join dates into notes (missing ones, or mismatched ones too). One SetNote per member.
function Notes.ExportToNotes(G, includeMismatches)
	local where, fmtId = DB.JoinNoteSetting(G)
	if where ~= "public" and where ~= "officer" then where = "public" end
	if not Notes.CanEdit(where) then return 0, "rank" end
	local n = 0
	for _, row in ipairs(Notes.Audit(G)) do
		if row.status == "savedOnly" or (includeMismatches and row.status == "mismatch") then
			local current = where == "public" and row.m.note or row.m.oNote
			local text = Notes.WithDate(current, row.saved, fmtId, L["Joined "])
			Notes.Queue(row.m.guid, where, text)
			n = n + 1
		end
	end
	return n
end
