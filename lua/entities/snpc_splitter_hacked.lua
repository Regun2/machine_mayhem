-- Rebel-aligned (hacked) version: friendly to the player and rebels, 2x engine power.
AddCSLuaFile()
ENT.Base      = "snpc_splitter"
ENT.PrintName = "Hacked Splitter"
ENT.Author    = "ANP"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_splitter_hacked", {
	Name = "Hacked Splitter", Class = "snpc_splitter_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})
