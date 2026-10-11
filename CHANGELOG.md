# Changelog

## 2.14.0

- Clicking a note (or "Blizzard's guild window") opens Blizzard's guild window again; 2.13.0 broke it.
- **Save & reload** (was "Sync now") asks before reloading your UI and waits until you're out of combat.
- The sidebar's **Character** always opens your own character, not whoever you last looked at.
- Dialogs: one OK when there's nothing to confirm (Leave as Guild Master), and Disband stays greyed until you type DISBAND; pressing Enter where a click is needed says so.
- The guild calendar bar shows a plain message instead of a Lua error if something goes wrong.
- Hide Olympus's /who search uses the game's class names (every class, in your client's language).
- Reading reputations no longer triggers another read of itself.
- The CurseForge page describes what the addon does now.

## 2.13.0

### Fixes: guild officer tools work again
- Forever blocks addons from changing ranks, removing members, making a new leader, leaving or disbanding, and from changing notes, the message of the day and guild info ("blocked from an action only available to the Blizzard UI"). Those buttons now go through Blizzard's own secure guild commands (/gpromote, /gdemote, /gremove, /gleader, /gquit, /gdisband) on your click, exactly as if you typed them.
- **Promote** and **Demote** move one rank per click; the buttons name the rank they move to, and stay in place greyed out (with the reason on hover) when that move isn't possible. Profile is always on the member panel too, greyed out for members without the addon. The panel's buttons sit in fixed pairs (Whisper/Invite, Promote/Demote, Profile/Make leader), and Invite greys out for offline members instead of disappearing. In the right-click menu, "Change rank…" opens the member panel.
- Notes, the message of the day and guild information open **Blizzard's guild window**, where the game allows the edit; the Perpetua window steps aside while it's open.
- These need you out of combat (the game won't move its secure buttons in combat).

### More fixes from a review before release
- "Change rank…" in the right-click menu no longer errors.
- Buffs, food and flasks no longer make your profile re-send to the whole guild (in a raid that was constant traffic); new profiles are also held back during combat and in raid instances and go out afterwards.
- Guild sync waits out boss fights (when the game pauses addon messages) instead of dropping loot lines and profile pieces.
- A loading screen can't wipe your gear or professions from your profile.
- Promote twice in a row without moving the mouse; the hidden secure button is put away when combat starts or its window closes, so a stray click can't run an old command.
- Escape closes just the dialog or form you're in, not the whole Perpetua window.
- Officer-only things (posting the calendar) now go by officer rank: "Raid Leader", "Quartermaster" or "Loot Master" ranks no longer count.
- A calendar stamped in the future can't block newer ones; nothing received in the first moments after login lands in a stray "No guild" list.
- Profiles you already have aren't unpacked again when someone else asks for them; the window redraws less when nothing changed; a gear change isn't pushed back by looting.
- One guildmate's malformed profile can't blank the Guild, Attunements or Calendar pages.
- Setup stops greeting you as new once you've opened any other page.

### Lighter and faster
- Guildmates' full profiles and recipes are now kept compressed and only unpacked when you open their Character page or the Crafters page; the lists use a small summary. About a quarter of the memory per guildmate (32 KB down to 8 KB in testing), which adds up in a big guild. Saved data from older versions is converted once at login.
- Your own profile only re-reads what changed: a bag update checks attunement items, a talent change reads talents, and so on, instead of everything (talents and reputations were the slow parts). An unchanged profile isn't re-hashed or re-sent.
- Reading reputations no longer leaves your collapsed reputation headers expanded.
- Profession windows are read once things settle, and only fetch details for recipes it hasn't seen, instead of re-reading everything after every craft.
- Hide Olympus only listens for nameplates, mouseover and target while it's switched on, and does less work per chat line.
- The guild sync send loop only runs while there's something to send (it ticked five times a second all session).
- Loot history older than 60 days and /rolls older than 14 days are dropped (the Perpetua app has uploaded them to the site).
- Smaller allocations in hot helpers, so less garbage collection.

### New
- **Guild Control** button (Guild page and Guild Info, for officers): Blizzard's window for rank names and permissions, adding and removing ranks, and guild bank tabs.
- **Blizzard UI** button on the Guild page opens Blizzard's guild window.

## 2.12.0

### New: schedule raids in game (officers)
- Officers get **New raid** on the Calendar tab: raid, title, day, start time, length, players, weekly repeat and notes. The raid goes to perpetua.gg with guild sync (Create & sync sends it straight away), then to Discord and everyone's Calendar tab. Until the site has it, it shows in the list as "(to the site)"; click it to drop it.
- The raid list now has Forever's raids first: Barrow Deeps, Hyjal Summit and Onyxia's Lair.

### New: raids in the guild calendar
- The site's raids can go into Blizzard's calendar as guild sign-up events, so everyone in the guild sees them, addon or not. Officers see a bar on the Calendar tab ("2 raids aren't on the guild calendar") with one button: each click adds the next raid, or takes off an event for a raid the site moved or cancelled. A raid already on the calendar (same title and time, whoever added it) isn't added twice.

## 2.11.1

### Fixes
- Long rank names (Guild Master) no longer run into the Spec column on the Guild page; the Rank column is wider, and a rank too long for it ends in "…".
- The members, online and with the addon numbers at the top of the Guild page line up.

## 2.11.0

### A new look
- The window now looks like perpetua.gg: the site's card frame with its gold corners, a top bar with the crest and motto, the sidebar grouped into Guild, You and Reference (with a count of this week's raids on Calendar), and sync status, Hide Olympus and Sync now together in one card.
- Page titles sit over the site's gold rule; the Guild page shows members, online and with the addon as big numbers.
- The Guild list marks each player with their class colour and shows ranks as tags (gold for officers).
- The Character page opens with a header card in the class colour: the crest, the name large with the surname, race, spec and class under it, and Level, item level, role and rank as badges. Professions and reputation are progress bars.
- Shaman and Warlock names use the site's lighter blue and purple, which read better on navy.

### New: one Guild list
- The **Guild** page lists everyone in the guild, with or without the addon: level, rank, spec, item level, professions, note and when they were last online (online first). Hover a name for their zone, notes, raid attunements, how fresh their profile is and their alts. Search, show or hide offline members, see alts separately, and sort any column.
- Click a member for their panel: rank (pick a new one if your rank allows), public and officer notes (click to edit), and Whisper, Group invite, Profile, Make leader and Remove. Right-click a member for the same in a menu.
- **Invite** adds someone to the guild by name.
- New **Guild Info** page: the message of the day and guild information (with Edit if your rank can change them), the guild log, and Leave guild (and Disband for the Guild Master).

### Try it: the new guild window
- Switch on **New guild window** at the top of the Perpetua window (or in Options > AddOns > Perpetua, or `/ppta guildui`) and the guild key (J) and the guild button on the menu bar open Perpetua instead of Blizzard's guild window. Hold **Shift** for Blizzard's. It's off until you turn it on.
- The officer tools come with it: the member panel and right-click menu, Invite and the Guild Info page. With it off, the Guild list works as before (click a name for their profile).

### Fixes
- Search box hints no longer run past the edge of the box.

## 2.10.0

### New: recipe totals
- Track two or more recipes and the **Profession** list in the objective tracker gets one more block at the bottom, under a thin gold line, **Totals: All Tracked Recipes**: every reagent they need between them, with how many you have, ticked off like the rest once you've got enough.

### Levels on perpetua.gg stay current
- The addon now saves the guild roster too (everyone's level and class, and when they were last online), and the Perpetua app takes it to the site. A character who levelled while nobody else with the addon was on now shows their new level on the site anyway, and in the addon window too.

## 2.9.1

### Fixes
- Hide Olympus didn't hide any chat in 2.9.0: it learned Olympus players but its chat filters never took effect. They're now set up at login through the current chat API, as other addons on this client do.

### Changes
- The Hide Olympus page shows running totals under the number of Olympus players known: messages hidden, invites turned down and trades cancelled. They're kept between sessions.
- Olympus players are saved in a much smaller form, and the list is capped at 5,000: past that, the ones seen longest ago make room.
- `/ppta olympus debug` shows what the chat filters have seen since login.

## 2.9.0

### New: Hide Olympus
- A **Hide Olympus** switch above **Sync now** hides players in any guild with "Olympus" in its name. It starts off.
- Click the words **Hide Olympus** to choose what it does. All of these are on until you untick them:
  - Hide their chat: say, yell, emotes, every channel, and party and raid chat.
    - Hide any chat that says "Olympus", from anyone (like trade asking for an Olympus layer).
  - Hide their whispers, plus any whisper that says "Olympus", from anyone.
  - Turn down their guild invites, and Olympus guild charters.
  - Turn down their group invites.
  - Cancel trades with them.
  - Turn down their duels.
- Optionally, a line in chat whenever an invite, trade or duel is turned away.
- Nothing goes on your ignore list and they can't tell. Switch it off and everything shows again.
- The game only shows someone's guild when you see them (nameplates, mouseover, target, your group, trades, invites and /who), so the addon remembers each Olympus player it spots. A whisper from an Olympus player standing nearby is hidden too, and so is anyone who whispers you about Olympus, from then on. Other chat from someone it hasn't seen yet still shows. **Look them up** on the Hide Olympus page runs a /who for Olympus players, 50 per click.
- `/ppta olympus` opens the page; `/ppta olympus on` and `/ppta olympus off` flip the switch.

### Update notice
- When a guildmate has a newer version of the addon, you'll see **Update available** in the window's sidebar and in the minimap button's tooltip, plus one line in chat per new version.
- The addon's version now shows under **Sync now**.

### Fixes
- Update notices never showed: versions 2.8.2 to 2.8.4 told guildmates they were 2.8.1. The addon now reads its version from its own files.

## 2.8.4

### Fixes
- Joining the guild while logged in now shares your character with guildmates straight away. Before, the addon could save your character before the game had the guild's name, file it in the wrong place, and then quietly send nothing until you restarted the game.

## 2.8.3

### Fixes
- The **Setup** page's three cards (What the addon does, Why link your characters, How to link) now always show their full text. They were coming out too short, so the text ran over the next card and past the bottom of the window. The text is also a little shorter so all three fit.
- The Setup page no longer mentions the guild forums, which are switched off for now.

## 2.8.2

### Fixes
- The **Welcome** page's three cards (Who we are, We're recruiting, About this addon) now always show their full text. They were coming out too short, so the text ran over the next card.

## 2.8.1

### Changes
- The **Forums** tab is switched off for now, along with `/ppta forums`. The addon no longer passes forum posts around the guild. The forums will come back when they open to members on perpetua.gg.

### Fixes
- The **Welcome** page (on characters outside the guild) no longer runs off the bottom of the window. The cards are shorter, and if they ever don't fit they scroll instead.

## 2.8.0

### Members only
- The addon now only works on characters in **<Perpetua>**. On any other character it opens a **Welcome** page instead of the usual tabs:
  - **Who we are:** an Alliance guild on the PvP ruleset for WoW Classic: Forever, and a community that has been gaming together for over eight years.
  - **We're recruiting:** how to apply, with the address for perpetua.gg/apply ready to copy.
  - **About this addon:** what it does for members, and why it needs you to be in the guild.
  - A status box showing which guild the character is in. Horde characters are told they'll need an Alliance character to join.
- Outside the guild the addon sends nothing, listens to nothing and records no loot or rolls.
- Characters outside the guild get one line in chat at login about the guild and `/ppta`.
- Joining the guild unlocks everything straight away, even with the window open, and takes new members to the Setup page.

### Fixes
- Removed a leftover test file from the download. The addon never loaded it.
