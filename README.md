# Guild Masters R Us

A guild roster manager for **WoW: Forever**. It keeps a log of everything that changes in your guild,
remembers join dates and rank history, links alts to mains, keeps a ban list, helps officers with
kicks and promotions, and shares all of that with guildmates who also run it.

**Status: 0.9.0 beta.** Every feature is built and passes offline tests, but **none of it has been run
in the game yet**. Please report anything odd (see [docs/BETA_TESTING.md](docs/BETA_TESTING.md)).

## Install
1. Copy the `GuildMastersRus` folder into your WoW: Forever `Interface\AddOns\` folder.
   (`tests/` and `docs/` can be left out.)
2. Enable **Guild Masters R Us** on the character select screen.
3. Log in on a character in your guild. Type `/gmru` to open the window.

The first time, it records everyone currently in the guild and fills in what it can from the
guild's event log (recent joins, promotions, who invited whom). From then on it logs every change.

## What it does

**Log** (`/gmru log`): joins and rejoins (who invited them, how many times they've been in the guild
before, how long they were gone), leaves vs. kicks (and who kicked), promotions and demotions (and by whom),
level-ups, public/officer note changes, name changes, rank renames, members back from a long absence,
kick recommendations for long-inactive members, and a warning if a **banned** player joins. Things that
happened while you were offline are filled in from the guild's event log. Filter, search, delete lines,
and choose which changes also print in chat.

**Member card**: hover a name in the guild roster (or in our Roster tab) to see it; click to keep it open.
Join date, promotion date, membership and rank history, time in rank, last online, who invited them,
alts, birthday, public and officer notes (editable if your rank allows), a 150-character custom note
only addon users see, alerts for when they come online/go offline/return, and Invite/Whisper/Ban buttons.
Right-clicking a guild member, a name in chat, or a party/raid member also offers **Member card**.

**Roster** (`/gmru roster`): sortable list of everyone, search names and notes, show/hide offline,
group alts under their mains.

**Audit** (`/gmru audit`): who's missing a join date, promotion date, or main/alt setting.
The **join date tool** reads dates already written in notes (most common formats), compares them with saved
dates, and can import them or write saved dates into notes.

**Alts and mains**: link alts on the card (start typing a name and pick it from the suggestions). Alts show their main's name in chat, for example `[Bobalt] (Bob): hi`.
Inactivity and kick rules count the whole alt group.

**Bans** (`/gmru bans`): ban from the card (optionally the whole alt group) or by name. You're warned if a banned
player rejoins or is in your group.

**Tools** (`/gmru tools`): kick inactive members, promote by time in rank and level, demote inactive members,
and move alts to their main's rank. Blizzard doesn't let addons do these directly, so the tool gives you one
button that runs `/gremove`, `/gpromote` or `/gdemote` for the next member each time you click it.
Members can be skipped for 30 days or always.

**Events** (`/gmru events`): upcoming guild anniversaries and birthdays, announced in your chat at login.
(Forever doesn't let addons add guild calendar events.)

**Group info** (`/gmru group`): who in your party or raid is a guildie, a former guildie (when they left,
whether they were kicked, renamed, which alts are still in the guild) or banned, with a trade-range dot.

**Sync** (`/gmru users`): join dates, promotion dates, alts, custom notes, birthdays and the ban list are shared
with guildmates running the addon. The newest edit wins, and only ranks you trust can send changes.
The guild master can set guild-wide sync ranks and the join-date note setting for everyone.

**Export** (`/gmru export`): members, former members, the log or the ban list as text for Excel or Google Sheets.
Restore points (one is saved automatically each week).

**`!note`** (off by default): when a member types `!note my text` in guild chat, an officer's addon sets their
public note for them.

## Commands
`/gmru` opens the window. `/gmru help` lists everything. Common ones:
`log`, `roster`, `audit`, `bans`, `tools`, `events`, `users`, `export`, `group`, `card <name>`, `scan`, `sync`,
`options`, `probe` (diagnostics for bug reports).

## Good to know
- The addon only sees changes while someone running it is online. The guild event log covers some gaps
  (it keeps roughly the last 100 entries), and sync covers most of the rest.
- Event-log times are approximate (the game only gives "how long ago"), so back-filled dates can be off by
  an hour for recent events and by days for older ones.
- Your log is your own and isn't shared, the same as the rest of your settings.

## Development
Offline tests: `python tests/test_addon.py` (needs `pip install lupa`).
Plan and design notes: [docs/PLAN.md](docs/PLAN.md).
