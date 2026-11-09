# Prepped

**Prepped** is a modular, "set-it-and-forget-it" reminder addon for **WoW Forever** (interface `16001`). It helps you avoid common mistakes—like walking into a dungeon without water or pulling a boss without your pet—by providing clear, non-intrusive, and highly configurable alerts.

**Download:** [CurseForge](https://www.curseforge.com/wow/addons/prepped) (also in WowUp) · [GitHub releases](https://github.com/Alwindh/Prepped/releases/latest) · **Bugs and ideas:** [GitHub issues](https://github.com/Alwindh/Prepped/issues)

### At a glance
- **Reagents and supplies**: water, ammo, Soul Shards, candles, Rebirth seeds, Symbols, Runes, Ankhs, poisons and more, for the spells you actually know. With Forever's Reagent Economy perk, vendor reagents are hidden automatically.
- **Your own buffs**: Mark of the Wild, Fortitude, Inner Fire, Arcane Intellect, armors, Aspects, Auras, Blessings and shields, when they're missing or about to run out.
- **Things you leave behind**: totems in the bank, no Healthstone or Soulstone, no pet or demon out, no poison or imbue on your weapon.
- **Joining a group**: your supply reminders on screen for a minute, and one line in group chat about what you're low on.
- **Leveling in Forever**: keep your food buff (Well Fed, +5% kill XP) and Camp Benefits up.
- **Repairs** when your gear gets worn.

Reminders stay out of your way: supply reminders show up in cities and inns where you can restock, buff reminders while you're out adventuring.

---

## Configuration and Options

Prepped's options live in the game's own settings: **Options → AddOns → Prepped**. Open them with `/prepped` or from the AddOns menu on the minimap.

- **Prepped** (main page): master toggle, account-wide vs. per-character settings, welcome message, water and repair reminders, the group options, the food buff and camp reminders, and **Reset All Settings**.
- **Appearance**: font size, minimum bar width, text color, background color and background opacity.
- **One page per class** (Druid, Hunter, Mage, Paladin, Priest, Rogue, Shaman, Warlock, Warrior): every reminder can be switched on or off. Stock reminders have a slider for the amount to warn at; buff reminders have an extra **Warn when expiring** option with a seconds slider.

Settings are shared by all characters (**Account-wide**) unless you switch that off; then each character gets its own settings.

---

## Available Reminders

### Universal (All Classes)
- **Repair Reminder**: Triggers when your average gear durability drops below your chosen percentage (only shown while **resting** in cities/inns).
- **Water Reminder**: Reminds mana users (also druids in Bear or Cat Form) to buy water if they drop below a threshold. You can also set a **minimum level** for this reminder to avoid being bothered at low levels.
- **Missing Food Buff**: While leveling, reminds you to keep a food buff (**Well Fed**) up when you're not resting, not in combat and not mounted (or in Travel Form / Ghost Wolf). In Forever, cooked food also gives +5% experience from kills. Off at max level or with experience turned off; optional early warning before it runs out.
- **Check Supplies When Joining a Group**: When you join a party or raid, your supply reminders (reagents, ammo, repairs and so on) show for a minute even outside cities and inns, so you can restock before you head in. Only you see them.
- **Tell My Group**: When you join a party or raid, Prepped posts one line in group chat about what you're low on, for example `[Prepped] you're at 47% durability, remember to repair soon.` It names up to three things, posts once per group, waits until you're out of combat, and only mentions durability below 50% (adjustable). Turn it off on the Prepped options page if you'd rather not.
- **Missing Camp Benefits**: Same conditions as the food buff: while leveling, reminds you to get **Camp Benefits** (sit at a camp for a minute; it combines the buffs of the camp's objects and lasts an hour). Optional early warning, by default 5 minutes before it runs out.

### Druid
- **Missing Mark of the Wild**: Alerts you when neither Mark of the Wild nor Gift of the Wild is on you (not while resting, mounted or in Travel/Aquatic/Flight Form).
- **Reagent Tracking**: Warnings while **resting** for the reagent of your highest rank:
  - **Rebirth seeds** (Maple, Stranglethorn, Ashwood, Hornbeam or Ironwood Seeds)
  - **Gift of the Wild** (Wild Berries or Wild Thornroot)
- **"Warn if Low"**: Optional early warning before Mark of the Wild runs out.

### Hunter
- **Missing Ammo**: Alerts you when you have a ranged weapon equipped but no ammo.
- **Critical Ammo**: A "Red Alert" while you're out adventuring when your ammo drops below a critical point (e.g., 200).
- **Low Ammo**: A reminder to stock up while **resting** if you have less than your desired stock (e.g., 1000).
- **Missing Aspect**: Alerts you if you don't have an Aspect active (Hawk, Monkey, Cheetah, etc.).
- **Missing Pet**: Warns you if your pet isn't out (only if you know *Tame Beast*).
- **Unhappy Pet**: Reminds you to feed your pet if its happiness level drops.
- **Low Pet Food**: Alerts you while **resting** if you have fewer than your configured amount of food items in your bags that your pet can actually eat.

### Mage
- **Missing Arcane Intellect**: Alerts you when Arcane Intellect (or Arcane Brilliance) isn't on you.
- **Missing Armor Buff**: Reminds you to apply Frost, Ice, or Mage Armor.
- **Missing Mana Gem**: Alerts you to conjure a Mana Gem if you have the spell but no gem in your bags.
- **Reagent Tracking**: Optional warnings while **resting** if you are low on:
  - **Arcane Powder** (for Brilliance)
  - **Rune of Teleportation**
  - **Rune of Portals**

### Paladin
- **Missing Aura**: Ensures you always have a Paladin Aura active.
- **Missing Blessing**: Reminds you to keep a Blessing (Might, Wisdom or Kings, or a Greater Blessing) active on yourself while adventuring.
- **Missing Righteous Fury**: Alerts you to activate Righteous Fury if you are in a group, have a shield equipped, and are Protection spec.
- **Reagent Tracking**: Monitors your stock of **Symbol of Kings** and **Symbol of Divinity** while resting.
- **"Warn if Low"**: Optional early warnings for Blessings and Righteous Fury—get notified before they expire.

### Priest
- **Missing Power Word: Fortitude**: Alerts you when Fortitude (or Prayer of Fortitude) is missing while adventuring.
- **Missing Inner Fire**: Alerts you when Inner Fire is missing while adventuring.
- **Low Candles**: Reminds you while **resting** to restock the candles your Prayer spells use: **Sacred Candles** once you know Prayer of Fortitude rank 2, Prayer of Spirit or Prayer of Shadow Protection, **Holy Candles** before that.
- **"Warn if Low"**: Optional early warnings for Fortitude and Inner Fire.

### Rogue
- **Missing Ammo/Thrown**: Alerts you if you have a ranged weapon equipped but no ammo or thrown weapon charges.
- **Critical Ammo**: A survival alert if your ammo/thrown count drops below a dangerous level.
- **Low Ammo**: A resting reminder to restock before your next adventure.
- **Missing Weapon Poison**: Alerts if either weapon is missing poison (only if you have the *Poisons* skill and poison in bags). A sharpening stone on the weapon doesn't count as a poison.
- **Low Flash Powder**: Reminds you to stock up on Flash Powder while **resting** if you know *Vanish* (default: 10).
- **Low Blinding Powder**: Reminds you to make or buy Blinding Powder while **resting** if you know *Blind* (default: 5).
- **Low Poison Stock**: Warns you while **resting** if your total poison count is low (default: 20, checks all poison types).
- **"Warn if Low"**: Optional early warning for weapon poisons—get notified before they expire (default: 60 seconds).
- *Thrown weapons with durability never run out in Forever, so they don't trigger ammo reminders.*

### Shaman
- **Missing Totem Items**: Totems in Forever still need their element's totem item in your bags. Prepped warns you (out of combat) when the **Earth, Fire, Water or Air Totem** for totems you know is missing, for example after leaving it in the bank.
- **Missing Shield**: Alerts if Lightning Shield (or Water Shield) is missing. Water Shield is new in Forever and is only recognised on English clients until its spell ID is known.
- **Weapon Imbues**: Smart tracking for Rockbiter, Flametongue, Frostbrand, and Windfury. 
  - *Note: Only triggers for Enhancement/Leveling Shamans and is dual-wield aware. Sharpening stones and oils don't count as an imbue.*
- **Reagent Tracking**: Warnings while **resting** for (each only once you know the spell that uses it):
  - **Ankhs** (Reincarnation)
  - **Fish Oil** (Water Walking)
  - **Fish Scales** (Water Breathing)
- **"Warn if Low"**: A special toggle for Shields and Weapon buffs—reminds you to re-apply them *before* they expire (configurable seconds threshold).

### Warlock
- **Missing Demon Armor**: Alerts you when Demon Armor (or Demon Skin before you learn it) is missing.
- **Missing Demon**: Warns you when no demon is summoned (not while a *Demonic Sacrifice* buff is on you).
- **Missing Weapon Stone**: In Forever, Firestone and Spellstone are weapon imbues. Once you can create one, Prepped reminds you to keep one on your main hand (a wizard oil on the same weapon doesn't count).
- **Missing Healthstone / Soulstone**: Reminds you to create them when you have a Soul Shard (out of combat, not while resting). No Soulstone reminder while you are soulstoned yourself.
- **Low Soul Shards**: Warns you out of combat while adventuring when you have fewer shards than your setting (default: 5), so you remember to *Drain Soul*.
- **"Warn if Low"**: Optional early warnings for Demon Armor and your weapon stone.

### Warrior
- **Missing Ammo/Thrown**: Alerts you if you have a ranged weapon equipped but no ammo or thrown weapon charges.
- **Critical Ammo**: A "Red Alert" for when your ranged supplies are nearly empty.
- **Low Ammo**: A convenience reminder to stock up while resting.
- *Thrown weapons with durability never run out in Forever, so they don't trigger ammo reminders.*

---

## Smart Features

- **Dynamic Logic**: Reminders only appear if you have learned the required spells and are at a relevant level.
- **Resting Awareness**: Supply and repair reminders stay hidden while you are adventuring, only appearing when you reach a City or Inn.
- **Combat & Movement Safety**: Reminders are automatically suppressed while you are dead or on a taxi, and buff reminders while you're mounted or in a travel form.
- **Non-Overlapping UI**: Alerts stack vertically and resize themselves to ensure every message is readable without cluttering your screen.

---

## WoW Forever Notes

- **Buffs during combat**: Forever doesn't let add-ons read your buffs during combat, even in open-world fights. Buff reminders therefore work out of combat, and Prepped stays quiet in combat instead of guessing. For in-combat alerts (a Seal, Battle Shout or any other buff that drops mid-fight), add the buff to Blizzard's **Cooldown Manager** and give it an "On Aura Removed" alert.
- **Reagent Economy perk**: If you have this Legacy perk, Prepped detects it and hides the reminders for vendor reagents (Arcane Powder, Runes, Ankhs, Symbols, Flash Powder, candles, Rebirth seeds, Wild Berries/Thornroot, …). Soul Shards and Blinding Powder aren't sold by vendors, so those reminders stay.
- **Any client language**: Spells are recognised by their spell ID, so Prepped works on non-English clients too (its own texts are English). The exception is Water Shield, until its Forever spell ID is known.
- **Spec detection** (Protection Paladin, Enhancement Shaman) uses the points spent in each talent tree.
- **`/prepped debug`** prints what Prepped sees: talent trees, weapon enchants, ranged weapon, Reagent Economy, the buffs on you with their spell IDs, which of your buffs Blizzard hides in combat, your druid form, any spell IDs your client doesn't know, spells Prepped only recognises by name (their IDs can then be added), and the line it would post when you join a group.

---

## Installation

- **CurseForge app or WowUp** (recommended, updates automatically): search for **Prepped**, or open the [CurseForge page](https://www.curseforge.com/wow/addons/prepped).
- **Manually**: download `Prepped.zip` from the [latest GitHub release](https://github.com/Alwindh/Prepped/releases/latest) and extract it into `World of Warcraft/_forever_/Interface/AddOns/`, so the folder is named exactly `Prepped`.

---

## Feedback

Found a bug or missing a reminder? Open an [issue on GitHub](https://github.com/Alwindh/Prepped/issues). For anything that looks wrong in-game, add the output of `/prepped debug`: it shows what Prepped sees on your character.

---

## Development

`tests/` runs Prepped against a mocked WoW Forever client: reminder scenarios for every class on an English and a German client, buff data hidden during combat, `/prepped debug` and the options. The tests run automatically on every pull request. To run them yourself you need Lua 5.1 (the game's Lua version):

```bash
lua5.1 tests/run.lua
```

The `tests/` folder isn't included in the release zip.


