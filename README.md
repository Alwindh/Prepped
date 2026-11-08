# Prepped

**Prepped** is a modular, "set-it-and-forget-it" reminder addon for **WoW Forever** (interface `16001`). It helps you avoid common mistakes—like walking into a dungeon without water or pulling a boss without your pet—by providing clear, non-intrusive, and highly configurable alerts.

---

## Configuration and Options

Prepped's options live in the game's own settings: **Options → AddOns → Prepped**. Open them with `/prepped` or from the AddOns menu on the minimap.

- **Prepped** (main page): master toggle, account-wide vs. per-character settings, welcome message, water and repair reminders, and **Reset All Settings**.
- **Appearance**: font size, minimum bar width, text color, background color and background opacity.
- **One page per class** (Hunter, Mage, Paladin, Priest, Rogue, Shaman, Warrior): every reminder can be switched on or off. Stock reminders have a slider for the amount to warn at; buff reminders have an extra **Warn when expiring** option with a seconds slider.

Settings are shared by all characters (**Account-wide**) unless you switch that off; then each character gets its own settings.

---

## Available Reminders

### Universal (All Classes)
- **Repair Reminder**: Triggers when your average gear durability drops below your chosen percentage (only shown while **resting** in cities/inns).
- **Water Reminder**: Reminds mana users to buy water if they drop below a threshold. You can also set a **minimum level** for this reminder to avoid being bothered at low levels.

### Hunter
- **Critical Ammo**: A "Red Alert" that shows anytime your ammo drops below a critical point (e.g., 200).
- **Low Ammo**: A reminder to stock up while **resting** if you have less than your desired stock (e.g., 1000).
- **Missing Aspect**: Alerts you if you don't have an Aspect active (Hawk, Monkey, Cheetah, etc.).
- **Missing Pet**: Warns you if your pet isn't out (only if you know *Tame Beast*).
- **Unhappy Pet**: Reminds you to feed your pet if its happiness level drops.
- **Low Pet Food**: Alerts you while **resting** if you have fewer than your configured amount of food items in your bags that your pet can actually eat.

### Mage
- **Missing Arcane Intellect**: Detects if you or your group are missing Intellect.
- **Missing Armor Buff**: Reminds you to apply Frost, Ice, or Mage Armor.
- **Missing Mana Gem**: Alerts you to conjure a Mana Gem if you have the spell but no gem in your bags.
- **Reagent Tracking**: Optional warnings while **resting** if you are low on:
  - **Arcane Powder** (for Brilliance)
  - **Rune of Teleportation**
  - **Rune of Portals**

### Paladin
- **Missing Seal**: Triggers in combat if you don't have a Seal active, including Forever's Seal of Fury (with built-in logic to suppress the warning after using *Judgement*).
- **Missing Aura**: Ensures you always have a Paladin Aura active.
- **Missing Blessing**: Reminds you to keep a long-duration Blessing (Might, Wisdom, Kings, etc., or a Greater Blessing) active on yourself while adventuring.
- **Missing Righteous Fury**: Alerts you to activate Righteous Fury if you are in a group, have a shield equipped, and are Protection spec.
- **Reagent Tracking**: Monitors your stock of **Symbol of Kings** and **Symbol of Divinity** while resting.
- **"Warn if Low"**: Optional early warnings for Seals and Righteous Fury—get notified before they expire.

### Rogue
- **Missing Ammo/Thrown**: Alerts you if you have a ranged weapon equipped but no ammo or thrown weapon charges.
- **Critical Ammo**: A survival alert if your ammo/thrown count drops below a dangerous level.
- **Low Ammo**: A resting reminder to restock before your next adventure.
- **Missing Weapon Poison**: Alerts if either weapon is missing poison (only if you have the *Poisons* skill and poison in bags). A sharpening stone on the weapon doesn't count as a poison.
- **Low Flash Powder**: Reminds you to stock up on Flash Powder while **resting** if you know *Vanish* (default: 10).
- **Low Poison Stock**: Warns you while **resting** if your total poison count is low (default: 20, checks all poison types).
- **"Warn if Low"**: Optional early warning for weapon poisons—get notified before they expire (default: 60 seconds).

### Shaman
- **Missing Shield**: Alerts if Lightning Shield (or Water Shield, a Restoration talent in Forever) is missing.
- **Weapon Imbues**: Smart tracking for Rockbiter, Flametongue, Frostbrand, and Windfury. 
  - *Note: Only triggers for Enhancement/Leveling Shamans and is dual-wield aware. Sharpening stones and oils don't count as an imbue.*
- **Reagent Tracking**: Warnings while **resting** for (each only once you know the spell that uses it):
  - **Ankhs** (Reincarnation)
  - **Fish Oil** (Water Walking)
  - **Fish Scales** (Water Breathing)
- **"Warn if Low"**: A special toggle for Shields and Weapon buffs—reminds you to re-apply them *before* they expire (configurable seconds threshold).

### Warrior
- **Missing Battle Shout**: Alerts you if you don't have Battle Shout active while in combat (only if you know *Battle Shout*).
- **"Warn if Low"**: Optional early warning for Battle Shout—get notified before it expires (default: 10 seconds remaining).
- **Missing Ammo/Thrown**: Alerts you if you have a ranged weapon equipped but no ammo or thrown weapon charges.
- **Critical Ammo**: A "Red Alert" for when your ranged supplies are nearly empty.
- **Low Ammo**: A convenience reminder to stock up while resting.

---

## Smart Features

- **Dynamic Logic**: Reminders only appear if you have learned the required spells and are at a relevant level.
- **Resting Awareness**: Supply and repair reminders stay hidden while you are adventuring, only appearing when you reach a City or Inn.
- **Combat & Movement Safety**: Reminders are automatically suppressed while you are dead, on a taxi, or (for certain buffs) while mounted.
- **Non-Overlapping UI**: Alerts stack vertically and resize themselves to ensure every message is readable without cluttering your screen.

---

## WoW Forever Notes

- **Buffs during combat**: Forever can hide buff information from addons during combat, boss encounters and PvP matches. When Prepped can't see your buffs it stays quiet instead of guessing, so in-combat reminders (Seal, Battle Shout, and other buffs that drop mid-fight) only show for buffs Blizzard keeps visible. Out of combat everything works as usual. For a guaranteed in-combat alert, add the buff to Blizzard's **Cooldown Manager** and give it an "On Aura Removed" alert.
- **Reagent Economy perk**: If you have this Legacy perk, Prepped detects it and hides the reminders for vendor reagents (Arcane Powder, Runes, Ankhs, Symbols, Flash Powder, …).
- **Any client language**: Spells are recognised by their spell ID, so Prepped works on non-English clients too (its own texts are English).
- **Spec detection** (Protection/Holy Paladin, Enhancement Shaman) uses the points spent in each talent tree.
- **`/prepped debug`** prints what Prepped sees: talent trees, weapon enchants, ranged weapon, Reagent Economy, which of your buffs Blizzard hides in combat, and any spell IDs your client doesn't know.

---

## Installation

1. Download the latest release.
2. Extract the folder into `World of Warcraft/_forever_/Interface/AddOns/`.
3. Ensure the folder is named exactly `Prepped`.
4. (Optional) Install via **CurseForge** or **WowUP** for automatic updates.


