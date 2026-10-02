--!strict
--[[
	Survival.lua — hunger, thirst and exposure.

	The climb is not only shooting: it is staying alive on the way up. Every
	frame each living player burns hunger and thirst, and the air itself is a
	threat — freezing on the low tiers, furnace-hot near the forge core high on
	the ascent. Empty hunger/thirst and extreme exposure all bite into health.

	This module owns ONLY the survival numbers. It never touches movement,
	combat or the round director, and it publishes its felt temperature so the
	client HUD can warn the player before the damage starts.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Runtime = require(script.Parent.Runtime)

local Survival = {}

export type ExposureBand = "Cold" | "Comfort" | "Heat"

--- Picks the exposure band for a felt temperature.
function Survival.band(tempC: number): ExposureBand
	local cfg = Config.Survival
	if tempC < cfg.coldComfortLow then
		return "Cold"
	elseif tempC > cfg.coldComfortHigh then
		return "Heat"
	end
	return "Comfort"
end

--- The real ambient temperature at a world position: cold city base, warmed by
--- proximity to the forge core. This is a cheap distance check, run per player
--- per step — no raycasts, no allocation.
function Survival.temperatureAt(position: Vector3): number
	local cfg = Config.Survival
	local district = Runtime.service("District")
	local forgeCore: Vector3? = district and district.forgeCore
	if forgeCore == nil then
		return cfg.ambientTemp
	end
	local d = (position - forgeCore).Magnitude
	if d >= cfg.forgeRadius then
		return cfg.ambientTemp
	end
	-- 0 at the core, 1 at the edge of the heat bubble.
	local t = d / cfg.forgeRadius
	return cfg.forgeTemp + (cfg.ambientTemp - cfg.forgeTemp) * t
end

--- Grants food/water to a player state (loot pick-up). Values are 0..1. The
--- HUD is broadcast 4x/second by the round director, so no explicit push here.
function Survival.grant(ps: Runtime.PlayerState, kind: "food" | "water", amount: number): ()
	if kind == "food" then
		ps.hunger = math.clamp(ps.hunger + amount, 0, 1)
	else
		ps.thirst = math.clamp(ps.thirst + amount, 0, 1)
	end
end

--- The survival slice of the HUD payload (kept tiny; RoundSystem owns the rest).
function Survival.hudExtras(ps: Runtime.PlayerState): { [string]: any }
	return {
		hunger = ps.hunger,
		thirst = ps.thirst,
		tempC = ps.tempC,
		exposure = Survival.band(ps.tempC),
	}
end

--- One survival step for every living player. Registered with Runtime.
local function step(dt: number, _now: number): ()
	local cfg = Config.Survival
	local damage = 0

	for _, ps in pairs(Runtime.allStates()) do
		if not ps.alive or ps.downed then
			continue
		end

		-- Burn hunger + thirst (these only tick while you are alive and up).
		ps.hunger = math.clamp(ps.hunger - (cfg.hungerDrain * dt) / cfg.maxHunger, 0, 1)
		ps.thirst = math.clamp(ps.thirst - (cfg.thirstDrain * dt) / cfg.maxThirst, 0, 1)

		-- Exposure: chase the real temperature so sudden moves read smoothly.
		local target = Survival.temperatureAt(ps.position)
		ps.tempC += (target - ps.tempC) * math.clamp(cfg.exposureLerp * dt, 0, 1)

		local hurt = 0
		if ps.hunger <= 0 then
			hurt += cfg.hungerStarveDamage * dt
		end
		if ps.thirst <= 0 then
			hurt += cfg.thirstDehydrateDamage * dt
		end
		local band = Survival.band(ps.tempC)
		if band ~= "Comfort" then
			hurt += cfg.exposureDamage * dt
		end

		if hurt > 0 then
			local humanoid = ps.player.Character
				and ps.player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid ~= nil then
				humanoid:TakeDamage(hurt)
			end
			ps.health = math.max(0, ps.health - hurt)
		end
	end
end

--- Registers the survival step. Called once by Boot.
function Survival.start(): ()
	Runtime.provide("Survival", Survival)
	Runtime.registerStep(step)
	-- Cheap liveness marker so a silent failure is visible in the console.
	print(
		string.format(
			"[DEADPACT] survival online — hunger %.2f/s thirst %.2f/s ambient %dC",
			Config.Survival.hungerDrain,
			Config.Survival.thirstDrain,
			Config.Survival.ambientTemp
		)
	)
end

return Survival
