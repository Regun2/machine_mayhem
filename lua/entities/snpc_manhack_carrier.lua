--[[-------------------------------------------------------------------------
	Manhack Carrier - an invisible manhack body with four Combine props attached to it.
	It never attacks. When it spots a hostile it hangs back at a distance and launches waves of
	regular manhacks (hacked ones for the hacked carrier), up to DeployMax alive at once and
	Reserve in total. It is always destroyed in pieces (the props fall off as physics props).

	Everything here is a plain field: change the Attachments table to change how it looks.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Base      = "snpc_manhack"
ENT.PrintName = "Manhack Carrier"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

-- body: the manhack model is only the physics / collision body, it is not drawn
ENT.SpawnHealth   = 150
ENT.Model         = "models/props_combine/headcrabcannister01a.mdl" -- an invisible stand-in with no hitboxes (the manhack model's tiny hitboxes were what bullets / the physgun hit)
ENT.HullSize      = 38            -- navigation / trace hull
ENT.PhysBox      = { Vector(-46, -30, -20), Vector(25, 30, 30) } -- collision body AND hull (the HullSize above is only a fallback)
ENT.PhysMass     = 25
ENT.AllowGravGun = false         -- cannot be picked up or punted by the gravity gun
ENT.ImpactResistance = 0.85      -- fraction of wall-impact damage it shrugs off
ENT.MaxSpeed      = 220
ENT.MaxVertSpeed  = 120
ENT.EyeAttachments = {}          -- no glowing eyes
ENT.SwarmEnabled  = false
ENT.StartPacked   = false
ENT.ChargeMinDist = 0            -- never charges
ENT.BladeDamage   = 0
ENT.GibDamage     = 0            -- always breaks apart
ENT.GibModels     = { "models/gibs/manhack_gib01.mdl", "models/gibs/manhack_gib02.mdl", "models/gibs/manhack_gib03.mdl",
                      "models/gibs/manhack_gib04.mdl", "models/gibs/manhack_gib05.mdl" }
ENT.GibCount      = 16
ENT.EngineVolume  = 0.6
ENT.Pitch1 = { min = 45, max = 80, dist = 600, water = 40 }
ENT.Pitch2 = { min = 40, max = 70, dist = 500, water = 40 }

-- keeping its distance
ENT.KeepAwayMin = 450
ENT.KeepAwayMax = 800
ENT.HoverHeight = 170            -- above the enemy's feet

-- deploying
ENT.DeployClass       = "snpc_manhack"
ENT.DeployClassHacked = "snpc_manhack_hacked"
ENT.DeployCount    = 4           -- per wave
ENT.DeployStagger  = 0.3         -- seconds between launches within a wave
ENT.DeployInterval = 9           -- seconds between waves
ENT.DeployDelay    = 0.8         -- reaction time after spotting someone
ENT.DeployMax      = 10          -- manhacks alive at once
ENT.Reserve        = 16          -- total manhacks it carries
ENT.DeployOffset   = Vector(-62, 0, 4)     -- launch point (out of the back), relative to the carrier
ENT.DeploySound    = "npc/turret_floor/deploy.wav"

-- (glow = where the glow / light sits, in the prop's own space)
-- (indicator = true: tinted with the eye colour - red normal, green hacked - and glows / lights up in it)
-- the attached props (X Y Z = position, Pitch Yaw Roll = angles, relative to the carrier)
ENT.Attachments = {
	{ model = "models/combine_advisor_pod/combine_advisor_pod.mdl", pos = Vector(35, 0, 4),   ang = Angle(-90, 0, 0), scale = 0.3 },
	{ model = "models/props_combine/combine_light002a.mdl",         pos = Vector(-35, 20, -20), ang = Angle(0, -90, 0),  scale = 1, indicator = true, glow = Vector(-10, 0, 36) },
	{ model = "models/props_combine/combine_light002a.mdl",         pos = Vector(-35, -20, -20), ang = Angle(0, 90, 0),  scale = 1, indicator = true, glow = Vector(-10, 0, 36) },
	{ model = "models/props_combine/combine_ballsocket.mdl",        pos = Vector(-40, 0, 4),   ang = Angle(0, -180, 0), scale = 0.2 },
}

list.Set("MachineMayhem", "snpc_manhack_carrier", {
	Name = "Manhack Carrier", Class = "snpc_manhack_carrier",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 64,
})

--=========================================================================
-- CLIENT: the indicator lights light up their surroundings
--=========================================================================
if CLIENT then
	function ENT:Think()
		local c = self:GetNWVector("PhysIndicatorCol", Vector(255, 0, 0))
		for i, def in ipairs(self.Attachments) do
			if def.indicator then
				local d = DynamicLight(self:EntIndex() * 8 + i)
				if d then
					local o = Vector(def.glow or vector_origin)
					o:Rotate(def.ang)
					d.pos = self:LocalToWorld(def.pos + o)
					d.r, d.g, d.b = c.x, c.y, c.z
					d.brightness = 4
					d.size = 280
					d.decay = 600
					d.dietime = CurTime() + 0.2
				end
			end
		end
		self:SetNextClientThink(CurTime())
		return true
	end
end

if not SERVER then return end

--=========================================================================
-- SERVER
--=========================================================================

function ENT:OnVariantSpawned()
	-- invisible body
	self:SetRenderMode(RENDERMODE_TRANSALPHA)
	self:SetColor(Color(255, 255, 255, 0))
	self:DrawShadow(false)
	self:KillSprites()

	self.Props = {}
	for _, def in ipairs(self.Attachments) do
		local p = ents.Create("prop_dynamic")
		if IsValid(p) then
			p:SetModel(def.model)
			p:SetPos(self:LocalToWorld(def.pos))
			p:SetAngles(self:LocalToWorldAngles(def.ang))
			p:Spawn()
			p:SetSolid(SOLID_NONE)
			p:SetParent(self)
			p:SetLocalPos(def.pos)
			p:SetLocalAngles(def.ang)
			p:SetModelScale(def.scale, 0)
			if def.indicator then self:MakeIndicator(p, def) end
			self.Props[#self.Props + 1] = { ent = p, def = def }
		end
	end

	local ec = self:GetEyeColor("Eye")
	self:SetNWVector("PhysIndicatorCol", Vector(ec.r, ec.g, ec.b))

	self.Brood = {}
	self.NextDeploy = CurTime() + 1
	self.PropsDropped = false
end

-- tint a light prop with the eye colour and give it a glow
function ENT:MakeIndicator(prop, def)
	local c = self:GetEyeColor("Eye")
	prop:SetColor(Color(c.r, c.g, c.b, 255))
	local s = ents.Create("env_sprite")
	if IsValid(s) then
		s:SetKeyValue("model", self.GlowSprite)
		s:SetKeyValue("rendermode", "9")
		s:SetKeyValue("scale", "1")
		s:SetKeyValue("GlowProxySize", "4")
		s:SetKeyValue("spawnflags", "1")
		s:SetPos(prop:GetPos())
		s:Spawn()
		s:SetParent(prop)
		s:SetLocalPos(def.glow or vector_origin)
		s:SetColor(Color(c.r, c.g, c.b, 255))
		self.IndicatorSprites = self.IndicatorSprites or {}
		self.IndicatorSprites[#self.IndicatorSprites + 1] = s
	end
end

-- never cuts anything
function ENT:CanSlice(ent) return false end

function ENT:OnTargetAcquired(ent)
	self.NextDeploy = math.min(self.NextDeploy or 0, CurTime() + self.DeployDelay)
end

function ENT:LiveBrood()
	local n = 0
	for i = #self.Brood, 1, -1 do
		local m = self.Brood[i]
		if IsValid(m) and not m.Crashing then n = n + 1 else table.remove(self.Brood, i) end
	end
	return n
end

function ENT:DeployOne()
	if self.Crashing or self.Gibbed then return end
	local m = ents.Create(self.Hacked and self.DeployClassHacked or self.DeployClass)
	if not IsValid(m) then return end
	m:SetPos(self:LocalToWorld(self.DeployOffset))
	local ang = self:GetAngles()
	m:SetAngles(ang)
	m:Spawn()
	m:Activate()

	local kick = self:GetForward() * -170 + VectorRand() * 60 -- out of the back
	if m.CurVel then m.CurVel = m.CurVel + kick + self.CurVel * 0.5 end
	local phys = m:GetPhysicsObject()
	if IsValid(phys) then phys:SetVelocity(kick) end

	local foe = self:GetFoe()
	if IsValid(foe) and m.AcquireTarget then m:AcquireTarget(foe) end
	self.Brood[#self.Brood + 1] = m
end

function ENT:DeployWave()
	local n = math.min(self.DeployCount, self.Reserve, self.DeployMax - self:LiveBrood())
	if n <= 0 then return end
	self.Reserve = self.Reserve - n
	if not self.Silent then self:EmitSound(self.DeploySound, 75, 90) end
	for i = 1, n do
		timer.Simple((i - 1) * self.DeployStagger, function()
			if IsValid(self) then self:DeployOne() end
		end)
	end
end

function ENT:OnVariantThink(dt)
	local now = CurTime()
	if now < self.NextDeploy or self.Held then return end
	local foe = self:GetFoe()
	if not (IsValid(foe) and self.FoeVisible) then return end
	self.NextDeploy = now + self.DeployInterval
	self:DeployWave()
end

-- Stay away from the enemy at a comfortable height; never dive in.
function ENT:CombatMove(dt, enemy, chase)
	local pos = self:GetPos()
	if not (IsValid(enemy) and self.FoeVisible) then
		if chase and pos:Distance(chase) > self.KeepAwayMax then
			self:MoveToTarget(dt, self:SteerAround(chase, enemy))
		else
			self:Decelerate(dt, 3)
		end
		return
	end

	local ep = enemy:GetPos()
	local flat = Vector(ep.x - pos.x, ep.y - pos.y, 0)
	local d = flat:Length()
	local dir = d > 1 and flat / d or self:GetForward()
	local goalZ = ep.z + self.HoverHeight

	local target
	if d < self.KeepAwayMin then
		target = Vector(pos.x - dir.x * 220, pos.y - dir.y * 220, goalZ)
	elseif d > self.KeepAwayMax then
		target = Vector(pos.x + dir.x * 220, pos.y + dir.y * 220, goalZ)
	elseif math.abs(pos.z - goalZ) < 12 then
		self:Decelerate(dt, 2)
		return
	else
		target = Vector(pos.x, pos.y, goalZ)
	end
	self:MoveToTarget(dt, self:SteerAround(target))
end

-- it shrugs off most of a wall impact
function ENT:AdjustImpactDamage(amount, speed)
	return amount * (1 - self.ImpactResistance)
end

-- Break apart into a bunch of manhack gibs (the attached props just vanish).
function ENT:SpawnGibs(pos, baseVel)
	self.PropsDropped = true
	for _, p in ipairs(self.Props or {}) do
		if IsValid(p.ent) then p.ent:Remove() end
	end
	scripted_ents.GetStored("base_physics_snpc").t.SpawnGibs(self, pos, baseVel)
	-- a real explosion
	local ex = EffectData()
	ex:SetOrigin(pos) ex:SetScale(1) ex:SetMagnitude(1)
	util.Effect("Explosion", ex)
	util.BlastDamage(self, self, pos, self.ExplosionRadius or 150, self.ExplosionDamage or 60)
	local ed = EffectData()
	ed:SetOrigin(pos) ed:SetScale(2) ed:SetMagnitude(3) ed:SetRadius(3)
	util.Effect("ElectricSpark", ed)
end

function ENT:OnVariantDeath()
	if self.PropsDropped then return end
	self.PropsDropped = true
	for _, p in ipairs(self.Props or {}) do
		if IsValid(p.ent) then p.ent:Remove() end
	end
end
