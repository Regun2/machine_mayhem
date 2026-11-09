--[[-------------------------------------------------------------------------
	Battle Drone - a combat variant of the City Scanner, ported from the "CUP" battle-drone addon code:
	  * a 0.4 scale headcrab-canister body, 200 health, no spotlight, no camera flash, much faster than a scanner
	  * four recreated ceiling turrets (snpc_turret_ceiling, mounted) (0.2 scale, parented, non-solid) and a thruster mounted at the back
	  * each turret fires on its own: enemies within 250 units that it can see take 5-10 shock damage
	    (instant hit with a tracer), then that turret waits 1-4 s
	  * spark + metal clang when hit, a tesla / flash effect when it spawns, drowns after 3 s under water
	Not ported: patrol-node mode, "follow the player" commander mode, companion convar.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Base      = "snpc_scanner"
ENT.PrintName = "Battle Drone"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.Model       = "models/props_combine/headcrabcannister01a.mdl"
ENT.ModelScale  = 0.4
ENT.SpawnHealth = 200
ENT.HullSize    = 16
ENT.PhysBox     = { Vector(-30, -10, -10), Vector(30, 10, 10) } -- collision body AND hull (the HullSize above is only a fallback)

-- faster than a scanner (the original sets flight speed 2000; that is wild for a physics body, so 600 x2 in combat)
ENT.MaxSpeed         = 600
ENT.CombatSpeedScale = 2
ENT.MaxVertSpeed     = 450
ENT.AccelAligned     = 600
ENT.AccelTurning     = 300
ENT.AccelVertical    = 600

-- hover at turret range instead of photo range
ENT.PhotoNear = 120
ENT.PhotoFar  = 200
ENT.AttackNearDist = 150
ENT.AttackFarDist  = 250

ENT.TurretScale    = 0.2
ENT.TurretDamageScale = 0.5
ENT.EngineModel    = "models/props_combine/headcrabcannister01a_skybox.mdl"
-- local offsets (forward, left, up) and roll, as in the original
ENT.TurretMounts = {
	{ Vector(-10,  6, -4),  45 },
	{ Vector(-10, -6, -4), -45 },
	{ Vector(-10,  3,  5), 135 },
	{ Vector(-10, -3,  5), -135 },
}
ENT.EngineMount = Vector(-18, 0, -0.5)

ENT.GibModels = { "models/gibs/metal_gib1.mdl", "models/gibs/metal_gib2.mdl", "models/gibs/metal_gib3.mdl",
                  "models/gibs/metal_gib4.mdl", "models/gibs/metal_gib5.mdl" }
ENT.GibCount      = 5
ENT.BatteryChance = 0
ENT.ExplosionDamage = 80
ENT.ExplosionRadius = 90

list.Set("MachineMayhem", "snpc_battledrone", {
	Name = "Battle Drone", Class = "snpc_battledrone",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 64,
})

--=========================================================================
-- CLIENT: thruster flame at the back
--=========================================================================
if CLIENT then
	ENT.RenderGroup = RENDERGROUP_BOTH

	local function AddMat(name, tex)
		local src = Material(tex)
		local t = src and src:GetTexture("$basetexture")
		if t then tex = t:GetName() end
		return CreateMaterial(name, "UnlitGeneric", {
			["$basetexture"] = tex, ["$additive"] = 1, ["$vertexcolor"] = 1, ["$vertexalpha"] = 1, ["$nocull"] = 1,
		})
	end
	local glow = AddMat("pm_drone_glow_a", "sprites/light_glow02")

	function ENT:Draw()
		self:DrawModel()
	end

	function ENT:DrawTranslucent()
		self:DrawModel()
		local speed = math.Clamp(self:GetVelocity():Length() / 600, 0, 1)
		local back = -self:GetForward()
		local origin = self:LocalToWorld(self.EngineMount + Vector(-3, 0, 0))
		local flick = math.Rand(0.8, 1.2)
		render.SetMaterial(glow)
		render.DrawSprite(origin, (16 + 12 * speed) * flick, (16 + 12 * speed) * flick, Color(120, 170, 255, 255))
		render.DrawSprite(origin + back * 6, (22 + 20 * speed) * flick, (22 + 20 * speed) * flick, Color(60, 110, 255, 200))
		render.DrawSprite(origin, 8 * flick, 8 * flick, Color(255, 255, 255, 255))
		local d = DynamicLight(self:EntIndex())
		if d then
			d.pos = origin + back * 8
			d.r, d.g, d.b = 80, 130, 255
			d.brightness = 1
			d.size = 90 + 60 * speed
			d.decay = 500
			d.dietime = CurTime() + 0.1
		end
	end
end

if not SERVER then return end

local function Base(name)
	local b = scripted_ents.GetStored("snpc_scanner")
	return b and b.t and b.t[name]
end

-- never any spotlight or camera flash: this one fights
function ENT:SpotlightWanted() return false end
function ENT:WantsFlashAttack(d2) return false end
function ENT:TakePhoto(foe) self.NextPhoto = CurTime() + 9999 end

-- our recreated ceiling turret (snpc_turret_ceiling[_hacked]), mounted: no physics, never targets the drone
local function MakeTurret(self, pos, roll, scale)
	local t = ents.Create(self.Hacked and "snpc_turret_ceiling_hacked" or "snpc_turret_ceiling")
	if not IsValid(t) then return end
	t.Mounted = true
	t.MountOwner = self
	t.DamageScale = self.TurretDamageScale or 0.5
	t:SetModelScale(scale, 0)
	t:SetPos(self:LocalToWorld(pos))
	t:SetAngles(self:LocalToWorldAngles(Angle(0, 0, roll or 0)))
	t:Spawn()
	t:Activate()
	t:SetParent(self)
	t:SetLocalPos(pos)
	t:SetLocalAngles(Angle(0, 0, roll or 0))
	t.MountLocalPos = Vector(pos)
	t.MountLocalAng = Angle(0, 0, roll or 0)
	return t
end

local function MakeProp(self, model, pos, roll, scale)
	local p = ents.Create("prop_dynamic")
	if not IsValid(p) then return end
	p:SetModel(model)
	p:SetPos(self:LocalToWorld(pos))
	p:SetAngles(self:LocalToWorldAngles(Angle(0, 0, roll or 0)))
	p:Spawn()
	if scale then p:SetModelScale(scale, 0) end
	p:SetSolid(SOLID_NONE)
	p:SetParent(self)
	p:SetLocalPos(pos)
	p:SetLocalAngles(Angle(0, 0, roll or 0))
	return p
end

function ENT:OnScannerSpawned()
	self.Turrets, self.TurretNext = {}, {}
	for i, m in ipairs(self.TurretMounts) do
		self.Turrets[i] = MakeTurret(self, m[1], m[2], self.TurretScale)
		self.TurretNext[i] = CurTime() + math.Rand(1, 3)
	end
	self.EngineProp = MakeProp(self, self.EngineModel, self.EngineMount, 0)

	self.WaterSince = nil

	-- spawn-in effects
	self:EmitSound("ambient/energy/whiteflash.wav", 70, 100)
	local ed = EffectData()
	ed:SetStart(self:GetPos()) ed:SetOrigin(self:GetPos()) ed:SetMagnitude(1) ed:SetEntity(self)
	util.Effect("propspawn", ed)

	local tes = ents.Create("point_tesla")
	if IsValid(tes) then
		tes:SetPos(self:GetPos())
		tes:SetKeyValue("m_SoundName", "DoSpark")
		tes:SetKeyValue("texture", "sprites/combineball_trail_blue_1.spr")
		tes:SetKeyValue("m_Color", "255 255 255")
		tes:SetKeyValue("m_flRadius", "100")
		tes:SetKeyValue("beamcount_max", "10")
		tes:SetKeyValue("thick_min", "15")
		tes:SetKeyValue("thick_max", "30")
		tes:SetKeyValue("lifetime_min", "0.1")
		tes:SetKeyValue("lifetime_max", "0.3")
		tes:SetKeyValue("interval_min", "0.1")
		tes:SetKeyValue("interval_max", "0.2")
		tes:Spawn()
		for t = 0.1, 1.3, 0.2 do tes:Fire("DoSpark", "", t) end
		tes:Fire("kill", "", 1.3)
	end
end

function ENT:OnScannerThink(dt)
	local now = CurTime()
	-- drowns after 3 s under water
	if self:WaterLevel() >= 3 then
		self.WaterSince = self.WaterSince or now
		if now - self.WaterSince > 3 and not self.Crashing then
			self:EmitSound("ambient/energy/zap" .. math.random(1, 3) .. ".wav", 70)
			self:InflictDamage(self:Health() + 10, game.GetWorld(), game.GetWorld(), DMG_DROWN)
		end
	else
		self.WaterSince = nil
	end
end

function ENT:OnDamaged(dmg)
	Base("OnDamaged")(self, dmg)
	local ed = EffectData()
	ed:SetOrigin(dmg:GetDamagePosition() ~= vector_origin and dmg:GetDamagePosition() or self:GetPos())
	ed:SetMagnitude(1) ed:SetScale(1) ed:SetRadius(1)
	util.Effect("ElectricSpark", ed)
	self:EmitSound("physics/metal/metal_solid_impact_bullet" .. math.random(1, 4) .. ".wav", 70, math.random(90, 110))
end

function ENT:OnScannerRemoved()
	for _, t in ipairs(self.Turrets or {}) do if IsValid(t) then t:Remove() end end
	if IsValid(self.EngineProp) then self.EngineProp:Remove() end
end
