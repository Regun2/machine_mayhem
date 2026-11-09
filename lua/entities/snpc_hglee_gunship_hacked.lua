-- Hacked (rebel-aligned) HGlee Gunship.
AddCSLuaFile()
ENT.Base      = "snpc_hglee_gunship"
ENT.PrintName = "Hacked HGlee Gunship"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

if PhysSNPC_ModInstalled and PhysSNPC_ModInstalled("glee") then
	list.Set("MachineMayhem", "snpc_hglee_gunship_hacked", {
		Name = "Hacked HGlee Gunship", Class = "snpc_hglee_gunship_hacked", Group = "Bosses",
		Category = "Machine Mayhem", SubCategory = "Hacked", Offset = 96,
	})
end
