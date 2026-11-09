-- reminders_druid.lua
-- Druid-specific reminders for the Prepped addon

local _, ns = ...
local API = ns.API

local DruidReminders = {}

local MARK_OF_THE_WILD = API.SpellFamily("Mark of the Wild", { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }, { class = "DRUID", aura = true })
local GIFT_OF_THE_WILD = API.SpellFamily("Gift of the Wild", { 21849, 21850 }, { class = "DRUID", aura = true })
local REBIRTH = API.SpellFamily("Rebirth", { 20484, 20739, 20742, 20747, 20748 }, { class = "DRUID" })

local IsMarkOfTheWild = API.Matcher(MARK_OF_THE_WILD, GIFT_OF_THE_WILD)

-- Each rank uses its own reagent; highest rank first.
local REBIRTH_SEEDS = {
    { spells = { 20748 }, item = 17038, name = "Ironwood Seeds" },
    { spells = { 20747 }, item = 17037, name = "Hornbeam Seeds" },
    { spells = { 20742 }, item = 17036, name = "Ashwood Seeds" },
    { spells = { 20739 }, item = 17035, name = "Stranglethorn Seeds" },
    { spells = { 20484 }, item = 17034, name = "Maple Seeds" },
}
local GIFT_REAGENTS = {
    { spells = { 21850 }, item = 17026, name = "Wild Thornroot" },
    { spells = { 21849 }, item = 17021, name = "Wild Berries" },
}

local druidReminders = {
    {
        id = "druid_mark",
        message = "Missing Mark of the Wild!",
        messageLow = "Mark of the Wild expiring (%ss left)",
        mustNotRest = true,
    },
    { id = "druid_rebirth_seeds", reagents = REBIRTH_SEEDS, family = REBIRTH, fallbackName = "Rebirth reagents", mustRest = true },
    { id = "druid_gift_reagents", reagents = GIFT_REAGENTS, family = GIFT_OF_THE_WILD, fallbackName = "Gift of the Wild reagents", mustRest = true },
}

-- Vendor reagents: not needed with the Legacy perk "Reagent Economy"
local function CheckReagent(config)
    if not API.KnowsFamily(config.family) or API.HasReagentEconomy() then return nil end
    local count, name = API.CountReagentForKnownSpell(config.reagents)
    if count < Prepped:GetRuleThreshold(config.id) then
        return string.format("Low on %s (%d left)", name or config.fallbackName, count), { name = name or config.fallbackName, count = count }
    end
    return nil
end

local checks = {
    druid_rebirth_seeds = CheckReagent,
    druid_gift_reagents = CheckReagent,
}

function checks.druid_mark(config)
    if API.IsTraveling() then return nil end
    if not (API.KnowsFamily(MARK_OF_THE_WILD) or API.KnowsFamily(GIFT_OF_THE_WILD)) then return nil end
    return Prepped:CheckTimedBuff(config.id, IsMarkOfTheWild, config.message, config.messageLow)
end

function DruidReminders.CheckReminders()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "DRUID" then return end
    Prepped:RunReminders(druidReminders, checks)
end

if Prepped then
    Prepped:RegisterReminderModule(DruidReminders)
end
