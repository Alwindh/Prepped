-- reminders_warlock.lua
-- Warlock reminders: Demon Armor, the demon (out, taunts in groups), weapon
-- stone, Healthstone, Soulstone and Soul Shards.

local _, ns = ...
local API, L, Action = ns.API, ns.L, ns.Action
local Prepped = ns.Prepped
local format = string.format

local DEMON_SKIN_IDS = { 687, 696 }
local DEMON_ARMOR_IDS = { 706, 1086, 11733, 11734, 11735 }
local DEMON_SKIN = API.SpellFamily("Demon Skin", DEMON_SKIN_IDS, { class = "WARLOCK", aura = true })
local DEMON_ARMOR = API.SpellFamily("Demon Armor", DEMON_ARMOR_IDS, { class = "WARLOCK", aura = true })
local IMP, VOIDWALKER, SUCCUBUS, FELHUNTER = { 688 }, { 697 }, { 712 }, { 691 }
local SUMMON_DEMON = API.SpellFamily("Summon demon", {
    688, -- Summon Imp
    697, -- Summon Voidwalker
    712, -- Summon Succubus
    691, -- Summon Felhunter
}, { class = "WARLOCK" })
-- Ranks have their own names ("Create Healthstone (Major)"), rank 1 first.
local CREATE_HEALTHSTONE = API.SpellFamily("Create Healthstone", { 6201, 6202, 5699, 11729, 11730 }, { class = "WARLOCK" })
local CREATE_SOULSTONE = API.SpellFamily("Create Soulstone", { 693, 20752, 20755, 20756, 20757 }, { class = "WARLOCK" })
-- In Forever, Firestone and Spellstone are weapon imbues (they stack with oils).
local CREATE_FIRESTONE = API.SpellFamily("Create Firestone", { 6366, 17951, 17952, 17953 }, { class = "WARLOCK" })
local CREATE_SPELLSTONE = API.SpellFamily("Create Spellstone", { 2362, 17727, 17728 }, { class = "WARLOCK" })
-- The Voidwalker's taunts, which take threat from the tank when on autocast in a group.
local TORMENT = API.SpellFamily("Torment", { 3716, 7809, 7810, 7811, 11774, 11775 }, { class = "WARLOCK" })
local SUFFERING = API.SpellFamily("Suffering", { 17735, 17750, 17751, 17752 }, { class = "WARLOCK" })
-- Demonic Sacrifice buffs: no demon out on purpose
local DEMONIC_SACRIFICE = API.SpellFamily("Demonic Sacrifice", {
    18789, -- Burning Wish (Imp)
    18790, -- Fel Stamina (Voidwalker)
    18791, -- Touch of Shadow (Succubus)
    18792, -- Fel Energy (Felhunter)
}, { class = "WARLOCK" })
local SOULSTONE_RESURRECTION = API.SpellFamily("Soulstone Resurrection", { 20707, 20762, 20763, 20764, 20765 }, { class = "WARLOCK" })

local IsDemonArmor = API.Matcher(DEMON_SKIN, DEMON_ARMOR)
local IsSacrificeBuff = API.Matcher(DEMONIC_SACRIFICE)
local IsSoulstoned = API.Matcher(SOULSTONE_RESURRECTION)
local IsTaunt = API.Matcher(TORMENT, SUFFERING)

local SOUL_SHARD = 6265
local HEALTHSTONES = {
    5512, 19004, 19005, -- Minor Healthstone (plain, Improved Healthstone 1/2 and 2/2)
    5511, 19006, 19007, -- Lesser Healthstone
    5509, 19008, 19009, -- Healthstone
    5510, 19010, 19011, -- Greater Healthstone
    9421, 19012, 19013, -- Major Healthstone
}
local SOULSTONES = { 5232, 16892, 16893, 16895, 16896 } -- Minor, Lesser, (plain), Greater, Major
-- Weapon stones in your bags, best first: Major, Greater, plain and Lesser Firestone, then Spellstones.
local WEAPON_STONES = { 13701, 13700, 13699, 1254, 13603, 13602, 5522 }

local function KnowsAny(...)
    for i = 1, select("#", ...) do
        if API.KnowsFamily((select(i, ...))) then return true end
    end
    return false
end

local function SoulShardCount()
    return C_Item.GetItemCount(SOUL_SHARD)
end

-- Demon Armor once you know it, Demon Skin before.
local function ArmorSpell()
    return API.BestKnownSpell(DEMON_ARMOR_IDS) or API.BestKnownFamilySpell(DEMON_ARMOR) or API.BestKnownFamilySpell(DEMON_SKIN)
end

-- Highest rank you know (the ranks have their own names).
local function CreateSpell(family)
    return API.BestKnownSpell(family.ids) or API.BestKnownFamilySpell(family)
end

local function FindWeaponStone()
    for _, itemID in ipairs(WEAPON_STONES) do
        local bag, slot = API.FindBagItem(itemID)
        if bag then return itemID, bag, slot end
    end
    return nil
end

Prepped:RegisterModule({
    class = "WARLOCK",
    group = "Warlock",
    reminders = {
        {
            id = "warlock_armor", label = L["Missing Demon Armor"], hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 },
            description = L["Reminds you to have Demon Armor (or Demon Skin before you learn it) up when not resting."],
            adventuring = true, noTravel = true,
            check = function(rule)
                local spellID = ArmorSpell()
                if not spellID then return nil end
                return Prepped:CheckTimedBuff(rule, IsDemonArmor, C_Spell.GetSpellName(spellID)), nil, API.GetSpellIcon(spellID)
            end,
            action = function() return Action.Cast(ArmorSpell()) end,
        },
        {
            -- Clicking summons the demon you summoned last.
            id = "warlock_pet", label = L["Missing Demon"],
            description = L["Reminds you to summon a demon when not resting (not while a Demonic Sacrifice buff is on you). Clicking it summons the demon you summoned last."],
            adventuring = true, noTravel = true,
            family = SUMMON_DEMON, prefer = { VOIDWALKER, IMP, SUCCUBUS, FELHUNTER }, rememberCasts = SUMMON_DEMON,
            check = function(rule)
                if not API.KnowsFamily(SUMMON_DEMON) then return nil end
                if UnitExists("pet") and not UnitIsDead("pet") then return nil end
                -- Sacrificed on purpose, or buff data hidden right now: don't nag
                if API.FindPlayerBuff(IsSacrificeBuff) ~= "missing" then return nil end
                return L["Summon your demon"], nil, API.GetSpellIcon(select(2, Prepped:ChooseSpell(rule)))
            end,
            action = function(rule) return Action.Cast(select(2, Prepped:ChooseSpell(rule))) end,
        },
        {
            id = "warlock_pet_taunt", label = L["Voidwalker Taunts on Autocast in Groups"],
            description = L["In a dungeon or raid group, warns when your Voidwalker's Torment or Suffering is on autocast, so it doesn't take threat from the tank. Clicking it turns autocast off."],
            outOfCombat = true,
            check = function()
                if not (UnitExists("pet") and API.InGroupInstance()) then return nil end
                local name, spellID = API.FindAutocastPetAction(IsTaunt)
                if not name then return nil end
                return format(L["Turn off %s autocast"], name), nil, API.GetSpellIcon(spellID or TORMENT.ids[1])
            end,
            action = function()
                local name = API.FindAutocastPetAction(IsTaunt)
                if not name then return nil end
                return Action.Macro("/petautocastoff " .. name, format(L["Turn off %s autocast"], name))
            end,
        },
        {
            -- Like poisons, the stone is an "Imbue" enchant on the main hand; an oil
            -- on the same weapon doesn't count.
            id = "warlock_weapon_stone", label = L["Missing Weapon Stone"], hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 },
            description = L["Once you can create a Firestone or Spellstone, reminds you to keep one on your main hand (weapon imbues in Forever; a wizard oil doesn't count). Clicking it applies a stone from your bags, or creates one."],
            adventuring = true, noTravel = true,
            check = function(rule)
                if not KnowsAny(CREATE_FIRESTONE, CREATE_SPELLSTONE) then return nil end
                local state, first = Prepped:CheckWeaponImbue(rule, false)
                local icon = API.GetSpellIcon(CreateSpell(CREATE_FIRESTONE) or CreateSpell(CREATE_SPELLSTONE))
                if state == "missing" then return L["Apply a Firestone or Spellstone"], nil, icon end
                if state == "expiring" then return format(L["%s expires in %s"], L["Weapon stone"], ns.FormatDuration(first)), nil, icon end
            end,
            action = function()
                local itemID, bag, slot = FindWeaponStone()
                if itemID then return Action.UseItem(bag, slot, itemID, API.MAIN_HAND_SLOT) end
                return Action.Cast(CreateSpell(CREATE_FIRESTONE) or CreateSpell(CREATE_SPELLSTONE))
            end,
        },
        {
            -- Healthstone and Soulstone: only when you have a shard to make one.
            id = "warlock_healthstone", label = L["Missing Healthstone"],
            description = L["Reminds you to create a Healthstone when you are out of combat, not resting, and have a Soul Shard."],
            announce = { L["missing a Healthstone"], L["create a Healthstone"] },
            adventuring = true, outOfCombat = true,
            check = function()
                local spellID = CreateSpell(CREATE_HEALTHSTONE)
                if not spellID or SoulShardCount() == 0 or API.CountItems(HEALTHSTONES) > 0 then return nil end
                return L["Create a Healthstone"], nil, API.GetSpellIcon(spellID)
            end,
            action = function() return Action.Cast(CreateSpell(CREATE_HEALTHSTONE)) end,
        },
        {
            id = "warlock_soulstone", label = L["Missing Soulstone"],
            description = L["Reminds you to create a Soulstone when you are out of combat, not resting, have a Soul Shard and aren't soulstoned yourself."],
            announce = { L["missing a Soulstone"], L["create a Soulstone"] },
            adventuring = true, outOfCombat = true,
            check = function()
                local spellID = CreateSpell(CREATE_SOULSTONE)
                if not spellID or SoulShardCount() == 0 or API.CountItems(SOULSTONES) > 0 then return nil end
                -- Already soulstoned yourself: the next one can wait
                if API.FindPlayerBuff(IsSoulstoned) ~= "missing" then return nil end
                return L["Create a Soulstone"], nil, API.GetSpellIcon(spellID)
            end,
            action = function() return Action.Cast(CreateSpell(CREATE_SOULSTONE)) end,
        },
        {
            -- Shards matter once you can make stones (Voidwalker and the others come at the same levels).
            id = "warlock_soul_shards", label = L["Low Soul Shards"], defaultThreshold = 5, unit = "count", range = { 0, 40, 1 },
            description = L["Out of combat and not resting, warns when you have fewer Soul Shards than this, so you remember to use Drain Soul."],
            announce = { L["low on Soul Shards ({count} left)"], L["farm more Soul Shards"] },
            adventuring = true, outOfCombat = true,
            item = SOUL_SHARD,
            check = function(rule)
                if not KnowsAny(CREATE_HEALTHSTONE, CREATE_SOULSTONE) then return nil end
                local shards = SoulShardCount()
                if shards < Prepped:GetRuleThreshold(rule.id) then
                    return format(L["Collect %s (%d left)"], L["Soul Shards"], shards), shards
                end
            end,
        },
    },
})
