-- Example variant: tougher, harder-hitting, orange eye. Only changes fields.
-- Deliberately has NO list.Set("NPC", ...): it only shows up in the Entities tab (Spawnable = true).
AddCSLuaFile()
ENT.Base      = "snpc_manhack"
ENT.PrintName = "Example Manhack"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = true

ENT.SpawnHealth = 80
ENT.BladeDamage = 40
ENT.MaxSpeed    = 600
ENT.EyeColor    = Color(255, 160, 0)
ENT.EyeColors   = { Light = Color(0, 120, 255) } -- each eye can have its own colour (by attachment)
