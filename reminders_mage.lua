-- Mage-specific reminders module
local MageReminders = {}

local mageReminders = {
    {
        id = "mage_powder",
        message = "LOW ARCANE POWDER (%s left!)", -- %s will be replaced by the number
        itemCheck = 17020, -- Arcane Powder
        minCount = 10,
        mustRest = true,
        requiredSpell = "Arcane Brilliance" 
    },
    {
        id = "mage_rune_teleport",
        message = "LOW RUNE OF TELEPORTATION (%s left!)",
        itemCheck = 17031, -- Rune of Teleportation
        minCount = 10,
        mustRest = true,
        requiredAnySpell = {
            "Teleport: Theramore",
            "Teleport: Stormwind", 
            "Teleport: Ironforge", 
            "Teleport: Darnassus", 
            "Teleport: Exodar", 
            "Teleport: Orgrimmar", 
            "Teleport: Undercity", 
            "Teleport: Thunder Bluff", 
            "Teleport: Stonard", 
            "Teleport: Silvermoon",
            "Teleport: Shattrath"
        }
    },
}

local lines = {}
local function CreateReminderLine(index)
    local container = _G.AlwinPackContainer
    local f = CreateFrame("Frame", nil, container)
    f:SetSize(400, 30)
    -- Align with other modules if possible, but for now just stacking them might overlap 
    -- if multiple modules trigger at once. 
    -- Ideally AlwinPackContainer handles layout, but the current design seems to have each module manage its own lines attached to the container.
    -- To avoid overlap, we might need a shared layout manager, but for now we follow the existing pattern.
    f:SetPoint("TOP", container, "TOP", 0, -(index - 1) * 32 - 100) -- Offset slightly to avoid hiding other class reminders on top? 
    -- Actually, usually only one class module is active per character.
    -- so sticking to -(index-1)*32 is fine.
    f:SetPoint("TOP", container, "TOP", 0, -(index - 1) * 32)
    
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    local txt = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    txt:SetPoint("CENTER")
    f.text = txt
    return f
end

local function IsSpellLearned(spellName)
    -- iterate spellbook
    for i = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(i)
        for j = offset + 1, offset + numSpells do
            local spellNameBook = GetSpellBookItemName(j, BOOKTYPE_SPELL)
            if spellNameBook == spellName then return true end
        end
    end
    return false
end

local function IsAnySpellLearned(spellList)
    for _, spell in ipairs(spellList) do
        if IsSpellLearned(spell) then return true end
    end
    return false
end

function MageReminders.CheckReminders()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "MAGE" then return end

    local isResting = IsResting()
    for _, line in ipairs(lines) do line:Hide() end

    local activeCount = 0
    for _, config in ipairs(mageReminders) do
        if not (AlwinPack and config.id and not AlwinPack:IsRuleEnabled(config.id)) then
            local trigger = true
            local displayMessage = config.message

            -- Resting check
            if config.mustRest and not isResting then trigger = false end

            -- Spell Learned Check
            if trigger and config.requiredSpell then
                if not IsSpellLearned(config.requiredSpell) then trigger = false end
            end

            -- Any Spell Learned Check
            if trigger and config.requiredAnySpell then
                if not IsAnySpellLearned(config.requiredAnySpell) then trigger = false end
            end

            -- Item Count Check
            if trigger and config.itemCheck then
                local count = GetItemCount(config.itemCheck)
                local threshold = config.minCount
                if AlwinPack and AlwinPack.GetRuleThreshold then
                     threshold = AlwinPack:GetRuleThreshold(config.id, config.minCount)
                end
                
                if count >= threshold then 
                    trigger = false 
                else
                    displayMessage = string.format(config.message, count)
                end
            end

            if trigger then
                activeCount = activeCount + 1
                if not lines[activeCount] then
                    lines[activeCount] = CreateReminderLine(activeCount)
                end
                lines[activeCount].text:SetText(displayMessage)
                lines[activeCount]:Show()
            end
        end
    end
end

if AlwinPack then
    AlwinPack:RegisterReminderModule(MageReminders)
end
