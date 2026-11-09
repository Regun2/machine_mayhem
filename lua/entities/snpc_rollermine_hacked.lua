-- Hacked (rebel-aligned) rollermine: friendly to the player, follows them around, 0.1 s stun after a shock.
AddCSLuaFile()
ENT.Base      = "snpc_rollermine"
ENT.PrintName = "Hacked Rollermine"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_rollermine_hacked", {
	Name = "Hacked Rollermine", Class = "snpc_rollermine_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 16,
})
