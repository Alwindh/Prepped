-- reminders_priest.lua
-- Priest-specific reminders for the Prepped addon

local _, ns = ...
local API = ns.API

local PriestReminders = {}

local FORTITUDE = API.SpellFamily("Power Word: Fortitude", { 1243, 1244, 1245, 2791, 10937, 10938 }, { class = "PRIEST", aura = true })
local PRAYER_OF_FORTITUDE = API.SpellFamily("Prayer of Fortitude", { 21562, 21564 }, { class = "PRIEST", aura = true })
local INNER_FIRE = API.SpellFamily("Inner Fire", { 588, 7128, 602, 1006, 10951, 10952 }, { class = "PRIEST", aura = true })
local PRAYER_OF_SPIRIT = API.SpellFamily("Prayer of Spirit", { 27681 }, { class = "PRIEST" })
local PRAYER_OF_SHADOW_PROTECTION = API.SpellFamily("Prayer of Shadow Protection", { 27683 }, { class = "PRIEST" })

local IsFortitudeBuff = API.Matcher(FORTITUDE, PRAYER_OF_FORTITUDE)
local IsInnerFire = API.Matcher(INNER_FIRE)

-- Prayer of Fortitude rank 1 uses Holy Candles; rank 2, Prayer of Spirit and
-- Prayer of Shadow Protection use Sacred Candles.
local CANDLES = {
    { spells = { 21564, 27681, 27683 }, item = 17029, name = "Sacred Candles" },
    { spells = { 21562 }, item = 17028, name = "Holy Candles" },
}

local priestReminders = {
    {
        id = "priest_fortitude",
        message = "Missing Power Word: Fortitude!",
        messageLow = "Fortitude expiring (%ss left)",
        mustNotRest = true,
    },
    {
        id = "priest_inner_fire",
        message = "Missing Inner Fire!",
        messageLow = "Inner Fire expiring (%ss left)",
        mustNotRest = true,
    },
    { id = "priest_candles", mustRest = true },
}

local checks = {}

function checks.priest_fortitude(config)
    if IsMounted() then return nil end
    if not (API.KnowsFamily(PRAYER_OF_FORTITUDE) or API.KnowsFamily(FORTITUDE)) then return nil end
    return Prepped:CheckTimedBuff(config.id, IsFortitudeBuff, config.message, config.messageLow)
end

function checks.priest_inner_fire(config)
    if IsMounted() or not API.KnowsFamily(INNER_FIRE) then return nil end
    return Prepped:CheckTimedBuff(config.id, IsInnerFire, config.message, config.messageLow)
end

-- Vendor reagent: not needed with the Legacy perk "Reagent Economy"
function checks.priest_candles(config)
    if API.HasReagentEconomy() then return nil end
    if not (API.KnowsFamily(PRAYER_OF_FORTITUDE) or API.KnowsFamily(PRAYER_OF_SPIRIT)
        or API.KnowsFamily(PRAYER_OF_SHADOW_PROTECTION)) then
        return nil
    end
    local count, name = API.CountReagentForKnownSpell(CANDLES)
    if count < Prepped:GetRuleThreshold(config.id) then
        return string.format("Low on %s (%d left)", name or "candles", count)
    end
    return nil
end

function PriestReminders.CheckReminders()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "PRIEST" then return end
    Prepped:RunReminders(priestReminders, checks)
end

if Prepped then
    Prepped:RegisterReminderModule(PriestReminders)
end
