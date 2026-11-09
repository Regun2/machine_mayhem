--[[-------------------------------------------------------------------------
	sv_factions.lua  -  who is a friend and who is an enemy (same rules the manhacks use)

	The engine's relationship lookup is unreliable for scripted NPCs, so SNPCs decide themselves:
	Combine-side classes are friends of each other, rebel-side (player, citizens, hacked things) friends of
	each other, everything else (zombies, antlions...) is hostile to both. Nextbots are hostile unless
	their class says otherwise.
---------------------------------------------------------------------------]]

local function ClassSet(names)
	local t = {}
	for _, n in ipairs(names) do
		local v = _G[n]
		if v then t[v] = true end
	end
	return t
end
local COMBINE_SIDE = ClassSet({ "CLASS_COMBINE", "CLASS_COMBINE_GUNSHIP", "CLASS_COMBINE_HUNTER", "CLASS_METROPOLICE",
	"CLASS_MILITARY", "CLASS_SCANNER", "CLASS_STALKER", "CLASS_PROTOSNIPER", "CLASS_MANHACK" })
local REBEL_SIDE = ClassSet({ "CLASS_PLAYER", "CLASS_PLAYER_ALLY", "CLASS_PLAYER_ALLY_VITAL", "CLASS_CITIZEN_PASSIVE",
	"CLASS_CITIZEN_REBEL", "CLASS_VORTIGAUNT", "CLASS_CONSCRIPT", "CLASS_HACKED_ROLLERMINE" })
local IGNORED = ClassSet({ "CLASS_NONE", "CLASS_BULLSEYE", "CLASS_FLARE", "CLASS_MISSILE", "CLASS_EARTH_FAUNA" })

-- VJ Base NPCs report their side through VJ_NPC_Class (strings such as "CLASS_COMBINE"): translate it
local function VJClass(ent)
	local vc = ent.VJ_NPC_Class
	if type(vc) ~= "table" then return end
	local first, rebel
	for _, name in ipairs(vc) do
		local c = _G[name]
		if c then
			if COMBINE_SIDE[c] then return c end
			if REBEL_SIDE[c] then rebel = rebel or c end
			first = first or c
		end
	end
	return rebel or first
end

local function ClassOf(ent)
	if ent:IsPlayer() then return CLASS_PLAYER end
	if ent.IsPhysicsSNPC then return ent:GetNPCClass() end
	local vj = VJClass(ent)
	if vj then return vj end
	if ent.Classify then return ent:Classify() end
end

local function SideOf(c)
	if COMBINE_SIDE[c] then return 1 end
	if REBEL_SIDE[c] then return 2 end
	return 0
end

function ENT:GetDisposition(ent)
	local theirs = IsValid(ent) and ClassOf(ent)
	if IsValid(ent) and ent:IsNextBot() then
		local a, b = SideOf(self:GetNPCClass()), theirs and SideOf(theirs) or 0
		if theirs and (theirs == self:GetNPCClass() or (a ~= 0 and a == b)) then return D_LI end
		return D_HT
	end
	if not theirs or IGNORED[theirs] then return D_NU end
	local mine = self:GetNPCClass()
	if mine == theirs then return D_LI end
	local a, b = SideOf(mine), SideOf(theirs)
	if a ~= 0 and a == b then return D_LI end
	return D_HT
end
