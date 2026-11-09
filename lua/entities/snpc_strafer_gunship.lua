--[[-------------------------------------------------------------------------
	Strafer Gunship - the "cybergunship" of Map Sweepers, remade as a Machine Mayhem gunship (only listed when Map Sweepers
	is installed; nothing from the gamemode is needed to run it).
	  * 1.25x size, three "hits" to kill: a bullet is 0.015 hit, a blast under 125 damage half a hit, anything bigger a whole one
	  * no belly cannon; its pulse rounds are explosive bolts (tight spread, 4 damage blasts) and it hits for a quarter damage
	  * every ~20 s it roars, sounds its siren, charges a deathray straight down (1.5 s) and strafes across its target
	    at high speed for ~15 s, burning a line of ground (120 dps, 64 wide)
	Credit for the original design: Map Sweepers by Octantis Addons (MerekiDor, JonahSoldier).
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base      = "snpc_gunship"
ENT.PrintName = "Strafer Gunship"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.ModelScale   = 1.25
ENT.SpawnHealth  = 1500
ENT.MaxHits      = 3
ENT.ShotDamage   = 10                      -- (the original scales its bullets by 0.25 against everything but players)
ENT.ShotSpread   = Vector(0.005, 0.005, 0)
ENT.StrafeDelay  = 20                      -- before the first strafe, and between strafes
ENT.StrafeTime   = 16
ENT.RayRadius    = 64
ENT.RayPrep      = 1.5
ENT.RayDPS       = 120
ENT.RayColour    = Vector(0.8, 0.5, 1)

if PhysSNPC_ModInstalled and PhysSNPC_ModInstalled("mapsweepers") then
	list.Set("MachineMayhem", "snpc_strafer_gunship", {
		Name = "Strafer Gunship", Class = "snpc_strafer_gunship", Group = "Bosses",
		Category = "Machine Mayhem", SubCategory = "Normal", Offset = 96,
	})
end

if CLIENT then return end

local SkinMat = "models/jcms/cybergunship/body"
local HackedMat = "models/cybergunship/body_hacked"

-- is there open air above this spot (the ray only reaches what is not under a roof)?
local function OpenAbove(pos, height)
	return util.TraceLine({ start = pos + Vector(0, 0, 40), endpos = pos + Vector(0, 0, height), mask = MASK_SOLID_BRUSHONLY }).Fraction >= 0.99
end

local function GB(name) return scripted_ents.Get("snpc_gunship")[name] end

function ENT:OnScannerSpawned()
	GB("OnScannerSpawned")(self)
	self.NextBelly = math.huge
	self.NextBlast = CurTime() + self.StrafeDelay
	self.Hits = self.MaxHits
	self.HitAcc = 0
	self.Strafe = nil
	self.BaseMaxSpeed, self.BaseAccel = self.MaxSpeed, self.FlightAccel
	if self.Hacked then
		self:SetSubMaterial(1, HackedMat)
		self.GibMaterial = HackedMat
	elseif file.Exists("materials/models/jcms/cybergunship/body.vmt", "GAME") then
		self:SetSubMaterial(1, SkinMat)
		self.GibMaterial = SkinMat
	end
end

function ENT:GetBeamAnchor()
	local id = self:LookupAttachment("BellyGun")
	local att = id and id > 0 and self:GetAttachment(id)
	return (att and att.Pos or self:GetPos()) - Vector(0, 0, 10)
end

-- hits, like the original's takeDamage
function ENT:ModifyDamage(dmg)
	if dmg:GetAttacker() == self or self.Crashing then dmg:SetDamage(0) return end
	local raw = dmg:GetDamage()
	local t = dmg:GetDamageType()
	if raw <= 0 or bit.band(t, bit.bor(DMG_BURN, DMG_SLOWBURN)) ~= 0 then dmg:SetDamage(0) return end
	local hits = raw < 50 and 0.015 or (raw < 125 and 0.5 or 1)
	self.HitAcc = self.HitAcc + hits
	local pos = dmg:GetDamagePosition()
	local now = CurTime()
	if self.HitAcc > 1 then
		self.HitAcc = 0
		local ed = EffectData()
		ed:SetOrigin(pos + VectorRand() * 25)
		util.Effect("Explosion", ed)
		if now >= (self.NextPain or 0) then
			self.NextPain = now + 1.2
			self:EmitSound("NPC_CombineGunship.Pain", 110, 100, 1, CHAN_VOICE)
		end
	end
	if now >= (self.NextShotDown or 0) then
		self.NextShotDown = now + 0.15
		local ed = EffectData()
		ed:SetOrigin(pos)
		util.Effect("RPGShotDown", ed)
	end
	if hits >= 0.5 then
		local dir = dmg:GetDamageForce()
		dir = dir:LengthSqr() > 0 and dir:GetNormalized() or VectorRand()
		self:DumpMetal(dir)
	end
	dmg:SetDamage(hits / self.MaxHits * self:GetMaxHealth())
end

function ENT:OnDamaged(dmg)
	local frac = self:Health() / self:GetMaxHealth()
	if frac < 0.7 then self:CreateSmokeTrail(frac <= 0.5) end
end

-- explosive bolts instead of the blue tracer
function ENT:ShotFX(muzzle, tr)
	local d = muzzle:Distance(tr.HitPos)
	local ed = EffectData()
	ed:SetStart(LerpVector(math.min(7 / math.max(d, 1), 1), muzzle, tr.HitPos))
	ed:SetOrigin(tr.HitPos)
	ed:SetScale(math.random(6500, 9000))
	util.Effect("physsnpc_bolt", ed)
	util.BlastDamage(self, self, tr.HitPos, 50, 4)
end

--=========================================================================
-- The strafing run
--=========================================================================
function ENT:StartStrafe(foe)
	self.Strafe = { start = CurTime(), phase = "prep", last = self:GetPos(), goal = self:GetPos() }
	self:AbortBurst()
	self:EmitSound("npc/combine_gunship/see_enemy.wav", 140, 80, 1, CHAN_AUTO)
	self:EmitSound("npc/strider/striderx_pain8.wav", 140, 80, 1, CHAN_AUTO)
	self.Siren = self.Siren or CreateSound(self, "ambient/alarms/apc_alarm_loop1.wav")
	if self.Siren then
		self.Siren:SetSoundLevel(120)
		self.Siren:PlayEx(0.75, 145)
	end
	timer.Simple(self.RayPrep - 1.4 > 0 and self.RayPrep - 1.4 or 0.1, function()
		if IsValid(self) and self.Strafe then self:EmitSound("npc/strider/charging.wav", 140, 80, 0.75, CHAN_AUTO) end
	end)
	local ray = ents.Create("physsnpc_deathray")
	if IsValid(ray) then
		ray:SetPos(self:GetBeamAnchor())
		ray.RayOwner = self
		ray:Spawn()
		-- parented to the belly so it moves with the hull every frame instead of trailing behind network updates
		local id = self:LookupAttachment("BellyGun")
		if id and id > 0 then
			ray:SetParent(self, id)
			ray:SetLocalPos(Vector(0, 0, -10))
			ray.RayParented = true
		end
		ray:SetBeamColour(self.RayColour)
		ray:SetBeamRadius(self.RayRadius)
		ray:SetBeamPrepTime(self.RayPrep)
		ray:SetBeamLifeTime(self.StrafeTime + 1.5 - self.RayPrep)
		ray.DPS, ray.DPS_DIRECT = self.RayDPS, self.RayDPS
		self.Ray = ray
	end
end

function ENT:EndStrafe()
	self.Strafe = nil
	self.MaxSpeed, self.FlightAccel = self.BaseMaxSpeed or self.MaxSpeed, self.BaseAccel or self.FlightAccel
	self.NextBlast = CurTime() + self.StrafeDelay
	if self.Siren then self.Siren:Stop() end
	if IsValid(self.Ray) then self.Ray:Remove() end
	self.Ray = nil
end

function ENT:OnScannerThink(dt)
	local now = CurTime()
	local st = self.Strafe
	if st then
		local el = now - st.start
		local f = self:GetFoe()
		if IsValid(f) and now >= (st.nextCover or 0) then
			st.nextCover = now + 0.5
			if OpenAbove(f:GetPos(), 900) then st.covered = nil else st.covered = st.covered or now end
		end
		if self.Crashing or el > self.StrafeTime or (st.covered and now - st.covered > 1.5) then
			self:EndStrafe()
		elseif st.phase == "prep" and el > self.RayPrep - 0.3 then
			st.phase = "run"
		end
	elseif not self.Crashing and not self.Held and now >= (self.NextBlast or 0) then
		local foe = self:GetFoe()
		if IsValid(foe) then
			if OpenAbove(foe:GetPos(), 1100) then self:StartStrafe(foe)
			else self.NextBlast = now + 3 end -- under a roof: the ray could not reach them, try again shortly
		end
	end
	GB("OnScannerThink")(self, dt)
	if self.Strafe then self:AbortBurst() end
end

local function Flat(v) return Vector(v.x, v.y, 0) end

-- The run: it stays right over the target, high up, and sweeps the beam back and forth across them (a lateral weave over the
-- target's predicted position) so the beam really crosses them, rather than flying long passes that mostly miss.
function ENT:UpdateMovement(dt)
	local st = self.Strafe
	if not st or self.Held or self.Crashing then return GB("UpdateMovement")(self, dt) end
	self.TurnRate = 60
	self.StuckTime = 0 -- (fast moves near geometry must not trigger the "back out upward" reflex)
	local pos = self:GetPos()
	local foe = self:GetFoe()
	if IsValid(foe) then st.lastFoe = foe:GetPos() st.lastVel = foe:GetVelocity() end
	local fpos = st.lastFoe or pos
	local fvel = st.lastVel or vector_origin

	-- fixed height over the ground under the target (not remembered / not accumulated), kept under any roof
	local gtr = util.TraceLine({ start = fpos + Vector(0, 0, 20), endpos = fpos - Vector(0, 0, 3000), mask = MASK_SOLID_BRUSHONLY })
	local groundZ = gtr.Hit and gtr.HitPos.z or fpos.z
	local alt = groundZ + 650
	local ctr = util.TraceLine({ start = fpos + Vector(0, 0, 40), endpos = fpos + Vector(0, 0, 4000), mask = MASK_SOLID_BRUSHONLY })
	if ctr.Hit then alt = math.min(alt, ctr.HitPos.z - 160) end
	st.alt = st.alt and math.Approach(st.alt, alt, 300 * dt) or alt -- smooth, so it cannot jump

	local lead = fpos + Flat(fvel) * 0.6
	local goal = Vector(lead.x, lead.y, st.alt)
	local speed = 1250
	if st.phase ~= "prep" then
		-- the weave: perpendicular to the way it is approaching, slow enough to dwell on the target each time across
		local to = Flat(goal - pos)
		local dir = to:LengthSqr() > 1 and to:GetNormalized() or self:GetForward()
		local right = Vector(dir.y, -dir.x, 0)
		goal = goal + right * math.sin((CurTime() - st.start) * 1.5) * 320
	else
		speed = 800
	end
	self.MaxSpeed = speed
	self.FlightAccel = (self.BaseAccel or 380) * 1.8
	self:FlyTo(dt, self:SteerAround(goal, foe), 1)
	self:LimitSpeed(self.MaxVertSpeed, speed)
end

function ENT:StartDying(dmg)
	if self.Strafe then self:EndStrafe() end
	GB("StartDying")(self, dmg)
end

function ENT:OnScannerRemoved()
	if self.Siren then self.Siren:Stop() end
	if IsValid(self.Ray) then self.Ray:Remove() end
	GB("OnScannerRemoved")(self)
end
