-- Hacked (rebel-aligned) Explosive Rollermine: blows up next to the player's enemies.
AddCSLuaFile()
ENT.Base      = "snpc_rollermine_explosive"
ENT.PrintName = "Hacked Explosive Rollermine"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_rollermine_explosive_hacked", {
	Name = "Hacked Explosive Rollermine", Class = "snpc_rollermine_explosive_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 16,
})
