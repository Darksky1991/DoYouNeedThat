local lib = LibStub:NewLibrary("DyntInspect", 2)
if not lib then return end

local pairs, ipairs, tostring, type = pairs, ipairs, tostring, type
local tinsert, tremove = table.insert, table.remove
local now = GetTime or time
local CreateFrame, C_Timer = CreateFrame, C_Timer
local UnitGUID, UnitName, UnitExists = UnitGUID, UnitName, UnitExists
local UnitIsConnected, UnitIsVisible = UnitIsConnected, UnitIsVisible
local IsInRaid, IsInGroup, GetNumGroupMembers = IsInRaid, IsInGroup, GetNumGroupMembers
local InCombatLockdown, CanInspect, NotifyInspect = InCombatLockdown, CanInspect, NotifyInspect
local CheckInteractDistance, ClearInspectPlayer = CheckInteractDistance, ClearInspectPlayer
local GetInspecting = GetInspecting
local GetInventoryItemLink, GetRealmName = GetInventoryItemLink, GetRealmName
local gsub, lower = string.gsub, string.lower
local max = math.max

local DEFAULTS = {
	cacheMaxAge = 600,
	requestThrottle = 1.2,
	inspectTimeout = 2.5,
	retryDelay = 3,
	maxAttempts = 4,
	failureCooldown = 15,
	groupScanInterval = 10,
	inspectUiRetryDelay = 1,
	minValidItemCount = 8,
}

local EQUIPMENT_SLOTS = {
	INVSLOT_HEAD,
	INVSLOT_NECK,
	INVSLOT_SHOULDER,
	INVSLOT_CHEST,
	INVSLOT_WAIST,
	INVSLOT_LEGS,
	INVSLOT_FEET,
	INVSLOT_WRIST,
	INVSLOT_HAND,
	INVSLOT_FINGER1,
	INVSLOT_FINGER2,
	INVSLOT_TRINKET1,
	INVSLOT_TRINKET2,
	INVSLOT_BACK,
	INVSLOT_MAINHAND,
	INVSLOT_OFFHAND,
}

lib.frame = lib.frame or CreateFrame("Frame")
lib.config = lib.config or {}
lib.cache = lib.cache or {}
lib.failures = lib.failures or {}
lib.queue = lib.queue or {}
lib.queuedByGuid = lib.queuedByGuid or {}
lib.nameToGuid = lib.nameToGuid or {}
lib.callbacks = lib.callbacks or {}
lib.active = nil
lib.debug = nil
lib.nextRequestAt = 0
lib.startTimer = nil
lib.startAt = nil
lib.groupScanTicker = nil

for key, value in pairs(DEFAULTS) do
	if lib.config[key] == nil then
		lib.config[key] = value
	end
end

local function debug(message, ...)
	if lib.debug then
		lib.debug(message, ...)
	end
end

local function normalizeName(name)
	if not name or name == "" then return nil end
	return lower(gsub(name, "%s+", ""))
end

local function unitFullName(unit)
	local name, realm = UnitName(unit)
	if not name then return nil, nil end
	if not realm or realm == "" then
		realm = GetRealmName and GetRealmName()
	end
	if realm and realm ~= "" then
		return name .. "-" .. realm, name
	end
	return name, name
end

local function rememberName(guid, unit, name)
	if not guid then return end
	local fullName, shortName
	if unit then
		fullName, shortName = unitFullName(unit)
	end
	name = name or fullName
	if name then
		lib.nameToGuid[normalizeName(name)] = guid
	end
	if fullName then
		lib.nameToGuid[normalizeName(fullName)] = guid
	end
	if shortName then
		lib.nameToGuid[normalizeName(shortName)] = guid
	end
end

local function findUnitByGuid(guid)
	if not guid then return nil end
	if UnitGUID("player") == guid then return "player" end
	local prefix = IsInRaid() and "raid" or "party"
	local max = IsInRaid() and GetNumGroupMembers() or (IsInGroup() and (GetNumGroupMembers() - 1) or 0)
	for i = 1, max do
		local unit = prefix .. i
		if UnitGUID(unit) == guid then
			return unit
		end
	end
	return nil
end

local function activeGroupGuids()
	local active = {}
	local prefix = IsInRaid() and "raid" or "party"
	local max = IsInRaid() and GetNumGroupMembers() or (IsInGroup() and (GetNumGroupMembers() - 1) or 0)
	for i = 1, max do
		local guid = UnitGUID(prefix .. i)
		if guid then
			active[guid] = true
		end
	end
	return active
end

local function runCallbacks(guid, data, reason)
	for _, callback in pairs(lib.callbacks) do
		callback(guid, data, reason)
	end
end

local function countTable(tbl)
	local count = 0
	for _ in pairs(tbl or {}) do
		count = count + 1
	end
	return count
end

local function readItems(unit)
	local items, count = {}, 0
	for _, slotId in ipairs(EQUIPMENT_SLOTS) do
		local itemLink = GetInventoryItemLink(unit, slotId)
		items[slotId] = itemLink
		if itemLink then
			count = count + 1
		end
	end
	return items, count
end

local function writeCache(guid, unit, items, count, reason, complete)
	local currentTime = now()
	local name = unitFullName(unit)
	local previous = lib.cache[guid]
	-- Inspect responses can contain different partial slot sets even when their
	-- item counts match. Preserve every previously known slot unless an explicit
	-- inventory-change event has already invalidated the cache.
	if previous and previous.items then
		local merged = {}
		for slotId, itemLink in pairs(previous.items) do merged[slotId] = itemLink end
		for slotId, itemLink in pairs(items) do merged[slotId] = itemLink end
		items = merged
		count = countTable(items)
		complete = complete or previous.complete == true
	end
	local data = {
		guid = guid,
		items = items,
		unit = unit,
		name = name,
		updatedAt = currentTime,
		expiresAt = currentTime + lib.config.cacheMaxAge,
		count = count,
		complete = complete == true,
	}
	lib.cache[guid] = data
	lib.failures[guid] = nil
	rememberName(guid, unit, name)
	debug("Inspect cache written: guid=%s unit=%s items=%s reason=%s", guid, unit, tostring(count), tostring(reason))
	runCallbacks(guid, data, reason)
	return data
end

local function userInspectionActive()
	if InspectFrame and InspectFrame.unit then return true end
	if PlayerSpellsFrame and PlayerSpellsFrame.IsInspecting and PlayerSpellsFrame:IsInspecting() then return true end
	return false
end

local function clearOwnedInspectState(request)
	if not request or not request.notified or not ClearInspectPlayer then return end
	if userInspectionActive() then return end
	if GetInspecting and GetInspecting() ~= request.guid then return end
	ClearInspectPlayer()
end

local function inspectionChannelBusy()
	if userInspectionActive() then return true end
	return GetInspecting and GetInspecting() ~= nil
end

local function cancelTimer(timer)
	if timer and timer.Cancel then timer:Cancel() end
end

local function scheduleStart(delay)
	delay = max(0, delay or 0)
	local scheduledAt = now() + delay
	if lib.startTimer and lib.startAt and lib.startAt <= scheduledAt then return end

	cancelTimer(lib.startTimer)
	local timer
	timer = C_Timer.NewTimer(delay, function()
		if lib.startTimer ~= timer then return end
		lib.startTimer = nil
		lib.startAt = nil
		lib:StartNext()
	end)
	lib.startTimer = timer
	lib.startAt = scheduledAt
end

local function moveQueuedToFront(request)
	for i = 1, #lib.queue do
		if lib.queue[i] == request then
			tremove(lib.queue, i)
			tinsert(lib.queue, 1, request)
			return
		end
	end
end

local function mergeRequiredSlots(request, requiredSlots)
	if type(requiredSlots) ~= "table" then return end
	request.requiredSlots = request.requiredSlots or {}
	local present = {}
	for _, slotId in ipairs(request.requiredSlots) do present[slotId] = true end
	for _, slotId in ipairs(requiredSlots) do
		if not present[slotId] then
			request.requiredSlots[#request.requiredSlots + 1] = slotId
			present[slotId] = true
		end
	end
end

local function requiredSlotsReady(items, requiredSlots)
	if type(requiredSlots) ~= "table" or #requiredSlots == 0 then return false end
	for _, slotId in ipairs(requiredSlots) do
		if items[slotId] == nil then return false end
	end
	return true
end

local function cacheSatisfies(data, requiredSlots)
	if not data then return false end
	if type(requiredSlots) == "table" and #requiredSlots > 0 then
		return requiredSlotsReady(data.items or {}, requiredSlots)
	end
	return data.complete == true
end

local function enqueueRequest(request)
	if request.priority then
		tinsert(lib.queue, 1, request)
	else
		lib.queue[#lib.queue + 1] = request
	end
end

local function retryDelayFor(reason, attempts)
	if reason and (reason:find("out of inspect range", 1, true)
		or reason:find("unit offline", 1, true)
		or reason:find("unit not visible", 1, true)
		or reason:find("cannot inspect unit", 1, true)
		or reason:find("in combat", 1, true)
		or reason:find("unit missing", 1, true)
		or reason:find("guid mismatch", 1, true)) then
		return lib.config.failureCooldown
	end
	if attempts > lib.config.maxAttempts then
		return lib.config.failureCooldown
	end
	return lib.config.retryDelay
end

local function finishRequest(request, reason, retry)
	if lib.active == request then
		lib.active = nil
	end
	local wasNotified = request and request.notified
	if request and request.timeoutTimer then
		cancelTimer(request.timeoutTimer)
		request.timeoutTimer = nil
	end
	clearOwnedInspectState(request)
	if request then
		request.notified = false
		request.token = nil
	end

	if retry and request and request.guid then
		request.attempts = (request.attempts or 0) + 1
		local delay = retryDelayFor(reason, request.attempts)
		if request.attempts > lib.config.maxAttempts then
			request.attempts = 0
			debug("Inspect deferred: guid=%s unit=%s reason=%s nextTry=%s", request.guid, tostring(request.unit), tostring(reason), tostring(now() + delay))
		else
			debug("Inspect retry: guid=%s unit=%s reason=%s attempt=%s nextTry=%s", request.guid, tostring(request.unit), tostring(reason), tostring(request.attempts), tostring(now() + delay))
		end
		request.nextTry = now() + delay
		lib.failures[request.guid] = {
			reason = reason,
			nextTry = request.nextTry,
			attempts = request.attempts,
		}
		lib.queuedByGuid[request.guid] = request
		enqueueRequest(request)
		if wasNotified then
			lib.nextRequestAt = max(lib.nextRequestAt or 0, now() + lib.config.requestThrottle)
		end
		-- Drain other ready work now. StartNext will schedule the earliest delayed
		-- request only when nothing else can run.
		scheduleStart(0)
		return
	end

	if request and request.guid then
		lib.queuedByGuid[request.guid] = nil
	end
	if wasNotified then
		lib.nextRequestAt = max(lib.nextRequestAt or 0, now() + lib.config.requestThrottle)
	end
	scheduleStart(max(0, (lib.nextRequestAt or 0) - now()))
end

local function canInspectUnit(unit)
	if not unit or not UnitExists(unit) then return false, "Inspect reason: unit missing" end
	if InCombatLockdown and InCombatLockdown() then return false, "Inspect reason: in combat" end
	if UnitIsConnected and not UnitIsConnected(unit) then return false, "Inspect reason: unit offline" end
	if UnitIsVisible and not UnitIsVisible(unit) then return false, "Inspect reason: unit not visible" end
	if CheckInteractDistance and not CheckInteractDistance(unit, 1) then return false, "Inspect reason: unit out of inspect range" end
	if not CanInspect(unit) then return false, "Inspect reason: cannot inspect unit" end
	return true
end

function lib:Configure(options)
	options = type(options) == "table" and options or {}
	for key, value in pairs(options) do
		if self.config[key] ~= nil then
			self.config[key] = value
		end
	end
end

function lib:SetDebug(callback)
	self.debug = callback
end

function lib:RegisterCallback(addonName, callback)
	if addonName and callback then
		self.callbacks[addonName] = callback
	end
end

function lib:UnregisterCallback(addonName)
	self.callbacks[addonName] = nil
end

function lib:GetCached(guidOrName)
	if not guidOrName then return nil end
	if self.cache[guidOrName] then return self.cache[guidOrName] end
	local guid = self.nameToGuid[normalizeName(guidOrName)]
	return guid and self.cache[guid] or nil
end

function lib:QueueUnit(unit, reason, priority, force, requiredSlots)
	if not unit or not UnitExists(unit) then return false, "Inspect reason: unit missing" end
	local guid = UnitGUID(unit)
	if not guid then return false, "Inspect reason: guid missing" end
	rememberName(guid, unit)

	local currentTime = now()
	local cached = self.cache[guid]
	if cached and not force and cached.expiresAt and cached.expiresAt > currentTime and cacheSatisfies(cached, requiredSlots) then
		debug("Inspect skipped: cached guid=%s unit=%s age=%s", guid, unit, tostring(currentTime - cached.updatedAt))
		runCallbacks(guid, cached, "cached")
		return true, "cached"
	end

	local request = self.queuedByGuid[guid]
	if request then
		request.unit = unit
		request.reason = reason or request.reason
		request.force = request.force or force
		mergeRequiredSlots(request, requiredSlots)
		if priority then
			request.priority = true
			request.nextTry = nil
			request.attempts = 0
			moveQueuedToFront(request)
		end
		debug("Inspect queued: guid=%s unit=%s reason=%s priority=%s", guid, unit, tostring(reason), tostring(priority))
		scheduleStart(0)
		return true, "queued"
	end

	local failure = self.failures[guid]

	request = {
		guid = guid,
		unit = unit,
		reason = reason or "manual",
		priority = priority == true,
		force = force == true,
		attempts = (priority or force) and 0 or (failure and failure.attempts or 0),
		nextTry = (not priority and not force and failure and failure.nextTry and failure.nextTry > currentTime) and failure.nextTry or nil,
	}
	mergeRequiredSlots(request, requiredSlots)
	self.queuedByGuid[guid] = request
	enqueueRequest(request)
	debug("Inspect queued: guid=%s unit=%s reason=%s priority=%s", guid, unit, tostring(reason), tostring(priority))
	scheduleStart(0)
	return true, "queued"
end

function lib:StartGroupScan(reason)
	if not self.groupScanTicker then
		self.groupScanTicker = C_Timer.NewTicker(self.config.groupScanInterval, function()
			self:QueueGroup("periodic", false, false)
		end)
	end
	return self:QueueGroup(reason or "group_scan", false, false)
end

function lib:StopGroupScan()
	cancelTimer(self.groupScanTicker)
	self.groupScanTicker = nil
end

function lib:QueueGroup(reason, priority, force)
	local count = 0
	local prefix = IsInRaid() and "raid" or "party"
	local max = IsInRaid() and GetNumGroupMembers() or (IsInGroup() and (GetNumGroupMembers() - 1) or 0)
	for i = 1, max do
		local ok = self:QueueUnit(prefix .. i, reason or "group", priority, force)
		if ok then count = count + 1 end
	end
	debug("Inspect group queued: reason=%s count=%s", tostring(reason), tostring(count))
	return count
end

function lib:ClearGroupCache()
	local active = activeGroupGuids()
	local removedCache, removedFailures, removedQueue = 0, 0, 0

	for guid in pairs(self.cache) do
		if not active[guid] then
			self.cache[guid] = nil
			removedCache = removedCache + 1
		end
	end
	for guid in pairs(self.failures) do
		if not active[guid] then
			self.failures[guid] = nil
			removedFailures = removedFailures + 1
		end
	end
	for i = #self.queue, 1, -1 do
		local request = self.queue[i]
		if request and request.guid and not active[request.guid] then
			self.queuedByGuid[request.guid] = nil
			tremove(self.queue, i)
			removedQueue = removedQueue + 1
		end
	end
	if self.active and self.active.guid and not active[self.active.guid] then
		if self.active.timeoutTimer then cancelTimer(self.active.timeoutTimer) end
		clearOwnedInspectState(self.active)
		self.queuedByGuid[self.active.guid] = nil
		self.active = nil
		scheduleStart(0)
	end
	debug("Inspect cache cleaned: cache=%s failures=%s queue=%s", tostring(removedCache), tostring(removedFailures), tostring(removedQueue))
end

function lib:Reset()
	local activeRequest = self.active
	local cacheCount = countTable(self.cache)
	if activeRequest and activeRequest.timeoutTimer then
		cancelTimer(activeRequest.timeoutTimer)
		activeRequest.timeoutTimer = nil
	end
	self.queue = {}
	self.queuedByGuid = {}
	self.failures = {}
	self.cache = {}
	self.nameToGuid = {}
	self.active = nil
	cancelTimer(self.startTimer)
	self.startTimer = nil
	self.startAt = nil
	self:StopGroupScan()
	self.nextRequestAt = 0
	if activeRequest then
		clearOwnedInspectState(activeRequest)
	end
	debug("Inspect reset: active=%s queue=%s cache=%s", tostring(activeRequest ~= nil), "0", tostring(cacheCount))
end

function lib:StartNext()
	if self.active then return end
	if InCombatLockdown and InCombatLockdown() then return end
	if inspectionChannelBusy() then
		scheduleStart(self.config.inspectUiRetryDelay)
		return
	end
	local currentTime = now()
	if currentTime < (self.nextRequestAt or 0) then
		scheduleStart(self.nextRequestAt - currentTime)
		return
	end

	local requestIndex
	local earliestTry
	for i, queued in ipairs(self.queue) do
		if not queued.nextTry or queued.nextTry <= currentTime then
			requestIndex = i
			break
		end
		if not earliestTry or queued.nextTry < earliestTry then
			earliestTry = queued.nextTry
		end
	end
	if not requestIndex then
		if earliestTry then scheduleStart(earliestTry - currentTime) end
		return
	end

	local request = tremove(self.queue, requestIndex)
	request.nextTry = nil

	local unit = findUnitByGuid(request.guid)
	if not unit then
		finishRequest(request, "Inspect reason: guid mismatch", true)
		return
	end
	request.unit = unit

	local items, count = readItems(unit)
	local complete = count >= self.config.minValidItemCount
	local requiredReady = requiredSlotsReady(items, request.requiredSlots)
	local hasRequiredSlots = type(request.requiredSlots) == "table" and #request.requiredSlots > 0
	if requiredReady or (complete and not hasRequiredSlots) then
		writeCache(request.guid, unit, items, count, request.reason or "direct", complete)
		finishRequest(request, "cached", false)
		return
	end

	local canInspect, reason = canInspectUnit(unit)
	if not canInspect then
		finishRequest(request, reason, true)
		return
	end

	request.token = {}
	request.notified = true
	request.startedAt = now()
	self.active = request
	debug("Inspect request: guid=%s unit=%s reason=%s attempt=%s", request.guid, unit, tostring(request.reason), tostring(request.attempts or 0))
	NotifyInspect(unit)

	local token = request.token
	request.timeoutTimer = C_Timer.NewTimer(self.config.inspectTimeout, function()
		if self.active == request and request.token == token then
			debug("Inspect timeout: guid=%s unit=%s", request.guid, tostring(request.unit))
			finishRequest(request, "Inspect reason: timeout", true)
		end
	end)
end

function lib:INSPECT_READY(guid)
	local request = self.active
	if not request or request.guid ~= guid then return end
	local unit = findUnitByGuid(guid) or request.unit
	local items, count = readItems(unit)
	debug("Inspect ready: guid=%s unit=%s items=%s", guid, tostring(unit), tostring(count))
	local complete = count >= self.config.minValidItemCount
	local requiredReady = requiredSlotsReady(items, request.requiredSlots)
	if count > 0 then
		writeCache(guid, unit, items, count, request.reason or "inspect", complete)
	end
	if complete or requiredReady then
		finishRequest(request, "ready", false)
	else
		finishRequest(request, "Inspect reason: links missing", true)
	end
end

lib.frame:SetScript("OnEvent", function(_, event, ...)
	if event == "INSPECT_READY" then
		lib:INSPECT_READY(...)
	elseif event == "PLAYER_REGEN_ENABLED" then
		scheduleStart(0)
	elseif event == "GROUP_ROSTER_UPDATE" then
		lib:ClearGroupCache()
	elseif event == "UNIT_INVENTORY_CHANGED" then
		local unit = ...
		local guid = unit and UnitGUID(unit)
		local groupUnit = lib.groupScanTicker and guid and findUnitByGuid(guid)
		if groupUnit and groupUnit ~= "player" then
			lib.cache[guid] = nil
			runCallbacks(guid, nil, "invalidated")
			lib:QueueUnit(groupUnit, "inventory_changed", false, true)
		end
	end
end)

lib.frame:RegisterEvent("INSPECT_READY")
lib.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
lib.frame:RegisterEvent("GROUP_ROSTER_UPDATE")
lib.frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
