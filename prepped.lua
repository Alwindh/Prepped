
-- Loader for modular reminders system

-- UI container for reminders (if needed by modules)
local container = CreateFrame("Frame", "PreppedContainer", UIParent)
container:SetSize(400, 200)
container:SetPoint("CENTER", 0, 200)

_G.PreppedContainer = container

----------------------------------------------------------------------
-- CORE ENGINE v4.0 (Multi-Line Support)
----------------------------------------------------------------------
local container = CreateFrame("Frame", "PreppedContainer", UIParent)
container:SetSize(400, 200)
container:SetPoint("CENTER", 0, 200)

-- ...existing code...