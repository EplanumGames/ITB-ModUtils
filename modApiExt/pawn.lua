kf_ModApiExt_Dummy = {
	Name = "",
	Image = nil,
	Health = 100,
	MoveSpeed = 0,
	Pushable = false,
	Corpse = false,
	IgnoreFire = true,
	IgnoreSmoke = true,
	IgnoreFlip = true,
	Neutral = true,
	Massive = true,
	Corporate = false,
	IsPortrait = false,
	SpaceColor = false,
	DefaultTeam = TEAM_PLAYER,
}
AddPawn("kf_ModApiExt_Dummy")

--------------------------------------------------------------------------

local pawn = {}

--[[
	Sets the pawn on fire if true, or removes the Fire status from it if false.
--]]
function pawn:setFire(pawn, fire)
	local d = SpaceDamage()
	if fire then d.iFire = EFFECT_CREATE else d.iFire = EFFECT_REMOVE end
	self:safeDamage(pawn, d)
end

--[[
	Damages the specified pawn using the specified SpaceDamage instance, without
	causing any side effects to the board (unless setting the Pawn on fire, and
	it is standing in a forest -- Pawns on fire set forests ablaze as soon as they
	move onto them.)
	The SpaceDamage's loc attribute is overwritten by this function.

	pawn
		The pawn to damage
	spaceDamage
		SpaceDamage instance to deal to the pawn.
--]]
function pawn:safeDamage(pawn, spaceDamage)
	local wasOnBoard = self.board:isPawnOnBoard(pawn)

	local pawnSpace = pawn:GetSpace()
	local safeSpace = self.board:getSafeSpace()

	local terrainData = self.board:getRestorableTerrainData(safeSpace)

	if not wasOnBoard then
		Board:AddPawn(pawn, safeSpace)
	end

	-- Set to water first to get rid of potential fire on the tile
	Board:SetTerrain(safeSpace, TERRAIN_WATER)
	-- change it to basic terrain so we don't trigger sounds if it's
	-- sand or forest tile or other.
	Board:SetTerrain(safeSpace, TERRAIN_ROAD)
	-- Pawns get affected by acid if moved onto an acid tile
	-- (even though technically they shouldn't, since the pawn doesn't
	-- stand on the tile during missionUpdate step?)
	Board:SetAcid(safeSpace, false)

	pawn:SetSpace(safeSpace)

	spaceDamage.loc = safeSpace
	Board:DamageSpace(spaceDamage)

	pawn:SetSpace(pawnSpace)
	self.board:restoreTerrain(safeSpace, terrainData)

	if not wasOnBoard then Board:RemovePawn(pawn) end
end

--[[
	Attempts to copy state from source pawn to the target pawn.
--]]
function pawn:copyState(sourcePawn, targetPawn)
	if sourcePawn:GetHealth() < targetPawn:GetHealth() then
		local spaceDamage = SpaceDamage()
		spaceDamage.iDamage = targetPawn:GetHealth() - sourcePawn:GetHealth()

		self:safeDamage(targetPawn, spaceDamage)
	end

	if sourcePawn:IsFire() then self:setFire(targetPawn, true) end
	if sourcePawn:IsFrozen() then targetPawn:SetFrozen(true) end
	if sourcePawn:IsAcid() then targetPawn:SetAcid(true) end
	if sourcePawn:IsShield() then targetPawn:SetShield(true) end
end

--[[
	Replaces the pawn with another one of the specified type.

	targetPawn
		The Pawn instance to replace.
	newPawnType
		Name of the pawn class to create the pawn from.
	returns
		The new pawn
--]]
function pawn:replace(targetPawn, newPawnType)
	local newPawn = PAWN_FACTORY:CreatePawn(newPawnType)

	newPawn:SetInvisible(true)
	newPawn:SetActive(targetPawn:IsActive())

	Board:AddPawn(newPawn, targetPawn:GetSpace())
	self:copyState(targetPawn, newPawn)
	Board:RemovePawn(targetPawn)

	-- make it visible on the next step to prevent audiovisual
	-- effects from playing
	self:runLater(function() newPawn:SetInvisible(false) end)

	return newPawn
end

function pawn:isDead(pawn)
	if pawn:IsPlayer() and pawn:IsMech() then
		return pawn:GetHealth() == 0 or pawn:IsDead()
	elseif pawn:GetHealth() == 0 or not self.board:isPawnOnBoard(pawn) then
		return true
	end

	return false
end

--[[
	Returns the pawn with the specified id. Works for pawns which
	may have been removed from the board.
--]]
function pawn:getById(pawnId)
	return Board:GetPawn(pawnId) or (modApiExt_pawnUserdata and modApiExt_pawnUserdata[pawnId]) or nil
end

--[[
	Returns the currently selected pawn, or nil if none is selected.
--]]
function pawn:getSelected()
	-- just Pawn works as well -- but it stays set even after it is deselected.
	for id, pawn in pairs(modApiExt.pawnUserdata) do
		if pawn:IsSelected() then return pawn end
	end

	return nil
end

--[[
	Returns the currently highlighted pawn (the one the player is hovering his
	mouse cursor over).
--]]
function pawn:getHighlighted()
	return Board:GetPawn(mouseTile())
end

function pawn:getSavedataTable(pawnId, sourceTable)
	if sourceTable then
		for k, v in pairs(sourceTable) do
			if type(v) == "table" and v.id and modApi:stringStartsWith(k, "pawn") then
				if v.id == pawnId then return v end
			end
		end	
	else
		local region = self.board:getCurrentRegion()
		local ptable = self:getSavedataTable(pawnId, SquadData)
		if not ptable and region then
			ptable = self:getSavedataTable(pawnId, region.player.map_data)
		end

		return ptable
	end

	return nil
end

function pawn:getWeaponData(ptable, field)
	assert(type(field) == "string")
	assert(field == "primary" or field == "secondary")
	local t = {}

	if ptable then
		t.id = ptable[field]
		t.power = ptable[field.."_power"]
		t.upgrade1 = ptable[field.."_mod1"]
		t.upgrade2 = ptable[field.."_mod2"]
	end

	return t
end

local function getUpgradeSuffix(wtable)
	if
		wtable.upgrade1 and wtable.upgrade1[1] > 0 and
		wtable.upgrade2 and wtable.upgrade2[1] > 0
	then
		return "_AB"
	elseif wtable.upgrade1 and wtable.upgrade1[1] > 0 then
		return "_A"
	elseif wtable.upgrade2 and wtable.upgrade2[1] > 0 then
		return "_B"
	end

	return ""
end

function pawn:getWeapons(pawnId)
	local ptable = self:getSavedataTable(pawnId)
	local t = {}

	local primary = self:getWeaponData(ptable, "primary")
	local secondary = self:getWeaponData(ptable, "secondary")

	if primary.id then
		t[1] = primary.id .. getUpgradeSuffix(primary)
	end
	if secondary.id then
		t[2] = secondary.id .. getUpgradeSuffix(secondary)
	end

	return t
end

--[[
	Returns a table holding information about the pilot of the pawn.
	Returns nil if the pawn is not piloted (eg. vek, mechs whose pilot is dead, etc.)
--]]
function pawn:getPilotTable(pawnId)
	local ptable = self:getSavedataTable(pawnId)

	return ptable.pilot
end

--[[
	Returns id of the pilot piloting this pawn, or "Pilot_Artificial" if
	it's not piloted.
--]]
function pawn:getPilotId(pawnId)
	local pilot = self:getPilotTable(pawnId)
	if pilot then
		return pilot.id
	else
		return "Pilot_Artificial"
	end
end

--todo update for massive and flag for flying
local function pawnTerrainMatcher(p, terrain, includeImpassible, includeFlying, includeMassive, pointsToExclude)
	local pTerrain = Board:GetTerrain(p)	
	
	--if the terrain is not the terrain we are immediate looking for we need to continue checking if it counts 
	--towards surronding
	if pTerrain ~= terrain then			
		--if we are not including impassible terrains or (if we are and) the terrain not a mountian or a building
		--we need to continue checking if it counts towards surronding
		if (not includeImpassible) or (pTerrain ~= TERRAIN_MOUNTAIN and pTerrain ~= TERRAIN_BUILDING) then
			--if the unit is flying or (if its a ground unit and) the terrain is not a water-like terrain then
			--we need to continue checking if it counts towards surronding
			if unit:IsFlying() or (pTerrain ~= TERRAIN_WATER and pTerrain ~= TERRAIN_ACID and pTerrain ~= TERRAIN_LAVA and pTerrain ~= TERRAIN_EMPTY) then					
				--see if its one of the points that is queued to become the terrain and if it is count it
				local foundPoint = false
				for pIdx = 1, #pointsToExclude do
					if pointsToExclude[pIdx] == p then
						pIdx = #pointsToExclude
						foundPoint = true
					end
				end
					
				if not foundPoint then
					return false
				end
			end
		end
	end
	
	return true
end

function pawn:isSurroundedByTerrain(pawnOrId, terrain, includeImpassible, includeFlying, includeMassive, pointsToExclude)
	includeImpassible = includeImpassible or true
	includeFlying = includeFlying or true
	includeMassive = includeMassive or true
	pointsToBeTerrain = pointsToBeTerrain or {}
	
	--get the pawn data if it was not passed to us
	local unit = pawnOrId
	if type(pawnOrId) == "number" then
		if not Board then
			return false
		end
		
		unit = Board:GetPawn(pawnOrId)
	end
	
	--get the space of the unit
	local point = unit:GetSpace()
 
	--todo update for massive
	return self.board:isSpaceSurroundedBy(point, pawnTerrainMatcher, terrain, includeImpassible, includeFlying, includeMassive, pointsToExclude)
end

function pawn:isSurroundedByAndOnTerrain(pawnOrId, terrain, includeImpassible, includeFlying, includeMassive, pointsToExclude)
	--get the pawn data if it was not passed to us
	local unit = pawnOrId
	if type(pawnOrId) == "number" then
		if not Board then
			return false
		end
		
		unit = Board:GetPawn(pawnOrId)
	end
	
	--get the space of the unit
	local point = unit:GetSpace()
 
	--todo update for massive
	return pawnTerrainMatcher(point, terrain, false, false, false, {}) and
			self.board:isSurroundedByTerrain(point, pawnTerrainMatcher, terrain, includeImpassible, includeFlying, includeMassive, pointsToExclude)
end

return pawn