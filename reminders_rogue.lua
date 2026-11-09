-- Rogue-specific reminders module
local _, ns = ...
local API = ns.API

local RogueReminders = { class = "ROGUE" }

local VANISH = API.SpellFamily("Vanish", { 1856, 1857 }, { class = "ROGUE" })
local BLIND = API.SpellFamily("Blind", { 2094 }, { class = "ROGUE" })
-- Poisons is a secondary skill in Forever (skill line 40), not a spellbook spell.
local POISONS = API.SpellFamily("Poisons", { 2842 }, { class = "ROGUE" })
local POISONS_SKILL_LINE = 40

local FLASH_POWDER = 5140    -- vendor reagent
local BLINDING_POWDER = 5530 -- made with Poisons, not sold by vendors

-- Poison item IDs (all ranks of each poison type)
local POISON_ITEMS = {
    6947, 6949, 6950, 8926, 8927, 8928, -- Instant Poison (Ranks 1-6)
    2892, 2893, 8984, 8985, 20844,      -- Deadly Poison (Ranks 1-5)
    3775, 3776,                         -- Crippling Poison (Ranks 1-2)
    5237, 6951, 9186,                   -- Mind-numbing Poison (Ranks 1-3)
    10918, 10920, 10921, 10922,         -- Wound Poison (Ranks 1-4)
}

local rogueReminders = {
    { id = "rogue_no_ammo", message = "No ammo/thrown equipped" },
    { id = "rogue_ammo_critical", message = "Critically low on ammo/thrown (%s left)" },
    {
        id = "rogue_ammo_low",
        message = "Low on ammo/thrown (%s left)",
        mustRest = true,
        suppressedBy = { "rogue_no_ammo", "rogue_ammo_critical" },
    },
    { id = "rogue_flash_powder", message = "Low on Flash Powder (%s left)", item = FLASH_POWDER, family = VANISH, mustRest = true },
    {
        id = "rogue_blinding_powder",
        message = "Low on Blinding Powder (%s left)",
        item = BLINDING_POWDER,
        family = BLIND,
        notSoldByVendors = true, -- Reagent Economy doesn't remove it
        mustRest = true,
    },
    { id = "rogue_poison_stock", message = "Low on Poison (%s total)", mustRest = true },
    {
        id = "rogue_weapon_poison",
        message = "Missing Weapon Poison!",
        messageLow = "Weapon Poison expiring (%ss left)",
        mustNotRest = true,
        noTravel = true,
    },
}

-- Learned Poisons (the poison-making skill)
local function KnowsPoisons()
    return API.GetSkillRank(POISONS_SKILL_LINE) > 0 or API.KnowsFamily(POISONS)
end

local function CheckReagent(config) return Prepped:CheckReagent(config) end

local checks = {
    rogue_flash_powder = CheckReagent,
    rogue_blinding_powder = CheckReagent,
}

function checks.rogue_no_ammo(config) return Prepped:CheckNoAmmo(config) end
function checks.rogue_ammo_critical(config) return Prepped:CheckAmmoBelow(config) end
checks.rogue_ammo_low = checks.rogue_ammo_critical

function checks.rogue_poison_stock(config)
    if not KnowsPoisons() then return nil end
    local count = API.CountItems(POISON_ITEMS)
    if count < Prepped:GetRuleThreshold(config.id) then
        return string.format(config.message, count), count
    end
    return nil
end

-- Both weapons when dual wielding; only poisons count, not sharpening stones
-- (which Forever lets you use on top of a poison).
function checks.rogue_weapon_poison(config)
    if not KnowsPoisons() or API.CountItems(POISON_ITEMS) == 0 then return nil end
    return Prepped:CheckWeaponImbue(config, true)
end

function RogueReminders.CheckReminders()
    Prepped:RunReminders(rogueReminders, checks)
end

if Prepped then
    Prepped:RegisterReminderModule(RogueReminders)
end
