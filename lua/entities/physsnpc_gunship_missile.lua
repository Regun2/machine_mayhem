--[[-------------------------------------------------------------------------
	Gunship missile - sandbox version of Hunter's Glee's "glee_gunshipmissile" (no Glee needed): a dumbfire missile that
	hangs out of the pod for a second, then screams off. Flown by hand (no physics), so the hit traces see the whole path.
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Type = "anim"
ENT.PrintName = "Gunship Missile"
ENT.Spawnable = false

ENT.StartSpeed = 3
ENT.IgnitionTime = 1.02
ENT.IgnitionAccel = 350
ENT.BurnAccel = 2000
ENT.MaxSpeed = 4000
ENT.WarnTime = 1.2
ENT.MaxLifetime = 12

function ENT:SetupDataTables()
	self:NetworkVar("Float", 0, "LaunchTime")
	self:NetworkVar("Bool", 0, "Detonated")
	self:NetworkVar("Bool", 1, "Exploded")
end

function ENT:SpeedAt(age)
	if age <= self.IgnitionTime then return self.StartSpeed + self.IgnitionAccel * age end
	local v = self.StartSpeed + self.IgnitionAccel * self.IgnitionTime
	return math.min(v + self.BurnAccel * (age - self.IgnitionTime), self.MaxSpeed)
end

if SERVER then
	local hullMaxs = Vector(5, 5, 5)
	local hullMins = -hullMaxs
	local blastMagnitudes = { 150, 75 } -- (env_explosion radius is 2.5x this)
	local dangerRadius = 500

	function ENT:TimeToFly(dist)
		local step, age, flown = 0.05, 0, 0
		while flown < dist and age < self.MaxLifetime do
			flown = flown + self:SpeedAt(age) * step
			age = age + step
		end
		return age
	end

	function ENT:Initialize()
		self:SetModel("models/weapons/w_missile_launch.mdl")
		self:SetModelScale(0.8)
		self:SetColor(Color(170, 195, 220))
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_NONE)
		self:DrawShadow(false)
		self:SetLaunchTime(CurTime())
		self.lastThink = CurTime()
		util.SpriteTrail(self, 0, Color(255, 255, 255), true, 3, 0, 0.5, 1 / 3 * 0.5, "trails/laser")
		util.SpriteTrail(self, 0, Color(170, 220, 255), true, 6, 0, 0.3, 1 / 6 * 0.5, "trails/laser")
		util.SpriteTrail(self, 0, Color(150, 165, 190, 90), false, 10, 100, 4, 1 / 110 * 0.5, "trails/smoke")
		self:WarnWhereItLands()
		self:NextThink(CurTime())
	end

	function ENT:HitTrace(a, b)
		return util.TraceHull({ start = a, endpos = b, filter = { self, self:GetOwner() }, mins = hullMins, maxs = hullMaxs, mask = MASK_SHOT })
	end

	-- it never turns, so where it lands is known now: everything nearby gets a head start running
	function ENT:WarnWhereItLands()
		local p = self:GetPos()
		local r = self:HitTrace(p, p + self:GetForward() * 40000)
		if r.HitSky or not r.Hit then return end
		sound.EmitHint(SOUND_DANGER, r.HitPos, dangerRadius, self:TimeToFly(p:Distance(r.HitPos)) + 0.5, self)
	end

	function ENT:Detonate(hitPos, hitSky)
		self:SetDetonated(true)
		self:SetPos(hitPos)
		SafeRemoveEntityDelayed(self, 4)
		if hitSky then return end
		self:SetExploded(true)
		local owner = self:GetOwner()
		for _, m in ipairs(blastMagnitudes) do
			local ex = ents.Create("env_explosion")
			ex:SetPos(hitPos)
			ex:SetOwner(owner)
			ex:SetKeyValue("iMagnitude", m)
			ex:Spawn()
			ex:Fire("Explode")
		end
	end

	function ENT:Think()
		if self:GetDetonated() then return end
		local cur = CurTime()
		local age = cur - self:GetLaunchTime()
		if age > self.MaxLifetime then self:Detonate(self:GetPos()) return end
		if not self.incomingSound and age > self.WarnTime then
			self.incomingSound = CreateSound(self, "weapons/mortar/mortar_shell_incomming1.wav")
			self.incomingSound:SetSoundLevel(140)
			self.incomingSound:PlayEx(1, 70)
			self.incomingSound:ChangePitch(90, 1)
		end
		local dt = cur - self.lastThink
		self.lastThink = cur
		local p = self:GetPos()
		local np = p + self:GetForward() * self:SpeedAt(age) * dt
		local r = self:HitTrace(p, np)
		if r.Hit then self:Detonate(r.HitPos, r.HitSky) return end
		self:SetPos(np)
		self:NextThink(cur)
		return true
	end

	function ENT:OnRemove()
		if self.incomingSound then self.incomingSound:Stop() end
	end
else
	local glowMat = Material("sprites/light_glow02_add")
	local glowColor = Color(150, 210, 255)
	local flareColor = Color(255, 255, 255)

	local function Flash(pos, size, brightness, life, index)
		local l = DynamicLight(index)
		if not l then return end
		l.pos = pos l.r, l.g, l.b = 150, 210, 255
		l.brightness = brightness l.size = size l.decay = size / life l.dietime = CurTime() + life
	end

	function ENT:Draw()
		if self:GetDetonated() then return end
		self:DrawModel()
		local age = CurTime() - self:GetLaunchTime()
		local size
		if age < self.IgnitionTime then size = math.Rand(8, 24)
		elseif age < self.IgnitionTime + 0.15 then size = 160
		else size = 48 + math.sin(CurTime() * 40) * 8 end
		local fwd, p = self:GetForward(), self:GetPos()
		render.SetMaterial(glowMat)
		render.DrawSprite(p - fwd * 12, size, size, glowColor)
		render.DrawSprite(p - fwd * 20, size * 0.5, size * 0.5, flareColor)
		local facing = math.max(fwd:Dot((EyePos() - p):GetNormalized()), 0)
		if facing > 0 then render.DrawSprite(p - fwd * 24, size * facing * 2.5, size * facing * 0.3, flareColor) end
	end

	function ENT:Think()
		local age = CurTime() - self:GetLaunchTime()
		if self:GetDetonated() then
			if self.engineSound then self.engineSound:Stop() self.engineSound = nil end
			if self:GetExploded() and not self.didFlash then
				self.didFlash = true
				Flash(self:GetPos(), 1200, 6, 0.5, self:EntIndex())
			end
			return
		end
		if not self.didIgnite and age >= self.IgnitionTime then
			self.didIgnite = true
			self:EmitSound("weapons/cguard/charging.wav", 75, 140, 1, CHAN_STATIC)
			Flash(self:GetPos(), 400, 3, 0.15, self:EntIndex())
		end
		local pitch = math.Clamp(self:SpeedAt(age) * 0.03, 20, 150)
		if not self.engineSound and self:GetPos():DistToSqr(LocalPlayer():EyePos()) < 2500 ^ 2 then
			self.engineSound = CreateSound(self, "Missile.Ignite")
			self.engineSound:PlayEx(1, pitch)
		elseif self.engineSound then
			self.engineSound:ChangePitch(pitch, 0.1)
		end
	end

	function ENT:OnRemove()
		if self.engineSound then self.engineSound:Stop() end
	end
end
