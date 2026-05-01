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
	if maxValue == nil then
		return math.random(minValue)
	end
	return math.random(minValue, maxValue)
end

local function randomString(wordsOrLen, rng)
	if type(wordsOrLen) == "table" then
		return wordsOrLen[randomRange(rng, 1, #wordsOrLen)];
	end

	wordsOrLen = wordsOrLen or randomRange(rng, 2, 15);
	if wordsOrLen > 0 then
		return randomString(wordsOrLen - 1, rng) .. charset[randomRange(rng, 1, #charset)]
	else
		return ""
	end
end

local function randomStringNode(wordsOrLen, rng)
	return Ast.StringExpression(randomString(wordsOrLen, rng))
end

return {
	randomString = randomString,
	randomStringNode = randomStringNode,
}
