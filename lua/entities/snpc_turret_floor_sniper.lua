-- Sniper floor turret: sees much further, aims slowly and precisely, fires about once every 1.5 s, and every shot hurts.
AddCSLuaFile()
ENT.Base      = "snpc_turret_floor"
ENT.PrintName = "Sniper Floor Turret"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.SpawnHealth = 80
ENT.SightRange  = 4000
ENT.SightFOV    = 110
ENT.FireRate    = 0.65
ENT.ConeDeg     = 0.4
ENT.AimSpeed    = 80
ENT.AimDot      = 0.9997
ENT.BulletDamage = 35        -- (the normal floor turret does 3)
ENT.TracerName  = "AR2Tracer"
ENT.Laser       = true       -- a thin aiming laser
ENT.GlowScale   = 1.3
ENT.TurretColor = Color(255, 215, 215)

list.Set("MachineMayhem", "snpc_turret_floor_sniper", {
	Name = "Sniper Floor Turret", Class = "snpc_turret_floor_sniper",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 0,
})
