--[[-------------------------------------------------------------------------
	Electrohack - a manhack that is a walking (flying) capacitor. No ranged beams: it fights up close.

	  * Charge: builds up while it fights (slowly when idle) and crackles visibly around the body
	    more and more as it fills.
	  * Discharge: when fully charged and an enemy is within PulseRange, it releases a shock pulse:
	    arcs to every enemy in range (stunning other physics SNPCs, jolting players), then starts over.
	  * Static field: any enemy that gets within FieldRange is continuously nipped by small arcs.
	  * Shocking blades: every cut zaps the victim and chains to one more enemy.
	  * Immune to shock / energy-beam / plasma damage; discharges one last time when it dies.
	  * Arcs are drawn in the colour of its eye glow.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Base      = "snpc_manhack"
ENT.PrintName = "Electrohack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.EyeColor       = Color(90, 170, 255)
ENT.HackedEyeColor = Color(130, 255, 230)

ENT.SpawnHealth = 30

-- charge / discharge pulse
ENT.ChargeTime    = 5       -- seconds to fill while fighting (3x as long when idle)
ENT.PulseRange    = 240
ENT.PulseDamage   = 14
ENT.PulseTargets  = 6
ENT.PulseStun     = 1.5     -- engine stall of other physics SNPCs
ENT.DeathZapDamage = 15

-- static field
ENT.FieldRange    = 130
ENT.FieldInterval = 0.5
ENT.FieldDamage   = 3

-- blades
ENT.SliceZapDamage  = 6
ENT.ArcChainRange   = 260
ENT.ArcChainFalloff = 0.7
ENT.StunTime        = 1.0
ENT.ArcSound        = "ambient/energy/zap1.wav"
ENT.PulseSound      = "ambient/energy/zap9.wav"

list.Set("MachineMayhem", "snpc_electrohack", {
	Name = "Electrohack", Class = "snpc_electrohack",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})

--=========================================================================
-- CLIENT: jagged lightning + crackle around the body
--=========================================================================
if CLIENT then
	local Arcs = {}
	local mat = Material("sprites/tp_beam001")

	local function AddArc(from, to, col, dur, scale)
		Arcs[#Arcs + 1] = { from = from, to = to, col = col, start = CurTime(), dur = dur or 0.3, nextShape = 0, scale = scale or 1 }
	end

	net.Receive("PhysSNPC_Arc", function()
		local from, to = net.ReadVector(), net.ReadVector()
		AddArc(from, to, net.ReadColor(), 0.3, 1)
	end)

	local function Shape(a)
		local pts = { a.from }
		local dist = a.from:Distance(a.to)
		local n = math.Clamp(math.floor(dist / 28), 3, 22)
		local dir = (a.to - a.from) / math.max(dist, 1)
		local right = dir:Cross(Vector(0, 0, 1))
		if right:LengthSqr() < 0.01 then right = Vector(1, 0, 0) end
		right:Normalize()
		local up = right:Cross(dir)
		local amp = math.Clamp(dist * 0.06, 2, 14)
		for i = 1, n - 1 do
			pts[#pts + 1] = a.from + dir * (dist * i / n) + right * math.Rand(-amp, amp) + up * math.Rand(-amp, amp)
		end
		pts[#pts + 1] = a.to
		a.pts = pts
	end

	hook.Add("PostDrawTranslucentRenderables", "PhysSNPC_Arcs", function()
		if #Arcs == 0 then return end
		local now = CurTime()
		render.SetMaterial(mat)
		for i = #Arcs, 1, -1 do
			local a = Arcs[i]
			local t = (now - a.start) / a.dur
			if t >= 1 then
				table.remove(Arcs, i)
			else
				if now >= a.nextShape then a.nextShape = now + 0.04 Shape(a) end
				local fade = 1 - t
				for pass = 1, 2 do
					local w = (pass == 1 and 14 * fade + 3 or 5 * fade + 1) * a.scale
					local col = pass == 1 and Color(a.col.r, a.col.g, a.col.b, 230 * fade) or Color(255, 255, 255, 255 * fade)
					render.StartBeam(#a.pts)
					for k, p in ipairs(a.pts) do render.AddBeam(p, w, k * 0.25, col) end
					render.EndBeam()
				end
			end
		end
	end)

	-- the fuller the charge, the more it crackles around the body
	function ENT:Draw()
		self:DrawModel()
		local ch = self:GetNWFloat("PhysCharge", 0)
		if ch < 0.2 then return end
		local now = CurTime()
		if now < (self.NextAuraArc or 0) then return end
		self.NextAuraArc = now + math.Rand(0.05, 0.18) / ch
		local c = self:GetNWVector("PhysArcCol", Vector(90, 170, 255))
		local from = self:WorldSpaceCenter()
		local to = from + VectorRand():GetNormalized() * math.Rand(14, 26) * (0.6 + ch)
		AddArc(from, to, Color(c.x, c.y, c.z), 0.12, 0.45)
	end
end

if not SERVER then return end

util.AddNetworkString("PhysSNPC_Arc")

--=========================================================================
-- SERVER
--=========================================================================

function ENT:OnVariantSpawned()
	self.Charge = 0
	self.NextFieldZap = 0
	self.NextChargeNW = 0
	self.Discharged = false
	local c = self:GetEyeColor("Eye")
	self:SetNWVector("PhysArcCol", Vector(c.r, c.g, c.b))
	self:SetNWFloat("PhysCharge", 0)
end

-- shock-proof
function ENT:AbsorbDamage(dmg)
	if dmg:IsDamageType(DMG_SHOCK) or dmg:IsDamageType(DMG_ENERGYBEAM) or dmg:IsDamageType(DMG_PLASMA) then
		dmg:SetDamage(0)
	end
end

-- visual only: an arc between two points
function ENT:ArcFx(from, to)
	local c = self:GetEyeColor("Eye")
	net.Start("PhysSNPC_Arc")
		net.WriteVector(from) net.WriteVector(to) net.WriteColor(Color(c.r, c.g, c.b, 255))
	net.Broadcast()
end

-- one arc from a point to an entity: visual, damage, stun
function ENT:ZapOne(from, ent, damage, stun, quiet)
	if not IsValid(ent) then return end
	local to = ent:WorldSpaceCenter()
	self:ArcFx(from, to)

	local d = DamageInfo()
	d:SetAttacker(self) d:SetInflictor(self)
	d:SetDamage(damage)
	d:SetDamageType(DMG_SHOCK)
	d:SetDamagePosition(to)
	d:SetDamageForce((to - from):GetNormalized() * 200)
	ent:TakeDamageInfo(d)

	if ent.IsPhysicsSNPC then
		ent.EngineStallTime = math.max(ent.EngineStallTime or 0, CurTime() + (stun or self.StunTime)) -- EMP
	elseif ent:IsPlayer() then
		local k = (stun or self.StunTime) > 1.2 and 2 or 1
		ent:ViewPunch(Angle(math.Rand(-5, 5) * k, math.Rand(-5, 5) * k, math.Rand(-3, 3) * k))
	end

	local ed = EffectData()
	ed:SetOrigin(to) ed:SetMagnitude(2) ed:SetScale(1) ed:SetRadius(2)
	util.Effect("ElectricSpark", ed)
	if not quiet and not self.Silent then sound.Play(self.ArcSound, to, 75, math.random(95, 110)) end
end

-- zap `target`, then let it jump on to the closest valid targets near the last one hit
function ENT:Zap(target, damage, chain)
	if not IsValid(target) then return end
	self:ZapOne(self:WorldSpaceCenter(), target, damage)

	local hit, last, dmg = { [target] = true, [self] = true }, target, damage
	for _ = 1, chain or 0 do
		local best, bestD
		local lp = last:WorldSpaceCenter()
		for _, e in ipairs(ents.FindInSphere(lp, self.ArcChainRange)) do
			if not hit[e] and (e:IsNPC() or e:IsPlayer() or e:IsNextBot()) and self:IsValidTarget(e) then
				local d = lp:DistToSqr(e:WorldSpaceCenter())
				if not bestD or d < bestD then best, bestD = e, d end
			end
		end
		if not best then break end
		hit[best] = true
		dmg = dmg * self.ArcChainFalloff
		self:ZapOne(lp, best, dmg)
		last = best
	end
end

-- Enemies near us that we can see (nearest first).
function ENT:NearbyEnemies(range, maxCount)
	local from = self:WorldSpaceCenter()
	local found = {}
	for _, e in ipairs(ents.FindInSphere(self:GetPos(), range)) do
		if e ~= self and (e:IsNPC() or e:IsPlayer() or e:IsNextBot()) and self:IsValidTarget(e) then
			local aim = e:WorldSpaceCenter()
			if not util.TraceLine({ start = from, endpos = aim, filter = { self, e }, mask = MASK_SOLID_BRUSHONLY }).Hit then
				found[#found + 1] = { e, from:DistToSqr(aim) }
			end
		end
	end
	table.sort(found, function(a, b) return a[2] < b[2] end)
	local out = {}
	for i = 1, math.min(#found, maxCount or #found) do out[i] = found[i][1] end
	return out
end

-- The discharge: arcs to everything hostile in range plus some for show.
function ENT:Pulse(damage, stun)
	local from = self:WorldSpaceCenter()
	for _, e in ipairs(self:NearbyEnemies(self.PulseRange, self.PulseTargets)) do
		self:ZapOne(from, e, damage, stun, true)
	end
	for _ = 1, 6 do
		local tr = util.TraceLine({ start = from, endpos = from + VectorRand():GetNormalized() * math.Rand(80, self.PulseRange), filter = self, mask = MASK_SOLID_BRUSHONLY })
		self:ArcFx(from, tr.HitPos)
	end
	local ed = EffectData()
	ed:SetOrigin(from) ed:SetMagnitude(4) ed:SetScale(3) ed:SetRadius(4)
	util.Effect("ElectricSpark", ed)
	if not self.Silent then sound.Play(self.PulseSound, from, 80, math.random(95, 110)) end
end

-- every cut shocks too (call the manhack's own retreat logic first)
function ENT:OnSliced(ent)
	local base = scripted_ents.GetStored("snpc_manhack")
	if base and base.t and base.t.OnSliced then base.t.OnSliced(self, ent) end
	if IsValid(ent) then self:Zap(ent, self.SliceZapDamage, 1) end
end

function ENT:OnVariantThink(dt)
	local now = CurTime()
	if self.Held or self.Packed then return end

	-- charge up
	local fighting = self:HasEnemy()
	self.Charge = math.min(1, self.Charge + dt / (fighting and self.ChargeTime or self.ChargeTime * 3))
	if now >= self.NextChargeNW then
		self.NextChargeNW = now + 0.15
		self:SetNWFloat("PhysCharge", self.Charge)
	end

	-- static field + discharge need someone close; checked a few times a second
	if now < self.NextFieldZap then return end
	self.NextFieldZap = now + self.FieldInterval * self:LoadScale()
	if self:IsStalled() then return end

	local near = self:NearbyEnemies(math.max(self.FieldRange, self.Charge >= 1 and self.PulseRange or 0), 1)
	local e = near[1]
	if not e then return end
	local d2 = self:GetPos():DistToSqr(e:GetPos())

	if self.Charge >= 1 and d2 < self.PulseRange ^ 2 then
		self.Charge = 0
		self:SetNWFloat("PhysCharge", 0)
		self:Pulse(self.PulseDamage, self.PulseStun)
	elseif d2 < self.FieldRange ^ 2 then
		self:ZapOne(self:WorldSpaceCenter(), e, self.FieldDamage, 0.3, true)
	end
end

-- last discharge
function ENT:OnVariantDeath()
	if self.Discharged then return end
	self.Discharged = true
	self:Pulse(self.DeathZapDamage, 1)
end
