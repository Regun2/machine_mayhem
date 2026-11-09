AddCSLuaFile()
ENT.Base      = "base_turret_snpc"
ENT.PrintName = "Floor Turret"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.TurretKind = "floor"
ENT.Model = "models/combine_turrets/floor_turret.mdl"
ENT.SpawnHealth = 100
ENT.SightRange = 1200
ENT.SightFOV = 133
ENT.FireRate = 10
ENT.ConeDeg = 10
ENT.AmmoType = "Pistol"
ENT.TracerName = "Tracer"
ENT.DamageConVar = "sk_npc_dmg_pistol"
ENT.DamageDefault = 3
ENT.AllowGravGun = true
ENT.Tippable = true
ENT.StaticProp = true
ENT.PhysMass = 25 -- light enough for the hands (+use)
ENT.DeathDelay = 0.4
ENT.ExplosionDamage = 60
ENT.ExplosionRadius = 80
ENT.Sounds = {
	Deploy = "NPC_FloorTurret.Deploy", Retire = "NPC_FloorTurret.Retire", Alert = "NPC_FloorTurret.Alert",
	Ping = "NPC_FloorTurret.Ping", Die = "NPC_FloorTurret.Die", Shot = "NPC_FloorTurret.ShotSounds",
	Alarm = "NPC_FloorTurret.Alarm", Activate = "NPC_FloorTurret.Activate",
}

list.Set("MachineMayhem", "snpc_turret_floor", {
	Name = "Floor Turret", Class = "snpc_turret_floor",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 0,
})
