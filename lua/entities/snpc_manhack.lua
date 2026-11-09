--[[-------------------------------------------------------------------------
	snpc_manhack  -  Half-Life 2 Manhack recreated as a physics SNPC
	(single file, built on base_physics_snpc)

	MAKING A VARIANT
	Create lua/entities/snpc_manhack_whatever.lua:

		AddCSLuaFile()
		ENT.Base      = "snpc_manhack"
		ENT.PrintName = "Whatever Manhack"
		ENT.SpawnHealth = 80
		ENT.BladeDamage = 40
		ENT.EyeColor    = Color(255, 160, 0)
		ENT.EyeColors   = { Light = Color(0, 120, 255) } -- optional: per-eye colours
		list.Set("NPC", "snpc_manhack_whatever", {
			Name = ENT.PrintName, Class = "snpc_manhack_whatever",
			Category = ENT.Category, Offset = 48,
			-- SubCategory is filled in automatically: "Hacked" if ENT.Hacked = true, else "Normal",
			-- or whatever you put in ENT.SubCategory
		})

	Every number below is a plain ENT field, so a variant only lists what it
	changes. For behaviour changes, override one of the small methods in the
	"VARIANT HOOKS" section (they never need to call a parent function).
	See snpc_manhack_hacked.lua and snpc_manhack_example.lua for examples.

	Values taken from Valve's npc_manhack.cpp / .h: health 25, blade damage 20/s,
	max speed 500, thrown speed 800, burst 1s with 2s cooldown, charge range 200,
	engine pitch ranges, 2x engine power when hacked, etc.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Base      = "base_physics_snpc"
ENT.Type      = "ai"
ENT.PrintName = "Manhack"
ENT.Author    = ""
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false -- NPCs are spawned from the NPC tab (the list.Set below)

--=========================================================================
-- CONFIG (override any of these in a variant)
--=========================================================================

-- body
ENT.Model        = "models/manhack.mdl"
ENT.SpawnHealth  = 25
ENT.HullSize     = 12
ENT.NPCClass     = CLASS_MANHACK

-- flight
ENT.MaxSpeed         = 500
ENT.PuntedMaxSpeed   = 800   -- speed cap while thrown by a gravity gun
ENT.BurstAccel       = 400   -- accel while charging
ENT.EnginePower      = 1
ENT.HackedEnginePower = 2    -- "Manhacks that have been hacked by Alyx get more engine power"

-- blades
ENT.BladeDamage            = 20   -- per second of contact (applied per SliceInterval hit)
ENT.PlayerDamageScale      = 2
ENT.CombineSoldierScale    = 6    -- extra vs npc_combine_s
ENT.HeldBladeDamage        = 100  -- per second while held by a gravity gun
ENT.ThrownNPCDamage        = 500  -- a thrown manhack kills almost any NPC it hits
ENT.SliceInterval          = 1     -- seconds between blade hits (per-hit damage = BladeDamage * this)
ENT.HeldSliceInterval      = 0.1   -- while held / thrown it chews continuously instead
ENT.RetreatTime            = 0.9   -- after a hit it flies away for this long before coming back
ENT.RetreatDistance        = 180

-- behaviour
ENT.PanelOpenDist   = 130   -- hull panels open when an enemy is this close (or while charging)
ENT.ChargeMinDist  = 200   -- starts a charge when this close (2D)
ENT.BurstTime      = 1     -- committed charge duration
ENT.BurstCooldown  = 2     -- wait between charges (they swarm in the meantime)
ENT.AttackSlots    = 2     -- how many manhacks attack one enemy at once
ENT.SwarmEnabled   = true
ENT.MinAttackDist  = 24    -- closer than this -> back away
ENT.StartPacked    = false -- spawn folded up (falls, deploys when it sees an enemy / is hurt)
ENT.NoDangerSounds = false
ENT.BurstMaxSpeed  = nil   -- speed cap while charging (nil = MaxSpeed)
ENT.FarMaxSpeed    = nil   -- speed cap while the enemy is further than FarSpeedDist (nil = MaxSpeed)
ENT.FarSpeedDist   = 1000
ENT.LungeSpeed     = 0     -- extra velocity kick (toward the enemy) when a charge starts
ENT.BulletDamageScale = 1  -- <1 = armour: scales DMG_BULLET damage
ENT.SearchSound    = ""    -- played every SearchInterval while there is no enemy
ENT.SearchInterval = 1.75
ENT.RotorWash      = false
ENT.ModelColor     = nil   -- Color(...) tint for a darker / different looking model
ENT.DamageTakenScale = 1   -- scales ALL incoming damage (0.5 = takes half)
ENT.KnockbackResistBullets = false -- bullets do not push it around
ENT.PropSliceDamage     = nil -- fixed blade damage vs props (nil = breaks them outright)
ENT.HeldPropSliceDamage = nil -- same while held by a gravity gun
ENT.CutZombies     = false -- a hit that could not kill a zombie cuts it in half anyway when it is low enough
ENT.RegenAmount    = 0     -- health regained per RegenDelay
ENT.RegenDelay     = 1
ENT.RegenOutOfCombat = true -- only regenerate with no enemy and not recently hurt
ENT.CombatEnginePower = nil -- engine power multiplier while it has an enemy
ENT.AlertNoise     = ""    -- played when it picks a target
ENT.LoseNoise      = ""    -- played when it loses its target
ENT.AlertPitch     = 100
ENT.AlertCooldown  = 3
ENT.HitSound       = ""    -- played when it takes any damage (throttled)
ENT.BatSound       = "NPC_Manhack.Bat" -- played when it is clubbed
ENT.HitPitch       = 100
ENT.GrabSound      = ""    -- gravity gun pickup / drop
ENT.DropSound      = ""
ENT.GrabLoopSound  = ""
ENT.BladeVolume    = nil   -- volume of the blade loop (nil = EngineVolume) -- dust/air disturbance while flying fast (env_rotorwash_emitter)
ENT.ForgetTime     = 10    -- seconds without seeing the enemy before it loses interest

-- hacked / ally state (see snpc_manhack_hacked.lua)
ENT.Hacked         = false

-- eyes
ENT.GlowSprite     = "sprites/glow1.vmt"
ENT.EyeColor       = Color(255, 0, 0)
ENT.HackedEyeColor = Color(0, 255, 0)
-- Per-eye colours (optional). Keys are attachment names; missing ones use EyeColor / HackedEyeColor.
--   ENT.EyeColors       = { Eye = Color(255, 0, 0), Light = Color(0, 100, 255) }
--   ENT.HackedEyeColors = { Eye = Color(0, 255, 0), Light = Color(255, 255, 0) }
ENT.EyeColors       = {}
ENT.HackedEyeColors = {}
ENT.EyeAttachments  = { "Eye", "Light" } -- which attachments get a glow sprite
ENT.StunColor      = Color(255, 128, 0)
ENT.StunDuration   = 2.5
ENT.EyeAlpha       = 164
ENT.EyeScale       = 0.25
ENT.StunScale      = 0.15

-- sounds (HL2 script names; set "" to silence one)
ENT.SliceSound   = "NPC_Manhack.Slice"
ENT.GrindSound   = "NPC_Manhack.Grind"
ENT.DeathSound   = "NPC_Manhack.Die"
ENT.EngineSound1 = "NPC_Manhack.EngineSound1"
ENT.EngineSound2 = "NPC_Manhack.EngineSound2"
ENT.BladeSound   = "NPC_Manhack.BladeSound"
ENT.EngineVolume = 0.55
ENT.GibModels = {
	"models/gibs/manhack_gib01.mdl", "models/gibs/manhack_gib02.mdl", "models/gibs/manhack_gib03.mdl",
	"models/gibs/manhack_gib04.mdl", "models/gibs/manhack_gib05.mdl",
}
ENT.Pitch1 = { min = 100, max = 160, dist = 512, water = 85 }
ENT.Pitch2 = { min = 85,  max = 190, dist = 400, water = 90 }

list.Set("MachineMayhem", "snpc_manhack", {
	Name     = "Manhack",
	Class    = "snpc_manhack",
	Category = "Machine Mayhem",
	SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), 
	Offset   = 48,
})

if not SERVER then return end

--=========================================================================
-- SERVER
--=========================================================================

local THINK_REF = 0.1
local BG_BLADE, BG_BLUR = 1, 2 -- bodygroups on manhack.mdl

--[[---------------------------------------------------------------------
	VARIANT HOOKS - override these in a variant if you need to
-----------------------------------------------------------------------]]

-- Which class do other NPCs see us as? Held / hacked manhacks count as player allies.
function ENT:GetNPCClass()
	if self.Held or self.Hacked then return CLASS_PLAYER_ALLY end
	return self.NPCClass
end

-- Factions. The engine's relationship lookup is unreliable for scripted NPCs, so manhacks decide
-- friend/foe themselves. A regular manhack is friends ONLY with Combine-side NPCs; a hacked (or held)
-- one is friends ONLY with the player and rebel-side NPCs. Everything else is an enemy.
local function ClassSet(names)
	local t = {}
	for _, n in ipairs(names) do
		local v = _G[n]
		if v then t[v] = true end
	end
	return t
end
local COMBINE_SIDE = ClassSet({ "CLASS_COMBINE", "CLASS_COMBINE_GUNSHIP", "CLASS_COMBINE_HUNTER", "CLASS_METROPOLICE",
	"CLASS_MILITARY", "CLASS_SCANNER", "CLASS_STALKER", "CLASS_PROTOSNIPER", "CLASS_MANHACK" })
local REBEL_SIDE = ClassSet({ "CLASS_PLAYER", "CLASS_PLAYER_ALLY", "CLASS_PLAYER_ALLY_VITAL", "CLASS_CITIZEN_PASSIVE",
	"CLASS_CITIZEN_REBEL", "CLASS_VORTIGAUNT", "CLASS_CONSCRIPT", "CLASS_HACKED_ROLLERMINE" })
-- things that are not real targets
local IGNORED = ClassSet({ "CLASS_NONE", "CLASS_BULLSEYE", "CLASS_FLARE", "CLASS_MISSILE", "CLASS_EARTH_FAUNA" })

-- VJ Base NPCs report their side through VJ_NPC_Class (strings such as "CLASS_COMBINE"): translate it
local function VJClass(ent)
	local vc = ent.VJ_NPC_Class
	if type(vc) ~= "table" then return end
	local first, rebel
	for _, name in ipairs(vc) do
		local c = _G[name]
		if c then
			if COMBINE_SIDE[c] then return c end
			if REBEL_SIDE[c] then rebel = rebel or c end
			first = first or c
		end
	end
	return rebel or first
end

local function ClassOf(ent)
	if ent:IsPlayer() then return CLASS_PLAYER end
	if ent.IsPhysicsSNPC then return ent:GetNPCClass() end
	local vj = VJClass(ent)
	if vj then return vj end
	if ent.Classify then return ent:Classify() end
end

local function SideOf(c)
	if COMBINE_SIDE[c] then return 1 end
	if REBEL_SIDE[c] then return 2 end
	return 0 -- zombies, headcrabs, antlions, ...: nobody's friend
end

function ENT:GetDisposition(ent)
	-- a manhack that is being held (gravity gun / physgun) shows up as a player ally to everyone else, but its own kind
	-- must not turn on it: if it would be on our side when let go, it stays a friend
	if IsValid(ent) and ent.IsPhysicsSNPC and ent ~= self and (ent.Held or ent:HasPhysicsAttacker(0.35)) then
		local own = ent.Hacked and CLASS_PLAYER_ALLY or ent.NPCClass
		local a, b = SideOf(self:GetNPCClass()), own and SideOf(own) or 0
		if own and (own == self:GetNPCClass() or (a ~= 0 and a == b)) then return D_LI end
	end
	local theirs = IsValid(ent) and ClassOf(ent)
	if IsValid(ent) and ent:IsNextBot() then
		-- nextbots rarely have a meaningful class: fair game unless one openly sides with us
		local a, b = SideOf(self:GetNPCClass()), theirs and SideOf(theirs) or 0
		if theirs and (theirs == self:GetNPCClass() or (a ~= 0 and a == b)) then return D_LI end
		return D_HT
	end
	if not theirs or IGNORED[theirs] then return D_NU end
	local mine = self:GetNPCClass()
	if mine == theirs then return D_LI end
	local a, b = SideOf(mine), SideOf(theirs)
	if a ~= 0 and a == b then return D_LI end
	return D_HT
end

function ENT:GetMaxEnginePower()
	return self.Hacked and self.HackedEnginePower or self.EnginePower
end

function ENT:GetMaxSpeed()
	if self:HasPhysicsAttacker(0.35) then return self.PuntedMaxSpeed end
	if self.WaterSuspended then return self.MaxSpeed * 0.1 end
	if self.BurstMaxSpeed and CurTime() < self.BurstEnd then return self.BurstMaxSpeed end
	if self.FarMaxSpeed then
		local foe = self:GetFoe()
		if IsValid(foe) and self:GetPos():DistToSqr(foe:GetPos()) > self.FarSpeedDist ^ 2 then
			return self.FarMaxSpeed
		end
	end
	return self.MaxSpeed
end

function ENT:IsFlightDisabled()
	return self.Held or self.Packed
end

function ENT:GetSliceInterval()
	if self.Held or self:HasPhysicsAttacker(0.35) then return self.HeldSliceInterval end
	return self.SliceInterval
end

-- Damage dealt by one blade hit. (Port of CNPC_Manhack::Slice's damage rules.)
function ENT:GetSliceDamage(ent, interval)
	local d = self.BladeDamage * interval
	if ent:IsPlayer() then d = d * self.PlayerDamageScale end

	if self.Held then
		d = self.HeldBladeDamage * interval
	elseif ent:IsNPC() and self:HasPhysicsAttacker(0.35) then
		d = self.ThrownNPCDamage
	elseif string.StartWith(ent:GetClass(), "prop_") or string.StartWith(ent:GetClass(), "func_breakable") then
		d = self.PropSliceDamage or math.max(ent:Health(), d) -- props break immediately
	elseif ent:IsNPC() and ent:GetClass() == "npc_combine_s" and self:GetDisposition(ent) == D_HT then
		d = d * self.CombineSoldierScale
	end
	if self.Held and self.HeldPropSliceDamage and (string.StartWith(ent:GetClass(), "prop_") or string.StartWith(ent:GetClass(), "func_breakable")) then
		d = self.HeldPropSliceDamage
	end
	if self.CutZombies and ent:IsNPC() and ent:Classify() == CLASS_ZOMBIE and ent:Health() <= d then
		d = ent:GetMaxHealth() -- cut it in half
	end
	return math.max(d, 1)
end

--=========================================================================
-- Setup
--=========================================================================

-- VARIANT HOOK: called at the end of the manhack's own setup (model bones, extra state...).
function ENT:OnVariantSpawned() end
-- VARIANT HOOK: called every tick while alive.
function ENT:OnVariantThink(dt) end
-- VARIANT HOOK: called once when it dies (crash, corpse or gibs).
function ENT:OnVariantDeath() end
-- VARIANT HOOK: edit/absorb incoming damage first (e.g. an energy shield). Change it with dmg:SetDamage().
function ENT:AbsorbDamage(dmg) end

function ENT:OnSpawned()
	local now = CurTime()
	self.Packed        = self.StartPacked
	self.BladesActive  = not self.Packed
	self.BladeSpeed    = 0
	self.NextBurstTime = now
	self.BurstEnd      = 0
	self.BurstDir      = Vector(0, 0, 0)
	self.ShowingHostile = false
	self.ForceMoveTarget = nil
	self.ForceMoveTime = 0
	self.SwarmCenter   = nil
	self.SwarmRecalc   = 0
	self.SwarmMoveTime = 0
	self.DoSwarm       = self.SwarmEnabled
	self.LoiterPos     = nil
	self.NextLoiterPulse = now
	self.PanelValue    = 0
	self.LastWaterLevel = 0
	self.NextEngineNoise = now
	self.NextDanger    = 0
	self.StunnedUntil  = 0
	self.Strobe        = false
	self.WaterSuspended = false

	self.PitchNow1, self.PitchNow2 = self.Pitch1.min, self.Pitch2.min
	self.DirtyPitch = true

	self:SyncNPCClass()
	self.NextSearch = now + 1
	self.NextRegen = now
	self.LastDamaged = -10
	self.HadFoe = false
	self.LastAlert = -10
	if self.ModelColor then self:SetColor(self.ModelColor) end
	self:BladesInit()
	self:OnVariantSpawned()
end

-- Play an activity's sequence. SNPC animation is owned by the engine's activity system, which keeps
-- resetting to idle unless the ideal activity is set too, so set all three and re-assert every tick.
function ENT:PlayAnim(act)
	self:ResetIdealActivity(act)
	self:SetActivity(act)
	local seq = self:SelectWeightedSequence(act)
	if not seq or seq < 0 then
		for _, n in ipairs(act == ACT_FLY and { "fly", "Fly", "idle", "idle01" } or { "idle", "idle01", "Idle" }) do
			seq = self:LookupSequence(n)
			if seq and seq >= 0 then break end
		end
	end
	self.AnimAct = act
	self.AnimSeq = (seq and seq >= 0) and seq or nil
	if self.AnimSeq and self:GetSequence() ~= self.AnimSeq then self:ResetSequence(self.AnimSeq) end
end

function ENT:BladesInit()
	self:PlayAnim(self.Packed and ACT_IDLE or ACT_FLY)
	if self.Packed then
		-- folded up: no engine, falls (a bit slower than real gravity, for looks)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableGravity(true) end
	else
		self:StartEngine(not self.Silent)
	end
end

function ENT:StartEngine(withSound)
	if withSound then self:SoundInit() end
	self:SetBodygroup(BG_BLADE, 1)
	self.BladesActive = true
	self:StartEye()
	self:PlayAnim(ACT_FLY)
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then phys:EnableGravity(false) end
end

-- Leave the packed-up state (damage, enemy sighted, or the "Unpack" input).
function ENT:Unpack()
	if not self.Packed then return end
	self.Packed = false
	self:EmitSound("NPC_Manhack.Unpack")
	self:StartEngine(not self.Silent)
	self:PlayAnim(ACT_FLY)
	self.NextBurstTime = CurTime() + 2 -- Valve: no bursts until fully unpacked
end

-- Turn this manhack into an ally (what Alyx's hacking does), or back again.
function ENT:SetHacked(state)
	self.Hacked = state and true or false
	self:SyncNPCClass()
	self.EnginePowerScale = math.min(self.EnginePowerScale or 1, self:GetMaxEnginePower())
	self:SetFoe(NULL)
	self:ReleaseAttackSlot()
	self:KillSprites()
	self:StartEye() -- recreate so the colour changes
	if self.Hacked then self:StopLoitering() end
end

--=========================================================================
-- Behaviour (Valve's schedules, flattened into one decision per tick)
--=========================================================================

function ENT:IsInEffectiveTargetZone(target)
	-- are we vertically between the target's feet and head?
	local ourZ = self:WorldSpaceCenter().z
	local low, high
	if target:IsPlayer() and target:InVehicle() and IsValid(target:GetVehicle()) then
		local v = target:GetVehicle()
		low = v:GetPos().z + v:OBBMins().z
		high = v:GetPos().z + v:OBBMaxs().z
	else
		low = target:GetPos().z + target:OBBMins().z
		high = target:GetPos().z + target:OBBMaxs().z
	end
	return ourZ > low and ourZ < high
end

-- Chase height: 75% up the enemy's body (Valve's TranslateNavGoal).
function ENT:GetChaseTarget(enemy)
	if enemy:IsPlayer() and enemy:InVehicle() and IsValid(enemy:GetVehicle()) then
		return enemy:GetVehicle():WorldSpaceCenter()
	end
	local pos = enemy:GetPos()
	return Vector(pos.x, pos.y, pos.z + Lerp(0.75, enemy:OBBMins().z, enemy:OBBMaxs().z))
end

function ENT:UpdateMovement(dt)
	local now = CurTime()

	if self.Packed then
		if self:HasEnemy() then self:Unpack() end
		return
	end

	local enemy = self:GetFoe()
	if self.LoiterPos and IsValid(enemy) then self:StopLoitering() end

	if self.LoiterPos then self:Loiter(dt) else self:MaintainGroundHeight(dt) end

	-- "so cops, etc. will try to avoid them"
	if not self.NoDangerSounds and not self.Held and now >= self.NextDanger then
		self.NextDanger = now + 0.1
		sound.EmitHint(SOUND_DANGER, self:GetPos(), 75, 0.2, self)
	end

	local chase = self:GetChasePos()
	if now < self.ForceMoveTime and self.ForceMoveTarget then
		self:MoveToTarget(dt, self:SteerAround(self.ForceMoveTarget))
	elseif chase then
		self:CombatMove(dt, enemy, chase)
	elseif now < self.SwarmMoveTime and self.SwarmCenter then
		self:MoveToTarget(dt, self:SteerAround(self.SwarmCenter))
	elseif self.DoSwarm and not self.LoiterPos and self:CountSwarmMates() > 0 then
		self:SwarmMove(dt)
	else
		self:Decelerate(dt, 9.5)
	end

	self:UpdateBurst(dt)
end

function ENT:CombatMove(dt, enemy, chase)
	local now = CurTime()
	local pos = self:GetPos()

	-- committed charge: fly straight, homing a little on the enemy
	if now < self.BurstEnd and not self:IsPathClear(self.BurstDir, math.Clamp(self.CurVel:Length() * 0.3, 90, 450)) then
		self:StopBurst() -- would slam into the world: abort the charge and brake
		self.CurVel = self.CurVel * 0.4
	end
	if now < self.BurstEnd then
		local zDist = 500
		if IsValid(enemy) and self.FoeVisible then
			local steer = enemy:EyePos() - pos
			zDist = math.abs(steer.z)
			steer:Normalize()
			self.BurstDir = self.BurstDir + steer * 4 * (dt / THINK_REF)
			self.BurstDir.z = steer.z
			self.BurstDir:Normalize()
		end
		self:MoveToTarget(dt, nil, self.BurstDir, zDist / math.max(dt, THINK_REF))
		return
	end

	-- waiting for the next attack opportunity: swarm
	if now < self.NextBurstTime then
		self:SwarmMove(dt)
		return
	end

	-- only a few manhacks may attack at once, the rest swarm
	local visible = IsValid(enemy) and self.FoeVisible
	if self.DoSwarm and visible and not self:OccupyAttackSlot(enemy, self.AttackSlots) then
		self:SwarmMove(dt)
		return
	end

	-- (chase is the enemy's live position only while we see it, otherwise where we last saw it)
	local target = visible and self:GetChaseTarget(enemy) or chase

	-- too close to the enemy (or badly out of height): back away and line up again
	if visible and not (enemy:IsPlayer() and enemy:InVehicle()) then
		local d = pos:Distance(enemy:WorldSpaceCenter())
		local deltaZ = pos.z - enemy:EyePos().z
		if d < self.MinAttackDist or deltaZ > 12 or deltaZ < -24 then
			if d < self.MinAttackDist * 2 then
				local away = pos - enemy:WorldSpaceCenter()
				away.z = 0
				if away:LengthSqr() < 1 then away = VectorRand() away.z = 0 end
				away:Normalize()
				target = Vector(pos.x + away.x * 60, pos.y + away.y * 60, enemy:EyePos().z - 6)
			end
		end
	end

	self:MoveToTarget(dt, self:SteerAround(target, enemy))
end

-- Orbit / drift toward the nearby group (TASK_MANHACK_FIND_SQUAD_CENTER + MOVEAT_SAVEPOSITION).
-- Only manhacks that are close and in line of sight count. With nobody to join, a waiting manhack
-- closes in on the enemy instead (so it never crawls or hangs around behind a wall).
-- Targets are placed far enough ahead that it flies at full speed (a 10-unit target made it crawl).
function ENT:SwarmMove(dt)
	local now = CurTime()
	if now >= self.SwarmRecalc then
		self.SwarmRecalc = now + 1
		self.SwarmCenter = self:GetSwarmCenter()
	end

	local pos = self:GetPos()
	local center = self.SwarmCenter
	if not center then
		local enemy = self:GetFoe()
		local chase = self:GetChasePos()
		if chase then
			-- hold back a little from the enemy rather than diving in
			local to = chase - pos
			if to:Length() > 250 then
				self:MoveToTarget(dt, self:SteerAround(chase, enemy))
				return
			end
			center = chase
		else
			self:Decelerate(dt, 3)
			return
		end
	end

	local dir = center - pos
	local dist = dir:Length()
	if dist > 0.01 then dir = dir / dist end

	local target
	if dist < 80 then
		target = pos + Vector(-dir.y, dir.x, 0) * 140 + Vector(0, 0, math.sin(now * 1.3 + self:EntIndex()) * 20)
	else
		target = pos + dir * math.min(dist, 300)
	end
	self:MoveToTarget(dt, self:SteerAround(target))
end

--=========================================================================
-- Charge ("burst") attack
--=========================================================================

function ENT:ShowHostile(state)
	if self.ShowingHostile == state then return end
	self.ShowingHostile = state
	if self.Silent then return end
	self:EmitSound(state and "NPC_Manhack.ChargeAnnounce" or "NPC_Manhack.ChargeEnd")
end

function ENT:StartBurst(dir)
	local now = CurTime()
	if now < self.BurstEnd then return end
	self:ShowHostile(true)
	self.NextBurstTime = now + self.BurstCooldown
	self.BurstEnd = now + self.BurstTime
	self.BurstDir = Vector(dir)
end

function ENT:StopBurst()
	local now = CurTime()
	if now >= self.BurstEnd then return end
	self:ShowHostile(false)
	self.NextBurstTime = now + self.BurstCooldown
	self.BurstEnd = now - 0.1
end

-- Port of the start of CNPC_Manhack::MoveExecute_Alive
function ENT:UpdateBurst(dt)
	local enemy = self:GetFoe()
	local noise = self.NoiseScale
	local now = CurTime()

	if IsValid(enemy) and self.FoeVisible then
		local dist2D = (self:GetPos() - enemy:GetPos()):Length2D()
		if dist2D < self.ChargeMinDist then noise = 2 end -- steadier when close

		if self:IsInEffectiveTargetZone(enemy) and dist2D < self.ChargeMinDist and now > self.NextBurstTime then
			local curDir = self.CurVel:GetNormalized()
			local toEnemy = enemy:EyePos() - self:WorldSpaceCenter()
			toEnemy:Normalize()
			local dot = curDir:Dot(toEnemy)

			if dot > 0.75 and self:IsPathClear(toEnemy, math.min(enemy:GetPos():Distance(self:GetPos()), 450)) then
				local offsetDir = toEnemy - curDir
				offsetDir:Normalize()
				offsetDir.z = 0
				local offsetSpeed = self.CurVel * dot
				self.ForceVel = self.ForceVel + offsetDir * (offsetSpeed:Length2D() * 0.25)

				self:StartBurst(toEnemy) -- commit: no steering for about a second
				if self.LungeSpeed > 0 then self.ForceVel = self.ForceVel + toEnemy * self.LungeSpeed end
				self:SetEyeState("charge")
			end
		end

	end
	if now > self.BurstEnd then self:ShowHostile(false) end -- also when the enemy vanished

	self.CurNoiseScale = noise
end

-- Hitting anything ends a charge.
function ENT:OnContact(ent, c)
	self:StopBurst()
	return false
end

-- After a hit: no charging for a while, and fly away first (Valve: bounce + StopBurst).
function ENT:OnSliced(ent)
	self.BladeSpeed = 20
	if self.Held or self:HasPhysicsAttacker(0.35) then return end

	local now = CurTime()
	self:ShowHostile(false)
	self.BurstEnd = now - 0.1
	self.NextBurstTime = now + self.BurstCooldown

	local away = self:WorldSpaceCenter() - ent:WorldSpaceCenter()
	away.z = 0
	if away:LengthSqr() < 1 then away = VectorRand() away.z = 0 end
	away:Normalize()
	self.ForceMoveTarget = self:GetPos() + away * self.RetreatDistance + Vector(0, 0, 20)
	self.ForceMoveTime = now + self.RetreatTime
end

--=========================================================================
-- Loitering (friendly manhack that was dropped with nothing to fight)
--=========================================================================

function ENT:StartLoitering()
	self.LoiterPos = self:GetPos()
	self.BankTarget = Vector(0, 0, 0)
	self.ForceVel = Vector(0, 0, 0)
	self.CurVel = Vector(0, 0, 0)
end

function ENT:StopLoitering()
	self.LoiterPos = nil
	self.NextLoiterPulse = CurTime()
end

function ENT:Loiter(dt)
	if self.Held or not self.LoiterPos then return end
	local now = CurTime()
	local pos = self:GetPos()
	local distSqr = self.LoiterPos:DistToSqr(pos)

	if distSqr > 144 then
		local dir = self.LoiterPos - pos
		dir:Normalize()
		if now > self.NextLoiterPulse then
			-- a pulse of thrust back toward the spot, at most once a second
			self.ForceVel = dir * (distSqr > 144 * 4 and 12 or 6)
			self.NextLoiterPulse = now + 1
		end
	else
		-- counteract velocity to settle
		self.ForceVel = self.CurVel * (-0.5 * (dt / THINK_REF))
	end
end

--=========================================================================
-- Blades, panels, water
--=========================================================================

function ENT:UpdateBlades(dt)
	if not self.BladesActive then
		self:SetBodygroup(BG_BLADE, 0)
		self:SetBodygroup(BG_BLUR, 0)
		self.BladeSpeed = 0
		self.MotorScale = 1
		self:SetPlaybackRate(1)
		return
	end

	local k = dt / THINK_REF
	if not self:IsStalled() then
		if self.BladeSpeed < 10 then
			self.BladeSpeed = self.BladeSpeed * (2 ^ k) + k
		else
			self.BladeSpeed = self.BladeSpeed + 80 * dt
		end
	end
	self.BladeSpeed = math.min(self.BladeSpeed, 100)

	-- blades -> blades+blur -> blur only
	if self.BladeSpeed < 20 then
		self:SetBodygroup(BG_BLADE, 1) self:SetBodygroup(BG_BLUR, 0)
	elseif self.BladeSpeed < 40 then
		self:SetBodygroup(BG_BLADE, 1) self:SetBodygroup(BG_BLUR, 1)
	else
		self:SetBodygroup(BG_BLADE, 0) self:SetBodygroup(BG_BLUR, 1)
	end

	self:SetPlaybackRate(math.max(self.BladeSpeed / 100, 0.01))
	self.MotorScale = self.BladeSpeed / 100 -- the motor can only push as hard as the blades spin
end

-- Keep the right sequence playing (the engine can reset it).
function ENT:CheckAnim()
	local want = self.BladesActive and ACT_FLY or ACT_IDLE
	if self.AnimAct ~= want then self:PlayAnim(want) return end
	if self.AnimSeq and self:GetSequence() ~= self.AnimSeq then self:ResetSequence(self.AnimSeq) end
end

-- Hull panels open while an enemy is close (or we are charging) and close again otherwise.
-- Driven purely by current state every tick, so they can never get stuck open.
function ENT:UpdatePanels(dt)
	if self:IsStalled() then
		for i = 1, 4 do self:SetPoseParameter("Panel" .. i, math.Rand(0, 90)) end
		self.PanelValue = 45
		return
	end

	local open = false
	local enemy = self:GetFoe()
	if self.BladesActive and IsValid(enemy) then
		local now = CurTime()
		if now < self.ForceMoveTime then
			open = false -- flying away after a hit: stay closed
		else
			open = now < self.BurstEnd or self:GetPos():Distance(enemy:WorldSpaceCenter()) < self.PanelOpenDist
		end
	end

	self.PanelValue = math.Approach(self.PanelValue, open and 90 or 0, (open and 600 or 220) * dt)
	for i = 1, 4 do self:SetPoseParameter("Panel" .. i, self.PanelValue) end
end

function ENT:UpdateWater()
	local lvl = self:WaterLevel()
	if (lvl > 0) ~= (self.LastWaterLevel > 0) then
		local ed = EffectData()
		ed:SetOrigin(self:WorldSpaceCenter())
		ed:SetNormal(Vector(0, 0, 1))
		ed:SetScale(8)
		util.Effect("watersplash", ed)
	end
	self.WaterSuspended = lvl > 0
	self.LastWaterLevel = lvl
end

function ENT:OnThinkAlive(dt)
	self:UpdateWater()
	self:UpdateBlades(dt)
	self:CheckAnim()
	self:UpdatePanels(dt)
	self:UpdateEyeFx()
	if not self.Packed then self:PlayFlySound() end
	self:UpdateSearch()
	if self.RotorWash then self:UpdateRotorWash() end
	if self.CombatEnginePower and self:HasEnemy() and self:WaterLevel() == 0 then
		self.EnginePowerScale = self.CombatEnginePower
	end
	self:UpdateRegen()
	self:UpdateAlerts()
	self:OnVariantThink(dt)
end

function ENT:UpdateRegen()
	if self.RegenAmount <= 0 then return end
	local now = CurTime()
	if now < self.NextRegen then return end
	self.NextRegen = now + self.RegenDelay
	if self:Health() >= self:GetMaxHealth() then return end
	if self.RegenOutOfCombat and (self:HasEnemy() or now - self.LastDamaged < 3) then return end
	self:SetHealth(math.min(self:GetMaxHealth(), self:Health() + self.RegenAmount))
	if self:Health() > self:GetMaxHealth() * 0.5 then self:DestroySmokeTrail() end
end

function ENT:UpdateAlerts()
	local has = self:HasEnemy()
	local now = CurTime()
	if has and not self.HadFoe then
		if self.AlertNoise ~= "" and not self.Silent and now - self.LastAlert >= self.AlertCooldown then
			self:EmitSound(self.AlertNoise, 80, self.AlertPitch)
			self.LastAlert = now
		end
	elseif self.HadFoe and not has then
		if self.LoseNoise ~= "" and not self.Silent then self:EmitSound(self.LoseNoise, 80, self.AlertPitch) end
	end
	self.HadFoe = has
end

function ENT:UpdateSearch()
	if self.SearchSound == "" or self.Packed or self.Silent or self:HasEnemy() then return end
	local now = CurTime()
	if now < self.NextSearch then return end
	self.NextSearch = now + self.SearchInterval
	self:EmitSound(self.SearchSound, 65, 100)
end

function ENT:UpdateRotorWash()
	local fast = self.CurVel:LengthSqr() > 600 ^ 2
	if fast and not IsValid(self.RotorWashEnt) then
		local r = ents.Create("env_rotorwash_emitter")
		if IsValid(r) then
			r:SetPos(self:GetPos())
			r:SetParent(self)
			r:Spawn()
			r:Activate()
			self.RotorWashEnt = r
		end
	elseif not fast and IsValid(self.RotorWashEnt) then
		self.RotorWashEnt:Remove()
		self.RotorWashEnt = nil
	end
end

--=========================================================================
-- Eyes (env_sprite glows parented to the "Eye" and "Light" attachments)
--=========================================================================

-- Colour for one eye (by attachment name). Per-eye tables win over the single EyeColor.
function ENT:GetEyeColor(att)
	if CurTime() < self.StunnedUntil then return self.StunColor end
	if self.Hacked then
		return self.HackedEyeColors[att] or self.HackedEyeColor
	end
	return self.EyeColors[att] or self.EyeColor
end

function ENT:KillSprites()
	for _, s in pairs(self.Sprites or {}) do
		if IsValid(s) then s:Remove() end
	end
	self.Sprites = {}
end

function ENT:MakeSprite(attachment, scale)
	local id = self:LookupAttachment(attachment)
	if not id or id <= 0 then return nil end
	local att = self:GetAttachment(id)
	local s = ents.Create("env_sprite")
	if not IsValid(s) then return nil end
	s:SetKeyValue("model", self.GlowSprite)
	s:SetKeyValue("rendermode", "9") -- world-space glow
	s:SetKeyValue("scale", tostring(scale))
	s:SetKeyValue("GlowProxySize", "2")
	s:SetKeyValue("spawnflags", "1")
	s:SetPos(att and att.Pos or self:GetPos())
	s:Spawn()
	s:SetParent(self)
	s:Fire("SetParentAttachment", attachment, 0)
	return s
end

function ENT:ApplySpriteColor(scaleMul)
	local scale = ((CurTime() < self.StunnedUntil) and self.StunScale or self.EyeScale) * (scaleMul or 1)
	for att, s in pairs(self.Sprites or {}) do
		if IsValid(s) then
			local c = self:GetEyeColor(att)
			s:SetColor(Color(c.r, c.g, c.b, self.EyeAlpha))
			s:SetKeyValue("scale", tostring(scale))
		end
	end
end

function ENT:StartEye()
	self:KillSprites()
	if self.Packed then return end
	self.Sprites = {}
	for _, att in ipairs(self.EyeAttachments) do
		local s = self:MakeSprite(att, self.EyeScale)
		if s then self.Sprites[att] = s end
	end
	self:ApplySpriteColor()
end

-- state: "stunned" (orange, after a club hit) or "charge" (brief flare)
function ENT:SetEyeState(state)
	if state == "stunned" then
		self.StunnedUntil = CurTime() + self.StunDuration
		self:ApplySpriteColor()
		if not self.Silent then self:EmitSound("NPC_Manhack.Stunned") end
	elseif state == "charge" then
		self.ChargeFlareUntil = CurTime() + 0.25
	end
end

function ENT:UpdateEyeFx()
	local now = CurTime()
	local stunned = now < self.StunnedUntil
	if self.WasStunned and not stunned then
		self.WasStunned = false
		self:ApplySpriteColor()
	elseif stunned then
		self.WasStunned = true
	end
	if self.ChargeFlareUntil and now < self.ChargeFlareUntil then
		if not self.FlareOn then self:ApplySpriteColor(1.6) end
		self.FlareOn = true
	elseif self.FlareOn then
		self.FlareOn = false
		self:ApplySpriteColor()
	end
end

--=========================================================================
-- Sound
--=========================================================================

local function Loop(ent, name, vol)
	if not name or name == "" then return nil end
	local s = CreateSound(ent, name)
	if s then s:PlayEx(vol or ent.EngineVolume, 100) end
	return s
end

function ENT:SoundInit()
	self:StopLoopingSounds()
	self.Loop1 = Loop(self, self.EngineSound1)
	self.Loop2 = Loop(self, self.EngineSound2)
	self.Loop3 = Loop(self, self.BladeSound, self.BladeVolume)
end

function ENT:StopLoopingSounds()
	for _, k in ipairs({ "Loop1", "Loop2", "Loop3", "GrabLoop" }) do
		if self[k] then self[k]:Stop() self[k] = nil end
	end
end

local function PitchFor(cfg, dist, water)
	if water then return cfg.water end
	local t = 1 - math.Clamp(dist / cfg.dist, 0, 1) -- closer to the enemy = higher pitch
	return Lerp(t, cfg.min, cfg.max)
end

function ENT:PlayFlySound()
	if self.Silent then return end
	local now = CurTime()
	if now < self.NextEngineNoise then return end
	self.NextEngineNoise = now + 0.1

	local enemy = self:GetFoe()
	local dist = IsValid(enemy) and self:GetPos():Distance(enemy:GetPos()) or 1e9
	local water = self.WaterSuspended
	local p1, p2 = PitchFor(self.Pitch1, dist, water), PitchFor(self.Pitch2, dist, water)

	-- ease toward target pitch so it does not jump
	self.PitchNow1 = Lerp(0.4, self.PitchNow1, p1)
	self.PitchNow2 = Lerp(0.4, self.PitchNow2, p2)
	if self.Loop1 then self.Loop1:ChangePitch(self.PitchNow1, 0.1) end
	if self.Loop2 then self.Loop2:ChangePitch(self.PitchNow2, 0.1) end

	-- stalled engine: cut the blade loop
	if self.Loop3 then
		self.Loop3:ChangeVolume(self:IsStalled() and 0 or (self.BladeVolume or self.EngineVolume), 0.1)
	end
end

--=========================================================================
-- Damage (port of CNPC_Manhack::OnTakeDamage_Alive / TakeDamage rules)
--=========================================================================

function ENT:ModifyDamage(dmg)
	if self.Packed then self:Unpack() end
	self.LastDamaged = CurTime()

	if self.BulletDamageScale ~= 1 and dmg:IsBulletDamage() then dmg:ScaleDamage(self.BulletDamageScale) end
	if self.DamageTakenScale ~= 1 then dmg:ScaleDamage(self.DamageTakenScale) end
	self:AbsorbDamage(dmg)
	if dmg:GetDamage() <= 0 then return end

	local inf = dmg:GetInflictor()
	local infClass = IsValid(inf) and inf:GetClass() or ""

	if dmg:IsDamageType(DMG_PHYSGUN) then
		dmg:SetDamage(1) -- "physgun does 1 point; doesn't kill, just tosses it around"
		return
	end

	if infClass == "prop_vehicle_airboat" then
		dmg:SetDamage(self:Health() + 1) -- airboat blades shred it
		return
	end

	if dmg:IsDamageType(DMG_CLUB) then
		dmg:ScaleDamage(1.5)
		-- batted: fling it toward a nearby prop if one is close to the swing line
		local attacker = dmg:GetAttacker()
		if IsValid(attacker) then
			local dir = (self:GetPos() - attacker:GetPos()):GetNormalized()
			local best, bestDot
			for _, e in ipairs(ents.FindInSphere(self:GetPos(), 300)) do
				if e ~= self and e:GetClass():StartWith("prop_physics") then
					local d = (e:GetPos() - self:GetPos()):GetNormalized():Dot(dir)
					if d > 0.7 and (not bestDot or d > bestDot) then best, bestDot = e, d end
				end
			end
			if best then
				dir = (best:WorldSpaceCenter() - self:GetPos()):GetNormalized()
			end
			dmg:SetDamageForce(dir * math.max(dmg:GetDamage(), 10) * 400)
		end
		return
	end
end

function ENT:OnDamaged(dmg)
	local now = CurTime()
	if not self.Silent then
		if dmg:IsDamageType(DMG_CLUB) and self.BatSound ~= "" then
			self:EmitSound(self.BatSound, 75, self.HitPitch)
		elseif self.HitSound ~= "" and now >= (self.NextHitSound or 0) then
			self.NextHitSound = now + 0.3
			self:EmitSound(self.HitSound, 75, self.HitPitch)
		end
	end
	if self.KnockbackResistBullets and dmg:IsBulletDamage() then return end
	if dmg:IsDamageType(DMG_CLUB) then
		self.EngineStallTime = now + 1
		self:SetEyeState("stunned")
		self:StopBurst()
	elseif not dmg:IsDamageType(DMG_PHYSGUN) then
		-- ordinary hits: brief stall and a shove
		self.EngineStallTime = math.max(self.EngineStallTime, now + 0.25)
		local f = dmg:GetDamageForce()
		if not f:IsZero() then
			local dir = f:GetNormalized()
			self.ForceVel = self.ForceVel + dir * dmg:GetDamage() * 20
		end
	end
	self:ApplyDamageForce(dmg, 0.25)
end

function ENT:OnStartDying(dmg)
	self:KillSprites()
	self:StopLoopingSounds()
	self:StopSound("NPC_Manhack.Stunned")
	self:SetBodygroup(BG_BLUR, 0)
	self:SetBodygroup(BG_BLADE, 1)
	self:ReleaseAttackSlot()
	if self.DeathSound ~= "" then self:EmitSound(self.DeathSound) end
	self:OnVariantDeath()
end

function ENT:OnGibbed()
	self:KillSprites()
	self:StopLoopingSounds()
	self:OnVariantDeath()
end


function ENT:OnRemoved()
	if IsValid(self.RotorWashEnt) then self.RotorWashEnt:Remove() end
	self:KillSprites()
	self:StopLoopingSounds()
	self:ReleaseAttackSlot()
end

--=========================================================================
-- Gravity gun / hacked loitering
--=========================================================================

function ENT:OnGravGunPickup(ply)
	self.PhysAttacker = ply
	self.PhysAttackerTime = CurTime()
	self.Held = true
	self:StopLoitering()
	if self.Packed then self:Unpack() end
	self:SyncNPCClass()
	if self.GrabSound ~= "" then self:EmitSound(self.GrabSound) end
	if self.GrabLoopSound ~= "" and not self.GrabLoop then
		self.GrabLoop = CreateSound(self, self.GrabLoopSound)
		self.GrabLoop:PlayEx(0.1, 100)
		self.GrabLoop:ChangeVolume(0.9, 2)
	end
end

function ENT:OnGravGunDrop(ply)
	self.Held = false
	self.PhysAttackerTime = CurTime()
	self:SyncNPCClass()
	if self.GrabLoop then self.GrabLoop:Stop() self.GrabLoop = nil end
	if self.DropSound ~= "" then self:EmitSound(self.DropSound) end
	-- a friendly manhack with nothing to do just hangs where it was dropped
	if self.Hacked and not self:HasEnemy() then self:StartLoitering() end
end

--=========================================================================
-- Map I/O
--=========================================================================

function ENT:AcceptInput(name, activator, caller, data)
	name = string.lower(name)
	if name == "unpack" then
		self:Unpack()
	elseif name == "disableswarm" then
		self.DoSwarm = false
	elseif name == "enableswarm" then
		self.DoSwarm = true
	elseif name == "powerdown" then
		self:InflictDamage(self:Health() + 1, activator, caller, DMG_GENERIC)
	elseif name == "hack" then
		self:SetHacked(true)
	elseif name == "unhack" then
		self:SetHacked(false)
	end
end
