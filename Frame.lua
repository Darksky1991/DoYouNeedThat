local AddonName, AddOn = ...
local CreateFrame, unpack = CreateFrame, unpack

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

local normal_button_text = CreateFont("dynt_button")
normal_button_text:SetFont("Fonts\\ARIALN.TTF", 13)
normal_button_text:SetTextColor(1,1,1,1)
normal_button_text:SetShadowColor(0, 0, 0)
normal_button_text:SetShadowOffset(1, -1)
normal_button_text:SetJustifyH("CENTER")

local large_font = CreateFont("dynt_large_text")
large_font:SetFont("Fonts\\ARIALN.TTF", 14)
large_font:SetShadowColor(0, 0, 0)
large_font:SetShadowOffset(1, -1)

-- Window
AddOn.lootFrame = CreateFrame('frame', 'DYNT', UIParent)
skinBackdrop(AddOn.lootFrame, .1,.1,.1,.8);
AddOn.lootFrame:EnableMouse(true)
AddOn.lootFrame:SetMovable(true)
AddOn.lootFrame:SetUserPlaced(true)
AddOn.lootFrame:SetFrameStrata("DIALOG")
AddOn.lootFrame:SetFrameLevel(1)
AddOn.lootFrame:SetClampedToScreen(true)
AddOn.lootFrame:SetSize(600, 400)
AddOn.lootFrame:SetPoint("CENTER")
AddOn.lootFrame:Hide()

-- Header
AddOn.lootFrame.header = CreateFrame('frame', nil, AddOn.lootFrame)
AddOn.lootFrame.header:EnableMouse(true)
AddOn.lootFrame.header:RegisterForDrag('LeftButton','RightButton')
AddOn.lootFrame.header:SetScript("OnDragStart", function(self) AddOn.lootFrame:StartMoving() end)
AddOn.lootFrame.header:SetScript("OnDragStop", function(self) AddOn.lootFrame:StopMovingOrSizing() end)
AddOn.lootFrame.header:SetPoint("TOPLEFT", AddOn.lootFrame, "TOPLEFT")
AddOn.lootFrame.header:SetPoint("BOTTOMRIGHT", AddOn.lootFrame, "TOPRIGHT", 0, -24)
skinBackdrop(AddOn.lootFrame.header,.1,.1,.1,1)

AddOn.lootFrame.header.close = CreateFrame("Button", nil, AddOn.lootFrame.header)
AddOn.lootFrame.header.close:SetPoint("RIGHT", AddOn.lootFrame.header, "RIGHT", -4, 0)
AddOn.lootFrame.header.close:SetText("x")
skinButton(AddOn.lootFrame.header.close, true, "red")
AddOn.lootFrame.header.close:SetScript("OnClick", function() AddOn.lootFrame:Hide() end)

AddOn.lootFrame.header.text = AddOn.lootFrame.header:CreateFontString(nil, "OVERLAY", "dynt_large_text")
AddOn.lootFrame.header.text:SetText("|cFFFF6B6BDoYouNeedThat")
AddOn.lootFrame.header.text:SetPoint("CENTER", AddOn.lootFrame.header, "CENTER")

-- Vote table
local vote_table = CreateFrame("Frame", nil, AddOn.lootFrame)
vote_table:SetPoint("TOPLEFT", AddOn.lootFrame, "TOPLEFT", 10, -50)
vote_table:SetPoint("BOTTOMRIGHT", AddOn.lootFrame, "BOTTOMRIGHT", -30, 10)
skinBackdrop(vote_table, .1,.1,.1,.8)

local scrollframe = CreateFrame("ScrollFrame", nil, vote_table)
scrollframe:SetPoint("TOPLEFT", vote_table, "TOPLEFT", 0, -2)
scrollframe:SetPoint("BOTTOMRIGHT", vote_table, "BOTTOMRIGHT", 0, 2)
vote_table.scrollframe = scrollframe

local scrollbar = CreateFrame("Slider", nil, scrollframe, "UIPanelScrollBarTemplate")
scrollbar:SetPoint("TOPLEFT", vote_table, "TOPRIGHT", 6, -16) 
scrollbar:SetPoint("BOTTOMLEFT", vote_table, "BOTTOMRIGHT", 0, 16)
scrollbar:SetMinMaxValues(1, 200)
scrollbar:SetValueStep(1)
scrollbar.scrollStep = 1
scrollbar:SetValue(0)
scrollbar:SetWidth(16)
scrollbar:SetScript("OnValueChanged", function (self, value) self:GetParent():SetVerticalScroll(value) end) 
skinBackdrop(scrollbar, .1,.1,.1,.8)
vote_table.scrollbar = scrollbar

vote_table.content = CreateFrame("Frame", nil, scrollframe)
vote_table.content:SetSize(560, 340)
scrollframe:SetScrollChild(vote_table.content)

vote_table.name_text = vote_table:CreateFontString(nil, "OVERLAY", "dynt_button")
vote_table.name_text:SetText("Looter")
vote_table.name_text:SetTextColor(1, 1, 1)
vote_table.name_text:SetPoint("TOPLEFT", vote_table, "TOPLEFT", 10, 16)

vote_table.item_text = vote_table:CreateFontString(nil, "OVERLAY", "dynt_button")
vote_table.item_text:SetText("Item")
vote_table.item_text:SetTextColor(1, 1, 1)
vote_table.item_text:SetPoint("TOPLEFT", vote_table, "TOPLEFT", 80, 16)

vote_table.ilvl_text = vote_table:CreateFontString(nil, "OVERLAY", "dynt_button")
vote_table.ilvl_text:SetText("ilvl")
vote_table.ilvl_text:SetTextColor(1, 1, 1)
vote_table.ilvl_text:SetPoint("TOPLEFT", vote_table, "TOPLEFT", 150, 16)

vote_table.whisper_text = vote_table:CreateFontString(nil, "OVERLAY", "dynt_button")
vote_table.whisper_text:SetText("Whisper")
vote_table.whisper_text:SetTextColor(1, 1, 1)
vote_table.whisper_text:SetPoint("TOPLEFT", vote_table, "TOPLEFT", 220, 16)


-- Test entries
local lastframe = nil
for i = 1, 20 do
	local entry = CreateFrame("Button", nil, vote_table.content)
	entry:SetSize(vote_table.content:GetWidth(), 22)
	if (lastframe) then
		entry:SetPoint("TOPLEFT", lastframe, "BOTTOMLEFT", 0, 2)
	else
		entry:SetPoint("TOPLEFT", vote_table.content, "TOPLEFT", 0, -3)
	end
	skinBackdrop(entry, 1,1,1,.1)
	entry:Hide()

	entry.name = entry:CreateFontString(nil, "OVERLAY", "dynt_button")
	entry.name:SetText("test")
	entry.name:SetTextColor(1, 1, 1)
	entry.name:SetPoint("LEFT", entry, "LEFT", 10, 0)

	entry.item = CreateFrame("frame", nil, entry)
	entry.item:SetSize(20,20)
	--entry.item:Hide();
	entry.item:SetPoint("LEFT", entry, "LEFT", 80, 0)
	skinBackdrop(entry.item, 0, 0, 0, 1)

	entry.item.tex = entry.item:CreateTexture(nil, "OVERLAY")
	entry.item.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	entry.item.tex:SetDrawLayer("ARTWORK")
	entry.item.tex:SetTexture(nil)
	entry.item.tex:SetPoint("TOPLEFT", entry.item, "TOPLEFT", 2, -2)
	entry.item.tex:SetPoint("BOTTOMRIGHT", entry.item, "BOTTOMRIGHT", -2, 2)

	entry.ilvl = entry:CreateFontString(nil, "OVERLAY", "dynt_button")
	entry.ilvl:SetText("123")
	entry.ilvl:SetTextColor(1, 1, 1)
	entry.ilvl:SetPoint("LEFT", entry, "LEFT", 150, 0)

	entry.whisper = CreateFrame("Button", nil, entry)
	entry.whisper:SetSize(45,20)
	entry.whisper:SetPoint("LEFT", entry, "LEFT", 220, 0)
	entry.whisper:SetText("Whisper")
	skinButton(entry.whisper, true, "blue")
	entry.whisper:SetScript("OnClick", function() 
		AddOn.SendWhisper(entry.itemLink, entry.looter)
		entry.whisper:Hide()
	end)

	entry.delete = CreateFrame("Button", nil, entry)
	entry.delete:SetSize(25, 20)
	entry.delete:SetPoint("RIGHT", entry, "RIGHT", -7, 0)
	entry.delete:SetText("x")
	skinButton(entry.delete, true, "red")
	entry.delete:SetScript("OnClick", function()
		entry:Hide()
	end)

	lastframe = entry
	AddOn.Entries[i] = entry
end