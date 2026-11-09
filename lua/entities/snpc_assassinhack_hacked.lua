-- Rebel-aligned (hacked) version: friendly to the player and rebels, 2x engine power.
AddCSLuaFile()
ENT.Base      = "snpc_assassinhack"
ENT.PrintName = "Hacked Assassinhack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_assassinhack_hacked", {
	Name = "Hacked Assassinhack", Class = "snpc_assassinhack_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})
