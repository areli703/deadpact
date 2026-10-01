--!strict
--[[
	Types.lua — shared type definitions and enums used across the wire.

	Keeping these in one place means server and client agree on every payload
	shape that travels over a RemoteEvent.
]]

local Types = {}

export type PhaseName = "Intermission" | "Deployment" | "Active" | "Extraction" | "Debrief"

export type PactChoice = "Ally" | "Fight" | "Ignore"

export type PactDecision = PactChoice | "None"

-- Per-pair ledger entry. Keyed by an ordered pair of UserIds.
export type LedgerEntry = {
	kept: number,
	broken: number,
}

-- Snapshot of one player's pact history shown to another player.
export type PactHistory = {
	kept: number,
	broken: number,
	pacted: boolean, -- currently allied?
}

export type RoundStatePayload = {
	phase: PhaseName,
	phaseTimeLeft: number,
	phaseDuration: number,
	waveIndex: number,
	zombieCount: number,
	survivors: number,
	dead: number,
	extracted: number,
}

export type WeaponHudState = {
	id: string,
	displayName: string,
	ammoInMag: number,
	magazine: number,
	reserve: number,
	reloading: boolean,
	reloadProgress: number,
}

export type HudStatePayload = {
	health: number,
	maxHealth: number,
	stamina: number,
	maxStamina: number,
	heat: number, -- 0..1 normalised local heat
	weapon: WeaponHudState?,
	weaponLowered: boolean,
	extractionOpen: boolean,
	extractionProgress: number,
	isDowned: boolean,
	alive: boolean,
}

export type PactPromptPayload = {
	partnerUserId: number,
	partnerName: string,
	distance: number,
	history: PactHistory,
	window: number, -- seconds the client has to decide
}

export type PactResultPayload = {
	partnerUserId: number,
	partnerName: string,
	outcome: "Pacted" | "Hostile" | "Ignored",
	broken: boolean,
	history: PactHistory,
}

export type NoisePulsePayload = {
	position: Vector3,
	heat: number, -- 0..1 relative to maxHeat
	loud: boolean, -- was this the district-wide hottest pulse?
}

export type HitMarkerPayload = {
	hit: boolean,
	killed: boolean,
	source: "Weapon" | "Melee" | "Zombie",
}

export type DebriefPactRow = {
	name: string,
	kept: number,
	broken: number,
}

export type DebriefPayload = {
	phase: PhaseName,
	survived: boolean,
	extracted: boolean,
	bankedScore: number,
	pacts: { DebriefPactRow },
	kills: number,
}

export type ExtractionPointState = {
	id: string,
	position: Vector3,
	open: boolean,
	openAt: number,
	closeAt: number,
}

export type LootKind = "weapon" | "ammo" | "med"

export type LootEntry = {
	id: string,
	kind: LootKind,
	weaponId: string?,
	ammoType: string?,
	amount: number?,
	position: Vector3,
	taken: boolean,
}

return Types
