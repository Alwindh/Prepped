-- Mage-specific reminders module
local _, ns = ...
local API = ns.API

local MageReminders = { class = "MAGE" }

local ARCANE_INTELLECT = API.SpellFamily("Arcane Intellect", { 1459, 1460, 1461, 10156, 10157 }, { class = "MAGE", aura = true })
local ARCANE_BRILLIANCE = API.SpellFamily("Arcane Brilliance", { 23028 }, { class = "MAGE", aura = true })
local ARMORS = API.SpellFamily("Mage armors", {
    168, 7300, 7301,          -- Frost Armor
    7302, 7320, 10219, 10220, -- Ice Armor
    6117, 22782, 22783,       -- Mage Armor
}, { class = "MAGE", aura = true })
local CONJURE_MANA_GEM = API.SpellFamily("Conjure Mana Gem", { 759, 3552, 10053, 10054 }, { class = "MAGE" })
-- Forever-only destinations are caught by the English pattern until their IDs are known.
local TELEPORTS = API.SpellFamily("Teleports", { 3561, 3562, 3563, 3565, 3566, 3567 }, { class = "MAGE", englishPattern = "^Teleport: " })
local PORTALS = API.SpellFamily("Portals", { 10059, 11416, 11417, 11418, 11419, 11420 }, { class = "MAGE", englishPattern = "^Portal: " })

local IsIntellectBuff = API.Matcher(ARCANE_INTELLECT, ARCANE_BRILLIANCE)
local IsMageArmor = API.Matcher(ARMORS)

local MANA_GEMS = {
    5514, -- Agate
    5513, -- Jade
    8007, -- Citrine
    8008, -- Ruby
}

local mageReminders = {
    {
        id = "mage_ai_buff",
        message = "Buff Missing: Arcane Intellect",
        messageLow = "Arcane Intellect expiring (%ss left)",
        mustNotRest = true,
        noTravel = true,
    },
    {
        id = "mage_armor_buff",
        message = "Buff Missing: Mage Armor",
        messageLow = "Armor buff expiring (%ss left)",
        mustNotRest = true,
        noTravel = true,
    },
    { id = "mage_powder", message = "Low on reagents: Arcane Powder (%s left!)", item = 17020, family = ARCANE_BRILLIANCE, mustRest = true },
    { id = "mage_rune_teleport", message = "Low on reagents: Rune of Teleportation (%s left!)", item = 17031, family = TELEPORTS, mustRest = true },
    { id = "mage_rune_portals", message = "Low on reagents: Rune of Portals (%s left!)", item = 17032, family = PORTALS, mustRest = true },
    { id = "mage_mana_gem", message = "Missing item: Mana Gem", mustNotRest = true, outOfCombat = true },
}

local function CheckReagent(config) return Prepped:CheckReagent(config) end

local checks = {
    mage_powder = CheckReagent,
    mage_rune_teleport = CheckReagent,
    mage_rune_portals = CheckReagent,
}

function checks.mage_ai_buff(config)
    if not API.KnowsFamily(ARCANE_INTELLECT) then return nil end
    return Prepped:CheckTimedBuff(config.id, IsIntellectBuff, config.message, config.messageLow)
end

function checks.mage_armor_buff(config)
    if not API.KnowsFamily(ARMORS) then return nil end
    return Prepped:CheckTimedBuff(config.id, IsMageArmor, config.message, config.messageLow)
end

function checks.mage_mana_gem(config)
    if not API.KnowsFamily(CONJURE_MANA_GEM) or API.CountItems(MANA_GEMS) > 0 then return nil end
    return config.message
end

function MageReminders.CheckReminders()
    Prepped:RunReminders(mageReminders, checks)
end

if Prepped then
    Prepped:RegisterReminderModule(MageReminders)
end
