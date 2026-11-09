AddCSLuaFile()
ENT.Base      = "snpc_turret_ceiling_heavy"
ENT.PrintName = "Hacked Heavy Ceiling Turret"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked = true
list.Set("MachineMayhem", "snpc_turret_ceiling_heavy_hacked", {
	Name = "Hacked Heavy Ceiling Turret", Class = "snpc_turret_ceiling_heavy_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 0,
})
