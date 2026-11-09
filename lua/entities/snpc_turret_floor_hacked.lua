AddCSLuaFile()
ENT.Base      = "snpc_turret_floor"
ENT.PrintName = "Hacked Floor Turret"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked = true
ENT.Laser = true

list.Set("MachineMayhem", "snpc_turret_floor_hacked", {
	Name = "Hacked Floor Turret", Class = "snpc_turret_floor_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 0,
})
