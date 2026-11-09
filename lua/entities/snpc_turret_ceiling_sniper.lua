-- Sniper ceiling turret: sees much further, aims slowly and precisely, fires about once every 1.5 s, and every shot hurts.
AddCSLuaFile()
ENT.Base      = "snpc_turret_ceiling"
ENT.PrintName = "Sniper Ceiling Turret"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.SpawnHealth  = 600
ENT.SightRange   = 4000
ENT.SightFOV     = 360
ENT.FireRate     = 0.65
ENT.ConeDeg      = 0.4
ENT.AimSpeed     = 80
ENT.AimDot       = 0.9997
ENT.BulletDamage = 35
ENT.TracerName   = "AR2Tracer"
ENT.Laser        = true
ENT.AimHigh      = true   -- aims at the head, not the middle of the body
ENT.GlowScale    = 1.3
ENT.TurretColor  = Color(255, 215, 215)

list.Set("MachineMayhem", "snpc_turret_ceiling_sniper", {
	Name = "Sniper Ceiling Turret", Class = "snpc_turret_ceiling_sniper",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 0,
})
