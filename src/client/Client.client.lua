--!strict
--[[
	Client.client.lua — DEADPACT's only LocalScript.

	Responsibilities (and nothing more):
	 * Build the whole HUD from scratch — survival bars, weapon readout,
	   round clock, the pact encounter panel and the end-of-round debrief.
	 * Render the five server->client feeds (RoundState, HudState, PactPrompt,
	   PactResult, Debrief, HitMarker, NoisePulse, ExtractionState).
	 * Capture player input and forward it as *requests* (fire, reload, sprint,
	   swap, loot, revive, lower, pact choice). The server is authoritative for
	   everything; this script never decides an outcome.

	Every handler is wrapped so a malformed payload can never take the whole
	client down and leave a blank screen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Viewmodel = require(script.Parent.Viewmodel)

local LocalPlayer = Players.LocalPlayer
local remotes = Remotes.ensure()

local COL_AMBER = Color3.fromRGB(255, 182, 72)
local COL_BLOOD = Color3.fromRGB(200, 50, 31)
local COL_STEEL = Color3.fromRGB(138, 148, 166)
local COL_HEALTH = Color3.fromRGB(214, 66, 48)
local COL_STAMINA = Color3.fromRGB(122, 190, 214)

-- ---------------------------------------------------------------------------
-- Small UI factory helpers
-- ---------------------------------------------------------------------------

local function newInstance<T>(className: string, props: { [string]: any }): T
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		(inst :: any)[key] = value
	end
	return inst :: any
end

local function makeBar(parent: Instance, yPos: number, width: number, color: Color3): Frame
	local track = newInstance("Frame", {
		Name = "Track",
		Size = UDim2.fromOffset(width, 12),
		Position = UDim2.new(0, 24, 1, yPos),
		BackgroundColor3 = Color3.fromRGB(18, 20, 26),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = parent,
	})
	newInstance("UICorner", { CornerRadius = UDim.new(1, 0), Parent = track })

	local fill = newInstance("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = track,
	})
	newInstance("UICorner", { CornerRadius = UDim.new(1, 0), Parent = fill })

	return fill
end

-- ---------------------------------------------------------------------------
-- Screen GUI
-- ---------------------------------------------------------------------------

local gui = newInstance("ScreenGui", {
	Name = "DeadpactHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 10,
	Parent = LocalPlayer:WaitForChild("PlayerGui"),
})

local root = newInstance("Frame", {
	Name = "Root",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = gui,
})

-- Top-centre round banner: phase + clock + wave.
local banner = newInstance("Frame", {
	Name = "Banner",
	Size = UDim2.fromOffset(380, 52),
	Position = UDim2.new(0.5, 0, 0, 16),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = Color3.fromRGB(10, 11, 15),
	BackgroundTransparency = 0.18,
	BorderSizePixel = 0,
	Parent = root,
})
newInstance("UICorner", { CornerRadius = UDim.new(0, 8), Parent = banner })
newInstance("UIStroke", { Color = COL_AMBER, Thickness = 1, Transparency = 0.6, Parent = banner })

local phaseLabel = newInstance("TextLabel", {
	Name = "Phase",
	Size = UDim2.new(0.5, -12, 0.5, 0),
	Position = UDim2.fromOffset(12, 6),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextColor3 = COL_AMBER,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "DEADPACT",
	Parent = banner,
})

local clockLabel = newInstance("TextLabel", {
	Name = "Clock",
	Size = UDim2.new(0.5, -12, 0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 6),
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	TextSize = 18,
	TextColor3 = Color3.fromRGB(230, 232, 238),
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "0:00",
	Parent = banner,
})

local statusLabel = newInstance("TextLabel", {
	Name = "Status",
	Size = UDim2.new(1, -24, 0.5, -4),
	Position = UDim2.new(0, 12, 0.5, 2),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 13,
	TextColor3 = COL_STEEL,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Waiting for drop-in…",
	Parent = banner,
})

-- Bottom-left survival bars.
local bars = newInstance("Frame", {
	Name = "Bars",
	Size = UDim2.fromOffset(240, 90),
	Position = UDim2.new(0, 0, 1, -18),
	AnchorPoint = Vector2.new(0, 1),
	BackgroundTransparency = 1,
	Parent = root,
})
local healthFill = makeBar(bars, 0, 232, COL_HEALTH)
local staminaFill = makeBar(bars, -22, 232, COL_STAMINA)

-- Bottom-right weapon readout.
local weaponLabel = newInstance("TextLabel", {
	Name = "Weapon",
	Size = UDim2.fromOffset(260, 68),
	Position = UDim2.new(1, -28, 1, -18),
	AnchorPoint = Vector2.new(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 15,
	TextColor3 = Color3.fromRGB(220, 224, 232),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextYAlignment = Enum.TextYAlignment.Bottom,
	Text = "LOWERED",
	Parent = root,
})

-- Centre hit marker.
local hitMarker = newInstance("TextLabel", {
	Name = "HitMarker",
	Size = UDim2.fromOffset(64, 64),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 30,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextTransparency = 1,
	Text = "✕",
	Parent = root,
})

-- ---------------------------------------------------------------------------
-- The Pact encounter panel — DEADPACT's signature decision.
-- ---------------------------------------------------------------------------

local pactPanel = newInstance("Frame", {
	Name = "PactPanel",
	Size = UDim2.fromOffset(360, 210),
	Position = UDim2.new(0.5, 0, 0.5, 40),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = Color3.fromRGB(12, 13, 18),
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	Visible = false,
	Parent = root,
})
newInstance("UICorner", { CornerRadius = UDim.new(0, 10), Parent = pactPanel })
newInstance(
	"UIStroke",
	{ Color = COL_BLOOD, Thickness = 1.5, Transparency = 0.35, Parent = pactPanel }
)

local pactTitle = newInstance("TextLabel", {
	Size = UDim2.new(1, -24, 0, 26),
	Position = UDim2.fromOffset(12, 12),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextColor3 = COL_AMBER,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "A survivor is in reach",
	Parent = pactPanel,
})

local pactBody = newInstance("TextLabel", {
	Size = UDim2.new(1, -24, 0, 60),
	Position = UDim2.fromOffset(12, 40),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 14,
	TextColor3 = Color3.fromRGB(200, 205, 214),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	Text = "",
	Parent = pactPanel,
})

local function makePactButton(label: string, xScale: number, color: Color3): TextButton
	local button = newInstance("TextButton", {
		Size = UDim2.new(0.3, 0, 0, 44),
		Position = UDim2.new(xScale, 0, 1, -56),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(12, 13, 18),
		Text = label,
		Parent = pactPanel,
	})
	newInstance("UICorner", { CornerRadius = UDim.new(0, 8), Parent = button })
	return button
end

local pactAlly = makePactButton("ALLY", 0.035, COL_AMBER)
local pactFight = makePactButton("FIGHT", 0.35, COL_BLOOD)
local pactIgnore = makePactButton("IGNORE", 0.665, COL_STEEL)

-- ---------------------------------------------------------------------------
-- Debrief panel
-- ---------------------------------------------------------------------------

local debrief = newInstance("Frame", {
	Name = "Debrief",
	Size = UDim2.fromOffset(460, 340),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(9, 10, 14),
	BackgroundTransparency = 0.04,
	BorderSizePixel = 0,
	Visible = false,
	Parent = root,
})
newInstance("UICorner", { CornerRadius = UDim.new(0, 12), Parent = debrief })
newInstance(
	"UIStroke",
	{ Color = COL_AMBER, Thickness = 1.5, Transparency = 0.3, Parent = debrief }
)

local debriefTitle = newInstance("TextLabel", {
	Size = UDim2.new(1, -32, 0, 34),
	Position = UDim2.fromOffset(16, 16),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 24,
	TextColor3 = COL_AMBER,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "DEBRIEF",
	Parent = debrief,
})
debriefTitle.Name = "Title"

local debriefBody = newInstance("TextLabel", {
	Size = UDim2.new(1, -32, 1, -76),
	Position = UDim2.fromOffset(16, 58),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 15,
	TextColor3 = Color3.fromRGB(206, 211, 220),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	Text = "",
	Parent = debrief,
})

-- ---------------------------------------------------------------------------
-- State application
-- ---------------------------------------------------------------------------

local function setBar(fill: Frame, ratio: number)
	fill.Size = UDim2.fromScale(Util.clamp(ratio, 0, 1), 1)
end

local function applyRoundState(payload: any)
	if type(payload) ~= "table" then
		return
	end
	phaseLabel.Text = string.upper(tostring(payload.phase or "?"))
	clockLabel.Text = Util.formatClock(payload.phaseTimeLeft or 0)
	statusLabel.Text = string.format(
		"Wave %d   ·   %d infected   ·   %d standing   ·   %d extracted",
		payload.waveIndex or 0,
		payload.zombieCount or 0,
		payload.survivors or 0,
		payload.extracted or 0
	)
end

local function applyHudState(payload: any)
	if type(payload) ~= "table" then
		return
	end
	setBar(healthFill, (payload.health or 0) / (payload.maxHealth or 100))
	setBar(staminaFill, (payload.stamina or 0) / (payload.maxStamina or 100))

	local weapon = payload.weapon
	if type(weapon) == "table" then
		if type(weapon.id) == "string" then
			Viewmodel.setWeapon(weapon.id)
		end
		local reload = ""
		if weapon.reloading then
			reload =
				string.format("  RELOADING %d%%", math.floor((weapon.reloadProgress or 0) * 100))
		end
		weaponLabel.Text = string.format(
			"%s\n%d / %d   ·   %d reserve%s",
			tostring(weapon.displayName or "—"),
			math.floor(weapon.ammoInMag or 0),
			math.floor(weapon.magazine or 0),
			math.floor(weapon.reserve or 0),
			reload
		)
	else
		weaponLabel.Text = "UNARMED"
	end

	if payload.isDowned then
		statusLabel.Text = "DOWNED — waiting for a pact ally to revive you"
	elseif payload.extractionOpen then
		statusLabel.Text = string.format(
			"EXTRACTION OPEN — hold the zone (%d%%)",
			math.floor((payload.extractionProgress or 0) * 100)
		)
	end
end

local function showPact(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local history = payload.history or {}
	pactTitle.Text = string.format("%s is in reach", tostring(payload.partnerName or "A survivor"))
	pactBody.Text = string.format(
		"Kept %d · Broken %d%s\nThey are %d studs away. You have %d seconds to decide.",
		history.kept or 0,
		history.broken or 0,
		history.pacted and "\nAlready pacted — they are your ally." or "",
		math.floor(payload.distance or 0),
		math.floor(payload.window or Config.Pact.decisionWindow)
	)
	pactPanel.Visible = true
end

local function hidePact()
	pactPanel.Visible = false
end

local function showDebrief(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local lines = {
		string.format("Survived: %s", payload.survived and "YES" or "NO"),
		string.format("Extracted: %s", payload.extracted and "YES" or "NO"),
		string.format("Banked score: %d", math.floor(payload.bankedScore or 0)),
		string.format("Kills: %d", math.floor(payload.kills or 0)),
		"",
		"WHO KEPT THEIR WORD",
	}
	local rows = payload.pacts
	if type(rows) == "table" then
		local any = false
		for _, row in ipairs(rows) do
			any = true
			table.insert(
				lines,
				string.format(
					"  %-18s  kept %d   ·   broke %d",
					tostring(row.name or "?"),
					row.kept or 0,
					row.broken or 0
				)
			)
		end
		if not any then
			table.insert(lines, "  No pacts were made.")
		end
	end
	debriefBody.Text = table.concat(lines, "\n")
	debrief.Visible = true
	pactPanel.Visible = false
end

-- ---------------------------------------------------------------------------
-- Inbound wiring (each handler isolated)
-- ---------------------------------------------------------------------------

local function bind(eventName: string, handler: (any) -> ())
	local event = remotes.events[eventName]
	if event == nil then
		return
	end
	event.OnClientEvent:Connect(function(payload: any)
		local ok, err = pcall(handler, payload)
		if not ok then
			warn(string.format("DEADPACT client: %s handler failed: %s", eventName, tostring(err)))
		end
	end)
end

bind("RoundState", function(payload)
	applyRoundState(payload)
	if payload and payload.phase == "Debrief" then
		pactPanel.Visible = false
	end
end)
bind("HudState", applyHudState)
bind("PactPrompt", showPact)
bind("PactResult", function(payload)
	hidePact()
	if type(payload) == "table" then
		local word = payload.outcome == "Pacted" and "PACT SEALED"
			or (payload.outcome == "Hostile" and "HOSTILE" or "IGNORED")
		statusLabel.Text = string.format("%s — %s", word, tostring(payload.partnerName or ""))
	end
end)
bind("Debrief", showDebrief)
bind("HitMarker", function(payload)
	if type(payload) == "table" and payload.hit then
		hitMarker.TextColor3 = payload.killed and COL_BLOOD or Color3.fromRGB(255, 255, 255)
		hitMarker.TextTransparency = 0
		task.delay(0.18, function()
			hitMarker.TextTransparency = 1
		end)
	end
end)
bind("WeaponFeedback", Viewmodel.applyFeedback)
bind("ExtractionState", function(payload)
	if type(payload) == "table" and payload.open then
		statusLabel.Text = "EXTRACTION OPEN — get to the zone"
	end
end)

-- One-shot snapshot so a late joiner is never blank.
task.spawn(function()
	local getInitial = remotes.functions.GetInitialState
	if getInitial == nil then
		return
	end
	local ok, snapshot = pcall(function()
		return getInitial:InvokeServer()
	end)
	if ok and type(snapshot) == "table" then
		if snapshot.round then
			applyRoundState(snapshot.round)
		end
		if snapshot.hud then
			applyHudState(snapshot.hud)
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Outbound: player input -> server requests
-- ---------------------------------------------------------------------------

local function fire(eventName: string, ...)
	local event = remotes.events[eventName]
	if event ~= nil then
		event:FireServer(...)
	end
end

local pactOpen = false
local function decide(choice: string)
	pactOpen = false
	hidePact()
	fire("PactChoice", choice)
end

pactAlly.Activated:Connect(function()
	decide("Ally")
end)
pactFight.Activated:Connect(function()
	decide("Fight")
end)
pactIgnore.Activated:Connect(function()
	decide("Ignore")
end)

local function onPactPrompt()
	pactOpen = true
end
bind("PactPrompt", onPactPrompt)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if pactOpen then
			return
		end
		fire("FireRequest")
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		Viewmodel.setAiming(true)
	elseif input.KeyCode == Enum.KeyCode.R then
		fire("ReloadRequest")
	elseif input.KeyCode == Enum.KeyCode.E then
		fire("LootRequest")
	elseif input.KeyCode == Enum.KeyCode.Q then
		fire("SwapWeapon")
	elseif input.KeyCode == Enum.KeyCode.F then
		fire("ReviveRequest")
	elseif input.KeyCode == Enum.KeyCode.X then
		fire("LowerWeapon", true)
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		fire("SprintState", false)
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		Viewmodel.setAiming(false)
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if
		not processed
		and (input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift)
	then
		fire("SprintState", true)
	end
end)

-- Keyboard shortcuts for the pact decision (1 / 2 / 3).
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or not pactOpen then
		return
	end
	if input.KeyCode == Enum.KeyCode.One then
		decide("Ally")
	elseif input.KeyCode == Enum.KeyCode.Two then
		decide("Fight")
	elseif input.KeyCode == Enum.KeyCode.Three then
		decide("Ignore")
	end
end)

if not RunService:IsClient() then
	return
end

-- Bring up the first-person weapon model.
Viewmodel.start()
