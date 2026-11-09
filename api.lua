-- api.lua
-- WoW Forever helpers shared by the reminder modules.
--
-- Spells are identified by spell ID; their names come from the client
-- (C_Spell.GetSpellName), so detection works in every client language.
-- Buff data can be "secret" (unreadable by addons) while Blizzard's combat
-- restrictions are active; the buff helpers report that as "unknown".

local _, ns = ...
local API = {}
ns.API = API

local GetTime = GetTime

------------------------------------------------------------------------
-- Secret values
------------------------------------------------------------------------
local issecretvalue = issecretvalue
local canaccesstable = canaccesstable

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end
API.IsSecret = IsSecret

-- True while Blizzard hides most buff data from addons (combat, encounters, PvP).
function API.AreAurasRestricted()
    local ok, restricted = pcall(C_Secrets.ShouldAurasBeSecret)
    return ok and restricted == true
end

local SECRECY_LABELS = {
    [0] = "always visible",   -- Enum.SecrecyLevel.NeverSecret
    [1] = "always hidden",    -- Enum.SecrecyLevel.AlwaysSecret
    [2] = "hidden in combat", -- Enum.SecrecyLevel.ContextuallySecret
}

-- How a spell's buff behaves under combat restrictions (for /prepped debug).
function API.DescribeAuraSecrecy(spellID)
    local ok, level = pcall(C_Secrets.GetSpellAuraSecrecy, spellID)
    if not ok or level == nil then return "unknown" end
    return SECRECY_LABELS[level] or ("level " .. tostring(level))
end

------------------------------------------------------------------------
-- Spell families
------------------------------------------------------------------------
-- A family groups the spell IDs that count as one thing: every rank of a
-- spell, or a set like "all seals". The client turns the IDs into localized
-- names, which also cover ranks that aren't listed.
--   opts.class          class token the family belongs to (debug grouping)
--   opts.aura           the family is a buff on the player (debug: secrecy)
--   opts.englishNames   fallback names for spells whose Forever ID is unknown
--   opts.englishPattern fallback Lua pattern (e.g. new Forever seals)
-- English fallbacks only ever match on English clients.
local families = {}

function API.SpellFamily(label, ids, opts)
    opts = opts or {}
    local family = {
        label = label,
        ids = ids,
        idSet = {},
        class = opts.class,
        isAura = opts.aura == true,
        englishNames = opts.englishNames,
        englishPattern = opts.englishPattern,
    }
    for _, id in ipairs(ids) do family.idSet[id] = true end
    families[#families + 1] = family
    return family
end

local function GetFamilyNames(family)
    if family.names then return family.names end
    local names = {}
    for _, id in ipairs(family.ids) do
        local name = C_Spell.GetSpellName(id)
        if name then names[name] = true end
    end
    for _, name in ipairs(family.englishNames or {}) do names[name] = true end
    if next(names) ~= nil then family.names = names end -- retry later if nothing resolved yet
    return names
end

function API.FamilyMatches(family, name, spellId)
    if spellId ~= nil and family.idSet[spellId] then return true end
    if name ~= nil then
        if GetFamilyNames(family)[name] then return true end
        if family.englishPattern and name:find(family.englishPattern) then return true end
    end
    return false
end

-- matcher(name, spellId) -> bool for any of the given families
function API.Matcher(...)
    local list = { ... }
    return function(name, spellId)
        for _, family in ipairs(list) do
            if API.FamilyMatches(family, name, spellId) then return true end
        end
        return false
    end
end

------------------------------------------------------------------------
-- Spellbook (cached; rebuilt on SPELLS_CHANGED and every few seconds)
------------------------------------------------------------------------
local SPELL_CACHE_TTL = 10
local spellCache, spellIDSet, spellCacheTime, spellCacheGeneration = nil, nil, 0, 0

-- Returns { [spellName] = { spellID, ... } } for every learned player spell.
local function GetSpellCache()
    local now = GetTime()
    if spellCache and (now - spellCacheTime) < SPELL_CACHE_TTL then
        return spellCache
    end

    local cache, idSet = {}, {}
    local bank = Enum.SpellBookSpellBank.Player
    local learned = Enum.SpellBookItemType.Spell -- FutureSpell = listed but not learned yet
    for lineIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
        if line then
            for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                if info and info.itemType == learned and not info.isOffSpec and info.name and info.name ~= "" then
                    local ids = cache[info.name]
                    if not ids then
                        ids = {}
                        cache[info.name] = ids
                    end
                    local id = info.spellID or info.actionID
                    ids[#ids + 1] = id
                    if id then idSet[id] = true end
                end
            end
        end
    end

    spellCache, spellIDSet, spellCacheTime = cache, idSet, now
    spellCacheGeneration = spellCacheGeneration + 1
    if next(cache) == nil then
        -- Spellbook not loaded yet (early login): retry soon instead of caching "nothing known".
        spellCacheTime = now - SPELL_CACHE_TTL + 1
    end
    return cache
end

function API.KnowsFamily(family)
    GetSpellCache()
    if family.knownGeneration == spellCacheGeneration then
        return family.known
    end

    local known = false
    for _, id in ipairs(family.ids) do
        if C_SpellBook.IsSpellKnown(id) then
            known = true
            break
        end
    end
    if not known then
        for name, ids in pairs(spellCache) do
            for _, id in ipairs(ids) do
                if API.FamilyMatches(family, name, id) then
                    known = true
                    break
                end
            end
            if known then break end
        end
    end

    family.known, family.knownGeneration = known, spellCacheGeneration
    return known
end

-- True if this exact spell ID (e.g. one rank of a spell) is learned.
function API.KnowsSpell(spellID)
    GetSpellCache()
    return spellIDSet[spellID] == true or C_SpellBook.IsSpellKnown(spellID)
end

-- For spells whose reagent depends on the rank you know.
--   options: { { spells = { spellID, ... }, item = itemID, name = "Reagent" }, ... }, best first
-- Returns the first option with a learned spell, or nil.
function API.PickByKnownSpell(options)
    for _, option in ipairs(options) do
        for _, spellID in ipairs(option.spells) do
            if API.KnowsSpell(spellID) then return option end
        end
    end
    return nil
end

-- Count and name of the reagent for the best learned option. If the spell is
-- learned under an ID that isn't listed, every listed reagent counts (name nil).
function API.CountReagentForKnownSpell(options)
    local option = API.PickByKnownSpell(options)
    if option then
        return C_Item.GetItemCount(option.item), option.name
    end
    local items = {}
    for i, entry in ipairs(options) do items[i] = entry.item end
    return API.CountItems(items), nil
end

-- predicate(spellName, spellID) -> bool. Returns the matching learned spell IDs.
function API.GetKnownSpellIDsMatching(predicate)
    local result = {}
    for name, ids in pairs(GetSpellCache()) do
        for _, id in ipairs(ids) do
            if predicate(name, id) then
                result[#result + 1] = id
            end
        end
    end
    return result
end

------------------------------------------------------------------------
-- Player buffs
------------------------------------------------------------------------
local MAX_AURAS = 255

local function SpellAuraMayBeSecret(spellID)
    local ok, secret = pcall(C_Secrets.ShouldSpellAuraBeSecret, spellID)
    return (not ok) or secret ~= false
end

-- Some auras were unreadable and none matched. "Missing" is still reliable if
-- every learned spell that could provide the buff is flagged never-secret:
-- that buff would have been readable had it been present.
local function MissingIsReliable(matcher)
    local ids = API.GetKnownSpellIDsMatching(matcher)
    if #ids == 0 then return false end
    for _, id in ipairs(ids) do
        if SpellAuraMayBeSecret(id) then return false end
    end
    return true
end

local function ScanPlayerBuffs(matcher)
    local sawSecret = false
    for index = 1, MAX_AURAS do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
        if not aura then break end

        if canaccesstable and not canaccesstable(aura) then
            sawSecret = true
        else
            local name, spellId = aura.name, aura.spellId
            if IsSecret(name) or IsSecret(spellId) then
                sawSecret = true
            elseif matcher(name, spellId) then
                local expirationTime = aura.expirationTime
                if expirationTime == nil or IsSecret(expirationTime) or expirationTime <= 0 then
                    return "present", nil
                end
                return "present", expirationTime - GetTime()
            end
        end
    end

    if sawSecret and not MissingIsReliable(matcher) then
        return "unknown"
    end
    return "missing"
end

-- Looks for a helpful aura on the player.
--   matcher(name, spellId) -> bool. Only called with readable (non-secret) values.
-- Returns one of:
--   "present", secondsLeft  (secondsLeft is nil for buffs without a known expiry)
--   "missing"
--   "unknown"               (buff data is hidden right now; don't warn)
function API.FindPlayerBuff(matcher)
    -- While buff data is hidden (in combat), Forever refuses add-on aura scans
    -- outright ("Auras cannot be accessed when secret"): don't even try.
    if API.AreAurasRestricted() then
        return "unknown"
    end
    local ok, state, remaining = pcall(ScanPlayerBuffs, matcher)
    if not ok then
        -- Most likely restricted buff data; kept for /prepped debug.
        API.lastBuffScanError = state
        return "unknown"
    end
    return state, remaining
end

------------------------------------------------------------------------
-- Weapon enchants
------------------------------------------------------------------------
-- In Forever, poisons, shaman imbues and warlock stones are "Imbue" enchants;
-- sharpening stones and oils are "Temporary" enchants and can sit on the same
-- weapon, so only Imbue enchants count as a poison/imbue.
local ENCHANT_IMBUE = (Enum.ItemEnchantType and Enum.ItemEnchantType.Imbue) or 3

local ENCHANT_TYPE_LABELS = { [0] = "none", [1] = "permanent", [2] = "temporary", [3] = "imbue" }

-- Raw enchant list for a weapon slot (Enum.WeaponSlot.MainHand/OffHand/Ranged).
function API.GetWeaponEnchantList(slot)
    local ok, list = pcall(C_Item.GetWeaponEnchantInfo, slot)
    return (ok and type(list) == "table") and list or {}
end

function API.DescribeEnchantType(enchantType)
    return ENCHANT_TYPE_LABELS[enchantType] or tostring(enchantType)
end

local function FindImbue(slot)
    for _, enchant in ipairs(API.GetWeaponEnchantList(slot)) do
        if enchant.hasEnchant and enchant.enchantType == ENCHANT_IMBUE then
            local msLeft = enchant.timeLeft
            if msLeft and msLeft <= 0 then msLeft = nil end
            return true, msLeft
        end
    end
    return false, nil
end

-- Returns hasMainHand, mainHandMsLeft, hasOffHand, offHandMsLeft for
-- poisons / imbues (msLeft is nil when the enchant has no known expiry).
function API.GetWeaponImbues()
    local hasMH, mhMs = FindImbue(Enum.WeaponSlot.MainHand)
    local hasOH, ohMs = FindImbue(Enum.WeaponSlot.OffHand)
    return hasMH, mhMs, hasOH, ohMs
end

------------------------------------------------------------------------
-- Skills, reagents, bags, consumables
------------------------------------------------------------------------
-- Still gaining levels: below the max level (as Forever's own UI works it out)
-- and experience not switched off.
function API.IsLeveling()
    local maxLevel = math.min(GetMaxLevelForPlayerExpansion() or 60, GetMaxPlayerLevel() or 60)
    return UnitLevel("player") < maxLevel and not IsXPUserDisabled()
end

-- "Name id" for each buff on you, for /prepped debug (nil while buffs are hidden).
function API.ListPlayerBuffs()
    if API.AreAurasRestricted() then return nil end
    local ok, result = pcall(function()
        local list = {}
        for index = 1, MAX_AURAS do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
            if not aura then break end
            if not (IsSecret(aura.name) or IsSecret(aura.spellId)) then
                list[#list + 1] = string.format("%s %s", tostring(aura.name), tostring(aura.spellId))
            end
        end
        return list
    end)
    return ok and result or nil
end

-- Total count of the given items in your bags.
function API.CountItems(itemIDs)
    local total = 0
    for _, itemID in ipairs(itemIDs) do
        total = total + C_Item.GetItemCount(itemID)
    end
    return total
end

-- Rank of a skill line (e.g. 40 = Poisons), 0 when not learned.
function API.GetSkillRank(skillLineID)
    local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, skillLineID)
    return (ok and info and info.rank) or 0
end

-- The Legacy perk "Reagent Economy" removes vendor reagents from class abilities.
local REAGENT_ECONOMY_SPELL_ID = 1262650
local LEGACY_CONSTANTS = Constants and Constants.LegacyConsts
local LEGACY_TREE_IDS = {
    (LEGACY_CONSTANTS and LEGACY_CONSTANTS.LEGACY_TREE_PROFESSIONS_ID) or 1187,
    (LEGACY_CONSTANTS and LEGACY_CONSTANTS.LEGACY_TREE_ADVENTURE_ID) or 1188,
    (LEGACY_CONSTANTS and LEGACY_CONSTANTS.LEGACY_TREE_PROGRESSION_ID) or 1189,
}
local REAGENT_ECONOMY_CACHE_TTL = 30
local reagentEconomy, reagentEconomySource, reagentEconomyTime = nil, nil, 0

local function LegacyTreesHavePerk(spellID)
    for _, treeID in ipairs(LEGACY_TREE_IDS) do
        local configID = C_Traits.GetConfigIDByTreeID(treeID)
        if configID then
            for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
                local node = C_Traits.GetNodeInfo(configID, nodeID)
                if node and (node.ranksPurchased or 0) > 0 and node.activeEntry then
                    local entry = C_Traits.GetEntryInfo(configID, node.activeEntry.entryID)
                    local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                    if definition and (definition.spellID == spellID or definition.overriddenSpellID == spellID) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- Returns hasPerk, howItWasDetected
function API.HasReagentEconomy()
    local now = GetTime()
    if reagentEconomy ~= nil and (now - reagentEconomyTime) < REAGENT_ECONOMY_CACHE_TTL then
        return reagentEconomy, reagentEconomySource
    end

    local has, source = false, nil
    if C_SpellBook.IsSpellKnown(REAGENT_ECONOMY_SPELL_ID) then
        has, source = true, "known spell"
    else
        local ok, inTree = pcall(LegacyTreesHavePerk, REAGENT_ECONOMY_SPELL_ID)
        if ok and inTree then
            has, source = true, "Legacy tree"
        elseif not API.AreAurasRestricted() then
            local auraOk, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, REAGENT_ECONOMY_SPELL_ID)
            if auraOk and aura then has, source = true, "aura" end
        end
    end

    reagentEconomy, reagentEconomySource, reagentEconomyTime = has, source, now
    return has, source
end

-- Backpack + equipped bags (and the reagent bag, if the client has one).
function API.NumBags()
    return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

local DRINK = API.SpellFamily("Drink", { 430, 431, 432, 1133, 1135, 1137 }, { englishNames = { "Drink" } })

-- True for drinks (water): their use effect is the "Drink" spell.
function API.IsDrinkItem(itemID)
    local spellName, spellID = C_Item.GetItemSpell(itemID)
    if spellName == nil and spellID == nil then return false end
    return API.FamilyMatches(DRINK, spellName, spellID)
end

------------------------------------------------------------------------
-- Talent trees (cached; rebuilt on talent events and every few seconds)
------------------------------------------------------------------------
-- Forever: one Traits tree per class, split into groups (Holy/Prot/Ret, ...),
-- returned in the classic tree order (confirmed in game: Arcane/Fire/Frost).
local TALENT_CACHE_TTL = 5
local talentCache, talentCacheTime = nil, 0

local function ReadTalentTrees()
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then
        configID = C_SpecializationInfo.GetCombatConfigIDForSpecGroup(C_SpecializationInfo.GetActiveSpecGroup())
    end
    if not configID then return nil end

    local configInfo = C_Traits.GetConfigInfo(configID)
    local treeID = configInfo and configInfo.treeIDs and configInfo.treeIDs[1]
    if not treeID then return nil end

    local displayInfos = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
    if not displayInfos or #displayInfos == 0 then return nil end

    local trees = {}
    for i, display in ipairs(displayInfos) do
        trees[i] = { groupID = display.groupID, name = display.displayName, order = display.orderIndex or i, index = i, points = 0 }
    end
    table.sort(trees, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.index < b.index
    end)

    local groupIDs = {}
    for i, tree in ipairs(trees) do groupIDs[i] = tree.groupID end
    for _, groupInfo in ipairs(C_Traits.GetGroupCurrencyInfo(configID, groupIDs) or {}) do
        local currency = groupInfo.currencyInfos and groupInfo.currencyInfos[1]
        for _, tree in ipairs(trees) do
            if tree.groupID == groupInfo.traitNodeGroupID then
                tree.points = (currency and currency.spent) or 0
            end
        end
    end
    return trees
end

-- Returns a list of { points = n, name = s } in talent-tree order, or nil.
function API.GetTalentTrees()
    local now = GetTime()
    if talentCache ~= nil and (now - talentCacheTime) < TALENT_CACHE_TTL then
        return talentCache or nil
    end

    local ok, trees = pcall(ReadTalentTrees)
    if not ok then
        API.lastTalentError = trees
        trees = nil
    end

    talentCache, talentCacheTime = trees or false, now
    return trees
end

-- Index of the tree with strictly the most points; nil if no points or a tie.
function API.GetPrimaryTalentTree()
    local trees = API.GetTalentTrees()
    if not trees then return nil end
    local best, bestPoints, tied = nil, 0, false
    for index, tree in ipairs(trees) do
        if tree.points > bestPoints then
            best, bestPoints, tied = index, tree.points, false
        elseif tree.points == bestPoints and bestPoints > 0 then
            tied = true
        end
    end
    if tied then return nil end
    return best
end

------------------------------------------------------------------------
-- Cache invalidation and events
------------------------------------------------------------------------
function API.InvalidateCaches()
    spellCache = nil
    talentCache = nil
    reagentEconomy = nil
end

local function IsEventValid(event)
    if C_EventUtils and C_EventUtils.IsEventValid then
        return C_EventUtils.IsEventValid(event)
    end
    return true
end

-- Registering an unknown event raises an error, so be defensive about
-- events Blizzard might rename in a future patch.
function API.RegisterEvent(frame, event)
    if not IsEventValid(event) then return false end
    return (pcall(frame.RegisterEvent, frame, event))
end

function API.RegisterUnitEvent(frame, event, ...)
    if not IsEventValid(event) then return false end
    return (pcall(frame.RegisterUnitEvent, frame, event, ...))
end

------------------------------------------------------------------------
-- Debug helpers
------------------------------------------------------------------------
function API.GetClientLabel()
    local version, build, _, interface = GetBuildInfo()
    return string.format("WoW Forever %s (build %s, interface %s), locale %s",
        tostring(version), tostring(build), tostring(interface), tostring(GetLocale()))
end

-- "Family: id" for every spell ID the client doesn't know (wrong or removed ID).
function API.GetUnresolvedSpellIDs()
    local result = {}
    for _, family in ipairs(families) do
        for _, id in ipairs(family.ids) do
            if not C_Spell.GetSpellName(id) then
                result[#result + 1] = family.label .. " " .. id
            end
        end
    end
    return result
end

-- Learned spells of this class that Prepped recognises by name but whose spell
-- ID isn't listed (e.g. a Forever-only spell or rank): "Name id", for /prepped debug.
function API.GetUnlistedNameMatches(classToken)
    local result, seen = {}, {}
    for name, ids in pairs(GetSpellCache()) do
        for _, id in ipairs(ids) do
            for _, family in ipairs(families) do
                if family.class == classToken and not family.idSet[id] and not seen[id]
                    and API.FamilyMatches(family, name, id) then
                    seen[id] = true
                    result[#result + 1] = string.format("%s %d", name, id)
                end
            end
        end
    end
    table.sort(result)
    return result
end

-- Buff families for a class, each with the learned spell IDs that provide it.
function API.GetAuraFamiliesForClass(classToken)
    local result = {}
    for _, family in ipairs(families) do
        if family.isAura and family.class == classToken then
            local ids = API.GetKnownSpellIDsMatching(function(name, id) return API.FamilyMatches(family, name, id) end)
            result[#result + 1] = { label = family.label, knownIDs = ids }
        end
    end
    return result
end
