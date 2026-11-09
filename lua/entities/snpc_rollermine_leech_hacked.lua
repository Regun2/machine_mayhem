-- Rebel-aligned (hacked) Leechmine: latches onto the player's enemies only.
AddCSLuaFile()
ENT.Base      = "snpc_rollermine_leech"
ENT.PrintName = "Hacked Leechmine"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true
ENT.BodyColor = Color(190, 255, 120)

list.Set("MachineMayhem", "snpc_rollermine_leech_hacked", {
	Name = "Hacked Leechmine", Class = "snpc_rollermine_leech_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 16,
})
