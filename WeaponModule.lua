-- Discord: lwfss | Roblox: lowpowermode123

--[[
	Advanced FPS Module
	
	Features:
	- Instant Hit Bullets
	- Bullet Spread
	- Recoil + Recovery
	- Smooth ADS
	- Ammo Saving/Storing
	- View Bobbing
]]

--// PLAYER VARIABLES
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character.Humanoid
local camera = workspace.CurrentCamera

--// GUI
local hud = player.PlayerGui:WaitForChild("HUD")
local holderFrame = hud.HolderFrame
local ammoContainer = holderFrame.AmmoContainer
local ammoLabel = ammoContainer.Ammo
local ammoAmount = ammoContainer.Amount

--// SERVICES
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

--// INSTANCES
local camera = workspace.CurrentCamera

local bulletRaycastEvent = ReplicatedStorage.Remotes.BulletRaycast

--// MODULES
local weaponModules = ReplicatedStorage.WeaponModules

--// WEAPON HANDLER
local WeaponHandler = {}
WeaponHandler.__index = WeaponHandler

--// MAIN FUNCTIONS
function WeaponHandler.InitWeapon(weaponName, savedAmmoTable)
	local self = setmetatable({}, WeaponHandler)
	
	-- Reassign player and ui variables every init (for character resets, etc)
	player = game.Players.LocalPlayer
	character = player.Character
	humanoid = character.Humanoid
	camera = workspace.CurrentCamera

	hud = player.PlayerGui:WaitForChild("HUD")
	holderFrame = hud.HolderFrame
	ammoContainer = holderFrame.AmmoContainer
	ammoLabel = ammoContainer.Ammo
	ammoAmount = ammoContainer.Amount
	
	-- Main
	self.weaponModule = weaponModules:FindFirstChild(weaponName)
	self.requiredWeaponModule = require(self.weaponModule)
	
	self.weaponName = weaponName
	self.savedAmmoTable = savedAmmoTable
	
	self.damage = self.requiredWeaponModule.damage
	self.fireRate = self.requiredWeaponModule.fireRate
	self.recoil = self.requiredWeaponModule.recoil
	self.spread = self.requiredWeaponModule.spread
	self.rayCount = self.requiredWeaponModule.rayCount
	self.maxAmmo = self.requiredWeaponModule.maxAmmo
	self.savedAmmo = self.savedAmmoTable[self.weaponName]
	self.currentAmmo = self.savedAmmo or self.maxAmmo
	self.maxRange = self.requiredWeaponModule.maxRange
	self.aimSpeed = self.requiredWeaponModule.aimSpeed
	
	-- Shared
	self.bobSpeedMultiplier = 6
	self.bobAmountMultiplier = 0.1
	self.bobTransitionLerpSpeed = 10
	
	self.recoilLerpSpeed = 10
	self.recoilRecoveryLerpSpeed = 1
	
	-- Debounces
	self.isShooting = false
	self.isReloading = false
	self.isAiming = false
	
	-- To be defined
	self.viewmodel = nil
	
	-- Tables
	self.connections = {}
	
	-- On equip
	self:SetViewmodel()
	self:SetHUD()
	
	return self
end

function WeaponHandler:Fire()
	if self.isReloading then return end
	
	if self.currentAmmo == 0 then
		self:PlaySound("NoAmmo")
		
		return 
	end
	
	self.isShooting = true
	self.currentAmmo -= 1
	
	self:SetHUD()
	self:PlaySound("Shoot")
	
	local resultTable = {}
	
	local track = self:PlayAnimation("Shoot")
	
	track.Stopped:Connect(function()
		self.isShooting = false
	end)
	
	-- Casts rays based off the number of rays in rayCount and spreads those rays based off the spread value (angle)
	-- Each ray is then inserted inside the resultTable to be stored and fired to the server if it hits a humanoid
	for i = 1, self.rayCount do
		local origin = camera.CFrame.Position
		
		local spreadAngle = math.rad(self.spread)
		
		-- Randomize spread angle for each ray by getting a random number from -1 to 1
		-- math.random() returns a number between 0 and 1 with decimals, but subtracting 0.5 shifts it to -0.5 to 0.5
		-- Multiplying it to 2 then turns the range into -1 to 1, and multiplying it to the spreadAngle scales it
		-- The reason for this is because math.random(-1, 1) only returns integers, not decimals (-1,0, and 1)
		-- The decimals are needed for the spread to look smoother and more natural
		local randomX = (math.random() - 0.5) * 2 * spreadAngle
		local randomY = (math.random() - 0.5) * 2 * spreadAngle
		
		-- Angle is set based off the camera so the origin wont be rotated as well and still stays on the camera
		local spreadCFrame = camera.CFrame * CFrame.Angles(randomY, randomX, 0)
		
		-- The direction is then based off the look vector of that camera's cframe with the spread angle included
		local direction = spreadCFrame.LookVector * self.maxRange

		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = {character}

		local raycastResult = workspace:Raycast(origin, direction, raycastParams)
		
		-- VISUAL RAYCAST (FOR DEBUGGING)
		--[[local part = Instance.new("Part")
		part.Size = Vector3.new(0.1, 0.1, (origin - direction).Magnitude)
		part.CFrame = spreadCFrame * CFrame.new(0, 0, -part.Size.Z / 2)
		part.Anchored = true
		part.Parent = workspace
		game.Debris:AddItem(part, 5)]]
		
		if not raycastResult then continue end
		
		table.insert(resultTable, raycastResult)
	end
	
	for _, result in resultTable do
		local resultInstance = result.Instance
		local resultPosition = result.Position
		local resultNormal = result.Normal -- Calculates the outwards face of the surface thas was hit by the raycast
		
		-- For results that only hit a humanoid
		if resultInstance.Parent:FindFirstChild("Humanoid") then
			bulletRaycastEvent:FireServer(
				resultInstance.Parent.Humanoid,
				self.damage
			)
		else
			-- For results that both hit and dont hit anything as long as its not a humanoid
			local bulletHole = ReplicatedStorage.BulletHoles.NormalHole:Clone()

			-- The bullethole part is set to the position where the raycast landed
			-- It's then rotated outwards of the surface the raycast hit relative to raycast land position
			-- It's relative to the raycast land position (resultposition) which is why its added to it
			bulletHole.CFrame = CFrame.new(resultPosition, resultPosition + resultNormal)

			bulletHole.Parent = workspace

			game.Debris:AddItem(bulletHole, 5)
		end
	end
	
	self:SetRecoil()
end

function WeaponHandler:Aim()
	if self.isReloading then return end
	self.isAiming = true
	
	self.recoil = self.recoil / 2 -- Halves the recoil
	self.recoilRecoveryLerpSpeed = self.recoilRecoveryLerpSpeed * 2 -- Makes recoil recovery 2x faster
end

function WeaponHandler:Unaim()
	if not self.isAiming then return end
	
	self.isAiming = false
	self.recoil = self.recoil * 2 -- Set recoil back to normal
	self.recoilRecoveryLerpSpeed = self.recoilRecoveryLerpSpeed / 2 -- Set recoil recovery back to normal
end

function WeaponHandler:Reload()
	if self.isShooting then return end
	if self.isAiming then return end
	if self.isReloading then return end
	self.isReloading = true
	
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	
	self.currentAmmo = self.maxAmmo
	
	ammoAmount.Text = "..." .. "/" .. self.maxAmmo
	
	local track = self:PlayAnimation("Reload")
	
	track.Stopped:Connect(function()
		self.isReloading = false
		self:SetHUD()
		
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
	end)
	
	self:PlaySound("Reload")
end

function WeaponHandler:OnUnequip()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	
	self.viewmodel:Destroy()
	self.connections = {}
	self.savedAmmoTable[self.weaponName] = self.currentAmmo
	self:SetHUD()
	
	hud.Enabled = false
end

--// UTILITY FUNCTIONS
function WeaponHandler:SetViewmodel()
	self.viewmodel = ReplicatedStorage.WeaponViewmodels[self.weaponName]:Clone()
	self.viewmodel.Parent = camera
	
	-- Moves the viewmodel to the distance and direction from aimpart's position to the viewmodel's position
	-- This way the aimpart is at the camera's position, and not the fakecamera
	local aimOffset = self.viewmodel.AimPart.CFrame:ToObjectSpace(self.viewmodel.PrimaryPart.CFrame)
	local currentOffset = CFrame.new()
	
	local bobSpeed = 0
	local bobOffset = CFrame.new()
	local currentBobOffset = CFrame.new()
	
	-- Since the camera isnt a basepart and you cant viewmodel to it, repeatedly set viewmodel's cframe to the camera's cframe
	self.connections["Viewmodel"] = RunService.RenderStepped:Connect(function(deltaTime)
		
		-- AIMING
		if self.isAiming then
			currentOffset = currentOffset:Lerp(aimOffset, deltaTime * self.aimSpeed)
		else 
			currentOffset = currentOffset:Lerp(CFrame.new(), deltaTime * self.aimSpeed)
		end
		
		-- BOBBING
		local canBob = humanoid.MoveDirection.Magnitude > 0 and humanoid.FloorMaterial ~= Enum.Material.Air and not self.isAiming
		
		if canBob then
			-- Can go up super high values when walking for too long but it doesnt matter since it doesnt affect anything and resets back to 0 when you stop anyway
			bobSpeed += deltaTime * self.bobSpeedMultiplier
		else
			bobSpeed = 0
		end
		
		-- X axis math.sin moves it side to side from 0 while y axis math.sin moves it up and down from 0
		-- Y axis math.sin moves it up and down because math.abs makes it so it goes 0 - 1 - 0 - 1 instead of 0 - 1 - 0 - (-1) by getting the absolute value (disregards negatives and automatically makes them positive) which means it'll only go from middle to up and back to the middle
		-- The multiplier is to make bobbing more or less extreme (multiplied to the result iself so bobspeed is still consistent)
		bobOffset = CFrame.new(math.sin(bobSpeed) * self.bobAmountMultiplier, math.abs(math.sin(bobSpeed)) * self.bobAmountMultiplier, 0)
		
		-- Lerp to the bob offset smoothly (since bobbing starts from 0 anyway, its mostly for when you stop walking so it transitions smoothly)
		currentBobOffset = currentBobOffset:Lerp(bobOffset, deltaTime * self.bobTransitionLerpSpeed)
		
		self.viewmodel:PivotTo(camera.CFrame * currentOffset * currentBobOffset)
	end)
end

function WeaponHandler:SetRecoil()
	-- Guard check just in case multiple run service connections stack on top of each other
	if self.connections["Recoil"] then
		self.connections["Recoil"]:Disconnect()
		self.connections["Recoil"] = nil
	end
	
	local alpha = 0
	local recoveryAlpha = 0
	local totalRecoil = 0
	local recovery = false

	self.connections["Recoil"] = RunService.RenderStepped:Connect(function(deltaTime)
		if not recovery then
			local oldCameraCFrame = camera.CFrame
			
			camera.CFrame = camera.CFrame:Lerp(camera.CFrame * CFrame.Angles(math.rad(self.recoil), 0, 0), deltaTime * self.recoilLerpSpeed)
			
			-- Track totalRecoil applied each frame for recoil recovery
			-- This is because lerping is inconsistent and poop (overshoots when lerpspeed too fast, more accurate when slow)
			-- So if recoil isnt tracked, it'll go higher than self.recoils value and on recovery it'll be exactly self.recoils value because of its slower lerpspeed
			-- Find difference of old camera cframe and current camera cframe in terms of rotation (euleranglesxyz)
			-- Then only get the X axis because that was the only angle that was touched while lerping
			local rotationX, _, _ = (oldCameraCFrame:ToObjectSpace(camera.CFrame)):ToEulerAnglesXYZ()
			totalRecoil += math.deg(rotationX) -- math.deg is just preference as well as for easier debugging (for me)

			alpha += deltaTime * self.recoilLerpSpeed
			
			if alpha < 1 then return end
			
			recovery = true
		else
			-- Lerp back to normal (inverse of total recoil)
			camera.CFrame = camera.CFrame:Lerp(camera.CFrame * CFrame.Angles(math.rad(-totalRecoil), 0, 0), deltaTime * self.recoilRecoveryLerpSpeed)
			
			recoveryAlpha += deltaTime * self.recoilRecoveryLerpSpeed

			if recoveryAlpha < 1 then return end
			
			self.connections["Recoil"]:Disconnect()
			self.connections["Recoil"] = nil
		end
	end)
end

function WeaponHandler:SetHUD()
	hud.Enabled = true
	
	ammoAmount.Text = self.currentAmmo .. "/" .. self.maxAmmo
end

function WeaponHandler:PlayAnimation(animName)
	local animator = self.viewmodel.AnimationController.Animator
	local animationTrack = animator:LoadAnimation(self.weaponModule.Anims[animName])
	
	animationTrack:Play()
	
	return animationTrack
end

function WeaponHandler:PlaySound(soundName)
	local sound = self.weaponModule.SFX[soundName]:Clone()
	sound.Parent = self.viewmodel
	
	sound:Play()
	
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

return WeaponHandler
