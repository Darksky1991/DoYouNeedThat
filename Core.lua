local AddonName, AddOn = ...

-- Localize
local print, gsub, sfind = print, string.gsub, string.find
local GetItemInfo, IsEquippableItem = C_Item.GetItemInfo, C_Item.IsEquippableItem
local GetInventoryItemLink, UnitClass = GetInventoryItemLink, UnitClass
local SendChatMessage, UIParent = C_ChatInfo.SendChatMessage, UIParent
local select, IsInGroup, GetItemInfoInstant = select, IsInGroup, C_Item.GetItemInfoInstant
local UnitGUID, IsInRaid, GetNumGroupMembers, GetInstanceInfo = UnitGUID, IsInRaid, GetNumGroupMembers, GetInstanceInfo
local C_Timer, InCombatLockdown, time = C_Timer, InCombatLockdown, time
local UnitIsConnected, CanInspect, UnitName = UnitIsConnected, CanInspect, UnitName
local CheckInteractDistance, UnitIsVisible, UnitExists = CheckInteractDistance, UnitIsVisible, UnitExists
local ClearInspectPlayer, issecretvalue = ClearInspectPlayer, issecretvalue
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local CreateFrame, GetDetailedItemLevelInfo = CreateFrame, C_Item.GetDetailedItemLevelInfo

local L = AddOn.L
local LOOT_ITEM_PATTERN = gsub(LOOT_ITEM, '%%s', '(.+)')
local LibInspect = LibStub("LibInspect")
local _, _, playerClassId = UnitClass("player")
local icon = LibStub("LibDBIcon-1.0")
local LDB = LibStub("LibDataBroker-1.1"):NewDataObject("DoYouNeedThat", {
    type = "data source",
    text = "DoYouNeedThat",
    icon = "Interface\\Icons\\inv_misc_bag_17",
    OnClick = function(_,buttonPressed)
        if buttonPressed == "RightButton" then
            if AddOn.db.minimap.lock then
                icon:Unlock("DoYouNeedThat")
            else
                icon:Lock("DoYouNeedThat")
            end
        else
            AddOn:ToggleWindow()
        end
    end,
    OnTooltipShow = function(tooltip)
        if not tooltip or not tooltip.AddLine then return end
        tooltip:AddLine("DoYouNeedThat")
        tooltip:AddLine(L["Click to toggle window"])
        tooltip:AddLine(L["Right-click to lock Minimap Button"])
    end,
})

AddOn.EventFrame = CreateFrame("Frame", nil, UIParent)
AddOn.db = {}
AddOn.Entries = {}
AddOn.RaidMembers = {}
AddOn.Config = {}
AddOn.inspectCount = 1
AddOn.PendingLoot = {}
AddOn.InspectFailures = {}

local INSPECT_RETRY_DELAY = 10
local PENDING_LOOT_MAX_RETRIES = 5

function AddOn.Print(msg)
	print("[|cff3399FFDYNT|r] " .. msg)
end

function AddOn.Debug(msg)
	if AddOn.Config.debug then AddOn.Print(msg) end
end

local function ExtractItemLink(message)
	if not message then return nil end
	return message:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)") or message:match("(|cn.-:|Hitem:.-|h%[.-%]|h|r)")
end

local function IsItemInfoReady(item)
	if not item then return false end
	local _, _, rarity = GetItemInfo(item)
	local itemId = C_Item.GetItemInfoInstant(item)
	local iLvl = GetDetailedItemLevelInfo(item)
	return itemId ~= nil and rarity ~= nil and iLvl ~= nil
end

-- Loot can arrive before the item cache is populated. Keep one small queue and
-- retry from both GET_ITEM_INFO_RECEIVED and a short ticker so dropped events do
-- not silently lose eligible items.
function AddOn:QueuePendingLoot(item, looter, retries)
	if not item or not looter then return end
	local itemId = self.Utils.GetItemIDFromLink(item) or item
	self.PendingLoot[itemId] = {
		item = item,
		looter = looter,
		retries = retries or 0,
	}
	self.EventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	if not self.PendingLootTimer then
		self.PendingLootTimer = C_Timer.NewTicker(2, function() self:GET_ITEM_INFO_RECEIVED() end)
	end
	self.Debug("Queued loot until item info is cached: " .. item)
end

-- Loot flow: CHAT_MSG_LOOT/ENCOUNTER_LOOT_RECEIVED -> ProcessLootItem -> AddItemToLootTable.
-- Keep all eligibility checks here so real loot and slash-command tests behave the same.
function AddOn:ProcessLootItem(item, looter)
	if not item or not looter then return end
	if not IsItemInfoReady(item) then
		self:QueuePendingLoot(item, looter)
		return
	end

	local _, _, rarity, _, _, _, _, _, equipLoc, _, _, itemClass, itemSubClass = GetItemInfo(item)
	local itemId = C_Item.GetItemInfoInstant(item)

	if not IsEquippableItem(item) then
		self.Debug(L["Item is not equippable"])
		local specInfo = C_Item.GetItemSpecInfo and C_Item.GetItemSpecInfo(item)
		if rarity == 4
			and itemClass == 15
			and itemSubClass == 0
			and specInfo
			and next(specInfo) ~= nil then
			self.Debug(L["Item is fittable for player class"])
		else
			self.Debug(L["Item is not fittable for player class"])
			return
		end
	end

	if C_PlayerInfo and C_PlayerInfo.CanUseItem and not C_PlayerInfo.CanUseItem(itemId) then
		self.Debug(L["Item is not equippable by your class"])
		return
	end

	if rarity == 5 or rarity < 3 then return end

	if C_Item.DoesItemContainSpec and not C_Item.DoesItemContainSpec(item, playerClassId) then
		self.Debug(L["Item is not contain your class"])
		return
	end

	if C_Item.IsItemBindToAccountUntilEquip and C_Item.IsItemBindToAccountUntilEquip(item) then
		self.Debug(L["Item is Bind to Account until equip"])
		return
	end

	local iLvl = GetDetailedItemLevelInfo(item)

	self.Debug(item .. " " .. iLvl)

	if not self:IsItemUpgrade(iLvl, equipLoc) then
		self.Debug(L["Item is below itemlevel threshold"])
		return
	end

	if not sfind(looter, '-') then
		looter = self.Utils.GetUnitNameWithRealm(looter) or looter
	end
	self:AddItemToLootTable(item, looter, iLvl)
end

function AddOn:CHAT_MSG_LOOT(...)
	local message, _, _, _, looter = ...
	if not message then return end
	if issecretvalue and issecretvalue(message) then return end

	local parsedLooter, item = message:match(LOOT_ITEM_PATTERN)
	item = item or ExtractItemLink(message)
	looter = looter or parsedLooter

	self:ProcessLootItem(item, looter)
end

function AddOn:ENCOUNTER_LOOT_RECEIVED(...)
	local _, _, itemLink, _, playerName = ...
	local player = UnitName("player")
	local shortName = playerName and playerName:match("^([^%-]+)")
	if shortName == player then return end
	if itemLink and playerName then
		self:ProcessLootItem(itemLink, playerName)
	end
end

function AddOn:GET_ITEM_INFO_RECEIVED()
	local hasPending = false
	for itemId, pending in pairs(self.PendingLoot) do
		if IsItemInfoReady(pending.item) then
			self.PendingLoot[itemId] = nil
			self:ProcessLootItem(pending.item, pending.looter)
		elseif pending.retries >= PENDING_LOOT_MAX_RETRIES then
			self.PendingLoot[itemId] = nil
			self.Debug("Dropping pending loot after item info retries: " .. pending.item)
		else
			pending.retries = pending.retries + 1
			hasPending = true
		end
	end

	if not hasPending and not next(self.PendingLoot) then
		self.EventFrame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
		if self.PendingLootTimer then
			self.PendingLootTimer:Cancel()
			self.PendingLootTimer = nil
		end
	end
end

function AddOn:ShowLootFrame()
	self.lootFrame:Show()
	self.db.lootWindowOpen = true
end

function AddOn:BOSS_KILL()
    local _, _, difficulty = GetInstanceInfo()
	self:ClearEntries()
    -- Don't open if its M+
	if self.Config.openAfterEncounter and difficulty ~= 8 then self:ShowLootFrame() end
end

function AddOn:CHALLENGE_MODE_COMPLETED()
	self.Debug("Challenge mode completed, clearing entries")
	self:ClearEntries()
	self.Debug("Opening loot window")
	self:ShowLootFrame()
	self.Debug("Challenge mode completed event end")
end

function AddOn:StopInspectTimer()
	self.InspectEnabled = false
	if self.InspectTimer then
		self.InspectTimer:Cancel()
		self.InspectTimer = nil
	end
	if ClearInspectPlayer then
		ClearInspectPlayer()
	end
end

function AddOn:StartInspectTimer()
	self.InspectEnabled = true
	if not self.InspectTimer then
		self.InspectTimer = C_Timer.NewTicker(7, function() self:InspectGroup() end)
	end
	C_Timer.After(1, function()
		if self.InspectEnabled then
			self:InspectGroup()
		end
	end)
end

function AddOn:ClearGroupState()
	self.RaidMembers = {}
	self.InspectFailures = {}
	self.inspectCount = 1
end

function AddOn:ClearPendingLoot()
	self.PendingLoot = {}
	self.EventFrame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	if self.PendingLootTimer then
		self.PendingLootTimer:Cancel()
		self.PendingLootTimer = nil
	end
end

function AddOn:EnableInstanceEvents()
	self.EventFrame:RegisterEvent("CHAT_MSG_LOOT")
	self.EventFrame:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
	self.EventFrame:RegisterEvent("BOSS_KILL")
	self.EventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
	self.EventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
	self.EventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:StartInspectTimer()
end

function AddOn:DisableInstanceEvents()
	self.EventFrame:UnregisterEvent("CHAT_MSG_LOOT")
	self.EventFrame:UnregisterEvent("ENCOUNTER_LOOT_RECEIVED")
	self.EventFrame:UnregisterEvent("BOSS_KILL")
	self.EventFrame:UnregisterEvent("CHALLENGE_MODE_COMPLETED")
	self.EventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
	self.EventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self:StopInspectTimer()
	self:ClearGroupState()
	self:ClearPendingLoot()
end

function AddOn:PLAYER_ENTERING_WORLD()
	local _, instanceType = GetInstanceInfo()
	if instanceType == "none" then
		self.Debug("Not in instance, unregistering events")
		self:DisableInstanceEvents()
		return
	end
	self.Debug("In instance, registering events")
	self:EnableInstanceEvents()
end

function AddOn:GROUP_ROSTER_UPDATE()
	self:CleanUpGroupCache()
	self.inspectCount = 1
	self:StartInspectTimer()
end

function AddOn:PLAYER_REGEN_ENABLED()
	self:InspectGroup()
end

function AddOn:ADDON_LOADED(addon)
	if addon ~= AddonName then return end
	self.EventFrame:UnregisterEvent("ADDON_LOADED")

	-- Set SavedVariables defaults
	if DyntDB == nil then
		DyntDB = {
			lootWindow = {"CENTER", 0, 0},
			lootWindowOpen = false,
			config = {
				whisperMessage = L["Default Whisper Message"],
				openAfterEncounter = true,
				debug = false,
				minDelta = 0,
			},
            minimap = {
                hide = false
            }
		}
	end

	self.db = DyntDB

	-- Set minDelta default if its not a fresh install
	if not self.db.config.minDelta then
		self.db.config.minDelta = 0
	end

	-- Set window position
	self.lootFrame:SetPoint(self.db.lootWindow[1], self.db.lootWindow[2], self.db.lootWindow[3])
	-- Reopen window if left opened on uireload/exit
	if self.db.lootWindowOpen then self.lootFrame:Show() end

	-- Replace config with saved one
	self.Config = self.db.config

    icon:Register("DoYouNeedThat", LDB, self.db.minimap)
    if not self.db.minimap.hide then
        icon:Show("DoYouNeedThat")
    end

    self:CreateOptionsFrame()
end

local function GetEquippedIlvlBySlotID(slotID)
	local item = GetInventoryItemLink('player', slotID)
	local iLvl = GetDetailedItemLevelInfo(item or '')
	return iLvl
end

function AddOn:IsItemUpgrade(ilvl, equipLoc)
	local function overOrWithinMin(ilvl, eq, delta)
		if not ilvl then return false end
		if not eq then return true end
		return ilvl >= eq - delta
	end

	if ilvl ~= nil and equipLoc ~= nil and equipLoc ~= '' then
		local delta = self.Config.minDelta
		-- minDelta is an allowance below the currently equipped item level.
		-- Example: delta 5 shows items up to 5 ilvls below the matching slot.
		if equipLoc == 'INVTYPE_FINGER' then
			local eqIlvl1 = GetEquippedIlvlBySlotID(11)
			local eqIlvl2 = GetEquippedIlvlBySlotID(12)
			return overOrWithinMin(ilvl, eqIlvl1, delta) or overOrWithinMin(ilvl, eqIlvl2, delta)
		elseif equipLoc == 'INVTYPE_TRINKET' then
			local eqIlvl1 = GetEquippedIlvlBySlotID(13)
			local eqIlvl2 = GetEquippedIlvlBySlotID(14)
			return overOrWithinMin(ilvl, eqIlvl1, delta) or overOrWithinMin(ilvl, eqIlvl2, delta)
		elseif equipLoc == 'INVTYPE_WEAPON' then
			local eqIlvl1 = GetEquippedIlvlBySlotID(16)
			local eqIlvl2 = GetEquippedIlvlBySlotID(17)
			return overOrWithinMin(ilvl, eqIlvl1, delta) or overOrWithinMin(ilvl, eqIlvl2, delta)
		else
			local slotID = self.Utils.GetSlotID(equipLoc)
			if not slotID then return true end
			local eqIlvl = GetEquippedIlvlBySlotID(slotID)
			return overOrWithinMin(ilvl, eqIlvl, delta)
		end
	end
	return false
end

function AddOn:ClearEntries()
	self.Debug("Clearing entries start")
	for i = 1, #self.Entries do
		if self.Entries[i].itemLink then
			self.Entries[i]:Hide()
			self.Entries[i].itemLink = nil
			self.Entries[i].looter = nil
			self.Entries[i].guid = nil
		end
	end
	self.Debug("Clearing entries end")
end

function AddOn:AcquireEntry(itemLink, looter)
	for i = 1, #self.Entries do
		if self.Entries[i].itemLink == itemLink and self.Entries[i].looter == looter then
			return self.Entries[i]
		end

		if not self.Entries[i].itemLink then
			return self.Entries[i]
		end
	end
end

local function GetComparedItemsForEquipLoc(raidMember, equipLoc)
	if not raidMember then return nil, nil end
	if equipLoc == "INVTYPE_FINGER" then
		return raidMember.items[11], raidMember.items[12]
	elseif equipLoc == "INVTYPE_TRINKET" then
		return raidMember.items[13], raidMember.items[14]
	else
		local slotId = AddOn.Utils.GetSlotID(equipLoc)
		return slotId and raidMember.items[slotId], nil
	end
end

function AddOn:ApplyComparedItemsToEntry(entry, raidMember, equipLoc)
	entry.looterEq1:Hide()
	entry.looterEq2:Hide()
	local item, item2 = GetComparedItemsForEquipLoc(raidMember, equipLoc)
	if item ~= nil then self:SetItemTooltip(entry.looterEq1, item) end
	if item2 ~= nil then self:SetItemTooltip(entry.looterEq2, item2) end
end

function AddOn:AddItemToLootTable(itemLink, looter, itemLevel)
	self.Debug("Adding item to entries")
	local entry = self:AcquireEntry(itemLink, looter)
	if not entry then
		self.Debug("Loot table is full")
		return
	end
	local _, _, _, equipLoc = GetItemInfoInstant(itemLink)
	local character = looter:match("(.*)%-") or looter
	local classColor = RAID_CLASS_COLORS[select(2, UnitClass(character))] or { r = 1, g = 1, b = 1 }
	entry.itemLink = itemLink
	entry.looter = looter
	entry.guid = UnitGUID(character)

	self:ApplyComparedItemsToEntry(entry, self.RaidMembers[entry.guid], equipLoc)

	entry.name:SetText(character)
	entry.name:SetTextColor(classColor.r, classColor.g, classColor.b)
	self:SetItemTooltip(entry.item, itemLink)
	entry.ilvl:SetText(itemLevel)

	self:repositionFrames()

	entry.whisper:Show()
	entry:Show()
	if self.Config.openAfterEncounter then
		self:ShowLootFrame()
	end
end

function AddOn:RefreshEntriesForGUID(guid)
	local raidMember = self.RaidMembers[guid]
	if not raidMember then return end

	-- Inspect data may arrive after a loot row is already visible; refresh those
	-- rows in place instead of requiring the item to be added again.
	for i = 1, #self.Entries do
		local entry = self.Entries[i]
		if entry.guid == guid and entry.itemLink then
			local _, _, _, equipLoc = GetItemInfoInstant(entry.itemLink)
			self:ApplyComparedItemsToEntry(entry, raidMember, equipLoc)
		end
	end
end

function AddOn:SendWhisper(itemLink, looter)
	-- Replace [item] with itemLink if supplied
	local message = self.Config.whisperMessage:gsub("%[item%]", itemLink)
	SendChatMessage(message, "WHISPER", nil, looter)
end

function AddOn:InspectPlayerUnit(unit)
	return LibInspect:RequestData("items", unit, false)
end

function AddOn:WarmInspectPlayer()
	self:InspectPlayerUnit("player")
end

-- Inspect is range/visibility/combat sensitive. Failed attempts are treated as
-- temporary backoff only; stale but usable cached gear is replaced on success,
-- not cleared on failure.
function AddOn:InspectPlayer(unit)
	if not UnitExists(unit) then
		return false
	end

	local guid = UnitGUID(unit)
	local now = time()
	local failure = guid and self.InspectFailures[guid]
	if failure and failure.nextTry and failure.nextTry > now then
		return false
	end

	local function delayRetry(reason)
		if guid then
			self.InspectFailures[guid] = {
				nextTry = now + INSPECT_RETRY_DELAY,
				reason = reason,
			}
		end
		self.Debug("Inspect delayed for " .. unit .. ": " .. reason)
		return false
	end

	if InCombatLockdown() then
		return delayRetry("in combat")
	end

	if not UnitIsConnected(unit) then
		return delayRetry("unit offline")
	end

	if UnitIsVisible and not UnitIsVisible(unit) then
		return delayRetry("unit not visible")
	end

	if CheckInteractDistance and not CheckInteractDistance(unit, 1) then
		return delayRetry("unit out of inspect range")
	end

	if not CanInspect(unit) then
		return delayRetry("cannot inspect unit")
	end

	local canInspect, unitFound = self:InspectPlayerUnit(unit)
	if not canInspect or not unitFound then
		delayRetry("inspect request not accepted")
		return false
	end
	return true
end

function AddOn:CleanUpGroupCache()
	local active = {}
	local isInRaid = IsInRaid()
	local max = isInRaid and GetNumGroupMembers() or (IsInGroup() and (GetNumGroupMembers() - 1) or 0)
	local unit = isInRaid and "raid" or "party"

	for i = 1, max do
		local guid = UnitGUID(unit..i)
		if guid then
			active[guid] = true
		end
	end

	for guid in pairs(self.RaidMembers) do
		if not active[guid] then
			self.RaidMembers[guid] = nil
		end
	end

	for guid in pairs(self.InspectFailures) do
		if not active[guid] then
			self.InspectFailures[guid] = nil
		end
	end
end

function AddOn:InspectGroup()
	if not self.InspectEnabled then return end
	local isInRaid = IsInRaid()
	if not isInRaid and not IsInGroup() or InCombatLockdown() then return end
	local max = isInRaid and GetNumGroupMembers() or (GetNumGroupMembers() - 1)
	if max <= 0 then return end
	local unit = isInRaid and "raid" or "party"
	local i = self.inspectCount
	local curTime = time()

	if i > max then
		i = 1
	end

	while i <= max do
		local guid = UnitGUID(unit..i)
		-- Temporary inspect failures only delay future attempts. Existing cached
		-- gear stays available until a successful inspect replaces it.
		if (self.RaidMembers[guid] == nil or self.RaidMembers[guid].maxAge <= curTime) and self:InspectPlayer(unit..i) then
			break
		end
		i = i + 1
	end

	i = i + 1
	if i > max then
		i = 1
	end
	self.inspectCount = i
end

function AddOn:ToggleWindow()
    if not self.db.lootWindowOpen then
        self.lootFrame:Show()
        self.db.lootWindowOpen = true
    else
        self.lootFrame:Hide()
        self.db.lootWindowOpen = false
    end
end

LibInspect:SetMaxAge(599)
LibInspect:AddHook(AddonName, "items", function(guid, data)
	if data then
		AddOn.InspectFailures[guid] = nil
		AddOn.RaidMembers[guid] = {
			items = data.items,
			maxAge = time() + 600
		}
		AddOn:RefreshEntriesForGUID(guid)
		if ClearInspectPlayer then
			ClearInspectPlayer()
		end
	end
end)

-- Event handler
AddOn.EventFrame:SetScript("OnEvent", function(self, event, ...)
	AddOn.Debug(event .. " event fired")
	if AddOn[event] then
		AddOn[event](AddOn, ...)
	else
		AddOn.Debug("No event handler for " .. event)
	end
end)

AddOn.EventFrame:RegisterEvent("ADDON_LOADED")
AddOn.EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

function AddOn:PrintHelp()
	self.Print(L["Commands:"])
	self.Print("/dynt - " .. L["Toggle Window"])
	self.Print("/dynt help - " .. L["Show command help"])
	self.Print("/dynt clear - " .. L["Clear loot list"])
	self.Print("/dynt test [itemLink] - " .. L["Add test item"])
	self.Print("/dynt testmsg [itemLink] - " .. L["Simulate loot message"])
	self.Print("/dynt debug - " .. L["Toggle debug output"])
end

local function SlashCommandHandler(msg)
	local _, _, cmd, args = sfind(msg, "%s?(%w+)%s?(.*)")
	if cmd == "help" then
		AddOn:PrintHelp()
	elseif cmd == "clear" then
		AddOn:ClearEntries()
	elseif cmd == "test" and args ~= "" then
		local player = UnitName("player")
		AddOn:WarmInspectPlayer()
		AddOn:ProcessLootItem(args, player)
	elseif cmd == "testmsg" and args ~= "" then
		local player = UnitName("player")
		AddOn:WarmInspectPlayer()
		local msg = gsub(LOOT_ITEM, '%%s', player, 1)
		msg = gsub(msg, '%%s', args, 1)
		AddOn:CHAT_MSG_LOOT(msg, nil, nil, nil, player);
	elseif cmd == "debug" then
		AddOn.Config.debug = not AddOn.Config.debug
		AddOn.Print("Debug mode " .. (AddOn.Config.debug and "enabled" or "disabled"))
	else
        AddOn:ToggleWindow()
	end
end

SLASH_DYNT1 = "/dynt"
SLASH_DYNT2 = "/doyouneedthat"
SlashCmdList["DYNT"] = SlashCommandHandler

-- Bindings
BINDING_HEADER_DOYOUNEEDTHAT = "DoYouNeedThat"
BINDING_NAME_DYNT_TOGGLE = L["Toggle Window"]
