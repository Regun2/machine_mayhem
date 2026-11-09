--[[-------------------------------------------------------------------------
	Electrical Drone - a very tough manhack that does not hunt: it hovers near enemies instead of diving at them.
	Its blades still cut whatever they touch. A helicopter bomb (scale 0.75) is attached to its origin and a saw
	blade to its "Blade" bone (roll 90). Every so often it throws a white arc at something near it: enemies, props, allies,
	even the bare world. Anything hostile or neutral takes a bit of damage; allies are zapped but never hurt.
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base      = "snpc_manhack"
ENT.PrintName = "Electrical Drone"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.SpawnHealth = 300

ENT.BombModel  = "models/Combine_Helicopter/helicopter_bomb01.mdl"
ENT.BombScale  = 0.75
ENT.SawModel   = "models/props_junk/sawblade001a.mdl"
ENT.HoverNear  = 150       -- backs off when closer
ENT.HoverFar   = 260       -- closes in when farther

ENT.ArcRange    = 260
ENT.ArcDamage   = 8
ENT.ArcMin, ENT.ArcMax = 0.5, 1.4   -- seconds between arcs
-- idle arcs: much smaller and much more frequent
ENT.IdleRange  = 85
ENT.IdleDamage = 2
ENT.IdleMin, ENT.IdleMax = 0.08, 0.3

list.Set("MachineMayhem", "snpc_electrical_drone", {
	Name = "Electrical Drone", Class = "snpc_electrical_drone",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})

--=========================================================================
-- CLIENT: the white arcs
--=========================================================================
if CLIENT then
	local function AddFrom(vmt, id)
		local src = Material(vmt)
		local tex = src and src:GetTexture("$basetexture")
		return CreateMaterial(id, "UnlitGeneric", {
			["$basetexture"] = tex and tex:GetName() or vmt,
			["$additive"] = 1, ["$vertexcolor"] = 1, ["$vertexalpha"] = 1, ["$nocull"] = 1,
		})
	end
	local beam = AddFrom("sprites/lgtning", "pm_edrone_arc_a")
	local glow = AddFrom("sprites/light_glow02", "pm_edrone_glow_a")
	local Arcs = {}

	net.Receive("PhysEDrone_Arc", function()
		Arcs[#Arcs + 1] = { a = net.ReadVector(), b = net.ReadVector(), k = net.ReadFloat(), die = CurTime() + 0.18 }
	end)

	hook.Add("PostDrawTranslucentRenderables", "PhysEDroneArcs", function(depth, sky)
		if sky or #Arcs == 0 then return end
		local now = CurTime()
		for i = #Arcs, 1, -1 do
			local a = Arcs[i]
			if now > a.die then
				table.remove(Arcs, i)
			else
				local f = (a.die - now) / 0.18
				local segs = a.k < 1 and 4 or 7
				local len = a.a:Distance(a.b)
				render.SetMaterial(beam)
				for pass = 1, 2 do
					render.StartBeam(segs + 1)
					for s = 0, segs do
						local t = s / segs
						local p = LerpVector(t, a.a, a.b)
						if s > 0 and s < segs then p = p + VectorRand() * math.min(len * 0.08, 12) end
						render.AddBeam(p, ((pass == 1 and 7 or 3) * f + 1) * a.k, t, Color(255, 255, 255, 255 * f))
					end
					render.EndBeam()
				end
				render.SetMaterial(glow)
				render.DrawSprite(a.b, 40 * f * a.k, 40 * f * a.k, Color(255, 255, 255, 220 * f))
				render.DrawSprite(a.a, 24 * f * a.k, 24 * f * a.k, Color(255, 255, 255, 200 * f))
			end
		end
	end)
end

if not SERVER then return end

util.AddNetworkString("PhysEDrone_Arc")

local function Attach(self, model, scale)
	local p = ents.Create("prop_dynamic")
	if not IsValid(p) then return end
	p:SetModel(model)
	p:SetPos(self:GetPos())
	p:SetAngles(self:GetAngles())
	p:Spawn()
	if scale then p:SetModelScale(scale, 0) end
	p:SetSolid(SOLID_NONE)
	p:SetMoveType(MOVETYPE_NONE)
	return p
end

function ENT:OnVariantSpawned()
	-- helicopter bomb on the origin
	local bomb = Attach(self, self.BombModel, self.BombScale)
	if IsValid(bomb) then
		bomb:SetParent(self)
		bomb:SetLocalPos(Vector(0, 0, 0))
		bomb:SetLocalAngles(Angle(0, 0, 0))
		self.Bomb = bomb
	end

	-- saw blade on the "Blade" bone (not Blade1 / Blade2 ...)
	local boneIdx
	for i = 0, (self:GetBoneCount() or 0) - 1 do
		local n = string.lower(self:GetBoneName(i) or "")
		if string.find(n, "blade$") then boneIdx = i break end
	end
	if not boneIdx then
		for i = 0, (self:GetBoneCount() or 0) - 1 do
			if string.find(string.lower(self:GetBoneName(i) or ""), "blade", 1, true) then boneIdx = i break end
		end
	end
	local saw = Attach(self, self.SawModel)
	if IsValid(saw) then
		saw:SetParent(self)
		if boneIdx then saw:FollowBone(self, boneIdx) end
		saw:SetLocalPos(Vector(0, 0, 0))
		saw:SetLocalAngles(Angle(0, 0, 90))
		self.Saw = saw
	end

	self.NextArc = CurTime() + math.Rand(self.ArcMin, self.ArcMax)
	self.NextIdle = CurTime() + math.Rand(self.IdleMin, self.IdleMax)
end

-- it does not hunt: it hangs around its target at a distance instead of diving in
function ENT:CombatMove(dt, enemy, chase)
	local pos = self:GetPos()
	if not (IsValid(enemy) and self.FoeVisible) then
		self:MoveToTarget(dt, self:SteerAround(chase, enemy))
		return
	end
	local fc = enemy:WorldSpaceCenter()
	local flat = fc - pos
	flat.z = 0
	local d = flat:Length()
	local dir = d > 1 and flat / d or self:GetForward()
	local goal = pos
	if d > self.HoverFar then goal = pos + dir * 200 elseif d < self.HoverNear then goal = pos - dir * 160 end
	goal = Vector(goal.x, goal.y, fc.z + 30)
	self:MoveToTarget(dt, self:SteerAround(goal, enemy))
end

-- Arcs go to anything: enemies, allies, props, and the bare world. Returns an entity or nil, and the hit position.
function ENT:PickArcTarget(range)
	range = range or self.ArcRange
	local center = self:WorldSpaceCenter()
	local list = {}
	for _, e in ipairs(ents.FindInSphere(center, range)) do
		if e ~= self and e ~= self.Bomb and e ~= self.Saw and IsValid(e) and e:GetSolid() ~= SOLID_NONE
			and not e:IsWeapon() and e:GetParent() ~= self then
			list[#list + 1] = e
		end
	end
	if #list > 0 and math.random() < 0.6 then
		local e = list[math.random(#list)]
		return e, e:WorldSpaceCenter()
	end
	-- the world: a random direction, wherever it hits within range
	local dir = VectorRand():GetNormalized()
	local tr = util.TraceLine({ start = center, endpos = center + dir * range, filter = { self, self.Bomb, self.Saw }, mask = MASK_SOLID })
	if tr.Hit then return (IsValid(tr.Entity) and not tr.Entity:IsWorld()) and tr.Entity or nil, tr.HitPos end
	return nil, nil
end

-- one arc: range, damage, visual scale
function ENT:Zap(range, damage, k)
	local t, to = self:PickArcTarget(range)
	if not to then return end
	local from = self:WorldSpaceCenter()
	if util.TraceLine({ start = from, endpos = to, filter = { self, t, self.Bomb, self.Saw }, mask = MASK_SOLID_BRUSHONLY }).Fraction < 0.97 then return end

	-- everything gets zapped, but nothing that is on our side takes damage
	local allied = IsValid(t) and (t:IsNPC() or t:IsPlayer() or t:IsNextBot()) and self:IsFriendlyTo(t)
	if IsValid(t) and not allied then
		local d = DamageInfo()
		d:SetAttacker(self) d:SetInflictor(self)
		d:SetDamage(damage)
		d:SetDamageType(DMG_SHOCK)
		d:SetDamagePosition(to)
		d:SetDamageForce((to - from):GetNormalized() * 300 * k)
		t:TakeDamageInfo(d)
	end

	net.Start("PhysEDrone_Arc")
	net.WriteVector(from)
	net.WriteVector(to)
	net.WriteFloat(k)
	net.SendPVS(from)
	local ed = EffectData()
	ed:SetOrigin(to) ed:SetMagnitude(k) ed:SetScale(k) ed:SetRadius(k)
	util.Effect("ElectricSpark", ed)
	self:EmitSound("ambient/energy/spark" .. math.random(1, 6) .. ".wav", 70 * (k < 1 and 0.85 or 1), math.random(95, 125), k < 1 and 0.4 or 0.8)
end

function ENT:OnVariantThink(dt)
	local now = CurTime()
	if self.Packed or self.Held or self.Crashing then return end
	if now >= self.NextArc then
		self.NextArc = now + math.Rand(self.ArcMin, self.ArcMax)
		self:Zap(self.ArcRange, self.ArcDamage, 1)
	end
	if now >= self.NextIdle then
		self.NextIdle = now + math.Rand(self.IdleMin, self.IdleMax)
		self:Zap(self.IdleRange, self.IdleDamage, 0.45)
	end
end

function ENT:OnVariantDeath()
	if IsValid(self.Bomb) then self.Bomb:Remove() end
	if IsValid(self.Saw) then self.Saw:Remove() end
end
