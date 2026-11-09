-- Rebel-aligned (hacked) version: friendly to the player and rebels, 2x engine power.
AddCSLuaFile()
ENT.Base      = "snpc_ranger_manhack"
ENT.PrintName = "Hacked Ranger Manhack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_ranger_manhack_hacked", {
	Name = "Hacked Ranger Manhack", Class = "snpc_ranger_manhack_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})
