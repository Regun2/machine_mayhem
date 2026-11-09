--[[-------------------------------------------------------------------------
	Assassinhack - a dark, much faster and much more fragile manhack. It leaves a trail behind each
	eye glow (the colour of that eye: red by default) and has a slimmer, modified body.
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Base      = "snpc_manhack"
ENT.PrintName = "Assassinhack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.ModelColor = Color(45, 45, 52)    -- darker coloring

-- fragile and fast
ENT.SpawnHealth    = 15
ENT.MaxSpeed       = 1000
ENT.FarMaxSpeed    = 1500
ENT.BurstMaxSpeed  = 1500
ENT.PuntedMaxSpeed = 1200
ENT.MaxVertSpeed   = 700
ENT.AccelAligned   = 800
ENT.AccelTurning   = 550
ENT.AccelVertical  = 550
ENT.BurstAccel     = 1500
ENT.MotorAccel     = 5500
ENT.LungeSpeed     = 500
ENT.ChargeMinDist  = 280
ENT.BurstTime      = 0.7
ENT.BurstCooldown  = 1.4
ENT.BladeDamage    = 25

-- eye trails
ENT.TrailLifetime = 0.55
ENT.TrailWidth    = 10
ENT.TrailTexture  = "trails/physbeam.vmt"
ENT.TrailColor    = nil               -- nil = same colour as the eye (red; green when hacked)

-- bone scaling of the slimmed body
ENT.BoneScales = {
	["Manhack.MH_ControlPincerTop"]    = 0,
	["Manhack.MH_ControlPincerBottom"] = 0,
	["Manhack.MH_ControlPanel4"]       = 0,
	["Manhack.MH_ControlPanel5"]       = 0,
	["Manhack.MH_ControlCamera"]       = 1.5,
}

list.Set("MachineMayhem", "snpc_assassinhack", {
	Name = "Assassinhack", Class = "snpc_assassinhack",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})

if not SERVER then return end

function ENT:OnVariantSpawned()
	for name, scale in pairs(self.BoneScales) do
		local bone = self:LookupBone(name)
		if bone and bone >= 0 then self:ManipulateBoneScale(bone, Vector(scale, scale, scale)) end
	end
	self:CreateTrails()
end

function ENT:CreateTrails()
	self:RemoveTrails()
	self.Trails = {}
	for _, att in ipairs(self.EyeAttachments) do
		local id = self:LookupAttachment(att)
		if id and id > 0 then
			local c = self.TrailColor or self:GetEyeColor(att)
			local t = util.SpriteTrail(self, id, Color(c.r, c.g, c.b, 255), true,
				self.TrailWidth, 0, self.TrailLifetime, 1 / (self.TrailWidth * 0.5), self.TrailTexture)
			if IsValid(t) then self.Trails[#self.Trails + 1] = t end
		end
	end
end

function ENT:RemoveTrails()
	for _, t in ipairs(self.Trails or {}) do
		if IsValid(t) then t:Remove() end
	end
	self.Trails = nil
end

function ENT:OnVariantDeath() self:RemoveTrails() end
