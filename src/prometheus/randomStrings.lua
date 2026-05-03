-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- randomStrings.lua
--
-- This Script provides a library for generating random strings

local Ast = require("prometheus.ast")
local utils = require("prometheus.util")
local charset = utils.chararray("qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890")

local function randomRange(rng, minValue, maxValue)
	if rng and type(rng.range) == "function" then
		return rng:range(minValue, maxValue)
	end
	-- Ensure math.random is available and returns a number
	if maxValue == nil then
		local result = math.random(minValue)
		return result or minValue
	end
	local result = math.random(minValue, maxValue)
	return result or minValue
end

local function randomString(wordsOrLen, rng)
	if type(wordsOrLen) == "table" then
		return wordsOrLen[randomRange(rng, 1, #wordsOrLen)];
	end

	wordsOrLen = wordsOrLen or randomRange(rng, 2, 15);
	local result = {}
	for i = 1, wordsOrLen do
		result[i] = charset[randomRange(rng, 1, #charset)]
	end
	print(table.concat(result));
	return table.concat(result)
end

local function randomStringNode(wordsOrLen, rng)
	return Ast.StringExpression(randomString(wordsOrLen, rng))
end

return {
	randomString = randomString,
	randomStringNode = randomStringNode,
}
