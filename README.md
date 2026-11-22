# Prepped

**Prepped** is a modular, "set-it-and-forget-it" reminder addon for **WoW Forever** (interface `16001`). It helps you avoid common mistakes, like walking into a dungeon without water or pulling a boss without your pet, with clear, non-intrusive and highly configurable reminders that you can click to fix.

**Download:** [CurseForge](https://www.curseforge.com/wow/addons/prepped) (also in WowUp) · [GitHub releases](https://github.com/Alwindh/Prepped/releases/latest) · **Bugs and ideas:** [GitHub issues](https://github.com/Alwindh/Prepped/issues)

### At a glance
- **Reagents and supplies**: water, food, ammo, bandages, Soul Shards, candles, Rebirth seeds, Symbols, Runes, Ankhs, poisons, bag space and more, for the spells you actually know. With Forever's Reagent Economy perk (or any spell that turns out to work without its reagent), those reagents are hidden automatically.
- **Your own buffs**: Mark of the Wild, Fortitude, Inner Fire, Arcane Intellect, armors, Aspects, Auras, Blessings and shields, when they're missing or about to run out.
- **Things you leave behind**: your Hearthstone or totems in the bank, no Healthstone or Soulstone, no pet or demon out, no poison or imbue on your weapon.
- **Gear**: repairs in town, and a warning anywhere when an item is about to break.
- **Groups**: your supply reminders on screen when you join a group, during a ready check and at any vendor; one line in party chat about what you're low on; warnings when your pet's taunt is on autocast or Righteous Fury is on while you're not tanking.
- **Leveling in Forever**: keep your food buff (Well Fed, +5% kill XP) and Camp Benefits up; spend your talent and Legacy points.
- **Click to fix**: left-click a reminder to cast the missing buff, apply a poison, summon your demon, eat buff food and more. Right-click to snooze it.
- **In your language**: English, German, French and Spanish, with spell and item names straight from your game client.

Reminders stay out of your way: supply reminders show up in cities, inns and at vendors, where you can restock; buff reminders while you're out adventuring (not while mounted). Snooze what you don't need right now, and an optional sound tells you when something new shows up.

---

## The reminder bars

- **Icons**: each reminder shows the spell or item it's about (**Show Icons** in Appearance).
- **Click to fix** (out of combat): left-click casts or uses what the reminder asks for. Buffs with several choices (Auras, Aspects, Blessings, mage armors, shields, demons) use the one you had up or summoned last; Ice Armor takes over from Frost Armor once you learn it. The tooltip says what a click does before you click. Only a reminder's text and icon catch clicks, so the world behind the rest of the bar stays clickable. **Clickable Reminders** in Appearance turns this off. You can bind a key to the first reminder with a macro: `/click PreppedReminderButton1`.
- **Right-click menu**: snooze a reminder for 15 minutes, an hour or until your next login, turn it off, or open its settings. Snoozes are kept across `/reload` and logouts.
- **Move them**: `/prepped move`, **Move Reminders** in Appearance, or Blizzard's Edit Mode. Drag the sample reminders anywhere, nudge them with the arrow keys (Shift: 10 pixels), then right-click or press Escape. **Reset Position** puts them back. **Grow Upwards** stacks new reminders above the first one.
- **Live preview**: changing the font, colors or width shows sample reminders for a few seconds, above the options window.
- **Combat-safe**: in combat the bars keep updating, but nothing is clickable and nothing moves, so Prepped never gets in the way of Blizzard's combat restrictions.

---

## Configuration and Options

Prepped's options live in the game's own settings: **Options → AddOns → Prepped**. Open them with `/prepped`, from the AddOns menu on the minimap (its tooltip shows how many reminders are on screen), or from a reminder's right-click menu.

- **Prepped** (main page): master toggle, account-wide vs. per-character settings, welcome message, sound for new reminders; **Supplies** (water, food, bandages, repairs, gear about to break, bag space, Hearthstone); **Groups and Vendors**; **Leveling**; and **Reset All Settings**.
- **Appearance**: move reminders, reset position, grow upwards, show icons, clickable reminders, font size, minimum width, text color, background color and opacity.
- **One page per class** (Druid, Hunter, Mage, Paladin, Priest, Rogue, Shaman, Warlock, Warrior): every reminder can be switched on or off. Stock reminders have a slider for the amount to warn at; buff reminders have an extra **Warn when expiring** option with a time slider.

Settings are shared by all characters (**Account-wide**) unless you switch that off; then each character gets its own settings. Snoozes and remembered spells are always per character.

### Commands
- `/prepped`: options
- `/prepped move` (or `unlock` / `lock`): move the reminders
- `/prepped snooze [minutes]`: hide the reminders on screen for a while (default 30 minutes); `/prepped unsnooze` brings them back
- `/prepped debug`: what Prepped sees, for bug reports
- `/prepped help`: this list

---

## Available Reminders

### Universal (All Classes)
- **Buy Water**: While resting, warns mana users (also druids in Bear or Cat Form) with less water than your setting. Mages get their own reminder to conjure it.
- **Buy Food**: While resting, warns when you have less food than your setting (default: 20). Not for mages, who conjure their own.
- **Food and Water From Level**: the minimum level for both (default: 10).
- **Low on Bandages**: While resting, once you know First Aid, warns when you have fewer bandages than your setting (default: 10).
- **Repair Reminder**: While resting, warns when your gear's average durability is below your setting (default 70%), or when a single item is below the **Repair When One Item Is Below** setting (default 25%), so one worn-out weapon isn't hidden by the average.
- **Gear About to Break**: Anywhere, even in combat, warns when an equipped item is at 10% durability or lower (adjustable), or broken: broken gear gives no stats until it's repaired. Shows the item's name and icon.
- **Low Bag Space**: While resting, warns when you have fewer free bag slots than your setting (default: 4), so you can sell or bank before heading out. Quivers, ammo pouches, soul bags and the reagent bag don't count.
- **Missing Hearthstone**: Out of combat, warns when your Hearthstone isn't in your bags, for example after leaving it in the bank.
- **Missing Food Buff**: While leveling (from level 10), reminds you to keep a food buff (**Well Fed**) up when you carry food that gives one and you're not resting, not in combat and not mounted (or in Travel Form / Ghost Wolf). Without such food in your bags there's no reminder. In Forever, cooked food also gives +5% experience from kills. Off at max level or with experience turned off; optional early warning before it runs out. Click it to eat the food.
- **Missing Camp Benefits**: While leveling (from level 10), reminds you to get **Camp Benefits** (sit at a camp for a minute; it combines the buffs of the camp's objects and lasts an hour) when you're not resting, not in combat and not mounted. Optional early warning, by default 5 minutes before it runs out.
- **Unspent Talent Points**: Out of combat, reminds you when you have talent points left to spend, or talent changes you haven't confirmed with **Apply** yet. Click it to open your talents.
- **Unspent Legacy Points**: Out of combat, reminds you when you have Legacy points left to spend in the Legacy trees (Professions, Adventure, Progression).
- **Sound for New Reminders** (off by default): a short sound when a reminder appears. The same reminder stays silent for a while afterwards (default: 5 minutes), and there's never a sound in combat.

### Groups and Vendors
- **Check Supplies When Joining a Group**: When you join a party or raid, your supply reminders (reagents, ammo, repairs and so on) show for a minute even outside cities and inns, so you can restock before you head in. Only you see them, and they wait while you're in combat.
- **Check Supplies on Ready Check**: The same during a ready check, until it's over.
- **Check Supplies at Vendors**: While you talk to any vendor, for example at a camp, your supply reminders show even outside cities and inns.
- **Tell My Group**: When you join a party, Prepped posts one line in group chat about what you're low on, for example `[Prepped] you're at 47% durability, remember to repair soon.` It names up to three things, posts once per group, waits until you're out of combat, and only mentions durability below 50% (adjustable). The line is in your client's language.
- **Also Post in Raids** (off by default): also post that line when you join a raid, which otherwise gets no line from everyone who uses Prepped.

### Druid
- **Missing Mark of the Wild**: Alerts you when neither Mark of the Wild nor Gift of the Wild is on you (not while resting, mounted or in Travel/Aquatic/Flight Form). Click it to cast Mark of the Wild on yourself.
- **Reagent Tracking**: Warnings while **resting** for the reagent of your highest rank:
  - **Rebirth seeds** (Maple, Stranglethorn, Ashwood, Hornbeam or Ironwood Seeds)
  - **Gift of the Wild** (Wild Berries or Wild Thornroot)
- **"Warn when expiring"**: Optional early warning before Mark of the Wild runs out.

### Hunter
- **No Ammo Equipped**: Alerts you when you have a ranged weapon equipped but no ammo.
- **Critical Ammo**: A "red alert" while you're out adventuring when your ammo drops below a critical point (e.g., 200).
- **Low Ammo**: A reminder to stock up while **resting** if you have less than your desired stock (e.g., 1000).
- **Missing Aspect**: Alerts you if you don't have an Aspect active. Click it to cast the Aspect you had up last (Cheetah and Pack, which are for travelling, don't count).
- **Missing Pet**: Warns you if your pet isn't out (only if you know *Tame Beast*). Click it to call your pet, or revive it if it's dead.
- **Unhappy Pet**: Reminds you to feed your pet when it isn't happy (out of combat). Click it to feed your pet food from your bags that it eats.
- **Growl on Autocast in Groups**: In a dungeon or raid group, warns when your pet's Growl is on autocast, so your pet doesn't take threat from the tank. Click it to turn autocast off.
- **Low Pet Food**: Alerts you while **resting** if you have fewer than your configured amount of food items in your bags that your pet can actually eat.

### Mage
- **Missing Arcane Intellect**: Alerts you when Arcane Intellect (or Arcane Brilliance) isn't on you. Click it to cast Arcane Intellect on yourself.
- **Missing Armor Buff**: Reminds you to keep Frost, Ice or Mage Armor up. Click it to cast the armor you had up last.
- **Missing Mana Gem**: Alerts you to conjure a Mana Gem if you have the spell but no gem in your bags. Click it to conjure the best one you know.
- **Conjure Water / Conjure Food**: Out of combat, anywhere, reminds you to conjure more when you're low (defaults: 20 water, 10 food). Click to conjure.
- **Reagent Tracking**: Optional warnings while **resting** if you are low on:
  - **Arcane Powder** (for Brilliance)
  - **Rune of Teleportation**
  - **Rune of Portals**

### Paladin
- **Missing Aura**: Ensures you always have a Paladin Aura active. Click it to cast the Aura you had up last.
- **Missing Blessing**: Reminds you to keep a Blessing (Might, Wisdom or Kings, or a Greater Blessing) on yourself while adventuring. Click it to cast the Blessing you had up last on yourself.
- **Missing Righteous Fury**: Alerts you to activate Righteous Fury if you are in a group, have a shield equipped, and are Protection spec.
- **Righteous Fury While Not Tanking**: In a dungeon or raid group, warns when Righteous Fury is on while your talents aren't Protection, so you don't take threat from the tank. Click it to turn Righteous Fury off.
- **Reagent Tracking**: Monitors your stock of **Symbol of Kings** and **Symbol of Divinity** while resting.
- **"Warn when expiring"**: Optional early warnings for Blessings and Righteous Fury.

### Priest
- **Missing Power Word: Fortitude**: Alerts you when Fortitude (or Prayer of Fortitude) is missing while adventuring. Click it to cast Fortitude on yourself.
- **Missing Inner Fire**: Alerts you when Inner Fire is missing while adventuring.
- **Low Candles**: Reminds you while **resting** to restock the candles your Prayer spells use: **Sacred Candles** once you know Prayer of Fortitude rank 2, Prayer of Spirit or Prayer of Shadow Protection, **Holy Candles** before that.
- **"Warn when expiring"**: Optional early warnings for Fortitude and Inner Fire.

### Rogue
- **No Ammo/Thrown Equipped**: Alerts you if you have a ranged weapon equipped but no ammo or thrown weapon charges.
- **Critical Ammo**: A survival alert if your ammo/thrown count drops below a dangerous level.
- **Low Ammo**: A resting reminder to restock before your next adventure.
- **Missing Weapon Poison**: Alerts if either weapon is missing poison (only if you have the *Poisons* skill and poison in bags), and says which hand. A sharpening stone on the weapon doesn't count as a poison. Click it to apply a poison from your bags: Instant Poison on the main hand, Deadly Poison on the off hand, else whatever you carry.
- **Low Flash Powder**: Reminds you to stock up on Flash Powder while **resting** if you know *Vanish* (default: 10).
- **Low Blinding Powder**: Reminds you to make or buy Blinding Powder while **resting** if you know *Blind* (default: 5).
- **Low Poison Stock**: Warns you while **resting** if your total poison count is low (default: 20, checks all poison types).
- **"Warn when expiring"**: Optional early warning for weapon poisons (default: 60 seconds).
- *Thrown weapons with durability never run out in Forever, so they don't trigger ammo reminders.*

### Shaman
- **Missing Totem Items**: Totems in Forever still need their element's totem item in your bags. Prepped warns you (out of combat) when the **Earth, Fire, Water or Air Totem** for totems you know is missing, for example after leaving it in the bank.
- **Missing Shield**: Alerts if Lightning Shield (or Water Shield) is missing (not while mounted or in Ghost Wolf). Click it to cast the shield you had up last. Water Shield is new in Forever and is only recognised on English clients until its spell ID is known.
- **Weapon Imbues**: Tracks your Rockbiter, Flametongue, Frostbrand or Windfury imbue. Click it to cast Windfury Weapon, else Rockbiter, Flametongue or Frostbrand, the first you know.
  - *Note: Only triggers for Enhancement/Leveling Shamans and is dual-wield aware. Sharpening stones and oils don't count as an imbue.*
- **Reagent Tracking**: Warnings while **resting** for (each only once you know the spell that uses it):
  - **Ankhs** (Reincarnation)
  - **Fish Oil** (Water Walking)
  - **Fish Scales** (Water Breathing)
- **"Warn when expiring"**: Reminds you to re-apply shields and weapon imbues *before* they expire.

### Warlock
- **Missing Demon Armor**: Alerts you when Demon Armor (or Demon Skin before you learn it) is missing. Click it to cast it.
- **Missing Demon**: Warns you when no demon is summoned (not while a *Demonic Sacrifice* buff is on you). Click it to summon the demon you summoned last (the Voidwalker until then).
- **Voidwalker Taunts on Autocast in Groups**: In a dungeon or raid group, warns when your Voidwalker's Torment or Suffering is on autocast. Click it to turn autocast off.
- **Missing Weapon Stone**: In Forever, Firestone and Spellstone are weapon imbues. Once you can create one, Prepped reminds you to keep one on your main hand (a wizard oil on the same weapon doesn't count). Click it to apply a stone from your bags, or create one.
- **Missing Healthstone / Soulstone**: Reminds you to create them when you have a Soul Shard (out of combat, not while resting). No Soulstone reminder while you are soulstoned yourself. Click to create the best one you know.
- **Low Soul Shards**: Warns you out of combat while adventuring when you have fewer shards than your setting (default: 5), so you remember to *Drain Soul*.
- **"Warn when expiring"**: Optional early warnings for Demon Armor and your weapon stone.

### Warrior
- **No Ammo/Thrown Equipped**: Alerts you if you have a ranged weapon equipped but no ammo or thrown weapon charges.
- **Critical Ammo**: A "red alert" for when your ranged supplies are nearly empty.
- **Low Ammo**: A convenience reminder to stock up while resting.
- *Thrown weapons with durability never run out in Forever, so they don't trigger ammo reminders.*

---

## Smart Features

- **Dynamic Logic**: Reminders only appear if you have learned the required spells and are at a relevant level.
- **Resting Awareness**: Supply and repair reminders stay hidden while you are adventuring, only appearing in a city or inn, at a vendor, after joining a group or during a ready check.
- **Combat & Movement Safety**: Reminders are automatically suppressed while you are dead or on a taxi, and buff reminders while you're mounted or in a travel form (Travel, Aquatic or Flight Form, Ghost Wolf).
- **Snooze**: right-click a reminder, or `/prepped snooze [minutes]` for everything on screen (default: 30 minutes); `/prepped unsnooze` brings them back.
- **Non-Overlapping UI**: Reminders stack and resize themselves to ensure every message is readable without cluttering your screen.
- **Lightweight**: Prepped reacts to game events (bags, buffs, equipment, resting, ...) and re-checks at most a few times a second, plus once a second for countdowns. Your buffs and bags are read once per change, not on every check.

---

## WoW Forever Notes

- **Buffs during combat**: Forever doesn't let add-ons read your buffs during combat, even in open-world fights. Buff reminders therefore work out of combat, and Prepped stays quiet in combat instead of guessing. For in-combat alerts (a Seal, Battle Shout or any other buff that drops mid-fight), add the buff to Blizzard's **Cooldown Manager** and give it an "On Aura Removed" alert.
- **Clicking**: Forever, like Blizzard's retail client, doesn't let add-ons change clickable buttons during combat. Prepped's click buttons are put away when combat starts and come back afterwards.
- **Reagent Economy perk**: If you have this Legacy perk, Prepped detects it and hides the reminders for vendor reagents (Arcane Powder, Runes, Ankhs, Symbols, Flash Powder, candles, Rebirth seeds, Wild Berries/Thornroot, …). Soul Shards and Blinding Powder aren't sold by vendors, so those reminders stay.
- **Other perks and talents**: when you run out of a reagent and the game still lets you cast the spell that uses it, Prepped stops reminding you about that reagent (until your talents or Legacy perks change). This covers perks Prepped doesn't know about yet; `/prepped debug` lists your Legacy perks so they can be added.
- **Food that gives a food buff**: which food makes you Well Fed is only written in its tooltip, so Prepped reads the tooltips of the food and drink in your bags and looks for the buff's name, in your client's language. Plain food and water don't count. If the tooltips on your client don't name the buff, any food in your bags counts instead. `/prepped debug` lists the food and drink it found and which of it counts.
- **Any client language**: Spells are recognised by their spell ID, so Prepped works on every client, and its own texts are translated into German, French and Spanish (other languages show English). Spell and item names in reminders come from your client. Teleports and portals to places Prepped has no spell ID for are recognised by how their name starts ("Teleport: ") in your language. The exception is Water Shield, until its Forever spell ID is known.
- **Spec detection** (Protection Paladin, Enhancement Shaman, Righteous Fury while not tanking) uses the points spent in each talent tree.
- **`/prepped debug`** prints what Prepped sees: talent trees, weapon enchants, ranged weapon, durability, Reagent Economy, your Legacy perks (with spell IDs), your unspent Legacy points per tree, spells seen working without their reagent, the buffs on you with their spell IDs, your pet's abilities and autocast (hunters, warlocks), the food and drink in your bags (and which of it gives a food buff), which of your buffs Blizzard hides in combat, your druid form, any spell IDs your client doesn't know, spells Prepped only recognises by name (their IDs can then be added), the line it would post when you join a group, snoozed reminders, where the reminders are and how they're set up, and how many checks Prepped has run (with timings).

---

## Installation

- **CurseForge app or WowUp** (recommended, updates automatically): search for **Prepped**, or open the [CurseForge page](https://www.curseforge.com/wow/addons/prepped).
- **Manually**: download `Prepped.zip` from the [latest GitHub release](https://github.com/Alwindh/Prepped/releases/latest) and extract it into `World of Warcraft/_forever_/Interface/AddOns/`, so the folder is named exactly `Prepped`.

---

## Feedback

Found a bug or missing a reminder? Open an [issue on GitHub](https://github.com/Alwindh/Prepped/issues). For anything that looks wrong in-game, add the output of `/prepped debug`: it shows what Prepped sees on your character. Translations can be improved in `locale_deDE.lua`, `locale_frFR.lua` and `locale_esES.lua`; a new language is one more such file.

---

## Development

- `core.lua`: rules, saved settings, checking the reminders, snoozes, events. Each `reminders_*.lua` module declares its reminders as rules (options texts, when they show, the check, icon and click action).
- `display.lua`: the bars, moving them, the preview and the secure click buttons. `supplies.lua`: supply windows and the group message. `commands.lua`: slash commands and `/prepped debug`. `options.lua`: the Settings pages. `api.lua`: the WoW Forever API helpers and caches.
- `locale.lua` and `locale_*.lua`: every text Prepped shows is looked up by its English wording; translations keep its placeholders.

`tests/` runs Prepped against a mocked WoW Forever client: reminder scenarios for every class (a German client must show the same reminders as the English one), buff data hidden during combat, the bars (moving, preview, icons, clicking, snoozing, combat lockdown), `/prepped debug`, the options and the translations. The tests run on every pull request, together with [luacheck](https://github.com/lunarmodules/luacheck) and a check that the version was bumped. To run the tests yourself you need Lua 5.1 (the game's Lua version):

```bash
lua5.1 tests/run.lua
```

The `tests/` folder isn't included in the release zip.
