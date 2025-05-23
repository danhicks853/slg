local addonName, SLG = ...

-- Create the module
local Attunement = {}
SLG:RegisterModule("Attunement", Attunement)

-- Cache for attunement status
local attunementCache = {}
local isUpdating = false

-- Shared timer frame
local sharedTimerFrame = CreateFrame("Frame")
sharedTimerFrame.timers = {}

function Attunement:ScheduleTimer(delay, callback)
    sharedTimerFrame.timers[#sharedTimerFrame.timers + 1] = {
        time = GetTime() + delay,
        callback = callback
    }
    sharedTimerFrame:Show()
end

sharedTimerFrame:SetScript("OnUpdate", function(self, elapsed)
    local currentTime = GetTime()
    for i = #self.timers, 1, -1 do
        local timer = self.timers[i]
        if currentTime >= timer.time then
            table.remove(self.timers, i)
            timer.callback()
        end
    end
    if #self.timers == 0 then
        self:Hide()
    end
end)

-- Initialize the module
function Attunement:Initialize()
    -- Always use the global SynastriaCoreLib object
    local SCL = _G['SynastriaCoreLib']
    if SCL then
        for k, v in pairs(SCL) do
        end
    end
    if not SCL then
        local waitFrame = CreateFrame("Frame")
        waitFrame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed
            if self.elapsed >= 1 then
                self:SetScript("OnUpdate", nil)
                Attunement:Initialize()
            end
        end)
        return
    end
    self.SCL = SCL
    
    -- Wait for SCL to be enabled
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function(_, event, addOnName)
        if addOnName == "SynastriaCoreLib" or addOnName == "SynastriaCoreLib-1.0" then
            frame:UnregisterEvent("ADDON_LOADED")
            -- Wait a short time for SCL to fully initialize
            Attunement:ScheduleTimer(1, function()
                if not Attunement.SCL.GetAttuneProgress then
                    Attunement:Initialize()
                else
                    Attunement:InitializeCallbacks()
                end
            end)
        end
    end)
    
    -- Register for loot events
    self:RegisterEvents()
end

-- Queue an update to prevent recursion
function Attunement:QueueUpdate()
    if isUpdating then return end
    isUpdating = true
    Attunement:ScheduleTimer(0.1, function()
        isUpdating = false
        if SLG.modules.ItemList then
            SLG.modules.ItemList:UpdateDisplay()
        end
    end)
end

-- Initialize callbacks once SCL is ready
function Attunement:InitializeCallbacks()
    if not self.SCL or not self.SCL.GetAttuneProgress then
        local waitFrame = CreateFrame("Frame")
        waitFrame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed
            if self.elapsed >= 1 then
                self:SetScript("OnUpdate", nil)
                Attunement:InitializeCallbacks()
            end
        end)
        return
    end
    
    -- Enable SCL if not already enabled
    if not self.SCL.enabled then
        self.SCL.OnEnable()
    end
    
    -- Register callbacks
    self.SCL.callbacks:RegisterCallback("ItemAttuned", function(_, itemId)
        attunementCache[itemId] = true
        self:QueueUpdate()
    end)
    
    self.SCL.callbacks:RegisterCallback("ItemUnattuned", function(_, itemId)
        attunementCache[itemId] = false
        self:QueueUpdate()
    end)
    
    self.SCL.callbacks:RegisterCallback("ItemAttuneProgress", function(_, itemId, progress)
        attunementCache[itemId] = progress == 100
        self:QueueUpdate()
    end)
    
    -- Register for custom game data to track attunement changes
    self.SCL.callbacks:RegisterCallback("CustomGameData", function(_, typeId, id, prev, cur)
        if typeId == self.SCL.CustomDataTypes.ATTUNE_HAS then
            attunementCache[id] = cur == 100
            self:QueueUpdate()
        end
    end)

    -- Initial cache population
    for itemId, _ in pairs(SLG.ZoneItems) do
        if type(itemId) == "number" then
            local progress = self.SCL.GetAttuneProgress(itemId)
            attunementCache[itemId] = progress and progress >= 100
        end
    end
end

-- Register loot-related events
function Attunement:RegisterEvents()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("LOOT_READY")
    frame:RegisterEvent("CHAT_MSG_LOOT")
    frame:RegisterEvent("BAG_UPDATE")
    
    frame:SetScript("OnEvent", function(_, event, ...)
        self:QueueUpdate()
    end)
    
    self.frame = frame
end

-- Check if an item is attuned
function Attunement:IsAttuned(itemId)
    local scl = self.SCL or _G['SynastriaCoreLib']
    if not scl or not scl.IsAttuned then
        local waitFrame = CreateFrame("Frame")
        waitFrame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed
            if self.elapsed >= 1 then
                self:SetScript("OnUpdate", nil)
                return Attunement:IsAttuned(itemId)
            end
        end)
        return false
    end
    local result = scl.IsAttuned(itemId)
    return result
end

-- Get attunement progress for an item
function Attunement:GetAttuneProgress(itemId)
    local scl = self.SCL or _G['SynastriaCoreLib']
    if not scl or not scl.GetAttuneProgress then
        local waitFrame = CreateFrame("Frame")
        waitFrame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed
            if self.elapsed >= 1 then
                self:SetScript("OnUpdate", nil)
                return Attunement:GetAttuneProgress(itemId)
            end
        end)
        return 0
    end
    local progress = scl.GetAttuneProgress(itemId)
    return progress or 0
end

-- Get attunement status text
function Attunement:GetStatusText(itemId, itemType)
    if not self.SCL then return itemType, SLG.Colors.NOT_ATTUNED end
    
    local ItemManager = SLG.modules.ItemManager
    
    if self:IsAttuned(itemId) then
        return "Attuned!", SLG.Colors.ATTUNED
    elseif ItemManager:IsItemEquipped(itemId) then
        local itemLink = ItemManager:GetEquippedItemLink(itemId)
        local pct = self:GetAttuneProgress(itemId)
        return string.format("Attuning: %d%%", pct), SLG.Colors.ATTUNING
    elseif ItemManager:IsItemInInventory(itemId) then
        local itemLink = ItemManager:GetInventoryItemLink(itemId)
        local pct = self:GetAttuneProgress(itemId)
        return string.format("Looted! (%d%%)", pct), SLG.Colors.ATTUNING
    else
        return itemType, SLG.Colors.NOT_ATTUNED
    end
end

-- Return the module
return Attunement 