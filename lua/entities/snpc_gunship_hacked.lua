-- Hacked (rebel-aligned) Gunship.
AddCSLuaFile()
ENT.Base      = "snpc_gunship"
ENT.PrintName = "Hacked Gunship"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_gunship_hacked", {
	Name = "Hacked Gunship", Class = "snpc_gunship_hacked", Group = "Bosses",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 96,
})
