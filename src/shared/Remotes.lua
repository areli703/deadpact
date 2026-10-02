--!strict
--[[
	Remotes.lua — a typed remote factory.

	The server calls Remotes.ensure() at boot to create the folder and every
	RemoteEvent/RemoteFunction under ReplicatedStorage.Remotes. The client calls
	Remotes.ensure() (which waits for replication) and gets the same typed table
	back.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

export type RemoteEventTable = { [string]: RemoteEvent }
export type RemoteFunctionTable = { [string]: RemoteFunction }

export type RemoteSet = {
	events: RemoteEventTable,
	functions: RemoteFunctionTable,
}

-- Every RemoteEvent used by DEADPACT.
local EVENT_NAMES = {
	"RoundState", -- S->C  phase + timers
	"HudState", -- S->C  per-player survival HUD
	"PactPrompt", -- S->C  the 3-choice encounter
	"PactResult", -- S->C  outcome of a decision
	"PactLedger", -- S->C  ledger refresh for the debrief
	"NoisePulse", -- S->C  heat pop at a world position
	"HitMarker", -- S->C  hit / kill feedback
	"Debrief", -- S->C  end-of-round summary
	"ExtractionState", -- S->C  which extraction zones are open
	"WeaponFeedback", -- S->C  shot/hit feedback for the viewmodel (recoil, flash)

	"PactChoice", -- C->S  Ally | Fight | Ignore
	"LowerWeapon", -- C->S  toggle lowered weapon
	"SprintState", -- C->S  sprinting on/off (server-authoritative noise)
	"FireRequest", -- C->S  player wants to fire
	"ReloadRequest", -- C->S  player wants to reload
	"LootRequest", -- C->S  player wants to take a loot entry
	"ReviveRequest", -- C->S  revive a downed pact ally
	"SwapWeapon", -- C->S  switch active weapon slot
}

local FUNCTION_NAMES = {
	"GetInitialState", -- C->S  one-shot state snapshot on join
}

--- Builds or waits for the ReplicatedStorage folder that holds the remotes.
local function getFolder(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		if existing and existing:IsA("Folder") then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

local function ensureClass(
	folder: Folder,
	className: "RemoteEvent" | "RemoteFunction",
	name: string
): Instance
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	if RunService:IsServer() then
		local instance = Instance.new(className)
		instance.Name = name
		instance.Parent = folder
		return instance
	end
	return folder:WaitForChild(name)
end

--- Creates (server) or waits for (client) every remote and returns them typed.
function Remotes.ensure(): RemoteSet
	local folder = getFolder()

	local events: RemoteEventTable = {}
	for _, name in ipairs(EVENT_NAMES) do
		events[name] = ensureClass(folder, "RemoteEvent", name) :: RemoteEvent
	end

	local functions: RemoteFunctionTable = {}
	for _, name in ipairs(FUNCTION_NAMES) do
		functions[name] = ensureClass(folder, "RemoteFunction", name) :: RemoteFunction
	end

	return { events = events, functions = functions }
end

return Remotes
