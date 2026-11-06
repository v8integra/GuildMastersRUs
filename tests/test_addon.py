"""Offline tests for Guild Masters R Us. Run: python tests/test_addon.py

Loads every file in the TOC against the WoW mock (tests/wowmock.py), then drives
scans, the event log, alts, bans, notes, rules, events, sync between two clients,
and opens every window/tab so UI code paths run at least once.
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wowmock import make_runtime, load_toc, printed, strip_codes  # noqa: E402

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


HOUR = 3600
DAY = 86400

ROSTER_LUA = r"""
MOCK.members = {
  { guid = "G-RAVEN", name = "Raven", rankOrder = 2, level = 80, online = true },
  { guid = "G-BOB", name = "Bob", rankOrder = 4, level = 70, lastDays = 2 },
  { guid = "G-BOBALT", name = "Bobalt", rankOrder = 5, level = 20, lastDays = 2 },
  { guid = "G-CARL", name = "Carl", rankOrder = 4, level = 45, lastDays = 300, note = "Joined 2025-01-15" },
  { guid = "G-DANA", name = "Dana", rankOrder = 3, level = 80, online = true, note = "tank" },
  { guid = "G-EVE", name = "Eve", rankOrder = 5, level = 12, lastDays = 1 },
  { guid = "G-FRED", name = "Fred", rankOrder = 5, level = 30, lastDays = 5 },
  { guid = "G-GINA", name = "Gina", rankOrder = 4, level = 60, lastDays = 400 },
  { guid = "G-HAL", name = "Hal", rankOrder = 5, level = 15, lastDays = 3 },
  { guid = "G-IVY", name = "Ivy", rankOrder = 1, level = 80, lastDays = 0, online = true },
  { guid = "G-JON", name = "Jon", rankOrder = 5, level = 10, lastDays = 8 },
  { guid = "G-KAT", name = "Kat", rankOrder = 4, level = 50, lastDays = 1 },
  { guid = "G-MAE", name = "Mae Stone-OtherRealm", rankOrder = 5, level = 9, lastDays = 1 },
}
MOCK.events = {
  { "invite", "Ivy", "Bob", nil, 24 * 40 },
  { "join", "Bob", nil, nil, 24 * 40 },
  { "promote", "Ivy", "Dana", "Veteran", 24 * 10 },
  { "invite", "Ivy", "Mae Stone", nil, 24 * 3 },
  { "join", "Mae Stone", nil, nil, 24 * 3 },
}
"""


def scan(lua, fire_log=True):
    lua.execute("FireEvent('GUILD_ROSTER_UPDATE')")
    lua.execute("RunTimers(1)")  # debounce -> ScanNow (waits for the event log)
    if fire_log:
        lua.execute("FireEvent('GUILD_EVENT_LOG_UPDATE')")
    lua.execute("RunTimers(3)")


def G(lua):
    return lua.eval("GuildMastersRus.G")


def log_kinds(lua):
    return [e.k for e in G(lua).log.values()]


def find_log(lua, kind, name=None):
    for e in G(lua).log.values():
        if e.k == kind and (name is None or (e.n and str(e.n).startswith(name))):
            return e
    return None


def boot(player="Raven", rank_index=1):
    lua = make_runtime()
    lua.execute(f"""
      MOCK.rankIndex = {rank_index}
      function UnitName(u) if u == 'player' then return '{player}' end return MOCK.units and MOCK.units[u] and MOCK.units[u].name end
      function UnitFullName(u) if u == 'player' then return '{player}', 'Forever' end end
      senderFilters = {{}}
      ChatFrameUtil = {{ AddSenderNameFilter = function(fn) senderFilters[#senderFilters + 1] = fn end }}
    """)
    lua.execute(ROSTER_LUA)
    load_toc(lua)
    lua.execute("FireEvent('ADDON_LOADED', 'GuildMastersRus')")
    lua.execute("FireEvent('PLAYER_LOGIN')")
    lua.execute("RunTimers(1)")
    return lua


def test_scanning():
    lua = boot()
    scan(lua)
    g = G(lua)
    check(g is not None and g.initialized, "first scan initializes the guild")
    check(len(list(g.members.keys())) == 13, "13 members stored")
    mae = g.members["G-MAE"]
    check(mae.name == "Mae Stone-OtherRealm" and mae.joined is not None and mae.invitedBy == "Ivy-Forever",
          "name with a space on another realm matches the event log")
    check(find_log(lua, "info") is not None, "tracking-started info entry")
    check(not find_log(lua, "join"), "no join spam on first scan")
    bob = g.members["G-BOB"]
    check(bob.joined is not None and bob.joined.src == "log", "Bob's join date back-filled from the event log")
    check(abs(bob.joined.t - (lua.eval("NOW") - 40 * DAY)) < 2 * DAY, "back-filled date is ~40 days ago")
    check(bob.invitedBy == "Ivy-Forever", "invited-by back-filled")
    dana = g.members["G-DANA"]
    check(dana.promoted is not None and dana.promoted.src == "log", "Dana's promotion back-filled")

    # --- live changes an hour later
    lua.execute(r"""
      NOW = NOW + 3600
      MOCK.members[2].rankOrder = 3                                  -- Bob promoted
      MOCK.members[3].level = 25                                     -- Bobalt levels
      MOCK.members[5].note = "main tank"                             -- Dana note
      MOCK.members[6].name = "Evelyn"                                -- Eve renamed (same GUID)
      table.remove(MOCK.members, 7)                                  -- Fred kicked
      MOCK.members[#MOCK.members + 1] = { guid = "G-NEW", name = "Newbie", rankOrder = 5, level = 5, online = true }
      MOCK.events[#MOCK.events + 1] = { "promote", "Raven", "Bob", "Veteran", 0 }
      MOCK.events[#MOCK.events + 1] = { "remove", "Ivy", "Fred", nil, 0 }
      MOCK.events[#MOCK.events + 1] = { "invite", "Raven", "Newbie", nil, 0 }
      MOCK.events[#MOCK.events + 1] = { "join", "Newbie", nil, nil, 0 }
    """)
    scan(lua)
    e = find_log(lua, "promote", "Bob")
    check(e is not None and e.a == "Raven-Forever", "promotion logged with who did it")
    check(find_log(lua, "level", "Bobalt") is not None, "level-up logged")
    check(find_log(lua, "note", "Dana") is not None, "note change logged")
    e = find_log(lua, "rename")
    check(e is not None and str(e.x.old).startswith("Eve") and str(e.x.new).startswith("Evelyn"), "rename logged")
    e = find_log(lua, "kick", "Fred")
    check(e is not None and e.a == "Ivy-Forever", "kick (not quit) logged with kicker")
    e = find_log(lua, "join", "Newbie")
    check(e is not None and e.a == "Raven-Forever", "join logged with inviter")
    g = G(lua)
    check(g.former["G-FRED"] is not None and g.former["G-FRED"].leftHow == "kick", "Fred moved to former members")
    check(len(list(g.members["G-BOB"].rankHist.values())) >= 1, "rank history recorded")

    # --- partial roster: nobody should "leave"
    lua.execute("SAVED = MOCK.members; MOCK.members = { SAVED[1], SAVED[2], SAVED[3] }; NOW = NOW + 3600")
    before = len(list(G(lua).former.keys()))
    scan(lua)
    check(len(list(G(lua).former.keys())) == before, "incomplete roster doesn't count as mass leave")
    lua.execute("MOCK.members = SAVED")

    # --- ban Fred, then Fred rejoins -> rejoin + ban warning
    lua.execute(r"""
      local G = GuildMastersRus.G
      GuildMastersRus.Bans.Add(G, "G-FRED", "Fred-Forever", "drama", false)
      NOW = NOW + 3 * 86400
      MOCK.members[#MOCK.members + 1] = { guid = "G-FRED", name = "Fred", rankOrder = 5, level = 31, online = true }
      MOCK.events[#MOCK.events + 1] = { "join", "Fred", nil, nil, 0 }
    """)
    scan(lua)
    e = find_log(lua, "rejoin", "Fred")
    check(e is not None and e.x.times == 1 and e.x.gone and e.x.gone >= 3 * DAY - HOUR,
          "rejoin logged with times and time away (%s)" % (None if e is None else str((e.x.times, e.x.gone))))
    check(find_log(lua, "banwarn", "Fred") is not None, "banned player rejoining is flagged")

    # --- something happened while nobody watched: Ghost joined and quit
    lua.execute(r"""
      NOW = NOW + 7200
      MOCK.events[#MOCK.events + 1] = { "join", "Ghost", nil, nil, 1 }
      MOCK.events[#MOCK.events + 1] = { "quit", "Ghost", nil, nil, 1 }
      MOCK.members[4].level = 46
    """)
    scan(lua)
    j = find_log(lua, "join", "Ghost")
    lv = find_log(lua, "leave", "Ghost")
    check(j is not None and j.x.fromLog, "join seen only in the event log is logged")
    check(lv is not None and lv.x.fromLog, "quit seen only in the event log is logged")
    # and not twice
    lua.execute("NOW = NOW + 3600")
    scan(lua)
    n = sum(1 for e in G(lua).log.values() if e.k == "join" and str(e.n).startswith("Ghost"))
    check(n == 1, f"event-log-only entries aren't repeated (got {n})")

    # --- return from inactivity + kick recommendation
    lua.execute(r"""
      NOW = NOW + 3600
      for _, m in ipairs(MOCK.members) do if m.guid == "G-GINA" then m.online = true end end
    """)
    scan(lua)
    check(find_log(lua, "return", "Gina") is not None, "back-from-inactivity logged")
    check(find_log(lua, "inactive", "Carl") is not None, "kick recommendation for Carl (300 days)")
    check(not any(k is None for k in log_kinds(lua)), "log entries have kinds")
    return lua


def test_logic(lua):
    r = lua.execute(r"""
      local GM = GuildMastersRus
      local G = GM.G
      local out = {}
      -- alts
      GM.Alts.Link(G, "G-BOB", "G-BOBALT")
      out.main = GM.Alts.GetMain(G, "G-BOBALT")
      out.isAlt = GM.Alts.IsAlt(G, "G-BOBALT")
      out.tag = GM.MainTagFor("Bobalt-Forever")
      GM.Alts.SetMain(G, "G-BOBALT")
      out.main2 = GM.Alts.GetMain(G, "G-BOB")
      GM.Alts.SetMain(G, "G-BOB")
      -- dates
      local N = GM.Notes
      local function D(s, dayFirst) local t = N.ParseDate(s, dayFirst) return t and os.date("%Y-%m-%d", t) or "nil" end
      out.d1 = D("Joined 2025-01-15")
      out.d2 = D("j 11/05/2026")
      out.d3 = D("05/11/2026", true)
      out.d4 = D("25/12/2024")
      out.d5 = D("3 Mar 2025")
      out.d6 = D("March 3, 2025")
      out.d7 = D("no date here")
      out.d8 = D("1/2/25")
      out.w1 = N.WithDate("tank", os.time({year=2026,month=1,day=2,hour=12}), "ymd", "Joined ")
      out.w2 = N.WithDate("Joined 2020-01-01 healer", os.time({year=2026,month=1,day=2,hour=12}), "ymd", "Joined ")
      -- import from notes (Carl has a date in his note)
      G.members["G-CARL"].joined = nil
      out.imported = N.ImportFromNotes(G, false)
      out.carlJoined = G.members["G-CARL"].joined and os.date("%Y-%m-%d", G.members["G-CARL"].joined.t)
      -- rules
      G.rules.kick.days = 200
      G.rules.kick.minRankOrder = 3
      local km = GM.Rules.KickMatches(G)
      out.kick = #km
      out.kickFirst = km[1] and km[1].m.name
      G.rules.promote = { { from = 5, days = 0, level = 20 } }
      local pm = GM.Rules.PromoteMatches(G)
      out.promote = #pm
      GM.Rules.SetSafe(G, "G-CARL", "kick", 30)
      out.kickAfterSafe = #GM.Rules.KickMatches(G)
      out.altRanks = #GM.Rules.AltRankMatches(G)
      -- events: Bob joined ~40 days ago; pretend 1 year
      G.members["G-BOB"].joined = { t = NOW - 365 * 86400 + 2 * 86400, src = "manual", ts = NOW }
      local up = GM.Events.Upcoming(G, NOW, 30)
      out.events = #up
      out.eventKind = up[1] and up[1].kind
      G.members["G-KAT"].birthday = { m = tonumber(os.date("%m", NOW + 86400)), d = tonumber(os.date("%d", NOW + 86400)), ts = NOW }
      out.events2 = #GM.Events.Upcoming(G, NOW, 30)
      -- export / backup
      out.exportMembers = select(2, GM.Export.Members(G, "\t"))
      out.exportLog = select(2, GM.Export.Log(G, ","))
      out.exportFormer = select(2, GM.Export.Former(G, ";"))
      GM.Backup.Save(G, "test")
      local before = G.members["G-KAT"].birthday
      G.members["G-KAT"].birthday = nil
      GM.Backup.Restore(G, 1)
      out.restored = G.members["G-KAT"].birthday ~= nil
      -- bans
      local n = GM.Bans.Add(G, "G-BOB", "Bob-Forever", "test", true)
      out.banAlts = n
      out.bobalt = GM.Bans.Check(G, "G-BOBALT", "Bobalt-Forever") ~= nil
      local _, key = GM.Bans.Check(G, "G-BOB")
      GM.Bans.Remove(G, key)
      GM.Bans.Remove(G, "G-BOBALT")
      out.bansLeft = #GM.Bans.List(G)
      return out
    """)
    o = {k: r[k] for k in r.keys()}
    check(o["main"] == "G-BOB" and o["isAlt"], "alt link: Bob is main of Bobalt")
    check(o["tag"] and "Bob" in strip_codes(o["tag"]), f"main tag for alt in chat ({o['tag']})")
    check(o["main2"] == "G-BOBALT", "set main moves main status")
    check(o["d1"] == "2025-01-15", f"date ymd ({o['d1']})")
    check(o["d2"] == "2026-11-05", f"date mdy ({o['d2']})")
    check(o["d3"] == "2026-11-05", f"date dmy with day-first ({o['d3']})")
    check(o["d4"] == "2024-12-25", f"date dmy when day > 12 ({o['d4']})")
    check(o["d5"] == "2025-03-03", f"date '3 Mar 2025' ({o['d5']})")
    check(o["d6"] == "2025-03-03", f"date 'March 3, 2025' ({o['d6']})")
    check(o["d7"] == "nil", "no date found")
    check(o["d8"] == "2025-01-02", f"two-digit year ({o['d8']})")
    check(o["w1"] == "Joined 2026-01-02 tank", f"join date added to note ({o['w1']})")
    check(o["w2"] == "Joined 2026-01-02 healer", f"existing date replaced ({o['w2']})")
    check(o["imported"] >= 1 and o["carlJoined"] == "2025-01-15", "import join date from note")
    check(o["kick"] == 1 and str(o["kickFirst"]).startswith("Carl"), f"kick matches: Carl only, Gina is back online (got {o['kick']}, first {o['kickFirst']})")
    check(o["kickAfterSafe"] == o["kick"] - 1, "safe list removes a member from kick matches")
    check(o["promote"] >= 1, "promote rule matches level 20+ initiates")
    check(o["altRanks"] >= 1, "alt rank mismatch found (Bobalt vs Bob)")
    check(o["events"] >= 1 and o["eventKind"] == "anniversary", "upcoming anniversary")
    check(o["events2"] == o["events"] + 1, "upcoming birthday")
    check(o["exportMembers"] >= 13 and o["exportLog"] > 5 and o["exportFormer"] >= 0, "exports produce rows")
    check(o["restored"], "restore point brings data back")
    check(o["banAlts"] == 1 and o["bobalt"], "ban with alts")
    check(o["bansLeft"] == 1, f"removing bans leaves Fred's ({o['bansLeft']})")


def test_sync():
    a = boot("Raven", 1)   # officer (rank 2)
    b = boot("Bob", 3)     # member (rank 4)
    scan(a)
    scan(b)
    # A edits a join date, B asks for updates
    a.execute(r"""
      local G = GuildMastersRus.G
      G.members["G-KAT"].joined = { t = NOW - 100 * 86400, src = "manual", ts = NOW }
      GuildMastersRus.Sync.Broadcast(G, "J", "G-KAT")
      for _ = 1, 5 do GuildMastersRus.Sync.Pump() end
    """)
    msgs = [m for m in a.eval("MOCK.sent").values()]
    live = [m for m in msgs if str(m[2]).startswith("D:live:")]
    check(len(live) == 1, f"live edit broadcast ({len(live)})")

    def deliver(src, dst, sender):
        for m in list(src.eval("MOCK.sent").values()):
            dst.globals().DELIVER = m[2]
            dst.execute(f"FireEvent('CHAT_MSG_ADDON', 'GMRU', DELIVER, '{m[3]}', '{sender}')")
        src.execute("MOCK.sent = {}")

    deliver(a, b, "Raven-Forever")
    kat = b.eval("GuildMastersRus.G.members['G-KAT'].joined")
    check(kat is not None and kat.src == "manual", "B accepted A's join date (officer rank)")

    # B (rank 4, below sync rank 2) edits -> not sent
    b.execute(r"""
      local G = GuildMastersRus.G
      G.members["G-HAL"].custom = { text = "hi", ts = NOW }
      GuildMastersRus.Sync.Broadcast(G, "J", "G-HAL")
      for _ = 1, 5 do GuildMastersRus.Sync.Pump() end
    """)
    sent_b = [m for m in b.eval("MOCK.sent").values() if str(m[2]).startswith("D:")]
    check(len(sent_b) == 0, "low-rank member's edits aren't sent")
    b.execute("MOCK.sent = {}")

    # a forged record from B is rejected by A
    a.globals().FORGED = "D:live:J^G-HAL^1000^" + str(10**10) + "^manual"
    a.execute("FireEvent('CHAT_MSG_ADDON', 'GMRU', FORGED, 'GUILD', 'Bob-Forever')")
    hal = a.eval("GuildMastersRus.G.members['G-HAL'].joined")
    check(hal is None or hal.ts != 10**10, "record from a too-low rank is rejected")

    # hello / full sync: A has a ban + alt link B doesn't know about
    a.execute(r"""
      local GM = GuildMastersRus
      local G = GM.G
      GM.Bans.Add(G, nil, "Troll-Forever", "spam", false)
      GM.Alts.Link(G, "G-KAT", "G-JON")
      MOCK.sent = {}
    """)
    b.execute("GuildMastersRus.Sync.Hello(true)")
    b.execute("GuildMastersRus.Sync.Pump()")
    deliver(b, a, "Bob-Forever")          # A hears the hello
    a.execute("RunTimers(2)")              # A's reply delay
    for _ in range(30):
        a.execute("GuildMastersRus.Sync.Pump()")
    deliver(a, b, "Raven-Forever")
    ban = b.eval("GuildMastersRus.Bans.Check(GuildMastersRus.G, nil, 'Troll-Forever')")
    check(ban is not None, "full sync delivers the ban list")
    main = b.eval("GuildMastersRus.Alts.GetMain(GuildMastersRus.G, 'G-JON')")
    check(main == "G-KAT", f"full sync delivers alt links ({main})")
    users = b.eval("GuildMastersRus.Sync.users['Raven-Forever']")
    check(users is not None, "sync users list knows Raven")

    # newest edit wins
    a.execute(r"""
      local G = GuildMastersRus.G
      G.members["G-KAT"].joined = { t = NOW - 5 * 86400, src = "manual", ts = NOW - 100 }
    """)
    b.execute("MOCK.sent = {}")
    a.globals().OLD = "D:live:J^G-KAT^123^" + str(1) + "^manual"
    a.execute("FireEvent('CHAT_MSG_ADDON', 'GMRU', OLD, 'GUILD', 'Ivy-Forever')")
    t = a.eval("GuildMastersRus.G.members['G-KAT'].joined.t")
    check(t != 123, "older edit doesn't overwrite a newer one")

    # guild settings only from the guild master
    a.globals().GS = "D:live:GS^1^1^1^public^dmy^" + str(10**10) + "^Bob-Forever"
    a.execute("FireEvent('CHAT_MSG_ADDON', 'GMRU', GS, 'GUILD', 'Bob-Forever')")
    check(a.eval("GuildMastersRus.G.guildSettings") is None, "guild settings from a non-GM are ignored")
    a.execute("FireEvent('CHAT_MSG_ADDON', 'GMRU', GS, 'GUILD', 'Ivy-Forever')")
    gs = a.eval("GuildMastersRus.G.guildSettings")
    check(gs is not None and gs.joinNote == "public", "guild settings from the GM are applied")


def test_ui(lua):
    lua.execute(r"""
      local GM = GuildMastersRus
      for _, cmd in ipairs({ "", "log", "roster", "audit", "bans", "tools", "events", "users", "export", "help", "version", "group", "card Bob", "probe", "ping" }) do
        SlashCmdList.GUILDMASTERSRUS(cmd)
      end
      RunTimers(3)
      -- every tab, refreshed
      for _, tab in ipairs(GM.UI.tabs) do GM.UI.Show(tab.id) GM.UI.RefreshCurrent() end
      -- tools modes
      local tools
      for _, t in ipairs(GM.UI.tabs) do if t.id == "tools" then tools = t end end
      GM.UI.Show("tools")
      -- member card for current and former members
      GM.Card.Show("G-BOB", true)
      GM.Card.Refresh()
      GM.Card.Show("G-FRED", true)
      GM.Card.Refresh()
      GM.Card.PromptDate(GM.G, GM.G.members["G-BOB"], "joined")
      local d = _G.GuildMastersRusDialog
      d.edit:SetText("2024-05-06")
      d.yes:Run("OnClick")
      GM.Card.PromptBirthday(GM.G, GM.G.members["G-BOB"])
      d.edit:SetText("07/23")
      d.yes:Run("OnClick")
      -- context menus
      GM.UI.MemberMenu(UIParent, GM.G, GM.G.members["G-BOB"])
      for tag, fn in pairs(modifiedMenus) do
        fn(UIParent, MenuUtil and { CreateDivider = function() end, CreateTitle = function() end, CreateButton = function() end }, { guid = "G-BOB", name = "Bob" })
      end
      -- dropdown generators on the log tab
      GM.UI.Show("log")
      -- chat tag through the sender-name filter
      CHATOUT = senderFilters[1] and senderFilters[1]("CHAT_MSG_GUILD", "[Bobalt]", "hi", "Bobalt-Forever")
      CHATSECRET = senderFilters[1] and senderFilters[1]("CHAT_MSG_GUILD", "[Bobalt]", "hi", SECRET)
      -- group info
      MOCK.units = { party1 = { name = "Fred", guid = "G-FRED" }, party2 = { name = "Stranger", guid = "G-X" } }
      FireEvent("GROUP_ROSTER_UPDATE")
      RunTimers(2)
      GROUPROWS = #GM.GroupInfo.Scan(GM.G)
      -- !note trigger
      GM.settings.noteTrigger = true
      MOCK.notesSet = {}
      FireEvent("CHAT_MSG_GUILD", "!note loves pie", "Kat-Forever")
      RunTimers(2)
      NOTESET = MOCK.notesSet[1] and MOCK.notesSet[1][2]
      -- options and minimap
      GM.OpenOptions()
      GuildMastersRus_OnCompartmentClick("GuildMastersRus", "LeftButton")
      GuildMastersRus_OnCompartmentEnter("GuildMastersRus", UIParent)
      -- combat-safety of the action button
      FireEvent("PLAYER_REGEN_DISABLED")
      ACTMACRO = GuildMastersRusActionButton and GuildMastersRusActionButton:GetAttribute("macrotext")
    """)
    out = lua.eval("CHATOUT")
    check(out is not None and "Bob" in strip_codes(str(out)), f"chat main tag appended ({out})")
    check(lua.eval("CHATSECRET") is None, "secret sender names are left alone")
    check(lua.eval("GROUPROWS") == 2, "group info scans party members")
    p = strip_codes(printed(lua))
    check("former guildie" in p or "ban list" in p, "group notice for former/banned guildie")
    check(lua.eval("NOTESET") == "loves pie", f"!note sets the public note ({lua.eval('NOTESET')})")
    check(lua.eval("ACTMACRO") is None, "action button emptied when combat starts")
    bob = lua.eval("GuildMastersRus.G.members['G-BOB']")
    check(bob.joined.src == "manual" and lua.eval("os.date('%Y-%m-%d', GuildMastersRus.G.members['G-BOB'].joined.t)") == "2024-05-06", "join date edited from the card")
    check(bob.birthday.m == 7 and bob.birthday.d == 23, "birthday set from the card")
    check("Probe:" in p, "probe ran")


def main():
    lua = test_scanning()
    test_logic(lua)
    test_ui(lua)
    test_sync()
    errs = [str(e) for e in lua.eval("errors").values()]
    p = printed(lua)
    for line in p.splitlines():
        if "|cffff4444" in line:
            errs.append("printed error: " + line)
    for e in errs:
        failures.append("Lua error: " + e)
    if failures:
        print("FAIL (%d):" % len(failures))
        for f in failures:
            print("  - " + f)
        sys.exit(1)
    print("all checks passed")


if __name__ == "__main__":
    main()
