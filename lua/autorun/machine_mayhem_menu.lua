--[[-------------------------------------------------------------------------
	Machine Mayhem - own spawnmenu tab
	Every Machine Mayhem NPC registers itself with  list.Set("MachineMayhem", class, { Name, Class, Offset, ... })
	and shows up here, grouped (Manhacks / City Scanners / Rollermines / Turrets / Bosses) and split into
	Normal / Hacked. Optional fields of an entry:  Group = "..."  (overrides the automatic group),
	Icon = "materials/path.png",  Info = "tooltip".   The example manhack stays in the Entities tab.
---------------------------------------------------------------------------]]

local GROUPS = { "Bosses", "Manhacks", "City Scanners", "Rollermines", "Turrets" }
local GROUP_COLOR = {
	["Bosses"] = Color(200, 60, 60), ["Manhacks"] = Color(70, 140, 220), ["City Scanners"] = Color(90, 190, 190),
	["Rollermines"] = Color(230, 170, 50), ["Turrets"] = Color(140, 140, 160),
}
local GROUP_ICON = {
	["Bosses"] = "entities/npc_manhack.png", ["Manhacks"] = "entities/npc_manhack.png",
	["City Scanners"] = "entities/npc_cscanner.png", ["Rollermines"] = "entities/npc_rollermine.png",
	["Turrets"] = "entities/npc_turret_floor.png",
}

local function GroupOf(class, v)
	if v.Group then return v.Group end
	if class:find("codered", 1, true) or class:find("jumbo", 1, true) then return "Bosses" end
	if class:find("turret", 1, true) then return "Turrets" end
	if class:find("rollermine", 1, true) then return "Rollermines" end
	if class:find("scanner", 1, true) or class:find("battledrone", 1, true) then return "City Scanners" end
	return "Manhacks"
end

local function SubOf(class)
	local ent = scripted_ents.Get(class)
	if ent and ent.SubCategory and ent.SubCategory ~= "" then return ent.SubCategory end
	return (ent and ent.Hacked) and "Hacked" or "Normal"
end

-- the NPCs also live in the normal NPCs tab (and the Creator tool): register them in both realms
hook.Add("InitPostEntity", "MachineMayhem_NPCList", function()
	local added = false
	for class, v in pairs(list.Get("MachineMayhem")) do
		if not list.Get("NPC")[class] then
			local t = table.Copy(v)
			t.Category = "Machine Mayhem"
			list.Set("NPC", class, t)
			added = true
		end
	end
	if added and CLIENT then timer.Simple(1, function() RunConsoleCommand("spawnmenu_reload") end) end
end)

--=========================================================================
-- SERVER: spawning
--=========================================================================
if SERVER then

	-- (the NPC list registration is shared: see below)

	-- debugging aid for relationships with other NPC packs (VJ Base...): aim at an NPC and run mm_class
	concommand.Add("mm_class", function(ply)
		if not IsValid(ply) then return end
		local e = ply:GetEyeTrace().Entity
		if not IsValid(e) then ply:PrintMessage(HUD_PRINTCONSOLE, "[Machine Mayhem] aim at an NPC first\n") return end
		local vj = istable(e.VJ_NPC_Class) and table.concat(e.VJ_NPC_Class, ", ") or tostring(e.VJ_NPC_Class)
		ply:PrintMessage(HUD_PRINTCONSOLE, string.format("[Machine Mayhem] %s  Classify=%s  VJ_NPC_Class={%s}  IsVJ=%s\n",
			e:GetClass(), tostring(e.Classify and e:Classify()), vj, tostring(e.IsVJBaseSNPC)))
	end)

	concommand.Add("mm_spawn", function(ply, _, args)
		if not IsValid(ply) then return end
		local class = args[1]
		local v = class and list.Get("MachineMayhem")[class]
		if not v then return end
		if not ply:CheckLimit("npcs") then return end
		if hook.Run("PlayerSpawnNPC", ply, class, "") == false then return end

		local tr = util.TraceLine({
			start = ply:GetShootPos(), endpos = ply:GetShootPos() + ply:GetAimVector() * 4096,
			filter = ply, mask = MASK_SOLID,
		})
		local ent = ents.Create(v.Class or class)
		if not IsValid(ent) then return end
		local off = v.Offset or 32
		ent:SetPos(tr.HitPos + tr.HitNormal * off)
		local ang = Angle(0, ply:EyeAngles().y + 180, 0)
		ent:SetAngles(ang)
		ent:Spawn()
		ent:Activate()
		if ent.SetCreator then ent:SetCreator(ply) end
		ply:AddCount("npcs", ent)
		ply:AddCleanup("npcs", ent)
		undo.Create("NPC")
			undo.SetPlayer(ply)
			undo.AddEntity(ent)
			undo.SetCustomUndoText("Undone " .. (v.Name or class))
		undo.Finish("NPC (" .. (v.Name or class) .. ")")
		hook.Run("PlayerSpawnedNPC", ply, ent)
	end)
	return
end

--=========================================================================
-- CLIENT: the tab
--=========================================================================
spawnmenu.AddContentType("machinemayhem", function(container, obj)
	local icon = vgui.Create("ContentIcon", container)
	icon:SetContentType("machinemayhem")
	icon:SetSpawnName(obj.spawnname)
	icon:SetName(obj.nicename)
	icon:SetMaterial(obj.material)
	icon:SetColor(obj.color or Color(70, 140, 220))
	if obj.info then icon:SetTooltip(obj.info) end
	icon.DoClick = function()
		RunConsoleCommand("mm_spawn", obj.spawnname)
		surface.PlaySound("ui/buttonclickrelease.wav")
	end
	icon.OpenMenu = function(self)
		local m = DermaMenu()
		m:AddOption("Copy to Clipboard", function() SetClipboardText(obj.spawnname) end):SetIcon("icon16/page_copy.png")
		m:AddOption("Spawn using Toolgun", function()
			RunConsoleCommand("gmod_tool", "creator")
			RunConsoleCommand("creator_type", "2")
			RunConsoleCommand("creator_name", obj.spawnname)
		end):SetIcon("icon16/brick_add.png")
		m:AddSpacer()
		m:AddOption("Delete", function()
			if IsValid(self) then self:Remove() end
			hook.Run("SpawnlistContentChanged", self)
		end):SetIcon("icon16/bin_closed.png")
		m:Open()
	end
	return icon
end)

-- a panel that lays its children out in rows and grows to fit them
local GRID = {}
function GRID:Init() self.Gap = 6 end
function GRID:PerformLayout(w)
	local x, y, rowH = 0, 0, 0
	for _, c in ipairs(self:GetChildren()) do
		if c:IsVisible() then
			local cw, ch = c:GetSize()
			if x > 0 and x + cw > w then x, y, rowH = 0, y + rowH + self.Gap, 0 end
			c:SetPos(x, y)
			x = x + cw + self.Gap
			rowH = math.max(rowH, ch)
		end
	end
	local h = y + rowH
	if self:GetTall() ~= h then self:SetTall(h) end
end
vgui.Register("MachineMayhemGrid", GRID, "Panel")

local ORDER = { ["Manhacks"] = 1, ["City Scanners"] = 2, ["Rollermines"] = 3, ["Turrets"] = 4, ["Bosses"] = 0 }

-- spawn icon: materials/entities/<class>.png (same as the NPC tab), else a stock icon of the family
local iconCache = {}
local function IconFor(class, v, group)
	if v.Icon then return v.Icon end
	if iconCache[class] == nil then
		iconCache[class] = file.Exists("materials/entities/" .. class .. ".png", "GAME")
			and ("entities/" .. class .. ".png") or false
	end
	return iconCache[class] or GROUP_ICON[group] or "entities/npc_manhack.png"
end

local function CollectItems(boss, hacked)
	local items = {}
	for class, v in pairs(list.Get("MachineMayhem")) do
		local g = GroupOf(class, v)
		if (g == "Bosses") == boss and (SubOf(v.Class or class) == "Hacked") == hacked then
			items[#items + 1] = { class = class, v = v, group = g }
		end
	end
	table.sort(items, function(a, b)
		local oa, ob = ORDER[a.group] or 9, ORDER[b.group] or 9
		if oa ~= ob then return oa < ob end
		return (a.v.Name or a.class) < (b.v.Name or b.class)
	end)
	return items
end

-- Combine look: gunmetal panels, thin cyan / amber trim, angular corners, stencil-style type
surface.CreateFont("MMHead",  { font = "Tahoma", size = 17, weight = 800, extended = true })
surface.CreateFont("MMSmall", { font = "Tahoma", size = 12, weight = 600, extended = true })
local COL_BG     = Color(13, 17, 21)
local COL_PANEL  = Color(22, 29, 35)
local COL_TRIM   = Color(50, 70, 84)
local COL_CYAN   = Color(40, 170, 255)
local COL_AMBER  = Color(255, 120, 40)
local COL_HACKED = Color(90, 235, 140)

-- a rectangle with the top-left and bottom-right corners cut off
local function Chamfer(x, y, w, h, c, col)
	surface.SetDrawColor(col)
	draw.NoTexture()
	surface.DrawPoly({
		{ x = x + c, y = y }, { x = x + w, y = y }, { x = x + w, y = y + h - c },
		{ x = x + w - c, y = y + h }, { x = x, y = y + h }, { x = x, y = y + c },
	})
end

local function Section(parent, title, tag, accent, boss)
	local hacked = cookie.GetString("mm_tab_hacked_" .. title, "0") == "1"
	local function Accent() return hacked and COL_HACKED or accent end

	local box = vgui.Create("DPanel", parent)
	box:Dock(TOP)
	box:DockMargin(6, 6, 6, 0)
	box.Paint = function(s, w, h)
		surface.SetDrawColor(COL_PANEL)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL_TRIM)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end

	local head = vgui.Create("DPanel", box)
	head:Dock(TOP)
	head:SetTall(26)
	head.Paint = function(s, w, h)
		local a = Accent()
		Chamfer(0, 0, w, h, 10, Color(a.r * 0.28, a.g * 0.28, a.b * 0.28))
		surface.SetDrawColor(a)
		surface.DrawRect(0, h - 2, w, 2)
		surface.DrawRect(0, 6, 3, h - 12)
		local label = string.upper(title) .. (hacked and "  //  HACKED" or "")
		draw.SimpleText(label, "MMHead", 14, h / 2 - 1, color_white, 0, 1)
		surface.SetFont("MMHead")
		local tw = surface.GetTextSize(label)
		draw.SimpleText(tag, "MMSmall", 14 + tw + 18, h / 2, Color(170, 190, 205), 0, 1)
	end

	local toggle = vgui.Create("DButton", head)
	toggle:Dock(RIGHT)
	toggle:DockMargin(0, 3, 6, 3)
	toggle:SetWide(76)
	toggle:SetText("")

	local grid = vgui.Create("MachineMayhemGrid", box)
	grid:Dock(TOP)
	grid:DockMargin(8, 8, 8, 8)
	grid.Gap = 4

	local function Fill()
		-- Remove() only takes effect next frame: hide the old icons right away so they do not show up (or take space) beside the new ones
		for _, c in ipairs(grid:GetChildren()) do c:SetVisible(false) c:Remove() end
		local items = CollectItems(boss, hacked)
		for _, it in ipairs(items) do
			spawnmenu.CreateContentIcon("machinemayhem", grid, {
				nicename = it.v.Name or it.class,
				spawnname = it.class,
				material = IconFor(it.class, it.v, it.group),
				color = Accent(),
				info = it.v.Info,
			})
		end
		if #items == 0 then
			local l = vgui.Create("DLabel", grid)
			l:SetFont("MMSmall")
			l:SetText("NO UNITS ON FILE")
			l:SetTextColor(Color(140, 160, 175))
			l:SizeToContents()
		end
		grid:InvalidateLayout(true)
		box:InvalidateLayout(true)
		box:SizeToChildren(false, true)
	end

	-- compact switch: shows the mode that is selected, click to flip it
	toggle.Paint = function(s, w, h)
		local a = Accent()
		local hov = s:IsHovered()
		surface.SetDrawColor(a.r * (hov and 0.5 or 0.3), a.g * (hov and 0.5 or 0.3), a.b * (hov and 0.5 or 0.3), 255)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(a)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		draw.SimpleText(hacked and "HACKED" or "NORMAL", "MMSmall", w / 2, h / 2, color_white, 1, 1)
	end
	toggle.DoClick = function()
		hacked = not hacked
		cookie.Set("mm_tab_hacked_" .. title, hacked and "1" or "0")
		surface.PlaySound("buttons/button17.wav")
		Fill()
	end

	-- the grid wraps with the panel width, so re-fit the height when the layout changes
	local oldLayout = grid.PerformLayout
	grid.PerformLayout = function(s, w, h)
		oldLayout(s, w, h)
		if IsValid(box) then box:SizeToChildren(false, true) end
	end

	Fill()
	return box
end

local function Build()
	local root = vgui.Create("DPanel")
	root.Paint = function(s, w, h)
		local t = CurTime()
		surface.SetDrawColor(COL_BG)
		surface.DrawRect(0, 0, w, h)
		-- slowly drifting grid
		local gx, gy = (t * 8) % 48, (t * 5) % 48
		surface.SetDrawColor(40, 110, 160, 14)
		for x = -48 + gx, w, 48 do surface.DrawRect(x, 0, 1, h) end
		for y = -48 + gy, h, 48 do surface.DrawRect(0, y, w, 1) end
		-- fine scan lines creeping down
		surface.SetDrawColor(255, 255, 255, 4)
		for y = (t * 20) % 4, h, 4 do surface.DrawRect(0, y, w, 1) end
		-- a soft band sweeping down the panel
		local by = ((t * 70) % (h + 240)) - 120
		for i = 0, 11 do
			surface.SetDrawColor(40, 170, 255, 3 + 2 * (6 - math.abs(i - 6)) * 0.5)
			surface.DrawRect(0, by + i * 10 - 60, w, 10)
		end
		-- slow pulse in the corners
		local pulse = 8 + 6 * math.sin(t * 1.3)
		surface.SetDrawColor(40, 170, 255, pulse)
		surface.DrawRect(0, 0, 3, h)
		surface.DrawRect(w - 3, 0, 3, h)
	end

	local scroll = vgui.Create("DScrollPanel", root)
	scroll:Dock(FILL)
	local bar = scroll:GetVBar()
	bar:SetWide(6)
	bar.Paint = function(s, w, h) surface.SetDrawColor(COL_PANEL) surface.DrawRect(0, 0, w, h) end
	bar.btnGrip.Paint = function(s, w, h) surface.SetDrawColor(COL_TRIM) surface.DrawRect(0, 0, w, h) end
	bar.btnUp.Paint, bar.btnDown.Paint = function() end, function() end

	local canvas = scroll:GetCanvas()
	local banner = vgui.Create("DPanel", canvas)
	banner:Dock(TOP)
	banner:SetTall(22)
	banner:DockMargin(6, 6, 6, 0)
	banner.Paint = function(s, w, h)
		draw.SimpleText("MACHINE MAYHEM  //  UNIT CATALOGUE", "MMHead", 2, h / 2, COL_CYAN, 0, 1)
	end

	Section(canvas, "Normal", "standard issue units", COL_CYAN, false)
	Section(canvas, "Boss", "heavy issue units", COL_AMBER, true)

	-- settings
	local box = vgui.Create("DPanel", canvas)
	box:Dock(TOP)
	box:DockMargin(6, 6, 6, 8)
	box.Paint = function(s, w, h)
		surface.SetDrawColor(COL_PANEL) surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL_TRIM) surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
	local head = vgui.Create("DPanel", box)
	head:Dock(TOP)
	head:SetTall(26)
	head.Paint = function(s, w, h)
		Chamfer(0, 0, w, h, 10, Color(30, 40, 50))
		surface.SetDrawColor(COL_TRIM)
		surface.DrawRect(0, h - 2, w, 2)
		surface.DrawRect(0, 6, 3, h - 12)
		draw.SimpleText("SETTINGS", "MMHead", 14, h / 2 - 1, color_white, 0, 1)
		draw.SimpleText("host / admin", "MMSmall", 110, h / 2, Color(170, 190, 205), 0, 1)
	end
	local body = vgui.Create("DPanel", box)
	body:Dock(TOP)
	body:DockMargin(12, 8, 12, 10)
	body.Paint = function() end

	local function Line(ctrl, h)
		ctrl:SetParent(body)
		ctrl:Dock(TOP)
		ctrl:DockMargin(0, 0, 0, 6)
		if h then ctrl:SetTall(h) end
		return ctrl
	end

	local cb = Line(vgui.Create("DCheckBoxLabel"), 18)
	cb:SetText("Replacement Mode")
	cb:SetFont("MMHead")
	cb:SetTextColor(color_white)
	cb:SetConVar("physsnpc_replace")
	cb:SizeToContents()

	local help = Line(vgui.Create("DLabel"), 44)
	help:SetFont("MMSmall")
	help:SetWrap(true)
	help:SetTextColor(Color(150, 170, 185))
	help:SetText("Replaces the map's manhacks, city scanners, rollermines and floor / ceiling turrets with the recreations (with a chance of a variant). Friendly ones only become hacked versions, hostile ones never do. Only affects NPCs created from now on.")

	local sl = Line(vgui.Create("DNumSlider"), 22)
	sl:SetText("Variant chance (%)")
	sl:SetMin(0) sl:SetMax(100) sl:SetDecimals(0)
	sl:SetConVar("physsnpc_replace_chance")
	sl.Label:SetTextColor(color_white)
	sl.Label:SetFont("MMSmall")
	sl.TextArea:SetTextColor(color_white)

	local pcb = Line(vgui.Create("DCheckBoxLabel"), 18)
	pcb:SetText("Pick variants by strength (stronger = rarer)")
	pcb:SetFont("MMSmall")
	pcb:SetTextColor(color_white)
	pcb:SetConVar("physsnpc_replace_power")
	pcb:SizeToContents()

	local bs = Line(vgui.Create("DNumSlider"), 22)
	bs:SetText("Strength bias")
	bs:SetMin(0) bs:SetMax(4) bs:SetDecimals(1)
	bs:SetConVar("physsnpc_replace_bias")
	bs.Label:SetTextColor(color_white)
	bs.Label:SetFont("MMSmall")
	bs.TextArea:SetTextColor(color_white)

	local bo = Line(vgui.Create("DNumSlider"), 22)
	bo:SetText("Boss chance (%, one per level)")
	bo:SetMin(0) bo:SetMax(100) bo:SetDecimals(2)
	bo:SetConVar("physsnpc_replace_boss")
	bo.Label:SetTextColor(color_white)
	bo.Label:SetFont("MMSmall")
	bo.TextArea:SetTextColor(color_white)

	local tcb = Line(vgui.Create("DCheckBoxLabel"), 18)
	tcb:SetText("Replace plain map turrets (never scripted ones)")
	tcb:SetFont("MMSmall")
	tcb:SetTextColor(color_white)
	tcb:SetConVar("physsnpc_replace_turrets")
	tcb:SizeToContents()

	local gcb = Line(vgui.Create("DCheckBoxLabel"), 18)
	gcb:SetText("Replace map gunships with the physics Gunship (boss)")
	gcb:SetFont("MMSmall")
	gcb:SetTextColor(color_white)
	gcb:SetConVar("physsnpc_replace_gunship")
	gcb:SizeToContents()

	local btn = Line(vgui.Create("DButton"), 24)
	btn:SetText("")
	btn.Paint = function(s, w, h)
		surface.SetDrawColor(s:IsHovered() and 36 or 22, s:IsHovered() and 60 or 40, s:IsHovered() and 80 or 54, 255)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL_CYAN)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		draw.SimpleText("REPLACE THE ONES ALREADY ON THE MAP", "MMSmall", w / 2, h / 2, color_white, 1, 1)
	end
	btn.DoClick = function() RunConsoleCommand("physsnpc_replace_now") end

	body:InvalidateLayout(true)
	body:SizeToChildren(false, true)
	box:InvalidateLayout(true)
	box:SizeToChildren(false, true)
	return root
end

spawnmenu.AddCreationTab("Machine Mayhem", Build, "icon16/cog.png", 55)


--=========================================================================
-- Utilities tab: settings + show / hide the Machine Mayhem tab
--=========================================================================
local cvHide = CreateClientConVar("physsnpc_hide_tab", "0", true, false, "Hide the Machine Mayhem spawnmenu tab")

local function ApplyTabVisibility()
	if not g_SpawnMenu or not IsValid(g_SpawnMenu.CreateMenu) then return end
	local hide = cvHide:GetBool()
	for _, it in pairs(g_SpawnMenu.CreateMenu.Items or {}) do
		if it.Name == "Machine Mayhem" and IsValid(it.Tab) then
			it.Tab:SetVisible(not hide)
			if hide and g_SpawnMenu.CreateMenu:GetActiveTab() == it.Tab then
				local first = g_SpawnMenu.CreateMenu.Items[1]
				if first and IsValid(first.Tab) then g_SpawnMenu.CreateMenu:SetActiveTab(first.Tab) end
			end
		end
	end
	g_SpawnMenu.CreateMenu:InvalidateLayout(true)
	if IsValid(g_SpawnMenu.CreateMenu.tabScroller) then g_SpawnMenu.CreateMenu.tabScroller:InvalidateLayout(true) end
end
cvars.AddChangeCallback("physsnpc_hide_tab", function() timer.Simple(0, ApplyTabVisibility) end, "MM_HideTab")
hook.Add("OnSpawnMenuOpen", "MM_HideTab", ApplyTabVisibility)
hook.Add("PostReloadToolsMenu", "MM_HideTab", function() timer.Simple(0.5, ApplyTabVisibility) end)

hook.Add("AddToolMenuCategories", "MM_UtilCat", function()
	spawnmenu.AddToolCategory("Utilities", "MachineMayhem", "Machine Mayhem")
end)
hook.Add("PopulateToolMenu", "MM_UtilSettings", function()
	spawnmenu.AddToolMenuOption("Utilities", "MachineMayhem", "mm_settings", "Settings", "", "", function(p)
		p:ClearControls()
		p:Help("Interface")
		p:CheckBox("Hide the Machine Mayhem spawnmenu tab", "physsnpc_hide_tab")
		p:Help("Replacement Mode (host / admin)")
		p:CheckBox("Replacement Mode", "physsnpc_replace")
		p:ControlHelp("Replaces the map's manhacks, city scanners, rollermines and plain floor / ceiling turrets with the recreations. Friendly ones only become hacked versions, hostile ones never do.")
		p:NumSlider("Variant chance (%)", "physsnpc_replace_chance", 0, 100, 0)
		p:CheckBox("Pick variants by strength (stronger = rarer)", "physsnpc_replace_power")
		p:NumSlider("Strength bias", "physsnpc_replace_bias", 0, 4, 1)
		p:NumSlider("Boss chance (%, max one per level)", "physsnpc_replace_boss", 0, 100, 2)
		p:CheckBox("Replace plain map turrets (never scripted ones)", "physsnpc_replace_turrets")
		p:CheckBox("Replace the map's gunships with the physics Gunship (boss)", "physsnpc_replace_gunship")
		p:Button("Replace the ones already on the map", "physsnpc_replace_now")
	end)
end)
