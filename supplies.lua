-- supplies.lua
-- When supply reminders (reagents, ammo, repairs, ...) show outside cities and
-- inns: for a minute after joining a group and during a ready check (vendors:
-- MERCHANT_SHOW in core.lua). And the one line Prepped posts in group chat
-- about what you're low on.

local _, ns = ...
local API, L = ns.API, ns.L
local Prepped = ns.Prepped

local GetTime = GetTime
local format = string.format

local GROUP_CHECK_SECONDS = 60
local GROUP_MESSAGE_DELAY = 2   -- let the group settle first
local GROUP_MESSAGE_MAX = 3     -- shortages named in one message
local CHAT_MESSAGE_LIMIT = 255
local READY_CHECK_SECONDS = 35  -- if the client doesn't say

-- Text for gsub's replacement argument, where "%" is special.
local function AsReplacement(value)
    return (tostring(value):gsub("%%", "%%%%"))
end

-- Fills {count} and {name} in a group message template.
local function FillTemplate(template, value)
    local count, name = value, nil
    if type(value) == "table" then count, name = value.count, value.name end
    local text = template:gsub("{count}", AsReplacement(count or "?"))
    text = text:gsub("{name}", AsReplacement(name or ""))
    return text
end

-- Cuts a message to the chat limit without splitting a UTF-8 character.
local function Truncate(message, limit)
    if #message <= limit then return message end
    local cut = limit - 3
    while cut > 0 do
        local byte = message:byte(cut + 1)
        if byte < 0x80 or byte >= 0xC0 then break end -- not a continuation byte
        cut = cut - 1
    end
    return message:sub(1, cut) .. "..."
end

-- Every supply reminder that would show right now (ignoring the resting rule), as
-- { id, value }. A dry run: the bars on screen don't change.
function Prepped:CollectSupplyShortages()
    local found = {}
    self.collecting, self.forceSupplies = found, true
    local ok, err = pcall(self.EvaluateReminders, self)
    self.collecting, self.forceSupplies = nil, nil
    if not ok then geterrorhandler()(err) end
    return found
end

-- "[Prepped] you're at 47% durability and low on ammo (150 left), remember to repair soon and buy more ammo."
-- Uses each supply rule's `announce = { state, action }`; nil when there's nothing to say.
function Prepped:BuildGroupMessage()
    local states, actions, seenAction = {}, {}, {}
    local repairBelow = self:GetRuleThreshold("general_group_announce")
    for _, entry in ipairs(self:CollectSupplyShortages()) do
        local rule = self:GetRule(entry.id)
        local announce = rule and rule.announce
        local tooMinor = entry.id == "general_repair" and (tonumber(entry.value) or 0) >= repairBelow
        if announce and not tooMinor and #states < GROUP_MESSAGE_MAX then
            states[#states + 1] = FillTemplate(announce[1], entry.value)
            local action = FillTemplate(announce[2], entry.value)
            if not seenAction[action] then
                seenAction[action] = true
                actions[#actions + 1] = action
            end
        end
    end
    if #states == 0 then return nil end
    return Truncate(format(L["[Prepped] you're %s, remember to %s."], ns.JoinList(states), ns.JoinList(actions)), CHAT_MESSAGE_LIMIT)
end

function Prepped:OnGroupJoined()
    if self.groupMessageSent then return end -- once per group
    local now = GetTime()
    if self:IsRuleEnabled("general_group_check") then
        self.supplyCheckUntil = now + GROUP_CHECK_SECONDS
    end
    if self:IsRuleEnabled("general_group_announce") then
        self.groupMessageAt = now + GROUP_MESSAGE_DELAY
        self.groupMessageUntil = now + GROUP_CHECK_SECONDS
    end
end

function Prepped:OnGroupLeft()
    self.groupMessageSent, self.groupMessageAt, self.supplyCheckUntil = nil, nil, nil
end

-- Ready check: supplies on screen until it ends.
function Prepped:OnReadyCheck(timeLeft)
    if not self:IsRuleEnabled("general_ready_check") then return end
    if API.IsSecret(timeLeft) then timeLeft = nil end
    self.readyCheckUntil = GetTime() + (tonumber(timeLeft) or READY_CHECK_SECONDS)
end

function Prepped:OnReadyCheckFinished()
    self.readyCheckUntil = nil
end

-- Called while a group message is due. Waits while you're in combat, dead, on a
-- taxi or while Forever blocks add-on chat; gives up after a minute. In a raid
-- only with "Also Post in Raids": a raid doesn't need a line from everyone.
function Prepped:TrySendGroupMessage()
    local now = GetTime()
    if now < self.groupMessageAt then return end
    if now > self.groupMessageUntil or not API.GroupChatType() then
        self.groupMessageAt = nil
        return
    end
    if UnitAffectingCombat("player") or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") or API.InChatLockdown() then
        self.groupMessageAt = now + 1
        return
    end
    self.groupMessageAt = nil
    self.groupMessageSent = true
    if API.IsInRaidGroup() and not self:IsRuleEnabled("general_group_announce_raids") then return end
    local message = self:BuildGroupMessage()
    if message then
        API.SendGroupMessage(message)
    end
end
