-- Rebel-aligned (hacked) Jumbo Manhack: friendly to the player and rebels, launches hacked assassin / ranger manhacks.
AddCSLuaFile()
ENT.Base      = "snpc_jumbo_manhack"
ENT.PrintName = "Hacked Jumbo Manhack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true
ENT.EyeLightColor = Color(70, 255, 110)
ENT.EyeMaterial   = "models/bomb/bomb_green"

list.Set("MachineMayhem", "snpc_jumbo_manhack_hacked", {
	Name = "Hacked Jumbo Manhack", Class = "snpc_jumbo_manhack_hacked", Group = "Bosses",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 70,
})
