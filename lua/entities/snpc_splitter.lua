--[[-------------------------------------------------------------------------
	Splitter - ported from the ANP ("Add NPC Plus") addon's Splitter / 2001 Proto Manhack.
	This is the Combine-aligned one (the ANP "2001 Proto Manhack"); "Hacked Splitter" is the
	rebel-aligned one (the ANP "Splitter").

	Same traits as the original: 50 health that regenerates out of combat, half damage taken,
	20 damage per hit (10 held), props take 20 (1 held), cuts zombies in half, bullets do not
	knock it around, a big engine-power boost while it has an enemy, and its own sounds.

	Not ported: ANP's follow-the-player command, enemy-marking key and HUD status icon
	(those need the ANP framework).
---------------------------------------------------------------------------]]

AddCSLuaFile()

ENT.Base      = "snpc_manhack"
ENT.PrintName = "Splitter"
ENT.Author    = "ANP"
ENT.Category  = "Machine Mayhem"
ENT.Spawnable = false

-- custom model if the player has it (same bones/bodygroups as the stock manhack), else stock
ENT.Model = file.Exists("models/anp/splitter.mdl", "GAME") and "models/anp/splitter.mdl" or "models/manhack.mdl"

-- sound scripts used by the original
sound.Add({ name = "ANP.Splitter.Grab", channel = CHAN_WEAPON, volume = 1, level = 80, pitch = 100,
	sound = { "npc/splitter/engine1.wav", "npc/splitter/engine2.wav", "npc/splitter/engine3.wav", "npc/splitter/engine4.wav" } })
sound.Add({ name = "ANP.Splitter.Drop", channel = CHAN_WEAPON, volume = 1, level = 80, pitch = 100,
	sound = { "npc/splitter/engineout1.wav", "npc/splitter/engineout2.wav", "npc/splitter/engineout3.wav", "npc/splitter/engineout4.wav" } })
sound.Add({ name = "ANP.Splitter.GrabLoop", channel = CHAN_AUTO, volume = 0.7, level = 75, pitch = 90,
	sound = "npc/splitter/spinloop_medium.wav" })

-- body
ENT.SpawnHealth      = 100
ENT.DamageTakenScale = 0.5     -- "Body = -50%"
ENT.RegenAmount      = 2       -- HealthRegen = { out of combat only, every 1s, 2 hp }
ENT.RegenDelay       = 1
ENT.RegenOutOfCombat = true
ENT.KnockbackResistBullets = true
ENT.ImpactSurviveFraction  = 0.1   -- a hard wall impact leaves it at ~10% health instead of killing it (unless already that low)

-- its own gibs
ENT.GibModels = {}
for i = 1, 9 do ENT.GibModels[i] = ("models/anp/gibs/splitter_gib%02d.mdl"):format(i) end
ENT.GibCount = 9
ENT.GibDamage = 0   -- any kill gibs it

-- flight: engine power x5 in the original while fighting
ENT.CombatEnginePower = 3
ENT.MaxSpeed          = 650
ENT.BurstCooldown     = 0     -- m_flNextBurstTime is held at 0: it charges as often as it can
ENT.BurstTime         = 0.8

-- blades
ENT.BladeDamage          = 20   -- per hit
ENT.HeldBladeDamage      = 100  -- = 10 per hit while held
ENT.PropSliceDamage      = 20
ENT.HeldPropSliceDamage  = 1
ENT.CutZombies           = true

-- sounds
ENT.EngineVolume = 0.4
ENT.BladeVolume  = 0.1
ENT.Pitch1 = { min = 80, max = 128, dist = 512, water = 68 }
ENT.Pitch2 = { min = 68, max = 152, dist = 400, water = 72 }
ENT.AlertNoise = "npc/roller/mine/rmine_predetonate.wav"
ENT.LoseNoise  = "npc/scanner/cbot_servoscared.wav"
ENT.AlertPitch = 60
ENT.HitSound      = "npc/splitter/bat_away.wav"   -- instead of the manhack's damage noise
ENT.BatSound      = "npc/splitter/bat_away.wav"
ENT.HitPitch      = 80
ENT.GrabSound     = "ANP.Splitter.Grab"
ENT.DropSound     = "ANP.Splitter.Drop"
ENT.GrabLoopSound = "ANP.Splitter.GrabLoop"

list.Set("MachineMayhem", "snpc_splitter", {
	Name = "Splitter", Class = "snpc_splitter",
	Category = "Machine Mayhem", SubCategory = ENT.SubCategory or (ENT.Hacked and "Hacked" or "Normal"), Offset = 48,
})
