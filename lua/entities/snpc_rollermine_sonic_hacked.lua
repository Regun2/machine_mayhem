-- Hacked (rebel-aligned) Sonic Rollermine: spindashes into the player's enemies.
AddCSLuaFile()
ENT.Base      = "snpc_rollermine_sonic"
ENT.PrintName = "Hacked Sonic Rollermine"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true
ENT.TrailColor = Color(255, 215, 90)

list.Set("MachineMayhem", "snpc_rollermine_sonic_hacked", {
	Name = "Hacked Sonic Rollermine", Class = "snpc_rollermine_sonic_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 16,
})
