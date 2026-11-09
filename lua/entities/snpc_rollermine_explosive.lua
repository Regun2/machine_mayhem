--[[-------------------------------------------------------------------------
	Explosive Rollermine - a rollermine that is always flashing red (skin flicker every 0.2 s, as in the "mhl2c"
	explosive rollermine) and blows up when an enemy gets within 200 units: it hops into the air first, just
	like when it is killed. It never opens its spikes and never shocks.
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base      = "snpc_rollermine"
ENT.PrintName = "Explosive Rollermine"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.FuseDist      = 200     -- an enemy this close lights the fuse
ENT.FuseTime      = 0.4     -- delay between the hop and the explosion (PreDetonate)
ENT.FlashInterval = 0.2     -- the original's flipcolorsin
ENT.ExplodeDamage = 90
ENT.ExplodeRadius = 170

list.Set("MachineMayhem", "snpc_rollermine_explosive", {
	Name = "Explosive Rollermine", Class = "snpc_rollermine_explosive",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 16,
})

if not SERVER then return end

local function Base(name)
	local b = scripted_ents.GetStored("snpc_rollermine")
	return b and b.t and b.t[name]
end

-- red while the fuse flashes
function ENT:UpdateSkin()
	local skin = self.Hacked and 1 or 0
	if self.FlashOn or self.PoweredDown then skin = 2 end
	self:SetSkin(skin)
end

local IgnoreCV

function ENT:OnSpawned()
	self.FlashOn = false
	self.NextFlash = 0
	self.NextFuseCheck = 0
	Base("OnSpawned")(self)
end

-- never opens its spikes and never shocks: it only blows up
function ENT:OpenSpikes() end
function ENT:TryShock() end
function ENT:ProximityShock() end

function ENT:HostileNear()
	IgnoreCV = IgnoreCV or GetConVar("ai_ignoreplayers")
	for _, e in ipairs(ents.FindInSphere(self:GetPos(), self.FuseDist)) do
		if e ~= self and IsValid(e) and (e:IsPlayer() or e:IsNPC() or e:IsNextBot()) and not e:IsFlagSet(FL_NOTARGET) then
			local ok = true
			if e:IsPlayer() then ok = e:Alive() and not IgnoreCV:GetBool() end
			if ok and not e:IsPlayer() and not e:IsNextBot() then
				ok = e:Health() > 0 or e:GetClass() == "npc_rollermine"
			end
			if ok and self:GetDisposition(e) == D_HT then return e end
		end
	end
end

function ENT:OnThinkAlive(dt)
	Base("OnThinkAlive")(self, dt)
	if self.Exploding then return end
	local now = CurTime()

	-- always flashing red
	if now >= self.NextFlash then
		self.NextFlash = now + self.FlashInterval
		self.FlashOn = not self.FlashOn
		self:UpdateSkin()
	end

	if self.Held or self.Detonating then return end

	-- an enemy close by: hop up and blow, exactly like when it is killed
	if now >= self.NextFuseCheck then
		self.NextFuseCheck = now + 0.1
		if self:HostileNear() then self:PreDetonate(self.FuseTime) end
	end
end
