--[[-------------------------------------------------------------------------
	Super Rollermine - twice the size, much heavier (and so slower), with a really powerful zap:
	60 shock damage, huge knockback, a wide beam, and the discharge arcs on to every other enemy around
	whatever it hit (half damage).
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base      = "snpc_rollermine"
ENT.PrintName = "Super Rollermine"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.ModelScale       = 2
ENT.HullSize         = 26
ENT.GroundRadius     = 25
ENT.PhysSphereRadius = 25      -- collision is a sphere (a scaled model keeps its unscaled mesh)
ENT.PhysMass         = 500     -- heavy (normal one: the model's own mass)
ENT.SpawnHealth      = 60
ENT.SoundPitch       = 0.7     -- deeper voice
ENT.BlastsToDetonate = 2       -- survives the first explosion

ENT.MaxRollSpeed     = 300
ENT.MaxSpeed         = 300
ENT.MaxTorqueFactor  = 3
ENT.OpenDist         = 340
ENT.OpenDistVehicle  = 480
ENT.TauntDist        = 500
ENT.StickForceLimit  = 40000

-- the zap
ENT.ShockDamage      = 60
ENT.ShockKnock       = 1500
ENT.RecoilSpeed      = 450     -- how hard it is thrown back itself (the ball is heavy)
ENT.ShockRadius      = 170     -- chains to everything hostile this close to the victim
ENT.ZapMode          = 2       -- the wide beam + lingering tesla
ENT.StunDelay        = 2.5
ENT.ExplodeDamage    = 60
ENT.PrimedDamage     = 150
ENT.PoweredDownDamage = 100
ENT.ExplodeRadius    = 220

-- client look (tesla scaled up with the ball)
ENT.EffectScale      = 2
ENT.ArcWidth         = 2.2
ENT.ArcAmp           = 1.6

list.Set("MachineMayhem", "snpc_rollermine_super", {
	Name = "Super Rollermine", Class = "snpc_rollermine_super",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 32,
})
