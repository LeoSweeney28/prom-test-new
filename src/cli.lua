-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- cli.lua
--
-- This Script contains the Code for the Prometheus CLI.

local function script_path()
	local str = debug.getinfo(2, "S").source:sub(2);
	return str:match("(.*[/%\\])");
end
package.path = script_path() .. "?.lua;" .. package.path;

---@diagnostic disable-next-line: different-requires
local Prometheus = require("prometheus");
Prometheus.Logger.logLevel = Prometheus.Logger.LogLevel.Info;
Prometheus.colors.enabled = true;

local function file_exists(file)
	local f = io.open(file, "rb");
	if f then
		f:close();
	end
	return f ~= nil;
end

local function lines_from(file)
	if not file_exists(file) then
		return {};
	end
	local lines = {};
	for line in io.lines(file) do
		lines[#lines + 1] = line;
	end
	return lines;
end

local function load_chunk(content, chunkName, environment)
	if type(loadstring) == "function" then
		local func, err = loadstring(content, chunkName);
		if not func then
			return nil, err;
		end
		if environment and type(setfenv) == "function" then
			setfenv(func, environment);
		elseif environment and type(load) == "function" then
			return load(content, chunkName, "t", environment);
		end
		return func;
	end

	if type(load) ~= "function" then
		return nil, "No load function available";
	end

	return load(content, chunkName, "t", environment);
end

local function clone(value)
	if type(value) ~= "table" then
		return value;
	end
	local out = {};
	for k, v in pairs(value) do
		out[k] = clone(v);
	end
	return out;
end

local function print_usage()
	Prometheus.Logger:info("Usage: prometheus [options] <input.lua>");
	Prometheus.Logger:info("  --preset, --p <name>    Use built-in preset");
	Prometheus.Logger:info("  --config, --c <file>    Use config lua file");
	Prometheus.Logger:info("  --out, --o <file>       Output file");
	Prometheus.Logger:info("  --Lua51 | --LuaU        Override Lua target version");
	Prometheus.Logger:info("  --pretty                Enable pretty print mode");
	Prometheus.Logger:info("  --nocolors              Disable colored logs");
	Prometheus.Logger:info("  --saveerrors            Save parser/step errors to *.error.txt");
	Prometheus.Logger:info("  --help, -h              Show help");
end

local is_declarative_config;

local function read_config_file(filename, unsafeConfig)
	if not file_exists(filename) then
		Prometheus.Logger:error(string.format('The config file "%s" was not found!', filename));
	end

	local content = table.concat(lines_from(filename), "\n");
	if not unsafeConfig and not is_declarative_config(content) then
		Prometheus.Logger:warn("Config safety mode is enabled. Non-declarative config logic may be unsafe. Use --unsafe-config to bypass this warning.");
	end
	local func, err = load_chunk(content, "@" .. filename, {});
	if not func then
		Prometheus.Logger:error(string.format('Failed to parse config file "%s": %s', filename, tostring(err)));
	end

	local ok, loaded = pcall(func);
	if not ok then
		Prometheus.Logger:error(string.format('Failed to execute config file "%s": %s', filename, tostring(loaded)));
	end
	if type(loaded) ~= "table" then
		Prometheus.Logger:error(string.format('Config file "%s" must return a table!', filename));
	end

	return loaded;
end

is_declarative_config = function(content)
	-- Fast safety check: declarative configs should be plain table-return statements.
	-- This blocks obvious dynamic execution unless --unsafe-config is set.
	local trimmed = content:gsub("^%s+", "");
	return trimmed:match("^return%s*{") ~= nil;
end

local function parse_args(rawArgs)
	rawArgs = rawArgs or {};
	local options = {
		config = nil;
		sourceFile = nil;
		outFile = nil;
		luaVersion = nil;
		prettyPrint = nil;
		saveErrors = false;
		unsafeConfig = false;
	};

	for idx = 1, #rawArgs do
		if rawArgs[idx] == "--unsafe-config" then
			options.unsafeConfig = true;
			break;
		end
	end

	local i = 1;
	while i <= #rawArgs do
		local curr = rawArgs[i];
		if type(curr) ~= "string" then
			Prometheus.Logger:error(string.format("Invalid argument at position %d", i));
		end
		if curr:sub(1, 2) == "--" or curr == "-h" then
			if curr == "--preset" or curr == "--p" then
				i = i + 1;
				if i > #rawArgs then
					Prometheus.Logger:error("Missing preset name after --preset/--p");
				end
				local presetName = tostring(rawArgs[i]);
				local preset = Prometheus.Presets[presetName];
				if not preset then
					Prometheus.Logger:error(string.format('A Preset with the name "%s" was not found!', presetName));
				end
				options.config = clone(preset);
			elseif curr == "--config" or curr == "--c" then
				i = i + 1;
				if i > #rawArgs then
					Prometheus.Logger:error("Missing config path after --config/--c");
				end
					options.config = read_config_file(tostring(rawArgs[i]), options.unsafeConfig);
			elseif curr == "--out" or curr == "--o" then
				i = i + 1;
				if i > #rawArgs then
					Prometheus.Logger:error("Missing output path after --out/--o");
				end
				options.outFile = tostring(rawArgs[i]);
			elseif curr == "--nocolors" then
				Prometheus.colors.enabled = false;
			elseif curr == "--Lua51" then
				options.luaVersion = "Lua51";
			elseif curr == "--LuaU" then
				options.luaVersion = "LuaU";
			elseif curr == "--pretty" then
				options.prettyPrint = true;
			elseif curr == "--saveerrors" then
				options.saveErrors = true;
			elseif curr == "--unsafe-config" then
				options.unsafeConfig = true;
			elseif curr == "--help" or curr == "-h" then
				print_usage();
				os.exit(0);
			else
				Prometheus.Logger:warn(string.format('The option "%s" is not valid and therefore ignored', curr));
			end
		else
			if options.sourceFile then
				Prometheus.Logger:error(string.format('Unexpected argument "%s"', rawArgs[i]));
			end
			options.sourceFile = tostring(rawArgs[i]);
		end
		i = i + 1;
	end

	return options;
end

local options = parse_args(arg);
if not options.sourceFile then
	print_usage();
	Prometheus.Logger:error("No input file was specified!");
end

local config = options.config or clone(Prometheus.Presets.Minify);
if not options.config then
	Prometheus.Logger:warn("No config was specified, falling back to Minify preset");
end

config.LuaVersion = options.luaVersion or config.LuaVersion;
if options.prettyPrint ~= nil then
	config.PrettyPrint = options.prettyPrint;
end

if not file_exists(options.sourceFile) then
	Prometheus.Logger:error(string.format('The File "%s" was not found!', options.sourceFile));
end


if options.saveErrors then
	Prometheus.Logger.errorCallback = function(...)
		print(Prometheus.colors(Prometheus.Config.NameUpper .. ": " .. ..., "red"));
		local message = table.concat({ ... }, " ");
		local fileName = options.sourceFile:sub(-4) == ".lua" and options.sourceFile:sub(0, -5) .. ".error.txt" or options.sourceFile .. ".error.txt";
		local handle = io.open(fileName, "w");
		if handle then
			handle:write(message);
			handle:close();
		end
		os.exit(1);
	end
end

local outFile = options.outFile;
if not outFile then
	if options.sourceFile:sub(-4) == ".lua" then
		outFile = options.sourceFile:sub(0, -5) .. ".obfuscated.lua";
	else
		outFile = options.sourceFile .. ".obfuscated.lua";
	end
end

local source = table.concat(lines_from(options.sourceFile), "\n");
local pipeline = Prometheus.Pipeline:fromConfig(config);
local out = pipeline:apply(source, options.sourceFile);
Prometheus.Logger:info(string.format('Writing output to "%s"', outFile));

local handle = io.open(outFile, "w");
if not handle then
	Prometheus.Logger:error(string.format('Could not write output file "%s"', outFile));
end
handle:write(out);
handle:close();
