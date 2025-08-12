--[===[

		stevedonovan 	<-> 	Original Penlight lexer author
		ryanjmulder 	<-> 	Penlight lexer contributer
		mpeterv 		<-> 	Penlight lexer contributer
		Tieske 			<->		Penlight lexer contributer
		
		boatbomber 		<-> 	Roblox port, and optimizations
		Sleitnick  		<->		Roblox optimizations
		howmanysmall 	<->		Lua + Roblox optimizations
		
		I striped up everything here, 5-10x performance I think
		
--]===]

--!optimize 2

local STRING_EMPTY 					= "^(['\"])%1"
local STRING_PLAIN 					= "^(['\"`])[^\n]-([^\\]%1)"
local STRING_INCOMP 				= "^(['\"`])[^\n]*"
local STRING_MULTI 					= "^%[(=*)%[.-%]%1%]"
local STRING_MULTI_INCOMP 			= "^%[=*%[.-.*"

local COMMENT_MULTI 				= "^%-%-%[(=*)%[.-%]%1%]"
local COMMENT_MULTI_INCOMP 			= "^%-%-%[=*%[.-.*"
local COMMENT_PLAIN 				= "^%-%-.-\n"
local COMMENT_INCOMP 				= "^%-%-.*"

local MATCHES = {

	{ "^[^\"'`%[%-]+", "iden" },

	{ STRING_EMPTY, "string" },
	{ STRING_PLAIN, "string" },
	{ STRING_INCOMP,"string" },
	{ STRING_MULTI, "string" },
	{ STRING_MULTI_INCOMP, "string" },
	
	{ COMMENT_MULTI,"bcomment" },
	{ COMMENT_MULTI_INCOMP,"bcomment" },
	{ COMMENT_PLAIN,"comment" },
	{ COMMENT_INCOMP,"comment" },

	{ "^.","iden" },
}

local PATTERNS = {}
local TOKENS = {}

for i, m in MATCHES do PATTERNS[i] = m[1] TOKENS[i] = m[2] end

local coroutine_create = coroutine.create
local coroutine_status = coroutine.status
local coroutine_resume = coroutine.resume
local coroutine_yield = coroutine.yield
local string_byte = string.byte
local string_find = string.find
local string_gsub = string.gsub
local string_byte = string.byte
local string_sub = string.sub

local function scan(s: string)
	local size,pos = #s,1
	local thread = coroutine_create(function()
		while pos <= size do
			for token, pattern in PATTERNS do
				local start, stop = string_find(s, pattern, pos)
				if start == nil then continue end
				local token = TOKENS[token]
				pos = stop + 1
				coroutine_yield(token, start, stop)
				break
			end
		end
	end)
	return function()
		if coroutine_status(thread) == "dead" then return end
		local success, token, start, stop = coroutine_resume(thread)
		if success and token then return token, start, stop end
	end
end

local function getline(Doc)
	local Source = Doc:GetText()
	local Tokens = scan(Source)
	local lastTokenType, lastStop
	for tokenType, start, stop in Tokens do
		if tokenType == 'iden' then
			if start == 1 and string_byte(Source) == 10 then
				return 1
			end
			local _, line = string_gsub(string_sub(Source, 1, start), "\n", "")
			if lastTokenType == "bcomment" then
				local _, lineold = string_gsub(string_sub(Source, 1, lastStop), "\n", "")
				if lineold == line then return end
			end
			return line + 1
		end
		lastTokenType = tokenType
		lastStop = stop
	end
	return 1
end

return getline
