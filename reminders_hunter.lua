-- Hunter-specific reminders module
local _, ns = ...
local API = ns.API

local HunterReminders = {}

local TAME_BEAST = API.SpellFamily("Tame Beast", { 1515 }, { class = "HUNTER" })
local ASPECTS = API.SpellFamily("Aspects", {
    13165, 14318, 14319, 14320, 14321, 14322, 25296, -- Aspect of the Hawk
    13163,                                            -- Aspect of the Monkey
    5118,                                             -- Aspect of the Cheetah
    13159,                                            -- Aspect of the Pack
    13161,                                            -- Aspect of the Beast
    20043, 20190,                                     -- Aspect of the Wild
}, { class = "HUNTER", aura = true })

local hunterReminders = {
    {
        id = "hunter_no_ammo",
        message = "No ammo equipped",
        noAmmoCheck = true,
    },
    {
        id = "hunter_ammo_critical",
        message = "Critically low on ammo (%s left)",
        ammoCheck = true,
        mustNotRest = true,
        minCount = 200,
    },
    {
        id = "hunter_ammo_low",
        message = "Low on ammo (%s left)",
        ammoCheck = true,
        mustRest = true,
        minCount = 1000,
    },
    {
        id = "hunter_aspect",
        message = "Buff missing: Aspect",
        mustNotRest = true,
        isMountedOnly = true,
        buffFamily = ASPECTS,
    },
    {
        id = "hunter_no_pet",
        message = "No pet active",
        mustNotRest = true,
        petCheck = true,
    },
    {
        id = "hunter_pet_unhappy",
        message = "Pet is unhappy",
        petHappinessCheck = true,
    },
    {
        id = "hunter_pet_food",
        message = "Low on pet food (%s left)",
        mustRest = true,
        petFoodCheck = true,
    },
}

local IsAspect = API.Matcher(ASPECTS)

-- Counts the food in your bags that your current pet will eat.
local function GetPetFoodCount()
    if not UnitExists("pet") then return nil end
    local foodTypes = C_PetInfo.GetPetFoodTypes()
    if not foodTypes or #foodTypes == 0 then return nil end

    local count = 0
    for bag = 0, API.NumBags() do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and C_PetInfo.CanPetEatItem(info.itemID) then
                count = count + (info.stackCount or 1)
            end
        end
    end
    return count
end

function HunterReminders.CheckReminders()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "HUNTER" then return end
    local isResting = IsResting()
    local criticalTriggered = false
    local ammoCount = Prepped:GetAmmoCount()

    for _, config in ipairs(hunterReminders) do
        if not (Prepped and config.id and not Prepped:IsRuleEnabled(config.id)) then
            local trigger = true
            local displayMessage = config.message
            local value -- amount for the group message (Prepped:BuildGroupMessage)
            if config.mustRest and not Prepped:IsSupplyTime() then trigger = false end
            if config.mustNotRest and isResting then trigger = false end

            -- If we already showed a "No Ammo" or "Critical" warning, skip "Low"
            if config.id == "hunter_ammo_low" and criticalTriggered then
                trigger = false
            end

            -- Ammo Logic
            if trigger and config.ammoCheck then
                -- Suppress Low/Crit if count is 0 (handled by hunter_no_ammo) or if no weapon (nil)
                if not ammoCount or ammoCount == 0 then
                    trigger = false
                else
                    local userThreshold = 0
                    if Prepped and Prepped.GetRuleThreshold then
                        userThreshold = Prepped:GetRuleThreshold(config.id)
                    end

                    local threshold = userThreshold
                    if isResting then
                        threshold = math.max(userThreshold, config.minCountResting or 0)
                    end

                    if ammoCount >= threshold then
                        trigger = false
                    else
                        -- If this is the critical warning and it triggered, mark it
                        if config.id == "hunter_ammo_critical" then
                            criticalTriggered = true
                        end
                    end
                    displayMessage = string.format(config.message, ammoCount)
                    value = ammoCount
                end
            end

            -- No Ammo Check
            if trigger and config.noAmmoCheck then
                if ammoCount ~= 0 then -- count == nil (no weapon) or count > 0 (has ammo)
                    trigger = false
                else
                    -- If "No Ammo" triggered, also treat it as "critical" to suppress "Low"
                    criticalTriggered = true
                end
            end

            -- Aspect Logic
            if trigger and config.buffFamily then
                if not API.KnowsFamily(config.buffFamily) then trigger = false end
                -- Don't show aspect reminder when mounted
                if trigger and config.isMountedOnly and IsMounted() then trigger = false end
                -- "present" or "unknown" (buff data hidden in combat): no warning
                if trigger and API.FindPlayerBuff(IsAspect) ~= "missing" then trigger = false end
            end

            -- Pet Logic
            if trigger and config.petCheck then
                if IsMounted() then
                    trigger = false
                elseif not API.KnowsFamily(TAME_BEAST) then
                    trigger = false
                elseif UnitExists("pet") and not UnitIsDead("pet") then
                    trigger = false
                end
            end

            -- Happiness Logic
            if trigger and config.petHappinessCheck then
                if UnitExists("pet") then
                    local happiness = C_PetInfo.GetPetHappiness()
                    -- happiness: 1 = unhappy, 2 = content, 3 = happy (nil = not available)
                    if happiness == nil or happiness == 3 then
                        trigger = false
                    end
                else
                    trigger = false
                end
            end

            -- Pet Food Logic
            if trigger and config.petFoodCheck then
                local count = GetPetFoodCount()
                if count == nil then
                    trigger = false
                else
                    local threshold = 20
                    if Prepped and Prepped.GetRuleThreshold then
                        threshold = Prepped:GetRuleThreshold(config.id)
                    end
                    if count >= threshold then
                        trigger = false
                    else
                        displayMessage = string.format(config.message, count or 0)
                        value = count
                    end
                end
            end

            if trigger then
                Prepped:ShowReminder(displayMessage, config.id, value)
            end
        end
    end
end

if Prepped then
    Prepped:RegisterReminderModule(HunterReminders)
end
