--[[-------------------------------------------------------------------------
	Codered-Hack - boss manhack, converted from the ZBase NPC of the same name.
	  * 2.5 x the size, 1000 health, very heavy (cannot be picked up or punted with the gravity gun), triple engine power
	  * takes 0.65 x bullet / club damage, crush / fall / vehicle damage is quartered and capped at 15, nothing shoves it
	  * "super-hack" body texture (models/janhack/manhack_sheet) when that material is installed, else a red tint
	  * while it has a target it keeps slashing: anything hostile within 100 units takes 240 slash damage every 0.25 s
	  * lights: top is always cyan; bottom is cyan at rest, red while it has a target, orange for 0.4 s after being hurt
	  * explodes when it is destroyed
---------------------------------------------------------------------------]]
AddCSLuaFile()
ENT.Base      = "snpc_manhack"
ENT.PrintName = "Codered-Hack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

ENT.IsBoss       = true          -- bosses never swarm, and nothing swarms with them
ENT.SwarmEnabled = false
ENT.ModelScale   = 2.5
ENT.SpawnHealth  = 1000
ENT.HullSize     = 16
ENT.PhysSphereRadius = 14       -- the model is scaled up but its physics are not: a sphere of the right size
ENT.PhysMass     = 200
ENT.AllowGravGun = false
ENT.EnginePower  = 3
ENT.HackedEnginePower = 3
ENT.MaxSpeed     = 380
ENT.PuntedMaxSpeed = 380
ENT.GibDamage    = 0
ENT.EyeScale     = 0.55
ENT.EyeAttachments = { "Eye", "Light" }   -- "Light" = top light, "Eye" = bottom light
ENT.KnockbackResistBullets = true
ENT.EngineVolume = 0.9
ENT.Pitch1 = { min = 60, max = 110, dist = 600, water = 55 }
ENT.Pitch2 = { min = 55, max = 120, dist = 500, water = 55 }

ENT.SuperSheet     = "models/janhack/manhack_sheet"
ENT.SlashRange     = 100
ENT.SlashDamage    = 240
ENT.SlashInterval  = 0.25
ENT.BulletTaken    = 0.65
ENT.CrushTaken     = 0.25
ENT.CrushCap       = 15

ENT.TopColor     = Color(0, 127, 255)
ENT.IdleColor    = Color(0, 127, 255)
ENT.EngagedColor = Color(255, 0, 0)
ENT.HurtColor    = Color(255, 175, 0)

list.Set("MachineMayhem", "snpc_codered_hack", {
	Name = "Codered-Hack", Class = "snpc_codered_hack", Group = "Bosses",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 64,
})

if not SERVER then return end

local ManhackBase
local function MB() ManhackBase = ManhackBase or scripted_ents.GetStored("snpc_manhack").t return ManhackBase end

function ENT:GetEyeColor(att)
	if att == "Light" then return self.TopColor end
	if CurTime() < (self.HurtFlashUntil or 0) then return self.HurtColor end
	if IsValid(self:GetFoe()) then return self.EngagedColor end
	return self.IdleColor
end

function ENT:OnVariantSpawned()
	self.HurtFlashUntil, self.NextSlash, self.NextLightUpdate = 0, 0, 0
	-- super-hack texture on the body (not blades / blur / wings)
	if file.Exists("materials/" .. self.SuperSheet .. ".vmt", "GAME") then
		for i, mat in ipairs(self:GetMaterials() or {}) do
			local low = string.lower(mat or "")
			if low:find("blade", 1, true) or low:find("blur", 1, true) or low:find("wing", 1, true) then
				self:SetSubMaterial(i - 1, "")
			elseif low:find("manhack", 1, true) or low:find("sheet", 1, true) then
				self:SetSubMaterial(i - 1, self.SuperSheet)
			end
		end
	else
		self:SetColor(Color(255, 110, 110))
	end
end

function ENT:OnVariantThink(dt)
	local now = CurTime()
	if now >= self.NextLightUpdate then
		self.NextLightUpdate = now + 0.15
		self:ApplySpriteColor()
	end
	if self.Held or self.Crashing or self.Packed or now < self.NextSlash then return end
	local foe = self:GetFoe()
	if not IsValid(foe) then return end
	-- slashes everything hostile within reach, not only its target
	local hit = false
	local me = self:WorldSpaceCenter()
	for _, e in ipairs(ents.FindInSphere(me, self.SlashRange * 1.6)) do
		-- centre-to-centre distance, as in the original (the sphere search alone would count a big target's whole bounding box)
		if e ~= self and IsValid(e) and me:Distance(e:WorldSpaceCenter()) <= self.SlashRange and (e == foe or ((e:IsNPC() or e:IsPlayer()) and self:GetDisposition(e) == D_HT)) then
			if not (e:IsPlayer() and not e:Alive()) then
				local d = DamageInfo()
				d:SetDamage(self.SlashDamage)
				d:SetDamageType(DMG_SLASH)
				d:SetAttacker(self)
				d:SetInflictor(self)
				d:SetDamagePosition(e:WorldSpaceCenter())
				e:TakeDamageInfo(d)
				hit = true
			end
		end
	end
	if hit then
		self.NextSlash = now + self.SlashInterval
		if not self.Silent then self:EmitSound(self.SliceSound or "NPC_Manhack.Slice") end
	end
end

function ENT:ModifyDamage(dmg)
	dmg:SetDamageForce(vector_origin)
	if dmg:IsBulletDamage() or dmg:IsDamageType(DMG_CLUB) then dmg:ScaleDamage(self.BulletTaken) end
	if dmg:IsDamageType(DMG_CRUSH) or dmg:IsDamageType(DMG_FALL) or dmg:IsDamageType(DMG_VEHICLE) then
		dmg:SetDamage(math.min(dmg:GetDamage() * self.CrushTaken, self.CrushCap))
	end
	self.HurtFlashUntil = CurTime() + 0.4
	self.NextLightUpdate = 0
	return MB().ModifyDamage(self, dmg)
end

-- blows up when it dies
function ENT:SpawnGibs(pos, baseVel)
	local ex = EffectData()
	ex:SetOrigin(pos) ex:SetScale(2) ex:SetMagnitude(2)
	util.Effect("Explosion", ex)
	sound.Play("weapons/explode" .. math.random(3, 5) .. ".wav", pos, 90, 100)
	scripted_ents.GetStored("base_physics_snpc").t.SpawnGibs(self, pos, baseVel)
end
