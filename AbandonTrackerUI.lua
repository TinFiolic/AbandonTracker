-- AbandonTrackerUI.lua
local addonName, AT = ...

AbandonTrackerUI = {}
local UI = AbandonTrackerUI

-- UI Configuration
local FRAME_WIDTH = 800
local FRAME_HEIGHT = 500
local ITEM_HEIGHT = 25
local COLUMN_WIDTH = {
    QUEST = FRAME_WIDTH * 0.4,
    ITEMS = FRAME_WIDTH * 0.4,
    TIME = FRAME_WIDTH * 0.2
}

-- Initialize UI components
function UI:Init()
    -- Create minimap button first thing
    self.minimapButton = self:CreateMinimapButton()
end

-- Minimap Button (created at startup)
function UI:CreateMinimapButton()
    local button = CreateFrame("Button", "AbandonTrackerMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("HIGH") -- Increased strata for better visibility
    button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0) -- More visible position
    
    -- Make button movable
    button:SetMovable(true)
    button:EnableMouse(true)
    
    -- Create a proper background (darker to make icon stand out)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER", button, "CENTER", -11, 12) -- Explicit center positioning
    
    -- Set your custom icon with precise positioning
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24) -- Slightly smaller for better appearance
    icon:SetPoint("CENTER", button, "CENTER", -11, 12) -- Explicit center positioning
    icon:SetTexture("Interface\\AddOns\\AbandonTracker\\icon\\icon.tga")
    
    -- Add a border
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("CENTER", button, "CENTER", 0, 0) -- Explicit center positioning
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function() UI:Toggle() end)
    
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(button, "ANCHOR_LEFT")
        GameTooltip:SetText("AbandonTracker")
        GameTooltip:AddLine("Left-click to toggle window", 1, 1, 1)
        GameTooltip:AddLine("Right-click and drag to move", 1, 1, 1)
        GameTooltip:Show()
    end)
    
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    button:RegisterForDrag("RightButton")
    button:SetScript("OnDragStart", function(self) self:StartMoving() end)
    button:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    
    -- Make sure the button is shown
    button:Show()
    
    return button
end

function UI:CreateMainFrame()
    local frame = CreateFrame("Frame", "AbandonTrackerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("AbandonTracker v1.01")

    -- Close Button
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function() frame:Hide() end)

    -- Column Headers
    local questHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    questHeader:SetPoint("TOPLEFT", 25, -80)
    questHeader:SetText("Quest Name")
    
    local itemsHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemsHeader:SetPoint("TOPLEFT", 25 + COLUMN_WIDTH.QUEST, -80)
    itemsHeader:SetText("Items")
    
    local timeHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timeHeader:SetPoint("TOPRIGHT", -25, -80)
    timeHeader:SetText("Abandoned On")

    -- Fix search box - correctly handling placeholder text
    local searchBox = CreateFrame("EditBox", nil, frame)
    searchBox:SetPoint("TOPLEFT", 20, -50)
    searchBox:SetSize(200, 40)
    searchBox:SetFontObject("GameFontHighlight")
    searchBox:SetAutoFocus(false)
    searchBox:SetTextInsets(8, 8, 0, 14)
    
    -- Create texture and border
    local searchBoxBg = searchBox:CreateTexture(nil, "BACKGROUND")
    searchBoxBg:SetTexture("Interface\\Common\\Common-Input-Border")
    searchBoxBg:SetSize(200, 40)
    searchBoxBg:SetPoint("CENTER", 0, 0)
    
    -- Add placeholder text as a separate fontstring
    local placeholderText = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    placeholderText:SetPoint("LEFT", 8, 6)
    placeholderText:SetText("Search quests & items...")
    placeholderText:SetJustifyH("LEFT")
    
    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        placeholderText:SetShown(text == "")
        UI:UpdateAbandonedList()
    end)
    
    UI.searchBox = searchBox

    -- Scroll Frame
    local scrollFrame = CreateFrame("ScrollFrame", "AbandonTrackerScrollFrame", frame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -100)
    scrollFrame:SetSize(FRAME_WIDTH - 40, FRAME_HEIGHT - 150)
    
    -- List Items
    local listItems = {}
    for i = 1, 15 do
        local item = CreateFrame("Button", "AbandonTrackerItem"..i, frame)
        item:SetSize(FRAME_WIDTH - 40, ITEM_HEIGHT)
        item:SetPoint("TOPLEFT", 25, -100 - (i-1)*ITEM_HEIGHT)
        
        -- Quest Name
        item.quest = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        item.quest:SetPoint("LEFT", 5, 0)
        item.quest:SetWidth(COLUMN_WIDTH.QUEST - 10)
        item.quest:SetJustifyH("LEFT")
        
        -- Items
        item.items = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        item.items:SetPoint("LEFT", COLUMN_WIDTH.QUEST, 0)
        item.items:SetWidth(COLUMN_WIDTH.ITEMS - 10)
        item.items:SetJustifyH("LEFT")
        
        -- Timestamp
        item.time = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        item.time:SetPoint("RIGHT", -20, 0)
        item.time:SetWidth(COLUMN_WIDTH.TIME - 10)
        item.time:SetJustifyH("RIGHT")
        
        item:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")
		item:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        item:SetScript("OnClick", function(self, btn)
            if btn == "LeftButton" then 
                if self.questID then AT:DisplayQuestieItems(self.questID, self.questTitle) end
            elseif btn == "RightButton" then
                -- Right-click to remove individual quest
                if self.questID then
					SlashCmdList["ABANDONTRACKER_REMOVE"](tostring(self.questID))
                end
            end
        end)
        
        listItems[i] = item
    end
    
    scrollFrame:SetScript("OnVerticalScroll", function(_, offset)
        FauxScrollFrame_OnVerticalScroll(scrollFrame, offset, ITEM_HEIGHT, function() UI:UpdateAbandonedList() end)
    end)

    self.scrollFrame = scrollFrame
    self.listItems = listItems

    -- Clear Button
    local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearButton:SetSize(100, 20)
    clearButton:SetPoint("BOTTOMRIGHT", -10, 10)
    clearButton:SetText("Clear All")
	clearButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    clearButton:SetScript("OnClick", function()
        SlashCmdList["ABANDONTRACKER_CLEAR"]()
    end)

    return frame
end

-- Helper function to truncate text with ellipsis for overflow
function UI:TruncateText(text, maxLength)
    if not text then return "" end
    if #text <= maxLength then return text end
    return string.sub(text, 1, maxLength - 3) .. "..."
end

function UI:UpdateAbandonedList()
    local scrollFrame = self.scrollFrame
    local listItems = self.listItems
    local searchText = self.searchBox:GetText():lower()
    
    local filtered = {}
    for questID, questData in pairs(AT.abandonedQuests) do
        local title = type(questData) == "table" and questData.title or questData
        local itemsText = ""
        
        -- Build items text for searching
        if type(questData) == "table" and questData.items then
            for _, itemData in ipairs(questData.items) do
                itemsText = itemsText .. " " .. (itemData.name or "")
            end
        end
        
        -- Search in both title and items
        if title:lower():find(searchText, 1, true) or itemsText:lower():find(searchText, 1, true) then
            table.insert(filtered, {
                id = questID,
                title = title,
                timestamp = questData.timestamp,
                items = questData.items
            })
        end
    end
    
    table.sort(filtered, function(a,b) return (a.timestamp or "") > (b.timestamp or "") end)
    
    FauxScrollFrame_Update(scrollFrame, #filtered, #listItems, ITEM_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(scrollFrame)
    
    for i = 1, #listItems do
        local item = listItems[i]
        local index = i + offset
        
        if index <= #filtered then
            local quest = filtered[index]
            item.questID = quest.id
            item.questTitle = quest.title
            
            -- Format timestamp
            local formattedTime = "Unknown"
            if quest.timestamp then
                formattedTime = quest.timestamp:gsub("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)", "%1/%2/%3 %4:%5:%6")
            end
            
            -- Set columns
            item.quest:SetText("|cffff6600" .. quest.title .. "|r")
            item.time:SetText("|cffaaaaaa" .. formattedTime .. "|r")
            
            local itemsText = ""
            if quest.items and #quest.items > 0 then
                for j, itemData in ipairs(quest.items) do
                    if j > 1 then itemsText = itemsText .. ", " end
                    local itemName = GetItemInfo(itemData.itemId) or itemData.name or "Unknown"
                    itemsText = itemsText .. itemName
                end
            else
                itemsText = "No items"
            end
            
            -- Truncate if too long
            local truncated = self:TruncateText(itemsText, 50)
            item.items:SetText(truncated)
            
            -- Add tooltip for full text if truncated
            if truncated ~= itemsText then
                item:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.questTitle)
                    GameTooltip:AddLine("Items:", 1, 1, 1)
                    GameTooltip:AddLine(itemsText, 1, 0.82, 0, true)
                    GameTooltip:AddLine("Right-click to remove from list", 0.7, 0.7, 1)
                    GameTooltip:Show()
                end)
                item:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            else
                item:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.questTitle)
                    GameTooltip:AddLine("Right-click to remove from list", 0.7, 0.7, 1)
                    GameTooltip:Show()
                end)
                item:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            end
            
            item:Show()
        else
            item:Hide()
        end
    end
end

function UI:Toggle()
    if not self.frame then
        self.frame = self:CreateMainFrame()
    end
    self.frame:SetShown(not self.frame:IsShown())
    if self.frame:IsShown() then self:UpdateAbandonedList() end
end

-- Start the addon
AT.frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and ... == addonName then
        UI:Init()
        C_Timer.After(1, function() 
            AT:CheckQuestie()
        end)
    end
end)
