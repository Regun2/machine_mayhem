--[[-------------------------------------------------------------------------
	Machine Mayhem - shared glue
	  * SubCategory (GMod's native spawnmenu sub-categories) for every Machine Mayhem NPC:
	      ENT.SubCategory = "Foo"   -> "Foo" (wins; inherited by variants)
	      ENT.Hacked = true         -> "Hacked"
	      otherwise                 -> "Normal"
	  * localisation (client): killfeed etc. show the NPC's name instead of "snpc_manhack"
---------------------------------------------------------------------------]]

local CATEGORY = "Machine Mayhem"

local function Resolve(class)
	local ent = scripted_ents.Get(class)
	if not ent then return "Normal" end
	if ent.SubCategory and ent.SubCategory ~= "" then return ent.SubCategory end
	return ent.Hacked and "Hacked" or "Normal"
end

local function Patch()
	local npcs = list.GetForEdit("MachineMayhem")
	for spawn, v in pairs(npcs) do
		if v.Category == CATEGORY then
			v.SubCategory = Resolve(v.Class or spawn)
			if CLIENT then language.Add(v.Class or spawn, v.Name or spawn) end
		end
	end
	-- the Entities tab (these are spawnable as entities too)
	local sents = list.GetForEdit("SpawnableEntities")
	for class, v in pairs(sents) do
		if v.Category == CATEGORY then v.SubCategory = Resolve(class) end
	end
end

hook.Add("Initialize", "ManhackMayhem_Patch", Patch)
hook.Add("InitPostEntity", "ManhackMayhem_Patch", Patch)
hook.Add("OnReloaded", "ManhackMayhem_Patch", Patch)
