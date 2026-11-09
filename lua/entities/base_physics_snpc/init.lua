AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")
include("sv_flight.lua")
include("sv_ai.lua")
include("sv_combat.lua")
include("sv_factions.lua")
include("sv_ground.lua")

--[[-------------------------------------------------------------------------
	OVERRIDABLE HOOKS (server). Derived SNPCs override these; none of them
	require calling a "super" function.

	ENT:OnSpawned()                       after everything is set up
	ENT:UpdateMovement(dt)                decide CurVel (see MoveToTarget / Decelerate)
	ENT:OnThinkAlive(dt)                  per-tick cosmetics (blades, eyes, sounds)
	ENT:OnThinkDying(dt)                  per-tick while crashing
	ENT:OnDamaged(dmg)                    after health was reduced and SNPC is still alive
	ENT:OnStartDying(dmg)                 health hit 0, SNPC begins to crash
	ENT:OnContact(ent, data)              physics contact; return true to skip default bump
	ENT:OnRemoved()
	ENT:GetMaxEnginePower()               thrust multiplier
	ENT:GetMaxSpeed()                     speed cap (default self.MaxSpeed)
	ENT:IsFlightDisabled()                true = do not run the motor (packed up, held, ...)
---------------------------------------------------------------------------]]

function ENT:OnSpawned() end
function ENT:UpdateMovement(dt) self:Decelerate(dt, 9.5) end
function ENT:OnThinkAlive(dt) end
function ENT:OnThinkDying(dt) end
function ENT:OnAIDisabled(dt) end
function ENT:OnDamaged(dmg) end
function ENT:OnStartDying(dmg) end
function ENT:OnContact(ent, data) return false end
function ENT:OnRemoved() end
function ENT:GetMaxEnginePower() return self.EnginePower end
function ENT:GetMaxSpeed() return self.MaxSpeed end
function ENT:IsFlightDisabled() return self.Held end

function ENT:Initialize()
	self:SetModel(self.Model)
	if self.ModelScale ~= 1 then self:SetModelScale(self.ModelScale, 0) end

	-- Engine-side NPC bookkeeping (relationships, enemy memory, visibility).
	self:SetHullType(HULL_TINY_CENTERED)
	self:SetHullSizeNormal()
	self:SetBloodColor(DONT_BLEED)
	self:SyncNPCClass()
	self:CapabilitiesAdd(bit.bor(CAP_MOVE_FLY, CAP_SQUAD))
	self:SetMaxHealth(self.SpawnHealth)
	self:SetHealth(self.SpawnHealth)
	self:SetViewOffset(self.ViewOffset)
	self:AddEFlags(EFL_NO_DISSOLVE)

	self.Crashing = false
	self.LastThink = CurTime()
	self.SpawnTime = CurTime()

	self:InitPhysicsFlight()
	self:InitTargeting()
	self:InitCombat()

	if self.PrecacheGibs then self:PrecacheGibs() end

	self:OnSpawned()
end

local AI_DISABLED = GetConVar("ai_disabled")

function ENT:Think()
	local now = CurTime()
	local dt = math.Clamp(now - (self.LastThink or now), 0.001, 0.2)
	self.LastThink = now

	-- impact detection (see CheckVelocityImpact)
	local aiOff = AI_DISABLED:GetBool()
	local ph = self:GetPhysicsObject()
	if IsValid(ph) and not self.Crashing and not aiOff and not self.Held then
		local v = ph:GetVelocity()
		if self.PrevPhysVel then self:CheckVelocityImpact(self.PrevPhysVel, v, self.PrevDesired) end
		self.PrevPhysVel = v
	else
		self.PrevPhysVel = nil
	end

	if aiOff and not self.Crashing then
		-- "Disable AI" (ai_disabled 1): freeze in place, no targeting, no movement, no attacks
		self.Contacts = {}
		self.CurVel = Vector(0, 0, 0)
		self.ForceVel = Vector(0, 0, 0)
		local phys = self:GetPhysicsObject()
		if self.Locomotion == "ground" then
			-- a rolling / falling thing just acts like a prop: leave its motion to the physics engine
			self:OnAIDisabled(dt)
		elseif IsValid(phys) and not self.Held then
			phys:SetVelocity(Vector(0, 0, 0))
			phys:AddAngleVelocity(-phys:GetAngleVelocity())
		end
	elseif self.Crashing then
		self:CrashThink(dt)
		self:OnThinkDying(dt)
	else
		self:UpdateTargeting(dt)
		if not self.StaticProp then
			-- (StaticProp: never moves or turns by itself, the physics engine and the player are the only things that move it)
			self:UpdateMovement(dt)
			self:FinishMovement(dt)
		end
		self:OnThinkAlive(dt)
	end

	self.PrevDesired = self.CurVel and Vector(self.CurVel) or nil

	self:NextThink(now)
	return true
end

function ENT:OnRemove()
	self:OnRemoved()
	self:DestroySmokeTrail()
end
