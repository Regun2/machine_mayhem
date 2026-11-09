AddCSLuaFile()
ENT.Base      = "base_turret_snpc"
ENT.PrintName = "Ceiling Turret"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.TurretKind = "ceiling"
ENT.AimSignY = 1 -- fixed aim directions for this hanging model
ENT.AimSignP = 1
ENT.AimLearn = false -- fixed signs, no runtime learning
ENT.Model = "models/combine_turrets/ceiling_turret.mdl"
ENT.SpawnHealth = 1000
ENT.SightRange = 1500
ENT.SightFOV = 360
ENT.FireRate = 10
ENT.ConeDeg = 8
ENT.DeathDelay = 1
ENT.ExplosionDamage = 100
ENT.ExplosionRadius = 100

list.Set("MachineMayhem", "snpc_turret_ceiling", {
	Name = "Ceiling Turret", Class = "snpc_turret_ceiling",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 0,
})
