-- locale.lua
-- Prepped's own texts. Code looks a text up by its English wording,
-- L["Missing %s"], and gets the translation for the client's language, or the
-- English text when there is none. The locale_*.lua files hold the
-- translations, one client language each.
--
-- Spell and item names are never translated here: they come from the client
-- (C_Spell.GetSpellName, C_Item.GetItemNameByID), so they always match what the
-- player sees in the game. Translations keep the English text's placeholders
-- (%s, %d, {count}, {name}) in the same order; tests/run.lua checks that.

local _, ns = ...

-- Clients that use another language's texts.
local SHARED_LOCALES = { enGB = "enUS", esMX = "esES" }
local clientLocale = GetLocale()
local textLocale = SHARED_LOCALES[clientLocale] or clientLocale

-- English texts looked up without a translation, for translators and tests.
local missing = {}

local L = setmetatable({}, {
    __index = function(t, english)
        if textLocale ~= "enUS" then missing[english] = true end
        rawset(t, english, english) -- next lookups skip this function
        return english
    end,
})

ns.L = L
ns.textLocale = textLocale
ns.missingTranslations = missing

-- Called by each locale_*.lua file. Only the client's language is kept.
function ns.AddTranslations(locale, translations)
    if locale ~= textLocale then return end
    for english, translated in pairs(translations) do
        rawset(L, english, translated)
    end
end
