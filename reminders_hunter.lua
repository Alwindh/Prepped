-- reminders_hunter.lua
-- Hunter reminders: ammo, Aspects, the pet (out, fed, Growl in groups) and pet food.

local _, ns = ...
local API, L, Action = ns.API, ns.L, ns.Action
local Prepped = ns.Prepped
local format = string.format

local HAWK = { 13165, 14318, 14319, 14320, 14321, 14322, 25296 }
local MONKEY, CHEETAH, PACK, BEAST, WILD = { 13163 }, { 5118 }, { 13159 }, { 13161 }, { 20043, 20190 }

local function Join(...)
    local all = {}
    for i = 1, select("#", ...) do
        for _, id in ipairs((select(i, ...))) do all[#all + 1] = id end
    end
    return all
end

local TAME_BEAST = API.SpellFamily("Tame Beast", { 1515 }, { class = "HUNTER" })
local ASPECTS = API.SpellFamily("Aspects", Join(HAWK, MONKEY, CHEETAH, PACK, BEAST, WILD), { class = "HUNTER", aura = true })
local GROWL = API.SpellFamily("Growl", { 2649, 14916, 14917, 14918, 14919, 14920, 14921 }, { class = "HUNTER" })

local IsAspect = API.Matcher(ASPECTS)
local IsGrowl = API.Matcher(GROWL)

local CALL_PET, REVIVE_PET, FEED_PET = 883, 982, 6991
local PET_UNHAPPY, PET_HAPPY = 1, 3 -- C_PetInfo.GetPetHappiness: 1 = unhappy, 2 = content, 3 = happy

-- Food in your bags that your current pet will eat: count, bag, slot, itemID of
-- the first stack. nil without a pet.
local function PetFood()
    if not UnitExists("pet") then return nil end
    local foodTypes = API.GetPetFoodTypes()
    if not foodTypes or #foodTypes == 0 then return nil end
    return API.CountBagItemsWhere("petfood", API.CanPetEatItem)
end

local function PetIsDead()
    return UnitExists("pet") and UnitIsDead("pet") and true or false
end

Prepped:RegisterModule({
    class = "HUNTER",
    group = "Hunter",
    reminders = {
        {
            id = "hunter_no_ammo", label = L["No Ammo Equipped"],
            description = L["Warns when you have a ranged weapon equipped but no ammo in your ammo slot."],
            announce = { L["out of ammo"], L["buy more ammo"] },
            icon = Prepped.AmmoIcon,
            check = function() return Prepped:CheckNoAmmo() end,
        },
        {
            id = "hunter_ammo_critical", label = L["Critical Ammo"], defaultThreshold = 200, unit = "count", range = { 0, 1000, 50 },
            description = L["Warns while you're out adventuring when your ammo drops below this."],
            announce = { L["low on ammo ({count} left)"], L["buy more ammo"] },
            adventuring = true,
            icon = Prepped.AmmoIcon,
            check = function(rule) return Prepped:CheckAmmoBelow(rule, true) end,
        },
        {
            id = "hunter_ammo_low", label = L["Low Ammo"], defaultThreshold = 1000, unit = "count", range = { 0, 4000, 100 },
            description = L["While resting, warns when your ammo drops below this."],
            announce = { L["low on ammo ({count} left)"], L["buy more ammo"] },
            supply = true,
            suppressedBy = { "hunter_no_ammo", "hunter_ammo_critical" },
            icon = Prepped.AmmoIcon,
            check = function(rule) return Prepped:CheckAmmoBelow(rule) end,
        },
        {
            -- Clicking casts the Aspect you had up last (not Cheetah or Pack, which are for travelling).
            id = "hunter_aspect", label = L["Missing Aspect"],
            description = L["Reminds you to have an Aspect up. Clicking it casts the one you had up last."],
            adventuring = true, noTravel = true,
            family = ASPECTS, prefer = { HAWK, MONKEY, WILD, BEAST },
            dontRemember = { [5118] = true, [13159] = true },
            check = function(rule)
                if not API.KnowsFamily(ASPECTS) then return nil end
                local name, spellID = Prepped:ChooseSpell(rule)
                return Prepped:CheckTimedBuff(rule, IsAspect, name), nil, API.GetSpellIcon(spellID)
            end,
            action = function(rule) return Action.Cast(select(2, Prepped:ChooseSpell(rule))) end,
        },
        {
            id = "hunter_no_pet", label = L["Missing Pet"],
            description = L["Reminds you to have your pet out if you know Tame Beast and aren't resting."],
            adventuring = true, noTravel = true,
            check = function()
                if not API.KnowsFamily(TAME_BEAST) then return nil end
                if UnitExists("pet") and not UnitIsDead("pet") then return nil end
                if PetIsDead() then return L["Revive your pet"], nil, API.GetSpellIcon(REVIVE_PET) end
                return L["Call your pet"], nil, API.GetSpellIcon(CALL_PET)
            end,
            action = function() return Action.Cast(PetIsDead() and REVIVE_PET or CALL_PET) end,
        },
        {
            -- Feed Pet can't be used in combat, so the reminder waits until you can act on it.
            id = "hunter_pet_unhappy", label = L["Unhappy Pet"],
            description = L["Reminds you to feed your pet when it isn't happy (out of combat). Clicking it feeds your pet food it eats from your bags."],
            outOfCombat = true,
            icon = function() return API.GetSpellIcon(FEED_PET) end,
            check = function()
                if not UnitExists("pet") then return nil end
                local happiness = API.GetPetHappiness()
                if happiness == nil or happiness == PET_HAPPY then return nil end
                return happiness == PET_UNHAPPY and L["Feed your pet (unhappy)"] or L["Feed your pet (content)"]
            end,
            action = function()
                local feedPet = C_Spell.GetSpellName(FEED_PET)
                local count, bag, slot, itemID = PetFood()
                if not (feedPet and count and count > 0) then return nil end
                return Action.Macro(format("/cast %s\n/use %d %d", feedPet, bag, slot),
                    format(L["Feed your pet %s"], API.GetItemName(itemID)))
            end,
        },
        {
            -- In dungeons and raids the tank holds threat; an autocast Growl takes it away.
            id = "hunter_pet_taunt", label = L["Growl on Autocast in Groups"],
            description = L["In a dungeon or raid group, warns when your pet's Growl is on autocast, so your pet doesn't take threat from the tank. Clicking it turns autocast off."],
            outOfCombat = true,
            check = function()
                if not (UnitExists("pet") and API.InGroupInstance()) then return nil end
                local name, spellID = API.FindAutocastPetAction(IsGrowl)
                if not name then return nil end
                return format(L["Turn off %s autocast"], name), nil, API.GetSpellIcon(spellID or GROWL.ids[1])
            end,
            action = function()
                local name = API.FindAutocastPetAction(IsGrowl)
                if not name then return nil end
                return Action.Macro("/petautocastoff " .. name, format(L["Turn off %s autocast"], name))
            end,
        },
        {
            id = "hunter_pet_food", label = L["Low Pet Food"], defaultThreshold = 20, unit = "count", range = { 0, 100, 5 },
            description = L["While resting, warns when you have less food your pet can eat than this."],
            announce = { L["low on pet food ({count} left)"], L["buy more pet food"] },
            supply = true,
            icon = function() return API.GetItemIcon(117) end,
            check = function(rule)
                local count = PetFood()
                if count and count < Prepped:GetRuleThreshold(rule.id) then
                    return format(L["Buy %s (%d left)"], L["pet food"], count), count
                end
            end,
        },
    },
})
