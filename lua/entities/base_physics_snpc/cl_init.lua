include("shared.lua")

function ENT:Draw()
	self:DrawModel()
end

-- Client-side corpse (what regular NPCs leave behind): the server tells us right before it removes the SNPC.
net.Receive("PhysSNPC_Corpse", function()
	local ent  = net.ReadEntity()
	local vel  = net.ReadVector()
	local ang  = net.ReadVector()
	local life = net.ReadFloat()
	if not IsValid(ent) then return end

	-- wait a moment so the entity's latest bodygroups / pose have arrived before we copy it
	timer.Simple(0.1, function()
		if not IsValid(ent) then return end
		local rag = ent:BecomeRagdollOnClient()
		if not IsValid(rag) then return end

		for i = 0, rag:GetPhysicsObjectCount() - 1 do
			local p = rag:GetPhysicsObjectNum(i)
			if IsValid(p) then
				p:SetVelocity(vel)          -- keeps the speed and direction it died with
				p:SetAngleVelocity(ang)     -- and its spin
			end
		end
		timer.Simple(life, function() if IsValid(rag) then rag:Remove() end end)
	end)
end)


--=========================================================================
-- Debug: physsnpc_debug_hull 1 draws boxes around every physics SNPC
--   yellow  = PhysBox (the box the entity file asks for, rotates with the entity)
--   cyan    = the engine's collision bounds (OBBMins / OBBMaxs, rotate with the entity)
--   magenta = the hull the AI / traces use (axis-aligned in the world)
--   green   = the physics object's own bounding box
--   white   = the model's render bounds
--=========================================================================
local cvDebugHull = CreateClientConVar("physsnpc_debug_hull", "0", false, false, "Draw the hull / collision boxes of physics SNPCs")

hook.Add("PostDrawTranslucentRenderables", "PhysSNPC_DebugHull", function(depth, sky)
	if depth or sky or not cvDebugHull:GetBool() then return end
	for _, e in ipairs(ents.GetAll()) do
		if IsValid(e) and e.IsPhysicsSNPC and not e:IsDormant() then
			local pos, ang = e:GetPos(), e:GetAngles()
			if e.PhysBox then render.DrawWireframeBox(pos, ang, e.PhysBox[1], e.PhysBox[2], Color(255, 230, 0), true) end
			local omn, omx = e:OBBMins(), e:OBBMaxs()
			render.DrawWireframeBox(pos, ang, omn, omx, Color(0, 220, 255), true)
			local hmn, hmx = e:GetNWVector("PhysHullMins", vector_origin), e:GetNWVector("PhysHullMaxs", vector_origin)
			render.DrawWireframeBox(pos, angle_zero, hmn, hmx, Color(255, 0, 255), true)
			local phys = e:GetPhysicsObject()
			if IsValid(phys) then
				local pmn, pmx = phys:GetAABB()
				if pmn then render.DrawWireframeBox(pos, ang, pmn, pmx, Color(0, 255, 0), true) end
			end
			local rmn, rmx = e:GetRenderBounds()
			render.DrawWireframeBox(pos, ang, rmn, rmx, Color(255, 255, 255), true)
		end
	end
end)

hook.Add("HUDPaint", "PhysSNPC_DebugHullText", function()
	if not cvDebugHull:GetBool() then return end
	local e = LocalPlayer():GetEyeTrace().Entity
	local x, y = ScrW() * 0.6, ScrH() * 0.35
	local function L(txt, col) draw.SimpleTextOutlined(txt, "DermaDefault", x, y, col or color_white, 0, 0, 1, color_black) y = y + 14 end
	L("physsnpc_debug_hull   yellow = PhysBox   cyan = engine collision bounds   magenta = AI hull   green = physics AABB   white = render bounds")
	if IsValid(e) and e.IsPhysicsSNPC then
		local omn, omx = e:OBBMins(), e:OBBMaxs()
		L(e:GetClass())
		L("PhysBox: " .. (e.PhysBox and (tostring(e.PhysBox[1]) .. " .. " .. tostring(e.PhysBox[2])) or "none"), Color(255, 230, 0))
		L("OBB:     " .. tostring(omn) .. " .. " .. tostring(omx), Color(0, 220, 255))
		L("Hull:    " .. tostring(e:GetNWVector("PhysHullMins")) .. " .. " .. tostring(e:GetNWVector("PhysHullMaxs")), Color(255, 0, 255))
		L("(console: physsnpc_hull_dump prints the server's values)")
	end
end)
