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

-- Game version
AT.gameVersion = "classic"

-- Table to track active quests
AT.activeQuests = {}

-- Flag to track if Questie is available
AT.questieAvailable = false
AT.questieRetryCount = 0

-- Initialize frame for event handling
AT.frame = CreateFrame("Frame")

function AT:DetectGameVersion()
    local _, _, _, clientVersion = GetBuildInfo()
    self.gameVersion = clientVersion >= 50000 and "cata" or "classic"
end

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

function AT:SetQuestNote(questID, note)
    local playerKey = self:GetPlayerKey()
    if not AbandonTrackerDB.characters[playerKey].questNotes then
        AbandonTrackerDB.characters[playerKey].questNotes = {}
    end
    AbandonTrackerDB.characters[playerKey].questNotes[questID] = note
end

function AT:GetQuestNote(questID)
    local playerKey = self:GetPlayerKey()
    return AbandonTrackerDB.characters[playerKey].questNotes 
        and AbandonTrackerDB.characters[playerKey].questNotes[questID]
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
                customQuestItems = {},
				questNotes = {}
            }
        end
		
		if AbandonTrackerUI then
            AbandonTrackerUI:Init()
        end
        
        AT.abandonedQuests = AbandonTrackerDB.characters[playerKey].abandonedQuests or {}
        print("|cff33ff99AbandonTracker|r v1.02: Loaded. Tracking abandoned quests for " .. playerKey .. ".")
        
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

function AT:ShowQuestDetails(questID)
    -- Safely get QuestieDB
    if not Questie or not QuestieLoader then
        print("|cffff0000AbandonTracker|r: Questie not loaded or detected.")
        return
    end
    
    local success, QuestieDB = pcall(function()
        return QuestieLoader:ImportModule("QuestieDB")
    end)
    
    if not success or not QuestieDB then
        print("|cffff0000AbandonTracker|r: Failed to load QuestieDB module.")
        return
    end
    
    -- Get basic quest info
    local questName = QuestieDB.QueryQuestSingle(questID, "name") or "Unknown Quest"
    local questLevel = QuestieDB.QueryQuestSingle(questID, "questLevel") or 0
    local objectives = QuestieDB.QueryQuestSingle(questID, "objectivesText") or {"No objectives available"}
    local objectivesData = QuestieDB.QueryQuestSingle(questID, "objectives") or {}
    
    -- Get source and required items
    local sourceItemId = QuestieDB.QueryQuestSingle(questID, "sourceItemId")
    local requiredItems = QuestieDB.QueryQuestSingle(questID, "requiredSourceItems") or {}
    
    -- Get who starts and ends the quest
    local startedBy = QuestieDB.QueryQuestSingle(questID, "startedBy") or {{},{},{}}
    local finishedBy = QuestieDB.QueryQuestSingle(questID, "finishedBy") or {{},{},{}}
    
    -- Create the window frame - IMPORTANT: Use BackdropTemplate
    local frame = CreateFrame("Frame", "ATQuestDetails", UIParent, "BackdropTemplate")
    frame:SetSize(550, 450)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    
    -- Set solid background
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    
    -- Add title bar
    local titleBar = frame:CreateTexture(nil, "ARTWORK")
    titleBar:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleBar:SetWidth(600)
    titleBar:SetHeight(64)
    titleBar:SetPoint("TOP", 0, 12)
    
    local titleText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    titleText:SetPoint("TOP", titleBar, "TOP", 0, -14)
    titleText:SetText(questName.." (Level "..questLevel..")")
    
    -- Close button
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
	closeButton:SetScript("OnClick", function() 
		frame:Hide() 
		AbandonTrackerUI.frame:Show()  -- Fixed reference
	end)
    
    -- Scrollable content
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -45)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 35)
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(500, 800)  -- Make it tall enough for all content
    scrollFrame:SetScrollChild(content)
    
    -- Description header
    local descHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    descHeader:SetPoint("TOPLEFT", 10, -10)
    descHeader:SetText("Quest Description:")
    
    -- Description text
    local descText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    descText:SetPoint("TOPLEFT", 15, -30)
    descText:SetWidth(470)
    descText:SetJustifyH("LEFT")
    if type(objectives) == "table" then
        descText:SetText(table.concat(objectives, "\n\n"))
    else
        descText:SetText(objectives or "No description available")
    end
    
    local yOffset = -30 - descText:GetHeight() - 20
    
    -- Quest NPCs
    local npcHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    npcHeader:SetPoint("TOPLEFT", 10, yOffset)
    npcHeader:SetText("Quest NPCs:")
    yOffset = yOffset - 20
    
    -- Quest starter NPCs
    if startedBy and startedBy[1] and #startedBy[1] > 0 then
        for _, npcID in ipairs(startedBy[1]) do
            local npcName = QuestieDB.QueryNPCSingle(npcID, "name") or "Unknown NPC"
            local npcText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            npcText:SetPoint("TOPLEFT", 15, yOffset)
            npcText:SetText("Started by: |cff00ff00"..npcName.."|r")
            yOffset = yOffset - 15
        end
    end
    
    -- Quest completer NPCs
    if finishedBy and finishedBy[1] and #finishedBy[1] > 0 then
        for _, npcID in ipairs(finishedBy[1]) do
            local npcName = QuestieDB.QueryNPCSingle(npcID, "name") or "Unknown NPC"
            local npcText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            npcText:SetPoint("TOPLEFT", 15, yOffset)
            npcText:SetText("Completed at: |cff00ff00"..npcName.."|r")
            yOffset = yOffset - 15
        end
    end
    
    yOffset = yOffset - 20
    
    -- Source items section (if exists)
    if sourceItemId and sourceItemId > 0 then
        local sourceHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        sourceHeader:SetPoint("TOPLEFT", 10, yOffset)
        sourceHeader:SetText("Source Item:")
        yOffset = yOffset - 20
        
        local itemName = QuestieDB.QueryItemSingle(sourceItemId, "name") or "Unknown Item"
        
        -- Create interactive item icon
        local icon = content:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24)
        icon:SetPoint("TOPLEFT", 15, yOffset)
        
        -- Try to get item texture
        C_Item.RequestLoadItemDataByID(sourceItemId)
        local itemTexture = select(5, GetItemInfoInstant(sourceItemId))
        if itemTexture then
            icon:SetTexture(itemTexture)
        else
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
        
        -- Create text to show item name
        local itemText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        itemText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        itemText:SetText(itemName)
        
        -- Make the icon interactive for tooltip
        local iconButton = CreateFrame("Button", nil, content)
        iconButton:SetSize(24, 24)
        iconButton:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        iconButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(sourceItemId)
            GameTooltip:Show()
        end)
        iconButton:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        
        yOffset = yOffset - 30
    end
    
    -- Required items
    if requiredItems and #requiredItems > 0 then
        local reqHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        reqHeader:SetPoint("TOPLEFT", 10, yOffset)
        reqHeader:SetText("Required Items:")
        yOffset = yOffset - 20
        
        for _, itemID in ipairs(requiredItems) do
            local itemName = QuestieDB.QueryItemSingle(itemID, "name") or "Unknown Item"
            
            -- Create interactive item icon
            local icon = content:CreateTexture(nil, "ARTWORK")
            icon:SetSize(24, 24)
            icon:SetPoint("TOPLEFT", 15, yOffset)
            
            -- Try to get item texture
            C_Item.RequestLoadItemDataByID(itemID)
            local itemTexture = select(5, GetItemInfoInstant(itemID))
            if itemTexture then
                icon:SetTexture(itemTexture)
            else
                icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
            
            -- Create text to show item name
            local itemText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            itemText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
            itemText:SetText(itemName)
            
            -- Make the icon interactive for tooltip
            local iconButton = CreateFrame("Button", nil, content)
            iconButton:SetSize(24, 24)
            iconButton:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
            iconButton:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(itemID)
                GameTooltip:Show()
            end)
            iconButton:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            
            yOffset = yOffset - 30
        end
        
        yOffset = yOffset - 10
    end
    
    -- Objective items section (from objectives data)
    if objectivesData and objectivesData[3] then -- Item objectives are at index 3
        local objHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        objHeader:SetPoint("TOPLEFT", 10, yOffset)
        objHeader:SetText("Objective Items:")
        yOffset = yOffset - 20
        
        for _, itemData in pairs(objectivesData[3]) do
            local itemID = itemData[1]
            local required = itemData[2] or 1
            local itemName = QuestieDB.QueryItemSingle(itemID, "name") or "Unknown Item"
            
            -- Create interactive item icon
            local icon = content:CreateTexture(nil, "ARTWORK")
            icon:SetSize(24, 24)
            icon:SetPoint("TOPLEFT", 15, yOffset)
            
            -- Try to get item texture
            C_Item.RequestLoadItemDataByID(itemID)
            local itemTexture = select(5, GetItemInfoInstant(itemID))
            if itemTexture then
                icon:SetTexture(itemTexture)
            else
                icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
            
            -- Create text to show item name and required count
            local itemText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            itemText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
            itemText:SetText(itemName.." (0/"..required..")")
            
            -- Make the icon interactive for tooltip
            local iconButton = CreateFrame("Button", nil, content)
            iconButton:SetSize(24, 24)
            iconButton:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
            iconButton:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(itemID)
                GameTooltip:Show()
            end)
            iconButton:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            
            yOffset = yOffset - 30
        end
    end
    
    -- Wowhead Link
    local wowheadHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	yOffset = yOffset - 20
    wowheadHeader:SetPoint("TOPLEFT", 10, yOffset)
    wowheadHeader:SetText("Wowhead Link:")
    yOffset = yOffset - 20
    
    local url = AT.gameVersion == "cata" 
        and "https://www.wowhead.com/cata/quest="..questID 
        or "https://www.wowhead.com/classic/quest="..questID
    
    local editBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    editBox:SetSize(400, 20)
    editBox:SetPoint("TOPLEFT", 15, yOffset)
    editBox:SetAutoFocus(false)
    editBox:SetText(url)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(url)
            self:HighlightText()
        end
    end)
    
    local copyHint = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    copyHint:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -2)
    copyHint:SetText("Click to select, Ctrl+C to copy")
    
    frame:Show()
end

local frame = CreateFrame("Frame", "ATQuestDetails", UIParent, "BackdropTemplate")
-- Add this after frame creation:
frame:SetScript("OnHide", function(self)
    if AbandonTrackerUI.frame and AbandonTrackerUI.wasMainVisible then
        AbandonTrackerUI.frame:Show()
    end
end)
