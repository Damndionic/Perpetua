# Perpetua

**Your guild's gear, talents, professions, attunements and raid loot, shared automatically between everyone who has the addon.**

Perpetua is the guild companion for **<Perpetua>**, an Alliance guild on the PvP ruleset for WoW Classic: Forever. Log in, and within a few seconds you can see what every guildmate with the addon is wearing, how they've specced, what they can craft and which raids they're attuned to. They don't need to be online.

> **Members only.** The addon only works on characters in <Perpetua>. On any other character it shows a short welcome page about the guild and how to apply, and stays silent. Join the guild and it unlocks by itself. **We're recruiting:** apply at [perpetua.gg](https://perpetua.gg/apply).

Type **/ppta** (or **/perpetua**) or click the crest on your minimap.

---

## What you get

**Guild**
Everyone in the guild, with or without the addon: level, rank, spec, item level, professions, note and when they were last online. Hover a name for their zone, notes, raid attunements and alts; search, show or hide offline members, see alts separately, and sort any column.

**Guild window** *(optional: the switch at the top of the window, or `/ppta guildui`)*
Makes the guild key (J) and the guild button open Perpetua instead of Blizzard's guild window (hold Shift for Blizzard's). Click a member for their panel: whisper, invite, promote and demote one rank at a time, view their profile, make leader, remove. Notes, the message of the day and guild info open Blizzard's guild window, and **Guild Control** opens Blizzard's rank and permission settings: the game only lets its own UI change those, so the addon hands you straight to it. Guild actions work out of combat.

**Guild Chat**
The guild chat log from Blizzard's guild window, history included, with an Officer tab for officers. Click a name to whisper, right-click for the member menu, and type below to send.

**Guild Info**
The message of the day, the guild information and the guild event log.

**Character**
Any guildmate's full profile: equipped gear with item icons, talents and spec, professions and skill levels, attunements and reputations.

**Attunements**
A guild-wide checklist for Onyxia, Molten Core, Blackwing Lair and Naxxramas. It also covers the dungeon keys: UBRS, Scholomance, Stratholme, Blackrock Depths and Dire Maul, plus Molten Core runes.

**Professions**
Who can make what, one profession at a time. Open your profession window once and your recipes are shared. Pick a profession to see its recipes and the guildmates who have it, by skill and with who's online; click a crafter for only their recipes, or a recipe to whisper someone who can make it.

**Loot**
Epic and better drops in raids, the /rolls for them and how each was decided, recorded by everyone with the addon and merged into one history. **How loot works** has the guild's loot rules. The loot master gets a small window for each epic: post the main-spec / off-spec roll and award it, or send a high-value item to the officers' loot council.

**Calendar** *(raids from perpetua.gg)*
Upcoming raids with in-game sign-ups (coming, tentative, can't make it, and every role you can take: tank, off tank, healer, DPS). Officers can schedule a raid from the addon with **New raid**, and put the site's raids into Blizzard's in-game calendar as guild events with one click each, so everyone sees them, addon or not.

**Recipe totals**
With two or more recipes tracked, the objective tracker gets one more block adding up the reagents they need between them.

---

## How it works

- **Guild chat only.** Everything travels over the hidden guild addon channel, which only guild members can hear. The addon never connects to the internet, and it doesn't send or listen to anything at all on characters outside <Perpetua>.
- **You only ever send your own character.** A profile is only accepted if the name inside it matches the player who sent it, so nobody can post data under someone else's name.
- **Light on traffic.** Each character sends a short hello when you log in and every 10 minutes. Full profiles are only sent when something has changed (buffs and food don't count) and someone asks for it, are held back during combat and in raid instances, and are throttled the same way ChatThrottleLib is.
- **Light on memory.** Guildmates' full profiles are kept compressed and only unpacked when you open their page, and former members' are let go 30 days after they leave.
- **Never shared:** gold, bags and bank contents, chat and whispers, or anything about your Battle.net account.

---

## Commands

| Command | What it does |
|---|---|
| `/ppta` | Open or close the window |
| `/ppta me` | Your character |
| `/ppta attune` | Attunements |
| `/ppta professions` | Who can make what (`/ppta crafters` works too) |
| `/ppta loot` | Loot and roll history |
| `/ppta loot rules` | How loot works |
| `/ppta raids` | The raid calendar |
| `/ppta guild` | The guild roster |
| `/ppta guildui` | Turn the guild window on or off (`on` / `off`) |
| `/ppta setup` | Link your characters to the guild website |
| `/ppta link CODE` | Save a link code from perpetua.gg |
| `/ppta export` | Your export for the site |
| `/ppta sync` | Save for the Perpetua app (reloads your UI) |
| `/ppta minimap` | Hide or show the minimap button |
| `/ppta scale 90` | Window size in percent, 70 to 150 (Ctrl + mouse wheel on the window, or Options > AddOns > Perpetua) |
| `/ppta help` | List all commands |

`/perpetua` and `/perp` work too.

---

## For Perpetua members

Link your characters to your Discord account on [perpetua.gg](https://perpetua.gg). Get a code from your member page, then paste it into the addon's Setup page or type `/ppta link CODE`. Your gear, talents, professions and attunements then appear on your profile page, and you can sign up for raids from inside the game.

---

## Notes

- Made for WoW Classic: Forever (Interface 16001). It uses Forever's First + Surname character names.
- Keep it up to date: very old versions may not be able to share with newer ones. When a guildmate has a newer version, the addon tells you once.
- Fonts: Cinzel and Cormorant Garamond, under the SIL Open Font License (license files included).
