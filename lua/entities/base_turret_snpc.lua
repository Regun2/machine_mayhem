--[[-------------------------------------------------------------------------
	base_turret_snpc  -  recreation of the HL2 ceiling and floor turret NPCs
	on top of base_physics_snpc, using our own faction logic instead of the engine's relationships.

	State machine (same idea as Valve's): Disabled / AutoSearch (closed, sensing) / Deploy / Search (open,
	sweeping, "ping") / Active (tracking + shooting) / Retire / Tipped / SelfDestruct / Dying.

	Lua "inputs"  (ent:Enable() ...  or  ent:Fire("Enable") / ent:AcceptInput):
		Enable, Disable, Toggle, SelfDestruct, Deploy (wake up now), Retire (go back to sleep)
	Fields (set before :Spawn()):
		ent.Mounted = true, ent.MountOwner = <entity>   bolted to something (battle drone): no physics, never
		                                                targets the owner, never retires
		ent.DamageScale = 1                             multiplier on the bullet damage

	Not verified in-game: the pose parameter / attachment names are the ones the Valve source uses
	(aim_yaw, aim_pitch, "eyes", "light"); the aim direction signs are auto-calibrated at runtime.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Base      = "base_physics_snpc"
ENT.PrintName = "Turret Base"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.Locomotion  = "static"
ENT.AutomaticFrameAdvance = false -- animation is stepped by hand (see StepAnim)
ENT.NPCClass    = CLASS_COMBINE
ENT.AllowGravGun = false
ENT.DeathSmoke  = false
ENT.ClientCorpse = false
ENT.RenderGroup = RENDERGROUP_BOTH

ENT.TurretKind  = "ceiling"          -- "ceiling" | "floor" | "ground"
ENT.Model       = "models/combine_turrets/ceiling_turret.mdl"
ENT.SpawnHealth = 1000
ENT.HullSize    = 12

-- perception
ENT.SightRange    = 1500
ENT.SightFOV      = 180
ENT.SenseRange    = 0
ENT.ForgetTime    = 1.5
ENT.RetargetDelay = 0.2

-- aiming / shooting
ENT.AimSignY      = 1               -- which way the aim_yaw / aim_pitch pose parameters turn (-1 = reversed)
ENT.AimSignP      = 1
ENT.AimSpeed      = 150             -- degrees per second
ENT.FireRate      = 10              -- shots per second
ENT.ConeDeg       = 5               -- bullet cone (full angle, degrees)
ENT.BulletDamage  = nil             -- nil = take it from the npc damage convar
ENT.DamageConVar  = "sk_npc_dmg_ar2"
ENT.DamageDefault = 4
ENT.AmmoType      = "AR2"
ENT.TracerName    = "AR2Tracer"
ENT.AimDot        = 0.9848          -- how well the barrel must point at the target before it fires
ENT.SweepYaw      = 45
ENT.SweepPitch    = 15
ENT.SweepSpeed    = 1.6
ENT.SearchTime2   = 5               -- seconds of searching before it goes back to sleep
ENT.DeployDelay   = 0
ENT.ArmoredWhenClosed = true        -- x0.1 damage while closed
ENT.Tippable      = false
ENT.BurstFire     = nil             -- { charge = s, count = n, rate = shots/s, rest = s }: charge up, then fire a burst (Hunter-Chopper style)
ENT.GlowScale     = 1
ENT.Laser         = false           -- visible aim laser (citizen floor turret)
ENT.ScanBeams     = false           -- ground turret scanning beams
ENT.DeathDelay    = 1
ENT.ExplodeOnDeath = true
ENT.ExplosionDamage = 100
ENT.ExplosionRadius = 100
ENT.DeathKeep     = 6               -- seconds a non-exploding wreck stays

ENT.GibModels  = { "models/gibs/metal_gib1.mdl", "models/gibs/metal_gib2.mdl", "models/gibs/metal_gib3.mdl",
                   "models/gibs/metal_gib4.mdl", "models/gibs/metal_gib5.mdl" }
ENT.GibCount   = 4

-- sound script names (silent when the script does not exist)
ENT.Sounds = {
	Deploy = "NPC_CeilingTurret.Deploy", Retire = "NPC_CeilingTurret.Retire", Alert = "NPC_CeilingTurret.Alert",
	Ping = "NPC_CeilingTurret.Ping", Die = "NPC_CeilingTurret.Die", Shot = "NPC_FloorTurret.ShotSounds",
	Alarm = "NPC_FloorTurret.Alarm", Activate = "NPC_CeilingTurret.Activate",
}

ENT.IsTurret = true

local ST_DISABLED, ST_AUTO, ST_DEPLOY, ST_SEARCH, ST_ACTIVE, ST_RETIRE, ST_TIPPED, ST_DESTRUCT, ST_DYING = 0, 1, 2, 3, 4, 5, 6, 7, 8
ENT.ST = { DISABLED = 0, AUTO = 1, DEPLOY = 2, SEARCH = 3, ACTIVE = 4, RETIRE = 5, TIPPED = 6, DESTRUCT = 7, DYING = 8 }

-- eyes are green while hacked/friendly-looking (cyan when it sees something), like a citizen-modified turret
function ENT:GetNPCClass()
	local st = self.State
	if st == ST_DISABLED or st == ST_DYING or self.Crashing then return CLASS_NONE end
	if self.Hacked then return self.HackedNPCClass or CLASS_PLAYER_ALLY end
	return self.NPCClass
end

--=========================================================================
-- CLIENT
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
	local glow  = AddMat("pm_turret_glow_a", "sprites/light_glow03")
	local beamM = AddMat("pm_turret_beam_a", "sprites/laserbeam")
	local flashM = AddMat("pm_turret_flash_a", "sprites/muzzleflash1")

	function ENT:Draw() self:DrawModel() end

	local function Att(self, name)
		local id = self:LookupAttachment(name)
		if id and id > 0 then return self:GetAttachment(id) end
	end

	function ENT:DrawTranslucent()
		self:DrawModel()
		local st = self:GetNWInt("TurSt", 1)
		local t = CurTime()
		local ms = self:GetModelScale()
		local hacked = self.Hacked
		local since = t - self:GetNWFloat("TurStT", t)

		-- eye glow (colours follow Valve's turret states)
		local r, g, b, a, scale = 0, 255, 0, 120, 0.3
		if st == ST_ACTIVE then
			if hacked then r, g, b = 60, 200, 255 else r, g, b = 255, 30, 20 end
			a, scale = 255, 0.4
		elseif st == ST_DEPLOY or st == ST_SEARCH then
			r, g, b = 255, 140, 0
			a = (st == ST_SEARCH) and (math.sin(t * 6.28) > 0 and 200 or 40) or 160
			scale = 0.35
		elseif st == ST_TIPPED or st == ST_DESTRUCT then
			r, g, b = 255, 30, 20
			a = math.sin(t * 25) > 0 and 255 or 30
		elseif st == ST_DYING then
			r, g, b = 255, 30, 20
			a = 255 * math.Clamp(1 - since, 0, 1)
		elseif st == ST_DISABLED then
			a = 120 * math.Clamp(1 - since, 0.15, 1)
		elseif st == ST_RETIRE then
			a = 120 * math.Clamp(1 - since * 2, 0, 1)
		end
		local lt = Att(self, "light") or Att(self, "eyes")
		local eyes = Att(self, "eyes")
		if lt and a > 1 and not (st == ST_AUTO and self.TurretKind == "ceiling" and false) then
			render.SetMaterial(glow)
			local sz = 60 * scale * ms * (self.GlowScale or 1)
			local cd = self:GetNWFloat("TurChargeDur", 0)
			if cd > 0 then -- charging a burst: the light swells
				sz = sz * (1 + 1.4 * math.Clamp((t - self:GetNWFloat("TurChargeStart", 0)) / cd, 0, 1))
			end
			render.DrawSprite(lt.Pos, sz, sz, Color(r, g, b, a))
			render.DrawSprite(lt.Pos, sz * 0.4, sz * 0.4, Color(255, 255, 255, a * 0.7))
		end

		-- aim laser / scanning beams
		if eyes and (st == ST_ACTIVE or st == ST_SEARCH or st == ST_DEPLOY) then
			local fw = eyes.Ang:Forward()
			if self.Laser or self.ScanBeams then
				local tr = util.TraceLine({ start = eyes.Pos, endpos = eyes.Pos + fw * 1500, filter = { self, self:GetOwner(), self:GetParent() }, mask = MASK_SHOT })
				local col = self.Laser and (hacked and Color(80, 255, 140, 170) or Color(255, 40, 30, 170)) or Color(110, 160, 255, 150)
				if st == ST_ACTIVE and self.ScanBeams then col = Color(255, 60, 40, 190) end
				render.SetMaterial(beamM)
				render.DrawBeam(eyes.Pos, tr.HitPos, 1.2 * math.max(ms, 0.5), 0, 1, col)
				if self.ScanBeams then
					-- two edge beams of the scan cone
					local ang = eyes.Ang
					for _, off in ipairs({ -14, 14 }) do
						local d = (ang + Angle(0, off, 0)):Forward()
						local t2 = util.TraceLine({ start = eyes.Pos, endpos = eyes.Pos + d * 900, filter = { self }, mask = MASK_SHOT })
						render.DrawBeam(eyes.Pos, t2.HitPos, 0.8, 0, 1, Color(110, 160, 255, 90))
					end
				end
			end
		end

		-- muzzle flash
		if eyes and t - self:GetNWFloat("TurShot", 0) < 0.06 then
			render.SetMaterial(flashM)
			local sz = (30 + math.Rand(0, 12)) * ms
			render.DrawSprite(eyes.Pos + eyes.Ang:Forward() * 2 * ms, sz, sz, Color(255, 200, 120, 255))
			local d = DynamicLight(self:EntIndex())
			if d then
				d.pos = eyes.Pos + eyes.Ang:Forward() * 6
				d.r, d.g, d.b = 255, 180, 90
				d.brightness = 2
				d.size = 110 * math.max(ms, 0.4)
				d.decay = 2000
				d.dietime = t + 0.06
			end
		end
	end
end

if not SERVER then return end

--=========================================================================
-- SERVER
--=========================================================================
local function Base(name)
	return scripted_ents.GetStored("base_physics_snpc").t[name]
end

local function Approach(cur, goal, step)
	if cur < goal then return math.min(cur + step, goal) end
	return math.max(cur - step, goal)
end

-- The engine's NPC code turns the whole body toward whatever IT thinks the enemy is. Turrets only aim with their
-- pose parameters, so drop the engine's enemy and put the body back where it was.
function ENT:HoldFacing()
	local en = self:GetEnemy()
	if IsValid(en) then self:SetEnemy(NULL) self:ClearEnemyMemory() end
	if self.Mounted then
		-- bolted to something: keep the mounting angle / position the owner gave us (the engine tried to turn us upright)
		if self.MountLocalAng then
			local la = self:GetLocalAngles()
			if math.abs(math.AngleDifference(la.p, self.MountLocalAng.p)) > 0.5 or math.abs(math.AngleDifference(la.y, self.MountLocalAng.y)) > 0.5
				or math.abs(math.AngleDifference(la.r, self.MountLocalAng.r)) > 0.5 then
				self:SetLocalAngles(self.MountLocalAng)
			end
		end
		if self.MountLocalPos and self:GetLocalPos():DistToSqr(self.MountLocalPos) > 0.25 then self:SetLocalPos(self.MountLocalPos) end
		self:SetIdealYawAndUpdate(self:GetLocalAngles().y) -- (local: the engine turns the local yaw of a parented entity)
		return
	end
	local ang = self:GetAngles()
	self:SetIdealYawAndUpdate(ang.y) -- (the engine's yaw motor has nothing to turn toward)
	if self.Tippable then
		local phys = self:GetPhysicsObject()
		if self.Held or self.Tipped or self:GetUp().z < 0.9 or CurTime() < (self.AdoptUntil or 0) then
			self.RestYaw = ang.y
			-- knocked over and lying still: it stays exactly the way it landed (nothing turns it toward anyone)
			if self.Tipped and not self.Held and IsValid(phys) then
				if phys:GetVelocity():LengthSqr() < 25 and phys:GetAngleVelocity():LengthSqr() < 25 then
					self.TipAng = self.TipAng or Angle(ang)
					if math.abs(math.AngleDifference(ang.y, self.TipAng.y)) > 2 or math.abs(math.AngleDifference(ang.p, self.TipAng.p)) > 2
						or math.abs(math.AngleDifference(ang.r, self.TipAng.r)) > 2 then
						phys:SetAngles(self.TipAng)
					end
				else
					self.TipAng = nil
				end
			end
			return
		end
		self.TipAng = nil
		if not self.RestYaw then self.RestYaw = ang.y return end
		-- standing upright: the yaw is nailed down (no turning at all, whatever pushes or the engine try)
		if IsValid(phys) then
			local av = phys:GetAngleVelocity()
			local wav = phys:LocalToWorldVector(av)
			if math.abs(wav.z) > 0.6 then
				wav.z = 0
				phys:SetAngleVelocity(phys:WorldToLocalVector(wav))
			end
		end
		-- (only a clear drift is corrected, and only through the physics object, so it never shakes or fights a grab)
		if math.abs(math.AngleDifference(ang.y, self.RestYaw)) > 1.5 and IsValid(phys) then
			ang.y = self.RestYaw
			phys:SetAngles(ang)
		end
	else
		self.RestAng = self.RestAng or ang
		if math.abs(math.AngleDifference(ang.y, self.RestAng.y)) > 3 then
			self:SetAngles(self.RestAng)
			local phys = self:GetPhysicsObject()
			if IsValid(phys) then phys:SetAngles(self.RestAng) end
		end
	end
end

function ENT:OnGravGunDrop(ply)
	Base("OnGravGunDrop")(self, ply)
	self.AdoptUntil = CurTime() + 2
end
function ENT:OnGravGunPunt(ply)
	Base("OnGravGunPunt")(self, ply)
	self.AdoptUntil = CurTime() + 3
end

-- sequence lookup by (lower case) name fragments
function ENT:FindSeq(pats)
	self.SeqCache = self.SeqCache or {}
	local key = table.concat(pats, "|")
	local c = self.SeqCache[key]
	if c ~= nil then return c or nil end
	local best
	for _, name in pairs(self:GetSequenceList() or {}) do
		local ln = string.lower(name)
		for rank, p in ipairs(pats) do
			if ln == p or (rank > 1 and string.find(ln, p, 1, true)) then
				if not best or rank < best[1] then best = { rank, name } end
			end
		end
	end
	local id = best and self:LookupSequence(best[2])
	if id and id < 0 then id = nil end
	self.SeqCache[key] = id or false
	return id
end

-- Plays a sequence (and remembers it: the engine's NPC code likes to reset the sequence, so the think re-applies it).
-- Animation is driven entirely from here: the cycle is computed from the elapsed time every tick (so it is always the
-- right speed and deploy / retract end exactly when the animation does), and the real playback rate is sent to
-- clients so they interpolate it smoothly.
function ENT:SetSeq(pats, rate, once)
	local id = self:FindSeq(pats)
	if not id then return 0 end
	self.WantSeq = id
	self.SeqRate = rate or 1
	self.SeqOnce = once or false
	self.SeqStart = CurTime()
	self.AnimDone = false
	self:ResetSequence(id)
	self:SetCycle(0)
	self:SetPlaybackRate(self.SeqRate)
	return self:SequenceDuration(id) / math.max(self.SeqRate, 0.01)
end

function ENT:StepAnim(dt)
	local id = self.WantSeq
	if not id then return end
	if self:GetSequence() ~= id then self:SetSequence(id) end
	local dur = self:SequenceDuration(id)
	if dur <= 0 then return end
	local e = (CurTime() - self.SeqStart) * (self.SeqRate or 1) / dur
	if self.SeqOnce then
		if e >= 1 then self.AnimDone = true e = 1 end
		self:SetCycle(e)
	else
		self:SetCycle(e % 1)
	end
	self:SetPlaybackRate(self.SeqRate or 1)
end

local IDLE_CLOSED = { "idle", "idle1", "idle_closed" }
local IDLE_ALERT  = { "idle alert", "idle_alert", "idlealert", "alert", "idle" }

function ENT:PlaySnd(name)
	local s = self.Sounds[name]
	if s and s ~= "" and not self.Silent then self:EmitSound(s) end
end

function ENT:SetTurretState(st)
	-- the alert / alarm sound scripts loop: cut them off when the state that started them ends
	local old = self.State
	if old == ST_ACTIVE and st ~= ST_ACTIVE and self.Sounds.Alert then self:StopSound(self.Sounds.Alert) end
	if (old == ST_TIPPED or old == ST_DESTRUCT) and st ~= ST_TIPPED and st ~= ST_DESTRUCT and self.Sounds.Alarm then
		self:StopSound(self.Sounds.Alarm)
	end
	self.State = st
	-- shut down (knocked over / disabled): none of the engine's AI runs
	if st == ST_DISABLED then
		self:SetEnemy(NULL)
		if SCHED_NPC_FREEZE then pcall(self.SetSchedule, self, SCHED_NPC_FREEZE) end
	elseif st == ST_TIPPED then
		self:SetEnemy(NULL)
	elseif old == ST_TIPPED or old == ST_DISABLED then
		pcall(self.ClearSchedule, self)
	end
	if st ~= ST_ACTIVE and self.BurstPhase then
		self.BurstPhase = nil
		self:SetNWFloat("TurChargeDur", 0)
	end
	self.StateTime = CurTime()
	self:SetNWInt("TurSt", st)
	self:SetNWFloat("TurStT", CurTime())
	self:SyncNPCClass()
end

--=========================================================================
-- Physics: ceiling / ground are frozen in place, mounted ones have none at all, the floor turret is a free prop
--=========================================================================
function ENT:InitPhysicsFlight()
	Base("InitPhysicsFlight")(self)
	local phys = self:GetPhysicsObject()
	if self.Mounted then
		self:PhysicsDestroy()
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_NONE)
		return
	end
	if IsValid(phys) then
		if self.Tippable then
			phys:EnableGravity(true)
			phys:SetDamping(0.2, 1)
			phys:Wake()
		else
			phys:EnableMotion(false)
		end
	end
end

function ENT:UpdateMovement(dt) end

--=========================================================================
-- Setup
--=========================================================================
function ENT:OnSpawned()
	self:AddEFlags(EFL_NO_DISSOLVE)
	self:CapabilitiesClear()
	if self.Tippable or self.StaticProp then self:SetMaxYawSpeed(0) end -- the engine never turns a floor turret
	self.PoseYaw, self.PosePitch = nil, nil
	for i = 0, (self:GetNumPoseParameters() or 0) - 1 do
		local n = self:GetPoseParameterName(i)
		local ln = n and string.lower(n) or ""
		if not self.PoseYaw and string.find(ln, "yaw", 1, true) then self.PoseYaw = n end
		if not self.PosePitch and string.find(ln, "pitch", 1, true) then self.PosePitch = n end
	end
	if not self:PlaceTurret() then self:Remove() return end
	self.RestAng = self:GetAngles()
	self.RestYaw = self:GetAngles().y
	self.CurYaw, self.CurPitch = 0, 0
	self.SignY, self.SignP = self.AimSignY or 1, self.AimSignP or 1
		self.NextShot = 0
	self.NextPing = 0
	self.Tipped = false
	self.SearchStart = 0
	self.DamageScale = self.DamageScale or 1
	if self.Hacked and self.TurretKind == "floor" then self:SetSkin(1) end
	if self.TurretColor then self:SetColor(self.TurretColor) end

	if self.Mounted then
		self.SightFOV = 360
		self.ArmoredWhenClosed = false
		self.AimSpeed = math.max(self.AimSpeed, 400) -- the mount moves: track fast
		self.AimDot = math.min(self.AimDot, 0.9)
		self.RetargetDelay = 0.1
	end

	self:NextThink(CurTime())
	if self.Mounted then
		self:StartOpen()
	else
		self:CloseNow()
	end
end

-- Ceiling turrets only live on ceilings (moved up to the ceiling above, removed when there is none);
-- the others are lifted so they never sit inside the floor.
function ENT:PlaceTurret()
	if self.Mounted then return true end
	local pos = self:GetPos()
	local function wtrace(a, b)
		return util.TraceLine({ start = a, endpos = b, mask = MASK_SOLID_BRUSHONLY })
	end
	if self.TurretKind == "ceiling" then
		local tr = wtrace(pos + Vector(0, 0, 2), pos + Vector(0, 0, 4096))
		if tr.StartSolid then tr = wtrace(pos + Vector(0, 0, -30), pos + Vector(0, 0, 4096)) end
		if not tr.Hit then return false end
		local off = self:OBBMaxs().z
		self:SetPos(Vector(pos.x, pos.y, tr.HitPos.z - math.max(off, 0) + 0.5))
		self:SetAngles(Angle(0, self:GetAngles().y, 0))
	else
		local tr = wtrace(pos + Vector(0, 0, 24), pos - Vector(0, 0, 64))
		local mins = self:OBBMins().z
		if tr.Hit and not tr.StartSolid then
			self:SetPos(Vector(pos.x, pos.y, tr.HitPos.z - mins + 1))
		else
			self:SetPos(pos + Vector(0, 0, math.max(-mins, 0) + 1))
		end
		self:SetAngles(Angle(0, self:GetAngles().y, 0))
	end
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then phys:SetPos(self:GetPos()) phys:SetAngles(self:GetAngles()) end
	return true
end

function ENT:GetSightOrigin()
	local p = self:GetMuzzle()
	return p
end

-- closed: the plain "idle" animation
function ENT:CloseNow()
	self:SetTurretState(ST_AUTO)
	self:SetSeq(IDLE_CLOSED, 1)
end

-- open: the "idle alert" animation
function ENT:OpenFrozen()
	self:SetSeq(IDLE_ALERT, 1)
end

function ENT:StartOpen()
	self:OpenFrozen()
	self:SetTurretState(ST_SEARCH)
	self.SearchStart = CurTime()
end

--=========================================================================
-- Targeting
--=========================================================================
function ENT:IsValidTarget(ent)
	if IsValid(self.MountOwner) then
		if ent == self.MountOwner or ent == self.MountOwner:GetParent() then return false end
	end
	return Base("IsValidTarget")(self, ent)
end

function ENT:IsFriendlyTo(ent)
	if IsValid(self.MountOwner) and ent == self.MountOwner then return true end
	return Base("IsFriendlyTo")(self, ent)
end

function ENT:UpdateTargeting(dt)
	local st = self.State
	if self.Held or self.Tipped then return end
	if st == ST_AUTO or st == ST_SEARCH or st == ST_ACTIVE then
		local foe = self:GetFoe()
		if IsValid(foe) and not self.Mounted and self.SightFOV < 360 then
			-- a target that leaves the field of view is let go (the barrel never swings round to follow it)
			local to = foe:WorldSpaceCenter() - self:GetSightOrigin()
			local half = math.rad(self.SightFOV * 0.5 + 8)
			if to:GetNormalized():Dot(self:GetForward()) < math.cos(half) then self:LoseFoe() end
		end
		Base("UpdateTargeting")(self, dt)
	end
end

function ENT:OnTargetAcquired(ent)
	local st = self.State
	if st == ST_AUTO then
		self:Deploy()
	elseif st == ST_SEARCH then
		self:PlaySnd("Alert")
		self:SetTurretState(ST_ACTIVE)
	end
end

function ENT:Deploy()
	if self.State ~= ST_AUTO and self.State ~= ST_RETIRE then return end
	self:PlaySnd("Deploy")
	self:SetTurretState(ST_DEPLOY)
	local d = self:SetSeq({ "deploy", "open" }, 1, true)
	self.DeployEnd = CurTime() + d + 0.3
end

function ENT:Retire()
	local st = self.State
	if st == ST_DYING or st == ST_DESTRUCT or st == ST_AUTO or st == ST_DISABLED then return end
	self:LoseFoe()
	self:PlaySnd("Retire")
	self:SetTurretState(ST_RETIRE)
	local d = self:SetSeq({ "retract", "close" }, 1, true)
	self.RetireEnd = CurTime() + d + 0.3
end

--=========================================================================
-- Aiming (pose parameters, closed loop on the "eyes" attachment)
--=========================================================================
function ENT:GetMuzzle()
	local id = self.AttEyes
	if id == nil then
		local a = self:LookupAttachment("eyes")
		self.AttEyes = (a and a > 0) and a or false
		id = self.AttEyes
	end
	if id then
		local att = self:GetAttachment(id)
		if att then return att.Pos, att.Ang:Forward(), att.Ang end
	end
	return self:WorldSpaceCenter(), self:GetForward(), self:GetAngles()
end

-- Open-loop aiming (no feedback from the animation, so no oscillation): the pose parameters are set straight from the
-- wanted angle in the turret's own space. Only the SIGN of each pose axis is learned, by watching which way the
-- "eyes" attachment moves when the pose changes.
local function Learn(self, key, la, pose)
	local last = self["L_" .. key]
	self["L_" .. key] = { la, pose }
	if not last then return end
	local da = math.AngleDifference(la, last[1])
	local dp = pose - last[2]
	if math.abs(dp) > 0.4 and math.abs(da) > 0.05 then
		self["C_" .. key] = math.Clamp((self["C_" .. key] or 0) * 0.95 + da * dp, -1e5, 1e5)
	end
end

function ENT:AimTowards(goalDir, dt)
	local mpos, mfwd, mang = self:GetMuzzle()
	if not self.PoseYaw and not self.PosePitch then return mfwd:Dot(goalDir) end

	local la = self:WorldToLocalAngles(mang)
	-- (yaw is NOT measured: with the barrel pointing straight up/down the Euler yaw of the attachment is arbitrary and flipped by 180 now and then)
	if not self.RestMuz then self.RestMuz = Angle(la.p, 0, 0) end
	local ld = self:WorldToLocalAngles(goalDir:Angle())
	local step = self.AimSpeed * dt

	if self.AttEyes and self.AimLearn ~= false then
		Learn(self, "y", la.y, self.CurYaw)
		Learn(self, "p", la.p, self.CurPitch)
		if math.abs(self.C_y or 0) > 60 then self.SignY = (self.C_y > 0) and 1 or -1 end
		if math.abs(self.C_p or 0) > 60 then self.SignP = (self.C_p > 0) and 1 or -1 end
	end

	if self.PoseYaw then
		local goal = self.SignY * math.AngleDifference(ld.y, self.RestMuz.y)
		local lim = math.min(self.SightFOV * 0.5 + 8, 180)
		goal = math.Clamp(goal, -lim, lim)
		local ok, mn, mx = pcall(function() return self:GetPoseParameterRange(self:LookupPoseParameter(self.PoseYaw)) end)
		if ok and mn then goal = math.Clamp(goal, mn, mx) end
		self.CurYaw = Approach(self.CurYaw, goal, step)
		self:SetPoseParameter(self.PoseYaw, self.CurYaw)
	end
	if self.PosePitch then
		local goal = self.SignP * math.AngleDifference(ld.p, self.RestMuz.p)
		local ok, mn, mx = pcall(function() return self:GetPoseParameterRange(self:LookupPoseParameter(self.PosePitch)) end)
		if ok and mn then goal = math.Clamp(goal, mn, mx) end
		self.CurPitch = Approach(self.CurPitch, goal, step)
		self:SetPoseParameter(self.PosePitch, self.CurPitch)
	end
	return mfwd:Dot(goalDir)
end

-- back to the rest position (closed)
function ENT:ResetAim(dt)
	local step = self.AimSpeed * dt
	self.CurYaw = Approach(self.CurYaw, 0, step)
	self.CurPitch = Approach(self.CurPitch, 0, step)
	if self.PoseYaw then self:SetPoseParameter(self.PoseYaw, self.CurYaw) end
	if self.PosePitch then self:SetPoseParameter(self.PosePitch, self.CurPitch) end
end

function ENT:GetBulletDamage()
	if self.BulletDamage then return self.BulletDamage * self.DamageScale end
	local cv = GetConVar(self.DamageConVar)
	return (cv and cv:GetFloat() or self.DamageDefault) * self.DamageScale
end

function ENT:Shoot(cone, aimDir)
	local pos, fwd = self:GetMuzzle()
	local s = math.sin(math.rad((cone or self.ConeDeg) * 0.5))
	self:FireBullets({
		Attacker = self, Inflictor = self, Damage = self:GetBulletDamage(), Force = 1, Num = 1,
		Src = pos, Dir = aimDir or fwd, -- (shots go at the target: the barrel only has to be roughly on it)
		 Spread = Vector(s, s, 0), Tracer = 1, TracerName = self.TracerName,
		AmmoType = self.AmmoType, IgnoreEntity = IsValid(self.MountOwner) and self.MountOwner or nil,
	})
	self:SetNWFloat("TurShot", CurTime())
	if not self.Silent then self:EmitSound(self.Sounds.Shot, 75, math.random(95, 105)) end
end

--=========================================================================
-- Main think
--=========================================================================
function ENT:AimPointOf(foe)
	if self.FoeVisible then
		if self.AimHigh then
			-- a sniper goes for the head: the eyes of a player / NPC, otherwise high on the body
			if foe.EyePos and (foe:IsPlayer() or foe:IsNPC()) then return foe:EyePos() end
			local mx = foe:OBBMaxs().z
			return foe:GetPos() + Vector(0, 0, mx * 0.85)
		end
		return foe:WorldSpaceCenter()
	end
	return self.EnemyLKP
end

-- charge up (light swells), then a burst of bullets, then a short rest
function ENT:BurstThink(now, dot, dir)
	local b = self.BurstFire
	local ph = self.BurstPhase
	if not ph then
		if dot >= self.AimDot and now >= (self.BurstRestUntil or 0) and not self.Held and self.FoeVisible and self:GetUp().z > 0.9 then
			self.BurstPhase, self.BurstStart = "charge", now
			self:SetNWFloat("TurChargeStart", now)
			self:SetNWFloat("TurChargeDur", b.charge)
			self:EmitSound("NPC_AttackHelicopter.ChargeGun", 80, 230) -- the Hunter-Chopper's gun spin-up, sped up
		end
	elseif ph == "charge" then
		if now - self.BurstStart >= b.charge then
			self.BurstPhase, self.BurstLeft, self.NextShot = "fire", b.count, now
			self:SetNWFloat("TurChargeDur", 0)
		end
	elseif ph == "fire" then
		if now >= self.NextShot then
			self.NextShot = now + 1 / b.rate
			self.BurstLeft = self.BurstLeft - 1
			self:Shoot(nil, dir)
			if self.BurstLeft <= 0 then
				self.BurstPhase = nil
				self.BurstRestUntil = now + b.rest
			end
		end
	end
end

function ENT:OnThinkAlive(dt)
	local now = CurTime()
	local st = self.State
	self:StepAnim(dt)
	self:HoldFacing()

	-- tipped over (floor turret)
	if self.Tippable and not self.Mounted and not self.Held and st ~= ST_DYING and st ~= ST_DESTRUCT then
		local uz = self:GetUp().z
		local tipped = uz < 0.75 or (self.Tipped and uz < 0.92)
		if tipped and not self.Tipped then
			self.Tipped = true
			self:LoseFoe()
			self.TipFrozen = false
			self.ThrashEnd = now + math.Rand(2, 2.5)   -- it thrashes around, firing wildly, then shuts down
			self.NextShot = now
			self:SetTurretState(ST_TIPPED)
			self.BlastHits = 0
			self:PlaySnd("Alarm")
		elseif not tipped and self.Tipped then
			-- stood back up: reactivates
			self.Tipped = false
			self.BlastHits = 0
			if st == ST_TIPPED then self:PlaySnd("Activate") self:CloseNow() end
		end
		st = self.State
	end

	if st == ST_AUTO or st == ST_DISABLED then
		self:ResetAim(dt)

	elseif st == ST_DEPLOY then
		self:ResetAim(dt)
		if self.AnimDone or now >= self.DeployEnd then
			self:OpenFrozen()
			self:SetTurretState(self:HasEnemy() and ST_ACTIVE or ST_SEARCH)
			self.SearchStart = now
			self:PlaySnd("Activate")
		end

	elseif st == ST_SEARCH then
		-- sweep left/right (and a little up/down), ping once a second
		local yaw = math.sin(now * self.SweepSpeed) * self.SweepYaw
		local goal = self:LocalToWorldAngles(Angle(self.SweepPitch * 0.5 * math.sin(now * self.SweepSpeed * 0.5), yaw, 0)):Forward()
		self:AimTowards(goal, dt)
		if now >= self.NextPing then
			self.NextPing = now + 1
			self:PlaySnd("Ping")
		end
		if not self.Mounted and now - self.SearchStart > self.SearchTime2 then self:Retire() end

	elseif st == ST_ACTIVE then
		local foe = self:GetFoe()
		if not IsValid(foe) then
			self:SetTurretState(ST_SEARCH)
			self.SearchStart = now
			return
		end
		-- keeps shooting for a moment after a brief loss of sight (a moving mount loses line of sight all the time)
		local vis = self.FoeVisible or (now - (self.LastEnemySeen or 0) < 0.6)
		local p = self.FoeVisible and self:AimPointOf(foe) or (vis and self.EnemyLKP) or nil -- longer out of sight: hold still
		if p then
			local mpos = self:GetMuzzle()
			local dir = (p - mpos):GetNormalized()
			local dot = self:AimTowards(dir, dt)
			self.SearchStart = now
			if self.BurstFire then
				self:BurstThink(now, dot, dir)
			elseif dot >= self.AimDot and now >= self.NextShot and not self.Held and self:GetUp().z > 0.9 then
				self.NextShot = now + 1 / self.FireRate
				self:Shoot(nil, dir)
			end
		end

	elseif st == ST_RETIRE then
		self:ResetAim(dt)
		if self.AnimDone or now >= self.RetireEnd then
			self:CloseNow()
		end

	elseif st == ST_TIPPED then
		if now < (self.ThrashEnd or 0) then
			-- thrashing: the barrel whips about at random and fires every 0.05 s
			local function pick(pose, lim)
				local g = math.Rand(-lim, lim)
				local ok, mn, mx = pcall(function() return self:GetPoseParameterRange(self:LookupPoseParameter(pose)) end)
				if ok and mn then g = math.Clamp(g, mn, mx) end
				return g
			end
			if now >= (self.NextWhip or 0) then
				self.NextWhip = now + 0.12
				self.WhipYaw = self.PoseYaw and pick(self.PoseYaw, 60) or 0
				self.WhipPitch = self.PosePitch and pick(self.PosePitch, 40) or 0
			end
			local step = 700 * dt
			if self.PoseYaw then self.CurYaw = Approach(self.CurYaw, self.WhipYaw or 0, step) self:SetPoseParameter(self.PoseYaw, self.CurYaw) end
			if self.PosePitch then self.CurPitch = Approach(self.CurPitch, self.WhipPitch or 0, step) self:SetPoseParameter(self.PosePitch, self.CurPitch) end
			self:OpenFrozen()
			if now >= self.NextShot then
				self.NextShot = now + 0.05
				self:Shoot(20)
			end
		else
			-- done thrashing: deactivated (dead weight with an occasional spark) until stood back up, no AI at all
			if not self.TipFrozen then
				self.TipFrozen = true
				self:PlaySnd("Die")
				if self.Sounds.Alarm then self:StopSound(self.Sounds.Alarm) end
				self:SetSeq(IDLE_CLOSED, 1)
				if SCHED_NPC_FREEZE then pcall(self.SetSchedule, self, SCHED_NPC_FREEZE) end
			end
			self:ResetAim(dt)
			if math.random() < 0.02 then
				local ed = EffectData()
				ed:SetOrigin(self:WorldSpaceCenter() + VectorRand() * 6)
				ed:SetMagnitude(1) ed:SetScale(1) ed:SetRadius(1)
				util.Effect("ElectricSpark", ed)
			end
		end

	elseif st == ST_DESTRUCT then
		self:DestructThink(now)
	end
end

--=========================================================================
-- Self destruct (floor turret): beeps faster and higher, then a small blast
--=========================================================================
function ENT:SelfDestruct()
	if self.State == ST_DYING or self.State == ST_DESTRUCT then return end
	self:LoseFoe()
	self:SetTurretState(ST_DESTRUCT)
	self.DestructStart = CurTime()
	self.NextBeep = 0
end

function ENT:DestructThink(now)
	local f = math.Clamp((now - self.DestructStart) / 4, 0, 1)
	if now >= self.NextBeep then
		self.NextBeep = now + Lerp(f, 0.75, 0.1)
		self:EmitSound("buttons/blip1.wav", 75, math.floor(Lerp(f, 100, 225)))
	end
	if f >= 1 then
		self.Crashing = true
		self:SetTurretState(ST_DYING)
		self:Explode(15, 120)
		self:Remove()
	end
end

function ENT:Explode(damage, radius)
	local pos = self:WorldSpaceCenter()
	local ed = EffectData()
	ed:SetOrigin(pos) ed:SetScale(1) ed:SetMagnitude(1)
	util.Effect("Explosion", ed)
	util.BlastDamage(self, self, pos, radius, damage)
	if self.GibModels and #self.GibModels > 0 then self:SpawnGibs(pos, Vector(0, 0, 0)) end
	self.Gibbed = true
end

--=========================================================================
-- Damage / death
--=========================================================================
function ENT:ModifyDamage(dmg)
	local st = self.State
	if self.Tipped and not self.Held and dmg:IsDamageType(DMG_BLAST) then
		-- already knocked over and shut down: one or two explosions finish it off
		local now = CurTime()
		if now - (self.LastBlast or 0) > 6 then self.BlastHits = 0 end
		self.LastBlast = now
		self.BlastHits = (self.BlastHits or 0) + 1
		if self.BlastHits >= 2 or dmg:GetDamage() >= 40 then
			self.Crashing = true
			self:Explode(15, 120)
			self:Remove()
			return
		end
	end
	if self.Tippable and not self.Tipped and not self.Held and dmg:IsDamageType(DMG_BLAST) then
		-- a standing turret is a prop: a blast shoves it (usually over) instead of destroying it
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then
			local from = dmg:GetDamagePosition()
			if not from or from == vector_origin then from = dmg:GetInflictor():IsValid() and dmg:GetInflictor():GetPos() or self:GetPos() end
			local dir = self:WorldSpaceCenter() - from
			local d = dir:Length()
			local radius = 170
			if d < radius then
				dir.z = math.max(dir.z, 0) + 10
				dir:Normalize()
				local m = phys:GetMass()
				phys:Wake()
				phys:ApplyForceOffset(dir * m * 190 * (1 - 0.6 * d / radius), self:GetPos() + self:GetUp() * 25)
			end
		end
		dmg:SetDamage(0)
		return
	end
	if self.ArmoredWhenClosed and (st == ST_DISABLED or st == ST_AUTO or st == ST_RETIRE) then
		dmg:ScaleDamage(0.1)
	end
end

function ENT:OnDamaged(dmg)
	-- shot while sleeping: wake up and look at whoever did it
	local atk = dmg:GetAttacker()
	if IsValid(atk) and self:IsValidTarget(atk) then
		if self.State == ST_AUTO then
			self:AcquireTarget(atk)
		elseif not self:HasEnemy() and (self.State == ST_SEARCH) then
			self:AcquireTarget(atk)
		end
	end
	if self.State ~= ST_DISABLED then
		local ed = EffectData()
		local p = dmg:GetDamagePosition()
		ed:SetOrigin(p ~= vector_origin and p or self:WorldSpaceCenter())
		ed:SetMagnitude(1) ed:SetScale(1) ed:SetRadius(1)
		util.Effect("ElectricSpark", ed)
	end
end

function ENT:StartDying(dmg)
	if self.Crashing then return end
	self.Crashing = true
	self.CrashStart = CurTime()
	self:LoseFoe()
	self:AddFlags(FL_NOTARGET)
	self:SetTurretState(ST_DYING)
	if self.Sounds.Alert then self:StopSound(self.Sounds.Alert) end
	self:PlaySnd("Die")
	hook.Run("OnNPCKilled", self, dmg:GetAttacker(), dmg:GetInflictor())
	self.DieEnd = CurTime() + self.DeathDelay
	self.NextSpark = 0
	self:OnStartDying(dmg)
end

-- the base's crash flight does not apply: a turret just sparks for a moment, then goes bang (or smoulders)
function ENT:CrashThink(dt) end

function ENT:OnThinkDying(dt)
	if self.Gibbed then return end
	local now = CurTime()
	if now >= self.NextSpark then
		self.NextSpark = now + 0.12
		local ed = EffectData()
		ed:SetOrigin(self:WorldSpaceCenter() + VectorRand() * 6)
		ed:SetMagnitude(2) ed:SetScale(1) ed:SetRadius(2)
		util.Effect("ElectricSpark", ed)
	end
	if now >= self.DieEnd then
		if self.ExplodeOnDeath then
			self:Explode(self.Mounted and 0 or self.ExplosionDamage * 0.1, self.ExplosionRadius)
			self:Remove()
		else
			-- ground turret: stays as a smoking wreck for a while
			self.Gibbed = true
			self:CreateSmokeTrailForce()
			SafeRemoveEntityDelayed(self, self.DeathKeep)
		end
	end
end

function ENT:CreateSmokeTrailForce()
	local keep = self.DeathSmoke
	self.DeathSmoke = true
	self:CreateSmokeTrail()
	self.DeathSmoke = keep
end

--=========================================================================
-- Inputs
--=========================================================================
function ENT:Enable()
	if self.State ~= ST_DISABLED then return end
	self:PlaySnd("Activate")
	self:SetTurretState(ST_AUTO)
	self:Deploy()
end

function ENT:Disable()
	local st = self.State
	if st == ST_DYING or st == ST_DESTRUCT or st == ST_DISABLED then return end
	self:LoseFoe()
	self:SetTurretState(ST_DISABLED)
	self:SetSeq(IDLE_CLOSED, 1)
end

function ENT:Toggle()
	if self.State == ST_DISABLED then self:Enable() else self:Disable() end
end

function ENT:AcceptInput(name, activator, caller, data)
	name = string.lower(name)
	if name == "enable" then self:Enable()
	elseif name == "disable" then self:Disable()
	elseif name == "toggle" then self:Toggle()
	elseif name == "selfdestruct" then self:SelfDestruct()
	elseif name == "deploy" then self:Deploy()
	elseif name == "retire" then self:Retire()
	else return false end
	return true
end

function ENT:OnRemoved()
	if self.Sounds.Alarm then self:StopSound(self.Sounds.Alarm) end
	if self.Sounds.Alert then self:StopSound(self.Sounds.Alert) end
end

function ENT:OnGravGunPickup(ply)
	self.TipAng = nil
	Base("OnGravGunPickup")(self, ply)
end

-- like the original's preferred carry angles: lying down (or turned away) it is carried upright, facing the way the player
-- looks. (Asked by the engine when the hold starts, so nothing is moved while the gun merely points at it.)
function ENT:PreferredCarryAngles(ply)
	if self.Tippable and self:GetUp().z < 0.9 then return Angle(0, 0, 0) end
end

-- +use picks it up with the player's hands. (The engine's own hand pickup refuses scripted NPCs, so this carries it by hand:
-- a velocity-driven hold in front of the player, upright. +use again drops it, attack throws it.)
local Carried = {}
local PendingThrow = {}

local function StopCarry(ply, throw)
	local e = Carried[ply]
	Carried[ply] = nil
	PendingThrow[ply] = nil
	if IsValid(ply) then
		ply:DrawViewModel(true)
		local w = ply.PhysSNPCCarryWep
		ply.PhysSNPCCarryWep = nil
		if IsValid(w) and ply:Alive() then ply:SelectWeapon(w:GetClass()) end
	end
	if not IsValid(e) then return end
	e.HandCarried = nil
	local ph = e:GetPhysicsObject()
	if IsValid(ph) then
		ph:EnableGravity(true)
		ph:Wake()
		if throw and IsValid(ply) then ph:SetVelocity(ply:GetAimVector() * 700 + ply:GetVelocity()) end
	end
	e:OnGravGunDrop(ply)
end

hook.Add("KeyPress", "PhysSNPC_TurretUse", function(ply, key)
	if not ply:Alive() then return end
	if Carried[ply] then
		if key == IN_USE then StopCarry(ply) end
		return
	end
	if key ~= IN_USE then return end
	local tr = util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 90, filter = ply })
	local e = tr.Entity
	if IsValid(e) and e.IsPhysicsSNPC and e.Tippable and not e.Mounted and not e.Held and e.State ~= ST_DYING and e.State ~= ST_DESTRUCT then
		local ph = e:GetPhysicsObject()
		if not IsValid(ph) then return end
		Carried[ply] = e
		e.HandCarried = ply
		e.TipAng = nil
		e:OnGravGunPickup(ply)
		ph:EnableGravity(false)
		ph:Wake()
		-- both hands are full: the weapon is lowered and cannot be used until it is put down
		local w = ply:GetActiveWeapon()
		if IsValid(w) then
			ply.PhysSNPCCarryWep = w
			ply:SetActiveWeapon(NULL)
		end
		ply:DrawViewModel(false)
	end
end)

-- no shooting / switching while carrying (attack throws it instead)
hook.Add("StartCommand", "PhysSNPC_TurretCarryCmd", function(ply, cmd)
	if not Carried[ply] then return end
	local atk = bit.bor(IN_ATTACK, IN_ATTACK2)
	if cmd:KeyDown(atk) then PendingThrow[ply] = true end
	cmd:RemoveKey(atk)
end)
hook.Add("PlayerSwitchWeapon", "PhysSNPC_TurretCarrySwitch", function(ply)
	if Carried[ply] then return true end
end)

hook.Add("Think", "PhysSNPC_TurretCarry", function()
	local dt = FrameTime()
	for ply, e in pairs(Carried) do
		if not IsValid(ply) or not IsValid(e) or not ply:Alive() or ply:InVehicle() or e.State == ST_DYING or e.State == ST_DESTRUCT
			or ply:EyePos():DistToSqr(e:GetPos()) > 220 * 220 then
			StopCarry(ply)
		elseif PendingThrow[ply] then
			StopCarry(ply, true)
		else
			local ph = e:GetPhysicsObject()
			if IsValid(ph) then
				local goal = ply:EyePos() + ply:GetAimVector() * 75 - Vector(0, 0, 18)
				local v = (goal - e:WorldSpaceCenter()) * 15
				if v:Length() > 1200 then v = v:GetNormalized() * 1200 end
				ph:SetVelocity(v)
				ph:SetAngleVelocity(Vector(0, 0, 0))
				-- turns upright gradually instead of snapping
				ph:SetAngles(LerpAngle(math.min(1, 4 * dt), e:GetAngles(), Angle(0, ply:EyeAngles().y, 0)))
				ph:Wake()
			end
		end
	end
end)
