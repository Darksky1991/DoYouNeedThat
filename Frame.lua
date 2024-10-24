local _, AddOn = ...
local L = AddOn.L

local icon = LibStub("LibDBIcon-1.0")
local CreateFrame, unpack, GetItemInfo, select = CreateFrame, unpack, C_Item.GetItemInfo, select
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local ITEM_QUALITY_COLORS, CreateFont, UIParent = ITEM_QUALITY_COLORS, CreateFont, UIParent
local tsort, tonumber, xpcall, geterrorhandler = table.sort, tonumber, xpcall, geterrorhandler
local IsModifiedClick, ChatEdit_InsertLink, DressUpItemLink = IsModifiedClick, ChatEdit_InsertLink, DressUpItemLink
local ShowUIPanel, GameTooltip = ShowUIPanel, GameTooltip
local IsAzeriteEmpoweredItemByID = C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItemByID
local OpenAzeriteEmpoweredItemUIFromLink = OpenAzeriteEmpoweredItemUIFromLink
local BackdropTemplateMixin = BackdropTemplateMixin

local function showItemTooltip(itemLink)
    ShowUIPanel(GameTooltip)
    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(itemLink)
    --GameTooltip_ShowCompareItem()
    GameTooltip:Show()
end

local function hideItemTooltip() GameTooltip:Hide() end

local function skinBackdrop(frame, ...)
    if (frame.background) then return false end

    local border = {0,0,0,1}
    local color = {...}
    if (not ... ) then
        color = {.11,.15,.18, 1}
        border = {.06, .08, .09, 1}
    end

    frame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
    frame:SetBackdropColor(unpack(color))
    frame:SetBackdropBorderColor(unpack(border))

    return true
end

local function skinButton(frame, small, color)
    local colors = {.1,.1,.1,1}
    local hovercolors = {0,0.55,.85,1}
    if (color == "red") then
        colors = {.6,.1,.1,0.6}
        hovercolors = {.6,.1,.1,1}
    elseif (color == "blue") then
        colors = {0,0.55,.85,0.6}
        hovercolors = {0,0.55,.85,1}
    elseif (color == "dark") then
        colors = {.1,.1,.1,1}
        hovercolors = {.1,.1,.1,1}
    elseif (color == "lightgrey") then
        colors = {.219, .219, .219, 1}
        hovercolors = {.270, .270, .270, 1}
    end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = {left=1,top=1,right=1,bottom=1}
    })
    frame:SetBackdropColor(unpack(colors))
    frame:SetBackdropBorderColor(0,0,0,1)
    frame:SetNormalFontObject("dynt_button")
    frame:SetHighlightFontObject("dynt_button")
    frame:SetPushedTextOffset(0,-1)

    frame:SetSize(frame:GetTextWidth()+16,24)

    if (small and frame:GetWidth() <= 24 ) then
        frame:SetWidth(20)
    end

    if (small) then
        frame:SetHeight(18)
    end

    frame:HookScript("OnEnter", function(f)
        f:SetBackdropColor(unpack(hovercolors))
    end)
    frame:HookScript("OnLeave", function(f)
        f:SetBackdropColor(unpack(colors))
    end)

    return true
end

local function setItemBorderColor(frame, item)
    local color = ITEM_QUALITY_COLORS[select(3, GetItemInfo(item))]
    frame:SetBackdropBorderColor(color.r, color.g, color.b, 1)
    return true
end

function AddOn:repositionFrames()
	local lastentry = nil

	tsort(AddOn.Entries, function(a,b)
		return tonumber(a.ilvl:GetText()) > tonumber(b.ilvl:GetText())
	end)

	for i = 1, #AddOn.Entries do
		local currententry = AddOn.Entries[i]
		if currententry.itemLink then
			if lastentry then
				currententry:SetPoint("TOPLEFT", lastentry, "BOTTOMLEFT", 0, 1)
			else
				currententry:SetPoint("TOPLEFT", AddOn.lootFrame.table.content, "TOPLEFT", 0, 1)
			end
			lastentry = currententry
		end
	end
end

function AddOn.setItemTooltip(frame, item)
	local tex = select(5, GetItemInfoInstant(item))
	frame.tex:SetTexture(tex)
	frame:SetScript("OnEnter", function() showItemTooltip(item) end)
	frame:SetScript("OnLeave", function() hideItemTooltip() end)
    frame:SetScript("OnClick", function(_, button)
        if IsModifiedClick("CHATLINK") then
            if ChatEdit_InsertLink(item) then return true end
        end
        if IsModifiedClick("DRESSUP") then return DressUpItemLink(item) end
        if button == "RightButton" and IsModifiedClick("EXPANDITEM") then
            if IsAzeriteEmpoweredItemByID(item) then
                OpenAzeriteEmpoweredItemUIFromLink(item);
                return true;
            end
        end
    end)
	setItemBorderColor(frame, item)
	frame:Show()
end

local normal_button_text = CreateFont("dynt_button")
normal_button_text:SetFont("Interface\\AddOns\\DoYouNeedThat\\Media\\Roboto-Medium.ttf", 12, "")
normal_button_text:SetTextColor(1,1,1,1)
normal_button_text:SetShadowColor(0, 0, 0)
normal_button_text:SetShadowOffset(1, -1)
normal_button_text:SetJustifyH("CENTER")

local large_font = CreateFont("dynt_large_text")
large_font:SetFont("Interface\\AddOns\\DoYouNeedThat\\Media\\Roboto-Medium.ttf", 14, "")
large_font:SetShadowColor(0, 0, 0)
large_font:SetShadowOffset(1, -1)

local normal_font = CreateFont("dynt_normal_text")
normal_font:SetFont("Interface\\AddOns\\DoYouNeedThat\\Media\\Roboto-Medium.ttf", 11, "")
normal_font:SetTextColor(1,1,1,1)
normal_font:SetShadowColor(0, 0, 0)
normal_font:SetShadowOffset(1, -1)
normal_font:SetJustifyH("CENTER")

-- Window
---@type Frame
AddOn.lootFrame = CreateFrame('frame', 'DYNT', UIParent, "BackdropTemplate")
skinBackdrop(AddOn.lootFrame, .1,.1,.1,.8)
AddOn.lootFrame:EnableMouse(true)
AddOn.lootFrame:SetMovable(true)
AddOn.lootFrame:SetUserPlaced(true)
AddOn.lootFrame:SetFrameStrata("DIALOG")
AddOn.lootFrame:SetFrameLevel(1)
AddOn.lootFrame:SetClampedToScreen(true)
AddOn.lootFrame:SetSize(380, 200)
AddOn.lootFrame:SetPoint("CENTER")
AddOn.lootFrame:Hide()

-- Header
---@type Frame
AddOn.lootFrame.header = CreateFrame('frame', nil, AddOn.lootFrame, "BackdropTemplate")
AddOn.lootFrame.header:EnableMouse(true)
AddOn.lootFrame.header:RegisterForDrag('LeftButton','RightButton')
AddOn.lootFrame.header:SetScript("OnDragStart", function() AddOn.lootFrame:StartMoving() end)
AddOn.lootFrame.header:SetScript("OnDragStop", function()
	AddOn.lootFrame:StopMovingOrSizing() 
	local point, _, _, x, y = AddOn.lootFrame:GetPoint()
	AddOn.db.lootWindow = { point, x, y }
end)
AddOn.lootFrame.header:SetPoint("TOPLEFT", AddOn.lootFrame, "TOPLEFT")
AddOn.lootFrame.header:SetPoint("BOTTOMRIGHT", AddOn.lootFrame, "TOPRIGHT", 0, -24)
skinBackdrop(AddOn.lootFrame.header,.1,.1,.1,1)

local minimized = false
---@type Button
AddOn.lootFrame.header.minimize = CreateFrame("Button", nil, AddOn.lootFrame.header, "BackdropTemplate")
AddOn.lootFrame.header.minimize:SetPoint("RIGHT", AddOn.lootFrame.header, "RIGHT", -30, 0)
AddOn.lootFrame.header.minimize:SetText("-")
skinButton(AddOn.lootFrame.header.minimize, true, "lightgrey")
AddOn.lootFrame.header.minimize:SetScript("OnClick", function(self)
	if minimized then
		AddOn.lootFrame:SetSize(380, 200)
		AddOn.lootFrame.table:Show()
		self:SetText("-")
		minimized = false
	else
		AddOn.lootFrame:SetSize(380, 24)
		AddOn.lootFrame.table:Hide()
		self:SetText("+")
		minimized = true
	end
end)

---@type Button
AddOn.lootFrame.header.close = CreateFrame("Button", nil, AddOn.lootFrame.header, "BackdropTemplate")
AddOn.lootFrame.header.close:SetPoint("RIGHT", AddOn.lootFrame.header, "RIGHT", -4, 0)
AddOn.lootFrame.header.close:SetText("x")
skinButton(AddOn.lootFrame.header.close, true, "red")
AddOn.lootFrame.header.close:SetScript("OnClick", function() 
	AddOn.lootFrame:Hide() 
	AddOn.db.lootWindowOpen = false
end)

AddOn.lootFrame.header.text = AddOn.lootFrame.header:CreateFontString(nil, "OVERLAY", "dynt_large_text")
AddOn.lootFrame.header.text:SetText("|cFFFF6B6BDoYouNeedThat")
AddOn.lootFrame.header.text:SetPoint("CENTER", AddOn.lootFrame.header, "CENTER")

-- Vote table
---@type Frame
local loot_table = CreateFrame("Frame", nil, AddOn.lootFrame, "BackdropTemplate")
loot_table:SetPoint("TOPLEFT", AddOn.lootFrame, "TOPLEFT", 10, -50)
loot_table:SetPoint("BOTTOMRIGHT", AddOn.lootFrame, "BOTTOMRIGHT", -30, 10)
skinBackdrop(loot_table, .1,.1,.1,.8)
AddOn.lootFrame.table = loot_table

---@type ScrollFrame
local scrollframe = CreateFrame("ScrollFrame", nil, loot_table)
scrollframe:SetPoint("TOPLEFT", loot_table, "TOPLEFT", 0, -2)
scrollframe:SetPoint("BOTTOMRIGHT", loot_table, "BOTTOMRIGHT", 0, 2)
loot_table.scrollframe = scrollframe

---@type Slider
local scrollbar = CreateFrame("Slider", nil, scrollframe, "UIPanelScrollBarTemplate")
Mixin(scrollbar, BackdropTemplateMixin)
scrollbar:SetPoint("TOPLEFT", loot_table, "TOPRIGHT", 6, -16) 
scrollbar:SetPoint("BOTTOMLEFT", loot_table, "BOTTOMRIGHT", 0, 16)
scrollbar:SetMinMaxValues(1, 60)
scrollbar:SetValueStep(1)
scrollbar.scrollStep = 1
scrollbar:SetValue(0)
scrollbar:SetWidth(16)
scrollbar:SetScript("OnValueChanged", function (self, value) self:GetParent():SetVerticalScroll(value) end) 
skinBackdrop(scrollbar, .1,.1,.1,.8)
loot_table.scrollbar = scrollbar

---@type Frame
loot_table.content = CreateFrame("Frame", nil, scrollframe)
loot_table.content:SetSize(340, 140)
scrollframe:SetScrollChild(loot_table.content)


loot_table.item_text = loot_table:CreateFontString(nil, "OVERLAY", "dynt_button")
loot_table.item_text:SetText(L["Item"])
loot_table.item_text:SetTextColor(1, 1, 1)
loot_table.item_text:SetPoint("TOPLEFT", loot_table, "TOPLEFT", 10, 16)

loot_table.ilvl_text = loot_table:CreateFontString(nil, "OVERLAY", "dynt_button")
loot_table.ilvl_text:SetText(L["ILvl"])
loot_table.ilvl_text:SetTextColor(1, 1, 1)
loot_table.ilvl_text:SetPoint("TOPLEFT", loot_table, "TOPLEFT", 50, 16)

loot_table.name_text = loot_table:CreateFontString(nil, "OVERLAY", "dynt_button")
loot_table.name_text:SetText(L["Looter"])
loot_table.name_text:SetTextColor(1, 1, 1)
loot_table.name_text:SetPoint("TOPLEFT", loot_table, "TOPLEFT", 90, 16)

loot_table.equipped_text = loot_table:CreateFontString(nil, "OVERLAY", "dynt_button")
loot_table.equipped_text:SetText(L["Looter Eq"])
loot_table.equipped_text:SetTextColor(1, 1, 1)
loot_table.equipped_text:SetPoint("TOPLEFT", loot_table, "TOPLEFT", 175, 16)

local lastframe = nil
for i = 1, 20 do
	---@type Button
	local entry = CreateFrame("Button", nil, loot_table.content, "BackdropTemplate")
	entry:SetSize(loot_table.content:GetWidth(), 24)
	if (lastframe) then
		entry:SetPoint("TOPLEFT", lastframe, "BOTTOMLEFT", 0, 2)
	else
		entry:SetPoint("TOPLEFT", loot_table.content, "TOPLEFT", 0, -3)
	end
	skinBackdrop(entry, 1,1,1,.1)
	entry:Hide()

	---@type Frame
	entry.item = CreateFrame("Button", nil, entry, "BackdropTemplate")
	entry.item:SetSize(20,20)
	--entry.item:Hide()
	entry.item:SetPoint("LEFT", entry, "LEFT", 12, 0)
    entry.item:RegisterForClicks("LeftButtonDown","RightButtonUp")
	skinBackdrop(entry.item, 0, 0, 0, 1)

	entry.item.tex = entry.item:CreateTexture(nil, "OVERLAY")
	entry.item.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	entry.item.tex:SetDrawLayer("ARTWORK")
	entry.item.tex:SetTexture(nil)
	entry.item.tex:SetPoint("TOPLEFT", entry.item, "TOPLEFT", 2, -2)
	entry.item.tex:SetPoint("BOTTOMRIGHT", entry.item, "BOTTOMRIGHT", -2, 2)

	entry.ilvl = entry:CreateFontString(nil, "OVERLAY", "dynt_normal_text")
	entry.ilvl:SetText("0")
	entry.ilvl:SetTextColor(1, 1, 1)
	entry.ilvl:SetPoint("LEFT", entry, "LEFT", 50, 0)

	entry.name = entry:CreateFontString(nil, "OVERLAY", "dynt_normal_text")
	entry.name:SetText("test")
	entry.name:SetTextColor(1, 1, 1)
	entry.name:SetPoint("LEFT", entry, "LEFT", 90, 0)

	---@type Frame
	entry.looterEq1 = CreateFrame("Button", nil, entry, "BackdropTemplate")
	entry.looterEq1:SetSize(20,20)
	--entry.looterEq1:Hide()
	entry.looterEq1:SetPoint("LEFT", entry, "LEFT", 181, 0)
    entry.looterEq1:RegisterForClicks("LeftButtonDown","RightButtonUp")
	skinBackdrop(entry.looterEq1, 0, 0, 0, 1)

	entry.looterEq1.tex = entry.looterEq1:CreateTexture(nil, "OVERLAY")
	entry.looterEq1.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	entry.looterEq1.tex:SetDrawLayer("ARTWORK")
	entry.looterEq1.tex:SetTexture(134400)
	entry.looterEq1.tex:SetPoint("TOPLEFT", entry.looterEq1, "TOPLEFT", 2, -2)
	entry.looterEq1.tex:SetPoint("BOTTOMRIGHT", entry.looterEq1, "BOTTOMRIGHT", -2, 2)

	---@type Frame
	entry.looterEq2 = CreateFrame("Button", nil, entry, "BackdropTemplate")
	entry.looterEq2:SetSize(20,20)
	entry.looterEq2:Hide()
	entry.looterEq2:SetPoint("LEFT", entry, "LEFT", 203, 0)
    entry.looterEq2:RegisterForClicks("LeftButtonDown","RightButtonUp")
	skinBackdrop(entry.looterEq2, 0, 0, 0, 1)

	entry.looterEq2.tex = entry.looterEq2:CreateTexture(nil, "OVERLAY")
	entry.looterEq2.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	entry.looterEq2.tex:SetDrawLayer("ARTWORK")
	entry.looterEq2.tex:SetTexture(nil)
	entry.looterEq2.tex:SetPoint("TOPLEFT", entry.looterEq2, "TOPLEFT", 2, -2)
	entry.looterEq2.tex:SetPoint("BOTTOMRIGHT", entry.looterEq2, "BOTTOMRIGHT", -2, 2)

	---@type Button
	entry.whisper = CreateFrame("Button", nil, entry, "BackdropTemplate")
	entry.whisper:SetSize(45,20)
	entry.whisper:SetPoint("RIGHT", entry, "RIGHT", -30, 0)
	entry.whisper:SetText(L["Whisper"])
	skinButton(entry.whisper, true, "blue")
	entry.whisper:SetScript("OnClick", function() 
		AddOn:SendWhisper(entry.itemLink, entry.looter)
		entry.whisper:Hide()
	end)
	entry.whisper:Hide()

	---@type Button
	entry.delete = CreateFrame("Button", nil, entry, "BackdropTemplate")
	entry.delete:SetSize(25, 20)
	entry.delete:SetPoint("RIGHT", entry, "RIGHT", -7, 0)
	entry.delete:SetText("x")
	skinButton(entry.delete, true, "red")
	entry.delete:SetScript("OnClick", function()
		entry.itemLink = nil
		entry.looter = nil
		entry:Hide()
		-- Re order
		AddOn:repositionFrames()
	end)

	lastframe = entry
	AddOn.Entries[i] = entry
end

--- Options GUI
function AddOn.createOptionsFrame()
    local options = CreateFrame("Frame")
    options.name = "DoYouNeedThat"

    -- Debug toggle
    ---@type CheckButton
    options.debug = CreateFrame("CheckButton", "DYNT_Options_Debug", options, "ChatConfigCheckButtonTemplate")
    options.debug:SetPoint("TOPLEFT", options, "TOPLEFT", 12, -20)
    DYNT_Options_DebugText:SetText(L["Debug"])
    if AddOn.Config.debug then options.debug:SetChecked(true) end
    options.debug:SetScript("OnClick", function(self)
        AddOn.Config.debug = self:GetChecked()
    end)


    -- Open after boss kill toggle
    ---@type CheckButton
    options.openAfterEncounter = CreateFrame("CheckButton", "DYNT_Options_OpenAfterEncounter", options, "ChatConfigCheckButtonTemplate")
    options.openAfterEncounter:SetPoint("TOPLEFT", options, "TOPLEFT", 12, -40)
    DYNT_Options_OpenAfterEncounterText:SetText(L["Open loot window after encounter"])
    if AddOn.Config.openAfterEncounter then options.openAfterEncounter:SetChecked(true) end
    options.openAfterEncounter:SetScript("OnClick", function(self)
        AddOn.Config.openAfterEncounter = self:GetChecked()
    end)

    -- Whisper message
    --@type EditBox
    options.whisperMessage = CreateFrame("EditBox", "DYNT_Options_WhisperMessage", options, "InputBoxTemplate")
    options.whisperMessage:SetSize(200, 32)
    options.whisperMessage:SetPoint("TOPLEFT", options, "TOPLEFT", 22, -80)
    options.whisperMessage:SetAutoFocus(false)
    options.whisperMessage:SetMaxLetters(128)
    AddOn.Debug(AddOn.Config.whisperMessage)
    if AddOn.Config.whisperMessage then options.whisperMessage:SetText(AddOn.Config.whisperMessage) end
    options.whisperMessage:SetCursorPosition(0)
    options.whisperMessage:SetScript("OnEditFocusGained", function() --[[ Override to not highlight the text ]] end)
    options.whisperMessage:SetScript("OnEnterPressed", function(self)
        AddOn.Config.whisperMessage = self:GetText()
        self:ClearFocus()
    end)

    local whisperLabel = options.whisperMessage:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
    whisperLabel:SetPoint("BOTTOMLEFT", options.whisperMessage, "TOPLEFT", 0, 0)
    --whisperLabel:SetPoint("BOTTOMRIGHT", options.whisperMessage, "TOPRIGHT", -6, 0)
    whisperLabel:SetJustifyH("LEFT")
    options.whisperMessage.labelText = whisperLabel
    options.whisperMessage.labelText:SetTextColor(1, 1, 1)
    options.whisperMessage.labelText:SetShadowColor(0, 0, 0)
    options.whisperMessage.labelText:SetShadowOffset(1, -1)
    options.whisperMessage.labelText:SetText(L["Whisper Message"])

	-- Hide minimap button
	---@type CheckButton
	options.hideMinimap = CreateFrame("CheckButton", "DYNT_Options_HideMinimap", options, "ChatConfigCheckButtonTemplate")
	options.hideMinimap:SetPoint("TOPLEFT", options, "TOPLEFT", 12, -110)
	DYNT_Options_HideMinimapText:SetText(L["Hide minimap button"])
	if AddOn.db.minimap.hide then options.hideMinimap:SetChecked(true) end
    options.hideMinimap:SetScript("OnClick", function(self)
        AddOn.db.minimap.hide = self:GetChecked()
        if not self:GetChecked() then
            icon:Show("DoYouNeedThat")
        else
            icon:Hide("DoYouNeedThat")
        end
    end)

    options.minDelta = CreateFrame("Slider", "DYNT_Options_MinDelta", options, "OptionsSliderTemplate")
    options.minDelta:SetWidth(100)
    options.minDelta:SetHeight(20)
    options.minDelta:SetPoint("TOPLEFT", 22, -170)
    options.minDelta:SetOrientation("HORIZONTAL")
    options.minDelta:SetMinMaxValues(0, 30)
    options.minDelta:SetValue(AddOn.Config.minDelta)
    options.minDelta:SetValueStep(1)
    options.minDelta:SetObeyStepOnDrag(true)
    options.minDelta:SetScript("OnValueChanged", function (_, val)
        DYNT_Options_MinDeltaText:SetText(val)
        AddOn.Config.minDelta = val
    end)
    options.tooltipText = L["Minimum itemlevel allowed"]
    DYNT_Options_MinDeltaLow:SetText("0")
    DYNT_Options_MinDeltaHigh:SetText("30")
    DYNT_Options_MinDeltaText:SetText(AddOn.Config.minDelta)
    options.minDelta:Show()

    local minDeltaLabel = options.minDelta:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
    minDeltaLabel:SetPoint("BOTTOMLEFT", options.minDelta, "TOPLEFT", 0, 20)
    minDeltaLabel:SetJustifyH("LEFT")
    options.minDelta.labelText = minDeltaLabel
    options.minDelta.labelText:SetTextColor(1, 1, 1)
    options.minDelta.labelText:SetShadowColor(0, 0, 0)
    options.minDelta.labelText:SetShadowOffset(1, -1)
    options.minDelta.labelText:SetText(L["Minimum itemlevels lower"])

    local category = Settings.RegisterCanvasLayoutCategory(options, "DoYouNeedThat")
    Settings.RegisterAddOnCategory(category)
end