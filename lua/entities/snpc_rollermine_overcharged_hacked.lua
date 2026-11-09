-- Hacked (rebel-aligned) Overcharged Rollermine: friendly to the player, shocks the player's enemies.
AddCSLuaFile()
ENT.Base      = "snpc_rollermine_overcharged"
ENT.PrintName = "Hacked Overcharged Rollermine"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_rollermine_overcharged_hacked", {
	Name = "Hacked Overcharged Rollermine", Class = "snpc_rollermine_overcharged_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 16,
})
