--!strict
--[[
	Viewmodel.lua — the weapon you actually SEE in your hands.

	This is a presentation-only module. It never decides damage, ammo or hits —
	the server owns all of that and tells us when a shot happened via the
	"WeaponFeedback" remote. Our job is to make the shot feel real:

	 * a first-person model parented to the camera (knife / pistol / shotgun / rifle)
	 * a spring that settles the weapon back to its rest pose
	 * a recoil impulse + muzzle flash on every shot
	 * a swing animation for melee
	 * aim-down-sights: the weapon centres and the FOV zooms

	Parts live under the Camera so they render in front of the world and are
	never replicated. Everything is CanCollide/CanQuery false — the model is a
	ghost that cannot interfere with the server's raycasts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Viewmodel = {}

local REST_OFFSET = CFrame.new(1.35, -1.15, -1.6)
local AIM_OFFSET = CFrame.new(0.0, -0.55, -1.15)
local BASE_FOV = 70

local camera: Camera? = nil
local root: Folder? = nil
local models: { [string]: Model } = {}
local currentId: string = "pistol"

-- Spring state (position + velocity), integrated each frame.
local springPos = Vector3.new(0, 0, 0)
local springVel = Vector3.new(0, 0, 0)
local recoilPitch: number = 0
local recoilVel: number = 0
local aimBlend: number = 0
local aiming: boolean = false
local swingT: number = -1
local bobPhase: number = 0

local muzzleByName: { [string]: BasePart } = {}

-- ---------------------------------------------------------------------------
-- Model construction
-- ---------------------------------------------------------------------------

local function part(
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local STEEL = Color3.fromRGB(52, 58, 66)
local DARK = Color3.fromRGB(30, 32, 36)
local WOOD = Color3.fromRGB(74, 52, 34)
local BLADE = Color3.fromRGB(196, 204, 214)

local function buildKnife(parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = "knife"
	local handle = part("Handle", Vector3.new(0.14, 0.14, 0.62), WOOD, Enum.Material.Wood, m)
	handle.CFrame = CFrame.new(0, 0, 0.25)
	local guard = part("Guard", Vector3.new(0.3, 0.08, 0.08), DARK, Enum.Material.Metal, m)
	guard.CFrame = CFrame.new(0, 0, -0.09)
	local blade = part("Blade", Vector3.new(0.07, 0.2, 0.95), BLADE, Enum.Material.Metal, m)
	blade.CFrame = CFrame.new(0, 0.05, -0.6)
	local tip = part("Tip", Vector3.new(0.06, 0.06, 0.24), BLADE, Enum.Material.Metal, m)
	tip.CFrame = CFrame.new(0, 0.13, -1.12)
	muzzleByName.knife = blade
	m.Parent = parent
	return m
end

local function buildGun(parent: Instance, name: string, long: boolean): Model
	local m = Instance.new("Model")
	m.Name = name
	part("Grip", Vector3.new(0.16, 0.44, 0.2), DARK, Enum.Material.Plastic, m).CFrame =
		CFrame.new(0, -0.24, 0.12)
	local body = part("Body", Vector3.new(0.2, 0.24, 0.66), STEEL, Enum.Material.Metal, m)
	body.CFrame = CFrame.new(0, 0, -0.08)
	local mag = part("Magazine", Vector3.new(0.14, 0.34, 0.14), DARK, Enum.Material.Plastic, m)
	mag.CFrame = CFrame.new(0, -0.3, 0.02)
	local barrelLen = if long then 1.1 else 0.5
	local barrel = part("Barrel", Vector3.new(0.11, 0.11, barrelLen), STEEL, Enum.Material.Metal, m)
	barrel.CFrame = CFrame.new(0, 0.02, -0.45 - barrelLen / 2)
	local muzzle = part("Muzzle", Vector3.new(0.17, 0.17, 0.22), DARK, Enum.Material.Metal, m)
	muzzle.CFrame = CFrame.new(0, 0.02, -0.45 - barrelLen - 0.1)
	muzzleByName[name] = muzzle
	if long then
		local stock = part("Stock", Vector3.new(0.16, 0.22, 0.5), WOOD, Enum.Material.Wood, m)
		stock.CFrame = CFrame.new(0, -0.06, 0.55)
	end
	m.Parent = parent
	return m
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function Viewmodel.visible(on: boolean): ()
	if root ~= nil then
		root.Parent = if on then camera else nil
	end
end

--- Builds every weapon model once and hides them. Safe to call repeatedly.
function Viewmodel.start(): ()
	if root ~= nil then
		return
	end
	camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	BASE_FOV = camera.FieldOfView
	local folder = Instance.new("Folder")
	folder.Name = "DEADPACTViewmodel"
	models.knife = buildKnife(folder)
	models.pistol = buildGun(folder, "pistol", false)
	models.shotgun = buildGun(folder, "shotgun", true)
	models.rifle = buildGun(folder, "rifle", true)
	for id, m in pairs(models) do
		m.Visible = false
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 0
			end
		end
		models[id] = m
	end
	root = folder
	folder.Parent = camera

	RunService.RenderStepped:Connect(function(dt: number)
		Viewmodel.step(dt)
	end)
end

function Viewmodel.setWeapon(weaponId: string): ()
	if models[weaponId] == nil then
		return
	end
	currentId = weaponId
	for id, m in pairs(models) do
		m.Visible = id == weaponId
	end
end

function Viewmodel.setAiming(on: boolean): ()
	aiming = on
end

--- Called from the WeaponFeedback remote. `payload` is server-authoritative:
--- it only tells us that a shot happened and how hard it kicked.
function Viewmodel.applyFeedback(payload: any): ()
	if type(payload) ~= "table" then
		return
	end
	if type(payload.weaponId) == "string" then
		Viewmodel.setWeapon(payload.weaponId)
	end
	local kick = tonumber(payload.recoil) or 0.1
	recoilVel += kick * 22
	if payload.melee then
		swingT = 0
	else
		Viewmodel.flash(tonumber(payload.muzzleScale) or 1)
	end
end

local flashUntil: number = 0
local flashScale: number = 1

function Viewmodel.flash(scale: number): ()
	flashUntil = os.clock() + 0.055
	flashScale = math.clamp(scale, 0.4, 3)
end

-- ---------------------------------------------------------------------------
-- Per-frame integration
-- ---------------------------------------------------------------------------

function Viewmodel.step(dt: number): ()
	if camera == nil then
		camera = workspace.CurrentCamera
		if camera == nil then
			return
		end
	end
	if root == nil or root.Parent ~= camera then
		return
	end
	local character = game:GetService("Players").LocalPlayer.Character
	if character == nil or character:FindFirstChild("HumanoidRootPart") == nil then
		return
	end

	-- Aim blend (0 = hip, 1 = sights).
	local target = if aiming then 1 else 0
	aimBlend += (target - aimBlend) * math.min(dt * 12, 1)
	camera.FieldOfView = BASE_FOV * (1 - aimBlend * 0.3)

	-- Recoil spring toward zero.
	recoilVel -= recoilPitch * 90 * dt
	recoilVel *= math.exp(-8 * dt)
	recoilPitch += recoilVel * dt

	-- Walking bob.
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local speed = hrp.AssemblyLinearVelocity.Magnitude
	bobPhase += dt * math.min(speed, 18) * 0.9
	local bobY = aiming and 0 or math.sin(bobPhase) * 0.02 * math.min(speed / 16, 1)
	local bobX = aiming and 0 or math.cos(bobPhase * 0.5) * 0.02 * math.min(speed / 16, 1)

	-- Melee swing: ease the knife forward and back.
	local swingZ, swingRot = 0, 0
	if swingT >= 0 then
		swingT += dt / 0.28
		if swingT >= 1 then
			swingT = -1
		else
			local s = math.sin(swingT * math.pi)
			swingZ = -s * 0.6
			swingRot = s * math.rad(55)
		end
	end

	local rest = REST_OFFSET:Lerp(AIM_OFFSET, aimBlend)
	local offset = rest
		* CFrame.new(bobX, bobY + recoilPitch * 0.35, -recoilPitch * 0.55 + swingZ)
		* CFrame.Angles(recoilPitch * 0.9, swingRot, swingRot * 0.3)

	local targetPos = camera.CFrame * offset
	local model = models[currentId]
	if model == nil then
		return
	end
	model:PivotTo(targetPos)

	-- Muzzle flash lives for a couple of frames.
	local muzzle = muzzleByName[currentId]
	if muzzle ~= nil and muzzle:IsA("BasePart") then
		local lit = os.clock() < flashUntil
		muzzle.Transparency = if lit then 0 else 0
		local light = muzzle:FindFirstChild("FlashLight")
		if lit then
			if light == nil then
				local l = Instance.new("PointLight")
				l.Name = "FlashLight"
				l.Color = Color3.fromRGB(255, 214, 140)
				l.Range = 14
				l.Brightness = 0
				l.Parent = muzzle
				light = l
			end
			if light ~= nil and light:IsA("PointLight") then
				light.Brightness = 8 * flashScale
			end
		elseif light ~= nil and light:IsA("PointLight") then
			light.Brightness = 0
		end
	end
end

return Viewmodel
