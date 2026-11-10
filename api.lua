-- api.lua
-- WoW Forever helpers shared by the reminder modules.
--
-- Spells are identified by spell ID; their names come from the client
-- (C_Spell.GetSpellName), so detection works in every client language.
-- Buff data can be "secret" (unreadable by addons) while Blizzard's combat
-- restrictions are active; the buff helpers report that as "unknown".
--
-- Everything that is costly to read (spellbook, buffs, bags, talents, Legacy
-- perks) is cached here. The core's event handler invalidates the caches
-- (API.InvalidateSpells / Talents / Auras / Bags); the TTLs are only a safety net.

local _, ns = ...
local API = {}
ns.API = API

local GetTime = GetTime

local function Wipe(t)
    for key in pairs(t) do t[key] = nil end
    return t
end
API.Wipe = Wipe

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

local function InCombat()
    return (UnitAffectingCombat("player") or InCombatLockdown()) and true or false
end
API.InCombat = InCombat

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
-- Spellbook (rebuilt after SPELLS_CHANGED and talent events)
------------------------------------------------------------------------
local SPELL_CACHE_TTL = 60 -- safety net only: the spellbook changes fire events
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

-- Count and name of the reagent for the best learned option, and the option. If
-- the spell is learned under an ID that isn't listed, every listed reagent
-- counts (name and option nil).
function API.CountReagentForKnownSpell(options)
    local option = API.PickByKnownSpell(options)
    if option then
        return C_Item.GetItemCount(option.item), option.name, option
    end
    local total = 0
    for _, entry in ipairs(options) do total = total + C_Item.GetItemCount(entry.item) end
    return total, nil, nil
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

-- Learned spell IDs of a family, listed or matched by name (cached per spellbook).
function API.GetKnownFamilyIDs(family)
    GetSpellCache()
    if family.knownIDsGeneration ~= spellCacheGeneration then
        family.knownIDs = API.GetKnownSpellIDsMatching(function(name, id)
            return API.FamilyMatches(family, name, id)
        end)
        family.knownIDsGeneration = spellCacheGeneration
    end
    return family.knownIDs
end

------------------------------------------------------------------------
-- Player buffs
------------------------------------------------------------------------
-- One scan of your buffs is shared by every buff check until UNIT_AURA (or a
-- change of combat restrictions) invalidates it, instead of one scan per
-- check. The entries are reused, so a rescan creates no garbage of its own.
local MAX_AURAS = 255
local AURA_SNAPSHOT_TTL = 5 -- safety net; UNIT_AURA normally invalidates sooner

local auraEntries = {} -- { name =, spellId =, expirationTime = } per readable buff
local auraCount, auraSawSecret = 0, false
local auraSnapshotOK, auraSnapshotTime = nil, 0 -- OK: nil = stale, false = scan failed

local function ScanPlayerBuffs()
    local count, sawSecret = 0, false
    for index = 1, MAX_AURAS do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
        if not aura then break end

        if canaccesstable and not canaccesstable(aura) then
            sawSecret = true
        else
            local name, spellId = aura.name, aura.spellId
            if IsSecret(name) or IsSecret(spellId) then
                sawSecret = true
            else
                local expirationTime = aura.expirationTime
                if expirationTime == nil or IsSecret(expirationTime) or expirationTime <= 0 then
                    expirationTime = nil
                end
                count = count + 1
                local entry = auraEntries[count]
                if not entry then
                    entry = {}
                    auraEntries[count] = entry
                end
                entry.name, entry.spellId, entry.expirationTime = name, spellId, expirationTime
            end
        end
    end
    return count, sawSecret
end

local function RefreshAuraSnapshot()
    local now = GetTime()
    if auraSnapshotOK ~= nil and (now - auraSnapshotTime) < AURA_SNAPSHOT_TTL then
        return auraSnapshotOK
    end
    local ok, count, sawSecret = pcall(ScanPlayerBuffs)
    auraSnapshotTime = now
    if ok then
        auraCount, auraSawSecret, auraSnapshotOK = count, sawSecret, true
    else
        -- Most likely restricted buff data; kept for /prepped debug.
        API.lastBuffScanError = count
        auraCount, auraSawSecret, auraSnapshotOK = 0, false, false
    end
    return auraSnapshotOK
end

local function SpellAuraMayBeSecret(spellID)
    local ok, secret = pcall(C_Secrets.ShouldSpellAuraBeSecret, spellID)
    return (not ok) or secret ~= false
end

-- Learned spell IDs per matcher, cached per spellbook (see MissingIsReliable).
local knownIDsByMatcher = setmetatable({}, { __mode = "k" })

local function KnownIDsFor(matcher)
    GetSpellCache()
    local entry = knownIDsByMatcher[matcher]
    if not entry or entry.generation ~= spellCacheGeneration then
        entry = { generation = spellCacheGeneration, ids = API.GetKnownSpellIDsMatching(matcher) }
        knownIDsByMatcher[matcher] = entry
    end
    return entry.ids
end

-- Some auras were unreadable and none matched. "Missing" is still reliable if
-- every learned spell that could provide the buff is flagged never-secret:
-- that buff would have been readable had it been present.
local function MissingIsReliable(matcher)
    local ids = KnownIDsFor(matcher)
    if #ids == 0 then return false end
    for _, id in ipairs(ids) do
        if SpellAuraMayBeSecret(id) then return false end
    end
    return true
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
    if not RefreshAuraSnapshot() then
        return "unknown"
    end
    for i = 1, auraCount do
        local entry = auraEntries[i]
        if matcher(entry.name, entry.spellId) then
            local expirationTime = entry.expirationTime
            if expirationTime then
                return "present", expirationTime - GetTime()
            end
            return "present", nil
        end
    end
    if auraSawSecret and not MissingIsReliable(matcher) then
        return "unknown"
    end
    return "missing"
end

-- "Name id" for each buff on you, for /prepped debug (nil while buffs are hidden).
function API.ListPlayerBuffs()
    if API.AreAurasRestricted() then return nil end
    auraSnapshotOK = nil
    if not RefreshAuraSnapshot() then return nil end
    local list = {}
    for i = 1, auraCount do
        local entry = auraEntries[i]
        list[i] = string.format("%s %s", tostring(entry.name), tostring(entry.spellId))
    end
    return list
end

------------------------------------------------------------------------
-- Weapon enchants
------------------------------------------------------------------------
-- In Forever, poisons, shaman imbues and warlock stones are "Imbue" enchants;
-- sharpening stones and oils are "Temporary" enchants and can sit on the same
-- weapon, so only Imbue enchants count as a poison/imbue.
local ENCHANT_IMBUE = (Enum.ItemEnchantType and Enum.ItemEnchantType.Imbue) or 3
local ITEM_CLASS_WEAPON = (Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local MAIN_HAND_SLOT = INVSLOT_MAINHAND or 16
local OFF_HAND_SLOT = INVSLOT_OFFHAND or 17

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

function API.HasMainHandWeapon()
    return GetInventoryItemID("player", MAIN_HAND_SLOT) ~= nil
end

-- Dual wielding: the off hand holds a weapon (not a shield or off-hand frill).
function API.IsOffHandWeapon()
    local itemID = GetInventoryItemID("player", OFF_HAND_SLOT)
    if not itemID then return false end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    return classID == ITEM_CLASS_WEAPON
end

------------------------------------------------------------------------
-- Character state
------------------------------------------------------------------------
-- Still gaining levels: below the max level (as Forever's own UI works it out)
-- and experience not switched off.
function API.IsLeveling()
    local expansionMax = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
    local playerMax = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    local xpOff = IsXPUserDisabled and IsXPUserDisabled()
    return UnitLevel("player") < math.min(expansionMax, playerMax) and not xpOff
end

-- On a mount or in a travel shape: druid Travel (3), Aquatic (4) or Flight
-- Form (27), shaman Ghost Wolf (16).
local TRAVEL_FORMS = { [3] = true, [4] = true, [16] = true, [27] = true }
function API.IsTraveling()
    if IsMounted() then return true end
    local formID = GetShapeshiftFormID()
    return formID ~= nil and TRAVEL_FORMS[formID] == true
end

------------------------------------------------------------------------
-- Group chat
------------------------------------------------------------------------
-- True while Forever blocks chat messages from add-ons (combat restrictions).
function API.InChatLockdown()
    local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    return ok and locked == true
end

-- Chat type that reaches your whole group, or nil when you're not in one.
function API.GroupChatType()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

-- Posts one line in group chat. Returns true when it was sent.
function API.SendGroupMessage(message)
    local chatType = API.GroupChatType()
    if not chatType then return false end
    local ok = pcall(C_ChatInfo.SendChatMessage, message, chatType)
    return ok
end

------------------------------------------------------------------------
-- Items and bags (bag-derived counts are cached until the bags change)
------------------------------------------------------------------------
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

-- Backpack + equipped bags (and the reagent bag, if the client has one).
function API.NumBags()
    return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

-- Bumped on every bag change; modules cache bag scans per generation.
local bagGeneration = 0
function API.GetBagGeneration()
    return bagGeneration
end

local itemDataPending = false -- the last bag scan met an item whose data hadn't loaded

-- Calls fn(itemID, stackCount) for every item in your bags.
function API.ForEachBagItem(fn)
    for bag = 0, API.NumBags() do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                if C_Item.GetItemInfo(info.itemID) == nil then itemDataPending = true end -- also requests it
                fn(info.itemID, info.stackCount or 1)
            end
        end
    end
end

-- GET_ITEM_INFO_RECEIVED: rescan the bags only if the last scan met an item whose
-- data was still loading (early after login). Returns false when nothing changed.
function API.OnItemInfoReceived()
    if not itemDataPending then return false end
    itemDataPending = false
    API.InvalidateBags()
    return true
end

-- Free slots for loot: the backpack and bags that take any item (not quivers,
-- ammo pouches, soul bags, or the reagent bag).
function API.CountFreeBagSlots()
    local free = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
        if slots and (bagFamily == nil or bagFamily == 0) then
            free = free + slots
        end
    end
    return free
end

local DRINK = API.SpellFamily("Drink", { 430, 431, 432, 1133, 1135, 1137 }, { englishNames = { "Drink" } })
local drinkItems = {} -- [itemID] = bool, once the item's data has loaded

-- True for drinks (water): their use effect is the "Drink" spell.
function API.IsDrinkItem(itemID)
    local known = drinkItems[itemID]
    if known ~= nil then return known end
    local spellName, spellID = C_Item.GetItemSpell(itemID)
    local isDrink = (spellName ~= nil or spellID ~= nil) and API.FamilyMatches(DRINK, spellName, spellID)
    -- Before the item's data has loaded GetItemSpell can come back empty, so a
    -- "no" is only remembered for items the client knows.
    if isDrink or C_Item.GetItemInfo(itemID) ~= nil then
        drinkItems[itemID] = isDrink
    end
    return isDrink
end

------------------------------------------------------------------------
-- Hunter pets (C_PetInfo, with the classic globals as a fallback)
------------------------------------------------------------------------
local function PetInfoFunction(name)
    return (C_PetInfo and C_PetInfo[name]) or _G[name]
end

-- 1 = unhappy, 2 = content, 3 = happy; nil when unavailable.
function API.GetPetHappiness()
    local fn = PetInfoFunction("GetPetHappiness")
    if not fn then return nil end
    local ok, happiness = pcall(fn)
    if not ok or IsSecret(happiness) then return nil end
    return happiness
end

function API.GetPetFoodTypes()
    local fn = PetInfoFunction("GetPetFoodTypes")
    if not fn then return nil end
    local ok, foodTypes = pcall(fn)
    return ok and type(foodTypes) == "table" and foodTypes or nil
end

function API.CanPetEatItem(itemID)
    local fn = PetInfoFunction("CanPetEatItem")
    if not fn then return false end
    local ok, canEat = pcall(fn, itemID)
    return ok and canEat == true
end

------------------------------------------------------------------------
-- Reagents and Forever's Legacy perks
------------------------------------------------------------------------
-- Legacy perks that remove the vendor reagents of class abilities. Add new perk
-- spell IDs here; /prepped debug lists the perks a character has bought.
local REAGENT_FREE_PERKS = {
    [1262650] = "Reagent Economy",
}
local LEGACY_CONSTANTS = Constants and Constants.LegacyConsts
local LEGACY_TREE_IDS = {
    (LEGACY_CONSTANTS and LEGACY_CONSTANTS.LEGACY_TREE_PROFESSIONS_ID) or 1187,
    (LEGACY_CONSTANTS and LEGACY_CONSTANTS.LEGACY_TREE_ADVENTURE_ID) or 1188,
    (LEGACY_CONSTANTS and LEGACY_CONSTANTS.LEGACY_TREE_PROGRESSION_ID) or 1189,
}
local REAGENT_ECONOMY_CACHE_TTL = 60 -- safety net; TRAIT_CONFIG_UPDATED invalidates it
local reagentEconomy, reagentEconomySource, reagentEconomyTime = nil, nil, 0

-- Calls fn(spellID, overriddenSpellID, ranksPurchased) for each Legacy perk you
-- bought, until fn returns true. Returns true if it did.
local function ForEachLegacyPerk(fn)
    for _, treeID in ipairs(LEGACY_TREE_IDS) do
        local configID = C_Traits.GetConfigIDByTreeID(treeID)
        if configID then
            for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
                local node = C_Traits.GetNodeInfo(configID, nodeID)
                local ranks = (node and node.ranksPurchased) or 0
                if ranks > 0 and node.activeEntry then
                    local entry = C_Traits.GetEntryInfo(configID, node.activeEntry.entryID)
                    local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                    if definition and fn(definition.spellID, definition.overriddenSpellID, ranks) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function IsReagentFreePerk(spellID, overriddenSpellID)
    return REAGENT_FREE_PERKS[spellID] ~= nil or REAGENT_FREE_PERKS[overriddenSpellID] ~= nil
end

-- Returns hasPerk, howItWasDetected
function API.HasReagentEconomy()
    local now = GetTime()
    if reagentEconomy ~= nil and (now - reagentEconomyTime) < REAGENT_ECONOMY_CACHE_TTL then
        return reagentEconomy, reagentEconomySource
    end

    local has, source = false, nil
    for spellID in pairs(REAGENT_FREE_PERKS) do
        if C_SpellBook.IsSpellKnown(spellID) then
            has, source = true, "known spell"
            break
        end
    end
    if not has then
        local ok, inTree = pcall(ForEachLegacyPerk, IsReagentFreePerk)
        if ok and inTree then
            has, source = true, "Legacy tree"
        elseif not API.AreAurasRestricted() then
            for spellID in pairs(REAGENT_FREE_PERKS) do
                local auraOk, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
                if auraOk and aura then
                    has, source = true, "aura"
                    break
                end
            end
        end
    end

    reagentEconomy, reagentEconomySource, reagentEconomyTime = has, source, now
    return has, source
end

-- "Name id" (with "xN" for several ranks) per Legacy perk you bought, for
-- /prepped debug; nil when the Legacy trees can't be read.
function API.GetLegacyPerks()
    local list = {}
    local ok = pcall(ForEachLegacyPerk, function(spellID, overriddenSpellID, ranks)
        local id = spellID or overriddenSpellID
        if id then
            local text = string.format("%s %d", C_Spell.GetSpellName(id) or "?", id)
            if ranks > 1 then text = text .. " x" .. ranks end
            list[#list + 1] = text
        end
    end)
    return ok and list or nil
end

-- Spells seen working without their reagent (see API.ReagentNeeded).
local reagentFreeSpells = {}

-- isUsable, or nil when the client won't say (secret value, no API).
local function IsSpellUsable(spellID)
    local fn = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
    if not fn then return nil end
    local ok, usable = pcall(fn, spellID)
    if not ok or IsSecret(usable) then return nil end
    return usable == true
end

-- Whether the reagent itemID is still needed for the learned spellIDs that use it.
-- Not needed when:
--   * soldByVendors and a Legacy perk such as Reagent Economy removes vendor reagents, or
--   * one of the spells is castable while you carry none of the reagent. A spell
--     that needs a reagent isn't usable without it, so this catches any perk or
--     talent Prepped doesn't know about yet. It can only be seen once you run
--     out, and is then remembered until your talents or Legacy perks change.
function API.ReagentNeeded(itemID, spellIDs, soldByVendors)
    if soldByVendors and API.HasReagentEconomy() then return false end
    for _, spellID in ipairs(spellIDs) do
        if reagentFreeSpells[spellID] then return false end
    end
    if C_Item.GetItemCount(itemID) == 0 and not InCombat() and not UnitIsDeadOrGhost("player") then
        for _, spellID in ipairs(spellIDs) do
            if IsSpellUsable(spellID) then
                reagentFreeSpells[spellID] = true
                return false
            end
        end
    end
    return true
end

-- "Name id" per spell seen working without its reagent, for /prepped debug.
function API.GetReagentFreeSpells()
    local list = {}
    for spellID in pairs(reagentFreeSpells) do
        list[#list + 1] = string.format("%s %d", C_Spell.GetSpellName(spellID) or "?", spellID)
    end
    table.sort(list)
    return list
end

------------------------------------------------------------------------
-- Talent trees (cached; rebuilt after talent events)
------------------------------------------------------------------------
-- Forever: one Traits tree per class, split into groups (Holy/Prot/Ret, ...),
-- returned in the classic tree order (confirmed in game: Arcane/Fire/Frost).
local TALENT_CACHE_TTL = 30 -- safety net; talent events invalidate it
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

-- Unspent talent points, and whether the talent frame has changes that
-- weren't confirmed (Apply) yet. Returns unspent, staged; nil if unknown.
-- Staged points count as spent here, so "staged" is what still needs Apply.
local function ReadTalentPointStatus()
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return nil end
    local configInfo = C_Traits.GetConfigInfo(configID)
    local treeID = configInfo and configInfo.treeIDs and configInfo.treeIDs[1]
    if not treeID then return nil end

    local unspent
    local currencies = C_Traits.GetTreeCurrencyInfo(configID, treeID, false)
    local currency = currencies and currencies[1]
    if currency and currency.quantity then unspent = currency.quantity end
    if unspent == nil and UnitCharacterPoints then unspent = UnitCharacterPoints("player") end

    local staged = C_Traits.ConfigHasStagedChanges and C_Traits.ConfigHasStagedChanges(configID) == true
    return unspent or 0, staged
end

-- Not cached: cheap, and staged changes come without TRAIT_CONFIG_UPDATED.
function API.GetTalentPointStatus()
    local ok, unspent, staged = pcall(ReadTalentPointStatus)
    if not ok or unspent == nil or IsSecret(unspent) then return nil end
    return unspent, staged
end

------------------------------------------------------------------------
-- Cache invalidation and events
------------------------------------------------------------------------
-- Spells learned or changed (SPELLS_CHANGED, LEARNED_SPELL_IN_SKILL_LINE).
function API.InvalidateSpells()
    spellCache = nil
    reagentEconomy = nil
end

-- Talents, specs or Legacy perks changed (TRAIT_CONFIG_UPDATED, ...).
function API.InvalidateTalents()
    talentCache = nil
    reagentEconomy = nil
    Wipe(reagentFreeSpells)
end

-- Buffs changed, or what Blizzard hides from addons did (combat, encounters).
function API.InvalidateAuras()
    auraSnapshotOK = nil
end

-- Bag contents changed (also when the pet changes: what counts as pet food).
function API.InvalidateBags()
    bagGeneration = bagGeneration + 1
end

function API.InvalidateCaches()
    API.InvalidateSpells()
    API.InvalidateTalents()
    API.InvalidateAuras()
    API.InvalidateBags()
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
            result[#result + 1] = { label = family.label, knownIDs = API.GetKnownFamilyIDs(family) }
        end
    end
    return result
end
