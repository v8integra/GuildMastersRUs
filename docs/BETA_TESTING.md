# Guild Masters R Us — beta test checklist

Thanks for testing! This build has only been tested offline, so some things may not work in the game.
The guild master is the best tester, because several features need guild master or officer permissions.

Tick what works, and note what doesn't. For anything that goes wrong, a screenshot plus the
SavedVariables file (step 0) helps the most.

## 0. Before anything else (2 minutes)
1. Install: copy the `GuildMastersRus` folder into your WoW: Forever `Interface\AddOns\` folder. Enable it.
2. Turn on Lua error messages so problems are visible: type `/console scriptErrors 1`.
3. Log in, wait 10 seconds, then type `/gmru probe`. A report prints in chat. **Screenshot it.**
4. Type `/reload`. Then send the file
   `WTF\Account\<YOUR ACCOUNT>\SavedVariables\GuildMastersRus.lua`.
   (It contains the guild's roster data and log. It stays private; only share it with the developer.)

## 1. First look
- [ ] `/gmru` opens the window. Chat said "Started tracking N members" (in the Log tab).
- [ ] The Roster tab lists everyone; online members show "Online"; others show how long ago they were on.
- [ ] Some join dates were filled in from the guild's event log (Roster tab, Joined column).
- [ ] The minimap button opens the window (right-click opens Options). Options are under Esc > Options > AddOns.

## 2. Guild roster and member card
- [ ] Open the guild window (J). Hovering a member shows the card beside it. Moving away hides it.
- [ ] Clicking a member keeps the card open. Esc closes it.
- [ ] Right-click a member in the guild roster: there's a **Member card** option at the bottom.
- [ ] On the card: **Edit** the join date (try `2024-05-06`). It shows on the Roster tab.
- [ ] Type in the public note box and press Enter. The note changes in Blizzard's roster too.
- [ ] Same for the officer note.
- [ ] Custom note: type, click **Save**.
- [ ] Set a birthday (`07/23`).

## 3. Change log (needs things to happen)
Do any of these and check the Log tab (and chat):
- [ ] Invite someone → "joined the guild (invited by …)".
- [ ] Promote or demote someone → "promoted from X to Y by …".
- [ ] Change someone's public note → logged.
- [ ] Someone leaves → "left the guild". Someone is removed → "was kicked by …".
- [ ] Log out and back in after changes happened while you were offline → they appear (some marked "from the guild's event log").

## 4. Alts
- [ ] On a card, click **Add** and start typing an alt's name: matching guild members appear under the box
  (Up/Down to pick, Tab or Enter to take one, or click it). Typing part of a last name works too. The Roster tab shows "alt of …"; tick "Group alts with mains".
- [ ] When the alt talks in guild chat, their main's name shows after theirs: `[Alt] (Main): hi`.

## 5. Bans
- [ ] Ban someone from their card (or Bans tab > Add a ban). It shows in the Bans tab.
- [ ] Remove the ban.

## 6. Tools (guild master / officers) — important
Blizzard doesn't let addons kick or promote directly. The Tools tab's big button runs the
`/gpromote`, `/gdemote` or `/gremove` command for you. **Please test with someone who agreed to it:**
- [ ] Promote tab: make a rule (pick a rank, days in rank `0`, Save rule). The member shows in the list.
  Click the big **Promote …** button once. Did the promotion happen?
  (Forever names have spaces, so the button sends the name as the game shows it, like `/gpromote Ominegod Frostburn`.
  If nothing happens, try typing that same command in chat and tell us whether it worked.)
- [ ] Put them back with Blizzard's guild window (right-click > Demote). The Log tab shows both changes.
- [ ] **Kick** only if you really mean to remove someone.
- [ ] Enter combat with the Tools tab open: the button disappears and comes back after combat.

## 7. Sync (needs two people with the addon)
- [ ] Both type `/gmru users` (Sync tab): you see each other.
- [ ] One person edits a join date or links an alt; it appears for the other within a few seconds.
- [ ] Guild master: on the Sync tab, pick the guild-wide settings and click **Send to the guild**.
  The other person's Sync tab shows "last set by …".

## 8. Other
- [ ] Join a party with a former guildie (if you know one) → chat warns you. `/gmru group` lists the group.
- [ ] Events tab lists anniversaries (needs members whose join date is about a year ago or more).
- [ ] Export tab: Members → Make export → Ctrl+C → paste into a spreadsheet.
- [ ] `!note` (Options > Roster and chat): switch it on; have a member type `!note hello` in guild chat.

## Reporting
For each problem: what you did, what happened, a screenshot, and any red Lua error text.
