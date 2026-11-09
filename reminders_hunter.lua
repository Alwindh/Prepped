-- Hunter-specific reminders module
local _, ns = ...
local API = ns.API

local HunterReminders = { class = "HUNTER" }

local TAME_BEAST = API.SpellFamily("Tame Beast", { 1515 }, { class = "HUNTER" })
local ASPECTS = API.SpellFamily("Aspects", {
    13165, 14318, 14319, 14320, 14321, 14322, 25296, -- Aspect of the Hawk
    13163,                                            -- Aspect of the Monkey
    5118,                                             -- Aspect of the Cheetah
    13159,                                            -- Aspect of the Pack
    13161,                                            -- Aspect of the Beast
    20043, 20190,                                     -- Aspect of the Wild
}, { class = "HUNTER", aura = true })

local IsAspect = API.Matcher(ASPECTS)

local PET_HAPPY = 3 -- C_PetInfo.GetPetHappiness: 1 = unhappy, 2 = content, 3 = happy

local hunterReminders = {
    { id = "hunter_no_ammo", message = "No ammo equipped" },
    { id = "hunter_ammo_critical", message = "Critically low on ammo (%s left)", mustNotRest = true },
    {
        id = "hunter_ammo_low",
        message = "Low on ammo (%s left)",
        mustRest = true,
        suppressedBy = { "hunter_no_ammo", "hunter_ammo_critical" },
    },
    { id = "hunter_aspect", message = "Buff missing: Aspect", mustNotRest = true, noTravel = true },
    { id = "hunter_no_pet", message = "No pet active", mustNotRest = true, noTravel = true },
    -- Feed Pet can't be used in combat, so the reminder waits until you can act on it.
    { id = "hunter_pet_unhappy", message = "Pet is unhappy", outOfCombat = true },
    { id = "hunter_pet_food", message = "Low on pet food (%s left)", mustRest = true },
}

-- Food in your bags that your current pet will eat, counted once per change of
-- the bags (or of the pet); nil without a pet.
local petFoodCount, petFoodBagGeneration = 0, nil

local function AddPetFood(itemID, stackCount)
    if API.CanPetEatItem(itemID) then petFoodCount = petFoodCount + stackCount end
end

local function GetPetFoodCount()
    if not UnitExists("pet") then return nil end
    local foodTypes = API.GetPetFoodTypes()
    if not foodTypes or #foodTypes == 0 then return nil end
    local generation = API.GetBagGeneration()
    if petFoodBagGeneration ~= generation then
        petFoodCount = 0
        API.ForEachBagItem(AddPetFood)
        petFoodBagGeneration = generation
    end
    return petFoodCount
end

local checks = {}

function checks.hunter_no_ammo(config) return Prepped:CheckNoAmmo(config) end
function checks.hunter_ammo_critical(config) return Prepped:CheckAmmoBelow(config) end
checks.hunter_ammo_low = checks.hunter_ammo_critical

-- "present" or "unknown" (buff data hidden in combat): no warning
function checks.hunter_aspect(config)
    if not API.KnowsFamily(ASPECTS) then return nil end
    if API.FindPlayerBuff(IsAspect) == "missing" then return config.message end
    return nil
end

function checks.hunter_no_pet(config)
    if not API.KnowsFamily(TAME_BEAST) then return nil end
    if UnitExists("pet") and not UnitIsDead("pet") then return nil end
    return config.message
end

function checks.hunter_pet_unhappy(config)
    if not UnitExists("pet") then return nil end
    local happiness = API.GetPetHappiness()
    if happiness == nil or happiness == PET_HAPPY then return nil end
    return config.message
end

function checks.hunter_pet_food(config)
    local count = GetPetFoodCount()
    if count and count < Prepped:GetRuleThreshold(config.id) then
        return string.format(config.message, count), count
    end
    return nil
end

function HunterReminders.CheckReminders()
    Prepped:RunReminders(hunterReminders, checks)
end

if Prepped then
    Prepped:RegisterReminderModule(HunterReminders)
end
