--[[-------------------------------------------------------------------------
	Ranger Manhack - an energy-shielded manhack that also shoots low-damage beams from its eyes.

	  * Shield: absorbs ShieldHealth damage, regenerates after ShieldRegenDelay seconds without being
	    hit. It is drawn as a translucent bubble in the colour of the eyes.
	  * Beams: every eye fires its own beam at the enemy in LOS, coloured like that eye's glow
	    (so per-eye colours via ENT.EyeColors give two-colour beams).
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Base      = "snpc_manhack"
ENT.PrintName = "Ranger Manhack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

-- shield
ENT.ShieldHealth     = 40
ENT.ShieldRegenDelay = 4      -- seconds without damage before it recharges
ENT.ShieldRegenRate  = 12     -- shield points per second
ENT.ShieldRadius     = 17
ENT.ShieldTint       = nil   -- nil = tint with the shield colour; set a Color(...) to force one
ENT.ShieldImpactProtection = 0.9   -- fraction of wall-impact damage the shield prevents
ENT.ShieldImpactDrain      = 0.6   -- fraction of the shield used up by such an impact

-- beams
ENT.BeamDamage   = 5          -- per beam (one beam per eye per volley)
ENT.BeamCooldown = 1.8        -- seconds between volleys
ENT.BeamDuration = 0.4        -- how long a beam is visible (it starts wide and contracts)
ENT.BeamRange    = 1100
ENT.BeamWidth    = 3
ENT.BeamFacing   = 25         -- degrees: it must face the target (horizontally) to fire
ENT.BeamSound    = "weapons/airboat/airboat_gun_energy1.wav"

ENT.EyeColor       = Color(0, 170, 255)
ENT.HackedEyeColor = Color(0, 255, 120)

list.Set("MachineMayhem", "snpc_ranger_manhack", {
	Name = "Ranger Manhack", Class = "snpc_ranger_manhack",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})

--=========================================================================
-- CLIENT: shield bubble + beams
--=========================================================================
if CLIENT then
	local Beams = {}

	net.Receive("PhysSNPC_RangerBeam", function()
		local from, to = net.ReadVector(), net.ReadVector()
		local c = net.ReadColor()
		local w, dur = net.ReadFloat(), net.ReadFloat()
		local now = CurTime()
		Beams[#Beams + 1] = { from = from, to = to, col = c, w = w, start = now, dur = dur }
	end)

	local beamMat   = Material("effects/laser1")
	local spriteMat = Material("sprites/light_glow02_add")
	hook.Add("PostDrawTranslucentRenderables", "PhysSNPC_RangerBeams", function()
		if #Beams == 0 then return end
		local now = CurTime()
		for i = #Beams, 1, -1 do
			local b = Beams[i]
			local t = (now - b.start) / b.dur
			if t >= 1 then
				table.remove(Beams, i)
			else
				local k = (1 - t) ^ 2                 -- starts big, contracts
				local w = b.w * (0.3 + 5 * k)
				render.SetMaterial(beamMat)
				render.DrawBeam(b.from, b.to, w, 0, 1, b.col)
				render.DrawBeam(b.from, b.to, w * 0.35, 0, 1, Color(255, 255, 255, 230 * (1 - t)))
				-- impact sprite in the beam colour
				render.SetMaterial(spriteMat)
				local sz = 10 + 46 * k
				render.DrawSprite(b.to, sz, sz, b.col)
				render.DrawSprite(b.to, sz * 0.4, sz * 0.4, Color(255, 255, 255, 200 * (1 - t)))
			end
		end
	end)

	local shieldMat = Material("effects/physhacks/comshieldwall_colorable")

	function ENT:Draw()
		self:DrawModel()
		local f = self:GetNWFloat("PhysShield", 0)
		if f <= 0.01 then return end
		local c = self:GetNWVector("PhysShieldCol", Vector(0, 170, 255))
		local hit = math.max(0, 1 - (CurTime() - self:GetNWFloat("PhysShieldHit", -10)) * 3)
		local a = math.min(255, (70 + 150 * hit) * (0.4 + 0.6 * f))
		local center, r = self:WorldSpaceCenter(), self.ShieldRadius

		render.SetMaterial(shieldMat)
		render.DrawSphere(center,  r, 18, 18, Color(c.x, c.y, c.z, a))
		render.DrawSphere(center, -r, 18, 18, Color(c.x, c.y, c.z, a * 0.5))

		-- extra faint tint so the shield stays visible in bright places
		local t = self.ShieldTint or Color(c.x, c.y, c.z)
		render.SetColorMaterial()
		render.DrawSphere(center, r * 1.02, 18, 18, Color(t.r, t.g, t.b, math.min(25, a * 0.12)))
	end
end

if not SERVER then return end

util.AddNetworkString("PhysSNPC_RangerBeam")

--=========================================================================
-- SERVER
--=========================================================================

function ENT:OnVariantSpawned()
	self.Shield = self.ShieldHealth
	self.NextShieldNW = 0
	self.NextBeam = 0
	self:SyncShield(true)
end

function ENT:SyncShield(force)
	local now = CurTime()
	if not force and now < self.NextShieldNW then return end
	self.NextShieldNW = now + 0.1
	self:SetNWFloat("PhysShield", self.Shield / self.ShieldHealth)
	local c = self:GetEyeColor("Eye")
	self:SetNWVector("PhysShieldCol", Vector(c.r, c.g, c.b))
end

-- soak up damage with the shield before health is touched
function ENT:AbsorbDamage(dmg)
	if self.Shield <= 0 then return end
	local amount = dmg:GetDamage()
	local soaked = math.min(self.Shield, amount)
	self.Shield = self.Shield - soaked
	self.ShieldHitTime = CurTime()
	dmg:SetDamage(amount - soaked)
	self:SetNWFloat("PhysShieldHit", CurTime())

	local ed = EffectData()
	ed:SetOrigin(dmg:GetDamagePosition():IsZero() and self:WorldSpaceCenter() or dmg:GetDamagePosition())
	ed:SetMagnitude(1) ed:SetScale(1) ed:SetRadius(1)
	util.Effect("ElectricSpark", ed)
	if self.Shield <= 0 then
		self:EmitSound("ambient/energy/zap" .. math.random(5, 9) .. ".wav", 75, 120)
	else
		self:EmitSound("ambient/energy/spark" .. math.random(1, 6) .. ".wav", 65, 140)
	end
	self:SyncShield(true)
end

-- the shield takes (most of) a wall impact instead of the hull
function ENT:AdjustImpactDamage(amount, speed)
	if self.Shield <= 0 then return amount end
	self.Shield = math.max(0, self.Shield - self.ShieldHealth * self.ShieldImpactDrain)
	self.ShieldHitTime = CurTime()
	self:SetNWFloat("PhysShieldHit", CurTime())
	local ed = EffectData()
	ed:SetOrigin(self:WorldSpaceCenter()) ed:SetMagnitude(2) ed:SetScale(2) ed:SetRadius(2)
	util.Effect("ElectricSpark", ed)
	self:EmitSound("ambient/energy/zap" .. math.random(5, 9) .. ".wav", 75, 110)
	self:SyncShield(true)
	return amount * (1 - self.ShieldImpactProtection)
end

function ENT:OnVariantThink(dt)
	-- recharge
	if self.Shield < self.ShieldHealth and CurTime() - (self.ShieldHitTime or -10) > self.ShieldRegenDelay then
		self.Shield = math.min(self.ShieldHealth, self.Shield + self.ShieldRegenRate * dt)
	end
	self:SyncShield()

	self:FireBeams()
end

function ENT:FireBeams()
	local now = CurTime()
	if now < self.NextBeam or self.Packed or self:IsStalled() or self.Held then return end
	local foe = self:GetFoe()
	if not IsValid(foe) then return end

	local aim = foe:WorldSpaceCenter()
	if self:GetPos():DistToSqr(aim) > self.BeamRange ^ 2 then return end

	-- must be facing the target (horizontally)
	local to2D = aim - self:GetPos()
	to2D.z = 0
	if to2D:LengthSqr() > 400 then
		local fwd = self:GetForward()
		fwd.z = 0
		fwd:Normalize()
		if fwd:Dot(to2D:GetNormalized()) < math.cos(math.rad(self.BeamFacing)) then return end
	end

	-- need a clear line to the target from the middle of the body
	local los = util.TraceLine({ start = self:WorldSpaceCenter(), endpos = aim, filter = { self, foe }, mask = MASK_SOLID_BRUSHONLY })
	if los.Hit then return end

	self.NextBeam = now + self.BeamCooldown

	for _, att in ipairs(self.EyeAttachments) do
		local id = self:LookupAttachment(att)
		local a = id and id > 0 and self:GetAttachment(id)
		if a then
			local dir = (aim - a.Pos):GetNormalized()
			local tr = util.TraceLine({
				start = a.Pos, endpos = a.Pos + dir * self.BeamRange,
				filter = self, mask = MASK_SHOT,
			})
			local c = self:GetEyeColor(att)

			net.Start("PhysSNPC_RangerBeam")
				net.WriteVector(a.Pos) net.WriteVector(tr.HitPos)
				net.WriteColor(Color(c.r, c.g, c.b, 255))
				net.WriteFloat(self.BeamWidth)
				net.WriteFloat(self.BeamDuration)
			net.Broadcast()

			local hit = tr.Entity
			if IsValid(hit) and not hit:IsWorld() and not self:IsFriendlyTo(hit) then
				local d = DamageInfo()
				d:SetAttacker(self) d:SetInflictor(self)
				d:SetDamage(self.BeamDamage)
				d:SetDamageType(DMG_ENERGYBEAM)
				d:SetDamagePosition(tr.HitPos)
				d:SetDamageForce(dir * 10)
				hit:TakeDamageInfo(d)
			end
			local ed = EffectData()
			ed:SetOrigin(tr.HitPos) ed:SetMagnitude(1) ed:SetScale(1) ed:SetRadius(1)
			util.Effect("ElectricSpark", ed)
		end
	end

	if not self.Silent then self:EmitSound(self.BeamSound, 70, 120, 0.8) end
end

function ENT:OnVariantDeath()
	self.Shield = 0
	self:SetNWFloat("PhysShield", 0)
end
