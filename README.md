# Prepped

**Prepped** is a lightweight, modular addon for WoW Classic/Anniversary that helps you avoid common mistakes by providing clear, non-intrusive reminders for missing buffs, low consumables, and other essentials.

---

## What Does Prepped Remind You About?

### Universal Reminders (All Classes)
- **Repair Reminder**: Alerts you to repair your gear when durability drops below your chosen threshold (only while resting).
- **Water Reminder**: Mana users are reminded to buy more water if they have less than your configured amount (only while resting, and only if you use mana).

### Hunter Reminders
- **Critical Ammo**: Warns you anytime your ammo drops below a critical threshold (default: 200).
- **Low Ammo**: Warns you while resting if your ammo is low (default: 1000).
- **Missing Aspect**: Reminds you if you do not have any Aspect buff active (e.g., Hawk, Cheetah, etc.).
- **No Pet Active**: Alerts you if you do not have a pet out (and you know Tame Beast).
- **Pet Unhappy**: Warns you if your pet is unhappy.
- **Low Pet Food**: Reminds you while resting if you have less than your configured amount of food for your pet's diet.

### Mage Reminders
- **Missing Arcane Intellect**: Alerts you if you do not have Arcane Intellect or Arcane Brilliance buff.
- **Missing Armor Buff**: Reminds you if you do not have any Mage Armor buff (e.g., Ice Armor, Mage Armor, etc.).
- **Low Arcane Powder**: Warns you while resting if you have less than your configured amount of Arcane Powder (for Arcane Brilliance).
- **Low Rune of Teleportation**: Warns you while resting if you have less than your configured amount of Runes of Teleportation (for Teleport spells).
- **Low Rune of Portals**: Warns you while resting if you have less than your configured amount of Runes of Portals (for Portal spells).

### Shaman Reminders
- **Missing Shield Buff**: Reminds you if you do not have Water Shield or Lightning Shield active (only while not resting).
- **Missing Weapon Buffs**: Alerts Enhancement/leveling Shamans if you are missing weapon imbues (checks both main and offhand for dual-wielders, only while not resting).
- **Low Ankh**: Reminds you while resting if you have less than your configured amount of Ankhs (for Reincarnation).
- **Low Fish Oil**: Reminds you while resting if you have less than your configured amount of Fish Oil (for Water Walking).
- **Low Fish Scales**: Reminds you while resting if you have less than your configured amount of Fish Scales (for Water Shield).
- **Buff/Weapon Buff Running Low**: Optionally, you can be warned when your shield or weapon buffs are about to expire (configurable duration threshold).

---

## How Do Reminders Work?
- **Smart Stacking**: All reminders stack vertically and never overlap, so you always see every alert.
- **Resting Logic**: Most supply reminders only trigger while you are in an Inn or Capital City, so you are not bothered while questing or raiding.
- **Level Awareness**: Reminders only show if they are relevant for your current level and class.

## Configuration
Type `/prepped` in-game to open the settings menu. You can:
- Enable/disable individual reminders.
- Set custom thresholds (e.g., "Warn me if I have less than 40 Water").
- Configure durability % for repair warnings.
- Toggle "Warn if low" for buffs to get a head start on re-buffing.

## Installation
1. Download the `Prepped.zip` from the latest release.
2. Extract it into your `World of Warcraft/_classic_/Interface/AddOns/` folder.
3. Ensure the folder is named `Prepped`.
4. Or simply use CurseForge, WowUP, or any other addon manager.

Or simply use CurseForge, WowUP, or any other addon manager.
