--!optimize 2

-- || Services || -- 

local ScriptEditorService = game:GetService'ScriptEditorService'
local StudioService       = game:GetService'StudioService'

-- || Modules || --

local Hierarchy    = require'@self/Hierarchy'
local Parser       = require'@self/Parser'
local Language     = require'@self/Language'
local Finder       = require'@self/Finder'
local Builder      = require'@self/Builder'

-- || Localization || -- 

local ActiveScript  = StudioService.ActiveScript

local GetAllModules = Hierarchy.GetAllModules
local GetAllShared  = Hierarchy.GetAllShared

local Directives    = Language.Directives
local Attributes    = Language.Attributes
local Services      = Language.Services
local Linting       = Language.Linting

-- || Optimizations || -- 

local CompleteKind  = Enum.CompletionItemKind.Snippet

local tableConcat   = table.concat
local tableInsert   = table.insert
local tableCreate   = table.create

local stringLower   = string.lower
local stringSplit   = string.split
local stringFind    = string.find
local stringByte    = string.byte
local stringSub     = string.sub

local AddItems = function(Items, Name, Replace, Dictionary)
	local Edit = Dictionary.Edit or Name
	
	local Item = {
		textEdit      = {newText = Edit, replace = Replace},
		documentation = {value = Dictionary.Desc},
		codeSample    = Dictionary.Sample,
		
		kind        = CompleteKind,
		detail      = Name,
		label       = Name,
		edit        = Edit,
	}
	
	if not Dictionary.Comment then
		Item.textEdit.replace.start = {line = 1, character = 1}
	end
	
	tableInsert(Items, Item)
end

local function deepcopy(t)
	local copy = table.clone(t)
	for k, v in t do
		if type(v) == "table" then
			copy[k] = deepcopy(v)
		end
	end
	return copy
end

local onCommentSpecial = function(LineText, Replace, RealItem)
	if stringSub(LineText, 1, 3) == '--!' then
		local Length = #LineText
		
		Replace.start.character -= Length
		
		for Name, Dict in Directives do AddItems(RealItem, Name, Replace, Dict) end
		
		if Length <= 9 or stringSub(LineText, 4, 10) ~= 'nolint ' then return LineText end
		
		for Name, Dict in Linting do AddItems(RealItem, Name, Replace, Dict) end
		
		return LineText
	end
end

local onAttributeSpecial = function(NameWS, Replace, RealItem)
	if stringByte(NameWS) == 64 then
		Replace.start.character -= #NameWS - 1
		
		table.clear(RealItem)
		
		for Name, Dict in Attributes do AddItems(RealItem, Name, Replace, Dict) end
		
		return NameWS
	end
end

local onAutocompleteUpdate = function(request, response)
	local c = os.clock()
	local Document = request.textDocument.document
	local Position = request.position
	local RealItem = response.items
	local Char = Position.character
	local Line = Position.line
	
	if Document:GetScript() ~= ActiveScript or Document:IsCommandBar() then return response end
	
	local LineText = stringSub(Document:GetLine(Line), 1, Char - 1)
	
	local _, _, NameWS = stringFind(LineText, "([^%s]*)$")
	local _, _, NameAW = stringFind(LineText, "([%w]+)$")
	
	local Replace = {
		["start"] = { line = Line, character = Char },
		["end"]   = { line = Line, character = Char },
	}
	
	if onCommentSpecial(LineText, Replace, RealItem) then return response end
	if onAttributeSpecial(NameWS, Replace, RealItem) then return response end
	
	if #RealItem < 2 then return response end
	
	if not NameAW or stringFind(NameWS, '^[.:]') then return response end
	
	local CheckDict = {}
	
	for _, v in RealItem do
		if v.kind == Enum.CompletionItemKind.Text then
			return response
		elseif v.kind == Enum.CompletionItemKind.Property then
			return response
		elseif v.kind == Enum.CompletionItemKind.Method then
			return response
		elseif v.kind == Enum.CompletionItemKind.Event then
			return response
		end
		CheckDict[v.label] = true
	end
	
	local Ended = Finder(Document)
	
	if not Ended then return response end
	
	local Length = #NameAW
	
	local Registry = Parser.Parse(Document:GetText(1, 1, Line, Char - Length), Ended - 1)
	
	local Replace = {
		["start"] = { line = 1, character = 1 },
		["end"]   = { line = Line, character = Char },
	}
	
	local Fixed = stringLower(NameAW)
	
	for Name, Dict in Services do
		if Registry.Services.Map[Name] then continue end
		if Fixed ~= stringSub(Dict.Lower, 1, Length) then continue end
		
		local Cloned = deepcopy(Registry)
		
		Builder.BuildService(Cloned, Name, Ended)
		
		local Text = Parser.Decode(Cloned)
		
		tableInsert(RealItem, {
			textEdit      = {newText = Text..Name, replace = Replace},
			documentation = {value = Dict.Desc},
			codeSample    = Dict.Sample,

			kind        = CompleteKind,
			detail      = Name,
			label       = Name,
		})
	end
	
	for Name, Dict in GetAllShared(ActiveScript) do
		if CheckDict[Name] then continue end
		if Fixed ~= stringSub(stringLower(Name), 1, Length) then continue end
		
		for _, Desc in Dict do
			local Cloned = deepcopy(Registry)
			
			Builder.BuildTree(Cloned, Desc.Tree, Desc.Clean, Desc.Real, Ended)
			
			local Text = Parser.Decode(Cloned)
			
			tableInsert(RealItem, {
				textEdit      = {newText = Text..Name, replace = Replace},
				documentation = {value = Desc.Desc},
				kind        = CompleteKind,
				detail      = Name,
				label       = Name,
			})
		end
	end
	
	for Name, Dict in GetAllModules(ActiveScript) do
		if CheckDict[Name] then continue end
		if Fixed ~= stringSub(stringLower(Name), 1, Length) then continue end
		
		for _, Desc in Dict do
			local Cloned = deepcopy(Registry)

			Builder.BuildModule(Cloned, ActiveScript, Desc.Tree, Desc.Clean, Desc.Real, Ended)

			local Text = Parser.Decode(Cloned)
			
			tableInsert(RealItem, {
				textEdit      = {newText = Text..Name, replace = Replace},
				documentation = {value = Desc.Desc},
				kind        = CompleteKind,
				detail      = Name,
				label       = Name,
			})
		end
	end

	return response
end

local onCleaning = function()
	pcall(ScriptEditorService.DeregisterAutocompleteCallback, ScriptEditorService, 'Completo')
end

local Connecting = function()
	ActiveScript = StudioService.ActiveScript; onCleaning()

	if ActiveScript and ActiveScript.Parent ~= game then
		ScriptEditorService:RegisterAutocompleteCallback('Completo', 3, onAutocompleteUpdate)
	end
end

local onUnloading = function()
	if ActiveConn then ActiveConn:Disconnect() end onCleaning()
end

-- || Initialization || -- 

for Name, Desc in Services do
	Services[Name] = {
		Sample = `local {Name} = game:GetService('{Name}')`,
		Lower  = stringLower(Name),
		Desc   = Desc,
		Edit   = Name,
	}
end

for Name, Desc in Directives do
	Directives[Name] = {
		Edit  = `--!{Name}`,
		Comment = true,
		Lower = Name,
		Desc  = Desc,
	}
end

for Name, Desc in Attributes do
	Attributes[Name] = {
		Edit  = Name,
		Comment = true,
		Lower = Name,
		Desc  = Desc,
	}
end

for Name, Desc in Linting do
	Linting[Name] = {
		Edit  = `--!nolint {Name}`,
		Comment = true,
		Desc  = Desc,
	}
end

-- || Functions || -- 

ActiveConn = StudioService:GetPropertyChangedSignal('ActiveScript'):Connect(Connecting)
plugin.Unloading:Connect(onUnloading)
Connecting()
