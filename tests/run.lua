local failures = 0
local tests = 0

local function test(name, callback)
	tests = tests + 1
	local ok, err = pcall(callback)
	if ok then
		io.write("PASS ", name, "\n")
	else
		failures = failures + 1
		io.write("FAIL ", name, "\n  ", tostring(err), "\n")
	end
end

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

local function assertTrue(value, message)
	if not value then
		error(message or "expected a truthy value", 2)
	end
end

local function countKeys(tbl)
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

local function makeFrame()
	local frame = { registered = {} }
	function frame:RegisterEvent(event) self.registered[event] = true end
	function frame:UnregisterEvent(event) self.registered[event] = nil end
	function frame:SetScript(script, callback) self[script] = callback end
	function frame:Show() self.shown = true end
	function frame:Hide() self.shown = false end
	function frame:SetPoint() end
	return frame
end

local function loadCore(options)
	options = options or {}
	local group = {
		party1 = { guid = "Player-1-Alice", name = "Alice", realm = "Realm", class = "MAGE" },
	}
	local inspect = { calls = {} }
	function inspect:QueueGroup(...) self.groupCall = {...} end
	function inspect:ClearGroupCache() end
	function inspect:Reset() end
	function inspect:Configure() end
	function inspect:SetDebug() end
	function inspect:RegisterCallback(_, callback) self.callback = callback end
	function inspect:GetCached(key)
		if key == "Player-1-Alice" or key == "Alice-Realm" then
			return self.cached
		end
	end
	function inspect:QueueUnit(...)
		self.calls[#self.calls + 1] = {...}
		return true
	end

	local itemData = options.itemData or {}
	local sent = {}
	local printed = {}
	_G.C_Item = {
		GetItemInfo = function() return "Test", nil, 4, nil, nil, nil, nil, nil, "INVTYPE_TRINKET", nil, nil, 4, 0 end,
		IsEquippableItem = function() return true end,
		GetItemInfoInstant = function(item)
			local data = itemData[item]
			return data and data.id or 123, nil, nil, data and data.equipLoc or "INVTYPE_TRINKET"
		end,
		GetDetailedItemLevelInfo = function(item)
			local data = itemData[item]
			return data and data.ilvl or 700
		end,
		DoesItemContainSpec = function() return true end,
		IsItemBindToAccountUntilEquip = function() return false end,
	}
	_G.C_PlayerInfo = { CanUseItem = function() return true end }
	_G.C_TooltipInfo = {
		GetHyperlink = function(item)
			if options.tooltipError then error(options.tooltipError) end
			local text = options.tooltipData and options.tooltipData[item]
			return text and { lines = { { leftText = text } } } or nil
		end,
	}
	_G.C_ChatInfo = {
		InChatMessagingLockdown = function() return options.chatLocked or false end,
		SendChatMessage = function(...)
			if options.sendError then error(options.sendError) end
			sent[#sent + 1] = {...}
		end,
	}
	_G.C_Timer = {
		NewTicker = function()
			return { Cancel = function() end }
		end,
	}
	_G.UnitClass = function(unit)
		local data = group[unit]
		return data and data.name or "Player", data and data.class or "WARRIOR", 1
	end
	_G.UnitGUID = function(unit)
		local data = group[unit]
		return data and data.guid or (unit == "player" and "Player-Self" or nil)
	end
	_G.UnitName = function(unit)
		local data = group[unit]
		if data then return data.name, data.realm end
		if unit == "player" then return "Self", "Realm" end
		return nil
	end
	_G.GetRealmName = function() return "Realm" end
	_G.GetTime = function() return options.now or 100 end
	_G.IsInRaid = function() return false end
	_G.IsInGroup = function() return true end
	_G.GetNumGroupMembers = function() return 2 end
	_G.GetInstanceInfo = function() return "Test", "party" end
	_G.GetInventoryItemLink = function() return nil end
	_G.CreateFrame = function() return makeFrame() end
	_G.UIParent = {}
	_G.RAID_CLASS_COLORS = { MAGE = {r = 0.2, g = 0.4, b = 1}, WARRIOR = {r = 1, g = 1, b = 1} }
	_G.LOOT_ITEM = "%s receives loot: %s."
	_G.issecretvalue = function() return false end
	_G.Settings = nil
	_G.SlashCmdList = {}
	_G.INVSLOT_FINGER1 = 11
	_G.INVSLOT_FINGER2 = 12
	_G.INVSLOT_TRINKET1 = 13
	_G.INVSLOT_TRINKET2 = 14
	_G.INVSLOT_MAINHAND = 16
	_G.INVSLOT_OFFHAND = 17

	local icon = { Register = function() end, Show = function() end, Lock = function() end, Unlock = function() end }
	local dataBroker = { NewDataObject = function(_, _, data) return data end }
	_G.LibStub = function(name)
		if name == "DyntInspect" then return inspect end
		if name == "LibDBIcon-1.0" then return icon end
		if name == "LibDataBroker-1.1" then return dataBroker end
		error("unexpected library " .. tostring(name))
	end

	local addon = {
		L = setmetatable({}, { __index = function(_, key) return key end }),
		Utils = {
			GetItemIDFromLink = function(link) return tonumber((link or ""):match("item:(%d+):")) end,
			GetUnitNameWithRealm = function(unit)
				local data = group[unit]
				return data and (data.name .. "-" .. data.realm) or nil
			end,
			GetSlotID = function(equipLoc)
				if equipLoc == "INVTYPE_TRINKET" then return 13 end
				if equipLoc == "INVTYPE_FINGER" then return 11 end
				if equipLoc == "INVTYPE_WEAPON" then return 16 end
				if equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" then return 16 end
				if equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then return 17 end
			end,
		},
		lootFrame = makeFrame(),
	}
	_G.print = function(message) printed[#printed + 1] = message end
	local chunk = assert(loadfile("Core.lua"))
	chunk("DoYouNeedThat", addon)
	return addon, inspect, group, { sent = sent, printed = printed }
end

local function makeButton()
	return {
		Show = function(self) self.shown = true end,
		Hide = function(self) self.shown = false end,
		SetText = function(self, value) self.text = value end,
		SetTextColor = function() end,
	}
end

local function makeEntry()
	return {
		item = makeButton(), ilvl = makeButton(), name = makeButton(),
		looterEq1 = makeButton(), looterEq2 = makeButton(), whisper = makeButton(),
		Show = function(self) self.shown = true end,
		Hide = function(self) self.shown = false end,
	}
end

test("chat lockdown keeps the whisper button available", function()
	local addon, _, _, control = loadCore({ chatLocked = true })
	addon.Config = { whisperMessage = "Need [item]?" }
	local entry = { itemLink = "item:123", looter = "Alice-Realm", whisper = makeButton() }
	entry.whisper:Show()
	local sent = addon:HandleWhisperClick(entry)
	assertEqual(sent, false)
	assertTrue(entry.whisper.shown, "a blocked send must keep the retry button visible")
	assertEqual(#control.sent, 0, "chat API must not be called during messaging lockdown")
	assertTrue(#control.printed > 0, "the player should receive a failure explanation")
end)

test("a thrown whisper error keeps the button available", function()
	local addon, _, _, control = loadCore({ sendError = "blocked action" })
	addon.Config = { whisperMessage = "Need [item]?" }
	local entry = { itemLink = "item:123", looter = "Alice-Realm", whisper = makeButton() }
	entry.whisper:Show()
	local sent = addon:HandleWhisperClick(entry)
	assertEqual(sent, false)
	assertTrue(entry.whisper.shown, "a failed send must keep the retry button visible")
	assertEqual(#control.sent, 0)
	assertTrue(#control.printed > 0)
end)

test("a successful whisper hides the button", function()
	local addon, _, _, control = loadCore()
	addon.Config = { whisperMessage = "Need [item]?" }
	local entry = { itemLink = "item:123", looter = "Alice-Realm", whisper = makeButton() }
	entry.whisper:Show()
	local sent = addon:HandleWhisperClick(entry)
	assertEqual(sent, true)
	assertEqual(entry.whisper.shown, false)
	assertEqual(#control.sent, 1)
	assertEqual(control.sent[1][1], "Need item:123?")
	assertEqual(control.sent[1][2], "WHISPER")
	assertEqual(control.sent[1][4], "Alice-Realm")
end)

test("removing an entry preserves the order of surviving rows", function()
	local addon = loadCore()
	local first = { itemLink = "item:1", Hide = function(self) self.shown = false end }
	local removed = { itemLink = "item:2", Hide = function(self) self.shown = false end }
	local third = { itemLink = "item:3", Hide = function(self) self.shown = false end }
	addon.Entries = { first, removed, third }
	addon.repositionFrames = function(self, sortEntries)
		if sortEntries then
			table.sort(self.Entries, function(a, b) return (a.itemLink or "") > (b.itemLink or "") end)
		end
	end
	addon:RemoveEntry(removed)
	local active = {}
	for _, entry in ipairs(addon.Entries) do
		if entry.itemLink then active[#active + 1] = entry.itemLink end
	end
	assertEqual(active[1], "item:1")
	assertEqual(active[2], "item:3")
end)

local function gear(id, equipLoc, ilvl, track)
	local link = "item:" .. id
	return link, { id = id, equipLoc = equipLoc, ilvl = ilvl }, track and ("Upgrade Level: " .. track .. " 1/6") or nil
end

local function comparisonAddon(definitions, config)
	local itemData, tooltipData = {}, {}
	for _, definition in ipairs(definitions) do
		itemData[definition[1]] = definition[2]
		tooltipData[definition[1]] = definition[3]
	end
	local addon = loadCore({ itemData = itemData, tooltipData = tooltipData })
	addon.Config = config
	return addon
end

test("upgrade tracks are parsed from English and Chinese tooltip lines", function()
	local hero, heroData, heroTip = gear(201, "INVTYPE_HEAD", 700, "Hero")
	local champion, championData = gear(202, "INVTYPE_HEAD", 690)
	local addon = comparisonAddon({
		{ hero, heroData, heroTip },
		{ champion, championData, "升级：勇士 4/6" },
	}, {})
	assertEqual(addon:GetUpgradeTrackRank(hero), 5)
	assertEqual(addon:GetUpgradeTrackRank(champion), 4)
end)

test("ring item level comparison uses the weaker equipped ring", function()
	local drop, dropData = gear(210, "INVTYPE_FINGER", 710)
	local high, highData = gear(211, "INVTYPE_FINGER", 720)
	local low, lowData = gear(212, "INVTYPE_FINGER", 700)
	local addon = comparisonAddon({ {drop, dropData}, {high, highData}, {low, lowData} }, {
		ignoreLooterItemLevelUpgrades = true,
	})
	assertEqual(addon:ShouldIgnoreLootForRecipient(drop, "INVTYPE_FINGER", { items = { [11] = high, [12] = low } }), true)
end)

test("equal item level is not treated as a recipient upgrade", function()
	local drop, dropData = gear(220, "INVTYPE_TRINKET", 700)
	local first, firstData = gear(221, "INVTYPE_TRINKET", 710)
	local second, secondData = gear(222, "INVTYPE_TRINKET", 700)
	local addon = comparisonAddon({ {drop, dropData}, {first, firstData}, {second, secondData} }, {
		ignoreLooterItemLevelUpgrades = true,
	})
	assertEqual(addon:ShouldIgnoreLootForRecipient(drop, "INVTYPE_TRINKET", { items = { [13] = first, [14] = second } }), false)
end)

test("trinket track comparison uses the lower equipped track", function()
	local drop, dropData, dropTip = gear(230, "INVTYPE_TRINKET", 700, "Hero")
	local high, highData, highTip = gear(231, "INVTYPE_TRINKET", 720, "Myth")
	local low, lowData, lowTip = gear(232, "INVTYPE_TRINKET", 690, "Champion")
	local addon = comparisonAddon({ {drop, dropData, dropTip}, {high, highData, highTip}, {low, lowData, lowTip} }, {
		ignoreLooterTrackUpgrades = true,
	})
	assertEqual(addon:ShouldIgnoreLootForRecipient(drop, "INVTYPE_TRINKET", { items = { [13] = high, [14] = low } }), true)
end)

test("tooltip API failures fail open for track filtering", function()
	local drop, dropData = gear(235, "INVTYPE_TRINKET", 700)
	local first, firstData = gear(236, "INVTYPE_TRINKET", 690)
	local second, secondData = gear(237, "INVTYPE_TRINKET", 680)
	local addon = loadCore({
		tooltipError = "tooltip unavailable",
		itemData = { [drop] = dropData, [first] = firstData, [second] = secondData },
	})
	addon.Config = { ignoreLooterTrackUpgrades = true }
	assertEqual(addon:ShouldIgnoreLootForRecipient(drop, "INVTYPE_TRINKET", { items = { [13] = first, [14] = second } }), false)
end)

test("generic one-hand comparison uses the weaker equipped weapon", function()
	local drop, dropData = gear(240, "INVTYPE_WEAPON", 710)
	local main, mainData = gear(241, "INVTYPE_WEAPON", 730)
	local off, offData = gear(242, "INVTYPE_WEAPONOFFHAND", 700)
	local addon = comparisonAddon({ {drop, dropData}, {main, mainData}, {off, offData} }, {
		ignoreLooterItemLevelUpgrades = true,
	})
	assertEqual(addon:ShouldIgnoreLootForRecipient(drop, "INVTYPE_WEAPON", { items = { [16] = main, [17] = off } }), true)
end)

test("main-hand-only and off-hand-only drops target only their own slots", function()
	local mainDrop, mainDropData = gear(250, "INVTYPE_WEAPONMAINHAND", 690)
	local offDrop, offDropData = gear(251, "INVTYPE_SHIELD", 710)
	local main, mainData = gear(252, "INVTYPE_WEAPONMAINHAND", 700)
	local off, offData = gear(253, "INVTYPE_SHIELD", 680)
	local addon = comparisonAddon({ {mainDrop, mainDropData}, {offDrop, offDropData}, {main, mainData}, {off, offData} }, {
		ignoreLooterItemLevelUpgrades = true,
	})
	local member = { items = { [16] = main, [17] = off } }
	assertEqual(addon:ShouldIgnoreLootForRecipient(mainDrop, "INVTYPE_WEAPONMAINHAND", member), false)
	assertEqual(addon:ShouldIgnoreLootForRecipient(offDrop, "INVTYPE_SHIELD", member), true)
end)

test("a two-hand drop must exceed both equipped one-hand items", function()
	local lowerDrop, lowerDropData = gear(260, "INVTYPE_2HWEAPON", 750)
	local higherDrop, higherDropData = gear(261, "INVTYPE_2HWEAPON", 770)
	local main, mainData = gear(262, "INVTYPE_WEAPONMAINHAND", 760)
	local off, offData = gear(263, "INVTYPE_SHIELD", 700)
	local addon = comparisonAddon({ {lowerDrop, lowerDropData}, {higherDrop, higherDropData}, {main, mainData}, {off, offData} }, {
		ignoreLooterItemLevelUpgrades = true,
	})
	local member = { items = { [16] = main, [17] = off } }
	assertEqual(addon:ShouldIgnoreLootForRecipient(lowerDrop, "INVTYPE_2HWEAPON", member), false)
	assertEqual(addon:ShouldIgnoreLootForRecipient(higherDrop, "INVTYPE_2HWEAPON", member), true)
end)

test("a one-hand drop is not filtered against an equipped two-hand", function()
	local drop, dropData, dropTip = gear(270, "INVTYPE_WEAPON", 800, "Myth")
	local equipped, equippedData, equippedTip = gear(271, "INVTYPE_2HWEAPON", 700, "Champion")
	local addon = comparisonAddon({ {drop, dropData, dropTip}, {equipped, equippedData, equippedTip} }, {
		ignoreLooterItemLevelUpgrades = true,
		ignoreLooterTrackUpgrades = true,
	})
	assertEqual(addon:ShouldIgnoreLootForRecipient(drop, "INVTYPE_WEAPON", { items = { [16] = equipped } }), false)
end)

test("missing off-hand data does not filter one-hand or two-hand drops", function()
	local oneHandDrop, oneHandDropData = gear(275, "INVTYPE_WEAPON", 800)
	local twoHandDrop, twoHandDropData = gear(276, "INVTYPE_2HWEAPON", 800)
	local equipped, equippedData = gear(277, "INVTYPE_WEAPONMAINHAND", 700)
	local addon = comparisonAddon({
		{oneHandDrop, oneHandDropData}, {twoHandDrop, twoHandDropData}, {equipped, equippedData},
	}, { ignoreLooterItemLevelUpgrades = true })
	local incomplete = { items = { [16] = equipped } }
	assertEqual(addon:ShouldIgnoreLootForRecipient(oneHandDrop, "INVTYPE_WEAPON", incomplete), false)
	assertEqual(addon:ShouldIgnoreLootForRecipient(twoHandDrop, "INVTYPE_2HWEAPON", incomplete), false)
end)

test("missing main-hand data does not filter an off-hand drop", function()
	local drop, dropData = gear(278, "INVTYPE_SHIELD", 800)
	local offHand, offHandData = gear(279, "INVTYPE_SHIELD", 700)
	local addon = comparisonAddon({ {drop, dropData}, {offHand, offHandData} }, {
		ignoreLooterItemLevelUpgrades = true,
	})
	assertEqual(addon:ShouldIgnoreLootForRecipient(drop, "INVTYPE_SHIELD", { items = { [17] = offHand } }), false)
end)

test("cached recipient equipment can suppress a row before it is populated", function()
	local drop, dropData = gear(280, "INVTYPE_TRINKET", 710)
	local high, highData = gear(281, "INVTYPE_TRINKET", 720)
	local low, lowData = gear(282, "INVTYPE_TRINKET", 700)
	local addon, inspect = loadCore({ itemData = { [drop] = dropData, [high] = highData, [low] = lowData } })
	inspect.cached = { guid = "Player-1-Alice", items = { [13] = high, [14] = low }, complete = true }
	addon.Config = { ignoreLooterItemLevelUpgrades = true, openAfterEncounter = false }
	local entry = makeEntry()
	addon.Entries = { entry }
	addon.ApplyComparedItemsToEntry = function() end
	addon.SetItemTooltip = function() end
	addon.repositionFrames = function() end
	addon:AddItemToLootTable(drop, "Alice-Realm", 710)
	assertEqual(entry.itemLink, nil, "a proven recipient upgrade should never become a visible row")
	assertEqual(entry.shown, nil)
end)

test("inspect refresh removes a newly proven recipient upgrade without sorting", function()
	local drop, dropData = gear(290, "INVTYPE_FINGER", 710)
	local high, highData = gear(291, "INVTYPE_FINGER", 720)
	local low, lowData = gear(292, "INVTYPE_FINGER", 700)
	local addon = loadCore({ itemData = { [drop] = dropData, [high] = highData, [low] = lowData } })
	addon.Config = { ignoreLooterItemLevelUpgrades = true }
	local entry = makeEntry()
	entry.itemLink = drop
	entry.looter = "Alice-Realm"
	entry.guid = "Player-1-Alice"
	entry.shown = true
	addon.Entries = { entry }
	addon.RaidMembers[entry.guid] = { guid = entry.guid, name = "Alice-Realm", items = { [11] = high, [12] = low } }
	addon.ApplyComparedItemsToEntry = function() end
	local sortRequested
	addon.repositionFrames = function(_, shouldSort) sortRequested = shouldSort end
	addon:RefreshEntriesForGUID(entry.guid)
	assertEqual(entry.itemLink, nil)
	assertEqual(entry.shown, false)
	assertEqual(sortRequested, false, "automatic filtering must preserve the surviving row order")
end)

test("an off-hand filter requests both weapon slots when main-hand data is missing", function()
	local drop, dropData = gear(295, "INVTYPE_SHIELD", 710)
	local offHand, offHandData = gear(296, "INVTYPE_SHIELD", 700)
	local addon, inspect = loadCore({ itemData = { [drop] = dropData, [offHand] = offHandData } })
	inspect.cached = { guid = "Player-1-Alice", items = { [17] = offHand }, complete = true }
	addon.Config = { ignoreLooterItemLevelUpgrades = true, openAfterEncounter = false }
	addon.Entries = { makeEntry() }
	addon.ApplyComparedItemsToEntry = function() end
	addon.SetItemTooltip = function() end
	addon.repositionFrames = function() end
	addon:AddItemToLootTable(drop, "Alice-Realm", 710)
	local call = inspect.calls[1]
	assertTrue(call)
	assertEqual(call[4], true, "missing main-hand context must bypass the fresh partial cache")
	assertEqual(call[5][1], 16)
	assertEqual(call[5][2], 17)
end)

test("an inspect invalidation clears stale recipient gear before filtering new loot", function()
	local drop, dropData = gear(297, "INVTYPE_TRINKET", 710)
	local high, highData = gear(298, "INVTYPE_TRINKET", 720)
	local low, lowData = gear(299, "INVTYPE_TRINKET", 700)
	local addon = loadCore({ itemData = { [drop] = dropData, [high] = highData, [low] = lowData } })
	addon.Config = { ignoreLooterItemLevelUpgrades = true, openAfterEncounter = false }
	addon.RaidMembers["Player-1-Alice"] = { items = { [13] = high, [14] = low } }
	addon:OnInspectData("Player-1-Alice", nil, "invalidated")
	local entry = makeEntry()
	addon.Entries = { entry }
	addon.ApplyComparedItemsToEntry = function() end
	addon.SetItemTooltip = function() end
	addon.repositionFrames = function() end
	addon:AddItemToLootTable(drop, "Alice-Realm", 710)
	assertEqual(entry.itemLink, drop, "stale equipment must not suppress a row after inventory invalidation")
end)

test("an expired recipient mirror cannot suppress new loot", function()
	local drop, dropData = gear(300, "INVTYPE_TRINKET", 710)
	local high, highData = gear(301, "INVTYPE_TRINKET", 720)
	local low, lowData = gear(302, "INVTYPE_TRINKET", 700)
	local addon = loadCore({ now = 100, itemData = { [drop] = dropData, [high] = highData, [low] = lowData } })
	addon.Config = { ignoreLooterItemLevelUpgrades = true, openAfterEncounter = false }
	addon.RaidMembers["Player-1-Alice"] = { maxAge = 99, items = { [13] = high, [14] = low } }
	local entry = makeEntry()
	addon.Entries = { entry }
	addon.ApplyComparedItemsToEntry = function() end
	addon.SetItemTooltip = function() end
	addon.repositionFrames = function() end
	addon:AddItemToLootTable(drop, "Alice-Realm", 710)
	assertEqual(entry.itemLink, drop, "expired gear data must fail open")
	assertEqual(addon.RaidMembers["Player-1-Alice"], nil)
end)

test("existing databases receive disabled recipient filter defaults", function()
	local addon = loadCore()
	_G.DyntDB = {
		lootWindow = { "CENTER", 0, 0 }, lootWindowOpen = false,
		config = { whisperMessage = "Need [item]?", minDelta = 0 },
		minimap = { hide = true },
	}
	addon.ApplyGlobalFont = function() end
	addon.CreateOptionsFrame = function() end
	addon:ADDON_LOADED("DoYouNeedThat")
	assertEqual(addon.Config.ignoreLooterItemLevelUpgrades, false)
	assertEqual(addon.Config.ignoreLooterTrackUpgrades, false)
end)

test("encounter loot is not registered as a row source", function()
	local addon = loadCore()
	addon.EventFrame.registered = {}
	addon:EnableInstanceEvents()
	assertEqual(addon.EventFrame.registered.ENCOUNTER_LOOT_RECEIVED, nil,
		"premature encounter loot must not create rows")
	assertTrue(addon.EventFrame.registered.CHAT_MSG_LOOT, "chat loot remains registered")
end)

test("pending loot keeps identical items for different recipients", function()
	local addon = loadCore()
	local link = "|cffa335ee|Hitem:123:0:0:0|h[Test]|h|r"
	addon:QueuePendingLoot(link, "Alice-Realm")
	addon:QueuePendingLoot(link, "Bob-Realm")
	assertEqual(countKeys(addon.PendingLoot), 2, "pending keys must include recipient identity")
end)

test("chat loot falls back to the recipient parsed from the message", function()
	local addon = loadCore()
	local receivedItem, receivedLooter
	addon.ProcessLootItem = function(_, item, looter)
		receivedItem, receivedLooter = item, looter
	end
	local link = "|cffa335ee|Hitem:123:0:0:0|h[Test]|h|r"
	addon:CHAT_MSG_LOOT("Alice receives loot: " .. link .. ".", nil, nil, nil, "")
	assertEqual(receivedItem, link)
	assertEqual(receivedLooter, "Alice", "an empty event field must not hide the parsed recipient")
end)

test("entry dedupe scans past empty rows and normalizes item and recipient", function()
	local addon = loadCore()
	local first = { itemLink = "|Hitem:999:0|h[Other]|h", looter = "Other-Realm" }
	local empty = {}
	local duplicate = { itemLink = "|cffa335ee|Hitem:123:0:0:0|h[Test]|h|r", looter = "Alice-Realm" }
	addon.Entries = { first, empty, duplicate }
	local acquired = addon:AcquireEntry("|cff0070dd|Hitem:123:0:0:0|h[Test renamed]|h|r", "Alice")
	assertEqual(acquired, duplicate, "existing logical row should win over an earlier empty row")
end)

test("recipient dedupe identity stays stable across roster resolution changes", function()
	local addon, _, group = loadCore()
	local link = "|cffa335ee|Hitem:123:0:0:0|h[Test]|h|r"
	local existing = { itemLink = link, looter = "Alice-Realm", lootKey = addon:GetLootKey(link, "Alice-Realm") }
	local empty = {}
	addon.Entries = { existing, empty }
	assertEqual(addon:AcquireEntry(link, "Alice"), existing)
	group.party1 = nil
	assertEqual(addon:AcquireEntry(link, "Alice-Realm"), existing,
		"dedupe identity must not switch from name to GUID when roster resolution changes")
end)

test("loot row forces a slot-aware priority inspect when compared gear is missing", function()
	local addon, inspect = loadCore()
	inspect.cached = { guid = "Player-1-Alice", items = {}, complete = true }
	local entry = {
		item = makeButton(), ilvl = makeButton(), name = makeButton(),
		looterEq1 = makeButton(), looterEq2 = makeButton(), whisper = makeButton(),
		Show = function(self) self.shown = true end,
	}
	addon.Entries = { entry }
	addon.Config = { openAfterEncounter = false }
	addon.ApplyComparedItemsToEntry = function() end
	addon.SetItemTooltip = function() end
	addon.repositionFrames = function() end
	addon:AddItemToLootTable("|cffa335ee|Hitem:123:0:0:0|h[Test]|h|r", "Alice-Realm", 700)
	local call = inspect.calls[1]
	assertTrue(call, "missing gear should enqueue an inspect")
	assertEqual(call[1], "party1")
	assertEqual(call[3], true, "loot inspect should be high priority")
	assertEqual(call[4], true, "missing compared gear should bypass stale cache/backoff")
	assertEqual(call[5][1], 13)
	assertEqual(call[5][2], 14)
end)

local function loadInspect(existingMinorVersion)
	local clock = 100
	local timers = {}
	local inspectLog = {}
	local currentInspecting
	local clearCount = 0
	local units = {
		player = { guid = "Player-Self", name = "Self", realm = "Realm", exists = true, inspectable = false, items = {} },
		party1 = { guid = "Player-One", name = "One", realm = "Realm", exists = true, inspectable = false, items = {} },
		party2 = { guid = "Player-Two", name = "Two", realm = "Realm", exists = true, inspectable = true, items = {} },
		target = { guid = "Player-Target", name = "Target", realm = "Realm", exists = true, inspectable = true, items = {} },
	}

	local function newTimer(delay, callback, repeating)
		local timer = { due = clock + (delay or 0), callback = callback, delay = delay or 0, repeating = repeating, cancelled = false }
		function timer:Cancel() self.cancelled = true end
		timers[#timers + 1] = timer
		return timer
	end

	local function runDue()
		local ran = true
		local guard = 0
		while ran do
			ran = false
			guard = guard + 1
			if guard > 1000 then error("timer loop did not settle") end
			table.sort(timers, function(a, b) return a.due < b.due end)
			for _, timer in ipairs(timers) do
				if not timer.cancelled and timer.due <= clock then
					timer.cancelled = not timer.repeating
					if timer.repeating then timer.due = clock + timer.delay end
					timer.callback()
					ran = true
					break
				end
			end
		end
	end

	local function advance(seconds)
		local target = clock + seconds
		while true do
			local nextDue
			for _, timer in ipairs(timers) do
				if not timer.cancelled and timer.due <= target and (not nextDue or timer.due < nextDue) then
					nextDue = timer.due
				end
			end
			if not nextDue then break end
			clock = nextDue
			runDue()
		end
		clock = target
		runDue()
	end

	_G.time = function() return math.floor(clock) end
	_G.GetTime = function() return clock end
	_G.C_Timer = {
		After = function(delay, callback) newTimer(delay, callback, false) end,
		NewTimer = function(delay, callback) return newTimer(delay, callback, false) end,
		NewTicker = function(delay, callback) return newTimer(delay, callback, true) end,
	}
	_G.CreateFrame = function() return makeFrame() end
	_G.UnitGUID = function(unit) return units[unit] and units[unit].guid end
	_G.UnitName = function(unit)
		local data = units[unit]
		return data and data.name, data and data.realm
	end
	_G.UnitExists = function(unit) return units[unit] and units[unit].exists or false end
	_G.UnitIsConnected = function(unit) return units[unit] and units[unit].exists or false end
	_G.UnitIsVisible = function(unit) return units[unit] and units[unit].exists or false end
	_G.IsInRaid = function() return false end
	_G.IsInGroup = function() return true end
	_G.GetNumGroupMembers = function() return 3 end
	_G.InCombatLockdown = function() return false end
	_G.CanInspect = function(unit) return units[unit] and units[unit].inspectable or false end
	_G.CheckInteractDistance = function(unit) return units[unit] and units[unit].inspectable or false end
	_G.NotifyInspect = function(unit)
		inspectLog[#inspectLog + 1] = unit
		currentInspecting = units[unit] and units[unit].guid
	end
	_G.GetInspecting = function() return currentInspecting end
	_G.ClearInspectPlayer = function()
		clearCount = clearCount + 1
		currentInspecting = nil
	end
	_G.InspectFrame = nil
	_G.PlayerSpellsFrame = nil
	_G.GetInventoryItemLink = function(unit, slot) return units[unit] and units[unit].items[slot] end
	_G.GetRealmName = function() return "Realm" end
	_G.INVSLOT_HEAD = 1
	_G.INVSLOT_NECK = 2
	_G.INVSLOT_SHOULDER = 3
	_G.INVSLOT_CHEST = 5
	_G.INVSLOT_WAIST = 6
	_G.INVSLOT_LEGS = 7
	_G.INVSLOT_FEET = 8
	_G.INVSLOT_WRIST = 9
	_G.INVSLOT_HAND = 10
	_G.INVSLOT_FINGER1 = 11
	_G.INVSLOT_FINGER2 = 12
	_G.INVSLOT_TRINKET1 = 13
	_G.INVSLOT_TRINKET2 = 14
	_G.INVSLOT_BACK = 15
	_G.INVSLOT_MAINHAND = 16
	_G.INVSLOT_OFFHAND = 17

	local library
	_G.LibStub = {
		NewLibrary = function(_, _, minorVersion)
			if existingMinorVersion and minorVersion <= existingMinorVersion then return nil end
			library = {}
			return library
		end,
	}
	assert(loadfile("Libs/DyntInspect.lua"))()
	local control = {
		setInspecting = function(guid) currentInspecting = guid end,
		getClearCount = function() return clearCount end,
		setInspectFrameUnit = function(unit)
			_G.InspectFrame = unit and { unit = unit, IsShown = function() return true end } or nil
		end,
	}
	return library, units, inspectLog, runDue, advance, control
end

test("the inspect library upgrades over an older embedded revision", function()
	local inspect = loadInspect(1)
	assertTrue(inspect, "a newer DyntInspect revision must replace embedded revision 1")
end)

test("an unavailable member does not block the next inspectable member", function()
	local inspect, _, log, runDue = loadInspect()
	inspect:QueueUnit("party1", "group", false, false)
	inspect:QueueUnit("party2", "group", false, false)
	runDue()
	assertEqual(log[1], "party2", "scanner should skip delayed requests and keep draining ready work")
end)

test("a loot request can replace a later scheduled wake-up", function()
	local inspect, units, log, runDue = loadInspect()
	inspect:QueueUnit("party1", "group", false, false)
	runDue()
	units.party2.inspectable = true
	inspect:QueueUnit("party2", "loot", true, true, {13, 14})
	runDue()
	assertEqual(log[1], "party2", "priority work should not wait for an older retry timer")
end)

test("partial direct data missing required slots triggers NotifyInspect", function()
	local inspect, units, log, runDue = loadInspect()
	units.party1.inspectable = true
	units.party1.items[1] = "head"
	units.party1.items[2] = "neck"
	units.party1.items[3] = "shoulder"
	inspect:QueueUnit("party1", "loot", true, true, {13, 14})
	runDue()
	assertEqual(log[1], "party1", "three unrelated item links are not enough for a trinket comparison")
end)

test("forced loot inspect is not short-circuited by unrelated complete data", function()
	local inspect, units, log, runDue = loadInspect()
	units.party1.inspectable = true
	for slot = 1, 10 do
		if slot ~= 4 then units.party1.items[slot] = "item-" .. slot end
	end
	inspect:QueueUnit("party1", "loot", true, true, {13, 14})
	runDue()
	assertEqual(log[1], "party1", "force plus missing required slots must call NotifyInspect")
end)

test("partial inspect results do not erase a richer cache", function()
	local inspect, units, _, runDue = loadInspect()
	units.party1.inspectable = true
	for _, slot in ipairs({1, 2, 3, 5, 6, 7, 8, 9}) do units.party1.items[slot] = "old-" .. slot end
	inspect:QueueUnit("party1", "group", false, false)
	runDue()
	assertEqual(inspect:GetCached("Player-One").count, 8)
	units.party1.items = { [1] = "new-head" }
	inspect:QueueUnit("party1", "loot", true, true, {13, 14})
	runDue()
	inspect:INSPECT_READY("Player-One")
	local cached = inspect:GetCached("Player-One")
	assertEqual(cached.items[1], "new-head")
	assertEqual(cached.items[2], "old-2", "partial refresh must retain previously known slots")
	assertTrue(cached.count >= 8, "partial refresh must not downgrade cache completeness")
end)

test("lower-count inspect results do not downgrade a richer cache", function()
	local inspect, units, _, runDue = loadInspect()
	units.party1.inspectable = true
	for _, slot in ipairs({1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17}) do
		units.party1.items[slot] = "old-" .. slot
	end
	inspect:QueueUnit("party1", "group", false, false)
	runDue()
	units.party1.items = {}
	for _, slot in ipairs({1, 2, 3, 5, 6, 7, 8, 9}) do units.party1.items[slot] = "new-" .. slot end
	inspect:QueueUnit("party1", "loot", true, true, {13, 14})
	runDue()
	inspect:INSPECT_READY("Player-One")
	local cached = inspect:GetCached("Player-One")
	assertEqual(cached.items[14], "old-14", "a lower-count response must retain richer known data")
	assertEqual(cached.count, 16)
end)

test("equal-count inspect results merge complementary slot coverage", function()
	local inspect, units, _, runDue = loadInspect()
	units.party1.inspectable = true
	for _, slot in ipairs({1, 2, 3, 5, 6, 7, 8, 9}) do units.party1.items[slot] = "old-" .. slot end
	inspect:QueueUnit("party1", "group", false, false)
	runDue()
	units.party1.items = {}
	for _, slot in ipairs({10, 11, 12, 13, 14, 15, 16, 17}) do units.party1.items[slot] = "new-" .. slot end
	inspect:QueueUnit("party1", "loot", true, true, {1})
	runDue()
	inspect:INSPECT_READY("Player-One")
	local cached = inspect:GetCached("Player-One")
	assertEqual(cached.items[1], "old-1", "equal-count refresh must retain old slot coverage")
	assertEqual(cached.items[17], "new-17", "equal-count refresh must add new slot coverage")
	assertEqual(cached.count, 16)
end)

test("inventory events for non-group units are ignored", function()
	local inspect = loadInspect()
	inspect:StartGroupScan("test")
	inspect.frame.OnEvent(nil, "UNIT_INVENTORY_CHANGED", "target")
	assertEqual(inspect.queuedByGuid["Player-Target"], nil,
		"non-group targets must not enter the persistent retry queue")
end)

test("inventory changes broadcast cache invalidation to consumers", function()
	local inspect = loadInspect()
	local invalidatedGuid
	inspect:RegisterCallback("test", function(guid, data, reason)
		if data == nil and reason == "invalidated" then invalidatedGuid = guid end
	end)
	inspect.cache["Player-One"] = { guid = "Player-One", items = { [1] = "old-head" } }
	inspect:StartGroupScan("test")
	inspect.frame.OnEvent(nil, "UNIT_INVENTORY_CHANGED", "party1")
	assertEqual(invalidatedGuid, "Player-One")
	assertEqual(inspect.cache["Player-One"], nil)
end)

test("background scanning waits while the Blizzard inspect UI owns the channel", function()
	local inspect, _, log, runDue, advance, control = loadInspect()
	control.setInspectFrameUnit("target")
	inspect:QueueUnit("party2", "group", false, false)
	runDue()
	assertEqual(#log, 0, "background scan must not overwrite a user inspection")
	control.setInspectFrameUnit(nil)
	control.setInspecting(nil)
	advance(2)
	assertEqual(log[1], "party2", "queued scan should resume after the UI releases inspection")
end)

test("timeout does not clear inspection state taken over by another owner", function()
	local inspect, _, _, runDue, advance, control = loadInspect()
	inspect:QueueUnit("party2", "group", false, false)
	runDue()
	control.setInspecting("Player-Target")
	advance(3)
	assertEqual(control.getClearCount(), 0,
		"the scanner must not clear a different inspection request")
end)

test("timeout does not clear a user inspection of the same unit", function()
	local inspect, _, _, runDue, advance, control = loadInspect()
	inspect:QueueUnit("party2", "group", false, false)
	runDue()
	control.setInspectFrameUnit("party2")
	advance(3)
	assertEqual(control.getClearCount(), 0,
		"the visible inspect UI owns cleanup even when it inspects the same GUID")
end)

test("reset clears the inspection request owned by the scanner", function()
	local inspect, _, _, runDue, _, control = loadInspect()
	inspect:QueueUnit("party2", "group", false, false)
	runDue()
	inspect:Reset()
	assertEqual(control.getClearCount(), 1,
		"reset must release the scanner's own active inspection channel")
end)

test("background scanning eventually recovers a previously unavailable member", function()
	local inspect, units, log, runDue, advance = loadInspect()
	inspect:Configure({ maxAttempts = 1, retryDelay = 1, failureCooldown = 3, groupScanInterval = 2 })
	inspect:StartGroupScan("test")
	runDue()
	advance(1)
	units.party1.inspectable = true
	advance(5)
	local recovered = false
	for _, unit in ipairs(log) do
		if unit == "party1" then recovered = true end
	end
	assertTrue(recovered, "maintenance scan should retry the previously unavailable member")
end)

io.write(string.format("\n%d tests, %d failures\n", tests, failures))
if failures > 0 then
	os.exit(1)
end
