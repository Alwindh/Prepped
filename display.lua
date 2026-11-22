-- display.lua
-- The reminder bars: where they are (movable, saved per account), how they
-- look (appearance settings, icons, growing up or down), a preview, and
-- clicking them.
--
-- Clicking: left-click does the reminder's action (cast the missing buff, apply
-- a poison, ...) through a secure action button, right-click opens a menu to
-- snooze or turn off the reminder. Secure buttons can't be shown, hidden, moved
-- or changed during combat, so they are separate frames, anchored to UIParent
-- (never to the bars: a frame a secure button is anchored to becomes protected
-- too). Out of combat they cover the bars' icon and text; when combat starts
-- they are put away, and the bars themselves, plain frames, keep updating.

local _, ns = ...
local API, L = ns.API, ns.L
local Prepped = ns.Prepped

local Display = {}
ns.Display = Display
Prepped.Display = Display

local GetTime = GetTime
local format, floor, max = string.format, math.floor, math.max

-- The first bar's outer edge (top when growing down), from the screen's centre.
-- Matches where the bars were before they could be moved.
local DEFAULT_POSITION = { x = 0, y = 300 }
local BAR_GAP = 2
local ICON_GAP = 6
local CLICK_PADDING = 6     -- clickable margin around the icon and text
local PREVIEW_SECONDS = 8   -- sample reminders after an appearance change
local REPAIR_ICON = "Interface\\Icons\\Trade_BlackSmithing"

local function Round(value)
    return floor(value + 0.5)
end

-- Hides the game tooltip only if Prepped showed it (owner: the frame it belongs to,
-- or nil for any of Prepped's click buttons).
local function HideOwnTooltip(owner)
    local current = GameTooltip:GetOwner()
    if current and (current == owner or (owner == nil and current.isPreppedButton)) then GameTooltip:Hide() end
end

------------------------------------------------------------------------
-- Frames
------------------------------------------------------------------------
local container = CreateFrame("Frame", "PreppedContainer", UIParent)
container:SetSize(400, 30)
container:SetMovable(true)
container:SetClampedToScreen(true)
-- Prepped saves the position itself; keep it out of the client's layout cache.
if container.SetDontSavePosition then container:SetDontSavePosition(true) end

local bars = {}        -- the reminders, top (or bottom) first
local previewBars = {} -- sample reminders while previewing
local overlays = {}    -- secure click buttons, one per bar
Display.bars = bars
Display.previewBars = previewBars
Display.overlays = overlays
Prepped.displayLines = bars
Prepped.activeCount = 0

local layoutVersion = 0 -- bumped by appearance changes: every bar is laid out again

local function NewBar()
    local bar = CreateFrame("Frame", nil, container)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.hover = bar:CreateTexture(nil, "BORDER")
    bar.hover:SetAllPoints()
    bar.hover:SetColorTexture(1, 1, 1, 0.12)
    bar.hover:Hide()
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon border
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    bar:Hide()
    return bar
end

local function GetBar(pool, index)
    local bar = pool[index]
    if not bar then
        bar = NewBar()
        pool[index] = bar
    end
    return bar
end

------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------
function Display:GrowsUp()
    return Prepped:GetDisplayOption("growUp") == true
end

local function BarHeight(app) return app.fontSize + 12 end
local function IconSize(app) return app.fontSize + 6 end

-- Puts text and icon on the bar, sizes it and places it in the stack.
local function LayoutBar(bar, index, text, icon, app, showIcons)
    if bar.shownText ~= text or bar.shownIcon ~= icon or bar.layoutVersion ~= layoutVersion then
        if bar.layoutVersion ~= layoutVersion then
            local bg, fc = app.bgColor, app.fontColor
            bar.bg:SetColorTexture(bg.r, bg.g, bg.b, bg.a or 0.5)
            bar.text:SetFont((GameFontNormalLarge:GetFont()), app.fontSize, "OUTLINE")
            bar.text:SetTextColor(fc.r or 1, fc.g or 0.82, fc.b or 0, 1)
        end
        bar.text:SetText(text)
        local withIcon = showIcons and icon and true or false
        local iconSize = IconSize(app)
        local iconWidth = withIcon and (iconSize + ICON_GAP) or 0
        local contentWidth = bar.text:GetUnboundedStringWidth() + iconWidth
        bar:SetSize(max(app.minWidth or 400, contentWidth + 40), BarHeight(app))
        -- icon and text are centred as one group
        bar.text:ClearAllPoints()
        bar.text:SetPoint("CENTER", bar, "CENTER", iconWidth / 2, 0)
        if withIcon then
            bar.icon:SetTexture(icon)
            bar.icon:SetSize(iconSize, iconSize)
            bar.icon:ClearAllPoints()
            bar.icon:SetPoint("RIGHT", bar.text, "LEFT", -ICON_GAP, 0)
            bar.icon:Show()
        else
            bar.icon:Hide()
        end
        bar.contentWidth = contentWidth + 2 * CLICK_PADDING
        bar.shownText, bar.shownIcon, bar.layoutVersion = text, icon, layoutVersion
        bar.index = nil -- placed again below
    end
    if bar.index ~= index or bar.growsUp ~= Display:GrowsUp() then
        local offset = (index - 1) * (BarHeight(app) + BAR_GAP)
        bar:ClearAllPoints()
        if Display:GrowsUp() then
            bar:SetPoint("BOTTOM", container, "BOTTOM", 0, offset)
        else
            bar:SetPoint("TOP", container, "TOP", 0, -offset)
        end
        bar.index, bar.growsUp = index, Display:GrowsUp()
    end
    return bar:GetWidth()
end

local function SetShown(bar, shown)
    if shown then
        if not bar:IsShown() then bar:Show() end
    elseif bar:IsShown() then
        bar:Hide()
    end
end

local function HideBars(pool, from)
    for i = from, #pool do
        local bar = pool[i]
        bar.ruleId = nil
        if bar:IsShown() then bar:Hide() end
    end
end

------------------------------------------------------------------------
-- Position
------------------------------------------------------------------------
local function CurrentPosition()
    return Prepped:GetAppearance().position or DEFAULT_POSITION
end

function Display:ApplyPosition()
    local position = CurrentPosition()
    container:ClearAllPoints()
    container:SetPoint(self:GrowsUp() and "BOTTOM" or "TOP", UIParent, "CENTER", position.x, position.y)
end

local function SetPosition(x, y)
    Prepped:GetAppearance().position = { x = Round(x), y = Round(y) }
    Display:ApplyPosition()
end

-- After dragging: where the bars' outer edge ended up, from the screen's centre.
local function SaveDraggedPosition()
    local x = container:GetCenter()
    local edge = Display:GrowsUp() and container:GetBottom() or container:GetTop()
    local centerX, centerY = UIParent:GetCenter()
    if not (x and edge and centerX) then return Display:ApplyPosition() end
    local scale = container:GetEffectiveScale() / UIParent:GetEffectiveScale()
    SetPosition(x * scale - centerX, edge * scale - centerY)
end

function Display:ResetPosition()
    Prepped:GetAppearance().position = nil
    self:ApplyPosition()
    self:Refresh()
end

------------------------------------------------------------------------
-- Moving (unlocked): a handle over the bars, with sample reminders
------------------------------------------------------------------------
local mover = CreateFrame("Frame", nil, container)
mover:SetPoint("TOPLEFT", container, "TOPLEFT", -6, 6)
mover:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 6, -6)
mover:SetFrameLevel(container:GetFrameLevel() + 20)
mover:EnableMouse(true)
mover:RegisterForDrag("LeftButton")
mover.bg = mover:CreateTexture(nil, "BACKGROUND")
mover.bg:SetAllPoints()
mover.bg:SetColorTexture(0.1, 0.45, 0.9, 0.3)
mover.label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
mover.label:SetPoint("BOTTOM", mover, "TOP", 0, 4)
mover:Hide()
Display.mover = mover

local NUDGE = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }

mover:SetScript("OnDragStart", function()
    if not InCombatLockdown() then container:StartMoving() end
end)
mover:SetScript("OnDragStop", function()
    container:StopMovingOrSizing()
    SaveDraggedPosition()
end)
mover:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then Display:SetUnlocked(false) end
end)
mover:SetScript("OnEnter", function(self)
    if not InCombatLockdown() then self:EnableKeyboard(true) end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["Prepped reminders"], 1, 1, 1)
    GameTooltip:AddLine(L["Drag to move them."], 1, 0.82, 0)
    GameTooltip:AddLine(L["Arrow keys move them by 1 pixel, with Shift by 10."], 1, 0.82, 0)
    GameTooltip:AddLine(L["Right-click or press Escape when you're done."], 1, 0.82, 0)
    GameTooltip:Show()
end)
mover:SetScript("OnLeave", function(self)
    if not InCombatLockdown() then self:EnableKeyboard(false) end
    HideOwnTooltip(self)
end)
mover:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown() then return end
    local step = NUDGE[key]
    if step then
        self:SetPropagateKeyboardInput(false)
        local amount = IsShiftKeyDown() and 10 or 1
        local position = CurrentPosition()
        SetPosition(position.x + step[1] * amount, position.y + step[2] * amount)
    elseif key == "ESCAPE" then
        self:SetPropagateKeyboardInput(false)
        Display:SetUnlocked(false)
    else
        self:SetPropagateKeyboardInput(true) -- every other key still works
    end
end)

function Display:IsUnlocked()
    return self.unlocked == true
end

-- Unlocked: the bars show samples and can be dragged. Not in combat. Returns
-- whether the bars are unlocked afterwards.
function Display:SetUnlocked(unlocked)
    unlocked = unlocked == true and not InCombatLockdown()
    if self:IsUnlocked() == unlocked then return unlocked end
    self.unlocked = unlocked
    if unlocked then
        mover.label:SetText(L["Prepped: drag to move, right-click to lock"])
        mover:Show()
    else
        mover:EnableKeyboard(false)
        HideOwnTooltip(mover)
        mover:Hide()
    end
    self:Refresh()
    return unlocked
end

------------------------------------------------------------------------
-- Preview
------------------------------------------------------------------------
local function IsPreviewing()
    return Display.unlocked or (Display.previewUntil ~= nil and GetTime() < Display.previewUntil)
end
Display.IsPreviewing = IsPreviewing

-- Sample reminders for a moment (after an appearance change).
function Display:ShowPreview(seconds)
    self.previewUntil = GetTime() + (seconds or PREVIEW_SECONDS)
    self:Refresh()
end

-- Realistic samples, so width and font changes look as they will.
local function PreviewSamples()
    return {
        { format(L["Missing %s"], C_Spell.GetSpellName(1459) or "Arcane Intellect"), API.GetSpellIcon(1459) },
        { format(L["Buy %s (%d left)"], L["water"], 7), API.GetItemIcon(159) },
        { format(L["Repair your gear (%d%%)"], 65), REPAIR_ICON },
    }
end

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------
local last = { count = 0 } -- the last reminders drawn, for Refresh

-- Draws the reminders (texts, rule IDs, icons; arrays reused by the core),
-- touching only bars whose content changed. While previewing, samples show
-- instead; the reminders themselves stay due.
function Display:Render(count, texts, ids, icons)
    last.count, last.texts, last.ids, last.icons = count, texts, ids, icons
    local app = Prepped:GetAppearance()
    local showIcons = Prepped:GetDisplayOption("showIcons")
    local previewing = IsPreviewing()
    local widest, shown = 0, 0

    for i = 1, count do
        local bar = GetBar(bars, i)
        bar.ruleId = ids[i]
        local width = LayoutBar(bar, i, texts[i], icons[i] or nil, app, showIcons)
        SetShown(bar, not previewing)
        if not previewing then widest, shown = max(widest, width), i end
    end
    HideBars(bars, count + 1)
    Prepped.activeCount = count

    if previewing then
        for i, sample in ipairs(PreviewSamples()) do
            local bar = GetBar(previewBars, i)
            widest, shown = max(widest, LayoutBar(bar, i, sample[1], sample[2], app, showIcons)), i
            SetShown(bar, true)
        end
    else
        HideBars(previewBars, 1)
    end

    -- The container fits the bars (the mover covers it, and it stays on screen).
    local height = max(1, shown) * (BarHeight(app) + BAR_GAP) - BAR_GAP
    container:SetSize(max(widest, app.minWidth or 400), height)
    -- While previewing or moving, show above the options window.
    local strata = previewing and "FULLSCREEN_DIALOG" or "MEDIUM"
    if container.strata ~= strata then
        container:SetFrameStrata(strata)
        container.strata = strata
    end

    self:SyncOverlays()
end

-- Draws the last reminders again (after a setting changed how they look).
function Display:Refresh()
    if last.texts then
        self:Render(last.count, last.texts, last.ids, last.icons)
    else
        self:Render(0, {}, {}, {})
    end
end

function Display:ApplyAppearance(withPreview)
    layoutVersion = layoutVersion + 1
    for _, bar in ipairs(bars) do bar.index = nil end
    for _, bar in ipairs(previewBars) do bar.index = nil end
    self:ApplyPosition()
    if withPreview then
        self:ShowPreview()
    else
        self:Refresh()
    end
end

-- Called once the saved settings are loaded.
function Display:Initialize()
    self:ApplyPosition()
    if EventRegistry and EventRegistry.RegisterCallback and not self.editModeHooked then
        -- Blizzard's Edit Mode: move the reminders along with the rest of the UI.
        self.editModeHooked = true
        EventRegistry:RegisterCallback("EditMode.Enter", function() Display:SetUnlocked(true) end, Display)
        EventRegistry:RegisterCallback("EditMode.Exit", function() Display:SetUnlocked(false) end, Display)
    end
end

------------------------------------------------------------------------
-- Clicking: secure buttons over the bars, out of combat
------------------------------------------------------------------------
local ACTION_ATTRIBUTES = {
    { "type1", "type" }, { "spell", "spell" }, { "unit", "unit" }, { "item", "item" },
    { "target-slot", "targetSlot" }, { "macrotext", "macrotext" },
}

local function ShowTooltip(overlay)
    local bar = bars[overlay.index]
    if bar then bar.hover:Show() end
    local rule = overlay.ruleId and Prepped:GetRule(overlay.ruleId)
    GameTooltip:SetOwner(overlay, "ANCHOR_BOTTOM")
    GameTooltip:SetText(bar and bar.shownText or "", 1, 1, 1)
    if rule and rule.description then GameTooltip:AddLine(rule.description, 1, 0.82, 0, true) end
    local action = overlay.action
    if action and action.label then
        GameTooltip:AddLine(format(L["Left-click: %s"], action.label), 0.25, 1, 0.25)
    end
    GameTooltip:AddLine(L["Right-click: snooze or turn off"], 0.65, 0.65, 0.65)
    GameTooltip:Show()
end

local function HideTooltip(overlay)
    local bar = bars[overlay.index]
    if bar then bar.hover:Hide() end
    HideOwnTooltip(overlay)
end

-- The right-click menu: snooze this reminder, turn it off, or open its settings.
function Display:OpenMenu(owner)
    local ruleId = owner.ruleId
    local rule = ruleId and Prepped:GetRule(ruleId)
    if not rule then return end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        -- No menu system on this client: right-click snoozes.
        Prepped:SnoozeRule(ruleId, 15 * 60)
        Prepped:Print(format(L["%s snoozed for %d minutes."], rule.label, 15))
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(rule.label)
        root:CreateButton(L["Snooze for 15 minutes"], function() Prepped:SnoozeRule(ruleId, 15 * 60) end)
        root:CreateButton(L["Snooze for 1 hour"], function() Prepped:SnoozeRule(ruleId, 60 * 60) end)
        root:CreateButton(L["Snooze until next login"], function() Prepped:SnoozeRule(ruleId, "login") end)
        root:CreateDivider()
        root:CreateButton(L["Turn off this reminder"], function() Prepped:TurnOffRule(ruleId) end)
        root:CreateButton(L["Open settings"], function() Prepped:OpenOptions(rule.group) end)
    end)
end

local function OnPostClick(overlay, button)
    if button == "RightButton" then
        Display:OpenMenu(overlay)
    elseif button == "LeftButton" and overlay.action and overlay.action.func then
        overlay.action.func() -- a plain action (opening a game window)
    end
end

local function GetOverlay(index)
    local overlay = overlays[index]
    if overlay then return overlay end
    -- Named, so a key can be bound to the first reminder: /click PreppedReminderButton1
    overlay = CreateFrame("Button", "PreppedReminderButton" .. index, UIParent, "SecureActionButtonTemplate")
    overlay.index, overlay.isPreppedButton = index, true
    overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    overlay:SetFrameStrata("MEDIUM")
    overlay:SetFrameLevel(container:GetFrameLevel() + 10)
    overlay:SetScript("OnEnter", ShowTooltip)
    overlay:SetScript("OnLeave", HideTooltip)
    overlay:SetScript("PostClick", OnPostClick)
    overlay:Hide()
    overlays[index] = overlay
    return overlay
end

-- Covers the bar's icon and text (not its whole background, so clicks next to
-- the text still reach the world behind it).
local function PlaceOverlay(overlay, bar)
    local x, y = bar:GetCenter()
    if not x then return false end
    local scale = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
    x, y = Round(x * scale), Round(y * scale)
    local width, height = Round((bar.contentWidth or bar:GetWidth()) * scale), Round(bar:GetHeight() * scale)
    if overlay.placedX ~= x or overlay.placedY ~= y or overlay.placedWidth ~= width or overlay.placedHeight ~= height then
        overlay:ClearAllPoints()
        overlay:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        overlay:SetSize(width, height)
        overlay.placedX, overlay.placedY, overlay.placedWidth, overlay.placedHeight = x, y, width, height
    end
    return true
end

local function ResolveAction(ruleId)
    local rule = ruleId and Prepped:GetRule(ruleId)
    if not (rule and rule.action) then return nil end
    local ok, action = pcall(rule.action, rule)
    return ok and action or nil
end

local function ApplyAction(overlay, action)
    for _, pair in ipairs(ACTION_ATTRIBUTES) do
        local value = action and action[pair[2]] or nil
        if overlay:GetAttribute(pair[1]) ~= value then overlay:SetAttribute(pair[1], value) end
    end
    overlay.action = action
end

-- Lines the click buttons up with the bars. Out of combat only: during
-- PLAYER_REGEN_DISABLED the lockdown hasn't started yet, but the buttons must
-- stay away. With "Clickable Reminders" off, while moving or previewing, there
-- are none.
function Display:SyncOverlays()
    if InCombatLockdown() or UnitAffectingCombat("player") then return end
    local active = 0
    if Prepped:GetDisplayOption("clickable") and not IsPreviewing() then active = Prepped.activeCount end
    local used = 0
    for i = 1, active do
        local bar = bars[i]
        if bar and bar:IsShown() then
            local overlay = GetOverlay(i)
            if PlaceOverlay(overlay, bar) then
                overlay.ruleId = bar.ruleId
                ApplyAction(overlay, ResolveAction(bar.ruleId))
                if not overlay:IsShown() then overlay:Show() end
                used = i
            end
        end
    end
    for i = used + 1, #overlays do
        local overlay = overlays[i]
        if overlay:IsShown() then overlay:Hide() end
        overlay.ruleId, overlay.action = nil, nil
    end
end

-- PLAYER_REGEN_DISABLED, just before the combat lockdown: put the click buttons
-- away and stop moving.
function Display:OnCombatStart()
    if InCombatLockdown() then return end
    for _, overlay in ipairs(overlays) do
        if overlay:IsShown() then overlay:Hide() end
    end
    HideOwnTooltip(nil)
    for _, bar in ipairs(bars) do bar.hover:Hide() end
    self:SetUnlocked(false)
end

-- UI scale or resolution changed: positions are worked out again.
function Display:OnScreenChanged()
    for _, overlay in ipairs(overlays) do overlay.placedX = nil end
    self:ApplyPosition()
    self:Refresh()
end
