-- commands.lua
-- /prepped, the welcome line, the AddOns menu entry and /prepped debug.
-- The debug report stays in English: it is meant for bug reports.

local addonName, ns = ...
local API, L = ns.API, ns.L
local Prepped = ns.Prepped

local format, floor, min, max = string.format, math.floor, math.min, math.max

SLASH_PREPPED1 = "/prepped"
local DEFAULT_SNOOZE_MINUTES = 30
local COMMAND_COLOR = "|cffffff00%s|r"

local function Command(text)
    return format(COMMAND_COLOR, text)
end

function Prepped:OpenOptions(group)
    if not (ns.Options and ns.Options.Open(group)) then
        self:Print(L["The options failed to load; please report the output of /prepped debug."])
    end
end

-- Unlocks the reminders for moving (true), locks them (false) or toggles (nil).
function Prepped:SetMoving(unlocked)
    local Display = ns.Display
    if unlocked == nil then unlocked = not Display:IsUnlocked() end
    if unlocked and InCombatLockdown() then
        self:Print(L["You can't move the reminders in combat."])
        return
    end
    if Display:SetUnlocked(unlocked) then
        self:Print(L["Drag the reminders to move them. Right-click them or press Escape when you're done."])
    else
        self:Print(L["Reminders locked."])
    end
end

------------------------------------------------------------------------
-- /prepped debug: everything needed to check Prepped's view of this client
------------------------------------------------------------------------
local function DebugLine(fmt, ...)
    print("  " .. format(fmt, ...))
end

local function ListOrNone(list)
    return (list and #list > 0) and table.concat(list, ", ") or "none"
end

function Prepped:PrintDebugReport()
    local _, classToken = UnitClass("player")
    print("|cff00ff00Prepped Debug:|r")
    DebugLine("Client: %s", API.GetClientLabel())
    DebugLine("Buff data hidden right now: %s", tostring(API.AreAurasRestricted()))

    local trees = API.GetTalentTrees()
    if trees then
        local parts = {}
        for i, tree in ipairs(trees) do
            parts[#parts + 1] = format("%d. %s %d", i, tostring(tree.name or "?"), tree.points or 0)
        end
        DebugLine("Talent trees: %s (primary: %s)", table.concat(parts, ", "), tostring(API.GetPrimaryTalentTree()))
    else
        DebugLine("Talent trees: unavailable %s", tostring(API.lastTalentError or ""))
    end

    for _, slot in ipairs({ { "Main hand", Enum.WeaponSlot.MainHand }, { "Off hand", Enum.WeaponSlot.OffHand } }) do
        local parts = {}
        for _, enchant in ipairs(API.GetWeaponEnchantList(slot[2])) do
            if enchant.hasEnchant then
                parts[#parts + 1] = format("%s #%s (%ds)", API.DescribeEnchantType(enchant.enchantType),
                    tostring(enchant.enchantID), floor((enchant.timeLeft or 0) / 1000))
            end
        end
        DebugLine("%s enchants: %s", slot[1], ListOrNone(parts))
    end

    local rangedSlot = Prepped.RANGED_SLOT
    local rangedID = GetInventoryItemID("player", rangedSlot)
    if rangedID then
        local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(rangedID)
        local durability, maxDurability = GetInventoryItemDurability(rangedSlot)
        DebugLine("Ranged: item %s (class %s/%s), durability %s/%s, ammo count %s", tostring(rangedID),
            tostring(classID), tostring(subClassID), tostring(durability), tostring(maxDurability), tostring(self:GetAmmoCount()))
    else
        DebugLine("Ranged: none")
    end
    local average, worstSlot, worstPercent = API.GetDurability()
    DebugLine("Durability: average %d%%, lowest %s", floor(average),
        worstSlot and format("slot %d at %d%%", worstSlot, floor(worstPercent)) or "none")

    if classToken == "ROGUE" then
        DebugLine("Poisons skill rank: %d, Poisons spell known: %s", API.GetSkillRank(40), tostring(C_SpellBook.IsSpellKnown(2842)))
    elseif classToken == "DRUID" then
        DebugLine("Shapeshift form ID: %s", tostring(GetShapeshiftFormID()))
    elseif classToken == "HUNTER" or classToken == "WARLOCK" then
        DebugLine("Pet actions: %s", ListOrNone(API.ListPetActions()))
    end

    local hasPerk, source = API.HasReagentEconomy()
    DebugLine("Reagent Economy perk: %s%s", hasPerk and "yes" or "no", source and (" (" .. source .. ")") or "")
    local perks = API.GetLegacyPerks()
    DebugLine("Legacy perks: %s", perks and ListOrNone(perks) or "unavailable")
    local legacyCurrencies = API.GetLegacyCurrencies()
    if legacyCurrencies then
        local parts = {}
        for _, currency in ipairs(legacyCurrencies) do
            parts[#parts + 1] = format("tree %s currency %s: %s", tostring(currency.treeID), tostring(currency.currencyID),
                API.IsSecret(currency.quantity) and "hidden" or tostring(currency.quantity))
        end
        DebugLine("Unspent Legacy points: %s (%s)", tostring(API.GetUnspentLegacyPoints()), ListOrNone(parts))
    else
        DebugLine("Unspent Legacy points: unavailable")
    end
    DebugLine("Spells seen working without their reagent: %s", ListOrNone(API.GetReagentFreeSpells()))

    for _, family in ipairs(API.GetAuraFamiliesForClass(classToken)) do
        if #family.knownIDs > 0 then
            local seen, labels = {}, {}
            for _, id in ipairs(family.knownIDs) do
                local label = API.DescribeAuraSecrecy(id)
                if not seen[label] then
                    seen[label] = true
                    labels[#labels + 1] = label
                end
            end
            DebugLine("%s in combat: %s", family.label, table.concat(labels, " / "))
        end
    end

    local buffs = API.ListPlayerBuffs()
    DebugLine("Buffs on you: %s", buffs and ListOrNone(buffs) or "hidden right now")
    local bagFood, tooltipsNameBuff = API.DescribeBagFood()
    DebugLine("Food and drink in your bags: %s", ListOrNone(bagFood))
    DebugLine("Food tooltips name the food buff: %s", tooltipsNameBuff)

    DebugLine("Unknown spell IDs: %s", ListOrNone(API.GetUnresolvedSpellIDs()))
    DebugLine("Recognised by name, ID not listed: %s", ListOrNone(API.GetUnlistedNameMatches(classToken)))
    DebugLine("Group message when joining: %s", self:BuildGroupMessage() or "nothing to report")
    DebugLine("Snoozed: %s", ListOrNone(self:DescribeSnoozes()))

    local app = self:GetAppearance()
    local position = app.position
    DebugLine("Display: position %s, grows %s, icons %s, clickable %s, unlocked %s, text language %s",
        position and format("%d,%d", position.x, position.y) or "default", self:GetDisplayOption("growUp") and "up" or "down",
        tostring(self:GetDisplayOption("showIcons")), tostring(self:GetDisplayOption("clickable")),
        tostring(ns.Display:IsUnlocked()), tostring(ns.textLocale))

    local stats = self.checkStats
    if stats.totalMs > 0 then
        DebugLine("Reminder checks: %d (average %.3f ms, slowest %.3f ms)", stats.count, stats.totalMs / stats.count, stats.slowestMs)
    else
        DebugLine("Reminder checks: %d", stats.count)
    end
    if API.lastBuffScanError then
        DebugLine("Last buff scan error: %s", tostring(API.lastBuffScanError))
    end
end

------------------------------------------------------------------------
-- /prepped
------------------------------------------------------------------------
local function PrintHelp()
    Prepped:Print(L["commands:"])
    print("  " .. Command("/prepped") .. " - " .. L["options"])
    print("  " .. Command("/prepped move") .. " - " .. L["move the reminders"])
    print("  " .. Command("/prepped snooze [minutes]") .. " - "
        .. format(L["hide the reminders on screen for a while (default %d minutes)"], DEFAULT_SNOOZE_MINUTES))
    print("  " .. Command("/prepped unsnooze") .. " - " .. L["bring snoozed reminders back"])
    print("  " .. Command("/prepped debug") .. " - " .. L["what Prepped sees, for bug reports"])
end

SlashCmdList["PREPPED"] = function(msg)
    local command, argument = string.lower(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    if command == "debug" then
        Prepped:PrintDebugReport()
    elseif command == "snooze" then
        local minutes = min(max(floor(tonumber(argument) or DEFAULT_SNOOZE_MINUTES), 1), 24 * 60)
        local count = Prepped:Snooze(minutes)
        if count == 0 then
            Prepped:Print(L["There's nothing to snooze right now."])
        elseif count == 1 then
            Prepped:Print(format(L["Snoozed 1 reminder for %d minutes; %s brings it back."], minutes, Command("/prepped unsnooze")))
        else
            Prepped:Print(format(L["Snoozed %d reminders for %d minutes; %s brings them back."], count, minutes, Command("/prepped unsnooze")))
        end
    elseif command == "unsnooze" then
        local count = Prepped:Unsnooze()
        Prepped:Print(count == 1 and L["1 snoozed reminder is back."] or format(L["%d snoozed reminders are back."], count))
    elseif command == "move" then
        Prepped:SetMoving(nil)
    elseif command == "unlock" then
        Prepped:SetMoving(true)
    elseif command == "lock" then
        Prepped:SetMoving(false)
    elseif command == "help" then
        PrintHelp()
    else
        Prepped:OpenOptions()
    end
end

------------------------------------------------------------------------
-- AddOns menu (## AddonCompartmentFunc... in the TOC) and the welcome line
------------------------------------------------------------------------
function Prepped_OpenOptions()
    Prepped:OpenOptions()
end

function Prepped_OnCompartmentEnter(_, button)
    local count = Prepped.activeCount or 0
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("Prepped", 1, 1, 1)
    GameTooltip:AddLine(count == 1 and L["1 reminder on screen"] or format(L["%d reminders on screen"], count), 1, 0.82, 0)
    GameTooltip:AddLine(L["Click to open the options."], 0.65, 0.65, 0.65)
    GameTooltip:Show()
end

function Prepped_OnCompartmentLeave()
    GameTooltip:Hide()
end

local function GetAddonVersion()
    return C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
end

function Prepped:ShowWelcomeMessage()
    if not self:IsRuleEnabled("general_welcome") then return end
    print(format("|cff00ff00Prepped|r |cffffcc00v%s|r %s", GetAddonVersion(), format(L["loaded. Type %s for options."], Command("/prepped"))))
end
