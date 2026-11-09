-- Rebel-aligned (hacked) Shadowhack: friendly to the player and rebels; its clones are hacked too.
AddCSLuaFile()
ENT.Base      = "snpc_shadowhack"
ENT.PrintName = "Hacked Shadowhack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_shadowhack_hacked", {
	Name = "Hacked Shadowhack", Class = "snpc_shadowhack_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})
