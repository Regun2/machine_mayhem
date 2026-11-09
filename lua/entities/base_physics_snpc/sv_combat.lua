--[[-------------------------------------------------------------------------
	sv_combat.lua  -  damage in, blades out, death

	Extra overridable hooks defined here:
		ENT:FilterDamage(dmg)         return false to ignore the hit entirely
		ENT:ModifyDamage(dmg)         scale / edit the damage before it hits health
		ENT:GetSliceDamage(ent, dt)   damage dealt to `ent` per blade hit
		ENT:CanSlice(ent)             may this thing cut `ent`?
		ENT:OnSliced(ent)             after a successful blade hit
		ENT:ShouldGib(dmg)            true = break apart instantly instead of crashing
		ENT:OnGibbed()
---------------------------------------------------------------------------]]

-- sounds (script names). Empty = silent.
ENT.SliceSound = ""
ENT.GrindSound = ""
ENT.DeathSound = ""

-- blade
ENT.BladeDamage        = 10   -- damage per second of blade contact
ENT.PlayerDamageScale  = 1
ENT.SliceInterval      = 0.1  -- seconds between blade hits
ENT.BumpSuppressTime   = 0.5

util.AddNetworkString("PhysSNPC_Corpse")

function ENT:InitCombat()
	for _, m in ipairs(self.GibModels or {}) do util.PrecacheModel(m) end
	self.Contacts = {}
	self.NextSlice = 0
	self.NextImpact = 0
	self.BumpSuppress = 0
	self.NextSpark = 0
	self.PhysAttacker = nil
	self.PhysAttackerTime = 0
	self.Held = false
end

function ENT:OnGibbed() end
function ENT:OnSliced(ent) end
function ENT:ModifyDamage(dmg) end

-- Only big hits (explosions, crossbow bolts, flung into a wall...) break it apart.
function ENT:ShouldGib(dmg)
	return dmg:IsDamageType(bit.bor(DMG_BLAST, DMG_ALWAYSGIB)) or dmg:GetDamage() >= self.GibDamage
end

-- How long between blade hits. Override to vary (e.g. rapid while held).
function ENT:GetSliceInterval() return self.SliceInterval end

--=========================================================================
-- Physics attacker (gravity gun / physgun thrown objects)
--=========================================================================

function ENT:HasPhysicsAttacker(dt)
	if self.Held or (CurTime() - dt <= self.PhysAttackerTime) then
		if IsValid(self.PhysAttacker) then return self.PhysAttacker end
	end
	return nil
end

function ENT:OnGravGunPickup(ply)
	self.PhysAttacker = ply
	self.PhysAttackerTime = CurTime()
	self.Held = true
end

function ENT:OnGravGunDrop(ply)
	self.Held = false
	self.PhysAttackerTime = CurTime()
end

function ENT:OnGravGunPunt(ply)
	self.Held = false
	self.PhysAttacker = ply
	self.PhysAttackerTime = CurTime()
	self.EngineStallTime = CurTime() + 2 -- engine out while flying through the air
	self.CurVel = Vector(0, 0, 0)
end

hook.Add("GravGunPickupAllowed", "PhysSNPC_NoPickup", function(ply, ent)
	if IsValid(ent) and ent.IsPhysicsSNPC and ent.AllowGravGun == false then return false end
end)
hook.Add("GravGunPunt", "PhysSNPC_NoPunt", function(ply, ent)
	if IsValid(ent) and ent.IsPhysicsSNPC and ent.AllowGravGun == false then return false end
end)

hook.Add("GravGunOnPickedUp", "PhysSNPC_Pickup", function(ply, ent)
	if IsValid(ent) and ent.IsPhysicsSNPC then ent:OnGravGunPickup(ply) end
end)
hook.Add("GravGunOnDropped", "PhysSNPC_Drop", function(ply, ent)
	if IsValid(ent) and ent.IsPhysicsSNPC then ent:OnGravGunDrop(ply) end
end)
hook.Add("GravGunPunt", "PhysSNPC_Punt", function(ply, ent)
	if IsValid(ent) and ent.IsPhysicsSNPC then ent:OnGravGunPunt(ply) end
end)
hook.Add("OnPhysgunPickup", "PhysSNPC_PhysgunPickup", function(ply, ent)
	if IsValid(ent) and ent.IsPhysicsSNPC then ent:OnGravGunPickup(ply) end
end)
hook.Add("PhysgunDrop", "PhysSNPC_PhysgunDrop", function(ply, ent)
	if IsValid(ent) and ent.IsPhysicsSNPC then ent:OnGravGunDrop(ply) end
end)

--=========================================================================
-- Taking damage
--=========================================================================

function ENT:FilterDamage(dmg)
	-- friends never hurt each other (blades, thrown friends, crashes...)
	local atk = dmg:GetAttacker()
	if IsValid(atk) and atk ~= self and atk.IsPhysicsSNPC and self:IsFriendlyTo(atk) then return false end
	-- Ordinary collisions are harmless unless something big or thrown hits us.
	if dmg:IsDamageType(DMG_CRUSH) then
		local inf = dmg:GetInflictor()
		local dangerous = IsValid(inf) and (inf:IsVehicle() or inf:GetClass() == "prop_combine_ball"
			or (inf.GetPhysicsAttacker and IsValid(inf:GetPhysicsAttacker())))
		if not dangerous then dmg:ScaleDamage(self.PhysicsImpactScale) end
	end
	return dmg:GetDamage() > 0
end

-- Applies the damage force to the physics object (what VPhysicsTakeDamage does in Valve's code).
function ENT:ApplyDamageForce(dmg, scale)
	local phys = self:GetPhysicsObject()
	if not IsValid(phys) then return end
	local f = dmg:GetDamageForce() * (scale or 1)
	if f:IsZero() then return end
	local pos = dmg:GetDamagePosition()
	if pos:IsZero() then pos = self:GetPos() end
	phys:ApplyForceOffset(f, pos)
end

function ENT:OnTakeDamage(dmg)
	if self.Crashing then
		-- like Valve's OnTakeDamage_Dying: just get shoved around
		self:ApplyDamageForce(dmg)
		return 0
	end

	if not self:FilterDamage(dmg) then return 0 end
	self:ModifyDamage(dmg)

	local amount = dmg:GetDamage()
	if amount <= 0 then return 0 end

	local hp = self:Health() - amount
	if hp <= 0 then
		self:SetHealth(0)
		self:StartDying(dmg)
	else
		self:SetHealth(hp)
		if hp <= self:GetMaxHealth() * 0.5 then self:CreateSmokeTrail() end
		self:OnDamaged(dmg)
	end
	return amount
end

-- Direct damage that skips FilterDamage (thrown-object impacts etc.)
function ENT:InflictDamage(amount, attacker, inflictor, dtype)
	local dmg = DamageInfo()
	dmg:SetDamage(amount)
	dmg:SetAttacker(IsValid(attacker) and attacker or game.GetWorld())
	dmg:SetInflictor(IsValid(inflictor) and inflictor or game.GetWorld())
	dmg:SetDamageType(dtype or DMG_GENERIC)
	dmg:SetDamagePosition(self:GetPos())
	dmg:SetDamageForce(Vector(1, 1, 1))
	return self:OnTakeDamage(dmg)
end

--=========================================================================
-- Physics contact -> queued, then processed on the next think
-- (never do TakeDamage / Remove inside the VPhysics callback)
--=========================================================================

function ENT:PhysicsCollide(data, phys)
	if #self.Contacts >= 6 then return end
	self.Contacts[#self.Contacts + 1] = {
		ent = data.HitEntity,
		HitPos = data.HitPos,
		HitNormal = data.HitNormal,
		speed = data.Speed,
		oldVel = data.OurOldVelocity,
		theirVel = data.TheirOldVelocity,
	}
end

function ENT:ProcessContacts(dt)
	local list = self.Contacts
	if not list or #list == 0 then return end
	self.Contacts = {}

	if self.Crashing then
		self.PendingGib = true -- Valve's CrashTouch: explode on touching anything
		return
	end

	for _, c in ipairs(list) do
		if IsValid(c.ent) then
			if not self:OnContact(c.ent, c) then
				self:HandleContact(c.ent, c)
			end
		end
	end
end

-- Slamming into the world / a prop at high speed (gravity-gun punt, physgun fling,
-- explosion...) hurts a LOT, proportional to speed and independent of max health,
-- so a tanky variant is not auto-killed by a mild bump.
-- Called every tick with the physics velocity of the previous and the current tick. A sudden big drop
-- in speed while we were being carried by something other than our own engine (gravity-gun punt,
-- physgun fling, explosion, a thrown prop...) means we hit something hard. This does not rely on
-- the PhysicsCollide callback (which is unreliable for NPC-type entities).
-- Overridable: change how much a wall impact hurts (e.g. a shield that takes the hit).
function ENT:AdjustImpactDamage(amount, speed) return amount end

function ENT:CheckVelocityImpact(prevVel, vel, prevDesired)
	if self.Crashing or self.Held then return end
	if prevVel:Length() < self.ImpactSpeed then return end
	local drop = (prevVel - vel):Length()
	if drop < self.ImpactSpeed * 0.75 then return end
	-- own flight at high speed (e.g. a fast variant) is not an "impact"
	local external = (prevVel - (prevDesired or Vector())):Length() >= self.ImpactSpeed * 0.5
	if not external and not self:HasPhysicsAttacker(1.5) then return end

	-- world geometry only: something solid of the map right in front of us, not an NPC / prop we cut
	local pos = self:GetPos()
	local tr = util.TraceHull({
		start = pos, endpos = pos + prevVel:GetNormalized() * (self.HullSize + 35),
		mins = self.HullMins, maxs = self.HullMaxs,
		mask = MASK_SOLID_BRUSHONLY, filter = self,
	})
	if not (tr.Hit or tr.StartSolid) then return end

	local now = CurTime()
	if now < self.NextImpact then return end
	self.NextImpact = now + 0.3

	local thrower = self:HasPhysicsAttacker(1.5) or game.GetWorld()
	-- DMG_GENERIC on purpose: FilterDamage shrinks DMG_CRUSH to ~nothing (ordinary bumps are harmless)
	local amount = self:AdjustImpactDamage(self.ImpactDamage * drop / self.ImpactSpeed, drop)
	if self.ImpactSurviveFraction then
		local floor = self:GetMaxHealth() * self.ImpactSurviveFraction
		if self:Health() > floor then
			-- (damage taken scale applies later, so account for it)
			amount = math.min(amount, (self:Health() - floor) / math.max(self.DamageTakenScale or 1, 0.01))
		end
	end
	self:InflictDamage(amount, thrower, thrower, DMG_GENERIC)
	if GetConVar("physsnpc_debug"):GetBool() then print(("[physsnpc] #%d impact, speed change %d u/s"):format(self:EntIndex(), drop)) end
end

function ENT:CheckImpact(c)
	if self.Crashing then return end
	local ent = c.ent
	if IsValid(ent) and self:CanSlice(ent) then return end -- living things are cut, not slammed into
	local rel = (c.oldVel or Vector()) - (c.theirVel or Vector())
	local speed = math.max(rel:Length(), c.speed or 0)
	if speed < self.ImpactSpeed then return end
	local thrower = self:HasPhysicsAttacker(1) or game.GetWorld()
	-- DMG_GENERIC on purpose: FilterDamage shrinks DMG_CRUSH to ~nothing (ordinary bumps are harmless)
	self:InflictDamage(self.ImpactDamage * speed / self.ImpactSpeed, thrower, thrower, DMG_GENERIC)
	if GetConVar("physsnpc_debug"):GetBool() then print(("[physsnpc] #%d impact at %d u/s"):format(self:EntIndex(), speed)) end
end

-- Thrown-object / vehicle damage to *us*.
function ENT:TakeContactDamage(ent, c)
	local thrower = self:HasPhysicsAttacker(0.35)
	if thrower then
		if ent:IsNPC() or ent:IsPlayer() then return end -- do not hurt ourselves on what we are cutting
		local factor = math.Clamp((c.speed or 0) / 500, 0, 2)
		self:InflictDamage(self:GetMaxHealth() * factor, thrower, thrower, DMG_GENERIC)
		return true
	end

	if ent:IsVehicle() then
		local speed = math.Clamp((c.theirVel and c.theirVel:Length() or 0), 300, 600)
		local f = (speed - 300) / 300
		f = f * f * (3 - 2 * f)
		if f > 0 then
			self:InflictDamage(20 * f, ent, ent, DMG_CRUSH)
		end
		return true
	end

	local pa = ent.GetPhysicsAttacker and ent:GetPhysicsAttacker()
	if IsValid(pa) then
		local ph = ent:GetPhysicsObject()
		local mass = IsValid(ph) and math.min(ph:GetMass(), 200) or 10
		local dmg = math.max(0, ((c.speed or 0) - 100) * mass / 400)
		if dmg > 0 then self:InflictDamage(dmg, pa, ent, DMG_CRUSH) end
		return true
	end
	return false
end

function ENT:HandleContact(ent, c)
	if self:TakeContactDamage(ent, c) and self.Crashing then return end
	if self.Crashing then return end

	if self:CanSlice(ent) and CurTime() >= self.NextSlice then
		self:Slice(ent, c)
	else
		self:Bump(ent, c)
	end
end

--=========================================================================
-- Blades
--=========================================================================

function ENT:CanSlice(ent)
	if not IsValid(ent) or ent:IsWorld() then return false end
	if self:IsFriendlyTo(ent) then return false end
	if ent.IsPhysicsSNPC and ent:GetNPCClass() == self:GetNPCClass() then return false end
	if ent:IsPlayer() and not ent:Alive() then return false end
	if self:WaterLevel() > 0 and ent:IsPlayer() then return false end -- do not hurt players from the water
	return ent:IsNPC() or ent:IsPlayer() or ent:IsNextBot() or ent:Health() > 0
end

function ENT:GetSliceDamage(ent, interval)
	local d = self.BladeDamage * interval
	if ent:IsPlayer() then d = d * self.PlayerDamageScale end
	return math.max(d, 1)
end

function ENT:Slice(ent, c)
	if GetConVar("physsnpc_debug"):GetBool() then print(("[physsnpc] #%d slices %s"):format(self:EntIndex(), tostring(ent))) end
	local interval = self:GetSliceInterval()
	local attacker = self:HasPhysicsAttacker(0.35) or self

	local dmg = DamageInfo()
	dmg:SetAttacker(attacker)
	dmg:SetInflictor(self)
	dmg:SetDamage(self:GetSliceDamage(ent, interval))
	dmg:SetDamageType(DMG_SLASH)
	local dir = ent:WorldSpaceCenter() - self:GetPos()
	dir:Normalize()
	dmg:SetDamageForce(dir * dmg:GetDamage() * 100)
	dmg:SetDamagePosition(c.HitPos or ent:WorldSpaceCenter())
	ent:TakeDamageInfo(dmg)

	local hitPos = c.HitPos or ent:WorldSpaceCenter()
	local bc = ent.GetBloodColor and ent:GetBloodColor()
	if type(bc) ~= "number" or bc == DONT_BLEED or bc == -1 then
		local ed = EffectData()
		ed:SetOrigin(hitPos)
		ed:SetAngles(self:GetAngles())
		ed:SetNormal(((c.HitNormal or -dir) + self.CurVel:GetNormalized()) * 0.5)
		util.Effect("ManhackSparks", ed)
		if self.GrindSound ~= "" and not self.Silent then self:EmitSound(self.GrindSound) end
	else
		local ed = EffectData()
		ed:SetOrigin(hitPos)
		ed:SetColor(bc)
		ed:SetScale(6)
		util.Effect("BloodImpact", ed)
		if self.SliceSound ~= "" and not self.Silent then self:EmitSound(self.SliceSound) end
	end

	self:SliceBounce(ent)
	self.NextSlice = CurTime() + interval
	self:OnSliced(ent)
end

-- Pop away a little after cutting something (ComputeSliceBounceVelocity).
function ENT:SliceBounce(ent)
	if ent:GetClass() == "func_breakable_surf" then return end -- let us fly through glass
	local dir = self:WorldSpaceCenter() - ent:WorldSpaceCenter()
	dir:Normalize()
	dir = dir * 200
	dir.z = 0
	self.CurVel = dir
end

-- Sweeps along the flight path so we also cut things physics did not report this tick.
function ENT:BladeTrace(dt)
	local now = CurTime()
	if self.Crashing or now < self.NextSlice then return end
	if now < (self.NextBladeTrace or 0) then return end
	local elapsed = now - (self.LastBladeTrace or (now - dt))
	self.LastBladeTrace = now
	self.NextBladeTrace = now + 0.04 * math.min(self:LoadScale(), 2) -- fewer sweeps when there are many of us

	local phys = self:GetPhysicsObject()
	local vel = IsValid(phys) and phys:GetVelocity() or self.CurVel
	local pos = self:GetPos()

	local tr = util.TraceHull({
		start = pos, endpos = pos + vel * math.Clamp(elapsed, 0.03, 0.25),
		mins = self.HullMins, maxs = self.HullMaxs,
		filter = self, mask = MASK_NPCSOLID,
	})
	local ent = tr.Entity
	if (tr.Hit or tr.StartSolid) and IsValid(ent) and not ent:IsWorld() and self:CanSlice(ent) then
		self:Slice(ent, { HitPos = tr.HitPos, HitNormal = tr.HitNormal })
	end
end

--=========================================================================
-- Bumping into things we do not cut
--=========================================================================

-- Port of CNPC_Manhack::HitPhysicsObject: shove loose props sideways like a spinning blade.
function ENT:ShoveProp(ent)
	local ph = ent:GetPhysicsObject()
	if not IsValid(ph) then return end
	local dir = ent:GetPos() - self:GetPos()
	dir:Normalize()
	local pos = self:GetPos() + dir * (self.HullSize * 0.5)
	local cross = dir:Cross(Vector(0, 0, 1))
	cross:Normalize()
	ph:ApplyForceOffset(cross * 30 * 100, pos)
end

function ENT:Bump(ent, c)
	local now = CurTime()
	if now < self.BumpSuppress then return end

	if IsValid(ent) and ent:GetMoveType() == MOVETYPE_VPHYSICS and not ent.IsPhysicsSNPC then
		self:ShoveProp(ent)
	end

	-- surface normal that opposes our motion (HitNormal's sign convention varies)
	local n = c.HitNormal and Vector(c.HitNormal) or Vector(0, 0, 1)
	local v = c.oldVel or self.CurVel
	if n:Dot(v) > 0 then n = -n end

	local speed = self.CurVel:Length()
	self:DeflectVelocity(n, speed)

	-- hit with the blade edge? sparks, grind noise, a bit of spin, a scratch decal
	if math.abs(self:GetUp():Dot(n)) < 0.25 then
		local hitPos = c.HitPos or self:GetPos()
		local ed = EffectData()
		ed:SetOrigin(hitPos)
		ed:SetAngles(self:GetAngles())
		ed:SetNormal((n + self.CurVel:GetNormalized()) * 0.5)
		util.Effect("ManhackSparks", ed)

		if self.GrindSound ~= "" and not self.Silent then self:EmitSound(self.GrindSound) end

		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:AddAngleVelocity(Vector(0, 0, 360)) end -- local z = our up axis

		if math.abs(n.z) < 0.5 then
			util.Decal("ManhackCut", self:GetPos(), hitPos - n * 24, self)
		end
	end
end

--=========================================================================
-- Death
--=========================================================================

function ENT:StartDying(dmg)
	if self.Crashing then return end
	self.Crashing = true
	self.CrashStart = CurTime()

	self:SetFoe(NULL)
	self:ReleaseAttackSlot()
	self:AddFlags(FL_NOTARGET) -- other NPCs stop shooting at the wreck
	self:DestroySmokeTrail()

	if self.DeathSound ~= "" and not self.Silent then self:EmitSound(self.DeathSound) end

	for _ = 1, 3 do
		local ed = EffectData()
		ed:SetOrigin(self:GetPos() + VectorRand() * 12)
		ed:SetMagnitude(2)
		ed:SetScale(1)
		ed:SetRadius(2)
		util.Effect("ElectricSpark", ed)
	end

	-- kill feed / scoring (sandbox's GM:OnNPCKilled)
	hook.Run("OnNPCKilled", self, dmg:GetAttacker(), dmg:GetInflictor())

	self:OnStartDying(dmg)

	if self:ShouldGib(dmg) then
		self:Gib()
		return
	end

	-- immediately become a corpse carrying our current velocity
	if self.ClientCorpse and self.ImmediateCorpse then
		self:MakeCorpse()
		return
	end

	-- slow crash: keep (or give) some forward speed, then fall until something is hit
	local phys = self:GetPhysicsObject()
	local v = IsValid(phys) and phys:GetVelocity() or Vector()
	if v:Length() < 120 then v = v + VectorRand() * 120 end
	v.z = math.min(v.z, 50)
	self.CurVel = v
	self.ForceVel = Vector(0, 0, 0)
	self.EngineStallTime = 0
end

function ENT:CrashEffects(dt)
	if self.PendingGib then self:CrashEnd() return end
	local now = CurTime()
	if now < self.NextSpark then return end
	self.NextSpark = now + math.Rand(0.1, 0.3)

	local ed = EffectData()
	ed:SetOrigin(self:GetPos())
	ed:SetMagnitude(1)
	ed:SetScale(1)
	ed:SetRadius(1)
	util.Effect("ElectricSpark", ed)
end

-- Replace the SNPC with a client-side corpse that keeps its speed, direction and spin.
function ENT:MakeCorpse()
	if self.Gibbed then return end
	self.Gibbed = true

	local phys = self:GetPhysicsObject()
	local vel, ang = Vector(), Vector()
	if IsValid(phys) then
		vel = phys:GetVelocity()
		ang = phys:GetAngleVelocity()
		if self.CurVel and self.CurVel:LengthSqr() > vel:LengthSqr() then vel = Vector(self.CurVel) end
		phys:EnableMotion(false)
	end

	self:OnGibbed()
	net.Start("PhysSNPC_Corpse")
		net.WriteEntity(self)
		net.WriteVector(vel)
		net.WriteVector(ang)
		net.WriteFloat(self.CorpseLifetime)
	net.Broadcast()
	self:SetNoDraw(true)
	self:SetNotSolid(true)
	SafeRemoveEntityDelayed(self, 0.5) -- long enough for the clients to build the corpse
end

-- End of a (slow) crash: sparks and a bang, then the corpse (or just removal).
function ENT:CrashEnd()
	if self.Gibbed then return end
	if self.GibOnCrash then self:Gib() return end

	local pos = self:WorldSpaceCenter()
	for _ = 1, 4 do
		local ed = EffectData()
		ed:SetOrigin(pos + VectorRand() * 6)
		ed:SetMagnitude(3) ed:SetScale(2) ed:SetRadius(3)
		util.Effect("ElectricSpark", ed)
	end
	local ed = EffectData()
	ed:SetOrigin(pos) ed:SetScale(1) ed:SetMagnitude(1) ed:SetNormal(Vector(0, 0, 1))
	util.Effect("ManhackSparks", ed)
	if self.CrashSound ~= "" then sound.Play(self.CrashSound, pos, 75, 100, 1) end

	if self.ClientCorpse then
		self:MakeCorpse()
	else
		self.Gibbed = true
		self:OnGibbed()
		self:Remove()
	end
end

-- Break apart: every gib flies off in its own direction with its own speed and spin.
function ENT:SpawnGibs(pos, baseVel)
	for i = 1, self.GibCount do
		local model = self.GibModels[((i - 1) % #self.GibModels) + 1]
		local g = ents.Create("prop_physics")
		if IsValid(g) then
			g:SetModel(model)
			g:SetPos(pos + VectorRand() * 6)
			g:SetAngles(AngleRand())
			g:Spawn()
			g:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
			local gp = g:GetPhysicsObject()
			if IsValid(gp) then
				gp:Wake()
				gp:SetVelocity(baseVel * 0.4 + VectorRand():GetNormalized() * math.Rand(self.GibSpeedMin, self.GibSpeedMax))
				gp:AddAngleVelocity(Vector(
					math.Rand(-1, 1), math.Rand(-1, 1), math.Rand(-1, 1)) * math.Rand(self.GibSpin * 0.3, self.GibSpin))
			end
			SafeRemoveEntityDelayed(g, self.GibLifetime + math.Rand(-2, 2))
		end
	end
end

function ENT:Gib()
	if self.Gibbed then return end
	self.Gibbed = true

	local phys = self:GetPhysicsObject()
	local vel = IsValid(phys) and phys:GetVelocity() or self.CurVel
	if self.GibModels and #self.GibModels > 0 then
		self:SpawnGibs(self:WorldSpaceCenter(), vel)
		local ed = EffectData()
		ed:SetOrigin(self:WorldSpaceCenter()) ed:SetScale(1) ed:SetMagnitude(2) ed:SetNormal(Vector(0, 0, 1))
		util.Effect("ManhackSparks", ed)
	else
		self:GibBreakServer(vel)
	end
	self:OnGibbed()
	self:Remove()
end

--=========================================================================
-- Smoke trail when badly damaged
--=========================================================================

function ENT:CreateSmokeTrail()
	if not self.DeathSmoke or IsValid(self.SmokeTrail) then return end
	local s = ents.Create("env_smoketrail")
	if not IsValid(s) then return end
	s:SetKeyValue("startsize", "8")
	s:SetKeyValue("endsize", "32")
	s:SetKeyValue("spawnradius", "5")
	s:SetKeyValue("minspeed", "15")
	s:SetKeyValue("maxspeed", "25")
	s:SetKeyValue("startcolor", "102 102 102")
	s:SetKeyValue("endcolor", "0 0 0")
	s:SetKeyValue("opacity", "1")
	s:SetKeyValue("spawnrate", "20")
	s:SetKeyValue("lifetime", "0.5")
	s:SetPos(self:GetPos())
	s:SetParent(self)
	s:Spawn()
	s:Activate()
	self.SmokeTrail = s
end

function ENT:DestroySmokeTrail()
	if IsValid(self.SmokeTrail) then self.SmokeTrail:Remove() end
	self.SmokeTrail = nil
end
