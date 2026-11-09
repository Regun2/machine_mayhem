-- Hacked (rebel-aligned) Killer Scanner: barrages the player's enemies.
AddCSLuaFile()
ENT.Base      = "snpc_kscanner"
ENT.PrintName = "Hacked Killer Scanner"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_kscanner_hacked", {
	Name = "Hacked Killer Scanner", Class = "snpc_kscanner_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 64,
})
