-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- presets.lua
--
-- This Script provides the predefined obfuscation presets for Prometheus

return {
	-- Minifies your code. Does not obfuscate it. No performance loss.
	["Minify"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {},
	},

	-- Weak obfuscation. Very readable, low performance loss.
	["Weak"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "Vmify", Settings = { MaxStatements = 160 } },
			{
				Name = "ConstantArray",
				Settings = {
					Threshold = 1,
					StringsOnly = true
				},
			},
			{ Name = "WrapInFunction", Settings = {} },
		},
	},

	-- This is here for the tests.lua file.
	-- It helps isolate any problems with the Vmify step.
	-- It is not recommended to use this preset for obfuscation.
	-- Use the Weak, Medium, or Strong for obfuscation instead.
	["Vmify"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "Vmify", Settings = { MaxStatements = 120 } },
		},
	},

	-- Medium obfuscation. Moderate obfuscation, moderate performance loss.
	["Medium"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "EncryptStrings", Settings = {} },
			{
				Name = "AntiTamper",
				Settings = {
					UseDebug = false,
				},
			},
			{ Name = "ProxifyLocals", Settings = { MaxUsageCount = 10 } },
			{ Name = "Vmify", Settings = { MaxStatements = 10 } },

			{
				Name = "ConstantArray",
				Settings = {
					Threshold = 1,
					StringsOnly = true,
					Shuffle = true,
					Rotate = true,
					LocalWrapperThreshold = 0,
				},
			},
			{ Name = "NumbersToExpressions", Settings = {} },
			{ Name = "ControlFlow", Settings = {} },
			{ Name = "WrapInFunction", Settings = {} },

		},
	},

	-- Strong obfuscation, high performance losss.
	["Strong"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "Vmify", Settings = { MaxStatements = 120 } },
			{ Name = "EncryptStrings", Settings = {} },
			{
				Name = "AntiTamper",
				Settings = {
					UseDebug = false,
				},
			},
			{ Name = "Vmify", Settings = { MaxStatements = 120 } },
			{
				Name = "ConstantArray",
				Settings = {
					Threshold = 1,
					StringsOnly = true,
					Shuffle = true,
					Rotate = true,
					LocalWrapperThreshold = 0
				},
			},
			{
				Name = "NumbersToExpressions",
				Settings = {
					NumberRepresentationMutaton = true
				},
			},
			{
				Name = "ControlFlow",
				Settings = {
					Treshold = 0.45,
					OpaquePredicate = true
				}
			},
			{ Name = "WrapInFunction", Settings = {} },
		},
	},

	-- Balanced obfuscation profile with moderate overhead.
	["Balanced"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "EncryptStrings", Settings = {} },
			{
				Name = "AntiTamper",
				Settings = {
					UseDebug = false,
				},
			},
			{ Name = "Vmify", Settings = { MaxStatements = 120 } },
			{
				Name = "ConstantArray",
				Settings = {
					Treshold = 0.85,
					StringsOnly = true,
					Shuffle = true,
					Rotate = true,
					LocalWrapperTreshold = 0.15,
					LocalWrapperCount = 1,
				},
			},
			{
				Name = "ControlFlow",
				Settings = {
					Treshold = 1,
					OpaquePredicate = true,
					MaxStatementsPerBlock = 80,
				},
			},
			{ Name = "WrapInFunction", Settings = {} },
		},
	},

	-- Hardened profile focused on reverse-engineering resistance.
	["Hardened"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "EncryptStrings", Settings = {} },
			{
				Name = "AntiTamper",
				Settings = {
					UseDebug = false,
				},
			},
			{ Name = "Vmify", Settings = { MaxStatements = 120 } },
			{
				Name = "ConstantArray",
				Settings = {
					Treshold = 1,
					StringsOnly = true,
					Shuffle = true,
					Rotate = true,
					LocalWrapperTreshold = 0.35,
					LocalWrapperCount = 2,
				},
			},
			{
				Name = "ControlFlow",
				Settings = {
					Treshold = 0.45,
					OpaquePredicate = true,
					MaxStatementsPerBlock = 120,
				},
			},
			{ Name = "WrapInFunction", Settings = { Iterations = 2 } },
		},
	},
}
