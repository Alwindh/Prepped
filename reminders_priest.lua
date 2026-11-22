-- reminders_priest.lua
-- Priest reminders: Power Word: Fortitude, Inner Fire and candles.

local _, ns = ...
local API, L, Action = ns.API, ns.L, ns.Action
local Prepped = ns.Prepped
local format = string.format

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
    { spells = { 21564, 27681, 27683 }, item = 17029, name = "Sacred Candle" },
    { spells = { 21562 }, item = 17028, name = "Holy Candle" },
}

-- The spell clicking casts: Power Word: Fortitude (no reagent), else Prayer of Fortitude.
local function FortitudeSpell()
    return API.BestKnownFamilySpell(FORTITUDE) or API.BestKnownFamilySpell(PRAYER_OF_FORTITUDE)
end

Prepped:RegisterModule({
    class = "PRIEST",
    group = "Priest",
    reminders = {
        {
            id = "priest_fortitude", label = L["Missing Power Word: Fortitude"], hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 },
            description = L["Reminds you to keep Power Word: Fortitude (or Prayer of Fortitude) on yourself."],
            adventuring = true, noTravel = true,
            check = function(rule)
                local spellID = FortitudeSpell()
                if not spellID then return nil end
                return Prepped:CheckTimedBuff(rule, IsFortitudeBuff, C_Spell.GetSpellName(spellID)), nil, API.GetSpellIcon(spellID)
            end,
            action = function() return Action.Cast(FortitudeSpell(), true) end,
        },
        {
            id = "priest_inner_fire", label = L["Missing Inner Fire"], hasLowWarningToggle = true, defaultThreshold = 60, range = { 0, 600, 10 },
            description = L["Reminds you to have Inner Fire up when not resting."],
            adventuring = true, noTravel = true,
            check = function(rule)
                local spellID = API.BestKnownFamilySpell(INNER_FIRE)
                if not spellID then return nil end
                return Prepped:CheckTimedBuff(rule, IsInnerFire, C_Spell.GetSpellName(spellID)), nil, API.GetSpellIcon(spellID)
            end,
            action = function() return Action.Cast(API.BestKnownFamilySpell(INNER_FIRE)) end,
        },
        {
            -- Vendor reagent: hidden when not needed (Legacy perk "Reagent Economy", ...)
            id = "priest_candles", label = L["Low Candles"], defaultThreshold = 10, unit = "count", range = { 0, 100, 5 },
            description = L["While resting, warns when you have fewer candles than this for your Prayer spells: Sacred Candles once you know Prayer of Fortitude rank 2, Prayer of Spirit or Prayer of Shadow Protection, Holy Candles before that."],
            announce = { L["low on {name} ({count} left)"], L["buy more {name}"] },
            supply = true,
            check = function(rule)
                if API.HasReagentEconomy() then return nil end
                if not (API.KnowsFamily(PRAYER_OF_FORTITUDE) or API.KnowsFamily(PRAYER_OF_SPIRIT)
                    or API.KnowsFamily(PRAYER_OF_SHADOW_PROTECTION)) then
                    return nil
                end
                local count, option = API.CountReagentForKnownSpell(CANDLES)
                if option and not API.ReagentNeeded(option.item, option.spells, true) then return nil end
                if count >= Prepped:GetRuleThreshold(rule.id) then return nil end
                local name = option and API.GetItemName(option.item, option.name) or L["candles"]
                local value = rule.value or {}
                rule.value = value
                value.count, value.name = count, name
                return format(L["Buy %s (%d left)"], name, count), value, API.GetItemIcon(option and option.item or CANDLES[2].item)
            end,
        },
    },
})
