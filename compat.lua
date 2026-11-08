-- compat.lua
-- API compatibility layer.
--
-- Prepped runs on two clients from one codebase:
--   * TBC Anniversary (interface 2050x): classic-style API.
--   * WoW Forever     (interface 1600x): Midnight-era API. Most legacy globals
--     (UnitAura, GetSpellInfo, GetItemInfo, spellbook tabs, talent tabs,
--     GetWeaponEnchantInfo, GetPetHappiness, ...) are gone, talents use the
--     Traits system, and buff data can be "secret" (unreadable by addons)
--     while Blizzard's combat restrictions are active.
--
-- Everything here is feature-detected rather than version-checked, so the
-- reminder modules can call one function and get the same answer on both.

local _, ns = ...
local Compat = {}
ns.Compat = Compat

local GetTime = GetTime

Compat.isForever = (WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT)

------------------------------------------------------------------------
-- Secret values
------------------------------------------------------------------------
local issecretvalue = issecretvalue
local canaccesstable = canaccesstable

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end
Compat.IsSecret = IsSecret

-- True while Blizzard hides most buff data from addons (combat, encounters,
-- PvP matches). Always false on clients without the restriction system.
function Compat.AreAurasRestricted()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, restricted = pcall(C_Secrets.ShouldAurasBeSecret)
        return ok and restricted == true
    end
    return false
end

------------------------------------------------------------------------
-- Spells and items
------------------------------------------------------------------------
function Compat.GetSpellName(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    elseif GetSpellInfo then
        return (GetSpellInfo(spellID))
    end
    return nil
end

function Compat.GetItemInfo(item)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(item)
    elseif GetItemInfo then
        return GetItemInfo(item)
    end
end

function Compat.GetItemInfoInstant(item)
    if C_Item and C_Item.GetItemInfoInstant then
        return C_Item.GetItemInfoInstant(item)
    elseif GetItemInfoInstant then
        return GetItemInfoInstant(item)
    end
end

function Compat.GetItemSpell(item)
    if C_Item and C_Item.GetItemSpell then
        return C_Item.GetItemSpell(item)
    elseif GetItemSpell then
        return GetItemSpell(item)
    end
end

function Compat.GetItemCount(item)
    local count
    if C_Item and C_Item.GetItemCount then
        count = C_Item.GetItemCount(item)
    elseif GetItemCount then
        count = GetItemCount(item)
    end
    return count or 0
end

------------------------------------------------------------------------
-- Spellbook (cached; rebuilt on SPELLS_CHANGED and every few seconds)
------------------------------------------------------------------------
local SPELL_CACHE_TTL = 10
local spellCache, spellCacheTime

local function AddKnownSpell(cache, name, spellID)
    if not name or name == "" then return end
    local ids = cache[name]
    if not ids then
        ids = {}
        cache[name] = ids
    end
    if spellID then
        ids[#ids + 1] = spellID
    end
end

-- Forever / modern spellbook
local function ScanSkillLineSpellBook(cache)
    local bank = (Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local learnedSpell = (Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1
    for lineIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
        if line then
            for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                -- FutureSpell items are listed in the book but not learned yet.
                if info and info.itemType == learnedSpell and not info.isOffSpec then
                    AddKnownSpell(cache, info.name, info.spellID or info.actionID)
                end
            end
        end
    end
end

-- Classic spellbook (spell tabs)
local function ScanTabSpellBook(cache)
    local bookType = BOOKTYPE_SPELL or "spell"
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        offset, numSpells = offset or 0, numSpells or 0
        for slot = offset + 1, offset + numSpells do
            local name = GetSpellBookItemName(slot, bookType)
            local spellID
            if GetSpellBookItemInfo then
                local kind, id = GetSpellBookItemInfo(slot, bookType)
                if kind == "FUTURESPELL" then
                    name = nil
                else
                    spellID = id
                end
            end
            AddKnownSpell(cache, name, spellID)
        end
    end
end

-- Returns { [spellName] = { spellID, ... } } for every learned player spell.
local function GetSpellCache()
    local now = GetTime()
    if spellCache and (now - spellCacheTime) < SPELL_CACHE_TTL then
        return spellCache
    end

    local cache = {}
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
        ScanSkillLineSpellBook(cache)
    elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
        ScanTabSpellBook(cache)
    end

    spellCache, spellCacheTime = cache, now
    if next(cache) == nil then
        -- Spellbook not loaded yet (early login): retry soon instead of caching "nothing known".
        spellCacheTime = now - SPELL_CACHE_TTL + 1
    end
    return cache
end

function Compat.KnowsSpellNamed(name)
    return name ~= nil and GetSpellCache()[name] ~= nil
end

function Compat.KnowsAnySpellNamed(names)
    local cache = GetSpellCache()
    for _, name in ipairs(names) do
        if cache[name] then return true end
    end
    return false
end

-- predicate(spellName) -> bool
function Compat.KnowsSpellMatching(predicate)
    for name in pairs(GetSpellCache()) do
        if predicate(name) then return true end
    end
    return false
end

-- predicate(spellName, spellID) -> bool. Returns the matching learned spell IDs.
function Compat.GetKnownSpellIDsMatching(predicate)
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

function Compat.KnowsSpellID(spellID)
    if not spellID then return false end
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellID) then
        return true
    end
    if IsPlayerSpell and IsPlayerSpell(spellID) then
        return true
    end
    -- Spell IDs/ranks can differ between clients; fall back to the spell's name.
    return Compat.KnowsSpellNamed(Compat.GetSpellName(spellID))
end

------------------------------------------------------------------------
-- Player buffs
------------------------------------------------------------------------
local MAX_AURAS = 255

local function ReadPlayerBuff(index)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        return C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
    elseif UnitAura then
        local name, _, _, _, duration, expirationTime, _, _, _, spellId = UnitAura("player", index, "HELPFUL")
        if name then
            return { name = name, duration = duration, expirationTime = expirationTime, spellId = spellId }
        end
    end
    return nil
end

local function SpellAuraMayBeSecret(spellID)
    local ok, secret = pcall(C_Secrets.ShouldSpellAuraBeSecret, spellID)
    return (not ok) or secret ~= false
end

-- Some auras were unreadable and none matched. "Missing" is still reliable if
-- every learned spell that could provide the buff is flagged never-secret:
-- that buff would have been readable had it been present.
local function MissingIsReliable(matcher)
    if not (C_Secrets and C_Secrets.ShouldSpellAuraBeSecret) then return false end
    local ids = Compat.GetKnownSpellIDsMatching(matcher)
    if #ids == 0 then return false end
    for _, id in ipairs(ids) do
        if SpellAuraMayBeSecret(id) then return false end
    end
    return true
end

local function ScanPlayerBuffs(matcher)
    local sawSecret = false
    for index = 1, MAX_AURAS do
        local aura = ReadPlayerBuff(index)
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
function Compat.FindPlayerBuff(matcher)
    local ok, state, remaining = pcall(ScanPlayerBuffs, matcher)
    if not ok then
        -- Most likely restricted buff data; kept for /prepped debug.
        Compat.lastBuffScanError = state
        return "unknown"
    end
    return state, remaining
end

-- Convenience matchers
function Compat.NameIn(names)
    local set = {}
    for _, name in ipairs(names) do set[name] = true end
    return function(name) return set[name] == true end
end

-- Matches by spell ID, or by the names of those spells: IDs/ranks can differ
-- between clients while the names stay the same.
function Compat.SpellIDOrNameIn(spellIDs)
    local idSet, nameSet = {}, {}
    for _, id in ipairs(spellIDs) do idSet[id] = true end
    return function(name, spellId)
        if spellId ~= nil and idSet[spellId] then return true end
        if next(nameSet) == nil then
            for _, id in ipairs(spellIDs) do
                local spellName = Compat.GetSpellName(id)
                if spellName then nameSet[spellName] = true end
            end
        end
        return name ~= nil and nameSet[name] == true
    end
end

------------------------------------------------------------------------
-- Weapon enchants (poisons, shaman imbues)
------------------------------------------------------------------------
local INVSLOT_MAINHAND_ID = INVSLOT_MAINHAND or 16
local INVSLOT_OFFHAND_ID = INVSLOT_OFFHAND or 17

local function ReadTemporaryEnchant(slot)
    local info = C_PaperDollInfo.GetTemporaryEnchantmentInfo(slot)
    if not info then return false, nil end
    if info.hasExpirationTime == false then return true, nil end
    return true, info.remainingTimeMs
end

-- Returns hasMainHand, mainHandMsLeft, hasOffHand, offHandMsLeft
-- (msLeft is nil when unknown or the enchant has no expiry).
function Compat.GetWeaponEnchants()
    if C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo then
        local hasMH, mhMs = ReadTemporaryEnchant(INVSLOT_MAINHAND_ID)
        local hasOH, ohMs = ReadTemporaryEnchant(INVSLOT_OFFHAND_ID)
        return hasMH, mhMs, hasOH, ohMs
    elseif GetWeaponEnchantInfo then
        local hasMH, mhMs, _, _, hasOH, ohMs = GetWeaponEnchantInfo()
        return hasMH and true or false, mhMs, hasOH and true or false, ohMs
    end
    return false, nil, false, nil
end

------------------------------------------------------------------------
-- Hunter pets
------------------------------------------------------------------------
function Compat.GetPetHappiness()
    if C_PetInfo and C_PetInfo.GetPetHappiness then
        return C_PetInfo.GetPetHappiness()
    elseif GetPetHappiness then
        return GetPetHappiness()
    end
end

-- Always returns a list of diet names (e.g. { "Meat", "Fish" }).
function Compat.GetPetFoodTypes()
    if C_PetInfo and C_PetInfo.GetPetFoodTypes then
        return C_PetInfo.GetPetFoodTypes() or {}
    elseif GetPetFoodTypes then
        return { GetPetFoodTypes() }
    end
    return {}
end

-- nil when the client can't answer (TBC: fall back to tooltip scanning).
function Compat.CanPetEatItem(itemID)
    if C_PetInfo and C_PetInfo.CanPetEatItem then
        return C_PetInfo.CanPetEatItem(itemID) == true
    end
    return nil
end

------------------------------------------------------------------------
-- Talent trees (cached; rebuilt on talent events and every few seconds)
------------------------------------------------------------------------
local TALENT_CACHE_TTL = 5
local talentCache, talentCacheTime

-- Forever: one Traits tree per class, split into groups (Holy/Prot/Ret, ...).
local function ReadTraitTalentTrees()
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID and C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup
        and C_SpecializationInfo.GetActiveSpecGroup then
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

-- TBC: sum talent ranks per tab (GetTalentTabInfo's point total is unreliable there).
local function ReadTabTalentTrees()
    local numTabs = GetNumTalentTabs()
    if not numTabs or numTabs == 0 then return nil end

    local trees = {}
    for tab = 1, numTabs do
        local points = 0
        for talent = 1, (GetNumTalents(tab) or 0) do
            local rank
            if GetTalentInfo then
                rank = select(5, GetTalentInfo(tab, talent))
            elseif C_SpecializationInfo and C_SpecializationInfo.GetTalentInfo then
                local info = C_SpecializationInfo.GetTalentInfo({ specializationIndex = tab, talentIndex = talent })
                rank = info and info.rank
            end
            points = points + (tonumber(rank) or 0)
        end
        trees[tab] = { points = points }
    end
    return trees
end

-- Returns a list of { points = n, name = s|nil } in talent-tree order, or nil.
function Compat.GetTalentTrees()
    local now = GetTime()
    if talentCache ~= nil and (now - talentCacheTime) < TALENT_CACHE_TTL then
        return talentCache or nil
    end

    local ok, trees = false, nil
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits
        and C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupCurrencyInfo then
        ok, trees = pcall(ReadTraitTalentTrees)
    elseif GetNumTalentTabs and GetNumTalents then
        ok, trees = pcall(ReadTabTalentTrees)
    end
    if not ok then
        Compat.lastTalentError = trees
        trees = nil
    end

    talentCache, talentCacheTime = trees or false, now
    return trees
end

-- Index of the tree with strictly the most points; nil if no points or a tie.
function Compat.GetPrimaryTalentTree()
    local trees = Compat.GetTalentTrees()
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
function Compat.InvalidateCaches()
    spellCache = nil
    talentCache = nil
end

local function IsEventValid(event)
    if C_EventUtils and C_EventUtils.IsEventValid then
        return C_EventUtils.IsEventValid(event)
    end
    return true
end

-- Registering an event the client doesn't know raises an error on modern
-- clients, so events that only exist on one client go through here.
function Compat.RegisterEvent(frame, event)
    if not IsEventValid(event) then return false end
    return (pcall(frame.RegisterEvent, frame, event))
end

function Compat.RegisterUnitEvent(frame, event, ...)
    if not IsEventValid(event) then return false end
    if frame.RegisterUnitEvent then
        return (pcall(frame.RegisterUnitEvent, frame, event, ...))
    end
    return (pcall(frame.RegisterEvent, frame, event))
end

function Compat.GetClientLabel()
    local version, build, _, interface = GetBuildInfo()
    local flavor = Compat.isForever and "WoW Forever" or "Classic"
    return string.format("%s %s (build %s, interface %s)", flavor, tostring(version), tostring(build), tostring(interface))
end
