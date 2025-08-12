--!optimize 2

--// Caches //--

local table_insert = table.insert
local table_concat = table.concat
local string_find = string.find
local string_sub = string.sub

--// Types //--

export type SourceCode = {string};

export type Map = {[string]: number};

export type Class = {
	Last: number;
	Map: Map;
}

export type Lookup = {
	[string]: Class
}

export type Registry = {
	Source: SourceCode;
	
	Services: Class;
	String: Class;
	Index: Class;
	Ins: Lookup;
	
	Last: number;
}

--// Strings //--

local TARGET1 = ":WaitForChild%(([\"'`])([^\"'`]+)%1%)$"
local TARGET2 = '%[(["\'`])(.-)%1%]$'
local TARGET3 = '%.([%a_][%w_]*)$'

local INSFORM = '^local%s*([%w_]+)%s*=%s*(.*)'
local SERFORM = '^local%s*[%w_]+%s*=%s*game%s*:%s*GetService%s*%((["\'`])(%a+)%1%)'
local SERFORM = '^local%s*[%w_]+%s*=%s*game%s*:%s*GetService%s*%((["\'`])(%a+)%1%)'

local MODFOR1 = '^local%s+[%w_]+%s*=%s*require%s*%((["\'`])(.+)%1%)'
local MODFOR2 = '^local%s+[%w_]+%s*=%s*require%s*%((.+)%)'

local PATH = '^([%a_][%w_]+)'
local STR = '([^/]+)$'

local PREFIX = 'local '
local LINE = '\n'
local NON = ''

--// Extraction //--

local TargetCaches = {}

local function ExtractTarget(Text: string): string?
	
	if TargetCaches[Text] then return TargetCaches[Text] end
	
	local _, _, _, Target = string_find(Text, TARGET1)
	if Target then TargetCaches[Text] = Target return Target end

	local _, _, _, Target = string_find(Text, TARGET2)
	if Target then TargetCaches[Text] = Target return Target end

	local _, _, Target = string_find(Text, TARGET3)
	if Target then TargetCaches[Text] = Target return Target end
	
end

local ParentCaches = {}

local function ExtractPath(Text: string): (string, string?)
	
	if ParentCaches[Text] then return ParentCaches[Text], ExtractTarget(Text) end
	
	local _, _, Parent = string_find(Text, PATH)
	
	if Parent then
		ParentCaches[Text] = Parent
	end
	
	return Parent, ExtractTarget(Text)
	
end

local function ExtractString(Text: string): string
	
	local _, _, Value = string_find(Text, STR)
	return Value
	
end

--// Utilities //--

local function ShiftMap(Class: Class, At: number, FN)
	for Name, Line in Class.Map do
		if Line >= At then
			Class.Map[Name] = Line + 1
		end
	end
	Class.Last += 1
end

local function ShiftLinesAfter(Reg: Registry, At: number)
	ShiftMap(Reg.Services, At)
	ShiftMap(Reg.String, At)
	ShiftMap(Reg.Index, At)
	
	Reg.Last += 1

	for _, Class in Reg.Ins do ShiftMap(Class, At) end
end

local function AddClass(Class: Class, At: number, Value: string): ()
	
	Class.Map[Value] = At
	if Class.Last < At then Class.Last = At end
	
end

local function AddLookup(Lookup: Lookup, At: number, Value: string, Parent: string): ()
	
	local Class = Lookup[Parent]
	if Class then
		AddClass(Class, At, Value, Parent)
	else
		Lookup[Parent] = {Last = At, Map = {[Value] = At}}
	end
	
end

--// Reader //--

local InsCaches = {}

local function ReadIns(Line: string): (string, string, string?)
	
	if InsCaches[Line] then return unpack(InsCaches[Line]) end
	
	local _, _, Name, Value = string_find(Line, INSFORM)
	
	if Value then
		local Path1, Path2 = ExtractPath(Value)
		InsCaches[Line] = {Path1, Path2}
		return Path1, Path2
	end
	
end

local LineCaches = {}

local function ReadSer(Line: string): string
	
	if LineCaches[Line] then return LineCaches[Line] end
	local _, _, _, Value = string_find(Line, SERFORM)
	
	if Value then LineCaches[Line] = Value return Value end
	
end

local ModCaches = {}

local function ReadMod(Line: string): string?
	if ModCaches[Line] then
		return unpack(ModCaches[Line])
	end

	local _, _, _, Value = string_find(Line, MODFOR1)
	if Value then
		local result = ExtractString(Value)
		ModCaches[Line] = {result, true}
		return result, true
	end

	local _, _, Value = string_find(Line, MODFOR2)
	if Value then
		local result = ExtractTarget(Value)
		ModCaches[Line] = {result, false}
		return result, false
	end

	return nil
end

--// Insertion //--

local function AddLine(Reg: Registry, At: number, Value: string): ()
	ShiftLinesAfter(Reg, At)
	table_insert(Reg.Source, At, NON)
end

local function AddService(Reg: Registry, At: number, Value: string): ()
	ShiftLinesAfter(Reg, At)
	table_insert(Reg.Source, At, `local {Value} = game:GetService('{Value}')`)
	AddClass(Reg.Services, At, Value)
end

local function AddInstance(Reg: Registry, At: number, Value: string, Parent: string, Edit: string): ()
	ShiftLinesAfter(Reg, At)
	table_insert(Reg.Source, At, Edit)
	AddLookup(Reg.Ins, At, Value, Parent)
end

local function AddModule(Reg: Registry, Type: string, At: number, Value: string, Edit: string): ()
	ShiftLinesAfter(Reg, At)
	table_insert(Reg.Source, At, Edit)
	AddClass(Reg[Type], At, Value)
end

--// Transform //--

local function Parse(Source: string, Ended: number): Registry
	local StringLast = 0
	local IndexLast = 0
	local SerLast = 0
	local MaxLast = 0

	local StringMaps = {}
	local IndexMaps = {}
	local SerMaps = {}
	local InsMaps = {}

	local Lines: SourceCode = {}
	local lineStart = 1
	local lineNum = 1
	local sourceLen = #Source

	while lineStart <= sourceLen + 1 do
		local nextBreak = string_find(Source, LINE, lineStart, true)
		if not nextBreak then nextBreak = sourceLen + 1 end

		local lineStr = string_sub(Source, lineStart, nextBreak - 1)
		Lines[lineNum] = lineStr

		if lineNum >= Ended then
			if string_sub(lineStr, 1, 6) == PREFIX then
				local Service = ReadSer(lineStr)
				if Service then
					SerMaps[Service] = lineNum
					SerLast = lineNum
					MaxLast = lineNum
				else
					local Module, IsString = ReadMod(lineStr)
					if Module then
						if IsString then
							StringMaps[Module] = lineNum
							StringLast = lineNum
						else
							IndexMaps[Module] = lineNum
							IndexLast = lineNum
						end
						MaxLast = lineNum
					else
						local Parent, Child = ReadIns(lineStr)
						if Parent and Child then
							local Class = InsMaps[Parent]
							MaxLast = lineNum
							if Class then
								Class.Map[Child] = lineNum
								Class.Last = lineNum
							else
								InsMaps[Parent] = {Last = lineNum, Map = {[Child] = lineNum}}
							end
						end
					end
				end
			end

			if lineNum > MaxLast + 6 then
				if nextBreak - 1 < sourceLen then
					Lines[lineNum + 1] = string_sub(Source, nextBreak + 1)
				end
				break
			end
		end

		lineStart = nextBreak + 1
		lineNum += 1
	end
	
	print(StringMaps)

	return {
		Source = Lines;
		Services = {Last = SerLast, Map = SerMaps};
		String = {Last = StringLast, Map = StringMaps};
		Index = {Last = IndexLast, Map = IndexMaps};
		Ins = InsMaps;
		Last = math.max(MaxLast, Ended);
	}
end


--// Helper //--

local function Decode(Registry: Registry, Name): string
	local Last = Registry.Last + 1
	if Registry.Source[Last] ~= NON then
		table_insert(Registry.Source, Last, NON)
	end
	return table_concat(Registry.Source, LINE)
end

--// Returns //--

return {
	AddInstance = AddInstance;
	AddService = AddService;
	AddModule = AddModule;
	AddLine = AddLine;
	
	Parse = Parse;
	Decode = Decode;
}
