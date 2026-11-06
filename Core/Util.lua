-- Guild Masters R Us - shared helpers: time, names, colors, text.
local _, GM = ...
local L = GM.L
local U = {}
GM.U = U

local DAY = 86400
U.DAY = DAY

function U.Now()
	if GetServerTime then
		local t = GetServerTime()
		if t and not GM.IsSecret(t) and t > 0 then return t end
	end
	return time()
end

-- Converts "how long ago" parts (as the guild roster and event log give them) to a time.
function U.ElapsedToTime(now, y, m, d, h)
	local hours = ((tonumber(y) or 0) * 365 + (tonumber(m) or 0) * 30 + (tonumber(d) or 0)) * 24 + (tonumber(h) or 0)
	return now - hours * 3600
end

-- "3 days", "2 months 5 days", "4 hours", "a few minutes"
function U.FormatDuration(seconds)
	seconds = math.max(0, seconds or 0)
	local days = math.floor(seconds / DAY)
	if days >= 365 then
		local years = math.floor(days / 365)
		local months = math.floor((days - years * 365) / 30)
		if months > 0 then return L["%d yr %d mo"]:format(years, months) end
		return years == 1 and L["1 year"] or L["%d years"]:format(years)
	elseif days >= 30 then
		local months = math.floor(days / 30)
		local rest = days - months * 30
		if rest > 0 then return L["%d mo %d days"]:format(months, rest) end
		return months == 1 and L["1 month"] or L["%d months"]:format(months)
	elseif days >= 1 then
		return days == 1 and L["1 day"] or L["%d days"]:format(days)
	end
	local hours = math.floor(seconds / 3600)
	if hours >= 1 then return hours == 1 and L["1 hour"] or L["%d hours"]:format(hours) end
	return L["under an hour"]
end

function U.FormatAgo(t, now)
	if not t then return L["unknown"] end
	return L["%s ago"]:format(U.FormatDuration((now or U.Now()) - t))
end

---------------------------------------------------------------------------
-- Names. Stored names are always "Name-Realm".
---------------------------------------------------------------------------
local function MyRealm()
	local r = GetNormalizedRealmName and GetNormalizedRealmName()
	if not r or r == "" or GM.IsSecret(r) then
		r = GetRealmName and GetRealmName() or ""
		r = r:gsub("[%s%-]", "")
	end
	return r
end
U.MyRealm = MyRealm

-- Forever gives guild members' names WITHOUT a realm, even though the guild spans several
-- realms, and guessing a realm breaks invites and matching. So names are kept exactly as the
-- game gives them, and names are compared by character name only. Members themselves are
-- identified by GUID.
function U.FullName(name)
	if type(name) ~= "string" or name == "" or GM.IsSecret(name) then return nil end
	return name
end

function U.ShortName(name)
	if type(name) ~= "string" then return name end
	return (name:match("^([^%-]+)")) or name
end

function U.DisplayName(name)
	if type(name) ~= "string" then return L["Unknown"] end
	return U.ShortName(name)
end

function U.NameKey(name)
	if type(name) ~= "string" or name == "" or GM.IsSecret(name) then return nil end
	return U.ShortName(name):lower()
end

function U.SameName(a, b)
	local ka, kb = U.NameKey(a), U.NameKey(b)
	return ka ~= nil and ka == kb
end

function U.MyName()
	local n = UnitName("player")
	if n and not GM.IsSecret(n) then return n end
	return nil
end

---------------------------------------------------------------------------
-- Classes
---------------------------------------------------------------------------
function U.ClassFile(classID)
	if not classID then return nil end
	if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
		local info = C_CreatureInfo.GetClassInfo(classID)
		if info then return info.classFile, info.className end
	end
	return nil
end

function U.ClassColorHex(classFile)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c then
		return ("ff%02x%02x%02x"):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
	end
	return "ffffffff"
end

function U.ColorName(m)
	if not m then return L["Unknown"] end
	local hex = U.ClassColorHex(m.classFile)
	return "|c" .. hex .. U.DisplayName(m.name) .. "|r"
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
function U.StripCodes(s)
	if type(s) ~= "string" then return s end
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
	return s
end

function U.Trim(s)
	if type(s) ~= "string" then return s end
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- UTF-8 aware truncation by character count.
function U.Truncate(s, maxChars)
	if type(s) ~= "string" then return s end
	local count, i = 0, 1
	local len = #s
	while i <= len do
		count = count + 1
		if count > maxChars then return s:sub(1, i - 1) end
		local c = s:byte(i)
		if c >= 240 then i = i + 4 elseif c >= 224 then i = i + 3 elseif c >= 192 then i = i + 2 else i = i + 1 end
	end
	return s
end

function U.CharCount(s)
	if type(s) ~= "string" then return 0 end
	local _, n = s:gsub("[^\128-\191]", "")
	return n
end

function U.Copy(t, seen)
	if type(t) ~= "table" then return t end
	seen = seen or {}
	if seen[t] then return seen[t] end
	local out = {}
	seen[t] = out
	for k, v in pairs(t) do out[U.Copy(k, seen)] = U.Copy(v, seen) end
	return out
end

function U.Count(t)
	local n = 0
	if t then for _ in pairs(t) do n = n + 1 end end
	return n
end

-- Sync field escaping (keeps ^ ~ : | % out of the payload).
function U.Escape(s)
	s = tostring(s == nil and "" or s)
	return (s:gsub("[%%%^~:|\n]", function(c) return ("%%%02X"):format(c:byte()) end))
end

function U.Unescape(s)
	if not s then return nil end
	return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function U.InCombat()
	return InCombatLockdown and InCombatLockdown()
end
