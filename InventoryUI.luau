-- Discord: lwfss | Roblox: lowpowermode123

--[[
	Custom Inventory UI System (Based on roblox's default backpack system)
	
	Features:
	- Hotbar with fixed slots
	- Drag and drop system
	- Keybind/click based equipping
	- Search bar
]]

-- Disable default roblox backpack
game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

--// VARIABLES
local player = game.Players.LocalPlayer
local playerGui = player.PlayerGui
local character = player.Character

local oldParent = nil
local dragConnection = nil
local draggingItem = nil

--// SERVICES
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

--// GUI
local inventoryGui = playerGui:WaitForChild("Inventory")
local holderFrame = inventoryGui.HolderFrame

local slotTemplate = inventoryGui.Slot
local itemTemplate = inventoryGui.Item

local hotbarContainer = holderFrame.HotbarContainer
local hotbarFrame = hotbarContainer.HotbarFrame

local inventoryContainer = holderFrame.InventoryContainer
local inventoryFrame = inventoryContainer.InventoryFrame
local inventoryScrollingFrame = inventoryFrame.InventoryScrollingFrame
local inventorySearchBar = inventoryFrame.SearchBar

--// CONFIGS
local NUMBER_OF_SLOTS = 10
local DISTANCE_BEFORE_DRAG = 5 -- Pixels between mouse and item when dragging

--// TABLES
local keyTexts = {
	"1",
	"2",
	"3",
	"4",
	"5",
	"6",
	"7",
	"8",
	"9",
	"0"
}
local keyInputs = {
	One = 1,
	Two = 2,
	Three = 3,
	Four = 4,
	Five = 5,
	Six = 6,
	Seven = 7,
	Eight = 8,
	Nine = 9,
	Zero = 0
}

local inventoryTable = {}

--// FUNCTIONS
local function ToggleInventory()
	local toggled = not inventoryFrame.Visible
	inventoryFrame.Visible = toggled
	
	-- Only toggle empty slots, occupied slots stay visible whether toggled or not so items are always shown
	for _, slot in hotbarFrame:GetChildren() do
		if not slot:IsA("Frame") then continue end
		if slot:FindFirstChildOfClass("TextButton") then continue end
		
		slot.Visible = toggled
	end
end

local function EquipOrUnequipTool(itemName)
	local tool = character:FindFirstChild(itemName) or player.Backpack:FindFirstChild(itemName)
	if not tool then return end
	
	if tool.Parent == character then
		tool.Parent = player.Backpack
	else
		-- Unequip all tools before equipping another one
		character.Humanoid:UnequipTools()
		tool.Parent = character
	end
end

local function StartDragging(item)
	-- Disconnect before creating a new connection to prevent stacking on double click
	if dragConnection then
		dragConnection:Disconnect()
		dragConnection = nil
	end
	
	oldParent = item.Parent
	draggingItem = item
	
	local oldMousePos = UserInputService:GetMouseLocation()
	dragConnection = RunService.RenderStepped:Connect(function()
		-- Cancel drag if inventory closes mid drag
		if not inventoryFrame.Visible then
			dragConnection:Disconnect()
			dragConnection = nil
			draggingItem = nil
			item.Parent = oldParent
			item.Position = UDim2.new(0.5, 0, 0.5, 0)
			return 
		end
		
		local mousePos = UserInputService:GetMouseLocation()
		local magnitude = (mousePos - oldMousePos).Magnitude
		
		-- If mouse is moved enough according to DISTANCE_BEFORE_DRAG, move item (avoids dragging on clicks)
		if magnitude >= DISTANCE_BEFORE_DRAG then
			item.Parent = holderFrame
			item.Position = UDim2.new(0, mousePos.X, 0, mousePos.Y)
		end
	end)
end

local function EndDragging()
	if not dragConnection then return end
	dragConnection:Disconnect()
	dragConnection = nil
	
	local item = draggingItem
	
	if not item then return end
	draggingItem = nil
	
	-- GetGuiObjectsAtPosition includes guiinset so its subtracted in order to align correctly
	local guiInset = GuiService:GetGuiInset()
	local mousePos = UserInputService:GetMouseLocation() - guiInset
	local guiUnderMouse = playerGui:GetGuiObjectsAtPosition(mousePos.X, mousePos.Y)
	
	local dropped = false
	for _, gui in guiUnderMouse do
		if gui == item then continue end
		
		-- Drop the item according to what gui its hovered on (inventory, hotbar, or nothing)
		if gui.Name == "InventoryScrollingFrame" or gui.Name == "Slot" then
			dropped = true
			item.Parent = gui
			item.Position = UDim2.new(0.5, 0, 0.5, 0)
			break
		elseif gui:IsA("TextButton") then
			dropped = true
			item.Parent = gui.Parent
			gui.Parent = oldParent
			item.Position = UDim2.new(0.5, 0, 0.5, 0)
			break
		end
	end
	
	-- If none of the conditions are met through all iterations, reparent item to original parent
	if not dropped then
		item.Parent = oldParent
		item.Position = UDim2.new(0.5, 0, 0.5, 0)
	end
end

-- Created according to layout order so items can be placed reliably
-- Sets slot visible/invisible based on if there is a child in the slot
local function CreateSlot(layoutOrder)
	local slot = slotTemplate:Clone()
	slot.LayoutOrder = layoutOrder
	slot.Key.Text = keyTexts[layoutOrder]
	slot.Parent = hotbarFrame
	
	slot.ChildAdded:Connect(function(child)
		if not child:IsA("TextButton") then return end
		if inventoryFrame.Visible then return end

		slot.Visible = true
	end)
	
	slot.ChildRemoved:Connect(function(child)
		if not child:IsA("TextButton") then return end
		if inventoryFrame.Visible then return end

		slot.Visible = false
	end)
end

local function CreateItem(child)
	local item = itemTemplate:Clone()
	item.Name = child.Name
	item.Text = child.Name

	item.MouseButton1Click:Connect(function()
		EquipOrUnequipTool(child.Name)
	end)
	
	item.MouseButton1Down:Connect(function()
		StartDragging(item)
	end)

	local parented = false

	-- Iterate in layout order so the first empty slot it comes across will be its parent
	for i = 1, NUMBER_OF_SLOTS do
		if parented then break end

		for _, slot in hotbarFrame:GetChildren() do
			if not slot:IsA("Frame") then continue end
			if slot.LayoutOrder ~= i then continue end
			if slot:FindFirstChildOfClass("TextButton") then continue end

			item.Parent = slot
			item.Visible = true
			parented = true
			break
		end
	end

	-- If not parented it means the hotbar is full, so parent to the inventory instead
	if parented then return end
	item.Parent = inventoryScrollingFrame
	item.Visible = true
end

-- Adds a tool to the inventory if it isnt already tracked
-- Uses the tool's name as a key (NOTE: this assumes unique tool names)
local function AddToInventory(child)
	-- Prevent duplication from happening due to backpack and character events
	if inventoryTable[child.Name] then return end
	inventoryTable[child.Name] = child
	
	CreateItem(child)
end

local function RemoveFromInventory(child)
	inventoryTable[child.Name] = nil

	local item = inventoryGui:FindFirstChild(child.Name, true)

	if not item then return end
	item:Destroy()
end

-- Searches for a tool in the inventory and only shows the ones that match the letters in order
local function SearchForItem(searchText)
	local searchText = searchText:lower()
	
	-- If searchbar is empty, show all items
	if searchText == "" then
		for _, invisibleItem in inventoryScrollingFrame:GetChildren() do
			if not invisibleItem:IsA("TextButton") then continue end
			if invisibleItem.Visible then continue end

			invisibleItem.Visible = true
		end
	end
	
	-- Match the searchbar text with the item name based on matching letters
	for _, item in inventoryScrollingFrame:GetChildren() do
		if not item:IsA("TextButton") then continue end

		local matchingStrings = string.find(item.Text:lower(), searchText)

		if matchingStrings then
			item.Visible = true
		else
			item.Visible = false
		end
	end
end

--// LOGIC

-- Enable inventory screengui on spawn
inventoryGui.Enabled = true

-- Searching
inventorySearchBar:GetPropertyChangedSignal("Text"):Connect(function()
	SearchForItem(inventorySearchBar.Text)
end)

-- Create slots 
for i = 1, NUMBER_OF_SLOTS do
	CreateSlot(i)
end

-- Item added or removed from backpack
player.Backpack.ChildAdded:Connect(function(child)
	if not child:IsA("Tool") then return end
	
	AddToInventory(child)
end)

player.Backpack.ChildRemoved:Connect(function(child)
	if not child:IsA("Tool") then return end
	if character:FindFirstChild(child.Name) then return end -- If item is in character, dont remove from inv
	
	RemoveFromInventory(child)
end)

-- Item added or removed from character
character.ChildAdded:Connect(function(child)
	if not child:IsA("Tool") then return end

	AddToInventory(child)
end)

character.ChildRemoved:Connect(function(child)
	if not child:IsA("Tool") then return end
	if player.Backpack:FindFirstChild(child.Name) then return end -- If item is in backpack, dont remove from inv

	RemoveFromInventory(child)
end)

-- Input handling
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	
	if input.KeyCode == Enum.KeyCode.Backquote then
		ToggleInventory()
	end
	
	local hotbarKeyInput = keyInputs[input.KeyCode.Name]
	if not hotbarKeyInput then return end
	
	for _, slot in hotbarFrame:GetChildren() do
		if not slot:IsA("Frame") then continue end
		if slot.LayoutOrder ~= tonumber(hotbarKeyInput) then continue end
		
		local item = slot:FindFirstChildOfClass("TextButton")
		if not item then return end
		
		EquipOrUnequipTool(item.Name)
	end
end)

-- Stop dragging on mouse release
-- Avoids issues with the mouse not being on top of the item when dragging (which is why mousebutton1up isnt used)
UserInputService.InputEnded:Connect(function(input, gpe)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		EndDragging()
	end
end)
