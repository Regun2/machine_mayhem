AddCSLuaFile()
ENT.Base      = "snpc_turret_floor_heavy"
ENT.PrintName = "Hacked Heavy Floor Turret"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked = true
list.Set("MachineMayhem", "snpc_turret_floor_heavy_hacked", {
	Name = "Hacked Heavy Floor Turret", Class = "snpc_turret_floor_heavy_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 0,
})
