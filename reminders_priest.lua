-- reminders_priest.lua
-- Priest-specific reminders for the Prepped addon

local _, ns = ...
local API = ns.API

local PriestReminders = {}

local FORTITUDE = API.SpellFamily("Power Word: Fortitude", { 1243, 1244, 1245, 2791, 10937, 10938 }, { class = "PRIEST", aura = true })
local PRAYER_OF_FORTITUDE = API.SpellFamily("Prayer of Fortitude", { 21562, 21564 }, { class = "PRIEST", aura = true })

local IsFortitudeBuff = API.Matcher(FORTITUDE, PRAYER_OF_FORTITUDE)

-- Reminder configuration
local priestReminders = {
    {
        id = "priest_fortitude",
        message = "Missing Power Word: Fortitude!",
        messageLow = "Fortitude expiring (%ss left)",
        mustNotRest = true,
    },
}

-- Main reminder check function
function PriestReminders.CheckReminders()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "PRIEST" then
        return
    end

    -- Get state variables
    local isResting = IsResting()
    local inCombat = UnitAffectingCombat("player") or (InCombatLockdown and InCombatLockdown())
    local isMounted = IsMounted()

    -- Process each reminder
    for _, config in ipairs(priestReminders) do
        if Prepped:IsRuleEnabled(config.id) then
            -- Apply filters
            local filterPassed = true
            if config.mustRest and not isResting then
                filterPassed = false
            end
            if config.mustNotRest and isResting then
                filterPassed = false
            end
            if config.inCombatOnly and not inCombat then
                filterPassed = false
            end

            if filterPassed then
                local trigger = false
                local displayMessage = config.message

                -- Check for Power Word: Fortitude
                if config.id == "priest_fortitude" then
                    -- Skip if mounted
                    if not isMounted then
                        -- Check if player knows Fortitude (Prayer or regular)
                        local knowsFortitude = API.KnowsFamily(PRAYER_OF_FORTITUDE) or API.KnowsFamily(FORTITUDE)

                        if knowsFortitude then
                            local state, remaining = API.FindPlayerBuff(IsFortitudeBuff)

                            if state == "missing" then
                                -- Buff is missing
                                trigger = true
                                displayMessage = config.message
                            elseif state == "present" and remaining and Prepped:IsLowEnabled(config.id) then
                                -- Check if buff is expiring soon
                                local threshold = Prepped:GetRuleThreshold(config.id, 60)
                                if remaining <= threshold then
                                    trigger = true
                                    displayMessage = string.format(config.messageLow, math.max(0, math.floor(remaining)))
                                end
                            end
                            -- "unknown": buff data hidden by combat restrictions, don't warn
                        end
                    end
                end

                -- Display the reminder if triggered
                if trigger then
                    local line = Prepped:GetNextLine()
                    if line then
                        line.text:SetText(displayMessage)
                        line:Show()
                    end
                end
            end
        end
    end
end

-- Register this module with the core system
if Prepped then
    Prepped:RegisterReminderModule(PriestReminders)
end
