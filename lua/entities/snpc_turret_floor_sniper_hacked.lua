AddCSLuaFile()
ENT.Base      = "snpc_turret_floor_sniper"
ENT.PrintName = "Hacked Sniper Floor Turret"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked = true
list.Set("MachineMayhem", "snpc_turret_floor_sniper_hacked", {
	Name = "Hacked Sniper Floor Turret", Class = "snpc_turret_floor_sniper_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 0,
})
