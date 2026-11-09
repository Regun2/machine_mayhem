-- Hacked (rebel-aligned) Missilehack.
AddCSLuaFile()
ENT.Base      = "snpc_missilehack"
ENT.PrintName = "Hacked Missilehack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_missilehack_hacked", {
	Name = "Hacked Missilehack", Class = "snpc_missilehack_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})
