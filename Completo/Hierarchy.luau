--!optimize 2

local ServicesToScan = {
	game:GetService("ServerScriptService"),
	game:GetService("ReplicatedStorage"),
	game:GetService("ReplicatedFirst"),
	game:GetService("ServerStorage"),
	game:GetService("StarterPlayer"),
	game:GetService("StarterPack"),
	game:GetService("StarterGui"),
	workspace
}

local GREAT = "^[%a_][%w_]*$"
local SPACE = "^[%a_ %-][%w_ %-]*$"
local PLACEHOLDER = "[- ]"
local SPACEHOLDER = "_"

local insert = table.insert
local find = string.find
local gsub = string.gsub

local GetChildren = game.GetChildren
local GetFullName = game.GetFullName
local IsA = game.IsA

local function Safetify(name: string)
	if find(name, GREAT) then
		return name
	elseif find(name, SPACE) then
		return gsub(name, PLACEHOLDER, SPACEHOLDER)
	end
end

local function GetDescendants()
	local out = {}
	local stack, stackSize = {}, 0
	
	for _, obj in GetChildren(game:GetService("ReplicatedStorage")) do
		stackSize += 1
		stack[stackSize] = obj
	end

	while stackSize > 0 do
		local current = stack[stackSize]
		stack[stackSize] = nil
		stackSize -= 1

		if not current:IsA('ModuleScript') then
			insert(out, current)
		end

		if IsA(current, "Folder") or IsA(current, "Configuration") then
			for _, obj in GetChildren(current) do
				stackSize += 1
				stack[stackSize] = obj
			end
		end
	end

	return out
end

local function GetModules()
	local modules = {}
	for _, service in ServicesToScan do
		for _, descendant in service:GetDescendants() do
			if IsA(descendant, "ModuleScript") then
				insert(modules, descendant)
			end
		end
	end
	return modules
end

local function ReadifyCustom(activeScript: Instance, list: {Instance})
	local result = {}

	for i = 1, #list do
		local object = list[i]
		if object == activeScript then continue end

		local fixedName = Safetify(object.Name)
		if not fixedName then continue end

		local rawPath, cleanPath, realPath = {}, {}, {}
		local valid = true
		local current = object

		while current and current.Parent do
			local safeSeg = Safetify(current.Name)
			if not safeSeg then
				valid = false
				break
			end
			insert(rawPath, 1, current.Name)
			insert(cleanPath, 1, safeSeg)
			insert(realPath, 1, current)
			current = current.Parent
		end

		if valid then
			local data = {
				Desc = `-> {GetFullName(object)}`,
				Tree = rawPath,
				Clean = cleanPath,
				Real = realPath
			}
			local bucket = result[object.Name]
			if bucket then
				insert(bucket, data)
			else
				result[object.Name] = { data }
			end
		end
	end
	return result
end

local function GetReal(object: Instance?): {string}
	local path = {}
	while object and object.Parent do insert(path, 1, object) object = object.Parent end
	return path
end

return {
	GetAllShared  = function(activeScript) return ReadifyCustom(activeScript, GetDescendants()) end,
	GetAllModules = function(activeScript) return ReadifyCustom(activeScript, GetModules()) end,
	Safetify      = Safetify,
	GetReal       = GetReal
}
