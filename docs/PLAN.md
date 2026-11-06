# Guild Masters R Us — Plan

A guild roster manager for WoW: Forever (interface `16001`), covering the features guilds use in
retail's Guild Roster Manager (GRM). It's a new build from scratch written for Forever's client,
not a port of GRM's code.

- Folder / addon name: `GuildMastersRus` · Title: **Guild Masters R Us**
- Slash: `/gmru` (alias `/guildmasters`) · SavedVariables: `GuildMastersRusDB`
- Addon-message prefix: `GMRU`

## What the Forever client gives us (checked in `Gethe/wow-ui-source`, branch `forever`, 2026-11-04)

| Need | API | Notes |
|---|---|---|
| Roster | `C_Club.GetGuildClubId()` + `C_Club.GetClubMembers` / `C_Club.GetMemberInfo` | Blizzard's own Communities roster uses this. Gives guid, name, rank + rankOrder, level, class, zone, member/officer note, professions, **lastOnline year/month/day/hour**, presence. |
| Refresh | `C_GuildInfo.GuildRoster()` → `GUILD_ROSTER_UPDATE` | Throttled by the server; don't spam it. |
| Who did what, when | `QueryGuildEventLog()` → `GUILD_EVENT_LOG_UPDATE`, `GetNumGuildEvents`, `GetGuildEventInfo(i)` | Types: invite, join, promote, demote, remove (kick), quit — with actor, target, rank, and a date. This is how we tell a kick from a quit, and who promoted whom. |
| Notes | `C_GuildInfo.SetNote(guid, note, isPublic)`, `CanEditOfficerNote`, `CanViewOfficerNote` | No restriction flag. |
| Rank / kick | `/gpromote`, `/gdemote`, `/gremove` run from a secure button | The docs show no restriction flag on `C_GuildInfo.Promote/Demote/Uninvite`, but retail blocks addons from calling them (since patch 7.3), which is why GRM builds macros. Assume they're blocked here too until an in-game test says otherwise. |
| Calendar | `C_Calendar.AddEvent` | **HasRestrictions**: we announce anniversaries but don't add calendar events. |
| Ranks | `GuildControlGetNumRanks`, `GuildControlGetRankName`, `C_GuildInfo.GuildControlGetRankFlags` | |
| Officer sync | `C_ChatInfo.RegisterAddonMessagePrefix` / `SendAddonMessage(prefix, msg, "GUILD")` | `SecretArguments = NotAllowed`: never pass a value we got from a secret source. |
| MOTD / info text | `C_GuildInfo.GetMOTD`, `GetInfoText` | **HasRestrictions** — read-only display at most; don't build on it. |

Legacy globals (`GetGuildRosterInfo`, `GetGuildRosterLastOnline`, `GuildRosterSetOfficerNote`) aren't
used anywhere in Forever's UI. We use `C_Club` and only fall back to the globals if Phase 0 shows
`C_Club` is missing data.

**Limitation to be honest about:** an addon only sees changes while someone running it is online.
Changes made while nobody's online are reconstructed from the event log on next login (the log is
short, about the last 100 entries) and from roster diffs. Officer sync (Phase 4) fills most gaps.

## Status (2026-11-05)
All phases (1–6, including 5b) are built as **0.9.0-beta** and pass the offline tests
(`tests/test_addon.py`). Nothing has been run in game yet; the guild master is testing with
[BETA_TESTING.md](BETA_TESTING.md). Notes from the build:
- Trade-range dots are in our group window, not on Blizzard's party/raid frames (avoids tainting them).
- The kick/promote button is a secure button parented to UIParent; it's emptied and hidden when combat starts.
- The main tag uses Forever's `ChatFrameUtil.AddSenderNameFilter`, which skips secret names by itself.
- Member data is keyed by GUID; a guild rename is detected by roster overlap and the data carries over.

## Phases

Each phase ends with an in-game test by the user before the next one starts.

### Phase 0 — In-game probe (go/no-go)
`/gmru probe` prints what the client actually returns:
- `C_Club` guild member fields — are lastOnline, officer note, and guid filled in for offline members?
- `GetGuildEventInfo` after `QueryGuildEventLog` — entry count, oldest date, name format (with realm?).
- Whether any field comes back as a secret value (`issecretvalue`).
- Whether `SendAddonMessage(..., "GUILD")` returns success (a second person is needed to confirm receipt).

### Phase 1 — Roster database + change log (the core)
- Members are stored by **GUID**, so renames are tracked rather than seen as new people.
- Each roster update is diffed against the stored snapshot. Former members are kept, so rejoins are recognized.
- Log entry types (each can be switched on/off for the log and for chat separately):
  joined · rejoined (times in guild before, how long they were gone, **warning if banned**) · invited by ·
  left vs kicked (and by whom), listing alts still in the guild · promoted/demoted (from → to, by whom) ·
  leveled (filters: minimum level, level range, milestones only) · public/officer note added/changed/removed ·
  rank renamed · name changed (including "left, renamed, rejoined") · back after N days inactive ·
  offline N months, kick recommended · guild renamed.
- Event-log entries are merged in with their approximate dates, so the first install back-fills recent history.
- Log window: filter by type, search, delete lines, clear. Options: show at login, or only when there are new entries.
- Scan on `GUILD_ROSTER_UPDATE` plus a configurable interval; `/gmru scan` forces one.

### Phase 2 — Member card + roster window
- Card opens on mouseover of a name in Blizzard's guild roster (hooked, not replaced); click to pin it, Esc to release.
- Card shows: level, rank, zone, status (online/AFK/busy/offline), last online, join date and promotion date (editable),
  membership history (joined/left/rejoined dates), rank history, public and officer notes (editable when your rank
  allows, with character count), a 150-character addon-only custom note, and a group-invite button.
- Per-member alerts: tell me when this person comes online / goes offline / returns from inactivity.
- Our own roster window (`/gmru roster`): sort by any column, search names and notes, show offline.

### Phase 3 — Alts, mains, and data cleanup
- Set main / add alt / remove alt. Card and roster show the group. "Last online" and inactivity use the most recent alt.
- **Main tag in chat** (for example `Bob (main: Robert)`) in guild/party/raid/whisper chat, colour and format configurable.
  *Needs an in-game check: chat messages can be secret during chat lockdown on Forever.*
- **Audit window**: who's missing a join date, promotion date, or main/alt setting. Sortable, with "set the rest to unknown".
  Shows the number of mains and accounts.
- **Join date in notes**: on join, write the date into the public or officer note (date format configurable).
- **Join date tool**: read existing dates from notes in common formats, compare them with our saved dates, and fix either side.
- Copy one join date across a whole alt group.

### Phase 4 — Sync between addon users
- Synced: join dates, promotion dates, alt/main links, ban list, custom notes, birthdays. Live updates to open windows.
- The log isn't synced (each person's log is their own, same as GRM).
- Separate minimum rank for: general data, ban list, custom notes. Newest timestamped edit wins, so someone returning
  after a year can't overwrite newer data.
- Sync users window: who's running it, version, "rank too low" / "outdated". Manual `/gmru sync`.
- Guild-wide settings set by the guild leader (sync ranks, note date format). GRM stores these in the guild info text,
  but `GetInfoText` is restricted on Forever, so the leader's settings are sent over sync instead and accepted only from
  the leader's rank.
- Messages are chunked and throttled so nobody gets disconnected.

### Phase 5 — Officer tools
- **Ban list**: ban from the card (optionally the whole alt group), or add someone by name; reason and date;
  warning if a banned player rejoins; synced.
- **Kick / promote / demote tool**: rules such as offline more than N months, in rank more than N days, level reached,
  and "move alts to the main's rank". A safe list keeps chosen people out of the rules, with an optional expiry.
  Alert when someone who matches a rule comes online.
  *GRM can't call kick/promote directly (Blizzard blocked addons from doing that), so it builds macros. We'd use
  a button that runs `/gremove`, `/gpromote` or `/gdemote` for one person per click. This needs an in-game go/no-go
  test before the phase starts.*
- **Anniversaries and birthdays**: announced N days ahead, at login. GRM can also add them to the guild calendar, but
  `C_Calendar.AddEvent` is restricted on Forever, so we only announce.
- **!note**: a member types `!note text` in guild chat and an officer's addon sets their public note (31 characters).
  *Needs the same chat-lockdown check as the main tag.*

### Phase 5b — Group info (GRM's separate "Group Info" module, built in here)
- In a party or raid: which members are guildies, and which are **former** guildies (when they left, whether they're banned,
  whether they renamed, which of their alts are still in the guild).
- Optional marker on party/raid frames when a member is close enough to trade.

### Phase 6 — Polish and release
- Options page (Settings API), minimap button and addon compartment entry.
- Export as delimited text (copy box, ready for Excel or Google Sheets): members, former members, log.
- Backups: save and restore points for this guild's data; reset guild data / reset everything.
- Localization scaffold, README, CHANGELOG, CurseForge page, `.pkgmeta`.

### Left out
- Hardcore death tracking (Hardcore realms only).
- GRM's web apps and other addons' compatibility modules.
- "Left the server" detection (GRM has no reliable way to tell on a single-realm setup either).

## About GRM's code
GRM (R1.99423 and Group Info R1.66, downloaded to the Desktop) is **all rights reserved**: no derivative works or
redistribution without the author's permission. We use it only as a list of features to match. No code, text,
images or the "Guild Roster Manager"/GRM name gets copied. Our code is written from scratch against Forever's API.

## Conventions (same as the other Forever addons)
- Never write Blizzard globals. Hook frame instances with `HookScript`/`hooksecurefunc`; don't replace them.
- Check `issecretvalue` before storing, comparing, or sending any value from the API.
- Test logic offline with `lupa` mocks (roster diff, event-log merge, sync merge); the user tests in game.
- The README says honestly what hasn't been tested in game yet.

## Open questions for the guild
1. Which GRM features matter most to you? Phases 1–2 are the core; the order of 3–5b can change.
2. Officer sync: officers only, or everyone running the addon (read-only for non-officers)?
3. Writing the join date into notes: public note, officer note, or off?
4. Is there a second person available to help test sync (Phase 4)?
