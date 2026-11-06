-- Guild Masters R Us - restore points and text export.
local _, GM = ...
local L = GM.L
local U = GM.U
local DB = GM.DB
local Backup = {}
GM.Backup = Backup
local Export = {}
GM.Export = Export

Backup.MAX = 5
local KEEP = { "members", "former", "bans", "altGroups", "rules", "rankNames", "guildSettings", "trackStart", "initialized", "announced" }

function Backup.List(G)
	local db = GM.db
	db.backups[G.key] = db.backups[G.key] or {}
	return db.backups[G.key]
end

function Backup.Save(G, label)
	local list = Backup.List(G)
	local data = {}
	for _, k in ipairs(KEEP) do data[k] = U.Copy(G[k]) end
	table.insert(list, 1, { t = U.Now(), label = label or L["Manual"], data = data, members = U.Count(G.members) })
	while #list > Backup.MAX do table.remove(list) end
	return list[1]
end

-- Replaces this guild's member data with the restore point (the log is kept).
function Backup.Restore(G, index)
	local b = Backup.List(G)[index]
	if not b then return false end
	for _, k in ipairs(KEEP) do G[k] = U.Copy(b.data[k]) end
	G.members, G.former = G.members or {}, G.former or {}
	GM.Log.Info(G, L["Restored data from the restore point of %s."]:format(date("%Y-%m-%d %H:%M", b.t)))
	GM:Fire("ROSTER_UPDATED", G)
	return true
end

function Backup.Delete(G, index)
	table.remove(Backup.List(G), index)
end

-- One automatic restore point per week.
function Backup.Auto(G)
	local list = Backup.List(G)
	local newestAuto
	for _, b in ipairs(list) do
		if b.auto then newestAuto = b break end
	end
	if not newestAuto or U.Now() - newestAuto.t > 7 * U.DAY then
		local b = Backup.Save(G, L["Weekly automatic"])
		b.auto = true
	end
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
local function Cell(v, delim)
	v = U.StripCodes(tostring(v == nil and "" or v)):gsub("[\r\n]", " ")
	if delim ~= "\t" and (v:find(delim, 1, true) or v:find('"', 1, true)) then
		v = '"' .. v:gsub('"', '""') .. '"'
	end
	return v
end

local function Row(cells, delim)
	local out = {}
	for i, c in ipairs(cells) do out[i] = Cell(c, delim) end
	return table.concat(out, delim)
end

local function D(t) return t and date("%Y-%m-%d", t) or "" end

local function Sorted(tbl)
	local list = {}
	for _, m in pairs(tbl) do list[#list + 1] = m end
	table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
	return list
end

function Export.Members(G, delim)
	local lines = { Row({ "Name", "Rank", "Level", "Class", "Joined", "Promoted", "Last online", "Main", "Alt group", "Public note", "Officer note", "Custom note", "Birthday" }, delim) }
	for _, m in ipairs(Sorted(G.members)) do
		local main = GM.Alts.MainName(G, m.guid)
		local alts = {}
		for _, g in ipairs(GM.Alts.GroupMembers(G, m.guid)) do
			if g ~= m.guid and G.members[g] then alts[#alts + 1] = U.DisplayName(G.members[g].name) end
		end
		local bd = m.birthday and m.birthday.m and ("%02d-%02d"):format(m.birthday.m, m.birthday.d or 0) or ""
		lines[#lines + 1] = Row({
			U.DisplayName(m.name), m.rank, m.level, m.classFile, D(m.joined and m.joined.t), D(m.promoted and m.promoted.t),
			m.online and "online" or D(m.lastOnline), main and U.DisplayName(main) or (GM.Alts.IsMain(G, m.guid) and "(main)" or ""),
			table.concat(alts, " "), m.note, m.oNote, m.custom and m.custom.text, bd,
		}, delim)
	end
	return table.concat(lines, "\n"), #lines - 1
end

function Export.Former(G, delim)
	local lines = { Row({ "Name", "Last rank", "Level", "Class", "Left", "How", "Times joined", "Banned", "Ban reason" }, delim) }
	for _, m in ipairs(Sorted(G.former)) do
		local ban = GM.Bans.Check(G, m.guid, m.name)
		lines[#lines + 1] = Row({
			U.DisplayName(m.name), m.rank, m.level, m.classFile, D(m.leftAt), m.leftHow or "", m.timesJoined or 1,
			ban and "yes" or "", ban and ban.reason or "",
		}, delim)
	end
	return table.concat(lines, "\n"), #lines - 1
end

function Export.Log(G, delim)
	local lines = { Row({ "Date", "Type", "Entry" }, delim) }
	local list = {}
	for _, e in ipairs(G.log) do list[#list + 1] = e end
	table.sort(list, function(a, b) return a.t < b.t end)
	for _, e in ipairs(list) do
		lines[#lines + 1] = Row({ date("%Y-%m-%d %H:%M", e.t), e.k, GM.Log.Text(e) }, delim)
	end
	return table.concat(lines, "\n"), #lines - 1
end

function Export.Bans(G, delim)
	local lines = { Row({ "Name", "Banned on", "By", "Reason" }, delim) }
	for _, row in ipairs(GM.Bans.List(G)) do
		local b = row.ban
		lines[#lines + 1] = Row({ U.DisplayName(b.name), D(b.t), b.by and U.DisplayName(b.by) or "", b.reason }, delim)
	end
	return table.concat(lines, "\n"), #lines - 1
end
