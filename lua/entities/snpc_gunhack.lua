--[[-------------------------------------------------------------------------
	Gunhack - a manhack that shoots instead of cutting. Its blades are scaled to 0.75 and never hurt anything;
	a gunship nose gun (models/gibs/gunship_gibs_nosegun.mdl, scale 0.25) is bolted to its camera bone and the
	bullets leave from the barrel of that model. It hovers at a distance, strafes and fires short bursts.
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base      = "snpc_manhack"
ENT.PrintName = "Gunhack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.BladeDamage = 0
ENT.BladeScale  = 0.75
ENT.EyeAttachments = { "Light" } -- the bottom light ("Eye", on the camera bone) is switched off

ENT.GunModel = "models/gibs/gunship_gibs_nosegun.mdl"
ENT.GunBone  = "Manhack.MH_ControlCamera"
ENT.GunScale = 0.25
ENT.GunPos   = Vector(-1.6, 1.25, 3)
ENT.GunAng   = Angle(-90, 0, 0)

ENT.GunDamage   = 4
ENT.GunRange    = 1200
ENT.GunNear     = 260      -- backs off when closer than this
ENT.GunFar      = 480      -- closes in when farther than this
ENT.BurstSize   = 6
ENT.ShotRate    = 11       -- shots per second inside a burst
ENT.BurstPause  = 1.1      -- seconds between bursts
ENT.GunSpread   = 3        -- degrees (cone)
ENT.FaceTol     = 35       -- degrees: it must face the target to fire

list.Set("MachineMayhem", "snpc_gunhack", {
	Name = "Gunhack", Class = "snpc_gunhack",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})

if not SERVER then return end

function ENT:CanSlice() return false end -- no blade attacks

function ENT:OnVariantSpawned()
	-- smaller blades
	for i = 0, (self:GetBoneCount() or 0) - 1 do
		local n = self:GetBoneName(i)
		if n and string.find(string.lower(n), "blade", 1, true) then
			self:ManipulateBoneScale(i, Vector(self.BladeScale, self.BladeScale, self.BladeScale))
		end
	end

	-- the nose gun on the camera bone
	local bone = self:LookupBone(self.GunBone)
	local g = ents.Create("prop_dynamic")
	if IsValid(g) then
		g:SetModel(self.GunModel)
		g:SetPos(self:GetPos())
		g:Spawn()
		g:SetModelScale(self.GunScale, 0)
		g:SetSolid(SOLID_NONE)
		g:SetMoveType(MOVETYPE_NONE)
		g:SetParent(self)
		if bone and bone >= 0 then g:FollowBone(self, bone) end
		g:SetLocalPos(self.GunPos)
		g:SetLocalAngles(self.GunAng)
		self.Gun = g
	end
	self.GunLeft = 0
	self.NextGunShot = CurTime() + 1
	self.StrafeDir = math.random() < 0.5 and 1 or -1
	self.NextStrafe = 0
end

-- barrel tip: the end of the gun model's longest axis that points the way the manhack faces
function ENT:GunMuzzle()
	local g = self.Gun
	if not IsValid(g) then return self:WorldSpaceCenter() end
	if not self.GunAxis then
		local mn, mx = g:GetModelBounds()
		local size = mx - mn
		local ax = (size.x >= size.y and size.x >= size.z) and "x" or ((size.y >= size.z) and "y" or "z")
		self.GunAxis = { ax = ax, mn = mn * self.GunScale, mx = mx * self.GunScale }
	end
	local a = self.GunAxis
	local c = (a.mn + a.mx) * 0.5
	local lo, hi = Vector(c), Vector(c)
	lo[a.ax], hi[a.ax] = a.mn[a.ax], a.mx[a.ax]
	local p1, p2 = g:LocalToWorld(lo), g:LocalToWorld(hi)
	local f = self:GetForward()
	return (p2 - p1):Dot(f) >= 0 and p2 or p1
end

function ENT:CombatMove(dt, enemy, chase)
	local now = CurTime()
	local pos = self:GetPos()
	if not (IsValid(enemy) and self.FoeVisible) then
		self:MoveToTarget(dt, self:SteerAround(chase, enemy))
		return
	end
	local fc = enemy:WorldSpaceCenter()
	local flat = fc - pos
	flat.z = 0
	local d = flat:Length()
	local dir = d > 1 and flat / d or self:GetForward()
	if now >= self.NextStrafe then
		self.NextStrafe = now + math.Rand(1.5, 3.5)
		self.StrafeDir = -self.StrafeDir
	end
	local goal = pos + Vector(dir.y, -dir.x, 0) * self.StrafeDir * 140
	if d > self.GunFar then goal = goal + dir * 200 elseif d < self.GunNear then goal = goal - dir * 200 end
	goal.z = fc.z + 40
	self:MoveToTarget(dt, self:SteerAround(goal, enemy))
end

function ENT:OnVariantThink(dt)
	local now = CurTime()
	if self.Packed or self.Held or self.Crashing then return end
	local foe = self:GetFoe()
	if not (IsValid(foe) and self.FoeVisible) then self.GunLeft = 0 return end
	if now < self.NextGunShot then return end

	local muzzle = self:GunMuzzle()
	local target = foe:WorldSpaceCenter()
	local to = target - muzzle
	if to:Length() > self.GunRange then return end
	local yawDiff = math.abs(math.AngleDifference((target - self:GetPos()):Angle().y, self:GetAngles().y))
	if yawDiff > self.FaceTol then return end

	if self.GunLeft <= 0 then self.GunLeft = self.BurstSize end
	self.GunLeft = self.GunLeft - 1
	self.NextGunShot = now + (self.GunLeft > 0 and 1 / self.ShotRate or self.BurstPause + math.Rand(0, 0.5))

	local s = math.sin(math.rad(self.GunSpread * 0.5))
	self:FireBullets({
		Attacker = self, Inflictor = self, Damage = self.GunDamage, Force = 1, Num = 1,
		Src = muzzle, Dir = to:GetNormalized(), Spread = Vector(s, s, 0), Tracer = 1, TracerName = "Tracer",
		AmmoType = "AR2", IgnoreEntity = self.Gun,
	})
	if not self.Silent then self:EmitSound("weapons/smg1/smg1_fire1.wav", 70, math.random(135, 150), 0.7) end
	local ed = EffectData()
	ed:SetOrigin(muzzle) ed:SetNormal(to:GetNormalized()) ed:SetScale(0.5)
	util.Effect("MuzzleEffect", ed)
end

function ENT:OnVariantDeath()
	if IsValid(self.Gun) then self.Gun:Remove() end
end
