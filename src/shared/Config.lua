--!strict
--[[
	Config.lua — THE SINGLE SOURCE OF TRUTH for every tunable number in DEADPACT.

	Nothing else in the game may hard-code a gameplay number. Server and client
	both read from here. Change a value here and the whole district, wave
	schedule, weapon table and pact window re-theme to match.
]]

local Config = {}

-- ---------------------------------------------------------------------------
-- District
-- ---------------------------------------------------------------------------

export type DistrictConfig = {
	studsPerSide: number,
	blockSize: number,
	streetWidth: number,
	groundY: number,
	buildingHeights: { number },
	buildingCount: number,
	lightHeight: number,
	blockColors: { Color3 },
	streetColor: Color3,
	groundColor: Color3,
	roofColor: Color3,
	buildingColor: Color3,
	lightColor: Color3,
	extractionCount: number,
	extractionRadius: number,
	lootCount: number,
}

Config.District = {
	-- ~120x120 stud playable area.
	studsPerSide = 120,
	blockSize = 24,
	streetWidth = 12,
	groundY = 0,
	-- Varied building heights; each is chosen from this list.
	buildingHeights = { 24, 36, 48, 60, 72, 90 },
	buildingCount = 42,
	lightHeight = 16,

	blockColors = {
		Color3.fromRGB(28, 30, 36),
		Color3.fromRGB(34, 36, 44),
		Color3.fromRGB(22, 24, 30),
		Color3.fromRGB(40, 38, 34),
	},
	streetColor = Color3.fromRGB(18, 19, 22),
	groundColor = Color3.fromRGB(14, 15, 18),
	roofColor = Color3.fromRGB(46, 48, 54),
	buildingColor = Color3.fromRGB(30, 32, 38),
	-- Amber street lighting, matching the concept palette.
	lightColor = Color3.fromRGB(255, 182, 72),

	extractionCount = 3,
	extractionRadius = 10,
	lootCount = 18,
} :: DistrictConfig

-- Art direction palette (concept §8). Used by props and UI tinting.
Config.Palette = {
	amber = Color3.fromRGB(255, 182, 72),
	blood = Color3.fromRGB(200, 50, 31),
	cold = Color3.fromRGB(127, 196, 255),
	charcoal = Color3.fromRGB(24, 26, 30),
}

-- ---------------------------------------------------------------------------
-- Round loop
-- ---------------------------------------------------------------------------

export type Phase = {
	name: string,
	duration: number,
}

Config.Round = {
	phases = {
		{ name = "Intermission", duration = 20 },
		{ name = "Deployment", duration = 15 },
		{ name = "Active", duration = 180 },
		{ name = "Extraction", duration = 45 },
		{ name = "Debrief", duration = 20 },
	} :: { Phase },
	minPlayersToStart = 1,
	respawnAllowed = false,
}

-- ---------------------------------------------------------------------------
-- Weapons
-- ---------------------------------------------------------------------------

export type WeaponConfig = {
	displayName: string,
	damage: number,
	fireRate: number, -- rounds per second
	magazine: number,
	reloadTime: number,
	spread: number, -- degrees
	range: number, -- studs
	ammoType: string,
	noise: number, -- heat raised per shot
	automatic: boolean,
}

Config.Weapons = {
	pistol = {
		displayName = "Sidearm",
		damage = 18,
		fireRate = 4,
		magazine = 12,
		reloadTime = 1.6,
		spread = 2,
		range = 120,
		ammoType = "light",
		noise = 18,
		automatic = false,
	} :: WeaponConfig,

	shotgun = {
		displayName = "Breacher",
		damage = 12, -- per pellet
		fireRate = 1.2,
		magazine = 6,
		reloadTime = 2.4,
		spread = 9,
		range = 55,
		ammoType = "shell",
		noise = 42,
		automatic = false,
	} :: WeaponConfig,

	rifle = {
		displayName = "Marksman",
		damage = 26,
		fireRate = 7,
		magazine = 30,
		reloadTime = 2.0,
		spread = 3.5,
		range = 220,
		ammoType = "heavy",
		noise = 30,
		automatic = true,
	} :: WeaponConfig,
} :: { [string]: WeaponConfig }

Config.WeaponOrder = { "pistol", "shotgun", "rifle" }
Config.StartingWeapon = "pistol"
Config.PelletCounts = {
	pistol = 1,
	shotgun = 6,
	rifle = 1,
} :: { [string]: number }

Config.Ammo = {
	light = { max = 96, pickup = 24 },
	shell = { max = 48, pickup = 12 },
	heavy = { max = 120, pickup = 30 },
}

-- ---------------------------------------------------------------------------
-- Zombies
-- ---------------------------------------------------------------------------

export type ZombieConfig = {
	displayName: string,
	health: number,
	walkSpeed: number,
	damage: number, -- contact damage per hit
	attackCooldown: number,
	size: Vector3,
	color: Color3,
	weight: number, -- relative spawn chance
	-- Special hooks (0 / false when not applicable).
	onDeathBurst: number,
	targetsIsolated: boolean,
}

Config.Zombies = {
	walker = {
		displayName = "Walker",
		health = 100,
		walkSpeed = 9,
		damage = 12,
		attackCooldown = 1.1,
		size = Vector3.new(2, 5, 1),
		color = Color3.fromRGB(96, 104, 84),
		weight = 10,
		onDeathBurst = 0,
		targetsIsolated = false,
	} :: ZombieConfig,

	shrieker = {
		displayName = "Shrieker",
		health = 70,
		walkSpeed = 12,
		damage = 6,
		attackCooldown = 1.4,
		size = Vector3.new(2, 5.4, 1),
		color = Color3.fromRGB(150, 90, 140),
		weight = 2,
		-- On death summons a burst of walkers.
		onDeathBurst = 5,
		targetsIsolated = false,
	} :: ZombieConfig,

	stalker = {
		displayName = "Stalker",
		health = 140,
		walkSpeed = 14,
		damage = 20,
		attackCooldown = 1.0,
		size = Vector3.new(1.8, 5.6, 1),
		color = Color3.fromRGB(40, 44, 52),
		weight = 2,
		onDeathBurst = 0,
		-- Hunts the most isolated player.
		targetsIsolated = true,
	} :: ZombieConfig,
} :: { [string]: ZombieConfig }

Config.ZombieMaxCount = 70
Config.ZombiePoolWarmup = 30
Config.ZombieSpawnInterval = 2.5
Config.ZombieSpawnDistanceMin = 45
Config.ZombieSpawnDistanceMax = 70
Config.ZombieDespawnDistance = 240

-- Wave schedule. Escalates over the Active phase; tied to Config.Round by the
-- load-time assertion in src/server/Boot.server.lua.
Config.Waves = {
	{ atSeconds = 0, count = 6, specials = 0 },
	{ atSeconds = 30, count = 10, specials = 1 },
	{ atSeconds = 60, count = 16, specials = 1 },
	{ atSeconds = 95, count = 22, specials = 2 },
	{ atSeconds = 130, count = 30, specials = 3 },
	{ atSeconds = 165, count = 40, specials = 4 },
} :: { { atSeconds: number, count: number, specials: number } }

-- ---------------------------------------------------------------------------
-- Noise / heat
-- ---------------------------------------------------------------------------

Config.Noise = {
	maxHeat = 120,
	decayPerSecond = 6, -- heat units lost per second at every node
	radius = 90, -- convergence radius around the hottest node
	sprintHeatPerSecond = 10,
	sprintHeatInterval = 0.5, -- s between sprint heat pulses
	propBreakHeat = 30,
	lootPickupHeat = 4,
	alertThreshold = 20, -- heat needed before zombies divert to a node
}

-- ---------------------------------------------------------------------------
-- The Pact
-- ---------------------------------------------------------------------------

Config.Pact = {
	radius = 10, -- studs
	decisionWindow = 6, -- seconds before it is treated as IGNORE
	-- A player's weapon is "lowered" unless they have fired within this window.
	loweredAfterSeconds = 3,
	friendlyFireOff = true,
	-- Loot within this radius of a pacted ally is visible to both.
	sharedLootRadius = 40,
	reviveTime = 3,
	reviveRange = 6,
	promptCooldown = 4.0, -- don't re-prompt the same pair faster than this
}

-- ---------------------------------------------------------------------------
-- Extraction
-- ---------------------------------------------------------------------------

Config.Extraction = {
	-- An extraction point opens at this offset into the Extraction phase, and
	-- closes this many seconds later. Staggered so they are not all open at once.
	openOffsets = { 0, 8, 16 },
	openDuration = 22,
	holdTime = 2.5, -- seconds a player must stand in an open zone to bank
	bankedLootScore = 100,
}

-- ---------------------------------------------------------------------------
-- Survival stats
-- ---------------------------------------------------------------------------

Config.Player = {
	maxHealth = 100,
	walkSpeed = 12,
	sprintSpeed = 20,
	maxStamina = 100,
	staminaDrain = 18, -- per second while sprinting
	staminaRegen = 12, -- per second while not sprinting
	respawnDelay = 5,
	bleedoutTime = 30, -- seconds a downed player has before dying
}

-- ---------------------------------------------------------------------------
-- Validation (called by the server at load time)
-- ---------------------------------------------------------------------------

local REQUIRED_WEAPON_STATS = {
	"displayName",
	"damage",
	"fireRate",
	"magazine",
	"reloadTime",
	"spread",
	"range",
	"ammoType",
	"noise",
	"automatic",
}

local REQUIRED_ZOMBIE_STATS = {
	"displayName",
	"health",
	"walkSpeed",
	"damage",
	"attackCooldown",
	"size",
	"color",
	"weight",
	"onDeathBurst",
	"targetsIsolated",
}

--- Asserts that every weapon/zombie entry carries every required stat.
function Config.validateStats(): ()
	for id, weapon in pairs(Config.Weapons) do
		for _, key in ipairs(REQUIRED_WEAPON_STATS) do
			assert(
				weapon[key] ~= nil,
				string.format("DEADPACT config error: weapon %q is missing stat %q", id, key)
			)
		end
	end

	for id, zombie in pairs(Config.Zombies) do
		for _, key in ipairs(REQUIRED_ZOMBIE_STATS) do
			assert(
				zombie[key] ~= nil,
				string.format("DEADPACT config error: zombie %q is missing stat %q", id, key)
			)
		end
	end
end

--- Asserts the wave schedule fits inside the Active phase.
function Config.validateRound(): ()
	local activeDuration = 0
	for _, phase in ipairs(Config.Round.phases) do
		if phase.name == "Active" then
			activeDuration = phase.duration
		end
	end

	assert(activeDuration > 0, "DEADPACT config error: no Active phase in Config.Round.phases")

	local lastWave = 0
	for _, wave in ipairs(Config.Waves) do
		assert(
			wave.atSeconds < activeDuration,
			string.format(
				"DEADPACT config error: wave at %ds falls outside the %ds Active phase",
				wave.atSeconds,
				activeDuration
			)
		)
		if wave.atSeconds > lastWave then
			lastWave = wave.atSeconds
		end
	end

	assert(
		lastWave <= activeDuration,
		string.format("DEADPACT config error: last wave (%ds) exceeds Active phase", lastWave)
	)
end

return Config
