-- Hacked (rebel-aligned) weapon scanner: shoots the player's enemies.
AddCSLuaFile()
ENT.Base      = "snpc_wpnscanner"
ENT.PrintName = "Hacked Weapon Scanner"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_wpnscanner_hacked", {
	Name = "Hacked Weapon Scanner", Class = "snpc_wpnscanner_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 64,
})
