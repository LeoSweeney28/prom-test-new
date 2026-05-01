-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- randomLiterals.lua
--
-- This Script provides a library for creating random literals

local Ast = require("prometheus.ast");
local RandomStrings = require("prometheus.randomStrings");

local RandomLiterals = {};

local function randomRange(rng, minValue, maxValue)
    if rng and type(rng.range) == "function" then
        return rng:range(minValue, maxValue)
    end
    if maxValue == nil then
        return math.random(minValue)
    end
    return math.random(minValue, maxValue)
end

local function resolveRng(pipeline, rng)
    if rng then
        return rng
    end
    if pipeline and type(pipeline.getRandom) == "function" then
        local prng = pipeline:getRandom();
        if prng and type(prng.derive) == "function" then
            return prng:derive("RandomLiterals");
        end
        return prng;
    end
    return nil
end

local function callNameGenerator(generatorFunction, ...)
	if(type(generatorFunction) == "table") then
		generatorFunction = generatorFunction.generateName;
	end
	return generatorFunction(...);
end

function RandomLiterals.String(pipeline, rng)
	rng = resolveRng(pipeline, rng)
    return Ast.StringExpression(callNameGenerator(pipeline.namegenerator, randomRange(rng, 1, 4096)));
end

function RandomLiterals.Dictionary(pipeline, rng)
	rng = resolveRng(pipeline, rng)
    return RandomStrings.randomStringNode(true, rng);
end

function RandomLiterals.Number(pipeline, rng)
	rng = resolveRng(pipeline, rng)
    return Ast.NumberExpression(randomRange(rng, -8388608, 8388607));
end

function RandomLiterals.Any(pipeline, rng)
	rng = resolveRng(pipeline, rng)
    local type = randomRange(rng, 1, 3);
    if type == 1 then
        return RandomLiterals.String(pipeline, rng);
    elseif type == 2 then
        return RandomLiterals.Number(pipeline, rng);
    elseif type == 3 then
        return RandomLiterals.Dictionary(pipeline, rng);
    end
end


return RandomLiterals;