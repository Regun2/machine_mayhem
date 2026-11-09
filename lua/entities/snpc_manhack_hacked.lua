-- Rebel-aligned (hacked) manhack: green eye, player-ally class, 2x engine power,
-- steady flight when idle, loiters when dropped with no enemy.
AddCSLuaFile()
ENT.Base      = "snpc_manhack"
ENT.PrintName = "Hacked Manhack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_manhack_hacked", {
	Name = "Hacked Manhack", Class = "snpc_manhack_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})
