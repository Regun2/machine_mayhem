--[[-------------------------------------------------------------------------
	Rollermine - Half-Life 2 npc_rollermine recreated as a physics SNPC with rolling ground physics
	(base_physics_snpc, Locomotion = "ground"). Ported from Valve's npc_rollermine.cpp:

	  * Rolls by spinning itself (angular acceleration 1200 deg/s^2 x a torque factor that ramps from 1 to 5
	    while it keeps charging at its target), so it really rolls over the ground.
	  * Opens its spikes (swaps to roller_spikes.mdl, hops) within 256 units of its enemy (400 vs. vehicles),
	    closes again when it overshoots or loses the enemy.
	  * Spikes shock whatever they touch: knockback 600, damage, then it is stunned for StunDelay seconds.
	    Combine soldiers at half health or less are killed outright, others lose half their max health.
	  * Explodes (25 damage, 100 when primed, 50 when powered down, radius 128) when burned / blown up or when
	    its health runs out (after a short Hurt chirp), and when it falls into water.
	  * Sticks to player vehicles (weld) and jolts them.
	  * Gravity gun: held mines do nothing; a punted open mine shocks whatever it hits.
	  * Hacked version (CLASS_HACKED_ROLLERMINE): friendly to the player, follows the player around, shorter stun.
	  * "PowerDown" input: flashes open/closed, then detonates.

	Not ported: burying / emerging, dropship embedding, the NPC-chirp network between mines.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Base      = "base_physics_snpc"
ENT.Type      = "ai"
ENT.PrintName = "Rollermine"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

-- body
ENT.Model          = "models/roller.mdl"
ENT.OpenModel      = "models/roller_spikes.mdl"
ENT.SpawnHealth    = 35        -- (Valve's mine only takes physics damage; here it can be shot to death -> it detonates)
ENT.HullSize       = 13
ENT.GroundRadius   = 14
ENT.Locomotion     = "ground"
ENT.NPCClass       = CLASS_COMBINE
ENT.HackedNPCClass = CLASS_HACKED_ROLLERMINE
ENT.HeldNPCClass   = CLASS_HACKED_ROLLERMINE
ENT.LinearDamping  = 0.05
ENT.AngularDamping = 0.3
ENT.SightRange     = 2048
ENT.SightFOV       = 270
ENT.SenseRange     = 300
ENT.ForgetTime     = 12
ENT.GibDamage      = 99999     -- never gibs, it explodes instead
ENT.ImpactSpeed    = 800

-- rolling (see sv_ground.lua)
ENT.RollAccel      = 1200
ENT.MaxRollSpeed   = 420
ENT.MaxSpeed       = 420

-- behaviour
ENT.OpenDist        = 256     -- opens its spikes this close to the enemy
ENT.OpenDistVehicle = 400
ENT.TauntDist       = 400
ENT.IsRollermine    = true
ENT.MaxTorqueFactor = 3.5       -- ROLLERMINE_MAX_TORQUE_FACTOR
ENT.ShockDamage     = 10      -- sk_rollermine_shock (skill.cfg value)
ENT.StunDelay       = 3       -- sk_rollermine_stun_delay (skill.cfg value)
ENT.HackedStunDelay = 0.1
ENT.ShockKnock      = 600
ENT.ShockCooldown   = 1.25
ENT.ExplodeDamage   = 25
ENT.PrimedDamage    = 100
ENT.PoweredDownDamage = 50
ENT.ExplodeRadius   = 128
ENT.StickForceLimit = 12000
ENT.FollowDist      = 200     -- hacked: starts rolling to the player beyond this
ENT.StopDist        = 80      -- ...and stops within this

list.Set("MachineMayhem", "snpc_rollermine", {
	Name = "Rollermine", Class = "snpc_rollermine",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 16,
})

--=========================================================================
-- CLIENT: electric glow while the spikes are live (port of c_npc_rollermine.cpp)
--=========================================================================
if CLIENT then
	-- additive copy of a vmt's texture, so the sprites never get a black background
	local function AddFrom(vmt, id)
		local src = Material(vmt)
		local tex = src and src:GetTexture("$basetexture")
		return CreateMaterial(id, "UnlitGeneric", {
			["$basetexture"] = tex and tex:GetName() or vmt,
			["$additive"] = 1, ["$vertexcolor"] = 1, ["$vertexalpha"] = 1, ["$nocull"] = 1,
		})
	end
	local glow    = AddFrom("effects/rollerglow", "pm_roller_glow_a")
	local beam    = AddFrom("sprites/lgtning", "pm_roller_tesla_a")
	local zapMat  = AddFrom("sprites/rollermine_shock", "pm_roller_zap_a")
	local zapYel  = AddFrom("sprites/rollermine_shock_yellow", "pm_roller_zapy_a")

	function ENT:Draw()
		self:DrawModel()
	end

	-- the points the tesla arcs jump between: the spike attachments (bones as a fallback)
	function ENT:GetSparkPoints()
		local mdl = self:GetModel()
		if self.SparkMdl ~= mdl then
			self.SparkMdl = mdl
			local n = #self:GetAttachments()
			self.SparkAtt = n >= 2 and n or 0
			self.SparkBones = self:GetBoneCount() or 0
		end
		return self.SparkAtt, self.SparkBones
	end

	function ENT:SparkPos(i, att, bones)
		if att > 0 then
			local a = self:GetAttachment(i)
			if a then return a.Pos end
		end
		if bones > 1 then
			local p = self:GetBonePosition(i % bones)
			if p then return p end
		end
		return self:GetPos() + VectorRand() * 8
	end

	-- TE_BEAMTESLA: a jagged beam, re-jittered every frame
	local function Tesla(p1, p2, w0, w1, amp, col)
		local segs = 4
		render.SetMaterial(beam)
		render.StartBeam(segs + 1)
		for i = 0, segs do
			local f = i / segs
			local p = LerpVector(f, p1, p2)
			if i > 0 and i < segs then p = p + VectorRand() * amp end
			render.AddBeam(p, Lerp(f, w0, w1), f, col)
		end
		render.EndBeam()
	end

	local function Small(p, scale, power, hacked, tint)
		local r = math.Rand(1, 1.5) * scale * 2
		local c
		if tint then local k = math.Rand(0.4, 1) c = Color(tint.r * k, tint.g * k, tint.b * k)
		elseif power then c = Color(255 * math.Rand(0.8, 1), 255 * math.Rand(0.1, 0.25), 0)
		elseif hacked then c = Color(255 * math.Rand(0.25, 0.75), 255 * math.Rand(0.1, 0.25), 0)
		else local v = 255 * math.Rand(0.25, 0.5) c = Color(v, v, v) end
		render.SetMaterial(glow)
		render.DrawSprite(p, r, r, Color(c.r * 0.6, c.g * 0.6, c.b * 0.6, 255))
	end

	-- Sonic: layered lightning trail behind it while it is fast (much stronger during a spindash dash)
	function ENT:DrawLightningTrail(now)
		local dash = self:GetNWBool("PhysDash", false)
		local life = dash and 0.7 or 0.4
		local pts = self.TrailPts
		if not pts then pts = {} self.TrailPts = pts end
		local pos = self:GetPos()
		local moving = self:GetVelocity():Length() > 250
		if FrameTime() > 0 and moving then
			local last = pts[#pts]
			if not last or now - last.t > 0.02 then pts[#pts + 1] = { p = pos, t = now } end
		end
		while pts[1] and now - pts[1].t > life do table.remove(pts, 1) end
		local n = #pts
		local c = self.TrailColor or Color(255, 255, 255)

		if n >= 2 then
			local strands = dash and 4 or 2
			local amp = dash and 9 or 5
			local w0 = dash and 20 or 11
			render.SetMaterial(beam)
			for s = 1, strands do
				render.StartBeam(n + 1)
				for i = 1, n do
					local a = pts[i]
					local f = 1 - (now - a.t) / life
					render.AddBeam(a.p + VectorRand() * amp * f, (w0 * f + 1) * (0.5 + 0.5 * math.random()), i / n * 2,
						Color(c.r, c.g, c.b, 255 * f))
				end
				render.AddBeam(pos, w0, 2, Color(c.r, c.g, c.b, 255))
				render.EndBeam()
			end
			-- white-hot, straight core
			render.StartBeam(n + 1)
			for i = 1, n do
				local a = pts[i]
				local f = 1 - (now - a.t) / life
				render.AddBeam(a.p, (w0 * 0.35) * f + 0.5, i / n * 2, Color(255, 255, 255, 255 * f))
			end
			render.AddBeam(pos, w0 * 0.4, 2, Color(255, 255, 255, 255))
			render.EndBeam()
			-- soft glow along the path
			render.SetMaterial(glow)
			for i = 1, n, 2 do
				local a = pts[i]
				local f = 1 - (now - a.t) / life
				local sz = (dash and 56 or 34) * f
				render.DrawSprite(a.p, sz, sz, Color(c.r, c.g, c.b, 110 * f))
			end
			-- forks branching off the trail
			if FrameTime() > 0 then
				for _ = 1, (dash and 5 or 2) do
					local a = pts[math.random(1, n)]
					Tesla(a.p, a.p + VectorRand() * math.Rand(25, dash and 90 or 55), dash and 6 or 4, 1, 5,
						Color(c.r, c.g, c.b, 220))
				end
			end
		end
		if moving then
			render.SetMaterial(glow)
			local hs = (dash and 80 or 44) * math.Rand(0.85, 1.15)
			render.DrawSprite(pos, hs, hs, Color(c.r, c.g, c.b, 200))
		end
	end

	-- Sonic: arcs crackling around it while the spindash charges (more and longer as it winds up)
	function ENT:DrawSpinCharge(now)
		local t = math.Clamp((now - self:GetNWFloat("PhysSpinStart", 0)) / (self.SpinChargeTime or 1.1), 0, 1)
		local c = self.TrailColor or Color(255, 255, 255)
		local pos = self:GetPos()
		for _ = 1, 3 + math.floor(t * 6) do
			local dir = VectorRand()
			dir.z = math.Rand(-0.7, 0.3)
			dir:Normalize()
			local tr = util.TraceLine({ start = pos, endpos = pos + dir * math.Rand(30, 55 + 45 * t),
				filter = self, mask = MASK_SOLID })
			Tesla(pos, tr.HitPos, math.Rand(5, 8) * (0.6 + t), 1.5, 6, Color(c.r, c.g, c.b, 255))
		end
		-- a ring of short arcs skittering over the ground under it
		for _ = 1, 2 + math.floor(t * 4) do
			local a = math.Rand(0, 360)
			local from = pos + Angle(0, a, 0):Forward() * 12 - Vector(0, 0, 10)
			local to = pos + Angle(0, a + math.Rand(-40, 40), 0):Forward() * math.Rand(40, 70) - Vector(0, 0, 12)
			Tesla(from, to, 4, 1, 4, Color(255, 255, 255, 230))
		end
		render.SetMaterial(glow)
		local g = (40 + 80 * t) * math.Rand(0.9, 1.1)
		render.DrawSprite(pos, g, g, Color(c.r, c.g, c.b, 150 + 100 * t))
		render.DrawSprite(pos, g * 0.4, g * 0.4, Color(255, 255, 255, 255))
		local d = DynamicLight(self:EntIndex())
		if d then
			d.pos = pos
			d.r, d.g, d.b = c.r, c.g, c.b
			d.brightness = 1 + 2 * t
			d.size = 120 + 160 * t
			d.decay = 600
			d.dietime = now + 0.1
		end
	end

	-- Overcharged: it also arcs to random geometry / objects around it
	function ENT:DrawWorldArcs(now, att, bones, count, bc)
		if count < 1 then return end
		self.WArcs = self.WArcs or {}
		if FrameTime() > 0 and now >= (self.NextWArc or 0) then
			self.NextWArc = now + math.Rand(0.12, 0.3)
			for _ = 1, 5 do
				local i1 = math.random(1, count)
				local p = self:SparkPos(i1, att, bones)
				local dir = VectorRand()
				dir:Normalize()
				local tr = util.TraceLine({ start = p, endpos = p + dir * math.Rand(70, 160), filter = self, mask = MASK_SOLID })
				if tr.Hit and not tr.StartSolid then
					self.WArcs[#self.WArcs + 1] = { i1 = i1, pos = tr.HitPos, die = now + 0.12,
						w0 = math.Rand(9, 13), amp = math.Rand(2, 4) }
					local ed = EffectData()
					ed:SetOrigin(tr.HitPos) ed:SetNormal(tr.HitNormal) ed:SetMagnitude(1) ed:SetScale(1) ed:SetRadius(1)
					util.Effect("ElectricSpark", ed)
					break
				end
			end
		end
		for k = #self.WArcs, 1, -1 do
			local a = self.WArcs[k]
			if now > a.die then
				table.remove(self.WArcs, k)
			else
				Tesla(self:SparkPos(a.i1, att, bones), a.pos, a.w0, 2, a.amp, bc)
				render.SetMaterial(glow)
				render.DrawSprite(a.pos, 26, 26, Color(110, 130, 200, 255))
			end
		end
	end

	-- Valve creates one 0.1 s beam per frame, so several arcs are alive at once
	function ENT:DrawRollerElectric(now)
		local power  = self:GetNWBool("PhysPowerDown", false)
		local hacked = self:GetNWBool("PhysHacked", false)
		local scale  = math.Rand(4, 6) * (self.EffectScale or 1)
		local origin = self:GetPos()
		local att, bones = self:GetSparkPoints()
		local count = att > 0 and att or bones
		local bc = power and Color(255, 64, 64) or ((self.ForceArcColor and self.ArcColor) or (hacked and Color(240, 200, 80) or (self.ArcColor or Color(255, 255, 255))))

		self.Arcs = self.Arcs or {}
		if self.Overcharged then self:DrawWorldArcs(now, att, bones, count, bc) end
		-- every prong shoots an arc to a random other prong, all at once, re-rolled every 0.08 s
		if FrameTime() > 0 and count >= 2 and now >= (self.NextArc or 0) then
			self.NextArc = now + 0.08
			self.Arcs = {}
			local wm, am = self.ArcWidth or 1, self.ArcAmp or 1
			for n = 1, count * (self.ArcMul or 1) do
				local i1 = (n - 1) % count + 1
				local i2 = math.random(1, count - 1)
				if i2 >= i1 then i2 = i2 + 1 end
				self.Arcs[#self.Arcs + 1] = {
					i1 = i1, i2 = i2, die = now + 0.1,
					w0 = math.Rand(6, 9) * wm, w1 = math.Rand(2, 4) * wm, amp = math.Rand(2, 5) * am,
				}
			end
		end
		for k = #self.Arcs, 1, -1 do
			local a = self.Arcs[k]
			if now > a.die then
				table.remove(self.Arcs, k)
			else
				local p1 = self:SparkPos(a.i1, att, bones)
				local p2 = self:SparkPos(a.i2, att, bones)
				Tesla(p1, p2, a.w0, a.w1, a.amp, bc)
				if self.Organic and a.i1 % 2 == 0 then -- living-energy look: a wriggling tendril off every other arc
					local mid = LerpVector(math.Rand(0.3, 0.7), p1, p2) + VectorRand() * 5
					Tesla(mid, mid + VectorRand() * 18, a.w1 * 1.4, 0.6, a.amp * 1.6, bc)
				end
				if a.i1 % 3 == 0 then Small(p1, scale, power, hacked, self.ForceArcColor and self.ArcColor or nil) end
			end
		end

		render.SetMaterial(glow)
		local cr = math.Rand(6, 6.5) * scale
		local c = hacked and Color(90, 22, 0) or Color(60, 60, 60)
		render.DrawSprite(origin, cr * 2, cr * 2, Color(c.r, c.g, c.b, 255))
	end

	--=====================================================================
	-- shock zap: beam from whatever was hit to the rollermine (Valve: CBeam, sprites/rollermine_shock)
	--=====================================================================
	local Zaps = {}
	local Lingers = {} -- short tesla left on whatever an overcharged mine hit

	net.Receive("PhysRoller_Zap", function()
		local victim, mine = net.ReadEntity(), net.ReadEntity()
		local hacked, mode = net.ReadBool(), net.ReadUInt(2)
		if not IsValid(victim) or not IsValid(mine) then return end
		local strong, big = mode == 1, mode == 2 -- 1 = stuck to a vehicle, 2 = overcharged hit
		local player = victim:IsPlayer()
		Zaps[#Zaps + 1] = {
			victim = victim, mine = mine, hacked = hacked,
			col = mine.ForceArcColor and mine.ArcColor and Color(mine.ArcColor.r, mine.ArcColor.g, mine.ArcColor.b, 255) or nil,
			die = CurTime() + (big and 0.7 or (strong and 0.5 or (player and 0.2 or 0.5))),
			w0 = big and 8 or 1,
			w1 = big and 36 or (strong and 8 or (player and 8 or 16)),
			noise = big and 12 or (strong and 30 or (player and 4 or 16)),
		}
		if big then Lingers[#Lingers + 1] = { ent = victim, die = CurTime() + 0.7 } end
	end)

	local function EntPoint(ent, attName, fallbackIdx)
		local id = attName and ent:LookupAttachment(attName) or 0
		if id and id > 0 then
			local a = ent:GetAttachment(id)
			if a then return a.Pos end
		end
		if fallbackIdx then
			local a = ent:GetAttachment(fallbackIdx)
			if a then return a.Pos end
		end
		return ent:WorldSpaceCenter()
	end

	local function DrawZaps(now)
		for k = #Zaps, 1, -1 do
			local z = Zaps[k]
			if now > z.die or not IsValid(z.victim) or not IsValid(z.mine) then
				table.remove(Zaps, k)
			else
				local p1 = EntPoint(z.victim, "beam_damage")
				local p2 = EntPoint(z.mine, nil, 1)
				local segs = 12
				render.SetMaterial(z.hacked and zapYel or zapMat)
				render.StartBeam(segs + 1)
				for i = 0, segs do
					local f = i / segs
					local p = LerpVector(f, p1, p2)
					if i > 0 and i < segs then p = p + VectorRand() * z.noise end
					render.AddBeam(p, Lerp(f, z.w0, z.w1) * 2, f * 2, z.col or Color(255, 255, 255, 255))
				end
				render.EndBeam()
			end
		end
	end

	local function DrawLingers(now)
		for k = #Lingers, 1, -1 do
			local l = Lingers[k]
			local e = l.ent
			if now > l.die or not IsValid(e) then
				table.remove(Lingers, k)
			else
				local mn, mx = e:OBBMins(), e:OBBMaxs()
				local fade = 255 * math.Clamp((l.die - now) / 0.35, 0, 1)
				local function P()
					return e:LocalToWorld(Vector(math.Rand(mn.x, mx.x), math.Rand(mn.y, mx.y), math.Rand(mn.z, mx.z)))
				end
				for _ = 1, 2 do Tesla(P(), P(), math.Rand(4, 6), 1.5, math.Rand(2, 4), Color(255, 255, 255, fade)) end
			end
		end
	end

	-- drawn from a hook so it works whatever render group the entity ends up in
	hook.Add("PostDrawTranslucentRenderables", "PhysRollermineEffects", function(depth, sky)
		if sky then return end
		local now = CurTime()
		for _, ent in ipairs(ents.FindByClass("snpc_rollermine*")) do
			if IsValid(ent) and not ent:IsDormant() then
				if ent.LightningTrail then
					ent:DrawLightningTrail(now)
					if ent:GetNWBool("PhysCharge", false) then ent:DrawSpinCharge(now) end
				end
				if ent:GetNWBool("PhysOpen", false) and (ent.Overcharged or ent:GetNWFloat("PhysActive", 0) <= now) then
					ent:DrawRollerElectric(now)
				end
			end
		end
		DrawZaps(now)
		DrawLingers(now)
	end)
end

if not SERVER then return end

--=========================================================================
-- SERVER
--=========================================================================

util.AddNetworkString("PhysRoller_Zap")

local ROLLER_SKIN_REGULAR, ROLLER_SKIN_FRIENDLY, ROLLER_SKIN_DETONATE = 0, 1, 2

function ENT:OnSpawned()
	local now = CurTime()
	self.Open          = false
	self.OpenSince     = 0
	self.Primed        = false
	self.PoweredDown   = false
	self.Detonating    = false
	self.Exploding     = false
	self.TurnedOff     = false
	self.ActiveTime    = 0
	self.ShockTime     = 0
	self.ChargeStart   = now
	self.TossedUntil   = 0
	self.Taunted       = false
	self.NextDanger    = 0
	self.StuckTo       = nil
	self.StuckWeld     = nil
	self.NextJolt      = 0
	self.NoStickUntil  = 0
	self.NextHopCheck  = 0

	self:SetNWBool("PhysOpen", false)
	self:SetNWFloat("PhysActive", 0)
	self:SetNWBool("PhysHacked", self.Hacked)
	self:SetNWBool("PhysPowerDown", false)
	self:UpdateSkin()

	self.RollSnd = CreateSound(self, "NPC_RollerMine.Roll")
	self.PingSnd = CreateSound(self, "NPC_RollerMine.Ping")
	self.RollSnd:PlayEx(0, 100 * (self.SoundPitch or 1))
end

function ENT:UpdateSkin()
	local skin = ROLLER_SKIN_REGULAR
	if self.PoweredDown then skin = ROLLER_SKIN_DETONATE
	elseif self.Hacked then skin = ROLLER_SKIN_FRIENDLY end
	self:SetSkin(skin)
end

function ENT:GetStunDelay()
	return self.Hacked and self.HackedStunDelay or self.StunDelay
end

--=========================================================================
-- Spikes (model swap)
--=========================================================================

function ENT:SwapModel(model)
	if self:GetModel() == model then return end
	if self:IsPlayerHolding() then return false end -- never yank it out of a physgun
	local phys = self:GetPhysicsObject()
	local vel, ang = Vector(), Vector()
	local frozen = false
	if IsValid(phys) then
		vel, ang = phys:GetVelocity(), phys:GetAngleVelocity()
		frozen = not phys:IsMotionEnabled()
	end
	local group = self:GetCollisionGroup()

	-- Keep the existing physics object (a sphere, like Valve's): rebuilding it on every open/close froze the ball
	-- for a moment in multiplayer. Only rebuild if the model swap somehow lost it.
	local keep = IsValid(phys) and not self.RebuildPhysOnSwap
	if not keep then self:SetPos(self:GetPos() + Vector(0, 0, 3 * (self.ModelScale or 1))) end -- the spiky shape must not start inside the floor
	self:SetModel(model)
	if self.ModelScale and self.ModelScale ~= 1 then self:SetModelScale(self.ModelScale, 0) end
	if keep and IsValid(self:GetPhysicsObject()) then
		self:UpdateSkin()
		return true
	end
	if self.PhysSphereRadius then
		self:PhysicsInitSphere(self.PhysSphereRadius, "metal") -- (a scaled model keeps its unscaled mesh: use a sphere)
	elseif not self:PhysicsInit(SOLID_VPHYSICS) then
		self:PhysicsInitSphere(self.GroundRadius, "metal")
	end
	self:SetMoveType(MOVETYPE_VPHYSICS)
	if not IsValid(self:GetPhysicsObject()) then return end
	phys = self:GetPhysicsObject()
	phys:SetDamping(self.LinearDamping, self.AngularDamping)
	if self.PhysMass and self.PhysMass > 0 then phys:SetMass(self.PhysMass) end
	phys:EnableGravity(true)
	self:SetCollisionGroup(group)
	if frozen then
		phys:EnableMotion(false) -- stays frozen (and physgunnable) through the model swap
	else
		phys:Wake()
		phys:SetVelocity(vel)
		phys:SetAngleVelocity(ang)
	end
	self:UpdateSkin()
	return true
end

function ENT:OpenSpikes(hop)
	if self.Open or self.TurnedOff or self:IsPlayerHolding() then return end
	self.Open = true
	self.OpenSince = CurTime()
	self:SwapModel(self.OpenModel)
	self:SetNWBool("PhysOpen", true)
	self:RSound("NPC_RollerMine.OpenSpikes")
	if hop and hop > 0 then self:Hop(hop) end
end

function ENT:CloseSpikes()
	if not self.Open or self.Primed or CurTime() < self.ShockTime or self:IsPlayerHolding() then return end
	self.Open = false
	self:SwapModel(self.Model)
	self:SetNWBool("PhysOpen", false)
end

--=========================================================================
-- Shocking
--=========================================================================

function ENT:ShockTarget(ent)
	local now = CurTime()
	self.ActiveTime = now + self:GetStunDelay()
	self.ShockTime = now + self.ShockCooldown
	self:SetNWFloat("PhysActive", self.ActiveTime)

	local dir = ent:WorldSpaceCenter() - self:WorldSpaceCenter()
	dir.z = 0
	if dir:LengthSqr() < 1 then dir = VectorRand() dir.z = 0 end
	dir:Normalize()
	local imp = (dir + Vector(0, 0, 0.75)):GetNormalized() * self.ShockKnock

	-- friendly mines only nudge a friendly player
	if self:GetDisposition(ent) ~= D_HT then
		if ent:IsPlayer() then ent:SetVelocity(imp * 0.5) end
		return
	end

	local damage = self.ShockDamage
	if ent:GetClass() == "npc_combine_s" then
		local hp, max = ent:Health(), ent:GetMaxHealth()
		damage = hp <= max / 2 and hp + 1 or max / 2
	end
	local d = DamageInfo()
	d:SetAttacker(self) d:SetInflictor(self)
	d:SetDamage(damage)
	d:SetDamageType(DMG_SHOCK)
	d:SetDamagePosition(ent:WorldSpaceCenter())
	d:SetDamageForce(imp * 0.3)
	ent:TakeDamageInfo(d)

	-- the one that gets thrown is the rollermine: away from what it hit, 30 degrees up (Valve: velocity = impulse)
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		phys:Wake()
		local rs = (self.RecoilSpeed or self.ShockKnock) / math.max(imp:Length(), 1)
		phys:SetVelocity(Vector(-imp.x, -imp.y, imp.z) * rs)
	end
	if ent:IsPlayer() then
		ent:SetVelocity(imp * 0.25)
	elseif ent:IsNPC() or ent:IsNextBot() then
		ent:SetVelocity(imp * 0.15)
	end

	local ed = EffectData()
	ed:SetOrigin(ent:WorldSpaceCenter()) ed:SetMagnitude(3) ed:SetScale(2) ed:SetRadius(3)
	util.Effect("ElectricSpark", ed)
	self:RSound("NPC_RollerMine.Shock")
	self:SendZap(ent, self.ZapMode or (self.Overcharged and 2 or 0))
	if self.ShockRadius then self:ChainShock(ent, damage) end
	self.ChargeStart = now
end

-- Super: the discharge also arcs to every other enemy around the victim
function ENT:ChainShock(victim, damage)
	for _, e in ipairs(ents.FindInSphere(victim:WorldSpaceCenter(), self.ShockRadius)) do
		if e ~= victim and e ~= self and IsValid(e) and (e:IsPlayer() or e:IsNPC() or e:IsNextBot())
			and (e:IsNextBot() or e:IsPlayer() or e:Health() > 0 or e:GetClass() == "npc_rollermine")
			and self:GetDisposition(e) == D_HT then
			local dir = e:WorldSpaceCenter() - self:WorldSpaceCenter()
			dir.z = 0
			dir:Normalize()
			local d = DamageInfo()
			d:SetAttacker(self) d:SetInflictor(self)
			d:SetDamage(damage * 0.5)
			d:SetDamageType(DMG_SHOCK)
			d:SetDamagePosition(e:WorldSpaceCenter())
			d:SetDamageForce(dir * self.ShockKnock * 0.3)
			e:TakeDamageInfo(d)
			if e:IsPlayer() then e:SetVelocity((dir + Vector(0, 0, 0.5)) * self.ShockKnock * 0.15) end
			self:SendZap(e, 2)
		end
	end
end

function ENT:SendZap(victim, mode)
	net.Start("PhysRoller_Zap")
	net.WriteEntity(victim)
	net.WriteEntity(self)
	net.WriteBool(self.Hacked)
	net.WriteUInt(mode or 0, 2)
	net.SendPVS(self:GetPos())
end

-- the vehicle (and its driver) this entity belongs to: stock vehicles, a seat/part parented to one,
-- and the usual vehicle bases (simfphys, LVS) whose driver sits in a separate seat
function ENT:DrivenVehicle(ent)
	if not IsValid(ent) then return end
	local veh = ent
	if not ent:IsVehicle() then
		local par = ent:GetParent()
		if IsValid(par) and (par:IsVehicle() or par.IsSimfphyscar or par.LVS) then
			veh = par
		elseif not (ent.IsSimfphyscar or ent.LVS) then
			return
		end
	end
	local drv = veh.GetDriver and veh:GetDriver()
	if not IsValid(drv) and veh.GetDriverSeat then
		local seat = veh:GetDriverSeat()
		if IsValid(seat) and seat.GetDriver then drv = seat:GetDriver() end
	end
	if IsValid(drv) and drv:IsPlayer() and drv:Alive() then return veh, drv end
end

function ENT:IsPlayerVehicle(ent)
	local veh, drv = self:DrivenVehicle(ent)
	if not veh then return false end
	return self:GetDisposition(drv) == D_HT
end

-- the touch callback is unreliable for NPC-type entities: also test for real contact with a driven vehicle
-- (a tiny hull trace against entities only: it touches the vehicle's actual collision shape, not its bounding box)
function ENT:ProximityStick()
	if self.Held or self.StuckTo or self.Exploding or self.Detonating or CurTime() < self.NoStickUntil then return end
	local r = self:GetGroundRadius() + 3
	local c = self:WorldSpaceCenter()
	local tr = util.TraceHull({
		start = c, endpos = c + Vector(0, 0, 0.1), mins = Vector(-r, -r, -r), maxs = Vector(r, r, r),
		filter = self, mask = MASK_SOLID, ignoreworld = true,
	})
	local e = tr.Entity
	if IsValid(e) and tr.Hit then
		local veh = self:DrivenVehicle(e)
		if veh and self:IsPlayerVehicle(veh) then self:StickToVehicle(veh) end
	end
end

-- every physics contact lands here (we never use the manhack's slicing / bumping)
function ENT:OnContact(ent, c)
	if not IsValid(ent) or ent:IsWorld() or self.Exploding then return true end
	local now = CurTime()

	if not self.Held and not self.StuckTo and now >= self.NoStickUntil then
		local veh = self:DrivenVehicle(ent)
		if veh and self:IsPlayerVehicle(veh) then
			self:StickToVehicle(veh)
			return true
		end
	end

	self:TryShock(ent)
	return true
end

function ENT:TryShock(ent)
	local now = CurTime()
	local live = (self.Open and now >= self.ActiveTime) or now < self.TossedUntil
	if not live or self.Held or now < self.ShockTime then return end
	if not (ent:IsNPC() or ent:IsPlayer() or ent:IsNextBot()) then return end
	if ent:IsPlayer() and not ent:Alive() then return end
	local disp = self:GetDisposition(ent)
	if disp == D_HT or disp == D_FR or (ent:IsPlayer() and self.Hacked) then
		-- two mines that meet hit each other: decide before the first shock stuns the other one
		local mutual = ent.IsRollermine and ent:CanShockNow(self)
		self:ShockTarget(ent)
		if mutual then ent:ShockTarget(self) end
	end
end

function ENT:CanShockNow(other)
	local now = CurTime()
	if not ((self.Open and now >= self.ActiveTime) or now < self.TossedUntil) then return false end
	if self.Held or self.Exploding or now < self.ShockTime then return false end
	local disp = self:GetDisposition(other)
	return disp == D_HT or disp == D_FR
end

-- the touch callback can be missed (queued, model swaps): also check what is within reach while open
function ENT:ProximityShock()
	if not self.Open or self.Held or CurTime() < self.ShockTime or CurTime() < self.ActiveTime then return end
	local reach = self:GetGroundRadius() + 20
	for _, e in ipairs(ents.FindInSphere(self:WorldSpaceCenter(), reach)) do
		if e ~= self and IsValid(e) and (e:IsPlayer() or e:IsNPC() or e:IsNextBot()) then
			self:TryShock(e)
			if CurTime() < self.ShockTime then return end
		end
	end
end

--=========================================================================
-- Vehicles
--=========================================================================

function ENT:StickToVehicle(veh)
	local weld = constraint.Weld(self, veh, 0, 0, self.StickForceLimit, true, false)
	self.StuckTo, self.StuckWeld = veh, weld
	if not IsValid(weld) then
		-- no constraint possible (odd vehicle physics): ride along by hand instead
		self.StuckLocal = veh:WorldToLocal(self:GetPos())
		self.StuckWeld = nil
	end
	self.NextJolt = CurTime() + math.Rand(1.5, 3)
	self:OpenSpikes(0)
	self:SendZap(veh, 1)
	self:RSound("NPC_RollerMine.Chirp")
	local vp, mp = veh:GetPhysicsObject(), self:GetPhysicsObject()
	if IsValid(vp) and IsValid(mp) then mp:SetVelocity(vp:GetVelocity()) end
end

function ENT:Unstick(quiet)
	if IsValid(self.StuckWeld) then self.StuckWeld:Remove() end
	self.StuckTo, self.StuckWeld, self.StuckLocal = nil, nil, nil
	if quiet then return end
	self.NoStickUntil = CurTime() + 3
	self.ActiveTime = CurTime() + self:GetStunDelay()
	self:SetNWFloat("PhysActive", self.ActiveTime)
	self:CloseSpikes()
end

function ENT:UpdateStuck()
	if not self.StuckTo then return end
	if not IsValid(self.StuckTo) or (not IsValid(self.StuckWeld) and not self.StuckLocal) or not self:DrivenVehicle(self.StuckTo) then
		self.StuckLocal = nil
		self:Unstick()
		return
	end
	if self.StuckLocal then
		local mp = self:GetPhysicsObject()
		if IsValid(mp) then
			mp:SetPos(self.StuckTo:LocalToWorld(self.StuckLocal))
			local vp = self.StuckTo:GetPhysicsObject()
			mp:SetVelocity(IsValid(vp) and vp:GetVelocity() or self.StuckTo:GetVelocity())
		end
	end
	local now = CurTime()
	if now >= self.NextJolt then
		self.NextJolt = now + math.Rand(2, 4)
		local vp = self.StuckTo:GetPhysicsObject()
		if IsValid(vp) then
			-- a real shove: sideways / up kick plus a twist, enough to throw the steering off
			local dir = VectorRand()
			dir.z = math.abs(dir.z) * 0.4 + 0.3
			vp:AddVelocity(dir:GetNormalized() * math.Rand(self.JoltMin or 350, self.JoltMax or 550))
			vp:AddAngleVelocity(VectorRand() * math.Rand(120, 260))
			vp:Wake()
		end
		self:RSound("NPC_RollerMine.JoltVehicle")
	end
end

--=========================================================================
-- Explosion
--=========================================================================

-- every rollermine sound goes through here so a variant can shift its pitch (SoundPitch, 1 = normal)
function ENT:RSound(name)
	self:EmitSound(name, 75, math.Clamp(math.floor(100 * (self.SoundPitch or 1)), 30, 255))
end

function ENT:HurtSound() self:RSound("NPC_RollerMine.Hurt") end

function ENT:PreDetonate(delay)
	if self.Detonating or self.Exploding then return end
	self.Detonating = true
	self:HurtSound()
	self:Hop(300, true)
	timer.Simple(delay or 0.5, function() if IsValid(self) then self:Explode() end end)
end

function ENT:Explode(attacker)
	if self.Exploding then return end
	self.Exploding = true
	self.Crashing = true -- (ignores further damage, see OnTakeDamage)
	-- kill feed: whoever set it off, or itself (water, power-down, anything without a culprit)
	local killer = IsValid(attacker) and attacker or self.Attacker
	if not IsValid(killer) or killer:IsWorld() or killer == self then killer = self end
	local infl = IsValid(self.Inflictor) and not self.Inflictor:IsWorld() and self.Inflictor or killer
	hook.Run("OnNPCKilled", self, killer, infl)
	attacker = killer ~= self and killer or nil
	if IsValid(self.StuckWeld) then self.StuckWeld:Remove() end
	local pos = self:WorldSpaceCenter()
	local dmg = self.Primed and self.PrimedDamage or (self.PoweredDown and self.PoweredDownDamage or self.ExplodeDamage)

	local ed = EffectData()
	ed:SetOrigin(pos)
	if self:WaterLevel() > 0 then
		util.Effect("WaterSurfaceExplosion", ed)
	else
		ed:SetScale(1) ed:SetMagnitude(1)
		util.Effect("Explosion", ed)
	end
	util.BlastDamage(self, IsValid(attacker) and attacker or self, pos, self.ExplodeRadius, dmg)
	self:StopLoops()
	self:Remove()
end

function ENT:StopLoops()
	if self.RollSnd then self.RollSnd:Stop() end
	if self.PingSnd then self.PingSnd:Stop() end
end

function ENT:OnRemoved()
	self:StopLoops()
	if IsValid(self.StuckWeld) then self.StuckWeld:Remove() end
end

-- health ran out -> short chirp, then it blows up
function ENT:StartDying(dmg)
	if self.Detonating or self.Exploding then return end
	self.Attacker, self.Inflictor = dmg:GetAttacker(), dmg:GetInflictor()
	self:PreDetonate(math.Rand(0.1, 0.5))
end

-- Burn / blast detonates it (unless another rollermine did it: that only dazes), everything else shoves it.
function ENT:ModifyDamage(dmg)
	if self.Exploding then dmg:SetDamage(0) return end
	local atk = dmg:GetAttacker()
	local now = CurTime()

	if IsValid(atk) and atk:GetClass():find("rollermine") and atk ~= self then
		self.ActiveTime = now + self:GetStunDelay()
		self:SetNWFloat("PhysActive", self.ActiveTime)
		self:Hop(300)
		dmg:SetDamage(0)
		return
	end

	if dmg:IsDamageType(bit.bor(DMG_BURN, DMG_BLAST)) then
		-- sturdy variants survive some explosions (each separate blast counts once; fire counts once per 1.5 s)
		local need = self.BlastsToDetonate or 1
		if need > 1 and not self.Detonating then
			local window = dmg:IsDamageType(DMG_BLAST) and 0.4 or 1.5
			if now - (self.LastBlastTime or -99) > window then
				self.LastBlastTime = now
				self.BlastsTaken = (self.BlastsTaken or 0) + 1
				if self.BlastsTaken < need then
					self:HurtSound()
					self:Hop(150, true)
					local ed = EffectData()
					ed:SetOrigin(self:GetPos()) ed:SetMagnitude(3) ed:SetScale(2) ed:SetRadius(3)
					util.Effect("ElectricSpark", ed)
				end
			end
			if self.BlastsTaken < need then dmg:SetDamage(0) dmg:SetDamageForce(Vector(0, 0, 0)) return end
		end
		if not self.Detonating then self.Attacker, self.Inflictor = dmg:GetAttacker(), dmg:GetInflictor() end
		self:PreDetonate(math.Rand(0.1, 0.5))
		return
	end
	-- not shootable: bullets, blades, etc. do nothing at all (Valve: DAMAGE_EVENTS_ONLY)
	dmg:SetDamage(0)
	dmg:SetDamageForce(Vector(0, 0, 0))
end

function ENT:AcceptInput(name, activator, caller, data)
	name = string.lower(name)
	if name == "turnon" then
		self.TurnedOff = false
		self:SetNWBool("PhysOpen", self.Open)
	elseif name == "turnoff" then
		self.TurnedOff = true
		self:CloseSpikes()
	elseif name == "powerdown" then
		if not self.PoweredDown then
			self.PoweredDown = true
			self:UpdateSkin()
			self:SetNWBool("PhysPowerDown", true)
			local now = CurTime()
			self.PowerDownStart = now + math.Rand(0.1, 0.5)
			self.PowerDownBlow = self.PowerDownStart + math.Rand(1.5, 4)
			self.NextToggle = self.PowerDownStart
		end
	elseif name == "hack" then
		self.Hacked = true
		self:SyncNPCClass()
		self:UpdateSkin()
		self:SetNWBool("PhysHacked", true)
		self:RSound("NPC_RollerMine.Reprogram")
		self:OpenSpikes(0)
	end
end

--=========================================================================
-- Gravity gun
--=========================================================================

local function BaseFn(name)
	local b = scripted_ents.GetStored("base_physics_snpc")
	return b and b.t and b.t[name]
end

-- the physgun is a tool for placing them (scenes): it must not change their open/closed or live state
local function IsPhysgun(ply)
	local w = IsValid(ply) and ply:IsPlayer() and ply:GetActiveWeapon()
	return IsValid(w) and w:GetClass() == "weapon_physgun"
end

function ENT:OnGravGunPickup(ply)
	BaseFn("OnGravGunPickup")(self, ply)
	if IsPhysgun(ply) then self:Unstick(true) return end
	self:Unstick()
	self:RSound("NPC_RollerMine.Held")
end

function ENT:OnGravGunPunt(ply)
	BaseFn("OnGravGunPunt")(self, ply)
	self.ActiveTime = CurTime() + self:GetStunDelay()
	self:SetNWFloat("PhysActive", self.ActiveTime)
	if self.Open then self.TossedUntil = CurTime() + 3 end
	self:RSound("NPC_RollerMine.Tossed")
end

function ENT:OnGravGunDrop(ply)
	BaseFn("OnGravGunDrop")(self, ply)
	if IsPhysgun(ply) then return end
	self.ActiveTime = CurTime() + self:GetStunDelay()
	self:SetNWFloat("PhysActive", self.ActiveTime)
end

function ENT:OnTargetAcquired(ent)
	self.ChargeStart = CurTime()
	self.Taunted = false
end

function ENT:IsFlightDisabled()
	return self.Held or self.StuckTo ~= nil
end

--=========================================================================
-- Movement AI
--=========================================================================

function ENT:UpdateMovement(dt)
	local now = CurTime()
	self:SetRoll(nil)
	if self.Held or self.StuckTo or self.Detonating then return end

	local pos = self:GetPos()
	local phys = self:GetPhysicsObject()
	local vel = IsValid(phys) and phys:GetVelocity() or Vector()
	local speed = vel:Length()

	-- "so cops, etc. will try to avoid them"
	if speed > 64 and now >= self.NextDanger then
		self.NextDanger = now + 0.2
		sound.EmitHint(SOUND_DANGER, pos, 120, 0.2, self)
	end

	local foe, chase = self:GetFoe(), self:GetChasePos()
	if chase then
		local to = Vector(chase.x - pos.x, chase.y - pos.y, 0)
		local d2 = to:Length()
		local toDir = d2 > 1 and to / d2 or self:GetForward()
		local vehicle = IsValid(foe) and foe:IsPlayer() and foe:InVehicle() and IsValid(foe:GetVehicle())
		local openDist = vehicle and self.OpenDistVehicle or self.OpenDist

		if IsValid(foe) and not self.Taunted and d2 < self.TauntDist then
			self.Taunted = true
			self:RSound("NPC_RollerMine.Taunt")
		end

		if not self.Open and d2 < openDist and self.FoeVisible then
			self:OpenSpikes(foe:GetClass() == "npc_bullseye" and 0 or (vehicle and 120 or 40))
		elseif self.Open and d2 > openDist + 80 and now - self.OpenSince > 1 then
			self:CloseSpikes()
		end

		-- torque ramps up the longer it keeps charging
		local cap = self.Hacked and self.MaxTorqueFactor * 0.75 or self.MaxTorqueFactor
		local factor = math.Clamp(1 + (now - self.ChargeStart) * 2, 1, cap)
		-- do not overshoot: the closer it gets the lower the wanted speed (the controller brakes by itself)
		local rollSpeed = d2 < 200 and self.NearSlow ~= false and math.max(160, self.MaxRollSpeed * (0.55 + 0.45 * d2 / 200)) or self.MaxRollSpeed

		local goal = chase
		if vehicle then goal = foe:GetVehicle():GetPos() + foe:GetVehicle():GetVelocity() * 1.0 end

		local step = self:GroundSteer(goal, foe)
		self:SetRoll(step - pos, factor, rollSpeed)

		-- overran it: close up and start the run again
		local vd = speed > 100 and vel / speed or nil
		if vd and now - self.ChargeStart > 1 and vd:Dot(toDir) < 0 then
			self:CloseSpikes()
			self.ChargeStart = now
		end
		-- rams vehicles with a hop
		if vehicle and vd and d2 < 300 and factor > 3 and vd:Dot(toDir) > 0 then self:Hop(120) end

	elseif self.Hacked then
		self:FollowPlayer(dt, pos)
	else
		self.ChargeStart = now
		if self.Open and now - self.OpenSince > 3 then self:CloseSpikes() end
	end
end

-- hacked mines return to the nearest player
local IgnoreCV
function ENT:FollowPlayer(dt, pos)
	local best, bd
	for _, p in ipairs(player.GetAll()) do
		if p:Alive() then
			local d = pos:DistToSqr(p:GetPos())
			if not bd or d < bd then best, bd = p, d end
		end
	end
	IgnoreCV = IgnoreCV or GetConVar("ai_ignoreplayers")
	if IgnoreCV:GetBool() then self.Following = false return end -- "ignore players": no following
	if not best or bd < self.StopDist ^ 2 then return end
	if bd > self.FollowDist ^ 2 or self.Following then
		self.Following = bd > self.StopDist ^ 2
		local step = self:GroundSteer(best:GetPos(), nil)
		self:SetRoll(step - pos, self.MaxTorqueFactor * 0.75 * 0.75,
			math.Clamp((math.sqrt(bd) - self.StopDist) * 2, 90, self.MaxRollSpeed))
	end
end

--=========================================================================
-- Per-tick extras: rolling / ping sounds, water, power-down, stuck-to-vehicle
--=========================================================================

function ENT:OnThinkAlive(dt)
	local now = CurTime()
	if self.Exploding then return end

	-- safety net: if it ever ends up inside the world or outside it, put it back where it last was fine
	local pos = self:GetPos()
	local phys0 = self:GetPhysicsObject()
	if IsValid(phys0) and phys0:IsMotionEnabled() then
		local stuck = not util.IsInWorld(pos) or bit.band(util.PointContents(pos), CONTENTS_SOLID) ~= 0
		if stuck then
			if self.LastGoodPos then
				self:SetPos(self.LastGoodPos + Vector(0, 0, 10))
				phys0:SetVelocity(Vector(0, 0, 0))
				phys0:SetAngleVelocity(Vector(0, 0, 0))
				phys0:Wake()
			end
		elseif now >= (self.NextGoodCheck or 0) then
			self.NextGoodCheck = now + 0.25
			local tr = util.TraceLine({ start = pos, endpos = pos - Vector(0, 0, 30), filter = self, mask = MASK_SOLID_BRUSHONLY })
			if tr.Hit and not tr.StartSolid then self.LastGoodPos = pos end
		end
	end

	-- falls into water -> blows up
	if self:WaterLevel() >= 1 and not self.WaterProof then
		local up = self:GetPos() + Vector(0, 0, 64)
		if bit.band(util.PointContents(up), CONTENTS_WATER) ~= 0 then self:Explode() return end
	end

	self:UpdateStuck()

	-- power-down: flash open/closed, then detonate
	if self.PoweredDown and self.PowerDownStart and now >= self.PowerDownStart then
		if now >= self.PowerDownBlow then
			self:HurtSound()
			self:Explode()
			return
		end
		if now >= self.NextToggle and not self:IsPlayerHolding() then
			self.NextToggle = now + math.Rand(0.3, 0.9)
			self:HurtSound()
			if self.Open then self.Open = false self:SwapModel(self.Model) self:SetNWBool("PhysOpen", false)
			else self.Open = true self:SwapModel(self.OpenModel) self:SetNWBool("PhysOpen", true) end
		end
	end

	self:ProximityShock()
	self:ProximityStick()

	self:UpdateLoops(false)
end

-- rolling + ping loops (also run while "Disable AI" is on, so a rolling prop still sounds like one)
function ENT:UpdateLoops(aiOff)
	local phys = self:GetPhysicsObject()
	if IsValid(phys) and self.RollSnd then
		local w = phys:GetAngleVelocity():Length()
		local rs = math.Clamp(w - 90, 1, 720) / 720
		if self.Held then rs = 0 end
		self.RollSnd:ChangeVolume(rs, 0.1)
		self.RollSnd:ChangePitch((90 + 25 * rs) * (self.SoundPitch or 1), 0.15)
	end

	-- ping while it is after something
	if self.PingSnd then
		local foe = self:GetFoe()
		if IsValid(foe) and not self.Held and not aiOff then
			if not self.PingSnd:IsPlaying() then self.PingSnd:PlayEx(1, 100 * (self.SoundPitch or 1)) end
			local d = math.Clamp(self:GetPos():Distance(foe:GetPos()), 1, 256)
			self.PingSnd:ChangePitch((95 + 30 * (1 - d / 256)) * (self.SoundPitch or 1), 0.1) -- Valve: closer = faster ping
		else
			self.PingSnd:Stop()
		end
	end
end

function ENT:OnAIDisabled(dt)
	if self.Exploding then return end
	self:UpdateLoops(true)
end

--=========================================================================
-- Alyx (Episode One behaviour), like Valve's INPCInteractive: while the PLAYER holds a rollermine with the gravity gun
-- and it is within 360 units of Alyx (she can see the player), she walks up to within 80 units, zaps it with her EMP
-- tool and it is hacked (friendly).
--=========================================================================
local alyxHack = {}
local function HeldByPlayerGun(m)
	if not m.Held or not IsValid(m.PhysAttacker) or not m.PhysAttacker:IsPlayer() then return false end
	local w = m.PhysAttacker:GetActiveWeapon()
	return IsValid(w) and w:GetClass() == "weapon_physcannon"
end
timer.Create("PhysSNPC_AlyxHacks", 0.25, 0, function()
	for _, alyx in ipairs(ents.FindByClass("npc_alyx")) do
		if not IsValid(alyx) or alyx:Health() <= 0 then alyxHack[alyx] = nil end
		local st = IsValid(alyx) and alyx:Health() > 0 and alyxHack[alyx] or nil
		if st and (not IsValid(st.mine) or st.mine.Hacked or not HeldByPlayerGun(st.mine)) then st = nil alyxHack[alyx] = nil end
		if not (IsValid(alyx) and alyx:Health() > 0) then
		elseif not st then
			for _, m in ipairs(ents.FindInSphere(alyx:GetPos(), 360)) do
				if IsValid(m) and m.IsPhysicsSNPC and m.IsRollermine and not m.Hacked and HeldByPlayerGun(m) and alyx:Visible(m.PhysAttacker) then
					alyxHack[alyx] = { mine = m }
					break
				end
			end
		else
			local m = st.mine
			if alyx:WorldSpaceCenter():Distance(m:WorldSpaceCenter()) > 80 then
				alyx:SetLastPosition(m:GetPos())
				alyx:SetSchedule(SCHED_FORCED_GO)
			else
				st.near = st.near or CurTime()
				alyx:SetSchedule(SCHED_IDLE_STAND)
				if CurTime() - st.near >= 0.8 then
					local ed = EffectData()
					ed:SetOrigin(m:WorldSpaceCenter()) ed:SetStart(alyx:WorldSpaceCenter()) ed:SetMagnitude(3) ed:SetScale(1) ed:SetRadius(3)
					util.Effect("ElectricSpark", ed)
					util.Effect("StunstickImpact", ed)
					m:EmitSound("NPC_RollerMine.Reprogram")
					m:AcceptInput("hack", alyx, alyx, "")
					alyxHack[alyx] = nil
				end
			end
		end
	end
end)
