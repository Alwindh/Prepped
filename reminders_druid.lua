-- reminders_druid.lua
-- Druid reminders: Mark of the Wild and the reagents for Rebirth and Gift of the Wild.

local _, ns = ...
local API, L, Action = ns.API, ns.L, ns.Action
local Prepped = ns.Prepped
local format = string.format

local MARK_OF_THE_WILD = API.SpellFamily("Mark of the Wild", { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }, { class = "DRUID", aura = true })
local GIFT_OF_THE_WILD = API.SpellFamily("Gift of the Wild", { 21849, 21850 }, { class = "DRUID", aura = true })
local REBIRTH = API.SpellFamily("Rebirth", { 20484, 20739, 20742, 20747, 20748 }, { class = "DRUID" })

local IsMarkOfTheWild = API.Matcher(MARK_OF_THE_WILD, GIFT_OF_THE_WILD)

-- Each rank uses its own reagent; highest rank first.
local REBIRTH_SEEDS = {
    { spells = { 20748 }, item = 17038, name = "Ironwood Seed" },
    { spells = { 20747 }, item = 17037, name = "Hornbeam Seed" },
    { spells = { 20742 }, item = 17036, name = "Ashwood Seed" },
    { spells = { 20739 }, item = 17035, name = "Stranglethorn Seed" },
    { spells = { 20484 }, item = 17034, name = "Maple Seed" },
}
local GIFT_REAGENTS = {
    { spells = { 21850 }, item = 17026, name = "Wild Thornroot" },
    { spells = { 21849 }, item = 17021, name = "Wild Berries" },
}

local function MarkSpell()
    return API.BestKnownFamilySpell(MARK_OF_THE_WILD) or API.BestKnownFamilySpell(GIFT_OF_THE_WILD)
end

-- Vendor reagents for the rank you know: hidden when not needed (Legacy perk
-- "Reagent Economy", ...). Learned under an unlisted ID, every listed reagent counts.
local function CheckReagent(rule)
    if not API.KnowsFamily(rule.family) or API.HasReagentEconomy() then return nil end
    local count, option = API.CountReagentForKnownSpell(rule.reagents)
    if option and not API.ReagentNeeded(option.item, option.spells, true) then return nil end
    if count >= Prepped:GetRuleThreshold(rule.id) then return nil end
    local name = option and API.GetItemName(option.item, option.name) or rule.fallbackName
    local value = rule.value or {}
    rule.value = value
    value.count, value.name = count, name
    return format(L["Buy %s (%d left)"], name, count), value, API.GetItemIcon(option and option.item or rule.reagents[1].item)
end

Prepped:RegisterModule({
    class = "DRUID",
    group = "Druid",
    reminders = {
        {
            id = "druid_mark", label = L["Missing Mark of the Wild"], hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 },
            description = L["Reminds you to keep Mark of the Wild (or Gift of the Wild) on yourself when not resting or travelling."],
            adventuring = true, noTravel = true,
            check = function(rule)
                local spellID = MarkSpell()
                if not spellID then return nil end
                return Prepped:CheckTimedBuff(rule, IsMarkOfTheWild, C_Spell.GetSpellName(spellID)), nil, API.GetSpellIcon(spellID)
            end,
            action = function() return Action.Cast(MarkSpell(), true) end,
        },
        {
            id = "druid_rebirth_seeds", label = L["Low Rebirth Seeds"], defaultThreshold = 5, unit = "count", range = { 0, 40, 1 },
            description = L["While resting, warns when you have fewer seeds for your highest Rebirth rank than this."],
            announce = { L["low on {name} ({count} left)"], L["buy more {name}"] },
            supply = true, reagents = REBIRTH_SEEDS, family = REBIRTH, fallbackName = L["Rebirth reagents"],
            check = CheckReagent,
        },
        {
            id = "druid_gift_reagents", label = L["Low Gift of the Wild Reagents"], defaultThreshold = 10, unit = "count", range = { 0, 100, 5 },
            description = L["While resting, warns when you have fewer reagents for your Gift of the Wild rank (Wild Berries or Wild Thornroot) than this."],
            announce = { L["low on {name} ({count} left)"], L["buy more {name}"] },
            supply = true, reagents = GIFT_REAGENTS, family = GIFT_OF_THE_WILD, fallbackName = L["Gift of the Wild reagents"],
            check = CheckReagent,
        },
    },
})
