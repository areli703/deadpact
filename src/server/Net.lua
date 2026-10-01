--!strict
--[[
	Net.lua — thin typed wrapper over the remote set.

	Central place the server uses to talk to clients, so no other server module
	needs to import Remotes directly and payload shapes stay in one file.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))

local Net = {}

local set = Remotes.ensure()

--- Fires a RemoteEvent at every client.
function Net.broadcast(eventName: string, payload: any): ()
	local event = set.events[eventName]
	assert(event ~= nil, string.format("DEADPACT net error: unknown remote event %q", eventName))
	event:FireAllClients(payload)
end

--- Fires a RemoteEvent at one player.
function Net.send(player: Player, eventName: string, payload: any): ()
	if not player.Parent then
		return
	end
	local event = set.events[eventName]
	assert(event ~= nil, string.format("DEADPACT net error: unknown remote event %q", eventName))
	event:FireClient(player, payload)
end

--- Returns the typed remote set (for binding OnServerEvent / OnClientEvent).
function Net.remotes(): Remotes.RemoteSet
	return set
end

--- Convenience: builds a RoundState payload from plain numbers.
function Net.roundState(fields: Types.RoundStatePayload): Types.RoundStatePayload
	return fields
end

return Net
