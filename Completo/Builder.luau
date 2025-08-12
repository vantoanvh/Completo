--!optimize 2

local ServerScriptService = game:GetService('ServerScriptService')
local ServerStorage = game:GetService('ServerStorage')

local Hierarchy = require'./Hierarchy'
local Parser = require'./Parser'

local tableConcat = table.concat
local tableInsert = table.insert
local tableSort = table.sort
local stringRep = string.rep

type Clean = {string}
type Real = {Instance}
type Tree = {string}

local function getRequirePathString(ActiveScript, activePath, targetPath)
	local useSelf = false
	local selfParts = {}
	
	for i = 1, #targetPath - 1 do
		if useSelf then
			tableInsert(selfParts, targetPath[i].Name)
		end
		if targetPath[i] == ActiveScript then
			useSelf = true
		end
	end
	
	if useSelf then
		local path = '@self'
		if #selfParts > 0 then
			path ..= '/' .. tableConcat(selfParts, '/')
		end
		return path .. '/' .. targetPath[#targetPath].Name
	end
	
	local common = 0
	for i = 1, math.min(#activePath, #targetPath) do
		if activePath[i] ~= targetPath[i] then break end
		common = i
	end
	
	local upCount = #activePath - common
	local downParts = {}
	for i = common + 1, #targetPath - 1 do
		tableInsert(downParts, targetPath[i].Name)
	end
	
	local dots = '.' .. stringRep('.', upCount - 1)
	local path = dots
	if #downParts > 0 then
		path ..= '/' .. tableConcat(downParts, '/')
	end
	return path .. '/' .. targetPath[#targetPath].Name
end

local function FindComplete(Class: Parser.Class, Length: number)
	local At = 8e8
	local found = false
	
	for Name, Line in Class.Map do
		if #Name < Length and Line < At then
			At = Line
			found = true
		end
	end
	
	if found then
		return At
	else
		if next(Class.Map) then
			return Class.Last + 1
		end
	end
end


local function BuildService(Registry: Parser.Registry, Value: string, Ended: number)
	
	if Registry.Services.Map[Value] then return end
	
	local At = FindComplete(Registry.Services, #Value)
	Parser.AddService(Registry, At or Ended, Value)
	
end

local function BuildTree(Registry: Parser.Registry, Tree: Tree, Clean: Clean, Real: Real, Ended: number)
	
	BuildService(Registry, Tree[1], Ended)
	
	local IsServer = Real[1] == ServerStorage or Real[1] == ServerScriptService
	
	local Sers = Registry.Services
	local Last = Sers.Last
	local Ins = Registry.Ins
	
	for Index, CNode in Clean do
		if Index > 1 then
			local TNode = Tree[Index]
			local CRoot = Clean[Index - 1]
			
			local Class = Ins[CRoot]
			
			if Class and Class.Map[TNode] then Last = Class.Last continue end
			
			local Edit if IsServer then
				if TNode ~= CNode then
					Edit = `local {CNode} = {CRoot}['{TNode}']`
				else
					Edit = `local {CNode} = {CRoot}.{TNode}`
				end
			else
				Edit = `local {CNode} = {CRoot}:WaitForChild('{TNode}')`
			end
			
			local At = Class and FindComplete(Class, #CNode) or Sers[CRoot]

			if not At then
				local ParentLen = #CRoot
				
				local Existance = {}

				for _, Obj in Real[Index - 1].Parent:GetChildren() do
					local Class = Ins[Obj.Name]
					if Class then tableInsert(Existance, {len = #Obj.Name, line = Class.Last}) end
				end

				tableSort(Existance, function(a, b) return a.len < b.len end)

				for _, Obj in Existance do
					if Obj.len > ParentLen then
						Parser.AddLine(Registry, Obj.line + 1)
						At = Obj.line + 2
						break
					end
				end

				if not At then
					Parser.AddLine(Registry, Last + 1)
					At = Last + 2
				end
			end
			
			Parser.AddInstance(Registry, At, TNode, CRoot, Edit)
			Last = Ins[CRoot].Last or Last + 2
		end
	end
end

local function BuildModule(Registry: Parser.Registry, ActiveScript: BaseScript, Tree: Tree, Clean: Clean, Real: Real, Ended: number)
	local ActivePath = Hierarchy.GetReal(ActiveScript)
	
	if ActivePath[1] == Real[1] then
		local Node = Clean[#Clean]

		local Edit = `local {Node} = require('{getRequirePathString(ActiveScript, ActivePath, Real)}')`
		
		local At = FindComplete(Registry.String, #Node)
		
		if not At then
			Parser.AddLine(Registry, Registry.Last + 1)
			At = Registry.Last + 1
		end
		
		Parser.AddModule(Registry, 'String', At, Tree[#Tree], Edit)
	else
		local IsServer = Real[1] == ServerStorage or Real[1] == ServerScriptService
		
		local onRemove
		local TimesToRemove = 0

		for i, v in Real do
			if i ~= #Real and v:IsA("ModuleScript") then
				onRemove = Tree[i - 1]
			end
			if onRemove then
				local nodeName = Tree[i]
				if IsServer then
					if nodeName == Clean[i] then
						onRemove ..= `.{nodeName}`
					else
						onRemove ..= `['{nodeName}']`
					end
				else
					onRemove ..= `:WaitForChild('{nodeName}')`
				end
				TimesToRemove += 1
			end
		end
		
		local OriginalModule = table.remove(Tree)
		local OriginalName = table.remove(Clean)
		
		for i = 1, TimesToRemove - 1 do
			table.remove(Clean)
			table.remove(Tree)
		end

		if #Tree == 1 then
			BuildService(Registry, Tree[1], Ended)
		else
			BuildTree(Registry, Tree, Clean, Real, Ended)
		end
		
		local Edit = `local {OriginalName} = require({onRemove or (
			IsServer and (
				OriginalModule ~= OriginalName and `{Clean[#Clean]}['{OriginalModule}']` or `{Clean[#Clean]}.{OriginalModule}`
			) or `{Clean[#Clean]}:WaitForChild('{OriginalModule}')`
		)})`

		local At = FindComplete(Registry.Index, #OriginalName)
		if not At then
			local Last = next(Registry.String.Map)
			if Last then
				local Counts = 1
				for _ in Registry.String.Map do
					Counts += 1
				end
				Last = Registry.Last - Counts
			else
				Last = Registry.Last
			end

			Parser.AddLine(Registry, Last + 1)
			At = Last + 2
		end

		Parser.AddModule(Registry, 'Index', At, OriginalModule, Edit)
	end

	local useWhat
end

return {
	BuildService = BuildService;
	BuildModule = BuildModule;
	BuildTree = BuildTree;
}
