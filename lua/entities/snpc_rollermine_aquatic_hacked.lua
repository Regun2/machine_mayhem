AddCSLuaFile()
ENT.Base      = "snpc_rollermine_aquatic"
ENT.PrintName = "Hacked Aquatic Rollermine"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked = true
list.Set("MachineMayhem", "snpc_rollermine_aquatic_hacked", {
	Name = "Hacked Aquatic Rollermine", Class = "snpc_rollermine_aquatic_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 16,
})
