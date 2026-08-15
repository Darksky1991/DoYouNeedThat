local _, AddOn = ...
local UnitGUID, GetRealmName, GetPlayerInfoByGUID = UnitGUID, GetRealmName, GetPlayerInfoByGUID
local tonumber, strmatch = tonumber, strmatch
local Utils = {}

AddOn.Utils = Utils

function Utils.GetUnitNameWithRealm(unit)
	local guid = UnitGUID(unit)
	if guid ~= nil then
		local _, _, _, _, _, name, realm = GetPlayerInfoByGUID(guid)
		if not realm or realm == '' then
			realm = GetRealmName()
		end
		return name .. '-' .. realm
	else
		return nil
	end
end

function Utils.GetSlotID(itemEquipLoc)
	if itemEquipLoc == 'INVTYPE_HEAD' then return INVSLOT_HEAD
	elseif itemEquipLoc == 'INVTYPE_NECK' then return INVSLOT_NECK
	elseif itemEquipLoc == 'INVTYPE_SHOULDER' then return INVSLOT_SHOULDER
	elseif itemEquipLoc == 'BODY' then return INVSLOT_BODY
	elseif itemEquipLoc == 'INVTYPE_CHEST' then return INVSLOT_CHEST
	elseif itemEquipLoc == 'INVTYPE_ROBE' then return INVSLOT_CHEST
	elseif itemEquipLoc == 'INVTYPE_WAIST' then return INVSLOT_WAIST
	elseif itemEquipLoc == 'INVTYPE_LEGS' then return INVSLOT_LEGS
	elseif itemEquipLoc == 'INVTYPE_FEET' then return INVSLOT_FEET
	elseif itemEquipLoc == 'INVTYPE_WRIST' then return INVSLOT_WRIST
	elseif itemEquipLoc == 'INVTYPE_HAND' then return INVSLOT_HAND
	elseif itemEquipLoc == 'INVTYPE_FINGER' then return INVSLOT_FINGER1
	elseif itemEquipLoc == 'INVTYPE_TRINKET' then return INVSLOT_TRINKET1
	elseif itemEquipLoc == 'INVTYPE_CLOAK' then return INVSLOT_BACK
	elseif itemEquipLoc == 'INVTYPE_WEAPON' then return INVSLOT_MAINHAND
	elseif itemEquipLoc == 'INVTYPE_SHIELD' then return INVSLOT_OFFHAND
	elseif itemEquipLoc == 'INVTYPE_2HWEAPON' then return INVSLOT_MAINHAND
	elseif itemEquipLoc == 'INVTYPE_WEAPONMAINHAND' then return INVSLOT_MAINHAND
	elseif itemEquipLoc == 'INVTYPE_WEAPONOFFHAND' then return INVSLOT_OFFHAND
	elseif itemEquipLoc == 'INVTYPE_HOLDABLE' then return INVSLOT_OFFHAND
	elseif itemEquipLoc == 'INVTYPE_RANGED' then return INVSLOT_MAINHAND
	elseif itemEquipLoc == 'INVTYPE_THROWN' then return INVSLOT_MAINHAND
	elseif itemEquipLoc == 'INVTYPE_RANGEDRIGHT' then return INVSLOT_MAINHAND
	elseif itemEquipLoc == 'INVTYPE_RELIC' then return INVSLOT_MAINHAND
	elseif itemEquipLoc == 'INVTYPE_TABARD' then return INVSLOT_TABARD
	else return nil
	end
end

function Utils.GetItemIDFromLink(link)
	return tonumber(strmatch(link or "", "item:(%d+):"))
end
