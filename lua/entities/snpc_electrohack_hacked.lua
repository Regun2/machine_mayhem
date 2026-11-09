-- Rebel-aligned (hacked) version: friendly to the player and rebels, 2x engine power.
AddCSLuaFile()
ENT.Base      = "snpc_electrohack"
ENT.PrintName = "Hacked Electrohack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_electrohack_hacked", {
	Name = "Hacked Electrohack", Class = "snpc_electrohack_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})
