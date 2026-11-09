--[[-------------------------------------------------------------------------
	Gunship tracer: a recreation of FX_GunshipTracer (fx.cpp) - a 128-256 unit long streak of "effects/gunshiptracer"
	that flies from the muzzle to the impact point at the given speed (default 8000 u/s), 5 units wide, with the
	"Bullets.GunshipNearmiss" whiz when it passes close to the viewer.
	data: Start = muzzle, Origin = impact, Scale = speed, Flags & 1 = whiz
---------------------------------------------------------------------------]]
local mat = Material("effects/gunshiptracer")

function EFFECT:Init(data)
	self.Start = data:GetStart()
	local endPos = data:GetOrigin()
	local dir = endPos - self.Start
	self.Dist = dir:Length()
	if self.Dist <= 256 then self.Dead = true return end -- (the original skips short tracers)
	self.Dir = dir / self.Dist
	self.Speed = data:GetScale() > 0 and data:GetScale() or 8000
	self.Length = math.Rand(128, 256)
	self.Width = 5
	self.Born = CurTime()
	self.Life = (self.Dist + self.Length) / self.Speed
	self:SetRenderBoundsWS(self.Start, endPos, Vector(64, 64, 64))

	if bit.band(data:GetFlags(), 1) == 1 then
		local ply = LocalPlayer()
		if IsValid(ply) then
			local p = ply:EyePos()
			local along = math.Clamp((p - self.Start):Dot(self.Dir), 0, self.Dist)
			local closest = self.Start + self.Dir * along
			if closest:DistToSqr(p) < 256 * 256 then
				timer.Simple(along / self.Speed, function() sound.Play("Bullets.GunshipNearmiss", closest) end)
			end
		end
	end
end

function EFFECT:Think()
	if self.Dead then return false end
	return CurTime() - self.Born < self.Life
end

function EFFECT:Render()
	if self.Dead then return end
	local head = math.Clamp((CurTime() - self.Born) * self.Speed, 0, self.Dist)
	local tail = math.Clamp(head - self.Length, 0, self.Dist)
	if head <= tail then return end
	render.SetMaterial(mat)
	render.DrawBeam(self.Start + self.Dir * tail, self.Start + self.Dir * head, self.Width, 0, 1, color_white)
end
