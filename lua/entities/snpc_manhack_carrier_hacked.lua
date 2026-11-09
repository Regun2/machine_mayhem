-- Rebel-aligned (hacked) carrier: friendly to the player and rebels, launches hacked manhacks.
AddCSLuaFile()
ENT.Base      = "snpc_manhack_carrier"
ENT.PrintName = "Hacked Manhack Carrier"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_manhack_carrier_hacked", {
	Name = "Hacked Manhack Carrier", Class = "snpc_manhack_carrier_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 64,
})
