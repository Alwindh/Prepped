-- reminders_warlock.lua
-- Warlock-specific reminders for the Prepped addon

local _, ns = ...
local API = ns.API

local WarlockReminders = { class = "WARLOCK" }

local DEMON_SKIN = API.SpellFamily("Demon Skin", { 687, 696 }, { class = "WARLOCK", aura = true })
local DEMON_ARMOR = API.SpellFamily("Demon Armor", { 706, 1086, 11733, 11734, 11735 }, { class = "WARLOCK", aura = true })
local SUMMON_DEMON = API.SpellFamily("Summon demon", {
    688, -- Summon Imp
    697, -- Summon Voidwalker
    712, -- Summon Succubus
    691, -- Summon Felhunter
}, { class = "WARLOCK" })
local CREATE_HEALTHSTONE = API.SpellFamily("Create Healthstone", { 6201, 6202, 5699, 11729, 11730 }, { class = "WARLOCK" })
local CREATE_SOULSTONE = API.SpellFamily("Create Soulstone", { 693, 20752, 20755, 20756, 20757 }, { class = "WARLOCK" })
-- In Forever, Firestone and Spellstone are weapon imbues (they stack with oils).
local CREATE_FIRESTONE = API.SpellFamily("Create Firestone", { 6366, 17951, 17952, 17953 }, { class = "WARLOCK" })
local CREATE_SPELLSTONE = API.SpellFamily("Create Spellstone", { 2362, 17727, 17728 }, { class = "WARLOCK" })
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

local SOUL_SHARD = 6265
local HEALTHSTONES = {
    5512, 19004, 19005, -- Minor Healthstone (plain, Improved Healthstone 1/2 and 2/2)
    5511, 19006, 19007, -- Lesser Healthstone
    5509, 19008, 19009, -- Healthstone
    5510, 19010, 19011, -- Greater Healthstone
    9421, 19012, 19013, -- Major Healthstone
}
local SOULSTONES = { 5232, 16892, 16893, 16895, 16896 } -- Minor, Lesser, (plain), Greater, Major

local warlockReminders = {
    { id = "warlock_armor", mustNotRest = true, noTravel = true },
    { id = "warlock_pet", message = "No demon summoned", mustNotRest = true, noTravel = true },
    {
        id = "warlock_weapon_stone",
        message = "Missing weapon stone (Firestone/Spellstone)",
        messageLow = "Weapon stone expiring (%ss left)",
        mustNotRest = true,
        noTravel = true,
    },
    { id = "warlock_healthstone", message = "Missing item: Healthstone", mustNotRest = true, outOfCombat = true },
    { id = "warlock_soulstone", message = "Missing item: Soulstone", mustNotRest = true, outOfCombat = true },
    { id = "warlock_soul_shards", message = "Low on Soul Shards (%s left)", mustNotRest = true, outOfCombat = true },
}

local function KnowsAny(...)
    for i = 1, select("#", ...) do
        if API.KnowsFamily((select(i, ...))) then return true end
    end
    return false
end

local function SoulShardCount()
    return C_Item.GetItemCount(SOUL_SHARD)
end

local checks = {}

local ARMOR_TEXTS = {
    [true] = { "Missing Demon Armor!", "Demon Armor expiring (%ss left)" },
    [false] = { "Missing Demon Skin!", "Demon Skin expiring (%ss left)" },
}

function checks.warlock_armor(config)
    if not KnowsAny(DEMON_ARMOR, DEMON_SKIN) then return nil end
    local texts = ARMOR_TEXTS[API.KnowsFamily(DEMON_ARMOR)]
    return Prepped:CheckTimedBuff(config.id, IsDemonArmor, texts[1], texts[2])
end

function checks.warlock_pet(config)
    if not API.KnowsFamily(SUMMON_DEMON) then return nil end
    if UnitExists("pet") and not UnitIsDead("pet") then return nil end
    -- Sacrificed on purpose, or buff data hidden right now: don't nag
    if API.FindPlayerBuff(IsSacrificeBuff) ~= "missing" then return nil end
    return config.message
end

-- Like poisons, the stone is an "Imbue" enchant on the main hand; an oil on the
-- same weapon doesn't count.
function checks.warlock_weapon_stone(config)
    if not KnowsAny(CREATE_FIRESTONE, CREATE_SPELLSTONE) then return nil end
    return Prepped:CheckWeaponImbue(config, false)
end

-- Healthstone and Soulstone: only when you have a shard to make one.
function checks.warlock_healthstone(config)
    if not API.KnowsFamily(CREATE_HEALTHSTONE) or SoulShardCount() == 0 then return nil end
    if API.CountItems(HEALTHSTONES) > 0 then return nil end
    return config.message
end

function checks.warlock_soulstone(config)
    if not API.KnowsFamily(CREATE_SOULSTONE) or SoulShardCount() == 0 then return nil end
    if API.CountItems(SOULSTONES) > 0 then return nil end
    -- Already soulstoned yourself: the next one can wait
    if API.FindPlayerBuff(IsSoulstoned) ~= "missing" then return nil end
    return config.message
end

-- Shards matter once you can make stones (Voidwalker and the others come at the same levels).
function checks.warlock_soul_shards(config)
    if not KnowsAny(CREATE_HEALTHSTONE, CREATE_SOULSTONE) then return nil end
    local shards = SoulShardCount()
    if shards < Prepped:GetRuleThreshold(config.id) then
        return string.format(config.message, shards), shards
    end
    return nil
end

function WarlockReminders.CheckReminders()
    Prepped:RunReminders(warlockReminders, checks)
end

if Prepped then
    Prepped:RegisterReminderModule(WarlockReminders)
end
