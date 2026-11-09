-- Rebel-aligned (hacked) Codered-Hack: friendly to the player and rebels, green bottom light.
AddCSLuaFile()
ENT.Base      = "snpc_codered_hack"
ENT.PrintName = "Hacked Codered-Hack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true
ENT.IdleColor = Color(0, 255, 90)
ENT.EngagedColor = Color(255, 235, 0)

list.Set("MachineMayhem", "snpc_codered_hack_hacked", {
	Name = "Hacked Codered-Hack", Class = "snpc_codered_hack_hacked", Group = "Bosses",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 64,
})
