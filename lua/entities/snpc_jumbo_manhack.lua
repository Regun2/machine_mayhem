--[[-------------------------------------------------------------------------
	Jumbo Manhack - boss. Built from the "Jumbo Manhack" dupe (headcrab canister body, helicopter bomb core, boiler,
	filing cabinet and canister at the back, six meat hooks as claws) on an invisible manhack body, plus the parts the
	workshop description lists: two big spinning saws, a gun in its eye, and a launch bay on top that deploys smaller
	manhacks (assassin and ranger manhacks; hacked ones for the hacked jumbo).

	Behaviour: it hangs back and shoots bursts from its eye gun; every few seconds it launches a wave of manhacks from
	its back, and now and then it charges its target with the saws (heavy slash damage to everything hostile in reach).
	Always breaks apart with an explosion.

	Everything is a plain field: change Attachments / Saws / the numbers below.
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base      = "snpc_manhack"
ENT.PrintName = "Jumbo Manhack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

-- body (the manhack model is only a hidden physics anchor; the collision body is the box)
ENT.IsBoss       = true
ENT.IsJumbo      = true
ENT.SpawnHealth  = 820
ENT.Model        = "models/props_combine/headcrabcannister01a.mdl" -- an invisible stand-in with no hitboxes
ENT.HullSize     = 44
ENT.PhysBox      = { Vector(-38, -38, -68), Vector(38, 38, 96) }
ENT.PhysMass     = 300
ENT.AllowGravGun = false
ENT.ImpactResistance = 0.8
ENT.EnginePower  = 1.5
ENT.HackedEnginePower = 1.5
ENT.MaxSpeed     = 280
ENT.PuntedMaxSpeed = 280
ENT.MaxVertSpeed = 170
ENT.EyeAttachments = {}
ENT.SwarmEnabled = false
ENT.StartPacked  = false
ENT.ChargeMinDist = 0
ENT.BladeDamage  = 0
ENT.GibDamage    = 0
ENT.GibModels = { "models/gibs/manhack_gib01.mdl", "models/gibs/manhack_gib02.mdl", "models/gibs/manhack_gib03.mdl",
                  "models/gibs/manhack_gib04.mdl", "models/gibs/manhack_gib05.mdl", "models/gibs/metal_gib1.mdl",
                  "models/gibs/metal_gib2.mdl", "models/gibs/metal_gib3.mdl" }
ENT.GibCount     = 22
ENT.EngineVolume = 0.8
ENT.Pitch1 = { min = 40, max = 70, dist = 700, water = 35 }
ENT.Pitch2 = { min = 35, max = 60, dist = 600, water = 35 }
ENT.ExplosionDamage = 90
ENT.ExplosionRadius = 220

-- the dupe's props in the Jumbo's own frame: it stands upright like a manhack (up = the top where the boiler and
-- cabinet launch bay sit, forward = the way the combine-bomb eye looks). The canister is the body.
ENT.Attachments = {
	{ model = "models/props_combine/headcrabcannister01a.mdl", pos = Vector(0, 0, 0), ang = Angle(90, 0, 0) },
	{ model = "models/props_c17/furnitureboiler001a.mdl", pos = Vector(-13.7, 1.8, 49.6), ang = Angle(-0.2, -88.3, 2), col = 109 },
	{ model = "models/props_lab/filecabinet02.mdl",       pos = Vector(1, -0.7, 61.7),    ang = Angle(2.8, 0.6, -0.1), col = 36, shiny = true },
	{ model = "models/props_c17/canister01a.mdl",         pos = Vector(-2.7, 3.9, 32.7),  ang = Angle(-21.9, -171.6, 88), col = 109 },
	{ model = "models/combine_helicopter/helicopter_bomb01.mdl", pos = Vector(10.1, 0.9, 13.7), ang = Angle(85.3, 138.3, 136.1), eye = true },
	-- the two rotors: three hooks each, they spin around the up axis like a manhack's blades (rotor = 1 / 2)
	{ model = "models/props_junk/meathook001a.mdl", pos = Vector(16.9, 30.6, -22.3),  ang = Angle(-87.9, -171.1, -122.3), col = 36, shiny = true, rotor = 1 },
	{ model = "models/props_junk/meathook001a.mdl", pos = Vector(-33, -1.6, -24.3),   ang = Angle(-87.8, -170.6, 1.5),    col = 36, shiny = true, rotor = 1 },
	{ model = "models/props_junk/meathook001a.mdl", pos = Vector(18, -29.1, -22.5),   ang = Angle(-88.6, 170.7, 136.3),   col = 36, shiny = true, rotor = 1 },
	{ model = "models/props_junk/meathook001a.mdl", pos = Vector(32.9, 7.1, -2.2),    ang = Angle(-87.8, -165.6, 179.5),  col = 36, shiny = true, rotor = 2 },
	{ model = "models/props_junk/meathook001a.mdl", pos = Vector(-23, 27.3, -3.7),    ang = Angle(-88, -165.5, -56.3),    col = 36, shiny = true, rotor = 2 },
	{ model = "models/props_junk/meathook001a.mdl", pos = Vector(-13.9, -30, -3.8),   ang = Angle(-88.7, -144.3, 38.7),   col = 36, shiny = true, rotor = 2 },
}

-- the rotors cut everything hostile within reach of their centre (z = height of the rotor, spin = deg / s, sign = direction)
ENT.Saws = {
	{ z = -22.3, reach = 56, spin = 2200 },    -- spin = degrees per second at full speed (drawn on the client, so it is smooth)
	{ z = -3.5,  reach = 56, spin = -2800 },
}
ENT.RotorIdle = 0.25                           -- fraction of full spin speed while it has no target
ENT.SawDamage   = 70
ENT.SawInterval = 0.3

-- the eye gun (bullets leave from the eye)
ENT.EyeCenter  = Vector(10.1, 0.9, 13.7)      -- the combine bomb
ENT.EyeMaterial = nil                         -- material for the bomb (the hacked version sets one)
ENT.EyeReach   = 15                            -- bullets, glow and spotlight start 15 units out along the bomb's own Z axis, wherever it points
ENT.EyeMaxAngle = 80                           -- how far the eye can look away from the body's forward (degrees)
ENT.EyeTurnSpeed = 240                         -- degrees per second
ENT.EyeLightColor = Color(255, 40, 40)         -- like the city scanner's spotlight (green when hacked)
ENT.EyeLightRange = 900
ENT.GunDamage  = 7
ENT.GunRange   = 1600
ENT.GunNear    = 380
ENT.GunFar     = 700
ENT.BurstSize  = 8
ENT.ShotRate   = 8
ENT.BurstPause = 1.4
ENT.GunSpread  = 3
ENT.FaceTol    = 30
ENT.EyeGlowPos = Vector(20, 0.9, 13.7)

-- saw charge
ENT.SawChargeTime = 5
ENT.SawChargeEvery = 12

-- launch bay (on top / at the back)
ENT.DeployClasses       = { "snpc_assassinhack", "snpc_ranger_manhack" }
ENT.DeployClassesHacked = { "snpc_assassinhack_hacked", "snpc_ranger_manhack_hacked" }
ENT.DeployCount    = 2
ENT.DeployStagger  = 0.5
ENT.DeployInterval = 8
ENT.DeployDelay    = 1
ENT.DeployMax      = 6
ENT.Reserve        = 14
ENT.DeployOffset   = Vector(-14, 2, 108)
ENT.DeploySound    = "npc/turret_floor/deploy.wav"

list.Set("MachineMayhem", "snpc_jumbo_manhack", {
	Name = "Jumbo Manhack", Class = "snpc_jumbo_manhack", Group = "Bosses",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 70,
})

--=========================================================================
-- CLIENT: spinning rotors (client-side models, so any spin speed looks smooth) and the eye's spotlight
--=========================================================================
if CLIENT then

	local function AddMat(name, tex)
		local src = Material(tex)
		local t = src and src:GetTexture("$basetexture")
		if t then tex = t:GetName() end
		return CreateMaterial(name, "UnlitGeneric", {
			["$basetexture"] = tex, ["$additive"] = 1, ["$vertexcolor"] = 1, ["$vertexalpha"] = 1, ["$nocull"] = 1,
		})
	end
	local halo = AddMat("mm_jumbo_halo", "sprites/light_glow02")
	local beam = AddMat("mm_jumbo_beam", "sprites/glow_test02")

	local function DrawCone(from, to, width, col)
		local dir = to - from
		local len = dir:Length()
		if len < 1 then return end
		dir = dir / len
		local right = dir:Cross(EyePos() - (from + to) * 0.5)
		if right:LengthSqr() < 0.0001 then return end
		right:Normalize()
		local h = width * 0.5
		render.SetMaterial(beam)
		mesh.Begin(MATERIAL_QUADS, 1)
		local function V(p, u, v)
			mesh.Position(p) mesh.TexCoord(0, u, v)
			mesh.Color(col.r, col.g, col.b, col.a)
			mesh.AdvanceVertex()
		end
		V(from - right * h, 0, 0)
		V(from + right * h, 1, 0)
		V(to + right * h, 1, 1)
		V(to - right * h, 0, 1)
		mesh.End()
	end

	function ENT:Draw() end -- the manhack body is invisible; the props are real entities

	function ENT:RemoveRotors()
		for _, r in ipairs(self.CSRotors or {}) do if IsValid(r.model) then r.model:Remove() end end
		self.CSRotors = nil
	end

	function ENT:OnRemove() self:RemoveRotors() end

	-- drawn from a hook, not from the entity: the body itself is invisible and the engine skips drawing such entities
	function ENT:DrawExtras()
		local now = CurTime()
		-- rotors
		if not self.CSRotors then
			self.CSRotors = {}
			self.RotAng = { 0, 0 }
			self.RotSpeed = { 0, 0 }
			for _, def in ipairs(self.Attachments) do
				if def.rotor then
					local m = ClientsideModel(def.model, RENDERGROUP_OPAQUE)
					if IsValid(m) then
						m:SetNoDraw(true)
						self.CSRotors[#self.CSRotors + 1] = { model = m, def = def }
					end
				end
			end
		end
		local dt = FrameTime()
		local active = self:GetNWBool("MMActive", false)
		local fn = FrameNumber()
		if self.RotFrame ~= fn then   -- (this can be called more than once per frame: step the rotors only once)
			self.RotFrame = fn
			self.RotStep = { 0, 0 }
			for i, sw in ipairs(self.Saws) do
				local want = sw.spin * (active and 1 or self.RotorIdle)
				self.RotSpeed[i] = Lerp(math.min(1, dt * 2.5), self.RotSpeed[i], want)
				self.RotStep[i] = self.RotSpeed[i] * dt
				self.RotAng[i] = (self.RotAng[i] + self.RotStep[i]) % 360
			end
		end
		-- a few fading copies trailing behind each hook (motion blur): at this speed one sharp copy per frame
		-- looks slow or even stationary from some angles
		local GHOSTS = 4
		for _, r in ipairs(self.CSRotors) do
			if IsValid(r.model) then
				local base = self.RotAng[r.def.rotor]
				local step = self.RotStep[r.def.rotor] or 0
				local col = r.def.col and (r.def.col / 255 * 1.6) or 0.4   -- dark metal
				render.SetColorModulation(col, col, col * 1.05)
				for g = GHOSTS, 0, -1 do
					local th = base - step * (g / GHOSTS) * 1.5
					local p = Vector(r.def.pos)
					p:Rotate(Angle(0, th, 0))
					r.model:SetPos(self:LocalToWorld(p))
					r.model:SetAngles(self:LocalToWorldAngles(Angle(r.def.ang.p, r.def.ang.y + th, r.def.ang.r)))
					render.SetBlend(g == 0 and 1 or 0.22)
					r.model:DrawModel()
				end
				render.SetBlend(1)
				render.SetColorModulation(1, 1, 1)
			end
		end

		-- the eye's spotlight, like the city scanner's
		if self:GetNWBool("MMEyeOn", false) then
			-- follow the bomb model itself: its position and its own Z axis (Up)
			local prop = self:GetNWEntity("MMEyeProp")
			local origin, d
			if IsValid(prop) then
				d = prop:GetUp()
				origin = prop:GetPos() + d * self.EyeReach
			else
				d = self:GetNWVector("MMEyeDir", self:GetForward()):GetNormalized()
				origin = self:LocalToWorld(self.EyeCenter) + d * self.EyeReach
			end
			local tr = util.TraceLine({ start = origin, endpos = origin + d * self.EyeLightRange, mask = MASK_SOLID_BRUSHONLY })
			local c = self.EyeLightColor
			local dist = origin:Distance(tr.HitPos)
			local w = math.Clamp(dist * 0.18, 40, 140)
			DrawCone(origin, tr.HitPos, w, Color(c.r, c.g, c.b, 200))
			render.SetMaterial(halo)
			render.DrawSprite(origin, 60, 60, Color(c.r, c.g, c.b, 255))
			local dl = DynamicLight(self:EntIndex())
			if dl then
				dl.pos = tr.HitPos
				dl.r, dl.g, dl.b = c.r, c.g, c.b
				dl.brightness = 1.2
				dl.size = 170
				dl.decay = 400
				dl.dietime = now + 0.1
			end
		end
	end

	hook.Add("PostDrawTranslucentRenderables", "MM_JumboExtras", function(depth, sky)
		if depth or sky then return end
		for _, e in ipairs(ents.GetAll()) do
			if IsValid(e) and e.IsJumbo and e.DrawExtras and not e:IsDormant() then e:DrawExtras() end
		end
	end)
end

if not SERVER then return end

function ENT:CanSlice(ent) return false end -- the saws are handled below

function ENT:OnVariantSpawned()
	self:SetRenderMode(RENDERMODE_TRANSALPHA)
	self:SetColor(Color(255, 255, 255, 0))
	self:DrawShadow(false)
	self:KillSprites()

	self.Props = {}
	local function Attach(model, pos, ang, scale)
		local p = ents.Create("prop_dynamic")
		if not IsValid(p) then return end
		p:SetModel(model)
		p:SetPos(self:LocalToWorld(pos))
		p:SetAngles(self:LocalToWorldAngles(ang))
		p:Spawn()
		p:SetSolid(SOLID_NONE)
		p:SetParent(self)
		p:SetLocalPos(pos)
		p:SetLocalAngles(ang)
		if scale and scale ~= 1 then p:SetModelScale(scale, 0) end
		self.Props[#self.Props + 1] = p
		return p
	end

	self.Rotors = {}
	for _, def in ipairs(self.Attachments) do
		if not def.rotor then -- (the rotor hooks are drawn by the client)
			local p = Attach(def.model, def.pos, def.ang, def.scale)
			if IsValid(p) then
				if def.col then p:SetColor(Color(def.col, def.col, def.col, 255)) end
				if def.shiny then p:SetMaterial("models/shiny") end
				if def.eye then
					self.EyeProp = p
					self.EyeBaseAng = def.ang
					-- (the hacked jumbo has a green bomb; only used when that material is installed)
					if self.EyeMaterial and file.Exists("materials/" .. self.EyeMaterial .. ".vmt", "GAME") then p:SetMaterial(self.EyeMaterial) end
				end
			end
		end
	end
	self.EyeYaw, self.EyePitch = 0, 0
	self:SetNWBool("MMEyeOn", true)

	self.Brood = {}
	self.DeployIndex = 0
	self.NextDeploy = CurTime() + 2
	self.GunLeft = 0
	self.NextGunShot = CurTime() + 1.5
	self.StrafeDir = math.random() < 0.5 and 1 or -1
	self.NextStrafe = 0
	self.NextSaw = 0
	self.SawChargeUntil = 0
	self.NextSawCharge = CurTime() + math.Rand(6, self.SawChargeEvery)
	self.PropsDropped = false
end

--=========================================================================
-- launch bay
--=========================================================================
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
	local list_ = self.Hacked and self.DeployClassesHacked or self.DeployClasses
	self.DeployIndex = (self.DeployIndex % #list_) + 1
	local m = ents.Create(list_[self.DeployIndex])
	if not IsValid(m) then return end
	m:SetPos(self:LocalToWorld(self.DeployOffset))
	m:SetAngles(self:GetAngles())
	m:Spawn()
	m:Activate()
	local kick = self:GetUp() * 240 + VectorRand() * 70
	if m.CurVel and self.CurVel then m.CurVel = m.CurVel + kick + self.CurVel * 0.5 end
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
	if not self.Silent then self:EmitSound(self.DeploySound, 80, 70) end
	for i = 1, n do
		timer.Simple((i - 1) * self.DeployStagger, function()
			if IsValid(self) then self:DeployOne() end
		end)
	end
end

--=========================================================================
-- eye gun
--=========================================================================
function ENT:GunMuzzle()
	local d = self.EyeDir or self:GetForward()
	return self:LocalToWorld(self.EyeCenter) + d * self.EyeReach
end

-- the eye looks at the target (up to EyeMaxAngle away from the body's forward), or sweeps around when idle
function ENT:UpdateEye(dt, foe)
	local ty, tp = 0, 0
	if IsValid(foe) then
		local rel = self:WorldToLocal(foe:WorldSpaceCenter()) - self.EyeCenter
		local a = rel:Angle()
		ty, tp = math.NormalizeAngle(a.y), math.NormalizeAngle(a.p)
	else
		ty = math.sin(CurTime() * 0.5) * 45
		tp = math.sin(CurTime() * 0.31) * 15
	end
	local m = self.EyeMaxAngle
	ty, tp = math.Clamp(ty, -m, m), math.Clamp(tp, -m, m)
	local step = self.EyeTurnSpeed * dt
	self.EyeYaw = self.EyeYaw + math.Clamp(ty - self.EyeYaw, -step, step)
	self.EyePitch = self.EyePitch + math.Clamp(tp - self.EyePitch, -step, step)

	local eyeAng = Angle(self.EyePitch, self.EyeYaw, 0)
	self.EyeDir = self:LocalToWorldAngles(eyeAng):Forward()
	self:SetNWVector("MMEyeDir", self.EyeDir)
	if IsValid(self.EyeProp) then self:SetNWEntity("MMEyeProp", self.EyeProp) end
	-- the bomb itself turns with it
	if IsValid(self.EyeProp) then
		local m1, m2 = Matrix(), Matrix()
		m1:SetAngles(eyeAng)
		m2:SetAngles(self.EyeBaseAng)
		self.EyeProp:SetLocalAngles((m1 * m2):GetAngles())
	end
end

function ENT:FireGun(foe, now)
	if now < self.NextGunShot then return end
	local muzzle = self:GunMuzzle()
	local target = foe:WorldSpaceCenter()
	local to = target - muzzle
	if to:Length() > self.GunRange then return end
	-- only fires when the eye is actually pointing at the target
	if not self.EyeDir or self.EyeDir:Dot(to:GetNormalized()) < math.cos(math.rad(8)) then return end

	if self.GunLeft <= 0 then self.GunLeft = self.BurstSize end
	self.GunLeft = self.GunLeft - 1
	self.NextGunShot = now + (self.GunLeft > 0 and 1 / self.ShotRate or self.BurstPause + math.Rand(0, 0.6))

	local s = math.sin(math.rad(self.GunSpread * 0.5))
	self:FireBullets({
		Attacker = self, Inflictor = self, Damage = self.GunDamage, Force = 1, Num = 1,
		Src = muzzle, Dir = self.EyeDir, Spread = Vector(s, s, 0), Tracer = 1, TracerName = "AR2Tracer",
		AmmoType = "AR2",
	})
	if not self.Silent then self:EmitSound("weapons/smg1/smg1_fire1.wav", 80, math.random(80, 95), 0.8) end
	local ed = EffectData()
	ed:SetOrigin(muzzle) ed:SetNormal(to:GetNormalized()) ed:SetScale(1)
	util.Effect("MuzzleEffect", ed)
end

--=========================================================================
-- saws
--=========================================================================
function ENT:SawHit(now)
	if now < self.NextSaw then return end
	local hit = false
	for _, s in ipairs(self.Saws) do
		local c = self:LocalToWorld(Vector(0, 0, s.z))
		for _, e in ipairs(ents.FindInSphere(c, s.reach * 1.5)) do
			if e ~= self and IsValid(e) and (e:IsNPC() or e:IsPlayer() or e:IsNextBot()) and self:GetDisposition(e) == D_HT
				and not (e:IsPlayer() and not e:Alive()) then
				-- horizontal distance to the rotor's axis, and within the rotor's height band
				local rel = self:WorldToLocal(e:WorldSpaceCenter())
				if math.sqrt(rel.x * rel.x + rel.y * rel.y) <= s.reach and math.abs(rel.z - s.z) <= 45 then
					local d = DamageInfo()
					d:SetDamage(self.SawDamage)
					d:SetDamageType(DMG_SLASH)
					d:SetAttacker(self)
					d:SetInflictor(self)
					d:SetDamagePosition(e:WorldSpaceCenter())
					d:SetDamageForce((e:WorldSpaceCenter() - c):GetNormalized() * 8000)
					e:TakeDamageInfo(d)
					hit = true
				end
			end
		end
	end
	if hit then
		self.NextSaw = now + self.SawInterval
		if not self.Silent then self:EmitSound("NPC_Manhack.Slice") end
	end
end

function ENT:OnVariantThink(dt)
	local now = CurTime()
	if self.Held or self.Crashing then return end
	local foe = self:GetFoe()
	local seen = IsValid(foe) and self.FoeVisible

	self:SetNWBool("MMActive", IsValid(foe))
	self:UpdateEye(dt, foe)
	self:SawHit(now)

	if not seen then self.GunLeft = 0 return end

	-- launch a wave
	if now >= self.NextDeploy then
		self.NextDeploy = now + self.DeployInterval
		self:DeployWave()
	end
	-- now and then charge with the saws; the gun is quiet while it does
	if now >= self.NextSawCharge then
		self.SawChargeUntil = now + self.SawChargeTime
		self.NextSawCharge = now + self.SawChargeEvery + math.Rand(0, 4)
	end
	if now >= self.SawChargeUntil then self:FireGun(foe, now) end
end

-- Hold a firing distance and strafe; charge into the target while the saw charge lasts.
function ENT:CombatMove(dt, enemy, chase)
	local now = CurTime()
	local pos = self:GetPos()
	if not (IsValid(enemy) and self.FoeVisible) then
		if chase then self:MoveToTarget(dt, self:SteerAround(chase, enemy)) else self:Decelerate(dt, 3) end
		return
	end
	local fc = enemy:WorldSpaceCenter()
	if now < self.SawChargeUntil then
		self:MoveToTarget(dt, self:SteerAround(fc, enemy))
		return
	end
	local flat = Vector(fc.x - pos.x, fc.y - pos.y, 0)
	local d = flat:Length()
	local dir = d > 1 and flat / d or self:GetForward()
	if now >= self.NextStrafe then
		self.NextStrafe = now + math.Rand(2, 4)
		self.StrafeDir = -self.StrafeDir
	end
	local goal = pos + Vector(dir.y, -dir.x, 0) * self.StrafeDir * 100
	if d > self.GunFar then goal = goal + dir * 240 elseif d < self.GunNear then goal = goal - dir * 240 end
	goal.z = fc.z + 130
	self:MoveToTarget(dt, self:SteerAround(goal, enemy))
end

function ENT:AdjustImpactDamage(amount, speed)
	return amount * (1 - self.ImpactResistance)
end

--=========================================================================
-- destruction
--=========================================================================
function ENT:SpawnGibs(pos, baseVel)
	self.PropsDropped = true
	for _, p in ipairs(self.Props or {}) do if IsValid(p) then p:Remove() end end
	scripted_ents.GetStored("base_physics_snpc").t.SpawnGibs(self, pos, baseVel)
	local ex = EffectData()
	ex:SetOrigin(pos) ex:SetScale(2) ex:SetMagnitude(2)
	util.Effect("Explosion", ex)
	sound.Play("weapons/explode" .. math.random(3, 5) .. ".wav", pos, 95, 90)
	util.BlastDamage(self, self, pos, self.ExplosionRadius, self.ExplosionDamage)
	local ed = EffectData()
	ed:SetOrigin(pos) ed:SetScale(3) ed:SetMagnitude(4) ed:SetRadius(4)
	util.Effect("ElectricSpark", ed)
end

function ENT:OnVariantDeath()
	if self.PropsDropped then return end
	self.PropsDropped = true
	for _, p in ipairs(self.Props or {}) do if IsValid(p) then p:Remove() end end
	self:SetNWBool("MMEyeOn", false)
end
