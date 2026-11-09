-- Hacked (rebel-aligned) Clustermine: releases hacked assassin hacks.
AddCSLuaFile()
ENT.Base      = "snpc_rollermine_cluster"
ENT.PrintName = "Hacked Clustermine"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_rollermine_cluster_hacked", {
	Name = "Hacked Clustermine", Class = "snpc_rollermine_cluster_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 24,
})
