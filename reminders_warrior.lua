-- Warrior-specific reminders module
-- (Forever hides buffs from add-ons in combat, so there is no Battle Shout reminder.)

local WarriorReminders = { class = "WARRIOR" }

local warriorReminders = {
    { id = "warrior_no_ammo", message = "No ammo/thrown equipped" },
    { id = "warrior_ammo_critical", message = "Critically low on ammo/thrown (%s left)" },
    {
        id = "warrior_ammo_low",
        message = "Low on ammo/thrown (%s left)",
        mustRest = true,
        suppressedBy = { "warrior_no_ammo", "warrior_ammo_critical" },
    },
}

local function NoAmmo(config) return Prepped:CheckNoAmmo(config) end
local function AmmoBelow(config) return Prepped:CheckAmmoBelow(config) end

local checks = {
    warrior_no_ammo = NoAmmo,
    warrior_ammo_critical = AmmoBelow,
    warrior_ammo_low = AmmoBelow,
}

function WarriorReminders.CheckReminders()
    Prepped:RunReminders(warriorReminders, checks)
end

if Prepped then
    Prepped:RegisterReminderModule(WarriorReminders)
end
