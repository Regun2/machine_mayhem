-- Hacked (rebel-aligned) Battle Drone: its turrets shoot the player's enemies.
AddCSLuaFile()
ENT.Base      = "snpc_battledrone"
ENT.PrintName = "Hacked Battle Drone"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_battledrone_hacked", {
	Name = "Hacked Battle Drone", Class = "snpc_battledrone_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 64,
})
