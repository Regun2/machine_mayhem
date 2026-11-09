--[[-------------------------------------------------------------------------
	Sandbox version of Map Sweepers' "jcms_bolt" (the Cybergunship's explosive pulse, type 4) - no gamemode needed.
	data: Start = muzzle side, Origin = impact, Scale = travel speed, Angles/Normal unused
	A bright pink-white streak races to the impact, leaving a fading beam, then a small additive blast flash.
---------------------------------------------------------------------------]]
local matSpark = Material("effects/spark")
local matCore  = Material("effects/fluttercore_gmod")
local matGlow  = Material("sprites/light_glow02_add")

EFFECT.RenderGroup = RENDERGROUP_TRANSLUCENT

function EFFECT:Init(data)
	self.Start = data:GetStart()
	self.EndPos = data:GetOrigin()
	self:SetRenderBoundsWS(self.Start, self.EndPos, Vector(96, 96, 96))
	self.T, self.TOut = 0, 0.5
	self.Length = self.Start:Distance(self.EndPos)
	self.Traveled = 0
	self.Speed = math.max(10000, self.Length / self.TOut)
	self.Color = Color(255, 255, 255, 255)
end

function EFFECT:Think()
	if self.T >= self.TOut then return false end
	local ft = FrameTime()
	self.T = math.min(self.TOut, self.T + ft)
	self.Traveled = self.Traveled + self.Speed * ft
	return true
end

function EFFECT:Render()
	local f = self.T / self.TOut
	local ff = (1 - f) ^ 4
	local c = self.Color
	c.r, c.g, c.b, c.a = 255 * (1 - f), 200 * ff, 255 * (1 - f), 255 * ff
	local width = 48

	local bulletLen = self.Length / 512
	local tx1 = math.Remap(self.Traveled, 0, self.Length, -bulletLen, 1)
	local tx2 = tx1 + bulletLen
	render.SetMaterial(matSpark)
	render.DrawBeam(self.EndPos, self.Start, width / 2, tx1, tx2, color_white)

	if not self.SparkPos then
		local n = (self.EndPos - self.Start):GetNormalized()
		n:Rotate(AngleRand(-32, 32))
		self.SparkPos = self.Start + n * math.random(64, 364)
	end
	render.DrawBeam(self.SparkPos, self.Start, width / 2, tx1, tx2, color_white)

	local ff2 = 1 - math.Clamp(self.T / 0.15, 0, 1)
	render.SetMaterial(matCore)
	render.DrawBeam(self.Start, self.EndPos, width / 2 * ff, 0, 0.8, c)
	render.DrawBeam(self.Start, self.EndPos, width * ff, ff2 - 1, ff2 + 1, c)

	-- the small blast flash at the impact
	render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
	if not self.BlastNormal then self.BlastNormal = VectorRand() end
	local size = 128
	local vn = self.BlastNormal * Lerp(ff, size / 4, size / 2)
	render.SetMaterial(matSpark)
	for i = 1, 6 do
		local v2 = VectorRand(-size / i * ff, size / i * ff) + self.EndPos
		render.DrawQuad(self.EndPos - vn, v2 - vn, self.EndPos + vn, v2 + vn, c)
	end
	render.SetMaterial(matGlow)
	render.DrawSprite(self.EndPos, size * ff, size * ff, c)
	render.OverrideBlend(false)
end
