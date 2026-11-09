--[[-------------------------------------------------------------------------
	Deathray - sandbox version of Map Sweepers' "jcms_deathray" (the Strafer gunship's orbital beam), no gamemode needed.
	A beam straight down from its position: charges for BeamPrepTime, burns for BeamLifeTime. Hurts every valid target
	of its owner along the beam (a wide box) and around the impact; hotter targets get dissolved-style blasts.
---------------------------------------------------------------------------]]
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Deathray"
ENT.Category = "Machine Mayhem"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

ENT.DPS = 120
ENT.DPS_DIRECT = 120
ENT.IgniteOnHit = true

-- the beam must deal this much in one chunk to hurt these (big targets are not shredded by a trickle)
local minThreshold = { npc_strider = 100, npc_combinegunship = 75, npc_helicopter = 150 }
local dmgMul = { npc_helicopter = 4.5 }

function ENT:SetupDataTables()
	self:NetworkVar("Float", 0, "BeamTime")
	self:NetworkVar("Float", 1, "BeamRadius")
	self:NetworkVar("Vector", 1, "BeamColour")
	self:NetworkVar("Float", 2, "BeamLifeTime")
	self:NetworkVar("Float", 3, "BeamPrepTime")
	if SERVER then
		self:SetBeamRadius(32)
		self:SetBeamLifeTime(15)
		self:SetBeamPrepTime(2)
		self:SetBeamColour(Vector(1, 0, 0))
	end
end

function ENT:GetBeamTrace()
	local pos = self:GetPos()
	local tr = util.TraceLine({ start = pos, endpos = Vector(pos.x, pos.y, pos.z - 32768), mask = MASK_SOLID_BRUSHONLY, filter = self })
	self.tr = tr
	return tr
end

function ENT:Initialize()
	if SERVER then
		self:SetModel("models/props_junk/PopCan01a.mdl")
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_NONE)
		self.Beamed = {}
	else
		self.SndBeam = CreateSound(self, "ambient/levels/citadel/zapper_loop1.wav")
		self.SndBeam:SetSoundLevel(140)
	end
	self:DrawShadow(false)
end

if SERVER then
	-- who the beam may hurt: whatever the owner is hostile to (or anything, with no owner), never the owner itself
	function ENT:ShouldHurt(e)
		local owner = self.RayOwner
		if e == self or e == owner then return false end
		if not IsValid(e) or e:GetMaxHealth() <= 0 and not (e:IsNPC() or e:IsPlayer()) then return false end
		if IsValid(owner) then
			if owner.IsValidTarget then return owner:IsValidTarget(e) or (not (e:IsNPC() or e:IsPlayer() or e:IsNextBot()) and e:GetMaxHealth() > 0) end
			return e:IsNPC() or e:IsPlayer()
		end
		return true
	end

	function ENT:Think()
		local iv = 1 / 20
		self:SetBeamTime(self:GetBeamTime() + iv)
		local t, prep, life = self:GetBeamTime(), self:GetBeamPrepTime(), self:GetBeamLifeTime()
		if IsValid(self.RayOwner) then
			if not self.RayParented then self:SetPos(self.RayOwner:GetBeamAnchor()) end
		elseif self.RayOwner ~= nil then
			self:Remove() return
		end
		if t >= prep and t <= life + prep then
			local tr = self:GetBeamTrace()
			local rad = self:GetBeamRadius()
			local attacker = IsValid(self.RayOwner) and self.RayOwner or self
			local dmg = DamageInfo()
			dmg:SetDamage(self.DPS * iv)
			dmg:SetAttacker(attacker)
			dmg:SetInflictor(self)
			dmg:SetReportedPosition(self:GetPos())
			dmg:SetDamageForce(vector_origin)
			dmg:SetDamageType(bit.bor(DMG_BLAST, DMG_DISSOLVE, DMG_DIRECT))
			sound.EmitHint(SOUND_DANGER, tr.HitPos, 300, 0.25)

			local targets = ents.FindAlongRay(tr.StartPos, tr.HitPos, Vector(-rad * 1.4, -rad * 1.4, -8), Vector(rad * 1.4, rad * 1.4, 8))
			local base = self.DPS_DIRECT
			local col = self:GetBeamColour() * 255
			for _, e in ipairs(targets) do
				if IsValid(e) and self:ShouldHurt(e) then
					local class = e:GetClass()
					local threshold = minThreshold[class] or 15
					dmg:SetDamagePosition(e:WorldSpaceCenter())
					e.PhysSNPCBeamSum = (e.PhysSNPCBeamSum or 0) + dmg:GetDamage() * (dmgMul[class] or 1)
					if e.PhysSNPCBeamSum >= threshold then
						e.PhysSNPCBeamSum = e.PhysSNPCBeamSum - threshold
						dmg:SetDamage(threshold)
						e:TakeDamageInfo(dmg)
						dmg:SetDamage(base * iv)
						local ed = EffectData()
						ed:SetOrigin(e:WorldSpaceCenter()) ed:SetScale(1) ed:SetMagnitude(1) ed:SetRadius(threshold / 10 + 72)
						util.Effect("ElectricSpark", ed)
						e:EmitSound("ambient/levels/citadel/weapon_disintegrate" .. math.random(3, 4) .. ".wav", 100, 90)
						if self.IgniteOnHit and (e:IsNPC() or e:IsPlayer()) then e:Ignite(math.ceil(threshold / 5)) end
					end
				end
			end
		elseif t > life + prep then
			self:Remove() return
		end
		self:NextThink(CurTime() + iv)
		return true
	end
else
	local matInner = Material("sprites/physbeam")
	local matOuter = Material("trails/plasma")
	local matLight = Material("effects/lamp_beam.vmt")
	local matGlow  = Material("particle/Particle_Glow_04")

	local function Wm(t, dur)
		local x = math.Clamp(math.min(t / 0.5, (dur - t) / 0.5), 0, 1)
		return x * x * (3 - 2 * x)
	end

	function ENT:DrawTranslucent()
		local t, prep, life = self:GetBeamTime(), self:GetBeamPrepTime(), self:GetBeamLifeTime()
		local cv = self:GetBeamColour()
		local col = Color(cv.x * 255, cv.y * 255, cv.z * 255)
		local tr = self:GetBeamTrace() -- (every frame: a cached trace trails behind a fast mover)
		local a = tr.StartPos
		render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
		if t <= prep then
			local f = (t / prep) ^ 2
			render.SetMaterial(matInner)
			render.DrawBeam(a, tr.HitPos, math.Rand(6, 8) * f, 0, 1, col)
			render.SetMaterial(matLight)
			render.DrawBeam(a, tr.HitPos, 32 * f * f, 0, 1, col)
		elseif t <= life + prep then
			local wm = Wm(t - prep, life)
			local rad = self:GetBeamRadius()
			local scroll = -t
			local len = tr.HitPos:Distance(a) / (rad * 10)
			local bright = Color((col.r + 255) / 2, (col.g + 255) / 2, (col.b + 255) / 2)
			render.SetMaterial(matOuter)
			render.DrawBeam(a, tr.HitPos, math.Rand(5, 10) * rad * wm, scroll * len, (scroll + 1) * len, col)
			render.SetMaterial(matInner)
			render.DrawBeam(a, tr.HitPos, math.Rand(3, 8) * rad * wm, scroll * len, (scroll + 1) * len, bright)
			render.SetMaterial(matGlow)
			local hp = tr.HitPos + tr.HitNormal
			render.DrawQuadEasy(hp, tr.HitNormal, math.Rand(8, 13) * rad * wm, math.random(3, 4) * rad * wm, bright, 360 * math.random())
			render.DrawSprite(hp, math.random(10, 18) * rad * wm, math.random(12, 18) * math.sqrt(rad) * wm, col)
			render.DrawQuadEasy(a, tr.Normal, math.random(6, 14) * rad * wm, math.random(6, 14) * rad * wm, bright, wm * 360)
			render.SetMaterial(matLight)
			render.DrawBeam(a, tr.HitPos, math.Rand(15, 18) * rad * wm, 0, 1, col)
		end
		render.OverrideBlend(false)
	end

	function ENT:Think()
		local tr = self:GetBeamTrace()
		self:SetBeamTime(self:GetBeamTime() + FrameTime())
		self:SetRenderBoundsWS(tr.StartPos, tr.HitPos, Vector(256, 256, 256))
		local t, prep, life = self:GetBeamTime(), self:GetBeamPrepTime(), self:GetBeamLifeTime()
		if t > prep and t <= life + prep then
			if not self.Played then
				self.Played = true
				self:EmitSound("beams/beamstart5.wav", 100, 88)
				self.SndBeam:Play()
			end
			local rad = self:GetBeamRadius()
			util.ScreenShake(tr.HitPos, rad / 6, rad, 0.1, rad * 6, true)
		elseif t <= prep and t > prep - 0.5 and not self.PlayedPre then
			self.PlayedPre = true
			self:EmitSound("ambient/levels/citadel/portal_beam_shoot6.wav", 140, 100)
		end
		self:SetNextClientThink(CurTime() + 1 / 66)
		return true
	end

	function ENT:OnRemove()
		if self.SndBeam then self.SndBeam:Stop() end
	end
end
