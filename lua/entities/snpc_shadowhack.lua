--[[-------------------------------------------------------------------------
	Shadowhack - converted from the ZBase NPC of the same name.
	  * a black, light-less manhack: 60 health, faster than a normal one, triple engine power
	  * it slashes anything hostile within 90 units (24 damage every 0.22 s)
	  * the first time its target comes within 350 units it calls up 7 shadow clones in a row in front of itself:
	    half the health, translucent black, faster, double slash damage; they vanish in a puff of smoke when it dies
	  * takes 0.65 x bullet / club damage, crush / fall / vehicle damage cut to 0.35 (max 18), knockback x 0.12
	  * explodes when it is destroyed
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base      = "snpc_manhack"
ENT.PrintName = "Shadowhack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.SpawnHealth  = 60
ENT.EnginePower  = 3
ENT.HackedEnginePower = 3
ENT.MaxSpeed     = 380
ENT.GibDamage    = 0
ENT.ModelColor   = Color(0, 0, 0)
ENT.EyeColor       = Color(255, 255, 255)   -- white glowing eyes
ENT.HackedEyeColor = Color(255, 255, 255)
ENT.EyeScale       = 0.35
ENT.IsShadowhack   = true
ENT.SmokeColor       = Color(46, 3, 3)      -- black smoke, tinted red (hacked: green)
ENT.HackedSmokeColor = Color(3, 40, 6)
ENT.KnockbackResistBullets = true

ENT.SlashRange    = 90
ENT.SlashDamage   = 24
ENT.SlashInterval = 0.22
-- Shadow Energy: fills while it sits in the dark, drains in bright light. Clones and teleports spend it.
ENT.EnergyMax      = 100
ENT.EnergyStart    = 60
ENT.CloneCost      = 50
ENT.TeleportCost   = 20
ENT.EnergyRegen    = 5       -- energy per second, always
ENT.CloneCooldown  = 9       -- wait after calling a batch
ENT.TeleCooldown   = 14      -- (+ up to 5 s); it also starts on cooldown
ENT.TeleDashDist   = 800     -- farther than this from its target it teleports closer
ENT.TeleDashStop   = 380     -- ...and lands this far from it
ENT.TeleFlankDist  = 260     -- flank teleports land this far behind its target
ENT.CloneCount    = 3
ENT.CloneTrigger  = 350
ENT.CloneSpacing  = 24
ENT.CloneHealthScale = 0.5
ENT.CloneSpeed    = 400
ENT.CloneDamageScale = 0.7
ENT.BulletTaken   = 0.65
ENT.CrushTaken    = 0.35
ENT.CrushCap      = 18
ENT.ForceScale    = 0.12

list.Set("MachineMayhem", "snpc_shadowhack", {
	Name = "Shadowhack", Class = "snpc_shadowhack",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})

--=========================================================================
-- CLIENT: a living shadow - it constantly sheds black smoke (tinted red / green), clones come out of it in a burst
--=========================================================================
if CLIENT then
	local emitter
	local PUFF_RED, PUFF_GREEN = Color(46, 3, 3), Color(3, 40, 6)
	local MATS = {}
	for i = 1, 16 do MATS[i] = string.format("particle/smokesprites_%04d", i) end

	local function Smoke(pos, vel, col, alpha, size, life)
		emitter = emitter or ParticleEmitter(pos, false)
		local p = emitter:Add(MATS[math.random(#MATS)], pos)
		if not p then return end
		p:SetVelocity(vel)
		p:SetDieTime(life)
		p:SetStartAlpha(alpha)
		p:SetEndAlpha(0)
		p:SetStartSize(size)
		p:SetEndSize(size * 2.6)
		p:SetRoll(math.Rand(0, 360))
		p:SetRollDelta(math.Rand(-1.2, 1.2))
		p:SetColor(col.r, col.g, col.b)
		p:SetGravity(Vector(0, 0, 14))
		p:SetAirResistance(60)
	end

	local function SmokeCol(ent)
		return ent.Hacked and ent.HackedSmokeColor or ent.SmokeColor
	end

	local nextEmit = 0
	hook.Add("Think", "MM_ShadowhackSmoke", function()
		local now = CurTime()
		if now < nextEmit then return end
		nextEmit = now + 0.04
		local eye = EyePos()
		for _, e in ipairs(ents.GetAll()) do
			if IsValid(e) and e.IsShadowhack and not e:IsDormant() and e:GetPos():DistToSqr(eye) < 2500 ^ 2 then
				local col = SmokeCol(e)
				local c = e:WorldSpaceCenter()
				local clone = e:GetNWBool("MMShadowClone", false)
				for i = 1, clone and 1 or 2 do
					Smoke(c + VectorRand() * 7, VectorRand() * 22 + Vector(0, 0, 8), col, clone and 70 or 110, math.Rand(6, 10), math.Rand(0.7, 1.3))
				end
				-- a trail behind it while it moves
				local v = e:GetVelocity()
				if v:LengthSqr() > 90 ^ 2 then
					Smoke(c - v:GetNormalized() * 8, -v * 0.08 + VectorRand() * 10, col, clone and 60 or 90, 9, 0.9)
				end
			end
		end
	end)

	-- the burst when the clones are called up
	net.Receive("MM_ShadowPuff", function()
		local pos, hacked, n = net.ReadVector(), net.ReadBool(), net.ReadUInt(6)
		local col = hacked and PUFF_GREEN or PUFF_RED
		for i = 1, n do
			Smoke(pos + VectorRand() * 6, VectorRand() * 90, col, 150, math.Rand(10, 16), math.Rand(0.8, 1.6))
		end
	end)
end

if not SERVER then return end

util.AddNetworkString("MM_ShadowPuff")

local function PuffNet(pos, hacked, n)
	net.Start("MM_ShadowPuff")
	net.WriteVector(pos)
	net.WriteBool(hacked)
	net.WriteUInt(n or 14, 6)
	net.SendPVS(pos)
end

local ManhackBase
local function MB() ManhackBase = ManhackBase or scripted_ents.GetStored("snpc_manhack").t return ManhackBase end

function ENT:OnVariantSpawned()
	self.NextSlash = 0
	self.Clones = self.Clones or {}
	self.Energy = self.EnergyStart
	self.NextCloneTime, self.NextTele, self.NextTeleCheck = 0, CurTime() + self.TeleCooldown, 0
	self:SetNWFloat("MMShadowEnergy", self.Energy)
	if self.IsClone then
		self:KillSprites()   -- clones have no glowing eyes
		self:SetRenderMode(RENDERMODE_TRANSALPHA)
		self:SetColor(Color(0, 0, 0, 120))
		self.SlashDamage = self.SlashDamage * self.CloneDamageScale
		self.MaxSpeed = self.CloneSpeed
	end
end

local function Puff(pos, hacked)
	PuffNet(pos, hacked, 16)
end

-- the clones pour out of the shadowhack one after another and fly to their places in the row
function ENT:SpawnClones(foe)
	PuffNet(self:WorldSpaceCenter(), self.Hacked, 24)
	if not self.Silent then self:EmitSound("ambient/levels/citadel/portal_beam_loop1.wav", 70, 160, 0.4) end
	timer.Simple(0.6, function() if IsValid(self) then self:StopSound("ambient/levels/citadel/portal_beam_loop1.wav") end end)

	for i = 1, self.CloneCount do
		timer.Simple((i - 1) * 0.07, function()
			if not IsValid(self) or self.Crashing or self.Gibbed then return end
			local fwd, right = self:GetForward(), self:GetRight()
			local start = self:GetPos() + self:GetUp() * 8
			local spread = (i - (self.CloneCount + 1) / 2) * self.CloneSpacing
			local dest = start + fwd * 90 + right * spread
			local tr = util.TraceHull({ start = start, endpos = dest, mins = self.HullMins, maxs = self.HullMaxs, filter = self })
			local slot = tr.Hit and (tr.HitPos - (dest - start):GetNormalized() * 6) or tr.HitPos

			local c = ents.Create(self:GetClass())
			if not IsValid(c) then return end
			c.IsClone = true
			c.CloneOf = self
			c.EyeAttachments = {}   -- no eye glows on clones
			c.SpawnHealth = math.max(1, math.floor(self.SpawnHealth * self.CloneHealthScale))
			c:SetPos(self:GetPos() + fwd * 6)   -- starts inside the shadowhack
			c:SetAngles(self:GetAngles())
			c:Spawn()
			c:Activate()
			c:SetNWBool("MMShadowClone", true)
			c.EmergeUntil = CurTime() + 0.45
			c.EmergeStart = CurTime()
			-- no bumping into its parent while it comes out
			constraint.NoCollide(c, self, 0, 0)
			local vel = (slot - c:GetPos()) / 0.4
			if c.CurVel then c.CurVel = vel end
			local phys = c:GetPhysicsObject()
			if IsValid(phys) then phys:SetVelocity(vel) end
			if c.AcquireTarget then c:AcquireTarget(foe) end
			PuffNet(c:GetPos(), self.Hacked, 6)
			self.Clones[#self.Clones + 1] = c
		end)
	end
end

function ENT:FreeSpot(pos)
	for i = 1, 8 do
		local c = pos + Vector(math.Rand(-70, 70), math.Rand(-70, 70), math.Rand(-20, 40)) * (i > 1 and 1 or 0)
		local tr = util.TraceHull({ start = c, endpos = c, mins = self.HullMins, maxs = self.HullMaxs, filter = self, mask = MASK_SOLID })
		if not tr.StartSolid and not tr.Hit then return c end
	end
end

function ENT:TeleportTo(pos)
	Puff(self:WorldSpaceCenter(), self.Hacked)
	local phys = self:GetPhysicsObject()
	self:SetPos(pos)
	if IsValid(phys) then phys:SetPos(pos) phys:SetVelocity(vector_origin) end
	if self.CurVel then self.CurVel = vector_origin end
	Puff(pos, self.Hacked)
	if not self.Silent then self:EmitSound("ambient/energy/whiteflash.wav", 75, 70, 0.6) end
end

-- Far from its target it jumps closer, near its target it may pop up behind it (long cooldown).
function ENT:TryTeleport(foe, now)
	if now < self.NextTele or now < self.NextTeleCheck or self.Energy < self.TeleportCost then return end
	self.NextTeleCheck = now + 1
	local mine, theirs = self:WorldSpaceCenter(), foe:WorldSpaceCenter()
	local d = mine:Distance(theirs)
	local dest
	if d > self.TeleDashDist then
		dest = theirs + (mine - theirs):GetNormalized() * self.TeleDashStop
	elseif d < 650 and math.random() < 0.4 then
		local away = foe.GetAimVector and foe:GetAimVector() or foe:GetForward()
		away.z = 0
		dest = theirs - away:GetNormalized() * self.TeleFlankDist
	end
	if not dest then return end
	local spot = self:FreeSpot(dest)
	if not spot then return end
	self.Energy = self.Energy - self.TeleportCost
	self.NextTele = now + self.TeleCooldown + math.Rand(0, 5)
	self:TeleportTo(spot)
end

function ENT:OnVariantThink(dt)
	local now = CurTime()
	if self.IsClone then
		-- fade in while it comes out of the shadowhack
		if self.EmergeUntil and now < self.EmergeUntil then
			local f = math.Clamp((now - self.EmergeStart) / 0.45, 0, 1)
			self:SetColor(Color(0, 0, 0, math.floor(120 * f)))
			if self.CurVel and IsValid(self.CloneOf) then self.CurVel = self.CurVel * 0.97 end
		end
		-- gone in a puff of smoke when the one that called it is destroyed
		if not IsValid(self.CloneOf) or self.CloneOf.Crashing or self.CloneOf.Gibbed then
			Puff(self:GetPos(), self.Hacked)
			self:Remove()
			return
		end
	end
	if self.Held or self.Crashing or self.Packed then return end

	-- Shadow Energy
	if not self.IsClone then
		self.Energy = self.Energy + self.EnergyRegen * dt
		self.Energy = math.Clamp(self.Energy, 0, self.EnergyMax)
		if now >= (self.NextEnergyNW or 0) then
			self.NextEnergyNW = now + 0.2
			self:SetNWFloat("MMShadowEnergy", self.Energy)
		end
	end

	local foe = self:GetFoe()
	if not IsValid(foe) then return end

	if not self.IsClone then
		-- calls up the clones (when none of the last batch are left) if it can pay for it
		if now >= self.NextCloneTime and self.Energy >= self.CloneCost
			and self:WorldSpaceCenter():Distance(foe:WorldSpaceCenter()) <= self.CloneTrigger then
			local alive = 0
			for _, c in ipairs(self.Clones) do if IsValid(c) and not c.Crashing then alive = alive + 1 end end
			if alive == 0 then
				self.Clones = {}
				self.Energy = self.Energy - self.CloneCost
				self.NextCloneTime = now + self.CloneCooldown
				self:SpawnClones(foe)
			end
		end
		self:TryTeleport(foe, now)
	end

	if now < self.NextSlash then return end
	local hit = false
	local me = self:WorldSpaceCenter()
	for _, e in ipairs(ents.FindInSphere(me, self.SlashRange * 1.6)) do
		-- centre-to-centre distance, as in the original (the sphere search alone would count a big target's whole bounding box)
		if e ~= self and IsValid(e) and me:Distance(e:WorldSpaceCenter()) <= self.SlashRange and (e == foe or ((e:IsNPC() or e:IsPlayer()) and self:GetDisposition(e) == D_HT)) then
			if not (e:IsPlayer() and not e:Alive()) then
				local d = DamageInfo()
				d:SetDamage(self.SlashDamage)
				d:SetDamageType(DMG_SLASH)
				d:SetAttacker(self)
				d:SetInflictor(self)
				d:SetDamagePosition(e:WorldSpaceCenter())
				e:TakeDamageInfo(d)
				hit = true
			end
		end
	end
	if hit then self.NextSlash = now + self.SlashInterval end
end

function ENT:ModifyDamage(dmg)
	dmg:SetDamageForce(dmg:GetDamageForce() * self.ForceScale)
	if dmg:IsBulletDamage() or dmg:IsDamageType(DMG_CLUB) then dmg:ScaleDamage(self.BulletTaken) end
	if dmg:IsDamageType(DMG_CRUSH) or dmg:IsDamageType(DMG_FALL) or dmg:IsDamageType(DMG_VEHICLE) then
		dmg:SetDamage(math.min(dmg:GetDamage() * self.CrushTaken, self.CrushCap))
	end
	return MB().ModifyDamage(self, dmg)
end

-- a clone that is killed just dissolves into smoke (no wreck, no gibs)
function ENT:StartDying(...)
	if self.IsClone then
		Puff(self:GetPos(), self.Hacked)
		SafeRemoveEntityDelayed(self, 0)
		return
	end
	return scripted_ents.Get("snpc_manhack").StartDying(self, ...)
end

function ENT:SpawnGibs(pos, baseVel)
	Puff(pos, self.Hacked)
	local ex = EffectData()
	ex:SetOrigin(pos) ex:SetScale(1) ex:SetMagnitude(1)
	util.Effect("Explosion", ex)
	scripted_ents.GetStored("base_physics_snpc").t.SpawnGibs(self, pos, baseVel)
end

function ENT:OnVariantDeath()
	for _, c in ipairs(self.Clones or {}) do
		if IsValid(c) then Puff(c:GetPos(), self.Hacked) c:Remove() end
	end
end
