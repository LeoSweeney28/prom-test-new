-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- pipeline.lua
--
-- This Script provides a configurable obfuscation pipeline that can obfuscate code using different modules
-- These modules can simply be added to the pipeline.

local Enums = require("prometheus.enums");
local util = require("prometheus.util");
local Parser = require("prometheus.parser");
local Unparser = require("prometheus.unparser");
local Random = require("prometheus.random");
local logger = require("logger");

local NameGenerators = require("prometheus.namegenerators");
local Steps = require("prometheus.steps");
local LuaVersion = Enums.LuaVersion;

-- On Windows, os.clock can be used. On other systems, os.time must be used for benchmarking.
local isWindows = package and package.config and type(package.config) == "string" and package.config:sub(1,1) == "\\";
local function gettime()
	if isWindows then
		return os.clock();
	else
		return os.time();
	end
end

local function cloneShallow(tbl)
	local copy = {};
	for k, v in pairs(tbl or {}) do
		copy[k] = v;
	end
	return copy;
end

local function validateConfigShape(config)
	if type(config) ~= "table" then
		logger:error("Pipeline config must be a table");
	end
	if config.Steps ~= nil and type(config.Steps) ~= "table" then
		logger:error("Pipeline config field 'Steps' must be a table");
	end
end

local Pipeline = {
	NameGenerators = NameGenerators;
	Steps = Steps;
	DefaultSettings = {
		LuaVersion = LuaVersion.LuaU;
		PrettyPrint = false;
		Seed = 0;
		VarNamePrefix = "";
	}
}

function Pipeline:new(settings)
	settings = settings or {};
	local luaVersion = settings.luaVersion or settings.LuaVersion or Pipeline.DefaultSettings.LuaVersion;
	local conventions = Enums.Conventions[luaVersion];
	if(not conventions) then
		logger:error("The Lua Version \"" .. luaVersion
			.. "\" is not recognized by the Tokenizer! Please use one of the following: \"" .. table.concat(util.keys(Enums.Conventions), "\",\"") .. "\"");
	end

	local prettyPrint = settings.PrettyPrint;
	if prettyPrint == nil then
		prettyPrint = Pipeline.DefaultSettings.PrettyPrint;
	end

	local prefix = settings.VarNamePrefix;
	if prefix == nil then
		prefix = Pipeline.DefaultSettings.VarNamePrefix;
	end

	local seed = settings.Seed;
	if seed == nil then
		seed = Pipeline.DefaultSettings.Seed;
	end

	local pipeline = {
		LuaVersion = luaVersion;
		PrettyPrint = prettyPrint;
		VarNamePrefix = prefix;
		Seed = seed;
		parser = Parser:new({ LuaVersion = luaVersion; });
		unparser = Unparser:new({ LuaVersion = luaVersion; PrettyPrint = prettyPrint; Highlight = settings.Highlight; });
		namegenerator = Pipeline.NameGenerators.MangledShuffled;
		conventions = conventions;
		steps = {};
		random = nil;
	}

	setmetatable(pipeline, self);
	self.__index = self;

	return pipeline;
end

function Pipeline:fromConfig(config)
	config = config or {};
	validateConfigShape(config);
	local pipeline = Pipeline:new({
		LuaVersion = config.LuaVersion or LuaVersion.Lua51;
		PrettyPrint = config.PrettyPrint;
		VarNamePrefix = config.VarNamePrefix;
		Seed = config.Seed;
		Highlight = config.Highlight;
	});

	pipeline:setNameGenerator(config.NameGenerator or "MangledShuffled");

	local steps = config.Steps or {};
	for _, step in ipairs(steps) do
		if type(step.Name) ~= "string" then
			logger:error("Step.Name must be a String");
		end
		if step.Settings ~= nil and type(step.Settings) ~= "table" then
			logger:error(string.format("Step.Settings for step \"%s\" must be a table", step.Name));
		end
		local constructor = pipeline.Steps[step.Name];
		if not constructor then
			logger:error(string.format("The Step \"%s\" was not found!", step.Name));
		end
		pipeline:addStep(constructor:new(cloneShallow(step.Settings or {})));
	end

	return pipeline;
end

function Pipeline:addStep(step)
	table.insert(self.steps, step);
end

function Pipeline:resetSteps(_)
	self.steps = {};
end

function Pipeline:getSteps()
	return self.steps;
end

function Pipeline:setLuaVersion(luaVersion)
	local conventions = Enums.Conventions[luaVersion];
	if(not conventions) then
		logger:error("The Lua Version \"" .. luaVersion
			.. "\" is not recognized by the Tokenizer! Please use one of the following: \"" .. table.concat(util.keys(Enums.Conventions), "\",\"") .. "\"");
	end

	self.LuaVersion = luaVersion;
	self.parser = Parser:new({ LuaVersion = luaVersion; });
	self.unparser = Unparser:new({ LuaVersion = luaVersion; PrettyPrint = self.PrettyPrint; });
	self.conventions = conventions;
end

function Pipeline:getLuaVersion()
	return self.LuaVersion;
end

function Pipeline:setNameGenerator(nameGenerator)
	if(type(nameGenerator) == "string") then
		nameGenerator = Pipeline.NameGenerators[nameGenerator];
	end

	if(type(nameGenerator) == "function" or type(nameGenerator) == "table") then
		self.namegenerator = nameGenerator;
		return;
	else
		logger:error("The Argument to Pipeline:setNameGenerator must be a valid NameGenerator function or function name e.g: \"mangled\"")
	end
end

function Pipeline:apply(code, filename)
	if type(code) ~= "string" then
		logger:error("Pipeline:apply expects the first argument to be a string");
	end

	local startTime = gettime();
	filename = filename or "Anonymous Script";
	logger:info(string.format("Applying Obfuscation Pipeline to %s ...", filename));

	local seed = (self.Seed and self.Seed > 0) and self.Seed or nil;
	self.random = Random:new(seed);
	self.random:seedGlobalMathRandom();
	if seed then
		logger:info("Using deterministic build seed from config");
	elseif self.random.SeedSource == "openssl" then
		logger:info("Using OpenSSL-derived entropy seed");
	else
		logger:warn("OpenSSL entropy unavailable. Using fallback entropy mixer.");
	end

	logger:info("Parsing ...");
	local parserStartTime = gettime();
	local sourceLen = string.len(code);
	local ast = self.parser:parse(code);
	logger:info(string.format("Parsing Done in %.2f seconds", gettime() - parserStartTime));

	for _, step in ipairs(self.steps) do
		local stepStartTime = gettime();
		logger:info(string.format("Applying Step \"%s\" ...", step.Name or "Unnamed"));
		local ok, newAstOrErr = xpcall(function()
			return step:apply(ast, self);
		end, debug.traceback);
		if not ok then
			logger:error(string.format("Step \"%s\" failed: %s", step.Name or "Unnamed", tostring(newAstOrErr)));
		end
		local newAst = newAstOrErr;
		if type(newAst) == "table" then
			ast = newAst;
		end
		logger:info(string.format("Step \"%s\" Done in %.2f seconds", step.Name or "Unnamed", gettime() - stepStartTime));
	end

	self:renameVariables(ast);
	code = self:unparse(ast);

	logger:info(string.format("Obfuscation Done in %.2f seconds", gettime() - startTime));
	logger:info(string.format("Generated Code size is %.2f%% of the Source Code size", (string.len(code) / sourceLen) * 100));

	return code;
end

function Pipeline:setPrettyPrint(prettyPrint)
	self.PrettyPrint = prettyPrint and true or false;
	self.unparser:setPrettyPrint(self.PrettyPrint);
end

function Pipeline:unparse(ast)
	local startTime = gettime();
	logger:info("Generating Code ...");
	local unparsed = self.unparser:unparse(ast);
	logger:info(string.format("Code Generation Done in %.2f seconds", gettime() - startTime));
	return unparsed;
end

function Pipeline:renameVariables(ast)
	local startTime = gettime();
	logger:info("Renaming Variables ...");

	local generatorFunction = self.namegenerator or Pipeline.NameGenerators.mangled;
	if(type(generatorFunction) == "table") then
		if (type(generatorFunction.prepare) == "function") then
			generatorFunction.prepare(ast);
		end
		generatorFunction = generatorFunction.generateName;
	end

	if not self.unparser:isValidIdentifier(self.VarNamePrefix) and #self.VarNamePrefix ~= 0 then
		logger:error(string.format("The Prefix \"%s\" is not a valid Identifier in %s", self.VarNamePrefix, self.LuaVersion));
	end

	local globalScope = ast.globalScope;
	globalScope:renameVariables({
		Keywords = self.conventions.Keywords;
		generateName = generatorFunction;
		prefix = self.VarNamePrefix;
	});

	logger:info(string.format("Renaming Variables Done in %.2f seconds", gettime() - startTime));
end

function Pipeline:getRandom()
	if not self.random then
		local seed = (self.Seed and self.Seed > 0) and self.Seed or nil;
		self.random = Random:new(seed);
	end
	return self.random;
end

return Pipeline;
