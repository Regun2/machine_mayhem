--[[-------------------------------------------------------------------------
	Replacement Mode - swaps the map's manhacks, city scanners and rollermines for our recreations,
	with a chance of one of the variants. Friendly (hacked) originals only ever become hacked versions;
	hostile ones never become hacked ones. NPCs the player spawns from the spawn menu are left alone.

	Settings (Machine Mayhem spawnmenu tab, or the console):
	  physsnpc_replace         0/1   Replacement Mode
	  physsnpc_replace_chance  0-100 chance (%) that a replacement is one of the variants
	  physsnpc_replace_power   0/1   pick the variant by strength (stronger ones are rarer) instead of evenly
	  physsnpc_replace_bias    0-4   how strongly rarity follows strength (power mode)
	  physsnpc_replace_boss    0-100 tiny chance (%, per enemy) that a manhack becomes a boss; at most one per level
	  physsnpc_replace_gunship 0/1   also replace the map's gunships with the physics Gunship boss (off by default)
	  physsnpc_replace_turrets 0/1   also replace map turrets (never named / map-scripted ones, never on the Nova Prospekt maps)
	  physsnpc_replace_now           (admin) replace the ones already on the map
---------------------------------------------------------------------------]]
AddCSLuaFile()

local cvOn = CreateConVar("physsnpc_replace", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Replace map manhacks, scanners, rollermines and turrets with the recreations")
local cvChance = CreateConVar("physsnpc_replace_chance", "30", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Chance (%) that a replacement is one of the variants", 0, 100)

CreateConVar("physsnpc_replace_power", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Pick variants by strength instead of evenly")
CreateConVar("physsnpc_replace_bias", "1.5", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "How strongly stronger variants are rarer", 0, 4)
CreateConVar("physsnpc_replace_boss", "0.5", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Tiny chance (%) per manhack to become a boss (max one per level)", 0, 100)
CreateConVar("physsnpc_replace_gunship", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Replace the map's combine gunships with the physics gunship (off by default)")
CreateConVar("physsnpc_replace_turrets", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Also replace map turrets that have no map logic attached")

-- (the settings live in the Machine Mayhem spawnmenu tab, below the NPC sections)
if CLIENT then return end

local FAMILIES = {
	npc_manhack = { base = "snpc_manhack", variants = {
		"snpc_ranger_manhack", "snpc_assassinhack", "snpc_electrohack", "snpc_superhack", "snpc_splitter",
		"snpc_manhack_carrier", "snpc_gunhack", "snpc_electrical_drone", "snpc_shadowhack", "snpc_linkhack", "snpc_missilehack" } },
	npc_cscanner = { base = "snpc_scanner", variants = { "snpc_wpnscanner", "snpc_kscanner", "snpc_battledrone" } },
	npc_rollermine = { base = "snpc_rollermine", variants = {
		"snpc_rollermine_overcharged", "snpc_rollermine_explosive", "snpc_rollermine_sonic", "snpc_rollermine_super",
		"snpc_rollermine_aquatic", "snpc_rollermine_cluster", "snpc_rollermine_leech" } },
	npc_turret_floor = { base = "snpc_turret_floor", variants = { "snpc_turret_floor_heavy", "snpc_turret_floor_sniper" } },
	npc_combinegunship = { base = "snpc_gunship", variants = {} }, -- only with physsnpc_replace_gunship
	npc_turret_ceiling = { base = "snpc_turret_ceiling", variants = { "snpc_turret_ceiling_heavy", "snpc_turret_ceiling_sniper" } },
}

-- strength rating (1 = plain) used by the power-based picking
local POWER = {
	snpc_ranger_manhack = 3, snpc_assassinhack = 5, snpc_electrohack = 4, snpc_superhack = 6, snpc_splitter = 5,
	snpc_manhack_carrier = 7, snpc_gunhack = 5, snpc_electrical_drone = 4, snpc_shadowhack = 6, snpc_linkhack = 3, snpc_missilehack = 6,
	snpc_wpnscanner = 4, snpc_kscanner = 3, snpc_battledrone = 7,
	snpc_rollermine_overcharged = 3, snpc_rollermine_explosive = 5, snpc_rollermine_sonic = 4, snpc_rollermine_super = 6,
	snpc_rollermine_aquatic = 2, snpc_rollermine_cluster = 5, snpc_rollermine_leech = 3,
	snpc_turret_floor_heavy = 4, snpc_turret_floor_sniper = 5, snpc_turret_ceiling_heavy = 4, snpc_turret_ceiling_sniper = 5,
}
local BOSSES = { npc_manhack = { "snpc_codered_hack", "snpc_jumbo_manhack" } }
local bossDone = {}  -- families that already got their boss this level

hook.Add("InitPostEntity", "ManhackMayhem_BossReset", function() bossDone = {} end)
hook.Add("PostCleanupMap", "ManhackMayhem_BossReset", function() bossDone = {} end)

local function Exists(class) return scripted_ents.GetStored(class) ~= nil end

local ALLY = {}
for _, n in ipairs({ "CLASS_PLAYER", "CLASS_PLAYER_ALLY", "CLASS_PLAYER_ALLY_VITAL", "CLASS_CITIZEN_REBEL", "CLASS_CITIZEN_PASSIVE", "CLASS_HACKED_ROLLERMINE" }) do
	if _G[n] then ALLY[_G[n]] = true end
end

local function IsAlly(ent)
	local c = ent.Classify and ent:Classify()
	return c ~= nil and ALLY[c] == true
end

local function PickVariant(fam)
	if not GetConVar("physsnpc_replace_power"):GetBool() then return fam.variants[math.random(#fam.variants)] end
	local bias, total, w = GetConVar("physsnpc_replace_bias"):GetFloat(), 0, {}
	for i, v in ipairs(fam.variants) do
		w[i] = 1 / (POWER[v] or 3) ^ bias
		total = total + w[i]
	end
	local r = math.Rand(0, total)
	for i, v in ipairs(fam.variants) do
		r = r - w[i]
		if r <= 0 then return v end
	end
	return fam.variants[#fam.variants]
end

local function Pick(fam, ally, cls)
	local class = fam.base
	local boss = BOSSES[cls]
	if boss and not bossDone[cls] and math.Rand(0, 100) < GetConVar("physsnpc_replace_boss"):GetFloat() then
		local b = boss[math.random(#boss)]
		local full = ally and (b .. "_hacked") or b
		if Exists(full) then bossDone[cls] = true return full end
	end
	if #fam.variants > 0 and math.random(100) <= cvChance:GetInt() then
		class = PickVariant(fam)
	end
	local full = ally and (class .. "_hacked") or class
	if Exists(full) then return full end
	full = ally and (fam.base .. "_hacked") or fam.base
	return Exists(full) and full or nil
end

local function TryReplace(ent)
	if not IsValid(ent) or ent.PhysKeep then return end
	local fam = FAMILIES[ent:GetClass()]
	if not fam then return end
	-- turrets: the map's logic talks to them (Nova Prospekt hacks them, doors / triggers enable and disable them), so only
	-- plain, unnamed, unparented ones on non-scripted maps are touched
	local cls = ent:GetClass()
	if cls == "npc_combinegunship" and not GetConVar("physsnpc_replace_gunship"):GetBool() then return end
	if cls == "npc_turret_floor" or cls == "npc_turret_ceiling" then
		if not GetConVar("physsnpc_replace_turrets"):GetBool() then return end
		if ent:GetName() ~= "" or IsValid(ent:GetParent()) or string.find(game.GetMap(), "^d2_prison") or string.find(game.GetMap(), "^d3_c17_1[23]")
			or string.find(game.GetMap(), "^ep%d_") then return end
	end
	local class = Pick(fam, IsAlly(ent), cls)
	if not class then return end

	local n = ents.Create(class)
	if not IsValid(n) then return end
	n:SetPos(ent:GetPos())
	if ent:GetClass() == "npc_turret_ceiling" then n:SetPos(ent:GetPos() - Vector(0, 0, 6)) end -- the ceiling turret's origin sits in the ceiling: start just below it
	n:SetAngles(Angle(0, ent:GetAngles().y, 0))
	if ent:GetName() ~= "" then n:SetName(ent:GetName()) end -- map logic keeps targeting it
	if ent:GetClass() == "npc_manhack" and ent:HasSpawnFlags(256) then n.StartPacked = true end
	n.PhysReplacement = true
	ent:Remove()
	n:Spawn()
	n:Activate()
end

-- NPCs spawned from the spawn menu are never replaced
hook.Add("PlayerSpawnedNPC", "ManhackMayhem_Keep", function(ply, ent)
	if IsValid(ent) then ent.PhysKeep = true end
end)

hook.Add("OnEntityCreated", "ManhackMayhem_Replace", function(ent)
	if not cvOn:GetBool() or not IsValid(ent) or not FAMILIES[ent:GetClass()] then return end
	timer.Simple(0, function() TryReplace(ent) end) -- after the spawn menu / the map finished setting it up
end)

concommand.Add("physsnpc_replace_now", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	for class in pairs(FAMILIES) do
		for _, e in ipairs(ents.FindByClass(class)) do TryReplace(e) end
	end
end)
