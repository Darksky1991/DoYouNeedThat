local AddonName, AddOn = ...

-- Localize
local print, gsub, sfind, strlower, format = print, string.gsub, string.find, string.lower, string.format
local GetItemInfo, IsEquippableItem = C_Item.GetItemInfo, C_Item.IsEquippableItem
local GetInventoryItemLink, UnitClass = GetInventoryItemLink, UnitClass
local SendChatMessage, InChatMessagingLockdown = C_ChatInfo.SendChatMessage, C_ChatInfo.InChatMessagingLockdown
local UIParent = UIParent
local select, IsInGroup, GetItemInfoInstant = select, IsInGroup, C_Item.GetItemInfoInstant
local UnitGUID, IsInRaid, GetNumGroupMembers, GetInstanceInfo = UnitGUID, IsInRaid, GetNumGroupMembers, GetInstanceInfo
local C_Timer = C_Timer
local GetTime = GetTime
local UnitName = UnitName
local issecretvalue = issecretvalue
local GetRealmName = GetRealmName
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local CreateFrame, GetDetailedItemLevelInfo = CreateFrame, C_Item.GetDetailedItemLevelInfo
local C_TooltipInfo = C_TooltipInfo

local L = AddOn.L
local LOOT_ITEM_PATTERN = gsub(LOOT_ITEM, '%%s', '(.+)')
local DyntInspect = LibStub("DyntInspect")
local _, _, playerClassId = UnitClass("player")
local icon = LibStub("LibDBIcon-1.0")
local LDB = LibStub("LibDataBroker-1.1"):NewDataObject("DoYouNeedThat", {
    type = "data source",
    text = "DoYouNeedThat",
    icon = "Interface\\AddOns\\DoYouNeedThat\\Media\\dynt.png",
    OnClick = function(_,buttonPressed)
        if buttonPressed == "RightButton" then
            if AddOn.db.minimap.lock then
                icon:Unlock("DoYouNeedThat")
            else
                icon:Lock("DoYouNeedThat")
            end
        elseif buttonPressed == "MiddleButton" then
            AddOn:OpenOptions()
        else
            AddOn:ToggleWindow()
        end
    end,
    OnTooltipShow = function(tooltip)
        if not tooltip or not tooltip.AddLine then return end
        tooltip:AddLine("DoYouNeedThat")
        tooltip:AddLine(L["Click to toggle window"])
        tooltip:AddLine(L["Right-click to lock Minimap Button"])
        tooltip:AddLine(L["Middle-click to open options"])
    end,
})

AddOn.EventFrame = CreateFrame("Frame", nil, UIParent)
AddOn.db = {}
AddOn.Entries = {}
AddOn.RaidMembers = {}
AddOn.Config = {}
AddOn.PendingLoot = {}

local PENDING_LOOT_MAX_RETRIES = 5
local TEST_LOOTER = "DYNT-Test"

function AddOn.Print(msg)
	print("[|cff3399FFDYNT|r] " .. msg)
end

function AddOn.Debug(msg, ...)
	if not AddOn.Config.debug then return end
	if select("#", ...) > 0 then
		msg = format(msg, ...)
	end
	AddOn.Print(msg)
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

local function NormalizePlayerName(name)
	if not name then return nil end
	return strlower(gsub(name, "%s+", ""))
end

local function GetItemIdentity(item)
	if not item then return nil end
	return item:match("|H(item:[^|]+)|h")
		or item:match("(item:[^|]+)")
		or tostring(C_Item.GetItemInfoInstant(item) or item)
end

function AddOn:GetLooterIdentity(looter)
	if not looter then return nil end
	local unit = self:GetUnitForLooter(looter)
	local resolvedName = unit and self.Utils and self.Utils.GetUnitNameWithRealm
		and self.Utils.GetUnitNameWithRealm(unit)
	local normalized = NormalizePlayerName(resolvedName or looter)
	if normalized and not sfind(normalized, "-", 1, true) then
		local realm = GetRealmName and GetRealmName()
		if realm and realm ~= "" then
			normalized = normalized .. "-" .. NormalizePlayerName(realm)
		end
	end
	return normalized
end

function AddOn:GetLootKey(item, looter)
	local itemIdentity = GetItemIdentity(item)
	local looterIdentity = self:GetLooterIdentity(looter)
	if not itemIdentity or not looterIdentity then return nil end
	return itemIdentity .. "\031" .. looterIdentity
end

-- Loot can arrive before the item cache is populated. Keep one small queue and
-- retry from both GET_ITEM_INFO_RECEIVED and a short ticker so dropped events do
-- not silently lose eligible items.
function AddOn:QueuePendingLoot(item, looter, retries)
	if not item or not looter then return end
	local lootKey = self:GetLootKey(item, looter)
	if not lootKey then return end
	self.PendingLoot[lootKey] = {
		item = item,
		looter = looter,
		retries = retries or 0,
	}
	self.EventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	if not self.PendingLootTimer then
		self.PendingLootTimer = C_Timer.NewTicker(2, function() self:GET_ITEM_INFO_RECEIVED() end)
	end
	self.Debug(L["Loot queued: item=%s looter=%s"], item, looter)
end

function AddOn:IsPlayerLooter(looter)
	if not looter then return false end

	local playerName = UnitName("player")
	if not playerName then return false end

	local normalizedLooter = NormalizePlayerName(looter)
	local normalizedPlayer = NormalizePlayerName(playerName)
	if normalizedLooter == normalizedPlayer then return true end

	local playerFullName = self.Utils and self.Utils.GetUnitNameWithRealm and self.Utils.GetUnitNameWithRealm("player")
	if not playerFullName then
		local realm = GetRealmName and GetRealmName()
		if realm and realm ~= "" then
			playerFullName = playerName .. "-" .. realm
		end
	end

	return normalizedLooter == NormalizePlayerName(playerFullName)
end

function AddOn:GetUnitForLooter(looter)
	if not looter then return nil end
	local target = NormalizePlayerName(looter)
	local isInRaid = IsInRaid()
	local unitPrefix = isInRaid and "raid" or "party"
	local max = isInRaid and GetNumGroupMembers() or (IsInGroup() and (GetNumGroupMembers() - 1) or 0)

	for i = 1, max do
		local unit = unitPrefix .. i
		local name, realm = UnitName(unit)
		if name then
			local fullName = name
			if realm and realm ~= "" then
				fullName = name .. "-" .. realm
			else
				local currentRealm = GetRealmName and GetRealmName()
				if currentRealm and currentRealm ~= "" then
					fullName = name .. "-" .. currentRealm
				end
			end
			if target == NormalizePlayerName(name) or target == NormalizePlayerName(fullName) then
				return unit
			end
		end
	end
	return nil
end

-- Loot flow: CHAT_MSG_LOOT/ENCOUNTER_LOOT_RECEIVED -> ProcessLootItem -> AddItemToLootTable.
-- Keep all eligibility checks here so real loot and slash-command tests behave the same.
function AddOn:ProcessLootItem(item, looter)
	if not item or not looter then
		self.Debug(L["Loot skipped: missing item or looter item=%s looter=%s"], tostring(item), tostring(looter))
		return
	end
	if self:IsPlayerLooter(looter) then
		self.Debug(L["Loot skipped: player looted item=%s looter=%s"], item, looter)
		return
	end
	if not IsItemInfoReady(item) then
		self:QueuePendingLoot(item, looter)
		return
	end

	local _, _, rarity, _, _, _, _, _, equipLoc, _, _, itemClass, itemSubClass = GetItemInfo(item)
	local itemId = C_Item.GetItemInfoInstant(item)

	if not IsEquippableItem(item) then
		local specInfo = C_Item.GetItemSpecInfo and C_Item.GetItemSpecInfo(item)
		if rarity == 4
			and itemClass == 15
			and itemSubClass == 0
			and specInfo
			and next(specInfo) ~= nil then
			self.Debug(L["Loot allowed: class token item=%s looter=%s"], item, looter)
		else
			self.Debug(L["Loot skipped: not equippable item=%s looter=%s"], item, looter)
			return
		end
	end

	if C_PlayerInfo and C_PlayerInfo.CanUseItem and not C_PlayerInfo.CanUseItem(itemId) then
		self.Debug(L["Loot skipped: unusable by player class item=%s looter=%s"], item, looter)
		return
	end

	if rarity == 5 or rarity < 3 then
		self.Debug(L["Loot skipped: rarity item=%s looter=%s rarity=%s"], item, looter, tostring(rarity))
		return
	end

	if C_Item.DoesItemContainSpec and not C_Item.DoesItemContainSpec(item, playerClassId) then
		self.Debug(L["Loot skipped: spec mismatch item=%s looter=%s"], item, looter)
		return
	end

	if C_Item.IsItemBindToAccountUntilEquip and C_Item.IsItemBindToAccountUntilEquip(item) then
		self.Debug(L["Loot skipped: warband bound item=%s looter=%s"], item, looter)
		return
	end

	local iLvl = GetDetailedItemLevelInfo(item)

	if not self:IsItemUpgrade(iLvl, equipLoc) then
		self.Debug(L["Loot skipped: item level item=%s looter=%s ilvl=%s equipLoc=%s minDelta=%s"], item, looter, tostring(iLvl), tostring(equipLoc), tostring(self.Config.minDelta))
		return
	end

	if not sfind(looter, '-') then
		looter = self.Utils.GetUnitNameWithRealm(looter) or looter
	end
	self.Debug(L["Loot accepted: item=%s looter=%s ilvl=%s equipLoc=%s"], item, looter, tostring(iLvl), tostring(equipLoc))
	self:AddItemToLootTable(item, looter, iLvl)
end

function AddOn:CHAT_MSG_LOOT(...)
	local message, _, _, _, looter = ...
	if not message then return end
	if issecretvalue and issecretvalue(message) then return end

	local parsedLooter, item = message:match(LOOT_ITEM_PATTERN)
	item = item or ExtractItemLink(message)
	if not looter or looter == "" then looter = parsedLooter end

	self:ProcessLootItem(item, looter)
end

function AddOn:ENCOUNTER_LOOT_RECEIVED(...)
	-- ENCOUNTER_LOOT_RECEIVED can arrive while group loot is still being
	-- resolved. CHAT_MSG_LOOT is the authoritative source once a recipient is
	-- known, so this event intentionally never creates a row.
end

function AddOn:GET_ITEM_INFO_RECEIVED()
	local hasPending = false
	for itemId, pending in pairs(self.PendingLoot) do
		if IsItemInfoReady(pending.item) then
			self.PendingLoot[itemId] = nil
			self:ProcessLootItem(pending.item, pending.looter)
		elseif pending.retries >= PENDING_LOOT_MAX_RETRIES then
			self.PendingLoot[itemId] = nil
			self.Debug(L["Loot dropped: item info unavailable item=%s looter=%s retries=%s"], pending.item, pending.looter, tostring(pending.retries))
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
end

function AddOn:CHALLENGE_MODE_COMPLETED()
	self.Debug(L["Challenge mode completed"])
end

function AddOn:ClearGroupState()
	self.RaidMembers = {}
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
	self.EventFrame:RegisterEvent("BOSS_KILL")
	self.EventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
	self.EventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
	self.EventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	if DyntInspect.StartGroupScan then
		DyntInspect:StartGroupScan("entering_world")
	else
		DyntInspect:QueueGroup("entering_world", false, false)
	end
end

function AddOn:DisableInstanceEvents()
	self.EventFrame:UnregisterEvent("CHAT_MSG_LOOT")
	self.EventFrame:UnregisterEvent("BOSS_KILL")
	self.EventFrame:UnregisterEvent("CHALLENGE_MODE_COMPLETED")
	self.EventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
	self.EventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
	DyntInspect:Reset()
	self:ClearGroupState()
	self:ClearPendingLoot()
end

function AddOn:PLAYER_ENTERING_WORLD()
	local _, instanceType = GetInstanceInfo()
	if instanceType == "none" then
		self.Debug(L["Instance events disabled: instanceType=%s"], tostring(instanceType))
		self:DisableInstanceEvents()
		return
	end
	self.Debug(L["Instance events enabled: instanceType=%s"], tostring(instanceType))
	self:EnableInstanceEvents()
end

function AddOn:GROUP_ROSTER_UPDATE()
	DyntInspect:ClearGroupCache()
	self:CleanUpGroupCache()
	DyntInspect:QueueGroup("group_roster_update", false, false)
end

function AddOn:PLAYER_REGEN_ENABLED()
	DyntInspect:QueueGroup("regen_enabled", false, false)
end

function AddOn:OnInspectData(guid, data, reason)
	if data and data.items then
		self.RaidMembers[guid] = {
			items = data.items,
			maxAge = data.expiresAt,
			name = data.name,
			unit = data.unit,
			complete = data.complete,
			count = data.count,
		}
		self:RefreshEntriesForGUID(guid)
	elseif reason == "invalidated" then
		self.RaidMembers[guid] = nil
	end
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
				fontName = nil,
				ignoreLooterItemLevelUpgrades = false,
				ignoreLooterTrackUpgrades = false,
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
	if self.db.config.ignoreLooterItemLevelUpgrades == nil then
		self.db.config.ignoreLooterItemLevelUpgrades = false
	end
	if self.db.config.ignoreLooterTrackUpgrades == nil then
		self.db.config.ignoreLooterTrackUpgrades = false
	end

	-- Set window position
	self.lootFrame:SetPoint(self.db.lootWindow[1], self.db.lootWindow[2], self.db.lootWindow[3])
	-- Reopen window if left opened on uireload/exit
	if self.db.lootWindowOpen then self.lootFrame:Show() end

	-- Replace config with saved one
	self.Config = self.db.config
	if self.Config.fontName == "" then
		self.Config.fontName = nil
	end
	self:ApplyGlobalFont()

	DyntInspect:Configure({
		cacheMaxAge = 600,
		requestThrottle = 1.2,
		inspectTimeout = 2.5,
		retryDelay = 3,
		maxAttempts = 4,
		failureCooldown = 15,
		groupScanInterval = 10,
		minValidItemCount = 8,
	})
	DyntInspect:SetDebug(function(msg, ...)
		local args = {...}
		for i = 1, #args do
			if type(args[i]) == "string" and L[args[i]] then
				args[i] = L[args[i]]
			end
		end
		AddOn.Debug(L[msg] or msg, unpack(args))
	end)
	DyntInspect:RegisterCallback(AddonName, function(guid, data, reason)
		AddOn:OnInspectData(guid, data, reason)
	end)

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
	local cleared = 0
	for i = 1, #self.Entries do
		if self.Entries[i].itemLink then
			self.Entries[i]:Hide()
			self.Entries[i].itemLink = nil
			self.Entries[i].looter = nil
			self.Entries[i].guid = nil
			self.Entries[i].lootKey = nil
			cleared = cleared + 1
		end
	end
	self.Debug(L["Loot list cleared: count=%s"], tostring(cleared))
end

function AddOn:AcquireEntry(itemLink, looter)
	local lootKey = self:GetLootKey(itemLink, looter)
	local emptyEntry
	for i = 1, #self.Entries do
		local entry = self.Entries[i]
		local entryKey = entry.lootKey
		if not entryKey and entry.itemLink and entry.looter then
			entryKey = self:GetLootKey(entry.itemLink, entry.looter)
		end
		if lootKey and entryKey == lootKey then
			return entry
		end
		if not emptyEntry and not entry.itemLink then
			emptyEntry = entry
		end
	end
	return emptyEntry
end

function AddOn:RemoveEntry(entry)
	if not entry then return end
	entry.itemLink = nil
	entry.looter = nil
	entry.guid = nil
	entry.lootKey = nil
	entry:Hide()
	if self.repositionFrames then
		self:repositionFrames(false)
	end
end

local UPGRADE_TRACK_ALIASES = {
	["explorer"] = 1,
	["adventurer"] = 2,
	["veteran"] = 3,
	["champion"] = 4,
	["hero"] = 5,
	["myth"] = 6,
	["mythic"] = 6,
	["探索者"] = 1,
	["冒险者"] = 2,
	["老兵"] = 3,
	["勇士"] = 4,
	["英雄"] = 5,
	["神话"] = 6,
}

function AddOn:GetUpgradeTrackRank(itemLink)
	if not itemLink or not C_TooltipInfo or not C_TooltipInfo.GetHyperlink then return nil end
	local ok, tooltipData = pcall(C_TooltipInfo.GetHyperlink, itemLink)
	if not ok then return nil end
	if not tooltipData or not tooltipData.lines then return nil end
	for _, line in ipairs(tooltipData.lines) do
		local text = line.leftText
		if text and text:match("%d+%s*/%s*%d+") then
			text = strlower(gsub(gsub(text, "\194\160", " "), "\226\128\175", " "))
			for alias, rank in pairs(UPGRADE_TRACK_ALIASES) do
				if sfind(text, alias, 1, true) then return rank end
			end
		end
	end
	return nil
end

local function IsTwoHandEquipLoc(equipLoc)
	return equipLoc == "INVTYPE_2HWEAPON"
		or equipLoc == "INVTYPE_RANGED"
		or equipLoc == "INVTYPE_RANGEDRIGHT"
end

local function IsOffHandEquipLoc(equipLoc)
	return equipLoc == "INVTYPE_WEAPONOFFHAND"
		or equipLoc == "INVTYPE_SHIELD"
		or equipLoc == "INVTYPE_HOLDABLE"
end

local function IsOffHandWeapon(equipLoc)
	return equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONOFFHAND"
end

local function GetEquipLoc(itemLink)
	if not itemLink then return nil end
	local _, _, _, equipLoc = GetItemInfoInstant(itemLink)
	return equipLoc
end

local function GetRecipientComparison(itemEquipLoc, items)
	if not items then return nil end
	if itemEquipLoc == "INVTYPE_FINGER" then
		if not items[INVSLOT_FINGER1] or not items[INVSLOT_FINGER2] then return nil end
		return { items[INVSLOT_FINGER1], items[INVSLOT_FINGER2] }, "min"
	elseif itemEquipLoc == "INVTYPE_TRINKET" then
		if not items[INVSLOT_TRINKET1] or not items[INVSLOT_TRINKET2] then return nil end
		return { items[INVSLOT_TRINKET1], items[INVSLOT_TRINKET2] }, "min"
	end

	local mainHand, offHand = items[INVSLOT_MAINHAND], items[INVSLOT_OFFHAND]
	local mainEquipLoc = GetEquipLoc(mainHand)
	local offEquipLoc = GetEquipLoc(offHand)
	if IsTwoHandEquipLoc(itemEquipLoc) then
		if not mainHand or not mainEquipLoc then return nil end
		if IsTwoHandEquipLoc(mainEquipLoc) then return { mainHand }, "single" end
		if not offHand then return nil end
		return { mainHand, offHand }, "max"
	elseif itemEquipLoc == "INVTYPE_WEAPON" then
		if not mainHand or not mainEquipLoc or not offHand or not offEquipLoc or IsTwoHandEquipLoc(mainEquipLoc) then return nil end
		local comparable = { mainHand }
		if IsOffHandWeapon(offEquipLoc) then comparable[#comparable + 1] = offHand end
		return comparable, #comparable == 2 and "min" or "single"
	elseif itemEquipLoc == "INVTYPE_WEAPONMAINHAND" then
		if not mainHand or not mainEquipLoc or IsTwoHandEquipLoc(mainEquipLoc) then return nil end
		return { mainHand }, "single"
	elseif IsOffHandEquipLoc(itemEquipLoc) then
		if not mainHand or not mainEquipLoc or not offHand or IsTwoHandEquipLoc(mainEquipLoc) then return nil end
		return { offHand }, "single"
	end

	local slotId = AddOn.Utils.GetSlotID(itemEquipLoc)
	if not slotId or not items[slotId] then return nil end
	return { items[slotId] }, "single"
end

local function IsMetricHigher(itemLink, equippedLinks, reduction, metric)
	local dropped = metric(itemLink)
	if not dropped then return nil end
	local baseline
	for _, equippedLink in ipairs(equippedLinks) do
		local value = metric(equippedLink)
		if not value then return nil end
		if not baseline
			or (reduction == "min" and value < baseline)
			or (reduction == "max" and value > baseline) then
			baseline = value
		end
	end
	return baseline ~= nil and dropped > baseline or false
end

function AddOn:ShouldIgnoreLootForRecipient(itemLink, equipLoc, raidMember)
	if not raidMember or not raidMember.items then return false end
	local equippedLinks, reduction = GetRecipientComparison(equipLoc, raidMember.items)
	if not equippedLinks then return false end
	if self.Config.ignoreLooterItemLevelUpgrades then
		local higher = IsMetricHigher(itemLink, equippedLinks, reduction, GetDetailedItemLevelInfo)
		if higher then return true end
	end
	if self.Config.ignoreLooterTrackUpgrades then
		local higher = IsMetricHigher(itemLink, equippedLinks, reduction, function(link)
			return self:GetUpgradeTrackRank(link)
		end)
		if higher then return true end
	end
	return false
end

local function GetComparedSlotIdsForEquipLoc(equipLoc)
	if equipLoc == "INVTYPE_FINGER" then
		return { INVSLOT_FINGER1, INVSLOT_FINGER2 }
	elseif equipLoc == "INVTYPE_TRINKET" then
		return { INVSLOT_TRINKET1, INVSLOT_TRINKET2 }
	elseif equipLoc == "INVTYPE_WEAPON" or IsTwoHandEquipLoc(equipLoc) or IsOffHandEquipLoc(equipLoc) then
		return { INVSLOT_MAINHAND, INVSLOT_OFFHAND }
	end
	local slotId = AddOn.Utils.GetSlotID(equipLoc)
	return slotId and { slotId } or {}
end

local function GetComparedItemsForEquipLoc(raidMember, equipLoc)
	if not raidMember then return nil, nil end
	local slots = GetComparedSlotIdsForEquipLoc(equipLoc)
	return slots[1] and raidMember.items[slots[1]], slots[2] and raidMember.items[slots[2]]
end

local function HasRequiredEquipment(raidMember, requiredSlots)
	if not raidMember or not raidMember.items then return false end
	for _, slotId in ipairs(requiredSlots) do
		if raidMember.items[slotId] == nil then return false end
	end
	return #requiredSlots > 0
end

function AddOn:ApplyComparedItemsToEntry(entry, raidMember, equipLoc)
	entry.looterEq1:Hide()
	entry.looterEq2:Hide()
	local item, item2 = GetComparedItemsForEquipLoc(raidMember, equipLoc)
	if item ~= nil then self:SetItemTooltip(entry.looterEq1, item) end
	if item2 ~= nil then self:SetItemTooltip(entry.looterEq2, item2) end
end

function AddOn:AddItemToLootTable(itemLink, looter, itemLevel)
	local entry = self:AcquireEntry(itemLink, looter)
	if not entry then
		self.Debug(L["Loot skipped: table full item=%s looter=%s"], itemLink, looter)
		return
	end
	local _, _, _, equipLoc = GetItemInfoInstant(itemLink)
	local character = looter:match("(.*)%-") or looter
	local looterUnit = self:GetUnitForLooter(looter)
	local looterGuid = looterUnit and UnitGUID(looterUnit)
	local cached = looterGuid and DyntInspect:GetCached(looterGuid) or DyntInspect:GetCached(looter)
	local currentTime = GetTime and GetTime()
	if cached and currentTime and cached.expiresAt and cached.expiresAt <= currentTime then
		cached = nil
	end
	local raidMember = self.RaidMembers[looterGuid] or cached
	if raidMember and currentTime and raidMember.maxAge and raidMember.maxAge <= currentTime then
		if looterGuid then self.RaidMembers[looterGuid] = nil end
		raidMember = cached
	end
	local requiredSlots = GetComparedSlotIdsForEquipLoc(equipLoc)
	local classColor = RAID_CLASS_COLORS[select(2, UnitClass(character))] or { r = 1, g = 1, b = 1 }
	if self:ShouldIgnoreLootForRecipient(itemLink, equipLoc, raidMember) then
		if entry.itemLink then self:RemoveEntry(entry) end
		self.Debug(L["Loot skipped: recipient upgrade item=%s looter=%s"], itemLink, looter)
		return
	end
	entry.itemLink = itemLink
	entry.looter = looter
	entry.guid = looterGuid or (cached and cached.guid) or UnitGUID(character)
	entry.lootKey = self:GetLootKey(itemLink, looter)

	self:ApplyComparedItemsToEntry(entry, self.RaidMembers[entry.guid] or raidMember, equipLoc)

	entry.name:SetText(character)
	entry.name:SetTextColor(classColor.r, classColor.g, classColor.b)
	self:SetItemTooltip(entry.item, itemLink)
	entry.ilvl:SetText(itemLevel)

	self:repositionFrames()

	entry.whisper:Show()
	entry:Show()
	local inspectUnit = looterUnit or (cached and cached.unit)
	if inspectUnit then
		local force = not HasRequiredEquipment(raidMember, requiredSlots)
		DyntInspect:QueueUnit(inspectUnit, "loot", true, force, requiredSlots)
	end
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
		local sameName = not entry.guid and raidMember.name
			and self:GetLooterIdentity(entry.looter) == self:GetLooterIdentity(raidMember.name)
		if entry.itemLink and (entry.guid == guid or sameName) then
			entry.guid = guid
			local _, _, _, equipLoc = GetItemInfoInstant(entry.itemLink)
			if self:ShouldIgnoreLootForRecipient(entry.itemLink, equipLoc, raidMember) then
				self.Debug(L["Loot skipped after inspect: recipient upgrade item=%s looter=%s"], entry.itemLink, entry.looter)
				self:RemoveEntry(entry)
			else
				self:ApplyComparedItemsToEntry(entry, raidMember, equipLoc)
			end
		end
	end
end

function AddOn:SendWhisper(itemLink, looter)
	-- Replace [item] with itemLink if supplied
	local message = self.Config.whisperMessage:gsub("%[item%]", itemLink)
	if InChatMessagingLockdown and InChatMessagingLockdown() then
		self.Print(L["Whisper failed: chat messaging is restricted"])
		return false
	end
	local ok, err = pcall(SendChatMessage, message, "WHISPER", nil, looter)
	if not ok then
		self.Print(format(L["Whisper failed: %s"], tostring(err)))
		return false
	end
	return true
end

function AddOn:HandleWhisperClick(entry)
	if not entry or not entry.itemLink or not entry.looter then return false end
	if not self:SendWhisper(entry.itemLink, entry.looter) then return false end
	entry.whisper:Hide()
	return true
end

function AddOn:CleanUpGroupCache()
	local active = {}
	local removedMembers = 0
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
			removedMembers = removedMembers + 1
		end
	end

	if removedMembers > 0 then
		self.Debug(L["Inspect cache cleaned: members=%s failures=%s"], tostring(removedMembers), "0")
	end
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

function AddOn:OpenOptions()
	if Settings and Settings.OpenToCategory and self.settingsCategory then
		Settings.OpenToCategory(self.settingsCategory.ID or self.settingsCategory)
	end
end

-- Event handler
AddOn.EventFrame:SetScript("OnEvent", function(self, event, ...)
	if AddOn[event] then
		AddOn[event](AddOn, ...)
	else
		AddOn.Debug(L["Event ignored: no handler event=%s"], event)
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
		AddOn:ProcessLootItem(args, TEST_LOOTER)
	elseif cmd == "testmsg" and args ~= "" then
		local msg = gsub(LOOT_ITEM, '%%s', TEST_LOOTER, 1)
		msg = gsub(msg, '%%s', args, 1)
		AddOn:CHAT_MSG_LOOT(msg, nil, nil, nil, TEST_LOOTER);
	elseif cmd == "debug" then
		AddOn.Config.debug = not AddOn.Config.debug
		AddOn.Print(AddOn.Config.debug and L["Debug mode enabled"] or L["Debug mode disabled"])
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
