-- AbandonTracker.lua
local addonName, AT = ...

-- Initialize frame for event handling
local frame = CreateFrame("Frame")

-- Register events
frame:RegisterEvent("QUEST_REMOVED")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")

-- Table to store quest item data
AT.questItems = {}

-- Database to store quest titles for abandoned quests with timestamps
AT.abandonedQuests = {}

-- Table to track active quests
AT.activeQuests = {}

-- Flag to track if Questie is available
AT.questieAvailable = false
AT.questieRetryCount = 0

-- Initialize frame for event handling
AT.frame = CreateFrame("Frame")

-- Function to get quest title using tooltip method if API fails
function AT:GetQuestTitle(questID)
    local title = C_QuestLog.GetQuestInfo(questID)
    if not title or title == "" then
        local tooltip = CreateFrame("GameTooltip", "ATQuestTooltip", nil, "GameTooltipTemplate")
        tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
        tooltip:SetHyperlink("quest:"..questID)
        if tooltip:NumLines() > 0 then
            title = _G["ATQuestTooltipTextLeft1"]:GetText()
        end
    end
    return title or "Unknown Quest (ID: "..questID..")"
end

-- Check if Questie is loaded and available
function AT:CheckQuestie()
    -- First check if Questie addon exists
    if not IsAddOnLoaded("Questie") then
        return false
    end
    
    -- Then check if the global Questie object exists
    if not Questie then
        return false
    end
    
    -- Check if QuestieLoader exists
    if not QuestieLoader then
        return false
    end
    
    -- Try to import QuestieDB module
    local success, QuestieDB = pcall(function() 
        return QuestieLoader:ImportModule("QuestieDB") 
    end)
    
    if not success or not QuestieDB then
        return false
    end
    
    -- Check if the QueryQuestSingle function exists
    if not QuestieDB.QueryQuestSingle then
        return false
    end
    
    self.questieAvailable = true
    return true
end

-- Attempt to connect to Questie with retries
function AT:TryConnectQuestie()
    if self:CheckQuestie() then
        print("|cff33ff99AbandonTracker|r: Questie detected. Using Questie's database for quest items.")
        -- Scan quest log to track existing quests
        self:ScanQuestLog()
        return true
    else
        self.questieRetryCount = self.questieRetryCount + 1
        
        if self.questieRetryCount < 3 then
            print("|cffff9900AbandonTracker|r: Questie not detected yet. Will retry in 10 seconds...")
            C_Timer.After(10, function() 
                self:TryConnectQuestie() 
            end)
        else
            print("|cffff0000AbandonTracker|r: Questie is necessary to run AbandonTracker! Please use /reload to manually reload your UI after Questie has fully loaded.")
        end
        return false
    end
end

-- Scan the quest log and add all active quests to our tracking
function AT:ScanQuestLog()
    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
        if not isHeader and questID then
            self.activeQuests[questID] = true
        end
    end
end

-- Get quest items from Questie's database
function AT:GetQuestItemsFromQuestie(questID)
    if not self.questieAvailable then
        return nil
    end
    
    -- Import QuestieDB module
    local success, QuestieDB = pcall(function() 
        return QuestieLoader:ImportModule("QuestieDB") 
    end)
    
    if not success or not QuestieDB then
        return nil
    end
    
    local questItems = {}
    
    -- Get quest data using QueryQuestSingle for specific fields
    local sourceItemId = QuestieDB.QueryQuestSingle(questID, "sourceItemId")
    local requiredSourceItems = QuestieDB.QueryQuestSingle(questID, "requiredSourceItems")
    local objectives = QuestieDB.QueryQuestSingle(questID, "objectives")
    
    -- Source Item (item provided by quest starter)
    if sourceItemId and sourceItemId > 0 then
        local itemName = QuestieDB.QueryItemSingle(sourceItemId, "name") or "Unknown Item"
        table.insert(questItems, {itemId = sourceItemId, type = "source", name = itemName})
    end
    
    -- Required Source Items (items needed but not objectives)
    if requiredSourceItems then
        for _, itemId in ipairs(requiredSourceItems) do
            local itemName = QuestieDB.QueryItemSingle(itemId, "name") or "Unknown Item"
            table.insert(questItems, {itemId = itemId, type = "required", name = itemName})
        end
    end
    
    -- Item Objectives
    if objectives and objectives[3] then -- itemObjectives are at index 3
        for _, itemData in ipairs(objectives[3]) do
            local itemId = itemData[1]
            local itemName = QuestieDB.QueryItemSingle(itemId, "name") or "Unknown Item"
            table.insert(questItems, {itemId = itemId, type = "objective", name = itemName})
        end
    end
    
    return #questItems > 0 and questItems or nil
end

-- Function to handle events
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and ... == addonName then
        if not AbandonTrackerDB then
            AbandonTrackerDB = {
                characters = {}
            }
        end
        
        if not AbandonTrackerDB.characters then
            AbandonTrackerDB.characters = {}
        end
        
        local playerKey = AT:GetPlayerKey()
        
        if not AbandonTrackerDB.characters[playerKey] then
            AbandonTrackerDB.characters[playerKey] = {
                abandonedQuests = {},
                customQuestItems = {}
            }
        end
		
		if AbandonTrackerUI then
            AbandonTrackerUI:Init()
        end
        
        AT.abandonedQuests = AbandonTrackerDB.characters[playerKey].abandonedQuests or {}
        print("|cff33ff99AbandonTracker|r v1.01: Loaded. Tracking abandoned quests for " .. playerKey .. ".")
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Check for Questie after player enters world (ensures Questie is fully loaded)
        C_Timer.After(2, function()
            AT:TryConnectQuestie()
        end)
        
    elseif event == "QUEST_ACCEPTED" then
        local index, questID = ...
        AT.activeQuests[questID] = true
        
    elseif event == "QUEST_REMOVED" then
        local questID = ...
        
        if AT.activeQuests[questID] then
            local questTitle = AT:GetQuestTitle(questID)
            local timestamp = date("%Y-%m-%d %H:%M:%S")
            
            AT.abandonedQuests[questID] = {
                title = questTitle,
                timestamp = timestamp,
                items = AT:GetQuestItemsFromQuestie(questID)
            }
            
            local playerKey = AT:GetPlayerKey()
            if not AbandonTrackerDB.characters[playerKey] then
                AbandonTrackerDB.characters[playerKey] = {
                    abandonedQuests = {}
                }
            end
            AbandonTrackerDB.characters[playerKey].abandonedQuests[questID] = AT.abandonedQuests[questID]
            
            print("|cff33ff99AbandonTracker|r: You abandoned quest: |cffff6600" .. questTitle .. "|r")
            
            if AT.questieAvailable then
                AT:DisplayQuestieItems(questID, questTitle)
            else
                -- Try to reconnect to Questie if it wasn't available before
                if AT:CheckQuestie() then
                    AT:DisplayQuestieItems(questID, questTitle)
                else
                    print("|cffff0000AbandonTracker|r: Questie is required to display quest items.")
                end
            end
            
            AT.activeQuests[questID] = nil
        end
        
    elseif event == "PLAYER_LOGOUT" then
        local playerKey = AT:GetPlayerKey()
        if not AbandonTrackerDB.characters[playerKey] then
            AbandonTrackerDB.characters[playerKey] = {}
        end
        AbandonTrackerDB.characters[playerKey].abandonedQuests = AT.abandonedQuests
    end
end)

-- Function to display quest items from Questie
function AT:DisplayQuestieItems(questID, questTitle)
    local items = self:GetQuestItemsFromQuestie(questID)
    
    if not items or #items == 0 then
        return
    end
    
    -- Group items by type
    local sourceItems = {}
    local requiredItems = {}
    local objectiveItems = {}
    
    for _, item in ipairs(items) do
        if item.type == "source" then
            table.insert(sourceItems, item)
        elseif item.type == "required" then
            table.insert(requiredItems, item)
        elseif item.type == "objective" then
            table.insert(objectiveItems, item)
        end
    end
    
    -- Display objective items (most important)
    if #objectiveItems > 0 then
        print("|cff33ff99AbandonTracker|r: Quest objective items for |cffff6600" .. questTitle .. "|r:")
        for _, item in ipairs(objectiveItems) do
            local itemLink = select(2, GetItemInfo(item.itemId))
            if itemLink then
                print("  - " .. itemLink .. " (Objective)")
            else
                C_Timer.After(1, function()
                    local delayedItemLink = select(2, GetItemInfo(item.itemId))
                    if delayedItemLink then
                        print("  - " .. delayedItemLink .. " (Objective)")
                    else
                        print("  - " .. item.name .. " (ID: " .. item.itemId .. ") (Objective)")
                    end
                end)
            end
        end
    end
    
    -- Display source items
    if #sourceItems > 0 then
        print("|cff33ff99AbandonTracker|r: Quest source items for |cffff6600" .. questTitle .. "|r:")
        for _, item in ipairs(sourceItems) do
            local itemLink = select(2, GetItemInfo(item.itemId))
            if itemLink then
                print("  - " .. itemLink .. " (Source)")
            else
                C_Timer.After(1, function()
                    local delayedItemLink = select(2, GetItemInfo(item.itemId))
                    if delayedItemLink then
                        print("  - " .. delayedItemLink .. " (Source)")
                    else
                        print("  - " .. item.name .. " (ID: " .. item.itemId .. ") (Source)")
                    end
                end)
            end
        end
    end
    
    -- Display required items
    if #requiredItems > 0 then
        print("|cff33ff99AbandonTracker|r: Required items for |cffff6600" .. questTitle .. "|r:")
        for _, item in ipairs(requiredItems) do
            local itemLink = select(2, GetItemInfo(item.itemId))
            if itemLink then
                print("  - " .. itemLink .. " (Required)")
            else
                C_Timer.After(1, function()
                    local delayedItemLink = select(2, GetItemInfo(item.itemId))
                    if delayedItemLink then
                        print("  - " .. delayedItemLink .. " (Required)")
                    else
                        print("  - " .. item.name .. " (ID: " .. item.itemId .. ") (Required)")
                    end
                end)
            end
        end
    end
end

-- Function to get a unique key for the current character
function AT:GetPlayerKey()
    local playerName = UnitName("player")
    local realmName = GetRealmName()
    return playerName .. "-" .. realmName
end


-- Enhanced slash commands
SLASH_ABANDONTRACKER1 = "/at"
SLASH_ABANDONTRACKER2 = "/abandontracker"
SlashCmdList["ABANDONTRACKER"] = function(msg)
    local command, rest = msg:match("^(%S*)%s*(.-)$")
    
    if command == "ui" or command == "" then
        -- Toggle UI
        if AbandonTrackerUI then
            AbandonTrackerUI:Toggle()
        else
            print("|cff33ff99AbandonTracker|r: UI module not loaded.")
        end
    end
end

SLASH_ABANDONTRACKER_REMOVE1 = "/atremove"
SlashCmdList["ABANDONTRACKER_REMOVE"] = function(msg)
    local questID = tonumber(msg)
    if questID and AT.abandonedQuests[questID] then
        local playerKey = AT:GetPlayerKey()
        AT.abandonedQuests[questID] = nil
        if AbandonTrackerDB.characters and AbandonTrackerDB.characters[playerKey] then
            AbandonTrackerDB.characters[playerKey].abandonedQuests[questID] = nil
        end
        print("|cff33ff99AbandonTracker|r: Removed quest ID " .. questID .. " from abandoned quest history.")
        if AbandonTrackerUI and AbandonTrackerUI.frame and AbandonTrackerUI.frame:IsShown() then
            AbandonTrackerUI:UpdateAbandonedList()
        end
    else
        print("|cffff0000AbandonTracker|r: Invalid quest ID or quest not found in abandoned history.")
    end
end

SLASH_ABANDONTRACKER_CLEAR1 = "/atclear"
SlashCmdList["ABANDONTRACKER_CLEAR"] = function()
    AT.abandonedQuests = {}
    local playerKey = AT:GetPlayerKey()
    if AbandonTrackerDB.characters and AbandonTrackerDB.characters[playerKey] then
        AbandonTrackerDB.characters[playerKey].abandonedQuests = {}
    else
        AbandonTrackerDB.abandonedQuests = {}
    end
    print("|cff33ff99AbandonTracker|r: Cleared abandoned quest history.")
    if AbandonTrackerUI and AbandonTrackerUI.frame and AbandonTrackerUI.frame:IsShown() then
        AbandonTrackerUI:UpdateAbandonedList()
    end
end


