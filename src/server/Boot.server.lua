--!strict
--[[
	Boot.server.lua — DEADPACT's entry point.

	This is the ONLY script that starts anything. It wires the systems in
	dependency order, publishes each under the name its peers expect, then hands
	control to the round director.

	If anything throws here the console prints a single loud banner — a silent
	half-boot is worse than a visible failure.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local Runtime = require(script.Parent.Runtime)
local Net = require(script.Parent.Net)
local District = require(script.Parent.District)
local Vertical = require(script.Parent.Vertical)
local LootSystem = require(script.Parent.LootSystem)
local NoiseSystem = require(script.Parent.NoiseSystem)
local PactSystem = require(script.Parent.PactSystem)
local PactLedger = require(script.Parent.PactLedger)
local ZombieSystem = require(script.Parent.ZombieSystem)
local CombatSystem = require(script.Parent.CombatSystem)
local ExtractionSystem = require(script.Parent.ExtractionSystem)
local Survival = require(script.Parent.Survival)
local RoundSystem = require(script.Parent.RoundSystem)

local function boot(): ()
	-- 1. The spine: player state + the single Heartbeat step registry.
	Runtime.start()

	-- 2. Build the world and place the loot.
	local district = District.generate(workspace)
	-- THE ASCENT: stack the sky tiers on top of the ground city. Additive and
	-- non-destructive — if it fails the ground game still runs untouched.
	local ascentOk, ascentErr = pcall(function()
		local ascent = Vertical.generate(workspace, district.propFolder)
		district.ascent = ascent
		district.forgeCore = ascent.forgeCore
	end)
	if not ascentOk then
		warn("[DEADPACT] ascent build failed (ground city unaffected): " .. tostring(ascentErr))
	end
	LootSystem.bind(district.lootSpots, district.propFolder)
	LootSystem.populate(district.lootSpots, district.propFolder)
	ExtractionSystem.setup(district.extractions)

	-- 3. Publish services by the names their peers look up. Order here is the
	--    contract: anything calling Runtime.service(name) at boot needs it set.
	Runtime.provide("Zombies", ZombieSystem)
	Runtime.provide("Pacts", PactSystem)
	Runtime.provide("Combat", CombatSystem)
	Runtime.provide("Loot", LootSystem)
	Runtime.provide("Extraction", ExtractionSystem)
	Runtime.provide("Round", RoundSystem)
	Runtime.provide("RoundLoop", RoundSystem)
	Runtime.provide("District", district)
	Runtime.provide("Survival", Survival)

	-- 4. Start the systems. ZombieSystem/Pact need RoundLoop + Combat present,
	--    which they now are.
	NoiseSystem.start()
	CombatSystem.start()
	LootSystem.start()
	Survival.start()
	ZombieSystem.start()
	PactSystem.start()
	ExtractionSystem.start()
	RoundSystem.start()

	print("[DEADPACT] booted — district, horde, loot and round director live.")
end

local ok, err = pcall(boot)
if not ok then
	warn("================================================")
	warn("[DEADPACT] BOOT FAILED: " .. tostring(err))
	warn("================================================")
end
