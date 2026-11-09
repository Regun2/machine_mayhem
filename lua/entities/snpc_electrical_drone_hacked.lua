-- Hacked (rebel-aligned) Electrical Drone.
AddCSLuaFile()
ENT.Base      = "snpc_electrical_drone"
ENT.PrintName = "Hacked Electrical Drone"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_electrical_drone_hacked", {
	Name = "Hacked Electrical Drone", Class = "snpc_electrical_drone_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})
