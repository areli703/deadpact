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
	sidewalkWidth: number,
	groundY: number,
	-- Shell + interior tunables for the enterable buildings.
	wallThickness: number,
	doorWidth: number,
	doorHeight: number,
	windowWidth: number,
	windowHeight: number,
	floorBandEvery: number,
	roofParapet: number,
	buildingHeights: { number },
	buildingCount: number,
	lightHeight: number,
	blockColors: { Color3 },
	streetColor: Color3,
	sidewalkColor: Color3,
	groundColor: Color3,
	roofColor: Color3,
	buildingColor: Color3,
	trimColor: Color3,
	glassColor: Color3,
	laneColor: Color3,
	interiorColor: Color3,
	lightColor: Color3,
	extractionCount: number,
	extractionRadius: number,
	lootCount: number,
}

Config.District = {
	-- ~240x240 stud playable area: a real grid of city blocks, not a corridor.
	studsPerSide = 240,
	blockSize = 60,
	streetWidth = 22,
	sidewalkWidth = 5,
	groundY = 0,
	-- Shell + interior tunables for the enterable buildings.
	wallThickness = 1.6,
	doorWidth = 8,
	doorHeight = 13,
	windowWidth = 8,
	windowHeight = 6.5,
	floorBandEvery = 11,
	roofParapet = 2.6,
	-- Varied building heights; each is chosen from this list.
	buildingHeights = { 26, 34, 42, 54, 64 },
	buildingCount = 16,
	lightHeight = 18,

	blockColors = {
		Color3.fromRGB(40, 42, 50),
		Color3.fromRGB(46, 44, 38),
		Color3.fromRGB(34, 38, 44),
		Color3.fromRGB(50, 46, 42),
		Color3.fromRGB(38, 40, 48),
	},
	streetColor = Color3.fromRGB(24, 25, 29),
	sidewalkColor = Color3.fromRGB(40, 41, 46),
	groundColor = Color3.fromRGB(20, 21, 25),
	roofColor = Color3.fromRGB(48, 50, 56),
	buildingColor = Color3.fromRGB(34, 36, 42),
	trimColor = Color3.fromRGB(60, 62, 70),
	glassColor = Color3.fromRGB(120, 170, 210),
	laneColor = Color3.fromRGB(208, 202, 176),
	interiorColor = Color3.fromRGB(46, 44, 42),
	-- Amber street lighting, matching the concept palette.
	lightColor = Color3.fromRGB(255, 182, 72),

	extractionCount = 3,
	extractionRadius = 12,
	lootCount = 16,

	-- ---- THE ASCENT ------------------------------------------------------
	-- The ground city above is only the start: tier after tier stacks upward
	-- into the clouds, matching the concept art's pyramid silhouette. Each tier
	-- is a platform ring holding enterable blocks, joined to the one below by
	-- grand staircases. Tune these to change how tall the world feels.
	ascentTiers = 10,
	ascentTierHeight = 30,
	ascentStairWidth = 16,
	ascentPlatformRadius = 52,
	ascentBlockCount = 3,
	-- Cold at the bottom, fire at the top: per-tier tint blended by Vertical.
	ascentColdColor = Color3.fromRGB(96, 128, 168),
	ascentHotColor = Color3.fromRGB(214, 118, 54),
} :: DistrictConfig

-- ---------------------------------------------------------------------------
-- World purpose — "The Payload"
--
-- The district is not scenery: at the centre of every round it hides ONE
-- extractable objective, THE PAYLOAD. Taking it and getting it out through an
-- extraction zone is the win condition. Because the payload is heavy, its
-- carrier moves slowly and cannot sprint — so you need a pact ally covering
-- you. Purpose + the Pact, wired together.
-- ---------------------------------------------------------------------------

Config.Purpose = {
	-- The landmark building that hides the payload sits here (district centre).
	landmarkPosition = Vector3.new(0, 0, 0),
	-- Seconds into the Active phase before the payload can be grabbed.
	armedAt = 0,
	-- How long a carrier must hold the pad to secure the payload.
	secureHoldTime = 2.5,
	-- Movement penalty on the carrier: the reason you want an ally.
	carrierWalkSpeed = 8,
	carrierCanSprint = false,
	-- Score awarded for escaping with the payload; a huge chunk of the round.
	extractScore = 750,
	-- Score awarded for standing on the payload when the round ends (contested).
	holdScore = 150,
	-- The payload is a physical, glowing object you can see across the district.
	beaconRange = 260,
	beaconBrightness = 4,
}

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
		{ name = "Intermission", duration = 3 },
		{ name = "Deployment", duration = 12 }, -- quick test prep before the siren
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
	-- Handling (drive the viewmodel + feedback on the client)
	melee: boolean, -- true for blades: no ammo, no muzzle flash
	adsZoom: number, -- camera FOV multiplier while aiming down sights
	recoil: number, -- kick applied to the viewmodel per shot
	headshotMultiplier: number, -- damage multiplier for a head hit
	backstabMultiplier: number, -- melee-only: damage multiplier from behind
	muzzleScale: number, -- size of the muzzle flash
}

Config.Weapons = {
	knife = {
		displayName = "Trench Knife",
		damage = 55,
		fireRate = 1.6,
		magazine = 0, -- blades do not reload
		reloadTime = 0,
		spread = 0,
		range = 7,
		ammoType = "none",
		noise = 0, -- the knife is the silent option
		automatic = false,
		melee = true,
		adsZoom = 1,
		recoil = 0.05,
		headshotMultiplier = 2,
		backstabMultiplier = 3,
		muzzleScale = 0,
	} :: WeaponConfig,

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
		melee = false,
		adsZoom = 0.75,
		recoil = 0.12,
		headshotMultiplier = 2,
		backstabMultiplier = 1,
		muzzleScale = 1.4,
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
		melee = false,
		adsZoom = 0.85,
		recoil = 0.3,
		headshotMultiplier = 1.5,
		backstabMultiplier = 1,
		muzzleScale = 2.2,
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
		melee = false,
		adsZoom = 0.6,
		recoil = 0.16,
		headshotMultiplier = 2.5,
		backstabMultiplier = 1,
		muzzleScale = 1.7,
	} :: WeaponConfig,
} :: { [string]: WeaponConfig }

Config.WeaponOrder = { "knife", "pistol", "shotgun", "rifle" }
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
Config.ZombieSpawnInterval = 1.2
Config.ZombieSpawnDistanceMin = 28
Config.ZombieSpawnDistanceMax = 42
Config.ZombieDespawnDistance = 240

-- Wave schedule. Escalates over the Active phase; tied to Config.Round by the
-- load-time assertion in src/server/Boot.server.lua.
-- ---------------------------------------------------------------------------
-- Wave director
-- ---------------------------------------------------------------------------

-- Every wave is telegraphed before it lands: a warning fires `warningLead`
-- seconds early with a name the client shows as a full-width alert, so the
-- player always gets to make a decision (brace, run, feed the fire) before the
-- horde arrives. Between waves the trickle pauses for `breather` seconds so
-- the pressure breathes instead of ramping monotonically.
export type WaveEntry = {
	atSeconds: number,
	count: number,
	specials: number,
	name: string,
	warning: string,
}

Config.Waves = {
	{
		atSeconds = 0,
		count = 6,
		specials = 0,
		name = "FIRST CONTACT",
		warning = "MOVEMENT IN THE LOWER CITY",
	},
	{
		atSeconds = 30,
		count = 10,
		specials = 1,
		name = "THE GATHERING",
		warning = "A CROWD FORMS BELOW",
	},
	{
		atSeconds = 60,
		count = 16,
		specials = 1,
		name = "THE PUSH",
		warning = "THEY HAVE FOUND THE STAIRS",
	},
	{
		atSeconds = 95,
		count = 22,
		specials = 2,
		name = "THE SURGE",
		warning = "SOMETHING BIG IS CLIMBING",
	},
	{
		atSeconds = 130,
		count = 30,
		specials = 3,
		name = "THE FLOOD",
		warning = "THE TIER IS OVERRUN",
	},
	{
		atSeconds = 165,
		count = 40,
		specials = 4,
		name = "LAST STAND",
		warning = "HOLD WHAT YOU HAVE",
	},
} :: { WaveEntry }

Config.WaveDirector = {
	warningLead = 8, -- seconds of warning before a wave lands
	breather = 6, -- seconds the trickle pauses after each wave lands
	alertDuration = 4, -- seconds the client banner stays up
	-- A wave that spawns into an empty map (no living players) still fires its
	-- alert, so a late joiner is never surprised by a silent horde.
}

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
-- Survival (hunger / thirst / exposure)
-- ---------------------------------------------------------------------------

-- The climb is survival, not just shooting. Hunger and thirst tick down
-- continuously; exposure is driven by WHERE you are — the frozen Blocks bite
-- on the low tiers, the Furnace roasts you if you stray too near its heart.
-- All rates are per-second. Early tuning is forgiving on purpose (design
-- philosophy: easy to learn, difficult to master).
Config.Survival = {
	maxHunger = 100,
	maxThirst = 100,

	hungerDrain = 0.55, -- empty in ~3 min of play
	thirstDrain = 0.85, -- thirst is the tighter clock (~2 min)
	hungerStarveDamage = 2, -- HP/s once hunger hits 0
	thirstDehydrateDamage = 3, -- HP/s once thirst hits 0

	-- Restores granted by loot items (amounts rolled per pick-up).
	foodRestore = { min = 18, max = 34 },
	waterRestore = { min = 22, max = 40 },

	-- Exposure: a global ambient temperature plus hotter zones near the forge.
	ambientTemp = -6, -- degrees C in the lower city
	forgeRadius = 70, -- studs from the forge core that counts as "in the heat"
	forgeTemp = 55, -- degrees C at the forge core
	coldComfortLow = -10, -- below this you start taking cold damage
	coldComfortHigh = 45, -- above this you start taking heat damage
	exposureDamage = 1.5, -- HP/s while outside your comfort band
	exposureLerp = 0.6, -- how fast felt temperature chases real temperature
}

-- ---------------------------------------------------------------------------
-- Safe zones & checkpoints
-- ---------------------------------------------------------------------------

-- Standing in a safe zone normalizes temperature and slowly mends you; the
-- first survivor to reach a checkpoint claims it as their respawn anchor.
Config.SafeZones = {
	radius = 14, -- capture / recovery radius around a checkpoint pad
	spawnRadius = 22, -- the drop apron is always safe
	comfortTemp = 18, -- felt temperature a safe zone pulls you toward
	healRate = 3, -- HP/s mended while safe
	warmRate = 1.2, -- how fast temperature normalizes while safe
	zombieSpawnRetries = 8, -- tries to find a non-safe spawn point
}

-- ---------------------------------------------------------------------------
-- Heat sources & cooling
-- ---------------------------------------------------------------------------

-- The cold is the low-tier killer, so the climb needs an answer to it: fires
-- you light and feed. A lit brazier radiates warmth in a small radius — the
-- only way to survive a long night below the forge. Fuel burns down in real
-- time; a dead fire gives nothing. Safe-zone checkpoints come pre-lit so a
-- checkpoint is genuinely a place to recover, not just to respawn.
Config.HeatSources = {
	maxFuel = 100,
	startFuel = 100,
	fuelBurnPerSecond = 1.4, -- a full fire lasts ~70s unattended
	refuelAmount = 45, -- per wood bundle
	heatRadius = 26, -- studs of meaningful warmth
	heatTemp = 28, -- degrees C felt standing at the fire
	-- Building limits (per player, per round).
	placeCooldown = 4, -- seconds between placements
	maxPerPlayer = 3,
	minSpacing = 12, -- studs between any two live fires
	-- Braziers seeded at each safe-zone checkpoint so checkpoints are warm.
	checkpointBrazierFuel = 100,
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
	"melee",
	"adsZoom",
	"recoil",
	"headshotMultiplier",
	"backstabMultiplier",
	"muzzleScale",
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
