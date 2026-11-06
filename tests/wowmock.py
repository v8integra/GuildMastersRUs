"""Minimal WoW API mock for running the addon's Lua offline with lupa.

make_runtime() returns a LuaRuntime with the mock loaded. load_toc() loads every file
listed in the TOC, the way the game does (each chunk gets ("GuildMastersRus", ns)).
"""
import os
import re
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PRELUDE = r"""
-- Lua 5.1 compatibility bits WoW has
math.atan2 = math.atan2 or math.atan
math.randomseed = nil -- WoW does not have it
unpack = unpack or table.unpack
table.getn = table.getn or function(t) return #t end
tinsert, tremove = table.insert, table.remove
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strsplit(sep, s, limit)
  local out, start = {}, 1
  while true do
    local i, j = string.find(s, sep, start, true)
    if not i then out[#out + 1] = string.sub(s, start) break end
    out[#out + 1] = string.sub(s, start, i - 1)
    start = j + 1
  end
  return table.unpack(out)
end
date, time = os.date, os.time
format = string.format

printed = {}
function print(...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
  printed[#printed + 1] = table.concat(t, " ")
end
errors = {}
function geterrorhandler() return function(e) errors[#errors + 1] = tostring(e) end end

NOW = 1790000000
function GetServerTime() return NOW end
function GetTime() return NOW end

SECRET = setmetatable({}, { __tostring = function() return "SECRET" end })
function issecretvalue(v) return v == SECRET end

-- timers
timers = {}
C_Timer = {
  After = function(s, fn) timers[#timers + 1] = fn end,
  NewTicker = function(s, fn) return { Cancel = function() end, fn = fn } end,
}
function RunTimers(rounds)
  for _ = 1, rounds or 5 do
    local list = timers
    timers = {}
    if #list == 0 then return end
    for _, fn in ipairs(list) do fn() end
  end
end

---------------------------------------------------------------------------
-- permissive frames
---------------------------------------------------------------------------
frames = {}
local Frame = {}
local FrameMT = { __index = function(t, k)
  local v = Frame[k]
  if v ~= nil then return v end
  if type(k) ~= "string" or not k:match("^%u") then return nil end -- fields: nil, like real frames
  return function(self, ...) return self end -- unknown methods: chainable no-ops
end }

local function NewFrame(kind, name, parent)
  local f = setmetatable({ _kind = kind, _name = name, _parent = parent, _shown = true, _scripts = {}, _events = {}, _attr = {}, _text = "", _w = 800, _h = 500 }, FrameMT)
  frames[#frames + 1] = f
  if name then _G[name] = f end
  return f
end
function Frame:GetName() return self._name end
function Frame:GetParent() return self._parent end
function Frame:RegisterEvent(e) self._events[e] = true end
function Frame:UnregisterEvent(e) self._events[e] = nil end
function Frame:SetScript(k, fn) self._scripts[k] = fn end
function Frame:GetScript(k) return self._scripts[k] end
function Frame:HookScript(k, fn)
  local old = self._scripts[k]
  if old then self._scripts[k] = function(...) old(...) fn(...) end else self._scripts[k] = fn end
end
function Frame:Run(k, ...) local fn = self._scripts[k] if fn then return fn(self, ...) end end
function Frame:Show() local was = self._shown self._shown = true if not was then self:Run("OnShow") end end
function Frame:Hide() local was = self._shown self._shown = false if was then self:Run("OnHide") end end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self._shown end
function Frame:IsVisible() local f = self while f do if not f._shown then return false end f = f._parent end return true end
function Frame:SetText(t) self._text = t end
function Frame:GetText() return self._text end
function Frame:SetChecked(v) self._checked = v end
function Frame:GetChecked() return self._checked end
function Frame:SetSize(w, h) self._w, self._h = w, h end
function Frame:SetWidth(w) self._w = w end
function Frame:SetHeight(h) self._h = h end
function Frame:GetWidth() return self._w end
function Frame:GetHeight() return self._h end
function Frame:GetStringHeight() return 12 end
function Frame:GetFrameLevel() return 1 end
function Frame:HasFocus() return false end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetCenter() return 0, 0 end
function Frame:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Frame:SetAttribute(k, v) self._attr[k] = v end
function Frame:GetAttribute(k) return self._attr[k] end
function Frame:IsTruncated() return false end
function Frame:Enable() self._enabled = true end
function Frame:Disable() self._enabled = false end
function Frame:IsEnabled() return self._enabled ~= false end
function Frame:CreateFontString() return NewFrame("FontString", nil, self) end
function Frame:CreateTexture() return NewFrame("Texture", nil, self) end
function Frame:GetThumbTexture() return NewFrame("Texture", nil, self) end
function Frame:GetMinMaxValues() return 0, 0 end
function Frame:SetValue(v) self._value = v local fn = self._scripts.OnValueChanged if fn then fn(self, v) end end

function CreateFrame(kind, name, parent, template)
  local f = NewFrame(kind, name, parent)
  f._template = template
  return f
end
function FireEvent(event, ...)
  for _, f in ipairs(frames) do
    if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end

UIParent = NewFrame("Frame", "UIParent")
Minimap = NewFrame("Frame", "Minimap")
GameTooltip = NewFrame("GameTooltip", "GameTooltip")
UISpecialFrames = {}
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 0.5, b = 0.25 } end })
ChatTypeInfo = { RAID_WARNING = {} }
RaidWarningFrame = NewFrame("Frame", "RaidWarningFrame")
function RaidNotice_AddMessage() end
SlashCmdList = {}
function hooksecurefunc(t, k, fn)
  if type(t) == "string" then t, k, fn = _G, t, k end
  local old = t[k]
  t[k] = function(...) local r = { old(...) } fn(...) return table.unpack(r) end
end
function InCombatLockdown() return MOCK.combat end
function IsShiftKeyDown() return false end
function GetCursorPosition() return 0, 0 end
function GetLocale() return "enUS" end
function ReloadUI() end
function GetMaxLevelForPlayerExpansion() return 80 end

-- menus: run generators against a recording root
menuLog = {}
local function MenuRoot()
  local root = {}
  root.CreateButton = function(_, text, cb) menuLog[#menuLog + 1] = { "button", text, cb } return root end
  root.CreateCheckbox = function(_, text, get, set) if get then get() end menuLog[#menuLog + 1] = { "check", text, set } return root end
  root.CreateRadio = function(_, text, get, set) if get then get() end menuLog[#menuLog + 1] = { "radio", text, set } return root end
  root.CreateTitle = function() return root end
  root.CreateDivider = function() return root end
  return root
end
MenuUtil = { CreateContextMenu = function(owner, gen) menuLog = {} gen(owner, MenuRoot()) end }
modifiedMenus = {}
Menu = { ModifyMenu = function(tag, fn) modifiedMenus[tag] = fn end }

-- Settings API
local function Obj() return setmetatable({}, { __index = function(t, k) return function() return Obj() end end }) end
Settings = {
  VarType = { Boolean = "boolean", Number = "number", String = "string" },
  RegisterVerticalLayoutCategory = function(name) local c = Obj() c.GetID = function() return 1 end return c, Obj() end,
  RegisterProxySetting = function(cat, var, typ, name, default, get, set) get() return Obj() end,
  CreateCheckbox = function() end, CreateSlider = function() end, CreateDropdown = function(_, _, opts) opts() end,
  CreateSliderOptions = function() return Obj() end,
  CreateControlTextContainer = function() local c = { data = {} } function c:Add(v, l) self.data[#self.data + 1] = { v, l } end function c:GetData() return self.data end return c end,
  RegisterAddOnCategory = function() end, OpenToCategory = function() end,
}
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
function CreateSettingsListSectionHeaderInitializer() return Obj() end
function CreateSettingsButtonInitializer() return Obj() end

---------------------------------------------------------------------------
-- player / guild
---------------------------------------------------------------------------
MOCK = { inGuild = true, guildName = "Test Guild", rankIndex = 1, combat = false, lockdown = false,
  members = {}, events = {}, ranks = { "Guild Master", "Officer", "Veteran", "Member", "Initiate" },
  canEditPublic = true, canEditOfficer = true, canViewOfficer = true, sent = {}, notesSet = {} }

function UnitName(u) if u == "player" then return "Raven" end return MOCK.units and MOCK.units[u] and MOCK.units[u].name end
function UnitFullName(u) if u == "player" then return "Raven", "Forever" end end
function UnitGUID(u) if u == "player" then return "Player-1-RAVEN" end return MOCK.units and MOCK.units[u] and MOCK.units[u].guid end
function UnitExists(u) return u == "player" or (MOCK.units and MOCK.units[u] ~= nil) end
function GetNormalizedRealmName() return "Forever" end
function GetRealmName() return "Forever" end
function IsInGuild() return MOCK.inGuild end
function IsInGroup() return MOCK.units ~= nil end
function IsInRaid() return false end
function GetNumGroupMembers() return 0 end
function CheckInteractDistance() return true end
function GetGuildInfo(u) if not MOCK.inGuild then return nil end return MOCK.guildName, MOCK.ranks[MOCK.rankIndex + 1], MOCK.rankIndex, nil end
function GuildControlGetNumRanks() return #MOCK.ranks end
function GuildControlGetRankName(i) return MOCK.ranks[i] end
function CanEditPublicNote() return MOCK.canEditPublic end
function CanGuildRemove() return true end
function CanGuildPromote() return true end
function CanGuildDemote() return true end
function IsGuildLeader() return MOCK.rankIndex == 0 end
C_GuildInfo = {
  GuildRoster = function() MOCK.rosterRequests = (MOCK.rosterRequests or 0) + 1 end,
  CanEditOfficerNote = function() return MOCK.canEditOfficer end,
  CanViewOfficerNote = function() return MOCK.canViewOfficer end,
  SetNote = function(guid, note, isPublic) MOCK.notesSet[#MOCK.notesSet + 1] = { guid, note, isPublic } end,
  IsGuildOfficer = function() return true end,
}
C_CreatureInfo = { GetClassInfo = function(id) return { classFile = "CLASS" .. tostring(id), className = "Class" .. tostring(id) } end }
C_AddOns = { IsAddOnLoaded = function() return false end }
C_PartyInfo = { InviteUnit = function() end }
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return 0 end,
  SendAddonMessage = function(p, m, c, t) MOCK.sent[#MOCK.sent + 1] = { p, m, c, t } return 0 end,
  InChatMessagingLockdown = function() return MOCK.lockdown end,
}
Enum = { ClubMemberPresence = { Unknown = 0, Online = 1, OnlineMobile = 2, Offline = 3, Away = 4, Busy = 5 },
  SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3 } }

-- roster: MOCK.members = list of { guid, name, rankOrder, level, classID, note, oNote, online, lastDays }
C_Club = {
  GetGuildClubId = function() return 7 end,
  GetClubMembers = function() local ids = {} for i in ipairs(MOCK.members) do ids[i] = i end return ids end,
  GetMemberInfo = function(_, i)
    local m = MOCK.members[i]
    if not m then return nil end
    return { guid = m.guid, name = m.name, guildRank = MOCK.ranks[m.rankOrder], guildRankOrder = m.rankOrder,
      level = m.level or 10, classID = m.classID or 1, zone = "Zone", memberNote = m.note or "", officerNote = m.oNote or "",
      presence = m.online and 1 or 3, lastOnlineYear = 0, lastOnlineMonth = 0, lastOnlineDay = m.online and nil or (m.lastDays or 1), lastOnlineHour = 0 }
  end,
}
function GetNumGuildMembers() return #MOCK.members end
-- event log: MOCK.events = list of { type, p1, p2, rank, hoursAgo }
function QueryGuildEventLog() end
function GetNumGuildEvents() return #MOCK.events end
function GetGuildEventInfo(i)
  local e = MOCK.events[i]
  local h = e[5] or 0
  local d = math.floor(h / 24)
  return e[1], e[2], e[3], e[4], 0, 0, d, h - d * 24
end
function GetBuildInfo() return "1.60.1", "70790", "Nov 4 2026", 16001 end
"""


def make_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute("ADDON_NS = {}")
    return lua


def load_file(lua, rel):
    path = os.path.join(ROOT, rel.replace("\\", os.sep))
    with open(path, encoding="utf-8") as fh:
        src = fh.read()
    loader = lua.eval("function(src, name) local f, err = load(src, '@' .. name) if not f then error(err) end return f end")
    chunk = loader(src, rel)
    lua.eval("function(f) return f('GuildMastersRus', ADDON_NS) end")(chunk)


def toc_files():
    with open(os.path.join(ROOT, "GuildMastersRus.toc"), encoding="utf-8") as fh:
        return [l.strip() for l in fh if l.strip() and not l.startswith("#")]


def load_toc(lua, only=None):
    for rel in toc_files():
        if only and not any(rel.replace("\\", "/").startswith(p) for p in only):
            continue
        load_file(lua, rel)


def printed(lua):
    return "\n".join(str(v) for v in lua.globals().printed.values())


def strip_codes(s):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", s)
