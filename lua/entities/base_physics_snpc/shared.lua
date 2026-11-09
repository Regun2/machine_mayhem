--[[-------------------------------------------------------------------------
	base_physics_snpc  (SNPC, ENT.Type = "ai", NOT a NextBot)

	A reusable base for flying SNPCs that are driven by VPhysics instead of the
	engine's step/fly movement code. The idea is the same as Valve's
	CAI_BasePhysicsFlyingBot: the AI decides on a *desired velocity*, and a
	"motor" pushes the physics object toward it. Because the entity is a real
	physics object, it collides, bounces, gets shoved by props, can be knocked
	around by explosions, and tumbles when it dies.

	HOW TO MAKE A NEW SNPC ON THIS BASE
		ENT.Base = "base_physics_snpc"
		... then change the config fields below and/or override the hooks.

	NOTE ON FIELD NAMES: do not name a config field after an Entity method
	(Health, Alive, Remove, ...). Writing ENT.Health = 25 would shadow
	Entity:Health() and break self:Health(). That is why this is SpawnHealth.
---------------------------------------------------------------------------]]

ENT.Base = "base_ai"
ENT.Type = "ai"

ENT.PrintName = "Physics SNPC Base"
ENT.Author = ""
ENT.Category = "Machine Mayhem"
ENT.Spawnable = false
ENT.AdminOnly = false
ENT.AutomaticFrameAdvance = true

ENT.IsPhysicsSNPC = true

--=========================================================================
-- CONFIG: body
--=========================================================================
ENT.Model          = "models/hunter/misc/sphere025x025.mdl"
ENT.ModelScale     = 1
ENT.SpawnHealth    = 50
ENT.AllowGravGun   = true       -- false: the gravity gun can neither pick it up nor punt it
ENT.PhysSphereRadius = nil     -- set a number to use a sphere of that radius as the collision body instead of the model's
ENT.PhysBox          = nil     -- { Vector(mins), Vector(maxs) } (entity space): a box as the collision body instead of the model's
ENT.HullSize       = 12        -- half-extent of the cube hull used for traces/engine hull
ENT.StaticProp     = false   -- true: never moves / turns / steers by itself, acts like a physics prop
ENT.PhysMass       = 0         -- 0 = keep the model's own mass
ENT.PhysMaterial   = nil       -- e.g. "metal"; nil = model default
ENT.NPCClass       = CLASS_NONE
ENT.ViewOffset     = Vector(0, 0, 10)

--=========================================================================
-- CONFIG: flight model (all in Source units / seconds)
--=========================================================================
ENT.Locomotion     = "fly"     -- "fly" (physics flight motor) or "ground" (rolling, see sv_ground.lua)
ENT.MaxSpeed       = 500       -- horizontal/overall speed cap
ENT.MaxVertSpeed   = 200       -- vertical speed cap (LimitSpeed zLimit in Valve code)
ENT.AccelAligned   = 300       -- steering accel when already heading toward the target
ENT.AccelTurning   = 200       -- steering accel when heading away from the target
ENT.AccelVertical  = 300
ENT.VelDecay       = 0.3       -- fraction of velocity kept after 1 second of coasting
ENT.EnginePower    = 1         -- thrust multiplier (the hacked manhack uses 2)
ENT.MotorAccel     = 2500      -- max accel the physics motor can apply toward the desired velocity
ENT.TurnRate       = 270       -- deg/s body yaw
ENT.BankAngle      = 30        -- max lean (degrees) when accelerating sideways/forward
ENT.OrientGain     = 10        -- how hard it tries to reach the desired orientation
ENT.OrientDamping  = 8
ENT.NoiseScale     = 7         -- idle wobble strength
ENT.LinearDamping  = 0.2       -- extra vphysics damping so it does not drift forever
ENT.AngularDamping = 4

--=========================================================================
-- CONFIG: perception / behaviour
--=========================================================================
ENT.SightRange     = 3000
ENT.SightFOV       = 200       -- degrees: new targets must be inside this cone (360 = sees everything)
ENT.SenseRange     = 180       -- ...unless this close (it "hears" / senses you)
ENT.SwarmRange     = 800       -- only manhacks this close (and in line of sight) swarm together
ENT.ForgetTime     = 10        -- seconds without seeing the enemy before it loses interest
ENT.SearchTime     = 3         -- ...or this long after reaching the spot where it last saw it
ENT.RetargetDelay  = 0.4
ENT.Silent         = false

--=========================================================================
-- CONFIG: damage taken
--=========================================================================
ENT.PhysicsImpactScale = 0.001 -- ordinary bumps do (almost) nothing, like Valve's SetImpactEnergyScale
ENT.CrashFailsafe  = 2.5       -- seconds a dying SNPC may fly before it is force-removed
ENT.CrashGravity   = 600       -- downward accel while crashing (so wrecks fall instead of floating)
ENT.GibDamage      = 50        -- a killing blow of at least this much (or any blast) gibs instead of crashing
ENT.GibOnCrash     = false     -- true = a crashed wreck also breaks into gibs
ENT.CrashSound     = "ambient/energy/zap9.wav"
ENT.ImpactSpeed    = 650       -- hitting a solid at/above this speed (units/s) is a violent impact
ENT.ImpactSurviveFraction = nil -- e.g. 0.1: impacts never take it below 10% health (only finish it off when already there)
ENT.ImpactDamage   = 150       -- damage at ImpactSpeed, scales linearly with speed (health-independent)
-- gibs: each model is spawned as a physics prop and flung in a random direction with random spin.
-- Empty list = fall back to the engine's generic gib effect.
ENT.GibModels      = {}
ENT.GibCount       = 6
ENT.GibSpeedMin    = 150
ENT.GibSpeedMax    = 550
ENT.GibSpin        = 900       -- max spin, degrees/s per axis
ENT.GibLifetime    = 10
-- a normal (non-gib) death leaves a client-side ragdoll/corpse like regular NPCs
ENT.ClientCorpse   = true
ENT.ImmediateCorpse = true     -- false = crash first (fly erratically until it hits something), then corpse
ENT.CorpseLifetime = 12
ENT.DeathSmoke     = true      -- smoke trail at <= 50% health

--=========================================================================
-- Shared helpers
--=========================================================================

-- Class other NPCs see us as. The ENGINE asks Classify(), so relationships (e.g. Combine vs us)
-- only work if this returns the right CLASS_*. Override GetNPCClass() to change it at runtime.
ENT.Hacked         = false     -- rebel-aligned version
ENT.HackedNPCClass = nil       -- class while hacked (nil = CLASS_PLAYER_ALLY)
ENT.HeldNPCClass   = nil       -- class while held by a gravity gun (nil = unchanged)
function ENT:GetNPCClass()
	if self.Held and self.HeldNPCClass then return self.HeldNPCClass end
	if self.Hacked then return self.HackedNPCClass or CLASS_PLAYER_ALLY end
	return self.NPCClass
end
function ENT:Classify() return self:GetNPCClass() end
-- VJ Base decides friend / foe from ENT.VJ_NPC_Class (names like "CLASS_COMBINE"), or from the classname of stock NPCs.
-- Our classnames mean nothing to it, so publish the side we are on: Combine-side units are "CLASS_COMBINE" and
-- rebel-side (hacked / player allies) are "CLASS_PLAYER_ALLY", so VJ combine and VJ rebels pick the right sides.
local VJ_COMBINE, VJ_REBEL = {}, {}
for _, n in ipairs({ "CLASS_COMBINE", "CLASS_COMBINE_GUNSHIP", "CLASS_COMBINE_HUNTER", "CLASS_METROPOLICE", "CLASS_MILITARY",
	"CLASS_SCANNER", "CLASS_STALKER", "CLASS_PROTOSNIPER", "CLASS_MANHACK" }) do if _G[n] then VJ_COMBINE[_G[n]] = true end end
for _, n in ipairs({ "CLASS_PLAYER", "CLASS_PLAYER_ALLY", "CLASS_PLAYER_ALLY_VITAL", "CLASS_CITIZEN_PASSIVE", "CLASS_CITIZEN_REBEL",
	"CLASS_VORTIGAUNT", "CLASS_CONSCRIPT", "CLASS_HACKED_ROLLERMINE" }) do if _G[n] then VJ_REBEL[_G[n]] = true end end

function ENT:SyncNPCClass()
	local c = self:GetNPCClass()
	if self.SetNPCClass then self:SetNPCClass(c) end
	self.CanAlly = true
	if VJ_COMBINE[c] then
		self.VJ_NPC_Class = { "CLASS_COMBINE", "CLASS_METROPOLICE", "CLASS_MILITARY" }
		self.AlliedWithPlayerAllies = false
	elseif VJ_REBEL[c] then
		-- VJ rebels only treat another entity as a friend when it has CLASS_PLAYER_ALLY AND is flagged AlliedWithPlayerAllies
		self.VJ_NPC_Class = { "CLASS_PLAYER_ALLY", "CLASS_PLAYER_ALLY_VITAL", "CLASS_CITIZEN_REBEL", "CLASS_CITIZEN_PASSIVE" }
		self.AlliedWithPlayerAllies = true
	end
end

-- Overridable. D_LI / D_HT / D_NU toward `ent`. Default = the engine's relationship table.
function ENT:GetDisposition(ent)
	return self:Disposition(ent)
end

-- Overridable. Return true if `ent` should be treated as a friend (never targeted or sliced).
function ENT:IsFriendlyTo(ent)
	if not IsValid(ent) then return false end
	if ent:IsNPC() or ent:IsPlayer() then
		return self:GetDisposition(ent) == D_LI
	end
	return false
end

-- Overridable. Return true if `ent` is a valid target.
local IgnorePlayersCV
function ENT:IsValidTarget(ent)
	if not IsValid(ent) or ent == self then return false end
	if not (ent:IsNPC() or ent:IsPlayer() or ent:IsNextBot()) then return false end
	if ent:IsFlagSet(FL_NOTARGET) then return false end
	if ent:IsPlayer() then
		IgnorePlayersCV = IgnorePlayersCV or GetConVar("ai_ignoreplayers")
		if not ent:Alive() or IgnorePlayersCV:GetBool() then return false end
	end
	-- (nextbots are not judged by Health(): many keep it at 0 or manage their own death)
	-- (the real npc_rollermine never sets a health value either: DAMAGE_EVENTS_ONLY)
	if not ent:IsNextBot() and ent:Health() <= 0 and ent:GetClass() ~= "npc_rollermine" then return false end
	return self:GetDisposition(ent) == D_HT
end
