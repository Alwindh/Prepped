-- .luacheckrc
-- luacheck (run in CI) catches accidental globals and misspelled game API names
-- in the addon's code: everything Prepped writes or reads globally is listed
-- here, so anything else is a bug. Only the global-variable warnings (1xx) are
-- reported; style is left to review. Add new game API names to read_globals.

std = "lua51"
only = { "1" }
exclude_files = { "tests/" }

-- What Prepped defines, and Blizzard tables it adds entries to
globals = {
    "Prepped",
    "PreppedSettings",
    "SLASH_PREPPED1",
    "Prepped_OpenOptions",
    "Prepped_OnCompartmentEnter",
    "Prepped_OnCompartmentLeave",
    "SlashCmdList",
    "StaticPopupDialogs",
    "_G",
}

-- What Prepped reads from the game: WoW Forever API, Blizzard UI and constants
read_globals = {
    -- API namespaces
    "C_AddOns", "C_ChatInfo", "C_ClassTalents", "C_Container", "C_EventUtils", "C_Item", "C_PetInfo",
    "C_Secrets", "C_SkillInfo", "C_SpecializationInfo", "C_Spell", "C_SpellBook", "C_TooltipInfo",
    "C_Traits", "C_UnitAuras",
    -- Functions
    "CreateColor", "CreateColorFromHexString", "CreateFrame", "debugprofilestop", "geterrorhandler",
    "GetBuildInfo", "GetInventoryItemCount", "GetInventoryItemDurability", "GetInventoryItemID",
    "GetInventoryItemTexture", "GetLocale", "GetMaxLevelForPlayerExpansion", "GetMaxPlayerLevel",
    "GetNumGroupMembers", "GetPetActionInfo", "GetRealmName", "GetServerTime", "GetShapeshiftFormID",
    "GetTime", "InCombatLockdown", "IsInGroup", "IsInInstance", "IsInRaid", "IsMounted", "IsResting",
    "IsShiftKeyDown", "IsUsableSpell", "IsXPUserDisabled", "PlaySound", "StaticPopup_Show", "time",
    "ToggleTalentFrame", "UnitAffectingCombat", "UnitCharacterPoints", "UnitClass", "UnitExists",
    "UnitIsDead", "UnitIsDeadOrGhost", "UnitLevel", "UnitName", "UnitOnTaxi", "UnitPowerMax",
    "UnitPowerType", "canaccesstable", "issecretvalue",
    -- Settings UI
    "Settings", "CreateSettingsButtonInitializer", "CreateSettingsCheckboxSliderInitializer",
    "CreateSettingsListSectionHeaderInitializer", "MinimalSliderWithSteppersMixin",
    -- UI objects and helpers
    "EventRegistry", "GameFontNormalLarge", "GameTooltip", "MenuUtil", "PlayerSpellsUtil", "UIParent",
    -- Constants and global strings
    "CANCEL", "Constants", "Enum", "INVSLOT_AMMO", "INVSLOT_MAINHAND", "INVSLOT_OFFHAND", "INVSLOT_RANGED",
    "LE_PARTY_CATEGORY_INSTANCE", "LOCALIZED_CLASS_NAMES_MALE", "NO", "NUM_BAG_SLOTS", "NUM_PET_ACTION_SLOTS",
    "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "RESET", "SOUNDKIT", "UNKNOWNOBJECT", "YES",
}
