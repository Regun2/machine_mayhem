--[[-------------------------------------------------------------------------
	Gunship muzzle flash: a recreation of MuzzleFlash_Gunship (fx_impact / fx.cpp) - one "effects/gunshipmuzzle" sprite
	(random roll, 0.05-0.1 s) at the "muzzle" attachment, plus the warm elight (255,192,64, radius 128-256, exponent 6).
	data: Entity + Attachment
---------------------------------------------------------------------------]]
local mat = Material("effects/gunshipmuzzle")

function EFFECT:Init(data)
	self.Ent = data:GetEntity()
	self.Att = data:GetAttachment()
	self.Pos = data:GetOrigin()
	self.Scale = math.Rand(2.5, 4.5)
	self.Size = math.Rand(6, 8) * 10 / 7 * self.Scale
	self.Roll = math.Rand(0, 360)
	self.Born = CurTime()
	self.Life = math.Rand(0.05, 0.1)
	self.Index = IsValid(self.Ent) and self.Ent:EntIndex() or 0
	self:SetRenderBoundsWS(self.Pos - Vector(128, 128, 128), self.Pos + Vector(128, 128, 128))
	self:Place()

	local d = DynamicLight(self.Index + 4096)
	if d then
		d.pos = self.Pos
		d.r, d.g, d.b = 255, 192, 64
		d.brightness = 2
		d.size = math.Rand(128, 256)
		d.decay = 2000
		d.dietime = CurTime() + 0.1
	end
end

function EFFECT:Place()
	if IsValid(self.Ent) and self.Att and self.Att > 0 then
		local a = self.Ent:GetAttachment(self.Att)
		if a then
			self.Pos = a.Pos + a.Ang:Forward() * 2 * self.Scale
			return
		end
	end
end

function EFFECT:Think()
	return CurTime() - self.Born < self.Life
end

function EFFECT:Render()
	self:Place()
	local fade = 1 - (CurTime() - self.Born) / self.Life * 0.5 -- alpha 255 -> 128
	local view = EyePos() - self.Pos
	render.SetMaterial(mat)
	render.DrawQuadEasy(self.Pos, view:GetNormalized(), self.Size * 2, self.Size * 2, Color(255, 255, 255, 255 * fade), self.Roll)
end
