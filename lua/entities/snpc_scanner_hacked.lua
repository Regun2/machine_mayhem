-- Hacked (rebel-aligned) city scanner: photographs and flashes the player's enemies instead.
AddCSLuaFile()
ENT.Base      = "snpc_scanner"
ENT.PrintName = "Hacked City Scanner"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false
ENT.Hacked    = true

list.Set("MachineMayhem", "snpc_scanner_hacked", {
	Name = "Hacked City Scanner", Class = "snpc_scanner_hacked",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 64,
})
