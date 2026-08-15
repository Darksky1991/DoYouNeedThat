local lib = LibStub:NewLibrary("DyntInspect", 1)
if not lib then return end

local pairs, ipairs, tostring, type = pairs, ipairs, tostring, type
local tinsert, tremove = table.insert, table.remove
local time = time
local CreateFrame, C_Timer = CreateFrame, C_Timer
local UnitGUID, UnitName, UnitExists = UnitGUID, UnitName, UnitExists
local UnitIsConnected, UnitIsVisible = UnitIsConnected, UnitIsVisible
local IsInRaid, IsInGroup, GetNumGroupMembers = IsInRaid, IsInGroup, GetNumGroupMembers
local InCombatLockdown, CanInspect, NotifyInspect = InCombatLockdown, CanInspect, NotifyInspect
local CheckInteractDistance, ClearInspectPlayer = CheckInteractDistance, ClearInspectPlayer
local GetInventoryItemLink, GetRealmName = GetInventoryItemLink, GetRealmName
local gsub, lower = string.gsub, string.lower

local DEFAULTS = {
	cacheMaxAge = 600,
	requestThrottle = 1.2,
	inspectTimeout = 2.5,
	retryDelay = 3,
	maxAttempts = 4,
	groupScanDelay = 0.25,
	minValidItemCount = 3,
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
lib.startScheduled = false

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

local function writeCache(guid, unit, items, count, reason)
	local now = time()
	local name = unitFullName(unit)
	local data = {
		guid = guid,
		items = items,
		unit = unit,
		name = name,
		updatedAt = now,
		expiresAt = now + lib.config.cacheMaxAge,
		count = count,
	}
	lib.cache[guid] = data
	lib.failures[guid] = nil
	rememberName(guid, unit, name)
	debug("Inspect cache written: guid=%s unit=%s items=%s reason=%s", guid, unit, tostring(count), tostring(reason))
	runCallbacks(guid, data, reason)
	return data
end

local function clearOwnedInspectState(request)
	if request and request.notified and ClearInspectPlayer then
		ClearInspectPlayer()
	end
end

local function scheduleStart(delay)
	if lib.startScheduled then return end
	lib.startScheduled = true
	C_Timer.After(delay or 0, function()
		lib.startScheduled = false
		lib:StartNext()
	end)
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

local function finishRequest(request, reason, retry)
	if lib.active == request then
		lib.active = nil
	end
	if request and request.guid then
		lib.queuedByGuid[request.guid] = nil
	end
	clearOwnedInspectState(request)

	if retry and request and request.guid then
		request.attempts = (request.attempts or 0) + 1
		if request.attempts <= lib.config.maxAttempts then
			local nextTry = time() + lib.config.retryDelay
			lib.failures[request.guid] = {
				reason = reason,
				nextTry = nextTry,
				attempts = request.attempts,
			}
			lib.queuedByGuid[request.guid] = request
			tinsert(lib.queue, request)
			debug("Inspect retry: guid=%s unit=%s reason=%s attempt=%s nextTry=%s", request.guid, tostring(request.unit), tostring(reason), tostring(request.attempts), tostring(nextTry))
			scheduleStart(lib.config.retryDelay)
			return
		end
		debug("Inspect failed: guid=%s unit=%s reason=%s attempts=%s", request.guid, tostring(request.unit), tostring(reason), tostring(request.attempts))
	end

	lib.nextRequestAt = time() + lib.config.requestThrottle
	scheduleStart(lib.config.requestThrottle)
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

function lib:QueueUnit(unit, reason, priority, force)
	if not unit or not UnitExists(unit) then return false, "Inspect reason: unit missing" end
	local guid = UnitGUID(unit)
	if not guid then return false, "Inspect reason: guid missing" end
	rememberName(guid, unit)

	local now = time()
	local cached = self.cache[guid]
	if cached and not force and cached.expiresAt and cached.expiresAt > now then
		debug("Inspect skipped: cached guid=%s unit=%s age=%s", guid, unit, tostring(now - cached.updatedAt))
		runCallbacks(guid, cached, "cached")
		return true, "cached"
	end

	local failure = self.failures[guid]
	if failure and failure.nextTry and failure.nextTry > now and not force then
		debug("Inspect delayed: guid=%s unit=%s reason=%s nextTry=%s", guid, unit, tostring(failure.reason), tostring(failure.nextTry))
		scheduleStart(failure.nextTry - now)
		return false, "retry delayed"
	end

	local request = self.queuedByGuid[guid]
	if request then
		request.unit = unit
		request.reason = reason or request.reason
		request.force = request.force or force
		if priority then
			moveQueuedToFront(request)
		end
		debug("Inspect queued: guid=%s unit=%s reason=%s priority=%s", guid, unit, tostring(reason), tostring(priority))
		scheduleStart(0)
		return true, "queued"
	end

	request = {
		guid = guid,
		unit = unit,
		reason = reason or "manual",
		priority = priority == true,
		force = force == true,
		attempts = failure and failure.attempts or 0,
	}
	self.queuedByGuid[guid] = request
	if priority then
		tinsert(self.queue, 1, request)
	else
		self.queue[#self.queue + 1] = request
	end
	debug("Inspect queued: guid=%s unit=%s reason=%s priority=%s", guid, unit, tostring(reason), tostring(priority))
	scheduleStart(0)
	return true, "queued"
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
		clearOwnedInspectState(self.active)
		self.active = nil
	end
	debug("Inspect cache cleaned: cache=%s failures=%s queue=%s", tostring(removedCache), tostring(removedFailures), tostring(removedQueue))
end

function lib:Reset()
	local hadActive = self.active ~= nil
	local cacheCount = countTable(self.cache)
	self.queue = {}
	self.queuedByGuid = {}
	self.failures = {}
	self.cache = {}
	self.nameToGuid = {}
	self.active = nil
	self.startScheduled = false
	if hadActive then
		clearOwnedInspectState({ notified = true })
	end
	debug("Inspect reset: active=%s queue=%s cache=%s", tostring(hadActive), "0", tostring(cacheCount))
end

function lib:StartNext()
	if self.active then return end
	if InCombatLockdown and InCombatLockdown() then return end
	if time() < (self.nextRequestAt or 0) then
		scheduleStart(self.nextRequestAt - time())
		return
	end

	local request = tremove(self.queue, 1)
	if not request then return end
	self.queuedByGuid[request.guid] = nil

	local unit = findUnitByGuid(request.guid)
	if not unit then
		finishRequest(request, "Inspect reason: guid mismatch", true)
		return
	end
	request.unit = unit

	local items, count = readItems(unit)
	if count >= self.config.minValidItemCount then
		writeCache(request.guid, unit, items, count, request.reason or "direct")
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
	request.startedAt = time()
	self.active = request
	debug("Inspect request: guid=%s unit=%s reason=%s attempt=%s", request.guid, unit, tostring(request.reason), tostring(request.attempts or 0))
	NotifyInspect(unit)

	local token = request.token
	C_Timer.After(self.config.inspectTimeout, function()
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
	if count >= self.config.minValidItemCount then
		writeCache(guid, unit, items, count, request.reason or "inspect")
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
	end
end)

lib.frame:RegisterEvent("INSPECT_READY")
lib.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
lib.frame:RegisterEvent("GROUP_ROSTER_UPDATE")
