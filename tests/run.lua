-- tests/run.lua
-- Runs Prepped against a mocked WoW Forever client (tests/mock_client.lua):
-- reminder scenarios for every class (by text on an English client; a German
-- client must show the same reminders), combat-restricted ("secret") buff data,
-- the reminder bars (moving, preview, icons, clicking, snoozing), /prepped
-- debug, the options and the translations.
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

-- Every reminders_*.lua file registers one module.
local MODULE_COUNT = 0
for _, file in ipairs(TOC_FILES) do
    if file:match("^reminders_") then MODULE_COUNT = MODULE_COUNT + 1 end
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

local function LastPrinted(env) return env.__printed[#env.__printed] or "" end

-- Loads the addon the way the client does (TOC order, then ADDON_LOADED etc.).
-- reload: PLAYER_ENTERING_WORLD says it's a /reload instead of a login.
local function LoadAddon(env, reload)
    local ns = {}
    env.__ns = ns
    local loadErrors = {}
    for _, file in ipairs(TOC_FILES) do
        local chunk = assert(loadfile(ADDON_DIR .. "/" .. file))
        setfenv(chunk, env)
        local ok, err = pcall(chunk, "Prepped", ns)
        if not ok then loadErrors[#loadErrors + 1] = file .. ": " .. tostring(err) end
    end
    assert(#loadErrors == 0, table.concat(loadErrors, " || "))
    env.__fire("ADDON_LOADED", "Prepped")
    if reload then env.__fire("PLAYER_ENTERING_WORLD", false, true) else env.__fire("PLAYER_ENTERING_WORLD", true, false) end
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
local function Shown(env) return table.concat(VisibleReminders(env), " | ") end

-- The rule IDs of the reminders on screen, in order.
local function VisibleIDs(env)
    local P, out = env.Prepped, {}
    for i = 1, P.activeCount do out[#out + 1] = tostring(P.displayLines[i].ruleId) end
    return table.concat(out, ",")
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
    Check(label .. " | no blocked actions", #env.__blocked == 0, table.concat(env.__blocked, ", "))
    return env
end

local NOW = 1000

local function Copy(S, extra)
    local copy = {}
    for k, v in pairs(S) do copy[k] = v end
    for k, v in pairs(extra or {}) do copy[k] = v end
    copy.time = copy.time or NOW
    return copy
end

-- One scenario on an English client (checked by text), and on a German client,
-- which must show the same reminders.
local function R(label, S, shown, hidden)
    local en = Run("enUS " .. label, Copy(S, { locale = "enUS" }), shown, hidden)
    local de = Mock.BuildEnv(Copy(S, { locale = "deDE" }))
    local ok, err = pcall(LoadAddon, de)
    Check("deDE " .. label .. " | addon loads", ok, err)
    if ok then
        de.Prepped:CheckReminders()
        Check("deDE " .. label .. " | same reminders as enUS", VisibleIDs(de) == VisibleIDs(en), VisibleIDs(de) .. " vs " .. VisibleIDs(en))
        Check("deDE " .. label .. " | no Lua errors", #de.__errors == 0, table.concat(de.__errors, " || "))
    end
    return en, de
end

local function Setup(S, configure)
    S.time = S.time or NOW
    local env = Mock.BuildEnv(S)
    LoadAddon(env)
    if configure then configure(env.Prepped) end
    return env
end

-- The same character after a /reload (reload = true) or a new login: a new
-- client with the saved variables of the last one.
local function Relaunch(env, S, reload)
    local next = Mock.BuildEnv(S)
    next.PreppedSettings = env.PreppedSettings
    LoadAddon(next, reload)
    return next
end

-- The click button over the reminder with this text.
local function ButtonFor(env, text)
    local P = env.Prepped
    for i = 1, P.activeCount do
        if P.displayLines[i].text:GetText() == text then return env["PreppedReminderButton" .. i] end
    end
end

-- What left-clicking the reminder with this text does, as "type spell=... unit=..." text.
local function ActionFor(env, text)
    local button = ButtonFor(env, text)
    if not (button and button:IsShown()) then return "no button" end
    local parts = { tostring(button:GetAttribute("type1")) }
    for _, key in ipairs({ "spell", "unit", "item", "target-slot", "macrotext" }) do
        local value = button:GetAttribute(key)
        if value ~= nil then parts[#parts + 1] = key .. "=" .. tostring(value) end
    end
    return table.concat(parts, " ")
end

local function TooltipFor(env, text)
    local button = ButtonFor(env, text)
    if not button then return "" end
    env.__enter(button)
    local lines = table.concat(env.__tooltipLines(), " / ")
    env.__leave(button)
    return lines
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
    Check("TOC: compartment tooltip functions", Mock.metadata.AddonCompartmentFuncOnEnter == "Prepped_OnCompartmentEnter"
        and Mock.metadata.AddonCompartmentFuncOnLeave == "Prepped_OnCompartmentLeave")
end

------------------------------------------------------------------------
-- Reminder scenarios
------------------------------------------------------------------------
local MEAT = { { bag = 0, slot = 1, itemID = 2680, count = 5 } }  -- Spiced Wolf Meat: its tooltip says it makes you well fed
local JERKY = { { bag = 0, slot = 1, itemID = 117, count = 5 } }  -- Tough Jerky: plain food
local FOOD_REMINDER = "Missing Well Fed"

-- Paladin
local pal = { 20154, 20271, 465, 19740, 25780, 19752, 25782 }
R("paladin: no buffs, out of combat", { class = "PALADIN", spells = pal, buffs = {}, items = { [21177] = 100 } },
    { "Missing Devotion Aura", "Missing Blessing of Might" }, { "Missing Righteous Fury" })
R("paladin: aura + blessing expiring", { class = "PALADIN", spells = pal, buffs = { { spellId = 465 }, { spellId = 19740, expires = NOW + 20 } } },
    { "Blessing of Might expires in 20s" }, { "Missing Devotion Aura", "Missing Blessing of Might" })
R("paladin: Blessing of Protection isn't a blessing", { class = "PALADIN", spells = pal, buffs = { { spellId = 465 }, { spellId = 1022, expires = NOW + 8 } } },
    { "Missing Blessing of Might" })
R("paladin: greater blessing counts", { class = "PALADIN", spells = pal, buffs = { { spellId = 465 }, { spellId = 25782, expires = NOW + 3000 } } },
    {}, { "Missing Blessing of Might", "Greater Blessing of Might expires in 50m" })
R("paladin: prot + shield + group, no RF", { class = "PALADIN", spells = pal, inGroup = true, talents = { 5, 31, 10 },
    equipped = { [16] = 2131, [17] = 1201 }, buffs = { { spellId = 465 }, { spellId = 19740, expires = NOW + 200 } } }, { "Missing Righteous Fury" })
R("paladin: holy talents = no Righteous Fury reminder", { class = "PALADIN", spells = pal, inGroup = true, talents = { 31, 5, 0 },
    equipped = { [16] = 2131, [17] = 1201 }, buffs = { { spellId = 465 }, { spellId = 19740, expires = NOW + 200 } } },
    {}, { "Missing Righteous Fury" })
R("paladin: resting, low Symbol of Kings", { class = "PALADIN", spells = pal, resting = true, items = { [21177] = 3 } },
    { "Buy Symbol of Kings (3 left)", "Buy Symbol of Divinity (0 left)" })
R("paladin: Reagent Economy hides symbols", { class = "PALADIN", spells = pal, resting = true, items = { [21177] = 3 }, reagentEconomy = true },
    {}, { "Buy Symbol of Kings (3 left)", "Buy Symbol of Divinity (0 left)" })

-- Priest
R("priest: fortitude expiring", { class = "PRIEST", spells = { 1243, 10938 }, buffs = { { spellId = 10938, expires = NOW + 30 } } },
    { "Power Word: Fortitude expires in 30s" })
R("priest: fortitude missing", { class = "PRIEST", spells = { 1243 }, buffs = {} }, { "Missing Power Word: Fortitude" })
R("priest: inner fire missing", { class = "PRIEST", spells = { 1243, 588 }, buffs = { { spellId = 1243, expires = NOW + 1000 } } },
    { "Missing Inner Fire" }, { "Missing Power Word: Fortitude", "Power Word: Fortitude expires in 16m 40s" })
R("priest: inner fire expiring", { class = "PRIEST", spells = { 588, 10952 }, buffs = { { spellId = 10952, expires = NOW + 40 } } },
    { "Inner Fire expires in 40s" })
R("priest: PoF rank 1 uses Holy Candles", { class = "PRIEST", spells = { 21562 }, resting = true, items = { [17028] = 3, [17029] = 50 } },
    { "Buy Holy Candle (3 left)" })
R("priest: PoF rank 2 uses Sacred Candles", { class = "PRIEST", spells = { 21562, 21564 }, resting = true, items = { [17028] = 50, [17029] = 4 } },
    { "Buy Sacred Candle (4 left)" }, { "Buy Holy Candle (50 left)" })
R("priest: Prayer of Spirit uses Sacred Candles", { class = "PRIEST", spells = { 27681 }, resting = true }, { "Buy Sacred Candle (0 left)" })
R("priest: no prayer = no candle reminder", { class = "PRIEST", spells = { 1243 }, resting = true },
    {}, { "Buy Holy Candle (0 left)", "Buy Sacred Candle (0 left)", "Buy candles (0 left)" })
R("priest: Reagent Economy hides candles", { class = "PRIEST", spells = { 21562, 21564 }, resting = true, reagentEconomy = true },
    {}, { "Buy Sacred Candle (0 left)" })

-- Warrior
R("warrior: resting, low ammo", { class = "WARRIOR", spells = { 6673 }, resting = true, equipped = { [18] = 2504 }, ammoCount = 50 },
    { "Buy ammo (50 left)" }, { "Out of ammo" })
R("warrior: bow without ammo", { class = "WARRIOR", spells = { 6673 }, inCombat = true, equipped = { [18] = 2504 }, ammoCount = 0, buffs = {} },
    { "Out of ammo" }, { "Missing Battle Shout" })

-- Mage
R("mage: frost armor ok, AI missing, no gem", { class = "MAGE", spells = { 1459, 168, 759 }, buffs = { { spellId = 168, expires = NOW + 1000 } } },
    { "Missing Arcane Intellect", "Conjure a Mana Gem" }, { "Missing Frost Armor" })
R("mage: resting, reagents low", { class = "MAGE", spells = { 1459, 23028, 3561, 10059 }, resting = true, items = { [17020] = 2 } },
    { "Buy Arcane Powder (2 left)", "Buy Rune of Teleportation (0 left)", "Buy Rune of Portals (0 left)" },
    { "Buy water (0 left)", "Buy food (0 left)" }) -- mages conjure their own
R("mage: Reagent Economy hides reagents", { class = "MAGE", spells = { 1459, 23028, 3561, 10059 }, resting = true, items = { [17020] = 2 }, reagentEconomy = true },
    {}, { "Buy Arcane Powder (2 left)", "Buy Rune of Teleportation (0 left)", "Buy Rune of Portals (0 left)" })

-- Hunter
R("hunter: low ammo, unhappy pet, low food", { class = "HUNTER", spells = { 1515, 13165 }, resting = true, equipped = { [18] = 2504 }, ammoCount = 150,
    pet = { happiness = 1, foodTypes = { "Meat" }, canEat = { [117] = true } },
    bags = { { bag = 0, slot = 1, itemID = 117, count = 5 }, { bag = 0, slot = 2, itemID = 4536, count = 20 } } },
    { "Buy ammo (150 left)", "Feed your pet (unhappy)", "Buy pet food (5 left)" })
R("hunter: content pet", { class = "HUNTER", spells = { 1515, 13165 }, resting = true, pet = { happiness = 2, foodTypes = { "Meat" } } },
    { "Feed your pet (content)" }, { "Feed your pet (unhappy)" })
R("hunter: no aspect, no pet", { class = "HUNTER", spells = { 1515, 13165 }, equipped = { [18] = 2504 }, ammoCount = 2000, buffs = {} },
    { "Missing Aspect of the Hawk", "Call your pet" })
R("hunter: dead pet", { class = "HUNTER", spells = { 1515, 13165 }, buffs = { { spellId = 13165 } }, pet = { dead = true } },
    { "Revive your pet" }, { "Call your pet" })
R("hunter: hawk (higher rank) active", { class = "HUNTER", spells = { 1515, 14322 }, equipped = { [18] = 2504 }, ammoCount = 2000,
    buffs = { { spellId = 14322 } }, pet = { happiness = 3, foodTypes = { "Meat" } } },
    {}, { "Missing Aspect of the Hawk", "Call your pet", "Feed your pet (unhappy)", "Feed your pet (content)" })

-- Rogue
local POISON_TEXTS = { "Apply poison to your main hand", "Apply poison to your off hand", "Apply poison to your weapons" }
R("rogue: thrown with durability needs no ammo", { class = "ROGUE", spells = { 1856 }, equipped = { [16] = 2131, [18] = 2947 }, rangedDurability = 200 },
    {}, { "Out of ammo" })
R("rogue: Poisons skill (not in spellbook), OH missing", { class = "ROGUE", spells = { 1856 }, skills = { [40] = 120 },
    equipped = { [16] = 2131, [17] = 2131 }, items = { [6947] = 30, [5140] = 20 }, enchants = { [0] = { { type = IMBUE, ms = 1800000 } } } },
    { "Apply poison to your off hand" })
R("rogue: sharpening stone doesn't count as poison", { class = "ROGUE", spells = { 1856 }, skills = { [40] = 120 },
    equipped = { [16] = 2131 }, items = { [6947] = 30, [5140] = 20 }, enchants = { [0] = { { type = TEMPORARY, ms = 1800000 } } } },
    { "Apply poison to your main hand" })
R("rogue: no poison on either weapon", { class = "ROGUE", spells = { 1856 }, skills = { [40] = 120 },
    equipped = { [16] = 2131, [17] = 2131 }, items = { [6947] = 30, [5140] = 20 } }, { "Apply poison to your weapons" })
R("rogue: poison + stone on both weapons", { class = "ROGUE", spells = { 1856 }, skills = { [40] = 120 },
    equipped = { [16] = 2131, [17] = 2131 }, items = { [6947] = 30, [5140] = 20 },
    enchants = { [0] = { { type = TEMPORARY, ms = 1800000 }, { type = IMBUE, ms = 1800000 } }, [1] = { { type = IMBUE, ms = 1700000 } } } },
    {}, POISON_TEXTS)
R("rogue: poison expiring", { class = "ROGUE", spells = { 1856 }, skills = { [40] = 120 }, equipped = { [16] = 2131 }, items = { [6947] = 30 },
    enchants = { [0] = { { type = IMBUE, ms = 45000 } } } }, { "Poison expires in 45s" })
R("rogue: no Poisons skill = no poison reminders", { class = "ROGUE", spells = { 1856 }, resting = true, equipped = { [16] = 2131 }, items = { [5140] = 20 } },
    {}, { "Make poisons (0 left)" })
R("rogue: resting, low stock + powder", { class = "ROGUE", spells = { 1856 }, skills = { [40] = 120 }, resting = true, equipped = { [16] = 2131 },
    items = { [6947] = 5, [5140] = 3 } }, { "Make poisons (5 left)", "Buy Flash Powder (3 left)" }, { "Buy water (0 left)" })
R("rogue: low Blinding Powder", { class = "ROGUE", spells = { 1856, 2094 }, resting = true, items = { [5140] = 20, [5530] = 2 } },
    { "Make Blinding Powder (2 left)" })
R("rogue: Reagent Economy keeps Blinding Powder", { class = "ROGUE", spells = { 1856, 2094 }, resting = true, reagentEconomy = true,
    items = { [5140] = 2, [5530] = 2 } }, { "Make Blinding Powder (2 left)" }, { "Buy Flash Powder (2 left)" })
R("rogue: no Blind = no powder reminder", { class = "ROGUE", spells = { 1856 }, resting = true, items = { [5140] = 20 } },
    {}, { "Make Blinding Powder (0 left)" })

-- Shaman
R("shaman: enh, no imbue/shield", { class = "SHAMAN", spells = { 324 }, talents = { 0, 15, 0 }, equipped = { [16] = 2131 },
    enchants = { [0] = { { type = TEMPORARY, ms = 1800000 } } }, buffs = {} }, { "Missing Lightning Shield", "Imbue your weapon" })
R("shaman: imbue + lightning shield present", { class = "SHAMAN", spells = { 324, 10432 }, talents = { 0, 15, 0 }, equipped = { [16] = 2131 },
    enchants = { [0] = { { type = IMBUE, ms = 1800000 } } }, buffs = { { spellId = 10432, expires = NOW + 500 } } },
    {}, { "Missing Lightning Shield", "Imbue your weapon" })
R("shaman: resting, ankh needs Reincarnation", { class = "SHAMAN", spells = { 324, 20608 }, resting = true, items = { [17030] = 1 } },
    { "Buy Ankh (1 left)" }, { "Buy Fish Oil (0 left)", "Buy Shiny Fish Scales (0 left)" })
R("shaman: totem items left in the bank", { class = "SHAMAN", spells = { 324, 8071, 3599, 5394 }, items = { [5175] = 1 } },
    { "Missing Fire Totem and Water Totem" }, { "Missing Earth Totem" })
R("shaman: one totem item missing, also while resting", { class = "SHAMAN", spells = { 8071, 10438, 8177 }, resting = true,
    items = { [5175] = 1, [5176] = 1 } }, { "Missing Air Totem" })
R("shaman: all totem items carried", { class = "SHAMAN", spells = { 8071, 3599, 5394, 8177 },
    items = { [5175] = 1, [5176] = 1, [5177] = 1, [5178] = 1 } },
    {}, { "Missing Earth Totem", "Missing Fire Totem", "Missing Water Totem", "Missing Air Totem" })
R("shaman: unlisted totem rank counts by name", { class = "SHAMAN", spells = { 900002 } }, { "Missing Fire Totem" })
R("shaman: totem reminder waits until out of combat", { class = "SHAMAN", spells = { 8071 }, inCombat = true, buffs = {} },
    {}, { "Missing Earth Totem" })
R("shaman: no totems learned, no totem reminder", { class = "SHAMAN", spells = { 324 } }, {}, { "Missing Earth Totem" })
R("shaman: elemental skips weapon imbue", { class = "SHAMAN", spells = { 324 }, talents = { 20, 5, 0 }, equipped = { [16] = 2131 },
    buffs = { { spellId = 324, expires = NOW + 500 } } }, {}, { "Imbue your weapon", "Missing Lightning Shield" })

-- Warlock
local lock = { 687, 688, 6201, 693 }
R("warlock: level 18, nothing up", { class = "WARLOCK", spells = lock, items = { [6265] = 3 }, buffs = {}, equipped = { [16] = 2131 } },
    { "Missing Demon Skin", "Summon your demon", "Create a Healthstone", "Create a Soulstone", "Collect Soul Shards (3 left)" },
    { "Apply a Firestone or Spellstone", "Missing Demon Armor" })
R("warlock: all set", { class = "WARLOCK", spells = { 687, 706, 11735, 688, 6201, 11730, 693, 17953 }, pet = {},
    items = { [6265] = 10, [19013] = 1, [16896] = 1 }, buffs = { { spellId = 11735, expires = NOW + 1000 } },
    equipped = { [16] = 2131 }, enchants = { [0] = { { type = IMBUE, ms = 3000000 } } } },
    {}, { "Missing Demon Armor", "Summon your demon", "Apply a Firestone or Spellstone", "Create a Healthstone",
        "Create a Soulstone", "Collect Soul Shards (10 left)", "Demon Armor expires in 16m 40s", "Weapon stone expires in 50m" })
R("warlock: wizard oil isn't a weapon stone", { class = "WARLOCK", spells = { 688, 2362 }, pet = {}, items = { [6265] = 10 },
    equipped = { [16] = 2131 }, enchants = { [0] = { { type = TEMPORARY, ms = 1800000 } } } },
    { "Apply a Firestone or Spellstone" })
R("warlock: weapon stone + armor expiring", { class = "WARLOCK", spells = { 706, 688, 17951 }, pet = {}, items = { [6265] = 10 },
    buffs = { { spellId = 706, expires = NOW + 45 } }, equipped = { [16] = 2131 },
    enchants = { [0] = { { type = TEMPORARY, ms = 1800000 }, { type = IMBUE, ms = 30000 } } } },
    { "Demon Armor expires in 45s", "Weapon stone expires in 30s" }, { "Apply a Firestone or Spellstone" })
R("warlock: no weapon equipped = no stone reminder", { class = "WARLOCK", spells = { 688, 17951 }, pet = {}, items = { [6265] = 10 } },
    {}, { "Apply a Firestone or Spellstone" })
R("warlock: Demonic Sacrifice = no demon on purpose", { class = "WARLOCK", spells = lock, items = { [6265] = 10, [5512] = 1, [5232] = 1 },
    buffs = { { spellId = 18791, expires = NOW + 1000 }, { spellId = 687, expires = NOW + 1000 } } },
    {}, { "Summon your demon" })
R("warlock: dead pet counts as missing", { class = "WARLOCK", spells = { 688 }, pet = { dead = true }, buffs = {} }, { "Summon your demon" })
R("warlock: soulstoned yourself, no shards", { class = "WARLOCK", spells = lock, pet = {}, items = { [6265] = 0 },
    buffs = { { spellId = 20765, expires = NOW + 1000 }, { spellId = 687, expires = NOW + 1000 } } },
    { "Collect Soul Shards (0 left)" }, { "Create a Soulstone", "Create a Healthstone" })
R("warlock: shards ok, soulstone on yourself", { class = "WARLOCK", spells = lock, pet = {}, items = { [6265] = 6, [5512] = 1 },
    buffs = { { spellId = 20707, expires = NOW + 1000 }, { spellId = 687, expires = NOW + 1000 } } },
    {}, { "Create a Soulstone", "Create a Healthstone", "Collect Soul Shards (6 left)" })
R("warlock: in combat only buff/pet reminders", { class = "WARLOCK", spells = lock, inCombat = true, items = { [6265] = 1 }, buffs = {} },
    { "Missing Demon Skin", "Summon your demon" }, { "Create a Healthstone", "Create a Soulstone", "Collect Soul Shards (1 left)" })
R("warlock: resting hides everything", { class = "WARLOCK", spells = lock, resting = true, items = { [6265] = 1 }, buffs = {} },
    {}, { "Missing Demon Skin", "Summon your demon", "Create a Healthstone", "Create a Soulstone", "Collect Soul Shards (1 left)" })
R("warlock: secret auras keep pet reminder quiet", { class = "WARLOCK", spells = { 688 }, inCombat = true, aurasSecret = true,
    buffs = { { spellId = 687, expires = NOW + 1000 } } }, {}, { "Summon your demon" })
R("warlock: Reagent Economy keeps Soul Shards", { class = "WARLOCK", spells = lock, pet = {}, items = { [6265] = 2 }, reagentEconomy = true,
    buffs = { { spellId = 687, expires = NOW + 1000 } } }, { "Collect Soul Shards (2 left)" })

-- Druid
local motw = { 1126, 9885 }
R("druid: no mark", { class = "DRUID", spells = motw, buffs = {} }, { "Missing Mark of the Wild" })
R("druid: mark expiring", { class = "DRUID", spells = motw, buffs = { { spellId = 9885, expires = NOW + 50 } } }, { "Mark of the Wild expires in 50s" })
R("druid: gift counts as mark", { class = "DRUID", spells = { 9885, 21850 }, buffs = { { spellId = 21850, expires = NOW + 3000 } } },
    {}, { "Missing Mark of the Wild", "Gift of the Wild expires in 50m" })
R("druid: travel form hides mark", { class = "DRUID", spells = motw, buffs = {}, form = 3 }, {}, { "Missing Mark of the Wild" })
R("druid: aquatic form hides mark", { class = "DRUID", spells = motw, buffs = {}, form = 4 }, {}, { "Missing Mark of the Wild" })
R("druid: cat form still shows mark", { class = "DRUID", spells = motw, buffs = {}, form = 1 }, { "Missing Mark of the Wild" })
R("druid: resting, reagents for highest ranks", { class = "DRUID", spells = { 20484, 20739, 20742, 20747, 20748, 21849, 21850 }, resting = true,
    items = { [17034] = 20, [17038] = 2, [17026] = 3, [17021] = 40 } },
    { "Buy Ironwood Seed (2 left)", "Buy Wild Thornroot (3 left)" }, { "Missing Mark of the Wild" })
R("druid: rank 1 reagents", { class = "DRUID", spells = { 20484, 21849 }, resting = true, items = { [17034] = 1, [17038] = 40 } },
    { "Buy Maple Seed (1 left)", "Buy Wild Berries (0 left)" })
R("druid: rank 3 rebirth", { class = "DRUID", spells = { 20484, 20739, 20742 }, resting = true, items = { [17036] = 9 } },
    {}, { "Buy Ashwood Seed (9 left)", "Buy Maple Seed (0 left)", "Buy Wild Berries (0 left)" })
R("druid: unlisted Rebirth rank counts every seed", { class = "DRUID", spells = { 888888 }, resting = true, items = { [17034] = 1, [17035] = 2 } },
    { "Buy Rebirth reagents (3 left)" })
R("druid: Reagent Economy hides reagents", { class = "DRUID", spells = { 20484, 21849 }, resting = true, reagentEconomy = true },
    {}, { "Buy Maple Seed (0 left)", "Buy Wild Berries (0 left)" })

-- Everyone: food buff while leveling, with food in your bags that gives it
R("leveling: no food buff", { class = "WARRIOR", level = 30, buffs = {}, bags = MEAT }, { FOOD_REMINDER })
R("leveling: Well Fed up", { class = "WARRIOR", level = 30, buffs = { { spellId = 19710, expires = NOW + 600 } }, bags = MEAT },
    {}, { FOOD_REMINDER, "Well Fed expires in 10m" })
R("leveling: food buff expiring", { class = "MAGE", level = 30, buffs = { { spellId = 24799, expires = NOW + 30 } }, bags = MEAT },
    { "Well Fed expires in 30s" })
R("leveling: no food reminder while resting", { class = "WARRIOR", level = 30, resting = true, buffs = {}, bags = MEAT },
    {}, { FOOD_REMINDER })
R("leveling: no food reminder in combat", { class = "WARRIOR", level = 30, inCombat = true, buffs = {}, bags = MEAT },
    {}, { FOOD_REMINDER })
R("max level: no food reminder", { class = "WARRIOR", level = 60, buffs = {}, bags = MEAT }, {}, { FOOD_REMINDER })
R("experience turned off: no food reminder", { class = "WARRIOR", level = 30, xpDisabled = true, buffs = {}, bags = MEAT },
    {}, { FOOD_REMINDER })
R("leveling: Forever's Well Fed counts", { class = "WARRIOR", level = 30, buffs = { { spellId = 1248406, expires = NOW + 900 } }, bags = MEAT },
    {}, { FOOD_REMINDER })
R("leveling: no food reminder while mounted", { class = "WARRIOR", level = 30, mounted = true, buffs = {}, bags = MEAT },
    {}, { FOOD_REMINDER })
R("leveling: no food reminder in Travel Form", { class = "DRUID", level = 30, form = 3, buffs = {}, bags = MEAT },
    {}, { FOOD_REMINDER })
R("leveling: no food reminder in Ghost Wolf", { class = "SHAMAN", level = 30, form = 16, buffs = {}, bags = MEAT },
    {}, { FOOD_REMINDER })
R("leveling: food reminder in Cat Form", { class = "DRUID", level = 30, form = 1, buffs = {}, bags = MEAT },
    { FOOD_REMINDER })

-- Without such food there's nothing you can do about it, so no reminder
R("food: nothing to eat", { class = "WARRIOR", level = 30, buffs = {} }, {}, { FOOD_REMINDER })
R("food: plain food gives no buff", { class = "WARRIOR", level = 30, buffs = {}, bags = JERKY }, {}, { FOOD_REMINDER })
R("food: water gives no buff", { class = "WARRIOR", level = 30, buffs = {}, bags = { { bag = 0, slot = 1, itemID = 159, count = 20 } } },
    {}, { FOOD_REMINDER })
R("food: buff food among plain food and water", { class = "WARRIOR", level = 30, buffs = {}, bags = {
    { bag = 0, slot = 1, itemID = 117, count = 5 }, { bag = 0, slot = 2, itemID = 159, count = 20 }, { bag = 0, slot = 7, itemID = 6888, count = 1 } } },
    { FOOD_REMINDER })
R("food: a drink that gives the buff counts", { class = "WARRIOR", level = 30, buffs = {}, bags = { { bag = 0, slot = 1, itemID = 900003, count = 3 } } },
    { FOOD_REMINDER })
R("food: buff running out with nothing left to eat", { class = "MAGE", level = 30, buffs = { { spellId = 24799, expires = NOW + 30 } }, bags = JERKY },
    {}, { "Well Fed expires in 30s", FOOD_REMINDER })
-- New characters are left alone until level 10
R("food: not at level 1", { class = "WARRIOR", level = 1, buffs = {}, bags = MEAT }, {}, { FOOD_REMINDER })
R("food: not at level 9", { class = "WARRIOR", level = 9, buffs = {}, bags = MEAT }, {}, { FOOD_REMINDER })
R("food: from level 10", { class = "WARRIOR", level = 10, buffs = {}, bags = MEAT }, { FOOD_REMINDER })

-- Everyone: Camp Benefits while leveling, also from level 10
R("camp: not at level 1", { class = "WARRIOR", level = 1, buffs = {} }, {}, { "Missing Camp Benefits" })
R("camp: not at level 9", { class = "WARRIOR", level = 9, buffs = {} }, {}, { "Missing Camp Benefits" })
R("camp: not at level 9 when about to expire", { class = "WARRIOR", level = 9, buffs = { { spellId = 1229741, expires = NOW + 200 } } },
    {}, { "Camp Benefits expires in 3m 20s" })
R("camp: from level 10", { class = "WARRIOR", level = 10, buffs = {} }, { "Missing Camp Benefits" })
R("leveling: no Camp Benefits", { class = "WARRIOR", level = 30, buffs = { { spellId = 1248406, expires = NOW + 900 } } },
    { "Missing Camp Benefits" }, { FOOD_REMINDER })
R("leveling: Camp Benefits up", { class = "WARRIOR", level = 30, buffs = { { spellId = 1229741, expires = NOW + 3000 } }, bags = MEAT },
    { FOOD_REMINDER }, { "Missing Camp Benefits", "Camp Benefits expires in 50m" })
R("leveling: Camp Benefits expiring (5 min warning)", { class = "WARRIOR", level = 30, buffs = { { spellId = 1229741, expires = NOW + 200 } } },
    { "Camp Benefits expires in 3m 20s" })
R("leveling: no camp reminder while resting", { class = "WARRIOR", level = 30, resting = true, buffs = {} }, {}, { "Missing Camp Benefits" })
R("leveling: no camp reminder in combat", { class = "WARRIOR", level = 30, inCombat = true, buffs = {} }, {}, { "Missing Camp Benefits" })
R("leveling: no camp reminder while mounted", { class = "WARRIOR", level = 30, mounted = true, buffs = {} }, {}, { "Missing Camp Benefits" })

-- Everyone: unspent or unconfirmed talent points, out of combat
R("talents: unspent points", { class = "WARRIOR", unspentTalents = 3 }, { "Spend 3 talent points" })
R("talents: one unspent point", { class = "WARRIOR", unspentTalents = 1 }, { "Spend 1 talent point" })
R("talents: changes not applied", { class = "WARRIOR", stagedTalents = true }, { "Apply your talent changes" }, { "Spend 0 talent points" })
R("talents: all spent", { class = "WARRIOR", talents = { 31, 20, 0 } }, {}, { "Apply your talent changes", "Spend 0 talent points" })
R("talents: nothing in combat", { class = "WARRIOR", inCombat = true, unspentTalents = 3, stagedTalents = true }, {},
    { "Spend 3 talent points", "Apply your talent changes" })
-- Everyone: unspent Legacy points, out of combat
R("legacy: unspent points in two trees", { class = "WARRIOR", unspentLegacy = { 2, 0, 3 } }, { "Spend 5 Legacy points" })
R("legacy: one unspent point", { class = "WARRIOR", unspentLegacy = { 0, 1, 0 } }, { "Spend 1 Legacy point" })
R("legacy: a currency shared by the trees counts once", { class = "WARRIOR", unspentLegacy = 4 }, { "Spend 4 Legacy points" })
R("legacy: all spent", { class = "WARRIOR" }, {}, { "Spend 0 Legacy points" })
R("legacy: nothing in combat", { class = "WARRIOR", inCombat = true, unspentLegacy = 4 }, {}, { "Spend 4 Legacy points" })
R("legacy: at max level too", { class = "WARRIOR", level = 60, unspentLegacy = { 1, 1, 0 } }, { "Spend 2 Legacy points" })
R("legacy: next to talent points", { class = "WARRIOR", unspentTalents = 2, unspentLegacy = 4 },
    { "Spend 2 talent points", "Spend 4 Legacy points" })
R("max level: no camp reminder", { class = "WARRIOR", level = 60, buffs = {} }, {}, { "Missing Camp Benefits" })

-- Everyone
R("mana user: low water (incl. reagent bag) + repair", { class = "PRIEST", spells = {}, resting = true, level = 40,
    bags = { { bag = 0, slot = 1, itemID = 159, count = 5 }, { bag = 5, slot = 2, itemID = 159, count = 2 } }, equipped = { [1] = 2131 }, headDurability = 40 },
    { "Buy water (7 left)", "Repair your gear (40%)" })
R("repair: slightly worn gear (80%) is above the default 70%", { class = "WARRIOR", resting = true, level = 40,
    equipped = { [1] = 2131 }, headDurability = 80 }, {}, { "Repair your gear (80%)" })
R("water: not below the minimum level", { class = "PRIEST", spells = {}, resting = true, level = 5 }, {}, { "Buy water (0 left)", "Buy food (0 left)" })
R("druid: bear form still a mana user (water)", { class = "DRUID", spells = {}, resting = true, level = 40, form = 5,
    bags = { { bag = 0, slot = 1, itemID = 159, count = 5 } } }, { "Buy water (5 left)" })
R("future (unlearned) spells are ignored", { class = "MAGE", spells = {}, futureSpells = { 1459 }, buffs = {} },
    {}, { "Missing Arcane Intellect" })

-- Buff data hidden during combat: Forever refuses add-on aura scans, so stay quiet
do
    local en, de = R("combat restrictions: no buff reminders", { class = "PALADIN", spells = pal, inCombat = true, aurasSecret = true, buffs = {} },
        {}, { "Missing Devotion Aura", "Missing Blessing of Might" })
    Check("combat restrictions: no aura scans attempted", en.__auraScans == 0 and de.__auraScans == 0, en.__auraScans .. "/" .. de.__auraScans)
end
-- Outside combat restrictions single buffs can be secret: "missing" only when it can't be one of them
R("one secret buff: never-secret blessing missing", { class = "PALADIN", spells = pal, secretBuffs = { [465] = true },
    neverSecret = { [19740] = true }, buffs = { { spellId = 465 } } }, { "Missing Blessing of Might" }, { "Missing Devotion Aura" })
R("one secret buff: could be the blessing", { class = "PALADIN", spells = pal, secretBuffs = { [19740] = true },
    buffs = { { spellId = 465 }, { spellId = 19740, expires = NOW + 200 } } }, {}, { "Missing Blessing of Might", "Missing Devotion Aura" })

-- Water Shield (new in Forever) is recognised by its English name until its spell ID is known
Run("enUS shaman: Water Shield recognised by name", { class = "SHAMAN", spells = { 324, 900001 }, time = NOW,
    buffs = { { spellId = 900001, expires = NOW + 500 } } }, {}, { "Missing Lightning Shield", "Missing Water Shield" })
do
    local env = Run("deDE shaman: Water Shield not recognised yet", { class = "SHAMAN", spells = { 324, 900001 }, time = NOW, locale = "deDE",
        buffs = { { spellId = 900001, expires = NOW + 500 } } })
    Check("deDE shaman: shield reminder shows", VisibleIDs(env):find("shaman_shield_buff", 1, true) ~= nil, VisibleIDs(env))
end

-- Teleports to Forever-only places are recognised by how their name starts, in any language
Run("enUS unlisted Forever teleport (shared name prefix)", { class = "MAGE", spells = { 777777 }, resting = true, time = NOW },
    { "Buy Rune of Teleportation (0 left)" })
do
    local env = Run("deDE unlisted Forever teleport (shared name prefix)", { class = "MAGE", spells = { 777777 }, resting = true, time = NOW, locale = "deDE" })
    Check("deDE unlisted teleport: rune reminder shows", VisibleIDs(env):find("mage_rune_teleport", 1, true) ~= nil, VisibleIDs(env))
end
Run("a druid's Moonglade teleport doesn't need runes", { class = "DRUID", spells = { 18960 }, resting = true, time = NOW },
    {}, { "Buy Rune of Teleportation (0 left)" })

------------------------------------------------------------------------
-- New reminders
------------------------------------------------------------------------
-- Buy food (everyone but mages), from the food-and-water level
R("food: buy food in town", { class = "WARRIOR", level = 30, resting = true, bags = JERKY }, { "Buy food (5 left)" })
R("food: not for mages", { class = "MAGE", level = 30, resting = true, bags = JERKY }, {}, { "Buy food (5 left)" })
R("food: not below the minimum level", { class = "WARRIOR", level = 5, resting = true, bags = JERKY }, {}, { "Buy food (5 left)" })
R("food: not out adventuring", { class = "WARRIOR", level = 30, bags = JERKY }, {}, { "Buy food (5 left)" })

-- Hearthstone left in the bank
R("hearthstone: missing", { class = "WARRIOR", noHearthstone = true }, { "Missing Hearthstone" })
R("hearthstone: carried", { class = "WARRIOR" }, {}, { "Missing Hearthstone" })
R("hearthstone: not in combat", { class = "WARRIOR", noHearthstone = true, inCombat = true }, {}, { "Missing Hearthstone" })

-- Bandages once you know First Aid
local BANDAGES = { { bag = 0, slot = 1, itemID = 1251, count = 3 } }
R("bandages: low with First Aid", { class = "WARRIOR", resting = true, skills = { [129] = 75 }, bags = BANDAGES }, { "Make bandages (3 left)" })
R("bandages: not without First Aid", { class = "WARRIOR", resting = true, bags = BANDAGES }, {}, { "Make bandages (3 left)" })

-- Gear about to break: anywhere, even in combat; in town it replaces the repair reminder
local SWORD = { [16] = 2131 }
R("gear: about to break", { class = "WARRIOR", equipped = SWORD, durability = { [16] = { 5, 100 } } }, { "Shortsword is about to break (5%)" })
R("gear: broken", { class = "WARRIOR", equipped = SWORD, durability = { [16] = { 0, 100 } } }, { "Shortsword is broken" })
R("gear: broken, in combat too", { class = "WARRIOR", equipped = SWORD, durability = { [16] = { 0, 100 } }, inCombat = true }, { "Shortsword is broken" })
R("gear: broken, in town no second repair line", { class = "WARRIOR", resting = true, equipped = SWORD, durability = { [16] = { 0, 100 } } },
    { "Shortsword is broken" }, { "Repair your gear (50%)" })
R("gear: worn item is fine at 30%", { class = "WARRIOR", equipped = SWORD, durability = { [16] = { 30, 100 } } }, {}, { "Shortsword is about to break (30%)" })
-- One worn-out item makes the repair reminder show, even if gear as a whole is fine
R("repair: one item below 25%", { class = "WARRIOR", resting = true, equipped = SWORD,
    durability = { [5] = { 100, 100 }, [7] = { 100, 100 }, [16] = { 20, 100 } } }, { "Repair your gear (Shortsword at 20%)" })
R("repair: every item above 25%", { class = "WARRIOR", resting = true, equipped = SWORD,
    durability = { [5] = { 100, 100 }, [7] = { 100, 100 }, [16] = { 30, 100 } } }, {}, { "Repair your gear (Shortsword at 30%)" })

-- Mages conjure water and food, anywhere out of combat
local WATER3 = { { bag = 0, slot = 1, itemID = 5350, count = 3 } }
R("mage: conjure water", { class = "MAGE", spells = { 5504, 5505 }, bags = WATER3 }, { "Conjure water (3 left)" })
R("mage: conjure water in town too", { class = "MAGE", spells = { 5504 }, resting = true, bags = WATER3 }, { "Conjure water (3 left)" })
R("mage: not in combat", { class = "MAGE", spells = { 5504 }, inCombat = true, bags = WATER3 }, {}, { "Conjure water (3 left)" })
R("mage: conjure food", { class = "MAGE", spells = { 587 }, bags = { { bag = 0, slot = 1, itemID = 5349, count = 2 } } },
    { "Conjure food (2 left)" }, { "Conjure water (0 left)" })
R("mage: enough water", { class = "MAGE", spells = { 5504 }, bags = { { bag = 0, slot = 1, itemID = 5350, count = 40 } } },
    {}, { "Conjure water (40 left)" })

-- Pet taunts on autocast in dungeon and raid groups
local GROWL_ON = { { spellID = 17253, autocast = true }, { spellID = 14921, autocast = true } }
R("hunter: Growl on autocast in a dungeon group", { class = "HUNTER", spells = { 1515 }, pet = { happiness = 3 }, petActions = GROWL_ON,
    inGroup = true, instanceType = "party" }, { "Turn off Growl autocast" })
R("hunter: Growl is fine outside instances", { class = "HUNTER", spells = { 1515 }, pet = { happiness = 3 }, petActions = GROWL_ON,
    inGroup = true }, {}, { "Turn off Growl autocast" })
R("hunter: Growl is fine solo in a dungeon", { class = "HUNTER", spells = { 1515 }, pet = { happiness = 3 }, petActions = GROWL_ON,
    instanceType = "party" }, {}, { "Turn off Growl autocast" })
R("hunter: Growl off", { class = "HUNTER", spells = { 1515 }, pet = { happiness = 3 }, inGroup = true, instanceType = "raid",
    petActions = { { spellID = 17253, autocast = true }, { spellID = 14921, autocast = false } } }, {}, { "Turn off Growl autocast" })
R("warlock: Torment on autocast in a raid", { class = "WARLOCK", spells = { 697 }, pet = {}, inRaid = true, instanceType = "raid",
    petActions = { { spellID = 11775, autocast = true } }, buffs = {} }, { "Turn off Torment autocast" })

-- Righteous Fury on while not tanking
local RF_UP = { { spellId = 25780, expires = NOW + 1500 } }
R("paladin: Righteous Fury on as Holy in a dungeon group", { class = "PALADIN", spells = { 25780 }, talents = { 31, 5, 0 }, inGroup = true,
    instanceType = "party", buffs = RF_UP }, { "Turn off Righteous Fury (not tanking)" })
R("paladin: Righteous Fury on as Protection", { class = "PALADIN", spells = { 25780 }, talents = { 5, 31, 0 }, inGroup = true,
    instanceType = "party", buffs = RF_UP }, {}, { "Turn off Righteous Fury (not tanking)" })
R("paladin: Righteous Fury outside instances", { class = "PALADIN", spells = { 25780 }, talents = { 31, 5, 0 }, inGroup = true,
    buffs = RF_UP }, {}, { "Turn off Righteous Fury (not tanking)" })
R("paladin: Righteous Fury off", { class = "PALADIN", spells = { 25780 }, talents = { 31, 5, 0 }, inGroup = true,
    instanceType = "party", buffs = {} }, {}, { "Turn off Righteous Fury (not tanking)" })

------------------------------------------------------------------------
-- Joining a group: supplies on screen for a minute, one line in group chat
------------------------------------------------------------------------
local function JoinGroup(env, S, kind)
    S[kind or "inGroup"] = true
    env.__fire("GROUP_JOINED", 1, "Party-0001")
end
local function Messages(env)
    local out = {}
    for _, m in ipairs(env.__chat) do out[#out + 1] = m.chatType .. ": " .. m.message end
    return table.concat(out, " || ")
end
-- A hunter with plenty of water and pet food, gear at 47% and 150 arrows
local function Hunter(extra)
    local S = { class = "HUNTER", spells = { 1515, 13165 }, equipped = { [18] = 2504, [1] = 2131 }, headDurability = 47,
        ammoCount = 150, pet = { happiness = 3, foodTypes = { "Meat" }, canEat = { [117] = true } }, buffs = { { spellId = 13165 } },
        bags = { { bag = 0, slot = 1, itemID = 117, count = 40 }, { bag = 0, slot = 2, itemID = 159, count = 60 } } }
    for k, v in pairs(extra or {}) do S[k] = v end
    return S
end
local WATER = { { bag = 0, slot = 2, itemID = 159, count = 60 } }
local HUNTER_MESSAGE = "PARTY: [Prepped] you're at 47% durability and low on ammo (150 left), remember to repair soon and buy more ammo."

do
    local S = Hunter()
    local env = Setup(S)
    JoinGroup(env, S)
    env.__tick(1)
    Check("group: waits a moment after joining", #env.__chat == 0, Messages(env))
    env.__tick(2)
    Check("group: one message in party chat", Messages(env) == HUNTER_MESSAGE, Messages(env))
    env.__fire("GROUP_JOINED", 1, "Party-0001")
    env.__tick(5)
    Check("group: only once per group", #env.__chat == 1, Messages(env))
    S.inGroup = false
    env.__fire("GROUP_LEFT", 1, "Party-0001")
    JoinGroup(env, S)
    env.__tick(3)
    Check("group: again in the next group", #env.__chat == 2, Messages(env))
    Check("group: no Lua errors", #env.__errors == 0, table.concat(env.__errors, " || "))
end

do
    -- Raids only with "Also Post in Raids": a raid doesn't need a line from everyone
    local S = Hunter()
    local env = Setup(S)
    JoinGroup(env, S, "inRaid")
    env.__tick(3)
    Check("group: no raid chat by default", #env.__chat == 0, Messages(env))
    local S1 = Hunter()
    local env1 = Setup(S1, function(P) P:SetRuleEnabled("general_group_announce_raids", true) end)
    JoinGroup(env1, S1, "inRaid")
    env1.__tick(3)
    Check("group: raid chat with Also Post in Raids", env1.__chat[1] ~= nil and env1.__chat[1].chatType == "RAID", Messages(env1))
    local S2 = Hunter()
    local env2 = Setup(S2)
    JoinGroup(env2, S2, "instanceGroup")
    env2.__tick(3)
    Check("group: instance chat in an instance group", env2.__chat[1] ~= nil and env2.__chat[1].chatType == "INSTANCE_CHAT", Messages(env2))
end

-- Waits while it can't or shouldn't post, then sends once; gives up after a minute
for _, case in ipairs({ { "chatLockdown", "while Forever blocks add-on chat" }, { "inCombat", "in combat" }, { "dead", "while dead" } }) do
    local S = Hunter({ [case[1]] = true })
    local env = Setup(S)
    JoinGroup(env, S)
    env.__tick(10)
    Check("group: waits " .. case[2], #env.__chat == 0, Messages(env))
    S[case[1]] = false
    env.__tick(2)
    Check("group: sends after waiting " .. case[2], Messages(env) == HUNTER_MESSAGE, Messages(env))
end
do
    local S = Hunter({ chatLockdown = true })
    local env = Setup(S)
    JoinGroup(env, S)
    env.__tick(65)
    S.chatLockdown = false
    env.__tick(5)
    Check("group: gives up after a minute", #env.__chat == 0, Messages(env))
end

do
    local S = Hunter({ headDurability = 60, ammoCount = 3000 })
    local env = Setup(S)
    JoinGroup(env, S)
    env.__tick(3)
    Check("group: nothing worth saying, no message (60% is above the 50% repair limit)", #env.__chat == 0, Messages(env))
    local S2 = Hunter({ headDurability = 60, ammoCount = 3000 })
    local env2 = Setup(S2, function(P) P:SetRuleThreshold("general_group_announce", 90) end)
    JoinGroup(env2, S2)
    env2.__tick(3)
    Check("group: repair limit is a setting", Messages(env2) == "PARTY: [Prepped] you're at 60% durability, remember to repair soon.", Messages(env2))
end

for _, rule in ipairs({ "general_group_announce", "general_master" }) do
    local S = Hunter()
    local env = Setup(S, function(P) P:SetRuleEnabled(rule, false) end)
    JoinGroup(env, S)
    env.__tick(5)
    Check("group: no message with " .. rule .. " off", #env.__chat == 0, Messages(env))
end

-- Supply reminders on screen for a minute after joining, even outside cities
do
    local S = { class = "ROGUE", spells = { 1856 }, items = { [5140] = 3 } }
    local env = Setup(S)
    env.Prepped:CheckReminders()
    Check("group check: supplies hidden outside cities before joining", not Has(VisibleReminders(env), "Buy Flash Powder (3 left)"))
    JoinGroup(env, S)
    env.__tick(1)
    Check("group check: shown after joining a group", Has(VisibleReminders(env), "Buy Flash Powder (3 left)"), Shown(env))
    env.__tick(60)
    Check("group check: hidden again after a minute", not Has(VisibleReminders(env), "Buy Flash Powder (3 left)"))

    local S2 = { class = "ROGUE", spells = { 1856 }, items = { [5140] = 3 } }
    local env2 = Setup(S2, function(P) P:SetRuleEnabled("general_group_check", false) end)
    JoinGroup(env2, S2)
    env2.__tick(1)
    Check("group check off: stays hidden outside cities", not Has(VisibleReminders(env2), "Buy Flash Powder (3 left)"))
    env2.__tick(3)
    Check("group check off: the group message still names it",
        Messages(env2) == "PARTY: [Prepped] you're low on Flash Powder (3 left), remember to buy more Flash Powder.", Messages(env2))
end

-- Names in the message
for _, case in ipairs({
    { { class = "SHAMAN", spells = { 8071, 3599, 5394 }, items = { [5175] = 1 }, bags = WATER },
        "PARTY: [Prepped] you're missing your Fire Totem and Water Totem, remember to check your bank." },
    { { class = "PRIEST", spells = { 21562, 21564 }, items = { [17029] = 2 }, bags = WATER },
        "PARTY: [Prepped] you're low on Sacred Candle (2 left), remember to buy more Sacred Candle." },
    { { class = "DRUID", spells = { 20484, 20739, 20742, 20747, 20748 }, items = { [17038] = 1 }, bags = WATER },
        "PARTY: [Prepped] you're low on Ironwood Seed (1 left), remember to buy more Ironwood Seed." },
    { { class = "WARLOCK", spells = { 688, 6201, 693 }, pet = {}, items = { [6265] = 2, [5512] = 1 }, bags = WATER },
        "PARTY: [Prepped] you're missing a Soulstone and low on Soul Shards (2 left), remember to create a Soulstone and farm more Soul Shards." },
    { { class = "WARRIOR", equipped = SWORD, durability = { [16] = { 0, 100 } } },
        "PARTY: [Prepped] you're at 0% durability on your Shortsword, remember to repair soon." },
    -- at most three things, the rest is left out
    { Hunter({ headDurability = 30, bags = { { bag = 0, slot = 1, itemID = 117, count = 5 } } }),
        "PARTY: [Prepped] you're low on water (0 left), at 30% durability and low on ammo (150 left), remember to buy more water, repair soon and buy more ammo." },
}) do
    local S = case[1]
    local env = Setup(S)
    JoinGroup(env, S)
    env.__tick(3)
    Check("group message: " .. case[2], Messages(env) == case[2], Messages(env))
end

------------------------------------------------------------------------
-- Vendors: supply reminders while you talk to one, even outside cities
------------------------------------------------------------------------
do
    local S = { class = "ROGUE", spells = { 1856 }, items = { [5140] = 3 } }
    local env = Setup(S)
    env.Prepped:CheckReminders()
    Check("vendor: supplies hidden outside cities", not Has(VisibleReminders(env), "Buy Flash Powder (3 left)"))
    env.__fire("MERCHANT_SHOW")
    env.__tick(0.3)
    Check("vendor: shown while talking to a vendor", Has(VisibleReminders(env), "Buy Flash Powder (3 left)"), Shown(env))
    env.__fire("MERCHANT_CLOSED")
    env.__tick(0.3)
    Check("vendor: hidden again afterwards", not Has(VisibleReminders(env), "Buy Flash Powder (3 left)"), Shown(env))
    env.Prepped:SetRuleEnabled("general_vendor_check", false)
    env.__fire("MERCHANT_SHOW")
    env.__tick(0.3)
    Check("vendor: off", not Has(VisibleReminders(env), "Buy Flash Powder (3 left)"), Shown(env))
end

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
    Check("debug: display state", DebugValue(env, "Display") == "position default, grows down, icons true, clickable true, unlocked false, text language enUS",
        DebugValue(env, "Display"))
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

do
    local env = Setup(Hunter({ petActions = GROWL_ON }))
    pcall(env.SlashCmdList.PREPPED, "debug")
    Check("debug: group message preview", "PARTY: " .. tostring(DebugValue(env, "Group message when joining")) == HUNTER_MESSAGE,
        DebugValue(env, "Group message when joining"))
    Check("debug: pet actions", DebugValue(env, "Pet actions") == "Bite 17253 (autocast), Growl 14921 (autocast)", DebugValue(env, "Pet actions"))
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
    { class = "MAGE", spells = { 3561, 777777 }, locale = "deDE", expect = "Recognised by name, ID not listed: DE:Teleport: Stonard 777777" },
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
    local env = Mock.BuildEnv({ class = "DRUID", spells = { 1126 }, time = NOW, form = 1, bags = WATER })
    LoadAddon(env)
    pcall(env.SlashCmdList.PREPPED, "debug")
    local out = table.concat(env.__printed, "\n")
    Check("debug: druid shapeshift form", out:find("Shapeshift form ID: 1", 1, true) ~= nil, out)
    Check("debug: nothing to say to a group", DebugValue(env, "Group message when joining") == "nothing to report",
        DebugValue(env, "Group message when joining"))
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
        Check("options: label and description for " .. rule.id, type(rule.label) == "string" and type(rule.description) == "string")
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

    -- the "Warn when expiring" row follows its rule's checkbox, and its slider shows minutes
    local mageLayout
    for _, c in ipairs(env.__categories) do if c.name == "Mage" then mageLayout = c.layout end end
    local warnRow
    for _, init in ipairs(mageLayout.initializers) do
        if init.kind == "checkboxSlider" and init.data.cbSetting.variable == "PREPPED_mage_ai_buff_LOW" then warnRow = init end
    end
    Check("options: warn row is a child row", warnRow and warnRow.parent ~= nil and warnRow.predicate ~= nil)
    Check("options: expiring slider shows minutes", warnRow and warnRow.data.options.formatter(90) == "1m 30s", warnRow and warnRow.data.options.formatter(90))
    S.PREPPED_mage_ai_buff:SetValue(false)
    Check("options: warn row disabled when rule is off", warnRow and warnRow.predicate() == false)
    S.PREPPED_mage_ai_buff:SetValue(true)
    Check("options: warn row enabled when rule is on", warnRow and warnRow.predicate() == true)

    -- toggles and thresholds drive the reminders
    P:CheckReminders()
    Check("options: low ammo shown by default", Has(VisibleReminders(env), "Buy ammo (150 left)"), Shown(env))
    S.PREPPED_hunter_ammo_low:SetValue(false)
    Check("options: rule off hides reminder", not Has(VisibleReminders(env), "Buy ammo (150 left)"))
    Check("options: rule setting reads back", S.PREPPED_hunter_ammo_low:GetValue() == false and P:IsRuleEnabled("hunter_ammo_low") == false)
    S.PREPPED_hunter_ammo_low:SetValue(true)
    S.PREPPED_hunter_ammo_low_THRESHOLD:SetValue(100.4)
    Check("options: threshold rounded and stored", P:GetRuleThreshold("hunter_ammo_low") == 100)
    Check("options: below new threshold hides reminder", not Has(VisibleReminders(env), "Buy ammo (150 left)"))

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
    Check("options: display defaults", S.PREPPED_SHOW_ICONS:GetValue() == true and S.PREPPED_GROW_UP:GetValue() == false
        and S.PREPPED_CLICKABLE:GetValue() == true)
    S.PREPPED_GROW_UP:SetValue(true)
    Check("options: grow upwards", P:GetDisplayOption("growUp") == true and S.PREPPED_GROW_UP:GetValue() == true)

    -- the Appearance page's buttons
    local buttons = {}
    for _, c in ipairs(env.__categories) do
        if c.name == "Appearance" then
            for _, init in ipairs(c.layout.initializers) do if init.kind == "button" then buttons[init.data.name] = init.data end end
        end
    end
    Check("options: move and reset position buttons", buttons["Move Reminders"] ~= nil and buttons["Reset Position"] ~= nil)
    buttons["Move Reminders"].click()
    Check("options: Move Reminders unlocks them", P.Display:IsUnlocked())
    P.Display:SetUnlocked(false)

    -- reset everything
    env.StaticPopupDialogs.PREPPED_RESET_ALL_SETTINGS.OnAccept()
    Check("options: reset thresholds", P:GetRuleThreshold("hunter_ammo_low") == 1000)
    Check("options: reset appearance", P:GetAppearance().fontSize == 18 and S.PREPPED_BG_OPACITY:GetValue() == 50 and P:GetDisplayOption("growUp") == false)
    Check("options: reset refreshes controls", S.PREPPED_FONT_SIZE.notified > 0)

    -- opening the options
    local ok, err = pcall(env.SlashCmdList.PREPPED, "")
    Check("/prepped opens the Prepped page", ok and env.__opened[#env.__opened] == env.__addonCategory.ID, tostring(err))
    ok, err = pcall(env.Prepped_OpenOptions)
    Check("minimap AddOns menu opens options", ok and #env.__opened == 2, tostring(err))
    P:OpenOptions("Mage")
    local magePage
    for _, c in ipairs(env.__categories) do if c.name == "Mage" then magePage = c end end
    Check("options: open on a class page", env.__opened[#env.__opened] == magePage.ID)
    Check("options: no Lua errors", #env.__errors == 0, table.concat(env.__errors, " || "))
end

-- A broken options UI must not stop the reminders
do
    local env = Mock.BuildEnv({ class = "HUNTER", spells = { 1515, 13165 }, resting = true, time = NOW, equipped = { [18] = 2504 }, ammoCount = 150, breakSettings = true })
    local ok, err = pcall(LoadAddon, env)
    Check("broken options: addon still loads", ok, err)
    if ok then
        env.Prepped:CheckReminders()
        Check("broken options: reminders still work", Has(VisibleReminders(env), "Buy ammo (150 left)"), Shown(env))
        Check("broken options: error reported once", #env.__errors == 1 and env.__errors[1]:find("settings broken", 1, true) ~= nil,
            table.concat(env.__errors, " || "))
    end
end

------------------------------------------------------------------------
-- Scheduling and cost: events are coalesced, nothing is polled 10x a second
------------------------------------------------------------------------
-- Counts the full reminder checks from now on.
local function CountChecks(env)
    local P, counter = env.Prepped, { n = 0 }
    local original = P.CheckReminders
    P.CheckReminders = function(self, ...)
        counter.n = counter.n + 1
        return original(self, ...)
    end
    return counter
end

do
    -- A leveling priest in the open world: four buff reminders (Fortitude, Inner Fire, food, camp)
    local S = { class = "PRIEST", level = 30, spells = { 1243, 588 }, time = NOW, bags = MEAT,
        buffs = { { spellId = 1243, expires = NOW + 1000 }, { spellId = 588, expires = NOW + 1000 } } }
    local env = Setup(S)
    env.__tick(1)
    local checks = CountChecks(env)

    for _ = 1, 25 do env.__fire("BAG_UPDATE", 0) end
    env.__tick(0.3)
    Check("cost: a burst of 25 bag updates costs one check", checks.n == 1, checks.n)

    checks.n = 0
    local scansBefore = env.__auraScans
    env.__tick(10)
    Check("cost: idle, about one check per second (was ten)", checks.n >= 8 and checks.n <= 11, checks.n)
    -- 2 buffs = 3 reads per scan; one scan per 5 s at most while nothing changes (was one per buff rule per check)
    Check("cost: idle, buffs are read once per change, not per check", env.__auraScans - scansBefore <= 3 * 3,
        env.__auraScans - scansBefore)

    -- Health changes (every hit in combat) don't trigger checks at all
    env.Prepped:CheckReminders()
    checks.n = 0
    for _ = 1, 50 do env.__fire("UNIT_HEALTH", "player"); env.__fire("UNIT_HEALTH", "pet") end
    env.__tick(0.5)
    Check("cost: health events aren't listened to", checks.n == 0, checks.n)

    -- A buff change still shows up right away
    S.buffs = { { spellId = 588, expires = NOW + 1000 } }
    env.__fire("UNIT_AURA", "player")
    env.__tick(0.3)
    Check("cost: a buff change shows within a fraction of a second", Has(VisibleReminders(env), "Missing Power Word: Fortitude"), Shown(env))
    Check("cost: no Lua errors", #env.__errors == 0, table.concat(env.__errors, " || "))
end

do
    -- Water is counted once per change of the bags, not on every check
    local S = { class = "PRIEST", level = 40, spells = {}, resting = true, time = NOW,
        bags = { { bag = 0, slot = 1, itemID = 159, count = 5 } } }
    local env = Setup(S)
    env.__tick(1)
    Check("bags: water counted", Has(VisibleReminders(env), "Buy water (5 left)"), Shown(env))
    local reads = env.__bagSlotReads
    env.__tick(10)
    Check("bags: no rescans while the bags don't change", env.__bagSlotReads == reads, env.__bagSlotReads - reads)
    S.bags[1].count = 3
    env.__fire("BAG_UPDATE", 0)
    env.__tick(0.3)
    Check("bags: rescanned after a bag update", Has(VisibleReminders(env), "Buy water (3 left)"), Shown(env))
end

do
    -- Water whose item data was still loading (just after login) is counted once it arrives
    local S = { class = "PRIEST", level = 40, spells = {}, resting = true, time = NOW, uncachedItems = { [159] = true },
        bags = { { bag = 0, slot = 1, itemID = 159, count = 50 } } }
    local env = Setup(S)
    env.__tick(1)
    Check("item data: not counted before it loads", Has(VisibleReminders(env), "Buy water (0 left)"), Shown(env))
    S.uncachedItems = nil
    env.__fire("GET_ITEM_INFO_RECEIVED", 159, true)
    env.__tick(0.3)
    Check("item data: counted once it loads", not Has(VisibleReminders(env), "Buy water (0 left)"), Shown(env))
    local checks = CountChecks(env)
    env.Prepped:CheckReminders()
    checks.n = 0
    for i = 1, 20 do env.__fire("GET_ITEM_INFO_RECEIVED", 1000 + i, true) end
    env.__tick(0.5)
    Check("item data: other items loading (auction house, tooltips) don't trigger checks", checks.n == 0, checks.n)
end

do
    -- Item names come from the client once their data has loaded
    local S = { class = "PALADIN", spells = { 25782 }, resting = true, time = NOW, items = { [21177] = 3 }, uncachedItems = { [21177] = true } }
    local env = Setup(S)
    env.__tick(1)
    Check("item names: English name while loading", Has(VisibleReminders(env), "Buy Symbol of Kings (3 left)"), Shown(env))
    local de = Setup(Copy(S, { locale = "deDE", uncachedItems = {} }))
    de.__tick(1)
    Check("item names: the client's name once loaded", Shown(de):find("DE:Symbol of Kings", 1, true) ~= nil, Shown(de))
end

do
    -- Building the group message (or /prepped debug) is a dry run: it doesn't draw the supplies it looks at
    local S = { class = "ROGUE", spells = { 1856 }, items = { [5140] = 3 }, time = NOW }
    local env = Setup(S)
    env.Prepped:CheckReminders()
    pcall(env.SlashCmdList.PREPPED, "debug")
    Check("dry run: debug doesn't put supply reminders on screen", not Has(VisibleReminders(env), "Buy Flash Powder (3 left)"), Shown(env))
    Check("dry run: but the group message still sees them",
        DebugValue(env, "Group message when joining") == "[Prepped] you're low on Flash Powder (3 left), remember to buy more Flash Powder.",
        DebugValue(env, "Group message when joining"))
end

------------------------------------------------------------------------
-- Settings: versioned, sparse, defaults from the rules
------------------------------------------------------------------------
do
    local env = Mock.BuildEnv({ class = "PRIEST", spells = { 1243 }, time = NOW })
    -- Settings saved by v2.3.0: every default written out, plus rules that no longer exist
    env.PreppedSettings = {
        useAccountWide = true,
        global = {
            enabledRules = { general_master = true, priest_fortitude = true, priest_inner_fire = false, paladin_seal = true },
            enabledLowRules = { priest_fortitude = true, general_water = true, mage_ai_buff = false },
            thresholds = { priest_fortitude = 60, priest_candles = 25, general_repair = 100, warrior_battle_shout = 30, hunter_ammo_low = 99999 },
        },
        profiles = { ["Other - Realm"] = { enabledRules = { druid_mark = true }, enabledLowRules = {}, thresholds = { druid_mark = 120 } } },
        appearance = { fontSize = 22, minWidth = 400, fontColor = { r = 1, g = 1, b = 1 }, bgColor = { r = 0, g = 0, b = 0, a = 0.3 } },
    }
    LoadAddon(env)
    local P, saved = env.Prepped, env.PreppedSettings
    local g = saved.global
    Check("settings: upgraded to schema 2", saved.schemaVersion == 2, saved.schemaVersion)
    Check("settings: removed rules dropped", g.enabledRules.paladin_seal == nil and g.thresholds.warrior_battle_shout == nil)
    Check("settings: stored defaults dropped", g.enabledRules.priest_fortitude == nil and g.enabledRules.general_master == nil
        and g.thresholds.priest_fortitude == nil and g.thresholds.general_repair == nil
        and g.enabledLowRules.priest_fortitude == nil and g.enabledLowRules.general_water == nil)
    Check("settings: the player's own choices kept", g.enabledRules.priest_inner_fire == false and g.thresholds.priest_candles == 25
        and g.enabledLowRules.mage_ai_buff == false)
    Check("settings: out-of-range threshold clamped", g.thresholds.hunter_ammo_low == 4000, g.thresholds.hunter_ammo_low)
    local other = saved.profiles["Other - Realm"]
    Check("settings: other characters upgraded too", other.thresholds.druid_mark == 120 and other.enabledRules.druid_mark == nil)
    Check("settings: appearance kept", saved.appearance.fontSize == 22 and saved.appearance.bgColor.a == 0.3)
    Check("settings: display options default", P:GetDisplayOption("showIcons") == true and P:GetDisplayOption("clickable") == true
        and saved.appearance.showIcons == nil and saved.appearance.position == nil)
    Check("settings: defaults still apply", P:GetRuleThreshold("priest_fortitude") == 60 and P:IsRuleEnabled("priest_fortitude") == true
        and P:IsRuleEnabled("priest_inner_fire") == false)
    Check("settings: no Lua errors", #env.__errors == 0, table.concat(env.__errors, " || "))

    local fresh = Setup({ class = "PRIEST", spells = { 1243 } })
    fresh.Prepped:CheckReminders()
    local fg = fresh.PreppedSettings.global
    Check("settings: a fresh install stores no defaults", next(fg.thresholds) == nil and next(fg.enabledRules) == nil
        and next(fg.enabledLowRules) == nil and fresh.PreppedSettings.schemaVersion == 2)

    local newer = Mock.BuildEnv({ class = "PRIEST", spells = { 1243 }, time = NOW })
    newer.PreppedSettings = { schemaVersion = 99, useAccountWide = true,
        global = { enabledRules = { future_rule = true }, enabledLowRules = {}, thresholds = { priest_fortitude = 60 } }, profiles = {} }
    LoadAddon(newer)
    Check("settings: from a newer Prepped (downgrade) left alone", newer.PreppedSettings.schemaVersion == 99
        and newer.PreppedSettings.global.enabledRules.future_rule == true and newer.PreppedSettings.global.thresholds.priest_fortitude == 60)

    -- broken display values are dropped
    local broken = Mock.BuildEnv({ class = "PRIEST", spells = { 1243 }, time = NOW })
    broken.PreppedSettings = { schemaVersion = 2, appearance = { showIcons = "yes", position = { x = "left" } } }
    LoadAddon(broken)
    Check("settings: broken display values repaired", broken.PreppedSettings.appearance.showIcons == nil
        and broken.PreppedSettings.appearance.position == nil and #broken.__errors == 0)
end

do
    -- A new per-character profile uses the rule's default (60 s), as the options show it
    local S = { class = "SHAMAN", spells = { 324 }, time = NOW, buffs = { { spellId = 324, expires = NOW + 30 } } }
    local env = Setup(S)
    env.Prepped:SetAccountWide(false)
    env.Prepped:CheckReminders()
    Check("settings: per-character profile uses the default warning time", Has(VisibleReminders(env), "Lightning Shield expires in 30s"), Shown(env))
end

------------------------------------------------------------------------
-- Reagents: Legacy perks Prepped doesn't know yet are detected by the client
------------------------------------------------------------------------
do
    local S = { class = "MAGE", spells = { 1459, 23028, 3561 }, resting = true, time = NOW, reagentFreeSpells = { [23028] = true } }
    local env = Setup(S)
    env.Prepped:CheckReminders()
    local shown = VisibleReminders(env)
    Check("reagents: Arcane Brilliance castable without powder hides the powder reminder",
        not Has(shown, "Buy Arcane Powder (0 left)"), table.concat(shown, " | "))
    Check("reagents: other reagents still needed", Has(shown, "Buy Rune of Teleportation (0 left)"), table.concat(shown, " | "))

    S.items = { [17020] = 3 }
    env.__fire("BAG_UPDATE", 0)
    env.__tick(0.3)
    Check("reagents: remembered after picking up a few", not Has(VisibleReminders(env), "Buy Arcane Powder (3 left)"))
    pcall(env.SlashCmdList.PREPPED, "debug")
    Check("reagents: listed in /prepped debug", DebugValue(env, "Spells seen working without their reagent") == "Arcane Brilliance 23028",
        DebugValue(env, "Spells seen working without their reagent"))

    S.reagentFreeSpells = nil
    env.__fire("TRAIT_CONFIG_UPDATED", 1)
    env.__tick(0.3)
    Check("reagents: forgotten when the perks change", Has(VisibleReminders(env), "Buy Arcane Powder (3 left)"), Shown(env))
end

for _, case in ipairs({
    { "candles for the rank you know", { class = "PRIEST", spells = { 21562, 21564 }, reagentFreeSpells = { [21564] = true } },
        {}, { "Buy Sacred Candle (0 left)" } },
    { "Rebirth seeds", { class = "DRUID", spells = { 20484 }, reagentFreeSpells = { [20484] = true } }, {}, { "Buy Maple Seed (0 left)" } },
    { "Symbols of Kings", { class = "PALADIN", spells = { 25782, 19752 }, reagentFreeSpells = { [25782] = true } },
        { "Buy Symbol of Divinity (0 left)" }, { "Buy Symbol of Kings (0 left)" } },
    -- Reincarnation only works while dead, so the client can't tell: keep reminding
    { "Ankhs (Reincarnation can't be tested)", { class = "SHAMAN", spells = { 20608 } }, { "Buy Ankh (0 left)" }, {} },
    -- Reagent Economy only covers vendor reagents
    { "Blinding Powder isn't covered by Reagent Economy", { class = "ROGUE", spells = { 1856, 2094 }, reagentEconomy = true, items = { [5140] = 0 } },
        { "Make Blinding Powder (0 left)" }, { "Buy Flash Powder (0 left)" } },
}) do
    local S = case[2]
    S.resting, S.time = true, NOW
    Run("reagents: " .. case[1], S, case[3], case[4])
end

do
    local env = Mock.BuildEnv({ class = "ROGUE", spells = { 1856 }, time = NOW, reagentEconomy = true })
    LoadAddon(env)
    pcall(env.SlashCmdList.PREPPED, "debug")
    Check("debug: Legacy perks listed", DebugValue(env, "Legacy perks") == "Some Other Perk 999999, Reagent Economy 1262650",
        DebugValue(env, "Legacy perks"))
    Check("debug: unspent Legacy points", DebugValue(env, "Unspent Legacy points")
        == "0 (tree 1187 currency 1187: 0, tree 1188 currency 1188: 0, tree 1189 currency 1189: 0)",
        DebugValue(env, "Unspent Legacy points"))
end

------------------------------------------------------------------------
-- Context: travel, combat, instances of "can't act on it right now"
------------------------------------------------------------------------
Run("mage: no buff reminders while mounted", { class = "MAGE", spells = { 1459, 168 }, mounted = true, buffs = {}, time = NOW },
    {}, { "Missing Arcane Intellect", "Missing Frost Armor" })
Run("shaman: no shield/imbue reminders in Ghost Wolf", { class = "SHAMAN", spells = { 324 }, form = 16, buffs = {}, time = NOW,
    equipped = { [16] = 2131 } }, {}, { "Missing Lightning Shield", "Imbue your weapon" })
Run("shaman: no shield/imbue reminders while mounted", { class = "SHAMAN", spells = { 324 }, mounted = true, buffs = {}, time = NOW,
    equipped = { [16] = 2131 } }, {}, { "Missing Lightning Shield", "Imbue your weapon" })
Run("shaman: expiring shield and imbue", { class = "SHAMAN", spells = { 324 }, talents = { 0, 15, 0 }, time = NOW, equipped = { [16] = 2131 },
    buffs = { { spellId = 324, expires = NOW + 30 } }, enchants = { [0] = { { type = IMBUE, ms = 40000 } } } },
    { "Lightning Shield expires in 30s", "Weapon imbue expires in 40s" })
Run("hunter: unhappy pet waits until out of combat", { class = "HUNTER", spells = { 1515 }, inCombat = true, time = NOW,
    pet = { happiness = 1, foodTypes = { "Meat" } } }, {}, { "Feed your pet (unhappy)" })
Run("rogue: no poison reminder without a weapon", { class = "ROGUE", spells = { 1856 }, skills = { [40] = 120 }, items = { [6947] = 30 }, time = NOW },
    {}, POISON_TEXTS)

do
    -- Supply windows (joining a group, ready checks) wait while you're in combat
    local S = { class = "ROGUE", spells = { 1856 }, items = { [5140] = 3 }, time = NOW, inCombat = true }
    local env = Setup(S, function(P) P:SetRuleEnabled("general_group_announce", false) end)
    JoinGroup(env, S)
    env.__tick(1)
    Check("group check: not during combat", not Has(VisibleReminders(env), "Buy Flash Powder (3 left)"))
    S.inCombat = false
    env.__fire("PLAYER_REGEN_ENABLED")
    env.__tick(0.3)
    Check("group check: shown once combat ends", Has(VisibleReminders(env), "Buy Flash Powder (3 left)"), Shown(env))
end

do
    -- Outside town during the group window a hunter sees "critical", not also "low"
    local S = Hunter({ ammoCount = 150 })
    local env = Setup(S, function(P) P:SetRuleEnabled("general_group_announce", false) end)
    JoinGroup(env, S)
    env.__tick(1)
    local shown = VisibleReminders(env)
    Check("hunter: critical ammo shown in the group window", Has(shown, "Ammo almost gone (150 left)"), table.concat(shown, " | "))
    Check("hunter: low ammo left out next to critical", not Has(shown, "Buy ammo (150 left)"), table.concat(shown, " | "))
end

------------------------------------------------------------------------
-- Ready checks, bag space, snoozing, sound
------------------------------------------------------------------------
do
    -- Ready check: supplies on screen until it's over
    local S = { class = "ROGUE", spells = { 1856 }, items = { [5140] = 3 }, inGroup = true, time = NOW }
    local env = Setup(S)
    env.Prepped:CheckReminders()
    Check("ready check: supplies hidden before", not Has(VisibleReminders(env), "Buy Flash Powder (3 left)"))
    env.__fire("READY_CHECK", "Leader", 35)
    env.__tick(0.3)
    Check("ready check: supplies shown", Has(VisibleReminders(env), "Buy Flash Powder (3 left)"), Shown(env))
    env.__fire("READY_CHECK_FINISHED", false)
    env.__tick(0.3)
    Check("ready check: hidden when it's over", not Has(VisibleReminders(env), "Buy Flash Powder (3 left)"))

    local S2 = { class = "ROGUE", spells = { 1856 }, items = { [5140] = 3 }, inGroup = true, time = NOW }
    local env2 = Setup(S2, function(P) P:SetRuleEnabled("general_ready_check", false) end)
    env2.__fire("READY_CHECK", "Leader", 35)
    env2.__tick(0.3)
    Check("ready check: off", not Has(VisibleReminders(env2), "Buy Flash Powder (3 left)"))
end

Run("bags: low bag space in town", { class = "WARRIOR", resting = true, freeBagSlots = 2, time = NOW }, { "Free up bag space (2 free)" })
Run("bags: enough bag space", { class = "WARRIOR", resting = true, freeBagSlots = 10, time = NOW }, {}, { "Free up bag space (10 free)" })
Run("bags: not out adventuring", { class = "WARRIOR", freeBagSlots = 2, time = NOW }, {}, { "Free up bag space (2 free)" })

do
    -- /prepped snooze hides what's on screen for a while
    local S = { class = "PRIEST", spells = { 1243 }, buffs = {}, time = NOW }
    local env = Setup(S)
    env.Prepped:CheckReminders()
    Check("snooze: reminder shown first", Has(VisibleReminders(env), "Missing Power Word: Fortitude"), Shown(env))
    env.SlashCmdList.PREPPED("snooze 10")
    Check("snooze: hidden", not Has(VisibleReminders(env), "Missing Power Word: Fortitude"))
    Check("snooze: confirmed in chat", LastPrinted(env):find("Snoozed 1 reminder for 10 minutes", 1, true) ~= nil, LastPrinted(env))
    env.__tick(9 * 60)
    Check("snooze: still hidden after 9 minutes", not Has(VisibleReminders(env), "Missing Power Word: Fortitude"))
    env.__tick(61)
    Check("snooze: back after 10 minutes", Has(VisibleReminders(env), "Missing Power Word: Fortitude"), Shown(env))
    env.SlashCmdList.PREPPED("snooze")
    Check("snooze: default length", not Has(VisibleReminders(env), "Missing Power Word: Fortitude"))
    -- kept across a /reload
    local reloaded = Relaunch(env, S, true)
    reloaded.Prepped:CheckReminders()
    Check("snooze: kept after a /reload", not Has(VisibleReminders(reloaded), "Missing Power Word: Fortitude"), Shown(reloaded))
    reloaded.SlashCmdList.PREPPED("unsnooze")
    Check("snooze: unsnooze brings it back", Has(VisibleReminders(reloaded), "Missing Power Word: Fortitude"), Shown(reloaded))
    Check("snooze: unsnooze confirmed", LastPrinted(reloaded):find("1 snoozed reminder is back.", 1, true) ~= nil, LastPrinted(reloaded))
    reloaded.SlashCmdList.PREPPED("snooze")
    reloaded.Prepped:Unsnooze()
    reloaded.SlashCmdList.PREPPED("unsnooze")
    Check("snooze: nothing to bring back", LastPrinted(reloaded):find("0 snoozed reminders are back.", 1, true) ~= nil, LastPrinted(reloaded))
    Check("snooze: no Lua errors", #env.__errors + #reloaded.__errors == 0, table.concat(env.__errors, " || "))
end

do
    -- Optional sound: off by default; once per reminder per cooldown; never in combat
    local FORT = { spellId = 1243, expires = NOW + 100000 }
    local S = { class = "PRIEST", spells = { 1243 }, buffs = { FORT }, time = NOW }
    local quiet = Setup({ class = "PRIEST", spells = { 1243 }, buffs = {}, time = NOW })
    quiet.__tick(2)
    Check("sound: off by default", #quiet.__sounds == 0, #quiet.__sounds)

    local env = Setup(S, function(P) P:SetRuleEnabled("general_sound", true) end)
    local function SetBuff(present)
        S.buffs = present and { FORT } or {}
        env.__fire("UNIT_AURA", "player")
        env.__tick(0.3)
    end
    env.__tick(1)
    SetBuff(false)
    Check("sound: plays when a reminder appears", #env.__sounds == 1, #env.__sounds)
    env.__tick(15)
    SetBuff(true)
    SetBuff(false)
    Check("sound: not again within the cooldown", #env.__sounds == 1, #env.__sounds)
    SetBuff(true)
    env.__tick(5 * 60)
    SetBuff(false)
    Check("sound: again after the cooldown (5 minutes)", #env.__sounds == 2, #env.__sounds)
    SetBuff(true)
    env.__tick(5 * 60)
    S.inCombat = true
    env.__fire("PLAYER_REGEN_DISABLED")
    SetBuff(false)
    Check("sound: never in combat", #env.__sounds == 2, #env.__sounds)
    Check("sound: no Lua errors", #env.__errors == 0, table.concat(env.__errors, " || "))
end

------------------------------------------------------------------------
-- Food buff: which food in your bags gives it is read from the item tooltips
------------------------------------------------------------------------
-- Where tooltips can't tell (they word the buff differently, or the client has no
-- tooltip data), any food counts; drinks don't
for _, case in ipairs({ { "tooltipsDontNameBuff", "tooltips don't name the buff" }, { "noTooltipAPI", "no tooltip data" } }) do
    local function FoodRun(label, bags, shown, hidden)
        Run("food, " .. case[2] .. ": " .. label, { class = "WARRIOR", level = 30, buffs = {}, bags = bags, time = NOW, [case[1]] = true },
            shown, hidden)
    end
    FoodRun("any food counts", JERKY, { FOOD_REMINDER })
    FoodRun("buff food counts", MEAT, { FOOD_REMINDER })
    FoodRun("water doesn't count", WATER, {}, { FOOD_REMINDER })
    FoodRun("other items don't count", { { bag = 0, slot = 1, itemID = 2131, count = 1 } }, {}, { FOOD_REMINDER })
    FoodRun("nothing to eat", {}, {}, { FOOD_REMINDER })
end

do
    -- Just after login item data is still loading: no reminder until Prepped can tell
    local S = { class = "WARRIOR", level = 30, buffs = {}, bags = MEAT, uncachedItems = { [2680] = true, [6888] = true } }
    local env = Setup(S)
    env.__tick(1)
    Check("food: not while item data is loading", not Has(VisibleReminders(env), FOOD_REMINDER), Shown(env))
    S.uncachedItems = nil
    env.__fire("GET_ITEM_INFO_RECEIVED", 2680, true)
    env.__tick(0.3)
    Check("food: shown once item data has loaded", Has(VisibleReminders(env), FOOD_REMINDER), Shown(env))
    Check("food: no Lua errors while loading", #env.__errors == 0, table.concat(env.__errors, " || "))

    -- The same for food in your bags that the client hasn't loaded yet
    local S2 = { class = "WARRIOR", level = 30, buffs = {}, bags = { { bag = 0, slot = 1, itemID = 6888, count = 2 } }, uncachedItems = { [6888] = true } }
    local env2 = Setup(S2)
    env2.__tick(1)
    Check("food: not while the food's own data is loading", not Has(VisibleReminders(env2), FOOD_REMINDER), Shown(env2))
    S2.uncachedItems = nil
    env2.__fire("GET_ITEM_INFO_RECEIVED", 6888, true)
    env2.__tick(0.3)
    Check("food: shown once the food's own data has loaded", Has(VisibleReminders(env2), FOOD_REMINDER), Shown(env2))
end

do
    -- Plain food doesn't show up in the meantime either
    local S = { class = "WARRIOR", level = 30, buffs = {}, bags = JERKY, uncachedItems = { [2680] = true, [6888] = true } }
    local env = Setup(S)
    local flashed = false
    for _ = 1, 50 do
        env.__tick(0.1)
        flashed = flashed or Has(VisibleReminders(env), FOOD_REMINDER)
    end
    Check("food: plain food doesn't flash while item data is loading", not flashed)
    -- If that data never arrives Prepped stops waiting, and any food counts
    env.__tick(8)
    Check("food: stops waiting for item data after 10 seconds", Has(VisibleReminders(env), FOOD_REMINDER), Shown(env))
    S.uncachedItems = nil
    env.__fire("GET_ITEM_INFO_RECEIVED", 2680, true)
    env.__tick(0.3)
    Check("food: tooltips are used once the data does arrive", not Has(VisibleReminders(env), FOOD_REMINDER), Shown(env))
end

do
    -- Bags and tooltips are read once per change of the bags, not on every check
    local TWO_STACKS = { { bag = 0, slot = 1, itemID = 117, count = 20 }, { bag = 0, slot = 2, itemID = 117, count = 5 },
        { bag = 0, slot = 4, itemID = 2131, count = 1 } } -- and a sword, which isn't food
    local S = { class = "WARRIOR", level = 30, buffs = {}, bags = TWO_STACKS }
    local env = Setup(S)
    env.__tick(1)
    Check("food: plain food, no reminder", not Has(VisibleReminders(env), FOOD_REMINDER), Shown(env))
    local slotReads, tooltipReads = env.__bagSlotReads, env.__tooltipReads
    env.__tick(10)
    Check("food: no rescans while the bags don't change", env.__bagSlotReads == slotReads and env.__tooltipReads == tooltipReads,
        (env.__bagSlotReads - slotReads) .. " slot reads, " .. (env.__tooltipReads - tooltipReads) .. " tooltip reads")
    env.__fire("BAG_UPDATE", 0)
    env.__tick(0.3)
    Check("food: one tooltip read for two stacks of the same food, none for other items", env.__tooltipReads - tooltipReads == 1,
        env.__tooltipReads - tooltipReads)

    S.bags = { TWO_STACKS[1], TWO_STACKS[2], TWO_STACKS[3], { bag = 0, slot = 3, itemID = 2680, count = 1 } }
    env.__fire("BAG_UPDATE", 0)
    env.__tick(0.3)
    Check("food: shown after picking up buff food", Has(VisibleReminders(env), FOOD_REMINDER), Shown(env))
    S.bags = TWO_STACKS
    env.__fire("BAG_UPDATE", 0)
    env.__tick(0.3)
    Check("food: hidden again after eating the last of it", not Has(VisibleReminders(env), FOOD_REMINDER), Shown(env))

    -- Safety net: looked at again after a minute even without a bag event
    slotReads = env.__bagSlotReads
    env.__tick(59)
    Check("food: still no rescan within a minute", env.__bagSlotReads == slotReads, env.__bagSlotReads - slotReads)
    env.__tick(3)
    Check("food: rescanned after a minute", env.__bagSlotReads > slotReads)
    Check("food: no Lua errors", #env.__errors == 0, table.concat(env.__errors, " || "))
end

do
    -- The leveling reminders start when a character (here with buff food) reaches level 10
    local S = { class = "WARRIOR", level = 9, buffs = {}, bags = MEAT }
    local env = Setup(S)
    env.__tick(1)
    Check("leveling: no reminders at all at level 9", #VisibleReminders(env) == 0, Shown(env))
    S.level = 10
    env.__fire("PLAYER_LEVEL_UP", 10)
    env.__tick(0.3)
    Check("food: shown on reaching level 10", Has(VisibleReminders(env), FOOD_REMINDER), Shown(env))
    Check("camp: shown on reaching level 10", Has(VisibleReminders(env), "Missing Camp Benefits"), Shown(env))
end

do
    -- /prepped debug lists the food and drink in your bags and what counts as buff food
    local BAGS = { { bag = 0, slot = 1, itemID = 117, count = 5 }, { bag = 0, slot = 2, itemID = 159, count = 20 },
        { bag = 0, slot = 3, itemID = 2680, count = 5 }, { bag = 0, slot = 4, itemID = 117, count = 20 }, { bag = 0, slot = 5, itemID = 2131, count = 1 } }
    local env = Setup({ class = "WARRIOR", level = 30, buffs = {}, bags = BAGS })
    pcall(env.SlashCmdList.PREPPED, "debug")
    Check("debug: food and drink in your bags",
        DebugValue(env, "Food and drink in your bags") == "Refreshing Spring Water 159, Spiced Wolf Meat 2680 (food buff), Tough Jerky 117",
        DebugValue(env, "Food and drink in your bags"))
    Check("debug: tooltips name the food buff", DebugValue(env, "Food tooltips name the food buff") == "yes",
        DebugValue(env, "Food tooltips name the food buff"))

    local vague = Setup({ class = "WARRIOR", level = 30, buffs = {}, bags = BAGS, tooltipsDontNameBuff = true })
    pcall(vague.SlashCmdList.PREPPED, "debug")
    Check("debug: any food counts where tooltips can't tell",
        DebugValue(vague, "Food and drink in your bags") == "Refreshing Spring Water 159, Spiced Wolf Meat 2680 (food buff), Tough Jerky 117 (food buff)"
        and DebugValue(vague, "Food tooltips name the food buff") == "no (any food counts)",
        tostring(DebugValue(vague, "Food and drink in your bags")) .. " / " .. tostring(DebugValue(vague, "Food tooltips name the food buff")))

    local loading = Setup({ class = "WARRIOR", level = 30, buffs = {}, bags = BAGS, uncachedItems = { [2680] = true, [6888] = true } })
    pcall(loading.SlashCmdList.PREPPED, "debug")
    Check("debug: food while item data is loading", DebugValue(loading, "Food tooltips name the food buff") == "item data still loading"
        and DebugValue(loading, "Food and drink in your bags") == "? 2680, Refreshing Spring Water 159, Tough Jerky 117",
        tostring(DebugValue(loading, "Food and drink in your bags")) .. " / " .. tostring(DebugValue(loading, "Food tooltips name the food buff")))
    Check("debug: no Lua errors (food)", #env.__errors + #vague.__errors + #loading.__errors == 0)
end

------------------------------------------------------------------------
-- The reminder bars: position, moving, growing up, icons, preview
------------------------------------------------------------------------
do
    local S = { class = "PRIEST", spells = { 1243, 588 }, buffs = {}, time = NOW }
    local env = Setup(S)
    local P = env.Prepped
    local D = P.Display
    P:CheckReminders()
    local container = env.PreppedContainer
    local point, relativeTo, relativePoint, x, y = container:GetPoint(1)
    Check("bars: default place, 300 px above the centre of the screen", point == "TOP" and relativeTo == env.UIParent
        and relativePoint == "CENTER" and x == 0 and y == 300, table.concat({ tostring(point), tostring(relativePoint), tostring(x), tostring(y) }, " "))
    local first, second = P.displayLines[1], P.displayLines[2]
    Check("bars: the first bar at the top", first:GetTop() == 840, first:GetTop())
    Check("bars: the second below the first", second:GetTop() < first:GetBottom(), second:GetTop() .. " / " .. first:GetBottom())
    Check("bars: icon of the spell to cast", first.icon:IsShown() and first.icon:GetTexture() == "spellicon:1243", tostring(first.icon:GetTexture()))

    -- Moving: samples you can drag, saved where you drop them
    env.SlashCmdList.PREPPED("move")
    Check("move: unlocked", D:IsUnlocked() and D.mover:IsShown())
    Check("move: told how", LastPrinted(env):find("Drag the reminders", 1, true) ~= nil, LastPrinted(env))
    Check("move: samples instead of the reminders", not first:IsShown() and D.previewBars[1]:IsShown() and D.previewBars[3]:IsShown())
    Check("move: above the options window", container:GetFrameStrata() == "FULLSCREEN_DIALOG")
    Check("move: no click buttons while moving", not env.PreppedReminderButton1:IsShown())
    env.__drag(D.mover, 100, -50)
    local position = P:GetAppearance().position
    Check("move: position saved", position and position.x == 100 and position.y == 250,
        position and (position.x .. "," .. position.y) or "nil")
    point, relativeTo, relativePoint, x, y = container:GetPoint(1)
    Check("move: anchored where it was dropped", point == "TOP" and relativePoint == "CENTER" and x == 100 and y == 250)
    -- arrow keys nudge it, other keys still reach the game
    env.__enter(D.mover)
    Check("move: hints in the tooltip", table.concat(env.__tooltipLines(), " / "):find("Arrow keys", 1, true) ~= nil)
    env.__key(D.mover, "UP")
    Check("nudge: 1 pixel up", P:GetAppearance().position.y == 251)
    S.shift = true
    env.__key(D.mover, "LEFT")
    S.shift = false
    Check("nudge: 10 pixels with Shift", P:GetAppearance().position.x == 90)
    env.__key(D.mover, "W")
    Check("nudge: other keys pass through", D.mover.__propagate == true)
    env.__key(D.mover, "ESCAPE")
    Check("move: Escape locks", not D:IsUnlocked() and not D.mover:IsShown())
    Check("move: reminders back after locking", first:IsShown() and not D.previewBars[1]:IsShown() and container:GetFrameStrata() == "MEDIUM")
    env.SlashCmdList.PREPPED("unlock")
    env.__mouseUp(D.mover, "RightButton")
    Check("move: right-click locks", not D:IsUnlocked())
    env.SlashCmdList.PREPPED("move")
    env.SlashCmdList.PREPPED("move")
    Check("move: /prepped move toggles", not D:IsUnlocked() and LastPrinted(env):find("Reminders locked.", 1, true) ~= nil, LastPrinted(env))

    -- Edit Mode moves them too
    env.__callback("EditMode.Enter")
    Check("edit mode: unlocks", D:IsUnlocked())
    env.__callback("EditMode.Exit")
    Check("edit mode: locks when done", not D:IsUnlocked())

    -- Not in combat; and combat locks them
    S.inCombat = true
    env.SlashCmdList.PREPPED("unlock")
    Check("move: not in combat", not D:IsUnlocked() and LastPrinted(env):find("can't move the reminders in combat", 1, true) ~= nil, LastPrinted(env))
    S.inCombat = false
    env.SlashCmdList.PREPPED("unlock")
    S.inCombat = true
    env.__fire("PLAYER_REGEN_DISABLED")
    Check("move: entering combat locks", not D:IsUnlocked())
    S.inCombat = false
    env.__fire("PLAYER_REGEN_ENABLED")
    env.__tick(0.3)

    -- The position is kept after a /reload, and can be reset
    local reloaded = Relaunch(env, S, true)
    point, relativeTo, relativePoint, x, y = reloaded.PreppedContainer:GetPoint(1)
    Check("move: kept after a /reload", x == 90 and y == 251, tostring(x) .. "," .. tostring(y))
    reloaded.Prepped.Display:ResetPosition()
    point, relativeTo, relativePoint, x, y = reloaded.PreppedContainer:GetPoint(1)
    Check("move: reset position", x == 0 and y == 300 and reloaded.Prepped:GetAppearance().position == nil)

    -- Growing upwards: anchored at the bottom, the second bar above the first
    P:SetDisplayOption("growUp", true)
    point = container:GetPoint(1)
    Check("grow up: anchored by the bottom edge", point == "BOTTOM", point)
    Check("grow up: the second bar above the first", second:GetBottom() > first:GetTop(), second:GetBottom() .. " / " .. first:GetTop())
    P:SetDisplayOption("growUp", false)

    -- Icons can be turned off
    P:SetDisplayOption("showIcons", false)
    Check("icons: off", not first.icon:IsShown())
    P:SetDisplayOption("showIcons", true)
    Check("icons: on again", first.icon:IsShown())
    Check("bars: no Lua errors or blocked actions", #env.__errors == 0 and #env.__blocked == 0,
        table.concat(env.__errors, " || ") .. table.concat(env.__blocked, ", "))
end

do
    -- Changing how they look shows samples for a moment, above the options window
    local S = { class = "PRIEST", spells = { 1243 }, buffs = {}, time = NOW }
    local env = Setup(S)
    local P = env.Prepped
    P:CheckReminders()
    env.__settings.PREPPED_FONT_SIZE:SetValue(22)
    Check("preview: samples after an appearance change", P.Display.previewBars[1]:IsShown() and not P.displayLines[1]:IsShown())
    Check("preview: above the options window", env.PreppedContainer:GetFrameStrata() == "FULLSCREEN_DIALOG")
    Check("preview: samples use the new font size", P.Display.previewBars[1].text.__fontSize == 22)
    env.__tick(9)
    Check("preview: gone after a few seconds", not P.Display.previewBars[1]:IsShown() and P.displayLines[1]:IsShown()
        and env.PreppedContainer:GetFrameStrata() == "MEDIUM")
    Check("preview: reminders use the new font size", P.displayLines[1].text.__fontSize == 22)
end

------------------------------------------------------------------------
-- Clicking: left-click fixes, right-click snoozes; never in combat
------------------------------------------------------------------------
do
    local S = { class = "MAGE", spells = { 1459, 1460 }, buffs = {}, time = NOW }
    local env = Setup(S)
    local P = env.Prepped
    P:CheckReminders()
    local button, bar = env.PreppedReminderButton1, P.displayLines[1]
    Check("click: a button over the reminder", button ~= nil and button:IsShown())
    Check("click: casts Arcane Intellect on you", ActionFor(env, "Missing Arcane Intellect") == "spell spell=Arcane Intellect unit=player",
        ActionFor(env, "Missing Arcane Intellect"))
    Check("click: covers the icon and text, not the whole bar", button:GetWidth() < bar:GetWidth() and button:GetHeight() == bar:GetHeight(),
        button:GetWidth() .. " / " .. bar:GetWidth())
    local bx, by = button:GetCenter()
    local cx, cy = bar:GetCenter()
    Check("click: centred on the bar", bx == cx and by == cy, bx .. "," .. by .. " / " .. cx .. "," .. cy)
    env.__click(button, "LeftButton")
    local action = env.__actions[1]
    Check("click: the cast happens", action and action.type == "spell" and action.spell == "Arcane Intellect" and action.unit == "player")
    -- the tooltip explains both buttons
    local tooltip = TooltipFor(env, "Missing Arcane Intellect")
    Check("click: tooltip", tooltip:find("Missing Arcane Intellect", 1, true) == 1 and tooltip:find("Left-click: Cast Arcane Intellect", 1, true) ~= nil
        and tooltip:find("Right-click: snooze or turn off", 1, true) ~= nil, tooltip)
    env.__enter(button)
    Check("click: the bar lights up under the mouse", bar.hover:IsShown())
    env.__leave(button)
    Check("click: and stops", not bar.hover:IsShown())

    -- Combat: the button goes away before the lockdown, the bars keep updating
    S.inCombat = true
    env.__fire("PLAYER_REGEN_DISABLED")
    Check("combat: button put away", not button:IsShown())
    S.buffs = { { spellId = 1460, expires = NOW + 1800 } }
    env.__fire("UNIT_AURA", "player")
    env.__tick(0.5)
    Check("combat: reminder gone when the buff is back", #VisibleReminders(env) == 0, Shown(env))
    S.buffs = {}
    env.__fire("UNIT_AURA", "player")
    env.__tick(0.5)
    Check("combat: reminder back, still no button", Has(VisibleReminders(env), "Missing Arcane Intellect") and not button:IsShown(), Shown(env))
    Check("combat: no secure frame touched in combat", #env.__blocked == 0, table.concat(env.__blocked, ", "))
    S.inCombat = false
    env.__fire("PLAYER_REGEN_ENABLED")
    env.__tick(0.3)
    Check("combat: button back afterwards", button:IsShown())

    -- Someone else's tooltip (a mob you're hovering) stays when combat starts
    local other = env.CreateFrame("Frame")
    env.GameTooltip:SetOwner(other)
    env.GameTooltip:SetText("Kobold Miner")
    env.GameTooltip:Show()
    S.inCombat = true
    env.__fire("PLAYER_REGEN_DISABLED")
    Check("combat: other tooltips are left alone", env.GameTooltip:IsShown())
    S.inCombat = false
    env.__fire("PLAYER_REGEN_ENABLED")
    env.__tick(0.3)

    -- "Clickable Reminders" off: no buttons, clicks go to the world
    P:SetDisplayOption("clickable", false)
    Check("clickable off: no button", not button:IsShown())
    P:SetDisplayOption("clickable", true)
    Check("clickable on: button again", button:IsShown())
end

do
    -- Right-click: snooze for a while, until the next login, or turn it off
    local S = { class = "MAGE", spells = { 1459 }, buffs = {}, time = NOW }
    local env = Setup(S)
    local P = env.Prepped
    P:CheckReminders()
    env.__click(env.PreppedReminderButton1, "RightButton")
    local items = {}
    for _, item in ipairs(env.__menu and env.__menu.items or {}) do items[#items + 1] = item.text or "-" end
    Check("menu: entries", table.concat(items, "|") == "Missing Arcane Intellect|Snooze for 15 minutes|Snooze for 1 hour|Snooze until next login|-|Turn off this reminder|Open settings",
        table.concat(items, "|"))
    Check("menu: no secure action on right-click", #env.__actions == 0)
    env.__menuClick("Snooze for 15 minutes")
    Check("menu: snoozed", #VisibleReminders(env) == 0, Shown(env))
    env.__tick(14 * 60)
    Check("menu: still snoozed after 14 minutes", #VisibleReminders(env) == 0, Shown(env))
    env.__tick(61)
    Check("menu: back after 15 minutes", Has(VisibleReminders(env), "Missing Arcane Intellect"), Shown(env))

    env.__click(env.PreppedReminderButton1, "RightButton")
    env.__menuClick("Snooze until next login")
    env.__tick(3 * 3600)
    Check("menu: until next login: hidden for hours", #VisibleReminders(env) == 0, Shown(env))
    local reloaded = Relaunch(env, S, true)
    reloaded.Prepped:CheckReminders()
    Check("menu: until next login: kept after a /reload", #VisibleReminders(reloaded) == 0, Shown(reloaded))
    local relogged = Relaunch(reloaded, S, false)
    relogged.Prepped:CheckReminders()
    Check("menu: until next login: back after logging in", Has(VisibleReminders(relogged), "Missing Arcane Intellect"), Shown(relogged))

    relogged.__click(relogged.PreppedReminderButton1, "RightButton")
    relogged.__menuClick("Open settings")
    local magePage
    for _, c in ipairs(relogged.__categories) do if c.name == "Mage" then magePage = c end end
    Check("menu: opens the reminder's settings page", relogged.__opened[#relogged.__opened] == magePage.ID)
    relogged.__click(relogged.PreppedReminderButton1, "RightButton")
    relogged.__menuClick("Turn off this reminder")
    Check("menu: turned off", not relogged.Prepped:IsRuleEnabled("mage_ai_buff") and #VisibleReminders(relogged) == 0
        and relogged.__settings.PREPPED_mage_ai_buff:GetValue() == false)
    Check("menu: says how to turn it back on", LastPrinted(relogged):find("Missing Arcane Intellect is off", 1, true) ~= nil, LastPrinted(relogged))
    Check("menu: no Lua errors", #env.__errors + #reloaded.__errors + #relogged.__errors == 0)

    -- Without a menu system, right-click snoozes right away
    local plain = Setup({ class = "MAGE", spells = { 1459 }, buffs = {}, time = NOW, noMenuUtil = true })
    plain.Prepped:CheckReminders()
    plain.__click(plain.PreppedReminderButton1, "RightButton")
    Check("menu: none on this client, snoozed for 15 minutes", #VisibleReminders(plain) == 0
        and LastPrinted(plain):find("snoozed for 15 minutes", 1, true) ~= nil, LastPrinted(plain))
end

-- What a left-click does, per reminder
local function ClickCase(label, S, text, expected, before)
    S.time = S.time or NOW
    local env = Setup(S)
    if before then before(env, S) end
    env.Prepped:CheckReminders()
    Check("click: " .. label, ActionFor(env, text) == expected, ActionFor(env, text) .. " | " .. Shown(env))
    return env
end
local MAGE_ARMORS = { 168, 7302, 6117 }
local function RemoveBuffs(env, S) S.buffs = {}; env.__fire("UNIT_AURA", "player"); env.__tick(0.3) end
local function HadBuff(spellId) return function(env, S) S.buffs = { { spellId = spellId } }; env.Prepped:CheckReminders(); RemoveBuffs(env, S) end end

ClickCase("the armor you had up last", { class = "MAGE", spells = MAGE_ARMORS }, "Missing Mage Armor", "spell spell=Mage Armor", HadBuff(6117))
ClickCase("Ice Armor takes over from Frost Armor", { class = "MAGE", spells = MAGE_ARMORS }, "Missing Ice Armor", "spell spell=Ice Armor", HadBuff(168))
ClickCase("the aura you had up last", { class = "PALADIN", spells = { 465, 7294 } }, "Missing Retribution Aura", "spell spell=Retribution Aura", HadBuff(7294))
ClickCase("a blessing goes on you", { class = "PALADIN", spells = { 19740, 19742 } }, "Missing Blessing of Might", "spell spell=Blessing of Might unit=player")
ClickCase("Aspect of the Cheetah isn't remembered", { class = "HUNTER", spells = { 13165, 5118 } }, "Missing Aspect of the Hawk",
    "spell spell=Aspect of the Hawk", HadBuff(5118))
ClickCase("Call Pet", { class = "HUNTER", spells = { 1515 } }, "Call your pet", "spell spell=Call Pet")
ClickCase("Revive Pet", { class = "HUNTER", spells = { 1515 }, pet = { dead = true } }, "Revive your pet", "spell spell=Revive Pet")
ClickCase("feed your pet food it eats", { class = "HUNTER", spells = { 1515 }, pet = { happiness = 1, foodTypes = { "Meat" }, canEat = { [117] = true } },
    bags = { { bag = 0, slot = 2, itemID = 4536, count = 5 }, { bag = 0, slot = 3, itemID = 117, count = 5 } } },
    "Feed your pet (unhappy)", "macro macrotext=/cast Feed Pet\n/use 0 3")
ClickCase("no food the pet eats: nothing to click", { class = "HUNTER", spells = { 1515 }, pet = { happiness = 1, foodTypes = { "Meat" } } },
    "Feed your pet (unhappy)", "nil")
ClickCase("turn off Growl autocast", { class = "HUNTER", spells = { 1515 }, pet = { happiness = 3 }, petActions = GROWL_ON, inGroup = true,
    instanceType = "party" }, "Turn off Growl autocast", "macro macrotext=/petautocastoff Growl")
ClickCase("turn off Torment autocast", { class = "WARLOCK", spells = { 697 }, pet = {}, inGroup = true, instanceType = "party",
    petActions = { { spellID = 11775, autocast = true } } }, "Turn off Torment autocast", "macro macrotext=/petautocastoff Torment")
ClickCase("poison for the off hand", { class = "ROGUE", spells = { 1856 }, skills = { [40] = 120 }, equipped = { [16] = 2131, [17] = 2131 },
    items = { [6947] = 5, [2892] = 5 }, bags = { { bag = 0, slot = 3, itemID = 6947, count = 5 }, { bag = 0, slot = 4, itemID = 2892, count = 5 } },
    enchants = { [0] = { { type = IMBUE, ms = 1800000 } } } }, "Apply poison to your off hand", "item item=0 4 target-slot=17")
ClickCase("poison for the main hand", { class = "ROGUE", spells = { 1856 }, skills = { [40] = 120 }, equipped = { [16] = 2131 },
    items = { [6947] = 5, [2892] = 5 }, bags = { { bag = 0, slot = 3, itemID = 6947, count = 5 }, { bag = 0, slot = 4, itemID = 2892, count = 5 } } },
    "Apply poison to your main hand", "item item=0 3 target-slot=16")
ClickCase("Windfury Weapon first", { class = "SHAMAN", spells = { 8017, 8232 }, equipped = { [16] = 2131 } }, "Imbue your weapon", "spell spell=Windfury Weapon")
ClickCase("Rockbiter before Windfury is learned", { class = "SHAMAN", spells = { 8017, 8024 }, equipped = { [16] = 2131 } }, "Imbue your weapon",
    "spell spell=Rockbiter Weapon")
ClickCase("the demon you summoned last", { class = "WARLOCK", spells = { 688, 697 } }, "Summon your demon", "spell spell=Summon Imp",
    function(env) env.__fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 688) end)
ClickCase("the Voidwalker until then", { class = "WARLOCK", spells = { 688, 697 } }, "Summon your demon", "spell spell=Summon Voidwalker")
ClickCase("a Firestone from your bags", { class = "WARLOCK", spells = { 17951 }, pet = {}, equipped = { [16] = 2131 },
    bags = { { bag = 0, slot = 2, itemID = 13699, count = 1 } } }, "Apply a Firestone or Spellstone", "item item=0 2 target-slot=16")
ClickCase("create a Firestone without one", { class = "WARLOCK", spells = { 17951 }, pet = {}, equipped = { [16] = 2131 } },
    "Apply a Firestone or Spellstone", "spell spell=Create Firestone")
ClickCase("the highest Healthstone you know", { class = "WARLOCK", spells = { 6201, 5699 }, pet = {}, items = { [6265] = 5 } },
    "Create a Healthstone", "spell spell=Create Healthstone")
ClickCase("the best Mana Gem", { class = "MAGE", spells = { 759, 3552 } }, "Conjure a Mana Gem", "spell spell=Conjure Mana Jade")
ClickCase("conjure water", { class = "MAGE", spells = { 5504, 5505 } }, "Conjure water (0 left)", "spell spell=Conjure Water")
ClickCase("Fortitude on you", { class = "PRIEST", spells = { 1243 } }, "Missing Power Word: Fortitude", "spell spell=Power Word: Fortitude unit=player")
ClickCase("Mark of the Wild on you", { class = "DRUID", spells = { 1126 } }, "Missing Mark of the Wild", "spell spell=Mark of the Wild unit=player")
ClickCase("Righteous Fury off", { class = "PALADIN", spells = { 25780 }, talents = { 31, 5, 0 }, inGroup = true, instanceType = "party", buffs = RF_UP },
    "Turn off Righteous Fury (not tanking)", "cancelaura spell=Righteous Fury unit=player")
ClickCase("eat buff food", { class = "WARRIOR", level = 30, bags = { { bag = 0, slot = 4, itemID = 2680, count = 2 } } }, FOOD_REMINDER, "item item=0 4")
ClickCase("supplies have nothing to click", { class = "WARRIOR", resting = true, freeBagSlots = 2 }, "Free up bag space (2 free)", "nil")

do
    -- Unspent talent points: the click opens the talent window
    local env = ClickCase("talents: no secure action", { class = "WARRIOR", unspentTalents = 3 }, "Spend 3 talent points", "nil")
    local tooltip = TooltipFor(env, "Spend 3 talent points")
    Check("click: talents tooltip", tooltip:find("Left-click: Open your talents", 1, true) ~= nil, tooltip)
    env.__click(ButtonFor(env, "Spend 3 talent points"), "LeftButton")
    Check("click: talents open the talent window", env.__talentWindowOpened == 1, env.__talentWindowOpened)
    local supplies = Setup({ class = "WARRIOR", resting = true, freeBagSlots = 2, time = NOW })
    supplies.Prepped:CheckReminders()
    Check("click: supplies tooltip has no left-click line", not TooltipFor(supplies, "Free up bag space (2 free)"):find("Left-click", 1, true))
    local poisonTip = Setup({ class = "ROGUE", spells = { 1856 }, skills = { [40] = 120 }, equipped = { [16] = 2131 }, time = NOW,
        items = { [2892] = 5 }, bags = { { bag = 0, slot = 4, itemID = 2892, count = 5 } } })
    poisonTip.Prepped:CheckReminders()
    Check("click: poison tooltip names the poison and the hand",
        TooltipFor(poisonTip, "Apply poison to your main hand"):find("Left-click: Apply Deadly Poison to your main hand", 1, true) ~= nil,
        TooltipFor(poisonTip, "Apply poison to your main hand"))
end

------------------------------------------------------------------------
-- Welcome line, help, AddOns menu
------------------------------------------------------------------------
do
    local env = Setup({ class = "WARRIOR" })
    local welcome
    for _, line in ipairs(env.__printed) do if line:find("loaded", 1, true) then welcome = line end end
    Check("welcome: one tidy line", welcome == "|cff00ff00Prepped|r |cffffcc00v" .. Mock.metadata.Version .. "|r loaded. Type |cffffff00/prepped|r for options.",
        tostring(welcome))
    local quiet = Setup({ class = "WARRIOR" }, nil)
    local count = #quiet.__printed
    local again = Relaunch(quiet, { class = "WARRIOR", time = NOW }, true)
    Check("welcome: shown after a /reload too", #again.__printed >= 1 and count >= 1)
    env.SlashCmdList.PREPPED("help")
    local help = table.concat(env.__printed, "\n")
    Check("help: lists the commands", help:find("/prepped move", 1, true) ~= nil and help:find("/prepped snooze [minutes]", 1, true) ~= nil
        and help:find("/prepped debug", 1, true) ~= nil, help)

    local S = { class = "PRIEST", spells = { 1243 }, buffs = {}, time = NOW }
    local menuEnv = Setup(S)
    menuEnv.Prepped:CheckReminders()
    menuEnv.Prepped_OnCompartmentEnter("Prepped", menuEnv.UIParent)
    Check("AddOns menu: tooltip counts the reminders", table.concat(menuEnv.__tooltipLines(), " / "):find("1 reminder on screen", 1, true) ~= nil,
        table.concat(menuEnv.__tooltipLines(), " / "))
    menuEnv.Prepped_OnCompartmentLeave()
    Check("AddOns menu: tooltip hidden again", #menuEnv.__tooltipLines() == 0)
end

------------------------------------------------------------------------
-- Translations: every text has one, with the same placeholders
------------------------------------------------------------------------
-- The English texts the addon looks up: every L["..."] in its code.
local function ReadFile(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local function EnglishTexts()
    local keys, count = {}, 0
    for _, file in ipairs(TOC_FILES) do
        if not file:match("^locale") then
            local source = ReadFile(ADDON_DIR .. "/" .. file)
            local from = 1
            while true do
                local _, open = source:find('%f[%w_]L%["', from)
                if not open then break end
                local i, parts = open + 1, {}
                while i <= #source do
                    local c = source:sub(i, i)
                    if c == "\\" then
                        parts[#parts + 1] = source:sub(i, i + 1)
                        i = i + 2
                    elseif c == '"' then
                        break
                    else
                        parts[#parts + 1] = c
                        i = i + 1
                    end
                end
                local value = loadstring("return \"" .. table.concat(parts) .. "\"")()
                if not keys[value] then count = count + 1 end
                keys[value] = file
                from = i + 1
            end
        end
    end
    return keys, count
end

-- Placeholders that must match: format specifiers in order, and {count}/{name}.
local function FormatSpecifiers(text)
    local list = {}
    for spec in text:gmatch("%%[%-%+#0]*%d*%.?%d*[sdifgxXc%%]") do list[#list + 1] = spec end
    return table.concat(list, " ")
end
local function Tokens(text)
    local set = {}
    for token in text:gmatch("{(%w+)}") do set[token] = true end
    return set
end

local ENGLISH, ENGLISH_COUNT = EnglishTexts()
Check("translations: the English texts were found", ENGLISH_COUNT > 200, ENGLISH_COUNT)

local LOCALES = { deDE = "locale_deDE.lua", frFR = "locale_frFR.lua", esES = "locale_esES.lua" }
for locale, file in pairs(LOCALES) do
    local translations
    local chunk = loadfile(ADDON_DIR .. "/" .. file)
    Check(locale .. ": file loads", chunk ~= nil, file)
    if chunk then
        local fakeNs = { textLocale = locale, AddTranslations = function(l, t) if l == locale then translations = t end end }
        setfenv(chunk, { GetLocale = function() return locale end, pairs = pairs })
        local ok, err = pcall(chunk, "Prepped", fakeNs)
        Check(locale .. ": translations register", ok and translations ~= nil, err)
    end
    translations = translations or {}
    local missing, stale, broken = {}, {}, {}
    for english in pairs(ENGLISH) do
        if translations[english] == nil then missing[#missing + 1] = english end
    end
    for english, translated in pairs(translations) do
        if not ENGLISH[english] then
            stale[#stale + 1] = english
        else
            local tokens, englishTokens = Tokens(translated), Tokens(english)
            local ok = FormatSpecifiers(translated) == FormatSpecifiers(english) and type(translated) == "string" and translated ~= ""
            for token in pairs(tokens) do
                if not englishTokens[token] and token ~= "name" then ok = false end -- {name}: the client's name may be used instead
            end
            if englishTokens.count and not tokens.count then ok = false end
            if not ok then broken[#broken + 1] = english .. " => " .. tostring(translated) end
        end
    end
    table.sort(missing)
    table.sort(stale)
    Check(locale .. ": every text translated", #missing == 0, #missing .. " missing: " .. table.concat(missing, " | "))
    Check(locale .. ": no translations of texts that are gone", #stale == 0, table.concat(stale, " | "))
    Check(locale .. ": placeholders kept", #broken == 0, table.concat(broken, " || "))
end

do
    -- A German client shows Prepped's texts in German, with the client's own names
    local env = Setup({ class = "MAGE", spells = { 1459 }, buffs = {}, locale = "deDE" })
    env.Prepped:CheckReminders()
    Check("deDE: reminder text in German", Has(VisibleReminders(env), "DE:Arcane Intellect fehlt"), Shown(env))
    Check("deDE: every text the run looked up is translated", next(env.__ns.missingTranslations) == nil,
        (function() local l = {} for k in pairs(env.__ns.missingTranslations) do l[#l + 1] = k end return table.concat(l, " | ") end)())
    local names = {}
    for _, c in ipairs(env.__categories) do names[#names + 1] = c.name end
    Check("deDE: option pages use the client's class names", table.concat(names, ","):find("DE:Mage", 1, true) ~= nil, table.concat(names, ","))
    local S = Hunter({ locale = "deDE" })
    local group = Setup(S)
    JoinGroup(group, S)
    group.__tick(3)
    Check("deDE: group message in German", Messages(group):find("[Prepped]", 1, true) ~= nil and not Messages(group):find("remember to", 1, true),
        Messages(group))
    for _, locale in ipairs({ "frFR", "esES" }) do
        local other = Setup({ class = "PRIEST", spells = { 1243 }, buffs = {}, locale = locale, resting = true, level = 30 })
        other.Prepped:CheckReminders()
        pcall(other.SlashCmdList.PREPPED, "help")
        Check(locale .. ": every text the run looked up is translated", next(other.__ns.missingTranslations) == nil,
            (function() local l = {} for k in pairs(other.__ns.missingTranslations) do l[#l + 1] = k end return table.concat(l, " | ") end)())
    end
    local mx = Setup({ class = "MAGE", spells = { 1459 }, buffs = {}, locale = "esMX" })
    Check("esMX: uses the Spanish texts", mx.__ns.textLocale == "esES" and next(mx.__ns.missingTranslations) == nil)
end

print(string.format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
