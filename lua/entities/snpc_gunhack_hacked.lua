-- Hacked (rebel-aligned) Gunhack.
AddCSLuaFile()
ENT.Base      = "snpc_gunhack"
ENT.PrintName = "Hacked Gunhack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_gunhack_hacked", {
	Name = "Hacked Gunhack", Class = "snpc_gunhack_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})
