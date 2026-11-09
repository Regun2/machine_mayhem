--[[-------------------------------------------------------------------------
	HGlee Gunship - the gunship boss of Hunter's Glee, remade as a Machine Mayhem gunship (only listed when Hunter's Glee is
	installed; nothing from Glee is needed to run it).
	  * health 1000 + 200 per player; bullets can't hurt it, everything else is capped at 100 per hit, one hit per 0.25 s,
	    and a health floor (half health, sliding to nothing over 3 minutes of fighting) means it always lives a while
	  * circles its target at range with the pulse gun (Glee's carrot orbit), and every so often (6 / 18 / 30 s by health
	    third), or out of spite, it BOMBS: salvos of dumbfire missiles fired in pairs, led at the target
	  * owed missiles can be paid with the BELLY CANNON instead: a strider warp cannon shot. Right over its target, or backing
	    away nose-up until the belly bears; 2 s charge tracking where the target will be, 500 dissolve damage + a huge blast
	  * every hit banks spite; hurt below half health with enough spite it RAGES and bombards whoever hurt it
	Credit for the original design: Hunter's Glee by StrawWagen.
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base      = "snpc_gunship"
ENT.PrintName = "HGlee Gunship"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.SpawnHealth  = 1000
ENT.HealthPerPlayer = 200
ENT.StandOff     = 3150
ENT.DuelRadius   = 3150
ENT.CarrotDist   = 1600
ENT.CarrotInterval = 1.2
ENT.MaxSpeed     = 1100

if PhysSNPC_ModInstalled and PhysSNPC_ModInstalled("glee") then
	list.Set("MachineMayhem", "snpc_hglee_gunship", {
		Name = "HGlee Gunship", Class = "snpc_hglee_gunship", Group = "Bosses",
		Category = "Machine Mayhem", SubCategory = "Normal", Offset = 96,
	})
end

if CLIENT then return end

-- tuning (Glee's gunship configs), tables indexed by health third: 1 is nearly dead, 3 is full health
local Cfg = {
	bombEvery = { 6, 18, 30 }, ammo = { 6, 4, 4 }, pairGap = { 1.2, 3.4, 5.5 }, inPairGap = { 0.6, 0.9, 1.25 },
	side = 100, forward = 200, leadSpeed = 1000, blindSpread = 150, bombRadiusMul = 1.25,
	cannonCooldown = { 10, 20, 30 }, setupTimeout = 6, blindFire = 5, backSpeed = 150, aimCone = 55, minDist = 800,
	maxDist = 3500, desperate = 1 / 3, landTol = 400, backRoom = 1800, prefire = 2, turnRate = 30, maxLead = 6,
	hitDamage = 500, hitForce = 50000, blasts = { 455, 227 }, recoil = 400,
	attackSpite = 200, perMissile = 100, perCannon = 500, rageBelow = 0.5, rageAt = 1000, rageUntil = 300,
	maxPerHit = 100, hitCooldown = 0.25, startFloor = 0.4, minLife = 45, taper = 0.3,
}

local function GB(name) return scripted_ents.Get("snpc_gunship")[name] end

local function Seg(self) return math.Clamp(math.ceil(self:Health() / self:GetMaxHealth() * 3), 1, 3) end

local function Attach(self, name)
	local id = self:LookupAttachment(name)
	local att = id and id > 0 and self:GetAttachment(id)
	if att then return att.Pos end
	return self:LocalToWorld(Vector(0, 0, self:OBBMins().z))
end

local function Sees(a, b) return util.TraceLine({ start = a, endpos = b, mask = MASK_SOLID_BRUSHONLY }).Fraction >= 0.99 end

function ENT:OnScannerSpawned()
	GB("OnScannerSpawned")(self)
	local hp = self.SpawnHealth + self.HealthPerPlayer * #player.GetAll()
	self:SetMaxHealth(hp) self:SetHealth(hp)
	self.NextBelly = math.huge
	self.StandOff = self.DuelRadius
	self.G = { mode = "duel", ammo = 0, nextMissile = 0, nextBomb = CurTime() + Cfg.bombEvery[3], spite = 0, grudges = {},
		lastSeg = 3, nextCannon = 0, hitUntil = 0 }
end

--=========================================================================
-- Damage: bullets do nothing, everything else is capped, with a health floor
--=========================================================================
function ENT:ModifyDamage(dmg)
	local g = self.G
	if dmg:GetAttacker() == self or self.Crashing or not g then dmg:SetDamage(0) return end
	local raw = dmg:GetDamage()
	if raw <= 0 or bit.band(dmg:GetDamageType(), bit.bor(DMG_BURN, DMG_SLOWBURN)) ~= 0 then dmg:SetDamage(0) return end
	-- every hit banks spite, only players earn a grudge
	g.spite = g.spite + raw
	local att = dmg:GetAttacker()
	if IsValid(att) and att:IsPlayer() then g.grudges[att] = (g.grudges[att] or 0) + raw end
	local now = CurTime()
	g.firstHit = g.firstHit or now
	if dmg:IsBulletDamage() then
		if math.random(0, 2) == 0 then
			local p, d = dmg:GetDamagePosition(), dmg:GetDamageForce():GetNormalized()
			local ed = EffectData()
			ed:SetStart(p) ed:SetOrigin(p - d * 1024 + VectorRand() * 300) ed:SetScale(3500)
			util.Effect("Tracer", ed)
		end
		dmg:SetDamage(0)
		return
	end
	if now < g.hitUntil then dmg:SetDamage(0) return end
	g.hitUntil = now + Cfg.hitCooldown
	g.firstHit = g.firstHit or now
	local d = math.min(raw, Cfg.maxPerHit)
	local mx = self:GetMaxHealth()
	local floor = mx * Cfg.startFloor * math.max(0, 1 - (now - g.firstHit) / Cfg.minLife)
	local allowed = self:Health() - floor
	if allowed <= 1 then d = 0
	else
		local band = floor * Cfg.taper
		if band > 0 and allowed < band then d = math.max(d * allowed / band, math.min(d, allowed) * 0.25) end
		d = math.min(d, allowed)
	end
	dmg:SetDamage(d)
	local dir = dmg:GetDamageForce()
	dir = dir:LengthSqr() > 0 and dir:GetNormalized() or VectorRand()
	if now >= (self.NextPain or 0) then
		self.NextPain = now + 1.2
		self:EmitSound("NPC_CombineGunship.Pain", 90, 100, 1, CHAN_VOICE)
	end
	self.CurVel = self.CurVel + dir * 200
	self:DumpMetal(dir)
end

--=========================================================================
-- Missiles (Hunter's Glee's own glee_gunshipmissile)
--=========================================================================
function ENT:StartBomb(seg)
	local g = self.G
	g.mode = "bomb"
	g.ammo = Cfg.ammo[seg]
	g.nextMissile = CurTime() + Cfg.pairGap[seg] * 0.5
	self.StandOff = self.DuelRadius * Cfg.bombRadiusMul
	self:EmitSound("npc/combine_gunship/attack_start2.wav", 150, 60, 1, CHAN_STATIC)
end

function ENT:EndAttack()
	local g = self.G
	if g.mode == "bomb" or g.mode == "rage" then
		self:EmitSound("npc/combine_gunship/attack_stop2.wav", 150, 60, 1, CHAN_STATIC)
	end
	g.mode = "duel"
	g.nextBomb = CurTime() + Cfg.bombEvery[Seg(self)]
	self.StandOff = self.DuelRadius
end

function ENT:FireMissiles(seg, tgt, dist, canSee)
	local g = self.G
	local now = CurTime()
	if g.ammo <= 0 or now < g.nextMissile then return end
	local side = g.ammo % 2 == 1 and 1 or -1
	local sp = self:GetPos() + self:GetRight() * Cfg.side * side + self:GetForward() * Cfg.forward
	local sight = g.sight
	local last = sight and sight.pos or tgt:WorldSpaceCenter()
	local aim
	if canSee then
		aim = last + tgt:GetVelocity() * math.max(dist / Cfg.leadSpeed, 1)
	else
		local spread = Cfg.blindSpread * (sight and sight.missilesSince or 0)
		aim = last + Angle(0, math.Rand(0, 360), 0):Forward() * spread * math.sqrt(math.Rand(0, 1))
	end
	if not util.IsInWorld(sp) or not Sees(sp, aim) then return end
	local dir = (aim - sp):GetNormalized()
	local m = ents.Create("glee_gunshipmissile")
	if not IsValid(m) then return end
	m:SetPos(sp) m:SetAngles(dir:Angle()) m:SetOwner(self) m:Spawn()
	self:EmitSound("weapons/mortar/mortar_fire1.wav", 95, 100, 1, CHAN_STATIC)
	self:EmitSound("weapons/mortar/mortar_fire1.wav", 140, 80, 0.5, CHAN_STATIC)
	local ed = EffectData()
	ed:SetOrigin(sp) ed:SetAngles((-dir):Angle()) ed:SetScale(10)
	util.Effect("MuzzleEffect", ed, true, true)
	g.ammo = g.ammo - 1
	g.spite = math.max(g.spite - Cfg.perMissile, 0)
	if sight then sight.missilesSince = sight.missilesSince + 1 end
	g.nextMissile = now + (g.ammo % 2 == 1 and Cfg.inPairGap[seg] or Cfg.pairGap[seg])
end

--=========================================================================
-- Belly cannon (strider warp cannon shot)
--=========================================================================
local function BellyDir(self) return -self:GetUp() end

local function ClampToCone(self, dir)
	local bd = BellyDir(self)
	local along = bd:Dot(dir)
	local cone = math.rad(Cfg.aimCone)
	if along >= math.cos(cone) then return dir end
	local across = dir - bd * along
	if across:LengthSqr() < 0.0001 then across = self:GetForward() end
	across:Normalize()
	return bd * math.cos(cone) + across * math.sin(cone)
end

local function ShotTrace(self, aimPos)
	local bp = Attach(self, "BellyGun")
	local dir = ClampToCone(self, (aimPos - bp):GetNormalized())
	return util.TraceHull({ start = bp, endpos = bp + dir * 40000, filter = self, mask = MASK_SHOT, mins = Vector(-20, -20, -20), maxs = Vector(20, 20, 20) })
end

local function Desperate(self) return self:Health() <= self:GetMaxHealth() * Cfg.desperate end

local function Away(self, pos)
	local a = self:GetPos() - pos
	a.z = 0
	a:Normalize()
	return a
end

local function DirectlyBelow(self, aimPos)
	local to = (aimPos - Attach(self, "BellyGun")):GetNormalized()
	return to:Dot(Vector(0, 0, -1)) >= math.cos(math.rad(Cfg.aimCone))
end

local function RoomToBackOff(self, aimPos)
	local pos = self:GetPos()
	local back = pos + Away(self, aimPos) * Cfg.backRoom
	local t = util.TraceHull({ start = pos, endpos = back, filter = self, mask = MASK_NPCSOLID_BRUSHONLY, mins = Vector(-120, -120, -120), maxs = Vector(120, 120, 120) })
	if t.Hit then return false end
	local s = util.TraceLine({ start = back + (Attach(self, "BellyGun") - pos), endpos = aimPos, mask = MASK_SHOT, filter = self })
	return s.HitPos:Distance(aimPos) < Cfg.landTol
end

function ENT:PlanCannon(tgt, canSee)
	local g = self.G
	if CurTime() < g.nextCannon or not IsValid(tgt) then return end
	local s = g.sight
	if not s or s.target ~= tgt then return end
	local aimPos = s.pos
	local bp = Attach(self, "BellyGun")
	if not Desperate(self) and bp:Distance(aimPos) > Cfg.maxDist then return end
	if bp:Distance(aimPos) < Cfg.minDist then return end
	if DirectlyBelow(self, aimPos) then return "overhead" end
	if canSee and RoomToBackOff(self, aimPos) then return "backoff" end
end

-- Hunter's Glee's own cannon entity (glee_gunshipbellybeam) does the charge, the tracking and the shot. It reads a few helpers
-- off terminator_Extras.glee_Gunship, so make sure they exist (and route its recoil call to us)
local function EnsureGleeHelpers()
	terminator_Extras = terminator_Extras or {}
	local te = terminator_Extras
	te.glee_Gunship = te.glee_Gunship or {}
	local gs = te.glee_Gunship
	gs.BellyCannonCfg = gs.BellyCannonCfg or {
		prefireTime = 2, turnRate = 30, maxLead = 6, hitDamage = 500, hitForce = 50000, blastMagnitudes = { 455, 227 },
	}
	gs.BellyPos = gs.BellyPos or function(npc) return npc:LocalToWorld(Vector(0, 0, npc:OBBMins().z)) end
	gs.BellyDir = gs.BellyDir or function(npc) return -npc:GetUp() end
	gs.BellyShotTrace = gs.BellyShotTrace or function(npc, aimPos, filter)
		local bp = gs.BellyPos(npc)
		local dir = ClampToCone(npc, (aimPos - bp):GetNormalized())
		return util.TraceHull({ start = bp, endpos = bp + dir * 40000, filter = filter or npc, mask = MASK_SHOT, mins = Vector(-20, -20, -20), maxs = Vector(20, 20, 20) })
	end
	if not gs.PhysSNPCRecoil then
		gs.PhysSNPCRecoil = true
		local orig = gs.BellyCannonRecoil
		gs.BellyCannonRecoil = function(npc, dir)
			if IsValid(npc) and npc.GleeBellyRecoil then return npc:GleeBellyRecoil(dir) end
			if orig then return orig(npc, dir) end
		end
	end
	te.PosCanSee = te.PosCanSee or function(a, b, mask) return util.TraceLine({ start = a, endpos = b, mask = mask or MASK_SOLID_BRUSHONLY }).Fraction >= 0.99 end
	te.recipFilterAllTargetablePlayers = te.recipFilterAllTargetablePlayers or function()
		local f = RecipientFilter()
		f:AddAllPlayers()
		return f
	end
end
EnsureGleeHelpers()

function ENT:GleeBellyRecoil(dir)
	self.CurVel = self.CurVel - dir * Cfg.recoil
end

function ENT:StartCannon(tgt, plan)
	local g = self.G
	EnsureGleeHelpers()
	-- the cannon is there from the moment it is decided, glowing small under the belly as a warning
	local cannon = ents.Create("glee_gunshipbellybeam")
	if not IsValid(cannon) then return end
	cannon:SetOwner(self)
	cannon:SetPos(Attach(self, "BellyGun"))
	cannon:SetParent(self)
	cannon.target = tgt
	cannon:Spawn()
	g.mode = "cannon"
	g.cn = { target = tgt, plan = plan, cannon = cannon, giveUp = CurTime() + Cfg.setupTimeout }
	self:EmitSound("npc/combine_gunship/see_enemy.wav", 140, 60, 1.2, CHAN_STATIC)
end

function ENT:CannonDone(fired)
	local g = self.G
	if g.cn then
		if IsValid(g.cn.cannon) and not g.cn.cannon:GetFired() then g.cn.cannon:Remove() end
		if fired then g.spite = math.max(g.spite - Cfg.perCannon, 0) end
	end
	g.cn = nil
	g.nextCannon = CurTime() + Cfg.cannonCooldown[Seg(self)]
	self:EndAttack()
	g.nextBomb = CurTime() + Cfg.bombEvery[Seg(self)]
	g.ammo = 0
end

function ENT:CannonThink(now, foe)
	local g, c = self.G, self.G.cn
	local tgt, cannon = c.target, c.cannon
	if not IsValid(cannon) then self:CannonDone(false) return end
	if c.charging then
		-- the shot is the cannon's; free to move on once it has landed
		if cannon:GetFired() then self:CannonDone(true) end
		return
	end
	if not IsValid(tgt) or tgt:Health() <= 0 then self:CannonDone(false) return end
	local bp = Attach(self, "BellyGun")
	local s = g.sight
	if now > c.giveUp or not s or s.target ~= tgt then self:CannonDone(false) return end
	if c.plan == "backoff" and now - s.time > Cfg.blindFire then self:CannonDone(false) return end
	if not Desperate(self) and bp:Distance(s.pos) > Cfg.maxDist * 1.1 then self:CannonDone(false) return end
	if bp:Distance(s.pos) < Cfg.minDist then return end
	local inPos = c.plan == "overhead" and DirectlyBelow(self, s.pos)
		or (c.plan == "backoff" and (self.CurVel:Dot(self:GetForward()) < -Cfg.backSpeed or DirectlyBelow(self, s.pos)))
	if not inPos then return end
	local off = math.deg(math.acos(math.Clamp(BellyDir(self):Dot((s.pos - bp):GetNormalized()), -1, 1)))
	if off <= Cfg.aimCone and ShotTrace(self, s.pos).HitPos:Distance(s.pos) < Cfg.landTol then
		c.charging = true
		cannon:StartCharge(s.pos)
		self:EmitSound("ambient/materials/metal_stress1.wav", 100, 60, 1, CHAN_STATIC)
		self:EmitSound("npc/combine_gunship/gunship_pain.wav", 120, 100, 1, CHAN_STATIC)
	end
end

-- flying while it lines up / charges
function ENT:CannonMove(dt, foe)
	local c = self.G.cn
	local pos = self:GetPos()
	local s = self.G.sight
	local sp = s and s.pos or foe:WorldSpaceCenter()
	if c.plan == "overhead" or c.charging then
		self:FlyTo(dt, Vector(sp.x, sp.y, pos.z), c.charging and 0.15 or 0.9, c.charging)
	else
		local carrot = pos + Away(self, sp) * 1600
		carrot.z = math.max(pos.z, sp.z + self.StandHeight)
		self:FlyTo(dt, self:SteerAround(carrot, foe), 1)
		self.BankTarget = Vector(-32, 0, self.BankTarget and self.BankTarget.z or 0) -- nose up: the belly comes to bear
	end
end

function ENT:CombatMove(dt, foe)
	local g = self.G
	if g and g.cn then return self:CannonMove(dt, foe) end
	GB("CombatMove")(self, dt, foe)
end

--=========================================================================
-- Brain
--=========================================================================
local function CanRageAt(e) return IsValid(e) and e:Health() > 0 and (not e:IsPlayer() or e:Alive()) end

function ENT:PickGrudge()
	local g = self.G
	local tot, cand = 0, {}
	for ply, gr in pairs(g.grudges) do
		if not IsValid(ply) then g.grudges[ply] = nil
		elseif CanRageAt(ply) then
			local w = gr
			if not Sees(self:GetPos(), ply:WorldSpaceCenter()) then w = w * 0.2 end
			tot = tot + w
			cand[#cand + 1] = { ply, w }
		end
	end
	if tot <= 0 then return end
	local r = math.Rand(0, tot)
	for _, c in ipairs(cand) do
		r = r - c[2]
		if r <= 0 then return c[1] end
	end
	return cand[#cand][1]
end

function ENT:OnScannerThink(dt)
	local g = self.G
	local now = CurTime()
	if not g or self.Held or self.Crashing then return GB("OnScannerThink")(self, dt) end
	local foe = self:GetFoe()
	local seg = Seg(self)

	-- rage
	if g.raging then
		if g.spite < Cfg.rageUntil then g.raging = false end
	elseif g.spite >= Cfg.rageAt and self:Health() < self:GetMaxHealth() * Cfg.rageBelow then
		g.raging = true
	end
	g.rageTarget = nil
	if g.raging then
		if not CanRageAt(g.rageTarget0) or now >= (g.nextReroll or 0) then
			g.rageTarget0 = self:PickGrudge()
			g.nextReroll = now + 1.8
		end
		g.rageTarget = g.rageTarget0
	end
	local tgt = (g.cn and g.cn.target) or g.rageTarget or foe
	if not IsValid(tgt) then
		if g.cn then self:CannonDone(false) end
		if g.mode ~= "duel" then self:EndAttack() end
		return GB("OnScannerThink")(self, dt)
	end
	local c = tgt:WorldSpaceCenter()
	local canSee = Sees(self:GetPos(), c)
	if canSee then g.sight = { target = tgt, pos = c, time = now, missilesSince = (g.sight and g.sight.target == tgt) and g.sight.missilesSince or 0 }
	elseif g.sight and g.sight.target ~= tgt then g.sight = nil end
	local dist = self:GetPos():Distance2D(tgt:GetPos())
	local dropped = seg < g.lastSeg
	g.lastSeg = seg

	if g.mode == "duel" then
		if g.rageTarget then
			g.mode = "rage"
			self:StartBomb(seg)
			g.mode = "rage"
		elseif g.spite >= Cfg.attackSpite or dropped or now >= g.nextBomb then
			local plan = self:PlanCannon(tgt, canSee)
			if plan then self:StartCannon(tgt, plan) else self:StartBomb(seg) end
		end
	elseif g.mode == "bomb" then
		if g.ammo <= 0 then self:EndAttack()
		else
			local plan = self:PlanCannon(tgt, canSee)
			if plan then self:StartCannon(tgt, plan)
			else self:FireMissiles(seg, tgt, dist, canSee) end
		end
	elseif g.mode == "rage" then
		if not g.rageTarget then self:EndAttack()
		else
			g.ammo = math.max(g.ammo, 2)
			if g.spite >= Cfg.perCannon then
				local plan = self:PlanCannon(tgt, canSee)
				if plan then self:StartCannon(tgt, plan) end
			end
			if g.mode == "rage" then self:FireMissiles(1, tgt, dist, canSee) end
		end
	end

	if g.mode == "cannon" then
		self.NextAttack = now + 0.5
		self:CannonThink(now, foe)
	end
	GB("OnScannerThink")(self, dt)
	if g.mode == "cannon" then self:AbortBurst() end
end

function ENT:StartDying(dmg)
	self:SetNWFloat("GsChargeStart", 0)
	if self.G then self.G.cn = nil end
	GB("StartDying")(self, dmg)
end
