--[[-------------------------------------------------------------------------
	Clustermine - a rollermine with a helicopter bomb (scale 0.8, metalset texture) as its body. It rolls at its
	target and, when it gets close (or is destroyed), bursts into bomb debris and 3-4 assassin hacks
	(hacked assassin hacks if it is the hacked version). It never opens its spikes or shocks.
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base      = "snpc_rollermine"
ENT.PrintName = "Clustermine"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.BombModel   = "models/Combine_Helicopter/helicopter_bomb01.mdl"
ENT.BombScale   = 0.8
ENT.BombMaterial = "phoenix_storms/metalset_1-2"
ENT.DebrisModels = { "models/combine_helicopter/bomb_debris_1.mdl", "models/combine_helicopter/bomb_debris_2.mdl", "models/combine_helicopter/bomb_debris_3.mdl" }
ENT.CarrierClass = "snpc_assassinhack"
ENT.HackedCarrierClass = "snpc_assassinhack_hacked"
ENT.PayloadMin, ENT.PayloadMax = 3, 4
ENT.BurstDist   = 170

ENT.PhysSphereRadius = 13
ENT.GroundRadius = 13
ENT.HullSize     = 13

list.Set("MachineMayhem", "snpc_rollermine_cluster", {
	Name = "Clustermine", Class = "snpc_rollermine_cluster",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 24,
})

if not SERVER then return end

local cache
local function Parent(name)
	cache = cache or scripted_ents.Get("snpc_rollermine")
	return cache and cache[name]
end

function ENT:OnSpawned()
	Parent("OnSpawned")(self)
	self:SetNoDraw(true) -- the bomb is the visible body
	local b = ents.Create("prop_dynamic")
	if IsValid(b) then
		b:SetModel(self.BombModel)
		b:SetPos(self:GetPos())
		b:SetAngles(self:GetAngles())
		b:Spawn()
		b:SetModelScale(self.BombScale, 0)
		b:SetMaterial(self.BombMaterial)
		b:SetSolid(SOLID_NONE)
		b:SetMoveType(MOVETYPE_NONE)
		b:SetParent(self)
		b:SetLocalPos(Vector(0, 0, 0))
		b:SetLocalAngles(Angle(0, 0, 0))
		self.Bomb = b
	end
end

-- no spikes, no shocks
function ENT:OpenSpikes() end
function ENT:CloseSpikes() end
function ENT:TryShock() end
function ENT:ProximityShock() end
function ENT:ShockTarget(ent)
	if IsValid(ent) and self:GetDisposition(ent) == D_HT then self:ClusterBurst(ent) end
end

function ENT:ClusterBurst(foe)
	if self.Clustered then return end
	self.Clustered = true
	local pos = self:GetPos()
	local vel = Vector()
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then vel = phys:GetVelocity() end

	-- debris: two of each, with the bomb's texture
	for _, m in ipairs(self.DebrisModels) do
		for _ = 1, 2 do
			local g = ents.Create("prop_physics")
			if IsValid(g) then
				g:SetModel(m)
				g:SetPos(pos + VectorRand() * 8)
				g:SetAngles(AngleRand())
				g:Spawn()
				g:SetMaterial(self.BombMaterial)
				g:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
				local gp = g:GetPhysicsObject()
				if IsValid(gp) then
					gp:Wake()
					gp:SetVelocity(vel * 0.4 + VectorRand():GetNormalized() * math.Rand(200, 500) + Vector(0, 0, 120))
					gp:AddAngleVelocity(VectorRand() * 500)
				end
				SafeRemoveEntityDelayed(g, 10 + math.Rand(-2, 2))
			end
		end
	end

	-- the payload
	local class = self.Hacked and self.HackedCarrierClass or self.CarrierClass
	for i = 1, math.random(self.PayloadMin, self.PayloadMax) do
		local m = ents.Create(class)
		if IsValid(m) then
			m:SetPos(pos + VectorRand() * 10 + Vector(0, 0, 8))
			m:SetAngles(Angle(0, math.Rand(0, 360), 0))
			m:Spawn()
			m:Activate()
			local mp = m:GetPhysicsObject()
			if IsValid(mp) then mp:SetVelocity(VectorRand():GetNormalized() * 250 + Vector(0, 0, 150)) end
			if IsValid(foe) and m.AcquireTarget and m:IsValidTarget(foe) then m:AcquireTarget(foe) end
		end
	end

	local ed = EffectData()
	ed:SetOrigin(pos) ed:SetScale(1) ed:SetMagnitude(2) ed:SetRadius(3) ed:SetNormal(Vector(0, 0, 1))
	util.Effect("ManhackSparks", ed)
	for _ = 1, 4 do
		local e2 = EffectData()
		e2:SetOrigin(pos + VectorRand() * 10) e2:SetMagnitude(3) e2:SetScale(2) e2:SetRadius(3)
		util.Effect("ElectricSpark", e2)
	end
	self:EmitSound("physics/metal/metal_box_break" .. math.random(1, 2) .. ".wav", 80, 100)
	self:EmitSound("ambient/energy/zap9.wav", 75, 90)

	self.Exploding = true
	if IsValid(self.Bomb) then self.Bomb:Remove() end
	self:Remove()
end

-- killed / blown up / drowned: it still bursts
function ENT:Explode()
	self:ClusterBurst(self:GetFoe())
end

function ENT:OnThinkAlive(dt)
	Parent("OnThinkAlive")(self, dt)
	if self.Clustered or self.Held then return end
	local foe = self:GetFoe()
	if IsValid(foe) and self.FoeVisible and self:GetPos():Distance(foe:GetPos()) < self.BurstDist then
		self:ClusterBurst(foe)
	end
end
