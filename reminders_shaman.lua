-- Shaman-specific reminders module
local _, ns = ...
local API = ns.API

local ShamanReminders = { class = "SHAMAN" }

-- Water Shield is new in Forever and its spell ID isn't known yet, so it is
-- recognised by its English name (English clients only) until it's listed here.
local SHIELDS = API.SpellFamily("Shields", {
    324, 325, 905, 945, 8134, 10431, 10432, -- Lightning Shield
}, { class = "SHAMAN", aura = true, englishNames = { "Water Shield" } })
local REINCARNATION = API.SpellFamily("Reincarnation", { 20608 }, { class = "SHAMAN" })
local WATER_WALKING = API.SpellFamily("Water Walking", { 546 }, { class = "SHAMAN" })
local WATER_BREATHING = API.SpellFamily("Water Breathing", { 131 }, { class = "SHAMAN" })

local IsShield = API.Matcher(SHIELDS)

-- Totems still need their element's totem item in your bags in Forever
-- (quest rewards at level 4, 10, 20 and 30). An element counts once you know
-- any of its totems. Forever has no Fire Nova Totem or Tranquil Air Totem.
local TOTEM_ELEMENTS = {
    { name = "Earth Totem", item = 5175, family = API.SpellFamily("Earth totems", {
        8071, 8154, 8155, 10406, 10407, 10408, -- Stoneskin Totem
        2484,                                  -- Earthbind Totem
        5730, 6390, 6391, 6392, 10427, 10428,  -- Stoneclaw Totem
        8075, 8160, 8161, 10442, 25361,        -- Strength of Earth Totem
        8143,                                  -- Tremor Totem
    }, { class = "SHAMAN" }) },
    { name = "Fire Totem", item = 5176, family = API.SpellFamily("Fire totems", {
        3599, 6363, 6364, 6365, 10437, 10438,  -- Searing Totem
        8181, 10478, 10479,                    -- Frost Resistance Totem
        8190, 10585, 10586, 10587,             -- Magma Totem
        8227, 8249, 10526, 16387,              -- Flametongue Totem
    }, { class = "SHAMAN" }) },
    { name = "Water Totem", item = 5177, family = API.SpellFamily("Water totems", {
        5394, 6375, 6377, 10462, 10463,        -- Healing Stream Totem
        5675, 10495, 10496, 10497,             -- Mana Spring Totem
        8166,                                  -- Poison Cleansing Totem
        8170,                                  -- Disease Cleansing Totem
        8184, 10537, 10538,                    -- Fire Resistance Totem
        16190, 17354, 17359,                   -- Mana Tide Totem
    }, { class = "SHAMAN" }) },
    { name = "Air Totem", item = 5178, family = API.SpellFamily("Air totems", {
        8177,                                  -- Grounding Totem
        10595, 10600, 10601,                   -- Nature Resistance Totem
        8512, 10613, 10614,                    -- Windfury Totem
        8835, 10627, 25359,                    -- Grace of Air Totem
        15107, 15111, 15112,                   -- Windwall Totem
        6495,                                  -- Sentry Totem
    }, { class = "SHAMAN" }) },
}

-- "Fire Totem", "Fire Totem and Air Totem", "Earth Totem, Fire Totem and Air Totem"
local function JoinNames(names)
    if #names <= 1 then return names[1] or "" end
    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- Talent tree order
local TREE_ELEMENTAL = 1
local TREE_RESTORATION = 3

local function IsEnhancementOrLeveling()
    -- Suppress only when Elemental or Restoration strictly leads.
    -- Enhancement leading, no talents yet, a tie, or no talent data -> show reminder.
    local primaryTree = API.GetPrimaryTalentTree()
    return primaryTree ~= TREE_ELEMENTAL and primaryTree ~= TREE_RESTORATION
end

local shamanReminders = {
    { id = "shaman_totems", outOfCombat = true },
    {
        id = "shaman_shield_buff",
        message = "Buff missing: Shield",
        messageLow = "Shield expiring (%ss left)",
        mustNotRest = true,
        noTravel = true,
    },
    {
        id = "shaman_weapon_buff",
        message = "Buff missing: Weapon",
        messageLow = "Weapon imbue expiring (%ss left)",
        mustNotRest = true,
        noTravel = true,
    },
    { id = "shaman_ankh", message = "Low on reagents: Ankh (%s left)", item = 17030, family = REINCARNATION, mustRest = true },
    { id = "shaman_fish_oil", message = "Low on reagents: Fish Oil (%s left)", item = 17058, family = WATER_WALKING, mustRest = true },
    { id = "shaman_fish_scales", message = "Low on reagents: Fish Scales (%s left)", item = 17057, family = WATER_BREATHING, mustRest = true },
}

local function CheckReagent(config) return Prepped:CheckReagent(config) end

local checks = {
    shaman_ankh = CheckReagent,
    shaman_fish_oil = CheckReagent,
    shaman_fish_scales = CheckReagent,
}

-- The totem items you need (you know a totem of that element) but don't carry,
-- e.g. after leaving one in the bank.
function checks.shaman_totems()
    local missing
    for _, element in ipairs(TOTEM_ELEMENTS) do
        if API.KnowsFamily(element.family) and C_Item.GetItemCount(element.item) == 0 then
            missing = missing or {}
            missing[#missing + 1] = element.name
        end
    end
    if not missing then return nil end
    local text = (#missing == 1 and "Missing item: " or "Missing items: ") .. table.concat(missing, ", ")
    return text, { name = JoinNames(missing), count = #missing }
end

function checks.shaman_shield_buff(config)
    if not API.KnowsFamily(SHIELDS) then return nil end
    return Prepped:CheckTimedBuff(config.id, IsShield, config.message, config.messageLow)
end

-- Enhancement (or still leveling) only; both weapons when dual wielding. Only
-- imbues count, not sharpening stones or oils (Forever lets them stack).
function checks.shaman_weapon_buff(config)
    if not IsEnhancementOrLeveling() then return nil end
    return Prepped:CheckWeaponImbue(config, true)
end

function ShamanReminders.CheckReminders()
    Prepped:RunReminders(shamanReminders, checks)
end

if Prepped then
    Prepped:RegisterReminderModule(ShamanReminders)
end
