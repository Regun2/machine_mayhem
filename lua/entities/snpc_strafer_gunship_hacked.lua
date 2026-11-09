-- Hacked (rebel-aligned) Strafer Gunship.
AddCSLuaFile()
ENT.Base      = "snpc_strafer_gunship"
ENT.PrintName = "Hacked Strafer Gunship"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true
ENT.RayColour = Vector(0.4, 1, 0.6)

if PhysSNPC_ModInstalled and PhysSNPC_ModInstalled("mapsweepers") then
	list.Set("MachineMayhem", "snpc_strafer_gunship_hacked", {
		Name = "Hacked Strafer Gunship", Class = "snpc_strafer_gunship_hacked", Group = "Bosses",
		Category = "Machine Mayhem", SubCategory = "Hacked", Offset = 96,
	})
end
