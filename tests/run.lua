-- tests/run.lua
-- Runs Prepped against a mocked WoW Forever client (tests/mock_client.lua):
-- reminder scenarios for every class on an English and a German client,
-- combat-restricted ("secret") buff data, /prepped debug and the options.
--
-- Usage, with Lua 5.1 like the game:  lua5.1 tests/run.lua [addonDir]
-- Exits with status 1 if any check fails.

local TESTS_DIR = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local ADDON_DIR = arg[1] or (TESTS_DIR .. "/..")
local Mock = dofile(TESTS_DIR .. "/mock_client.lua")
local IMBUE, TEMPORARY = Mock.IMBUE, Mock.TEMPORARY

------------------------------------------------------------------------
-- The TOC: load order and metadata
------------------------------------------------------------------------
local TOC_FILES = {}
for line in io.lines(ADDON_DIR .. "/prepped.toc") do
    line = line:gsub("\r$", "")
    local key, value = line:match("^##%s*([%w%-_]+):%s*(.-)%s*$")
    if key then
        Mock.metadata[key] = value
    elseif line:match("%.lua%s*$") then
        TOC_FILES[#TOC_FILES + 1] = line:match("^%s*(.-)%s*$")
    end
end

-- Every reminders_*.lua file except the core registers one module.
local MODULE_COUNT = 0
for _, file in ipairs(TOC_FILES) do
    if file:match("^reminders_") and file ~= "reminders_core.lua" then MODULE_COUNT = MODULE_COUNT + 1 end
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local failures, passes = 0, 0
local function Check(label, cond, detail)
    if cond then
        passes = passes + 1
    else
        failures = failures + 1
        print("FAIL: " .. label .. (detail and ("  -> " .. tostring(detail)) or ""))
    end
end
local function Has(list, text) for _, v in ipairs(list) do if v == text then return true end end return false end

-- The value of one "/prepped debug" line, e.g. DebugValue(env, "Unknown spell IDs").
local function DebugValue(env, label)
    for _, line in ipairs(env.__printed) do
        if line:sub(1, #label + 4) == "  " .. label .. ": " then return line:sub(#label + 5) end
    end
end

-- Loads the addon the way the client does (TOC order, then ADDON_LOADED etc.).
local function LoadAddon(env)
    local ns = {}
    local loadErrors = {}
    for _, file in ipairs(TOC_FILES) do
        local chunk = assert(loadfile(ADDON_DIR .. "/" .. file))
        setfenv(chunk, env)
        local ok, err = pcall(chunk, "Prepped", ns)
        if not ok then loadErrors[#loadErrors + 1] = file .. ": " .. tostring(err) end
    end
    assert(#loadErrors == 0, table.concat(loadErrors, " || "))
    env.__fire("ADDON_LOADED", "Prepped")
    env.__fire("PLAYER_ENTERING_WORLD", true, false)
    env.__fire("SPELLS_CHANGED")
    for _, line in ipairs(env.__printed) do assert(not line:find("ERROR", 1, true), line) end
    assert(env.Prepped and #env.Prepped.reminderModules == MODULE_COUNT,
        "expected " .. MODULE_COUNT .. " reminder modules to register")
end

local function VisibleReminders(env)
    local P, out = env.Prepped, {}
    for i = 1, P.activeCount do out[#out + 1] = P.displayLines[i].text:GetText() end
    return out
end

-- One scenario: load the addon for character S, check which reminders show.
local function Run(label, S, expectShown, expectHidden)
    local env = Mock.BuildEnv(S)
    local ok, err = pcall(LoadAddon, env)
    Check(label .. " | addon loads", ok, err)
    if not ok then return env end
    env.Prepped:CheckReminders()
    local shown = VisibleReminders(env)
    local shownStr = "[" .. table.concat(shown, " | ") .. "]"
    for _, text in ipairs(expectShown or {}) do Check(label .. " | shows '" .. text .. "'", Has(shown, text), shownStr) end
    for _, text in ipairs(expectHidden or {}) do Check(label .. " | hides '" .. text .. "'", not Has(shown, text), shownStr) end
    Check(label .. " | no Lua errors", #env.__errors == 0, table.concat(env.__errors, " || "))
    return env
end

------------------------------------------------------------------------
-- TOC sanity: every file exists, and every .lua file is listed
------------------------------------------------------------------------
do
    local listed = {}
    for _, file in ipairs(TOC_FILES) do
        listed[file] = true
        local f = io.open(ADDON_DIR .. "/" .. file)
        Check("TOC: " .. file .. " exists", f ~= nil)
        if f then f:close() end
    end
    local ls = io.popen('ls "' .. ADDON_DIR .. '" 2>/dev/null')
    if ls then
        for file in ls:lines() do
            if file:match("%.lua$") then Check("TOC lists " .. file, listed[file] == true) end
        end
        ls:close()
    end
end

------------------------------------------------------------------------
-- Reminder scenarios, on an English and a German client
------------------------------------------------------------------------
local NOW = 1000
for _, locale in ipairs({ "enUS", "deDE" }) do
    local function R(label, S, shown, hidden)
        S.locale = locale
        S.time = S.time or NOW
        return Run(locale .. " " .. label, S, shown, hidden)
    end

    -- Paladin
    local pal = { 20154, 20271, 465, 19740, 25780, 19752, 25782 }
    R("paladin: no buffs, out of combat", { class = "PALADIN", spells = pal, buffs = {}, items = { [21177] = 100 } },
        { "No Aura Active!", "No Blessing Active!" }, { "Missing Righteous Fury!" })
    R("paladin: aura + blessing expiring", { class = "PALADIN", spells = pal, buffs = { { spellId = 465 }, { spellId = 19740, expires = NOW + 20 } } },
        { "Blessing expiring (20s left)" }, { "No Aura Active!", "No Blessing Active!" })
    R("paladin: Blessing of Protection isn't a blessing", { class = "PALADIN", spells = pal, buffs = { { spellId = 465 }, { spellId = 1022, expires = NOW + 8 } } },
        { "No Blessing Active!" })
    R("paladin: greater blessing counts", { class = "PALADIN", spells = pal, buffs = { { spellId = 465 }, { spellId = 25782, expires = NOW + 3000 } } },
        {}, { "No Blessing Active!", "Blessing expiring (3000s left)" })
    R("paladin: prot + shield + group, no RF", { class = "PALADIN", spells = pal, inGroup = true, talents = { 5, 31, 10 },
        equipped = { [16] = 2131, [17] = 1201 }, buffs = { { spellId = 465 }, { spellId = 19740, expires = NOW + 200 } } }, { "Missing Righteous Fury!" })
    R("paladin: holy talents = no Righteous Fury reminder", { class = "PALADIN", spells = pal, inGroup = true, talents = { 31, 5, 0 },
        equipped = { [16] = 2131, [17] = 1201 }, buffs = { { spellId = 465 }, { spellId = 19740, expires = NOW + 200 } } },
        {}, { "Missing Righteous Fury!" })
    R("paladin: resting, low Symbol of Kings", { class = "PALADIN", spells = pal, resting = true, items = { [21177] = 3 } },
        { "Low on Symbol of Kings (3 left)", "Low on Symbol of Divinity (0 left)" })
    R("paladin: Reagent Economy hides symbols", { class = "PALADIN", spells = pal, resting = true, items = { [21177] = 3 }, reagentEconomy = true },
        {}, { "Low on Symbol of Kings (3 left)", "Low on Symbol of Divinity (0 left)" })

    -- Priest
    R("priest: fortitude expiring", { class = "PRIEST", spells = { 1243, 10938 }, buffs = { { spellId = 10938, expires = NOW + 30 } } },
        { "Fortitude expiring (30s left)" })
    R("priest: fortitude missing", { class = "PRIEST", spells = { 1243 }, buffs = {} }, { "Missing Power Word: Fortitude!" })
    R("priest: inner fire missing", { class = "PRIEST", spells = { 1243, 588 }, buffs = { { spellId = 1243, expires = NOW + 1000 } } },
        { "Missing Inner Fire!" }, { "Missing Power Word: Fortitude!", "Fortitude expiring (1000s left)" })
    R("priest: inner fire expiring", { class = "PRIEST", spells = { 588, 10952 }, buffs = { { spellId = 10952, expires = NOW + 40 } } },
        { "Inner Fire expiring (40s left)" })
    R("priest: PoF rank 1 uses Holy Candles", { class = "PRIEST", spells = { 21562 }, resting = true, items = { [17028] = 3, [17029] = 50 } },
        { "Low on Holy Candles (3 left)" })
    R("priest: PoF rank 2 uses Sacred Candles", { class = "PRIEST", spells = { 21562, 21564 }, resting = true, items = { [17028] = 50, [17029] = 4 } },
        { "Low on Sacred Candles (4 left)" }, { "Low on Holy Candles (50 left)" })
    R("priest: Prayer of Spirit uses Sacred Candles", { class = "PRIEST", spells = { 27681 }, resting = true }, { "Low on Sacred Candles (0 left)" })
    R("priest: no prayer = no candle reminder", { class = "PRIEST", spells = { 1243 }, resting = true },
        {}, { "Low on Holy Candles (0 left)", "Low on Sacred Candles (0 left)", "Low on candles (0 left)" })
    R("priest: Reagent Economy hides candles", { class = "PRIEST", spells = { 21562, 21564 }, resting = true, reagentEconomy = true },
        {}, { "Low on Sacred Candles (0 left)" })

    -- Warrior
    R("warrior: resting, low ammo", { class = "WARRIOR", spells = { 6673 }, resting = true, equipped = { [18] = 2504 }, ammoCount = 50 },
        { "Low on ammo/thrown (50 left)" }, { "No ammo/thrown equipped" })
    R("warrior: bow without ammo", { class = "WARRIOR", spells = { 6673 }, inCombat = true, equipped = { [18] = 2504 }, ammoCount = 0, buffs = {} },
        { "No ammo/thrown equipped" }, { "No Battle Shout Active!" })

    -- Mage
    R("mage: frost armor ok, AI missing, no gem", { class = "MAGE", spells = { 1459, 168, 759 }, buffs = { { spellId = 168, expires = NOW + 1000 } } },
        { "Buff Missing: Arcane Intellect", "Missing item: Mana Gem" }, { "Buff Missing: Mage Armor" })
    R("mage: resting, reagents low", { class = "MAGE", spells = { 1459, 23028, 3561, 10059 }, resting = true, items = { [17020] = 2 } },
        { "Low on reagents: Arcane Powder (2 left!)", "Low on reagents: Rune of Teleportation (0 left!)", "Low on reagents: Rune of Portals (0 left!)" },
        { "Low on water (0 left)" }) -- mages conjure their own
    R("mage: Reagent Economy hides reagents", { class = "MAGE", spells = { 1459, 23028, 3561, 10059 }, resting = true, items = { [17020] = 2 }, reagentEconomy = true },
        {}, { "Low on reagents: Arcane Powder (2 left!)", "Low on reagents: Rune of Teleportation (0 left!)", "Low on reagents: Rune of Portals (0 left!)" })

    -- Hunter
    R("hunter: low ammo, unhappy pet, low food", { class = "HUNTER", spells = { 1515, 13165 }, resting = true, equipped = { [18] = 2504 }, ammoCount = 150,
        pet = { happiness = 1, foodTypes = { "Meat" }, canEat = { [117] = true } },
        bags = { { bag = 0, slot = 1, itemID = 117, count = 5 }, { bag = 0, slot = 2, itemID = 4536, count = 20 } } },
        { "Low on ammo (150 left)", "Pet is unhappy", "Low on pet food (5 left)" })
    R("hunter: no aspect, no pet", { class = "HUNTER", spells = { 1515, 13165 }, equipped = { [18] = 2504 }, ammoCount = 2000, buffs = {} },
        { "Buff missing: Aspect", "No pet active" })
    R("hunter: hawk (higher rank) active", { class = "HUNTER", spells = { 1515, 14322 }, equipped = { [18] = 2504 }, ammoCount = 2000,
        buffs = { { spellId = 14322 } }, pet = { happiness = 3, foodTypes = { "Meat" } } }, {}, { "Buff missing: Aspect", "No pet active", "Pet is unhappy" })

    -- Rogue
    R("rogue: thrown with durability needs no ammo", { class = "ROGUE", spells = { 1856 }, equipped = { [16] = 2131, [18] = 2947 }, rangedDurability = 200 },
        {}, { "No ammo/thrown equipped" })
    R("rogue: Poisons skill (not in spellbook), OH missing", { class = "ROGUE", spells = { 1856 }, skills = { [40] = 120 },
        equipped = { [16] = 2131, [17] = 2131 }, items = { [6947] = 30, [5140] = 20 }, enchants = { [0] = { { type = IMBUE, ms = 1800000 } } } },
        { "Missing Weapon Poison!" })
    R("rogue: sharpening stone doesn't count as poison", { class = "ROGUE", spells = { 1856 }, skills = { [40] = 120 },
        equipped = { [16] = 2131 }, items = { [6947] = 30, [5140] = 20 }, enchants = { [0] = { { type = TEMPORARY, ms = 1800000 } } } },
        { "Missing Weapon Poison!" })
    R("rogue: poison + stone on both weapons", { class = "ROGUE", spells = { 1856 }, skills = { [40] = 120 },
        equipped = { [16] = 2131, [17] = 2131 }, items = { [6947] = 30, [5140] = 20 },
        enchants = { [0] = { { type = TEMPORARY, ms = 1800000 }, { type = IMBUE, ms = 1800000 } }, [1] = { { type = IMBUE, ms = 1700000 } } } },
        {}, { "Missing Weapon Poison!" })
    R("rogue: poison expiring", { class = "ROGUE", spells = { 1856 }, skills = { [40] = 120 }, equipped = { [16] = 2131 }, items = { [6947] = 30 },
        enchants = { [0] = { { type = IMBUE, ms = 45000 } } } }, { "Weapon Poison expiring (45s left)" })
    R("rogue: no Poisons skill = no poison reminders", { class = "ROGUE", spells = { 1856 }, resting = true, equipped = { [16] = 2131 }, items = { [5140] = 20 } },
        {}, { "Low on Poison (0 total)" })
    R("rogue: resting, low stock + powder", { class = "ROGUE", spells = { 1856 }, skills = { [40] = 120 }, resting = true, equipped = { [16] = 2131 },
        items = { [6947] = 5, [5140] = 3 } }, { "Low on Poison (5 total)", "Low on Flash Powder (3 left)" }, { "Low on water (0 left)" })
    R("rogue: low Blinding Powder", { class = "ROGUE", spells = { 1856, 2094 }, resting = true, items = { [5140] = 20, [5530] = 2 } },
        { "Low on Blinding Powder (2 left)" })
    R("rogue: Reagent Economy keeps Blinding Powder", { class = "ROGUE", spells = { 1856, 2094 }, resting = true, reagentEconomy = true,
        items = { [5140] = 2, [5530] = 2 } }, { "Low on Blinding Powder (2 left)" }, { "Low on Flash Powder (2 left)" })
    R("rogue: no Blind = no powder reminder", { class = "ROGUE", spells = { 1856 }, resting = true, items = { [5140] = 20 } },
        {}, { "Low on Blinding Powder (0 left)" })

    -- Shaman
    R("shaman: enh, no imbue/shield", { class = "SHAMAN", spells = { 324 }, talents = { 0, 15, 0 }, equipped = { [16] = 2131 },
        enchants = { [0] = { { type = TEMPORARY, ms = 1800000 } } }, buffs = {} }, { "Buff missing: Shield", "Buff missing: Weapon" })
    R("shaman: imbue + lightning shield present", { class = "SHAMAN", spells = { 324, 10432 }, talents = { 0, 15, 0 }, equipped = { [16] = 2131 },
        enchants = { [0] = { { type = IMBUE, ms = 1800000 } } }, buffs = { { spellId = 10432, expires = NOW + 500 } } },
        {}, { "Buff missing: Shield", "Buff missing: Weapon" })
    R("shaman: resting, ankh needs Reincarnation", { class = "SHAMAN", spells = { 324, 20608 }, resting = true, items = { [17030] = 1 } },
        { "Low on reagents: Ankh (1 left)" }, { "Low on reagents: Fish Oil (0 left)", "Low on reagents: Fish Scales (0 left)" })
    R("shaman: totem items left in the bank", { class = "SHAMAN", spells = { 324, 8071, 3599, 5394 }, items = { [5175] = 1 } },
        { "Missing items: Fire Totem, Water Totem" }, { "Missing item: Earth Totem" })
    R("shaman: one totem item missing, also while resting", { class = "SHAMAN", spells = { 8071, 10438, 8177 }, resting = true,
        items = { [5175] = 1, [5176] = 1 } }, { "Missing item: Air Totem" })
    R("shaman: all totem items carried", { class = "SHAMAN", spells = { 8071, 3599, 5394, 8177 },
        items = { [5175] = 1, [5176] = 1, [5177] = 1, [5178] = 1 } },
        {}, { "Missing item: Earth Totem", "Missing item: Fire Totem", "Missing item: Water Totem", "Missing item: Air Totem" })
    R("shaman: unlisted totem rank counts by name", { class = "SHAMAN", spells = { 900002 } }, { "Missing item: Fire Totem" })
    R("shaman: totem reminder waits until out of combat", { class = "SHAMAN", spells = { 8071 }, inCombat = true, buffs = {} },
        {}, { "Missing item: Earth Totem" })
    R("shaman: no totems learned, no totem reminder", { class = "SHAMAN", spells = { 324 } }, {}, { "Missing item: Earth Totem" })
    R("shaman: elemental skips weapon imbue", { class = "SHAMAN", spells = { 324 }, talents = { 20, 5, 0 }, equipped = { [16] = 2131 },
        buffs = { { spellId = 324, expires = NOW + 500 } } }, {}, { "Buff missing: Weapon", "Buff missing: Shield" })

    -- Warlock
    local lock = { 687, 688, 6201, 693 }
    R("warlock: level 18, nothing up", { class = "WARLOCK", spells = lock, items = { [6265] = 3 }, buffs = {}, equipped = { [16] = 2131 } },
        { "Missing Demon Skin!", "No demon summoned", "Missing item: Healthstone", "Missing item: Soulstone", "Low on Soul Shards (3 left)" },
        { "Missing weapon stone (Firestone/Spellstone)", "Missing Demon Armor!" })
    R("warlock: all set", { class = "WARLOCK", spells = { 687, 706, 11735, 688, 6201, 11730, 693, 17953 }, pet = {},
        items = { [6265] = 10, [19013] = 1, [16896] = 1 }, buffs = { { spellId = 11735, expires = NOW + 1000 } },
        equipped = { [16] = 2131 }, enchants = { [0] = { { type = IMBUE, ms = 3000000 } } } },
        {}, { "Missing Demon Armor!", "No demon summoned", "Missing weapon stone (Firestone/Spellstone)", "Missing item: Healthstone",
            "Missing item: Soulstone", "Low on Soul Shards (10 left)", "Demon Armor expiring (1000s left)", "Weapon stone expiring (3000s left)" })
    R("warlock: wizard oil isn't a weapon stone", { class = "WARLOCK", spells = { 688, 2362 }, pet = {}, items = { [6265] = 10 },
        equipped = { [16] = 2131 }, enchants = { [0] = { { type = TEMPORARY, ms = 1800000 } } } },
        { "Missing weapon stone (Firestone/Spellstone)" })
    R("warlock: weapon stone + armor expiring", { class = "WARLOCK", spells = { 706, 688, 17951 }, pet = {}, items = { [6265] = 10 },
        buffs = { { spellId = 706, expires = NOW + 45 } }, equipped = { [16] = 2131 },
        enchants = { [0] = { { type = TEMPORARY, ms = 1800000 }, { type = IMBUE, ms = 30000 } } } },
        { "Demon Armor expiring (45s left)", "Weapon stone expiring (30s left)" }, { "Missing weapon stone (Firestone/Spellstone)" })
    R("warlock: no weapon equipped = no stone reminder", { class = "WARLOCK", spells = { 688, 17951 }, pet = {}, items = { [6265] = 10 } },
        {}, { "Missing weapon stone (Firestone/Spellstone)" })
    R("warlock: Demonic Sacrifice = no demon on purpose", { class = "WARLOCK", spells = lock, items = { [6265] = 10, [5512] = 1, [5232] = 1 },
        buffs = { { spellId = 18791, expires = NOW + 1000 }, { spellId = 687, expires = NOW + 1000 } } },
        {}, { "No demon summoned" })
    R("warlock: dead pet counts as missing", { class = "WARLOCK", spells = { 688 }, pet = { dead = true }, buffs = {} }, { "No demon summoned" })
    R("warlock: soulstoned yourself, no shards", { class = "WARLOCK", spells = lock, pet = {}, items = { [6265] = 0 },
        buffs = { { spellId = 20765, expires = NOW + 1000 }, { spellId = 687, expires = NOW + 1000 } } },
        { "Low on Soul Shards (0 left)" }, { "Missing item: Soulstone", "Missing item: Healthstone" })
    R("warlock: shards ok, soulstone on yourself", { class = "WARLOCK", spells = lock, pet = {}, items = { [6265] = 6, [5512] = 1 },
        buffs = { { spellId = 20707, expires = NOW + 1000 }, { spellId = 687, expires = NOW + 1000 } } },
        {}, { "Missing item: Soulstone", "Missing item: Healthstone", "Low on Soul Shards (6 left)" })
    R("warlock: in combat only buff/pet reminders", { class = "WARLOCK", spells = lock, inCombat = true, items = { [6265] = 1 }, buffs = {} },
        { "Missing Demon Skin!", "No demon summoned" }, { "Missing item: Healthstone", "Missing item: Soulstone", "Low on Soul Shards (1 left)" })
    R("warlock: resting hides everything", { class = "WARLOCK", spells = lock, resting = true, items = { [6265] = 1 }, buffs = {} },
        {}, { "Missing Demon Skin!", "No demon summoned", "Missing item: Healthstone", "Missing item: Soulstone", "Low on Soul Shards (1 left)" })
    R("warlock: secret auras keep pet reminder quiet", { class = "WARLOCK", spells = { 688 }, inCombat = true, aurasSecret = true,
        buffs = { { spellId = 687, expires = NOW + 1000 } } }, {}, { "No demon summoned" })
    R("warlock: Reagent Economy keeps Soul Shards", { class = "WARLOCK", spells = lock, pet = {}, items = { [6265] = 2 }, reagentEconomy = true,
        buffs = { { spellId = 687, expires = NOW + 1000 } } }, { "Low on Soul Shards (2 left)" })

    -- Druid
    local motw = { 1126, 9885 }
    R("druid: no mark", { class = "DRUID", spells = motw, buffs = {} }, { "Missing Mark of the Wild!" })
    R("druid: mark expiring", { class = "DRUID", spells = motw, buffs = { { spellId = 9885, expires = NOW + 50 } } }, { "Mark of the Wild expiring (50s left)" })
    R("druid: gift counts as mark", { class = "DRUID", spells = { 9885, 21850 }, buffs = { { spellId = 21850, expires = NOW + 3000 } } },
        {}, { "Missing Mark of the Wild!", "Mark of the Wild expiring (3000s left)" })
    R("druid: travel form hides mark", { class = "DRUID", spells = motw, buffs = {}, form = 3 }, {}, { "Missing Mark of the Wild!" })
    R("druid: aquatic form hides mark", { class = "DRUID", spells = motw, buffs = {}, form = 4 }, {}, { "Missing Mark of the Wild!" })
    R("druid: cat form still shows mark", { class = "DRUID", spells = motw, buffs = {}, form = 1 }, { "Missing Mark of the Wild!" })
    R("druid: resting, reagents for highest ranks", { class = "DRUID", spells = { 20484, 20739, 20742, 20747, 20748, 21849, 21850 }, resting = true,
        items = { [17034] = 20, [17038] = 2, [17026] = 3, [17021] = 40 } },
        { "Low on Ironwood Seeds (2 left)", "Low on Wild Thornroot (3 left)" }, { "Missing Mark of the Wild!" })
    R("druid: rank 1 reagents", { class = "DRUID", spells = { 20484, 21849 }, resting = true, items = { [17034] = 1, [17038] = 40 } },
        { "Low on Maple Seeds (1 left)", "Low on Wild Berries (0 left)" })
    R("druid: rank 3 rebirth", { class = "DRUID", spells = { 20484, 20739, 20742 }, resting = true, items = { [17036] = 9 } },
        {}, { "Low on Ashwood Seeds (9 left)", "Low on Maple Seeds (0 left)", "Low on Wild Berries (0 left)" })
    R("druid: unlisted Rebirth rank counts every seed", { class = "DRUID", spells = { 888888 }, resting = true, items = { [17034] = 1, [17035] = 2 } },
        { "Low on Rebirth reagents (3 left)" })
    R("druid: Reagent Economy hides reagents", { class = "DRUID", spells = { 20484, 21849 }, resting = true, reagentEconomy = true },
        {}, { "Low on Maple Seeds (0 left)", "Low on Wild Berries (0 left)" })

    -- Everyone: food buff while leveling
    R("leveling: no food buff", { class = "WARRIOR", level = 30, buffs = {} }, { "Missing food buff (Well Fed)" })
    R("leveling: Well Fed up", { class = "WARRIOR", level = 30, buffs = { { spellId = 19710, expires = NOW + 600 } } },
        {}, { "Missing food buff (Well Fed)", "Food buff expiring (600s left)" })
    R("leveling: food buff expiring", { class = "MAGE", level = 30, buffs = { { spellId = 24799, expires = NOW + 30 } } },
        { "Food buff expiring (30s left)" })
    R("leveling: no food reminder while resting", { class = "WARRIOR", level = 30, resting = true, buffs = {} },
        {}, { "Missing food buff (Well Fed)" })
    R("leveling: no food reminder in combat", { class = "WARRIOR", level = 30, inCombat = true, buffs = {} },
        {}, { "Missing food buff (Well Fed)" })
    R("max level: no food reminder", { class = "WARRIOR", level = 60, buffs = {} }, {}, { "Missing food buff (Well Fed)" })
    R("experience turned off: no food reminder", { class = "WARRIOR", level = 30, xpDisabled = true, buffs = {} },
        {}, { "Missing food buff (Well Fed)" })
    R("leveling: Forever's Well Fed counts", { class = "WARRIOR", level = 30, buffs = { { spellId = 1248406, expires = NOW + 900 } } },
        {}, { "Missing food buff (Well Fed)" })
    R("leveling: no food reminder while mounted", { class = "WARRIOR", level = 30, mounted = true, buffs = {} },
        {}, { "Missing food buff (Well Fed)" })
    R("leveling: no food reminder in Travel Form", { class = "DRUID", level = 30, form = 3, buffs = {} },
        {}, { "Missing food buff (Well Fed)" })
    R("leveling: no food reminder in Ghost Wolf", { class = "SHAMAN", level = 30, form = 16, buffs = {} },
        {}, { "Missing food buff (Well Fed)" })
    R("leveling: food reminder in Cat Form", { class = "DRUID", level = 30, form = 1, buffs = {} },
        { "Missing food buff (Well Fed)" })

    -- Everyone: Camp Benefits while leveling (same conditions as the food buff)
    R("leveling: no Camp Benefits", { class = "WARRIOR", level = 30, buffs = { { spellId = 1248406, expires = NOW + 900 } } },
        { "Missing Camp Benefits" }, { "Missing food buff (Well Fed)" })
    R("leveling: Camp Benefits up", { class = "WARRIOR", level = 30, buffs = { { spellId = 1229741, expires = NOW + 3000 } } },
        { "Missing food buff (Well Fed)" }, { "Missing Camp Benefits", "Camp Benefits expiring (3000s left)" })
    R("leveling: Camp Benefits expiring (5 min warning)", { class = "WARRIOR", level = 30, buffs = { { spellId = 1229741, expires = NOW + 200 } } },
        { "Camp Benefits expiring (200s left)" })
    R("leveling: no camp reminder while resting", { class = "WARRIOR", level = 30, resting = true, buffs = {} }, {}, { "Missing Camp Benefits" })
    R("leveling: no camp reminder in combat", { class = "WARRIOR", level = 30, inCombat = true, buffs = {} }, {}, { "Missing Camp Benefits" })
    R("leveling: no camp reminder while mounted", { class = "WARRIOR", level = 30, mounted = true, buffs = {} }, {}, { "Missing Camp Benefits" })
    R("max level: no camp reminder", { class = "WARRIOR", level = 60, buffs = {} }, {}, { "Missing Camp Benefits" })

    -- Everyone
    R("mana user: low water (incl. reagent bag) + repair", { class = "PRIEST", spells = {}, resting = true, level = 40,
        bags = { { bag = 0, slot = 1, itemID = 159, count = 5 }, { bag = 5, slot = 2, itemID = 159, count = 2 } }, equipped = { [1] = 2131 }, headDurability = 40 },
        { "Low on water (7 left)", "Repair your gear" })
    R("water: not below the minimum level", { class = "PRIEST", spells = {}, resting = true, level = 5 }, {}, { "Low on water (0 left)" })
    R("druid: bear form still a mana user (water)", { class = "DRUID", spells = {}, resting = true, level = 40, form = 5,
        bags = { { bag = 0, slot = 1, itemID = 159, count = 5 } } }, { "Low on water (5 left)" })
    R("future (unlearned) spells are ignored", { class = "MAGE", spells = {}, futureSpells = { 1459 }, buffs = {} },
        {}, { "Buff Missing: Arcane Intellect" })

    -- Buff data hidden during combat: Forever refuses add-on aura scans, so stay quiet
    local env = R("combat restrictions: no buff reminders", { class = "PALADIN", spells = pal, inCombat = true, aurasSecret = true, buffs = {} },
        {}, { "No Aura Active!", "No Blessing Active!" })
    Check(locale .. " combat restrictions: no aura scans attempted", env.__auraScans == 0, env.__auraScans)
    -- Outside combat restrictions single buffs can be secret: "missing" only when it can't be one of them
    R("one secret buff: never-secret blessing missing", { class = "PALADIN", spells = pal, secretBuffs = { [465] = true },
        neverSecret = { [19740] = true }, buffs = { { spellId = 465 } } }, { "No Blessing Active!" }, { "No Aura Active!" })
    R("one secret buff: could be the blessing", { class = "PALADIN", spells = pal, secretBuffs = { [19740] = true },
        buffs = { { spellId = 465 }, { spellId = 19740, expires = NOW + 200 } } }, {}, { "No Blessing Active!", "No Aura Active!" })
end

-- Water Shield (new in Forever) is recognised by its English name until its spell ID is known
Run("enUS shaman: Water Shield recognised by name", { class = "SHAMAN", spells = { 324, 900001 }, time = NOW,
    buffs = { { spellId = 900001, expires = NOW + 500 } } }, {}, { "Buff missing: Shield" })
Run("deDE shaman: Water Shield not recognised yet", { class = "SHAMAN", spells = { 324, 900001 }, time = NOW, locale = "deDE",
    buffs = { { spellId = 900001, expires = NOW + 500 } } }, { "Buff missing: Shield" })

-- English-only fallback: a Forever teleport whose ID isn't listed still counts on English clients
Run("enUS unlisted Forever teleport (English pattern)", { class = "MAGE", spells = { 777777 }, resting = true, time = NOW },
    { "Low on reagents: Rune of Teleportation (0 left!)" })
Run("deDE unlisted Forever teleport (no English fallback)", { class = "MAGE", spells = { 777777 }, resting = true, time = NOW, locale = "deDE" },
    {}, { "Low on reagents: Rune of Teleportation (0 left!)" })

------------------------------------------------------------------------
-- /prepped debug
------------------------------------------------------------------------
do
    local env = Mock.BuildEnv({ class = "ROGUE", spells = { 1856 }, skills = { [40] = 75 }, time = NOW, reagentEconomy = true,
        equipped = { [16] = 2131, [18] = 2947 }, rangedDurability = 200, missingSpellIDs = { [2094] = true },
        enchants = { [0] = { { type = IMBUE, ms = 90000, id = 7 }, { type = TEMPORARY, ms = 1800000, id = 13 } } } })
    LoadAddon(env)
    local ok, err = pcall(env.SlashCmdList.PREPPED, "debug")
    Check("/prepped debug runs", ok, err)
    local out = table.concat(env.__printed, "\n")
    Check("debug: client + locale", out:find("interface 16001), locale enUS", 1, true) ~= nil, out)
    Check("debug: main hand enchant types", out:find("Main hand enchants: imbue #7 (90s), temporary #13 (1800s)", 1, true) ~= nil, out)
    Check("debug: thrown durability", out:find("durability 200/200, ammo count nil", 1, true) ~= nil, out)
    Check("debug: poisons skill", out:find("Poisons skill rank: 75", 1, true) ~= nil, out)
    Check("debug: reagent economy", out:find("Reagent Economy perk: yes (Legacy tree)", 1, true) ~= nil, out)
    Check("debug: unknown spell IDs", DebugValue(env, "Unknown spell IDs") == "Blind 2094", DebugValue(env, "Unknown spell IDs"))
    Check("debug: nothing recognised by name only", out:find("Recognised by name, ID not listed: none", 1, true) ~= nil, out)
    Check("debug: no Lua errors", #env.__errors == 0, table.concat(env.__errors, " || "))
end

do
    local env = Mock.BuildEnv({ class = "PALADIN", spells = { 20154, 20271, 465, 19740 }, time = NOW, neverSecret = { [19740] = true } })
    LoadAddon(env)
    pcall(env.SlashCmdList.PREPPED, "debug")
    local out = table.concat(env.__printed, "\n")
    Check("debug: buff visibility per family", out:find("Blessings in combat: always visible", 1, true) ~= nil
        and out:find("Auras in combat: hidden in combat", 1, true) ~= nil, out)
    Check("debug: buffs on you", DebugValue(env, "Buffs on you") == "none", DebugValue(env, "Buffs on you"))
    -- every spell ID Prepped lists exists in the (Forever) spell data
    Check("debug: no unknown spell IDs", DebugValue(env, "Unknown spell IDs") == "none", DebugValue(env, "Unknown spell IDs"))
end

-- The buffs on you are listed with their IDs (to find Forever-only IDs), unless they're hidden
do
    local env = Mock.BuildEnv({ class = "SHAMAN", spells = { 324 }, time = NOW,
        buffs = { { spellId = 900001, expires = NOW + 500 }, { spellId = 1248406, expires = NOW + 600 } } })
    LoadAddon(env)
    pcall(env.SlashCmdList.PREPPED, "debug")
    Check("debug: buffs on you with IDs", DebugValue(env, "Buffs on you") == "Water Shield 900001, Well Fed 1248406",
        DebugValue(env, "Buffs on you"))
    local hidden = Mock.BuildEnv({ class = "SHAMAN", spells = { 324 }, time = NOW, inCombat = true, aurasSecret = true,
        buffs = { { spellId = 900001, expires = NOW + 500 } } })
    LoadAddon(hidden)
    pcall(hidden.SlashCmdList.PREPPED, "debug")
    Check("debug: buffs hidden in combat", DebugValue(hidden, "Buffs on you") == "hidden right now", DebugValue(hidden, "Buffs on you"))
    Check("debug: no aura scan while hidden", hidden.__auraScans == 0, hidden.__auraScans)
end

-- Spells recognised only by name show their IDs, so they can be added to Prepped
for _, case in ipairs({
    { class = "SHAMAN", spells = { 324, 900001 }, locale = "enUS", expect = "Recognised by name, ID not listed: Water Shield 900001" },
    { class = "MAGE", spells = { 3561, 777777 }, locale = "enUS", expect = "Recognised by name, ID not listed: Teleport: Stonard 777777" },
    { class = "DRUID", spells = { 20484, 888888 }, locale = "deDE", expect = "Recognised by name, ID not listed: DE:Rebirth 888888" },
    -- a druid's "Teleport: Moonglade" isn't a mage teleport
    { class = "DRUID", spells = { 1126, 18960 }, locale = "enUS", expect = "Recognised by name, ID not listed: none" },
}) do
    local env = Mock.BuildEnv({ class = case.class, spells = case.spells, locale = case.locale, time = NOW })
    LoadAddon(env)
    pcall(env.SlashCmdList.PREPPED, "debug")
    local out = table.concat(env.__printed, "\n")
    Check("debug: " .. case.expect, out:find(case.expect, 1, true) ~= nil, out)
end

do
    local env = Mock.BuildEnv({ class = "DRUID", spells = { 1126 }, time = NOW, form = 1 })
    LoadAddon(env)
    pcall(env.SlashCmdList.PREPPED, "debug")
    local out = table.concat(env.__printed, "\n")
    Check("debug: druid shapeshift form", out:find("Shapeshift form ID: 1", 1, true) ~= nil, out)
    Check("debug: no Lua errors (druid)", #env.__errors == 0, table.concat(env.__errors, " || "))
end

------------------------------------------------------------------------
-- Options (Options > AddOns > Prepped)
------------------------------------------------------------------------
do
    local env = Mock.BuildEnv({ class = "HUNTER", spells = { 1515, 13165 }, resting = true, time = NOW, equipped = { [18] = 2504 }, ammoCount = 150 })
    LoadAddon(env)
    local P, S = env.Prepped, env.__settings
    Check("options: Prepped category registered", env.__addonCategory and env.__addonCategory.name == "Prepped")
    local names = {}
    for _, c in ipairs(env.__categories) do names[#names + 1] = c.name end
    Check("options: pages", table.concat(names, ",") == "Prepped,Appearance,Druid,Hunter,Mage,Paladin,Priest,Rogue,Shaman,Warlock,Warrior", table.concat(names, ","))

    -- every rule has a control; sliders start at the default, which lies on the slider
    for _, rule in ipairs(P.AllRules) do
        local key = rule.id == "general_account_wide" and "PREPPED_ACCOUNT_WIDE" or ("PREPPED_" .. rule.id)
        Check("options: control for " .. rule.id, S[key] ~= nil)
        if rule.defaultThreshold then
            local r = rule.range
            Check("options: range for " .. rule.id, r ~= nil and r[1] <= rule.defaultThreshold and rule.defaultThreshold <= r[2]
                and (rule.defaultThreshold - r[1]) % r[3] == 0, r and table.concat(r, "/") or "no range")
            local sliderKey = rule.sliderOnly and key or (key .. (rule.hasLowWarningToggle and "_SECONDS" or "_THRESHOLD"))
            Check("options: slider for " .. rule.id, S[sliderKey] ~= nil and S[sliderKey]:GetValue() == rule.defaultThreshold)
        end
        if rule.hasLowWarningToggle then Check("options: warn toggle for " .. rule.id, S[key .. "_LOW"] ~= nil) end
    end

    Check("options: no in-combat-only rules", S.PREPPED_paladin_seal == nil and S.PREPPED_warrior_battle_shout == nil)

    -- the "Warn when expiring" row follows its rule's checkbox
    local mageLayout
    for _, c in ipairs(env.__categories) do if c.name == "Mage" then mageLayout = c.layout end end
    local warnRow
    for _, init in ipairs(mageLayout.initializers) do
        if init.kind == "checkboxSlider" and init.data.cbSetting.variable == "PREPPED_mage_ai_buff_LOW" then warnRow = init end
    end
    Check("options: warn row is a child row", warnRow and warnRow.parent ~= nil and warnRow.predicate ~= nil)
    S.PREPPED_mage_ai_buff:SetValue(false)
    Check("options: warn row disabled when rule is off", warnRow and warnRow.predicate() == false)
    S.PREPPED_mage_ai_buff:SetValue(true)
    Check("options: warn row enabled when rule is on", warnRow and warnRow.predicate() == true)

    -- toggles and thresholds drive the reminders
    P:CheckReminders()
    Check("options: low ammo shown by default", Has(VisibleReminders(env), "Low on ammo (150 left)"))
    S.PREPPED_hunter_ammo_low:SetValue(false)
    Check("options: rule off hides reminder", not Has(VisibleReminders(env), "Low on ammo (150 left)"))
    Check("options: rule setting reads back", S.PREPPED_hunter_ammo_low:GetValue() == false and P:IsRuleEnabled("hunter_ammo_low") == false)
    S.PREPPED_hunter_ammo_low:SetValue(true)
    S.PREPPED_hunter_ammo_low_THRESHOLD:SetValue(100.4)
    Check("options: threshold rounded and stored", P:GetRuleThreshold("hunter_ammo_low") == 100)
    Check("options: below new threshold hides reminder", not Has(VisibleReminders(env), "Low on ammo (150 left)"))

    -- the master switch hides everything but keeps each rule's own setting
    S.PREPPED_general_master:SetValue(false)
    Check("options: master off hides reminders", #VisibleReminders(env) == 0)
    Check("options: rule checkbox unaffected by master", S.PREPPED_hunter_ammo_low:GetValue() == true)
    S.PREPPED_general_master:SetValue(true)

    -- account-wide <-> per character
    local before = S.PREPPED_hunter_pet_food_THRESHOLD.notified
    S.PREPPED_ACCOUNT_WIDE:SetValue(false)
    Check("options: per-character profile", P:IsAccountWide() == false and S.PREPPED_ACCOUNT_WIDE:GetValue() == false)
    Check("options: controls refreshed after profile switch", S.PREPPED_hunter_pet_food_THRESHOLD.notified > before)
    Check("options: per-character starts at defaults", P:GetRuleThreshold("hunter_ammo_low", 1000) == 1000)
    S.PREPPED_ACCOUNT_WIDE:SetValue(true)
    Check("options: account-wide asks first", env.__popups[#env.__popups] == "PREPPED_CONFIRM_ACCOUNT_WIDE" and P:IsAccountWide() == false)
    env.StaticPopupDialogs.PREPPED_CONFIRM_ACCOUNT_WIDE.OnCancel()
    Check("options: cancel keeps per-character", P:IsAccountWide() == false)
    S.PREPPED_ACCOUNT_WIDE:SetValue(true)
    env.StaticPopupDialogs.PREPPED_CONFIRM_ACCOUNT_WIDE.OnAccept()
    Check("options: accept switches to account-wide", P:IsAccountWide() == true and P:GetRuleThreshold("hunter_ammo_low") == 100)

    -- appearance
    S.PREPPED_FONT_SIZE:SetValue(24.2)
    Check("options: font size", P:GetAppearance().fontSize == 24)
    Check("options: text color default hex", S.PREPPED_FONT_COLOR:GetValue() == "ffffd100", S.PREPPED_FONT_COLOR:GetValue())
    S.PREPPED_FONT_COLOR:SetValue("ff336699")
    local fc = P:GetAppearance().fontColor
    Check("options: text color set", math.abs(fc.r - 0.2) < 0.01 and math.abs(fc.b - 0.6) < 0.01)
    Check("options: opacity default", S.PREPPED_BG_OPACITY:GetValue() == 50)
    S.PREPPED_BG_OPACITY:SetValue(75)
    Check("options: opacity set", P:GetAppearance().bgColor.a == 0.75)

    -- reset everything
    env.StaticPopupDialogs.PREPPED_RESET_ALL_SETTINGS.OnAccept()
    Check("options: reset thresholds", P:GetRuleThreshold("hunter_ammo_low") == 1000)
    Check("options: reset appearance", P:GetAppearance().fontSize == 18 and S.PREPPED_BG_OPACITY:GetValue() == 50)
    Check("options: reset refreshes controls", S.PREPPED_FONT_SIZE.notified > 0)

    -- opening the options
    local ok, err = pcall(env.SlashCmdList.PREPPED, "")
    Check("/prepped opens the Prepped page", ok and env.__opened[#env.__opened] == env.__addonCategory.ID, tostring(err))
    ok, err = pcall(env.Prepped_OpenOptions)
    Check("minimap AddOns menu opens options", ok and #env.__opened == 2, tostring(err))
    Check("options: no Lua errors", #env.__errors == 0, table.concat(env.__errors, " || "))
end

-- A broken options UI must not stop the reminders
do
    local env = Mock.BuildEnv({ class = "HUNTER", spells = { 1515, 13165 }, resting = true, time = NOW, equipped = { [18] = 2504 }, ammoCount = 150, breakSettings = true })
    local ok, err = pcall(LoadAddon, env)
    Check("broken options: addon still loads", ok, err)
    if ok then
        env.Prepped:CheckReminders()
        Check("broken options: reminders still work", Has(VisibleReminders(env), "Low on ammo (150 left)"))
        Check("broken options: error reported once", #env.__errors == 1 and env.__errors[1]:find("settings broken", 1, true) ~= nil,
            table.concat(env.__errors, " || "))
    end
end

print(string.format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
