-- Rebel-aligned (hacked) Linkhack: friendly to the player and rebels; links with other hacked linkhacks.
AddCSLuaFile()
ENT.Base      = "snpc_linkhack"
ENT.PrintName = "Hacked Linkhack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_linkhack_hacked", {
	Name = "Hacked Linkhack", Class = "snpc_linkhack_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})
