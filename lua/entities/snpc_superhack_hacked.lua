-- Rebel-aligned J.I. Superhack (hacked: friendly to the player and rebels, 2x engine power).
AddCSLuaFile()
ENT.Base      = "snpc_superhack"
ENT.PrintName = "Hacked Superhack"
ENT.Author    = "Jackarunda"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_superhack_hacked", {
	Name = "Hacked Superhack", Class = "snpc_superhack_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})
