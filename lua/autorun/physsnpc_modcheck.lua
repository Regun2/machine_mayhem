-- Which workshop mods are installed (the mod-based variants only show up when their source mod is there).
-- PhysSNPC_ModInstalled("glee") / ("mapsweepers")
local checks = {
	glee = { wsid = "2848253104", files = { "lua/glee_flight/gunship/sv_gunship.lua", "lua/entities/glee_gunshipmissile/shared.lua" } },
	mapsweepers = { wsid = "3523033966", files = { "gamemodes/mapsweepers/gamemode/npcs/types/combine.lua", "gamemodes/mapsweepers/mapsweepers.txt" } },
}
local cache = {}

function PhysSNPC_ModInstalled(name)
	if cache[name] ~= nil then return cache[name] end
	local c = checks[name]
	local found = false
	if c then
		for _, f in ipairs(c.files) do
			if file.Exists(f, "GAME") then found = true break end
		end
		if not found and engine and engine.GetAddons then
			for _, a in ipairs(engine.GetAddons()) do
				if tostring(a.wsid) == c.wsid and a.mounted then found = true break end
			end
		end
	end
	cache[name] = found
	return found
end
