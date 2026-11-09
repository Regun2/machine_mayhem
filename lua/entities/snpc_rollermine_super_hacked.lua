-- Hacked (rebel-aligned) Super Rollermine: friendly to the player, zaps the player's enemies.
AddCSLuaFile()
ENT.Base      = "snpc_rollermine_super"
ENT.PrintName = "Hacked Super Rollermine"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_rollermine_super_hacked", {
	Name = "Hacked Super Rollermine", Class = "snpc_rollermine_super_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 32,
})
