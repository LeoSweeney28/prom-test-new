-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- tests_verbose.lua
--
-- Extended test runner with richer diagnostics and failure artifacts.

local Prometheus = require("src.prometheus")

local isWindows = package.config:sub(1, 1) == "\\"

local function parseArgs(rawArgs)
	local opts = {
		iterations = 10,
		ciMode = false,
		verbose = false,
		failFast = false,
		includeAntiTamper = false,
		noColors = false,
		seedOverride = nil,
		presetFilter = nil,
		fileFilter = nil,
		outDir = nil,
	}

	for _, currArg in ipairs(rawArgs or {}) do
		if currArg == "--CI" then
			opts.ciMode = true
		elseif currArg == "--verbose" then
			opts.verbose = true
		elseif currArg == "--failfast" then
			opts.failFast = true
		elseif currArg == "--with-antitamper" then
			opts.includeAntiTamper = true
		elseif currArg == "--nocolors" then
			opts.noColors = true
		else
			local it = currArg:match("^%-%-iterations=(%d+)$")
			if it then
				opts.iterations = math.max(tonumber(it) or 1, 1)
			end

			local seed = currArg:match("^%-%-seed=(%d+)$")
			if seed then
				opts.seedOverride = tonumber(seed)
			end

			local preset = currArg:match("^%-%-preset=(.+)$")
			if preset then
				opts.presetFilter = {}
				for name in preset:gmatch("[^,]+") do
					opts.presetFilter[name] = true
				end
			end

			local file = currArg:match("^%-%-file=(.+)$")
			if file then
				opts.fileFilter = {}
				for name in file:gmatch("[^,]+") do
					opts.fileFilter[name] = true
				end
			end

			local outDir = currArg:match("^%-%-outdir=(.+)$")
			if outDir then
				opts.outDir = outDir
			end
		end
	end

	return opts
end

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = deepCopy(v)
	end
	return out
end

local function ensureDir(path)
	if isWindows then
		os.execute('mkdir "' .. path .. '" >nul 2>nul')
	else
		os.execute('mkdir -p "' .. path .. '" >/dev/null 2>&1')
	end
end

local function writeFile(path, content)
	local h = io.open(path, "wb")
	if not h then
		return false
	end
	h:write(content or "")
	h:close()
	return true
end

local function sanitizeName(name)
	return (name:gsub("[^%w%-%._]", "_"))
end

local function listLuaFiles(directory)
	local cmd
	if isWindows then
		cmd = 'dir "' .. directory .. '" /b'
	else
		cmd = 'ls -1 "' .. directory .. '"'
	end

	local p = io.popen(cmd)
	if not p then
		error("Failed to list tests directory: " .. tostring(directory))
	end

	local files = {}
	for filename in p:lines() do
		if filename:sub(-4) == ".lua" then
			files[#files + 1] = filename
		end
	end
	p:close()
	table.sort(files)
	return files
end

local function sortedPresetNames(presets, filter)
	local names = {}
	for name, _ in pairs(presets) do
		if not filter or filter[name] then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names
end

local function removeAntiTamperSteps(config)
	if not config.Steps then
		return
	end
	for i = #config.Steps, 1, -1 do
		if config.Steps[i].Name == "AntiTamper" then
			table.remove(config.Steps, i)
		end
	end
end

local function packReturns(...)
	return {
		n = select("#", ...),
		...
	}
end

local function captureRun(func)
	local output = {}
	local env = {}
	for k, v in pairs(_G) do
		env[k] = v
	end
	env.print = function(...)
		local items = {}
		for i = 1, select("#", ...) do
			items[i] = tostring(select(i, ...))
		end
		output[#output + 1] = table.concat(items, "\t")
	end

	---@diagnostic disable-next-line: deprecated
	if type(setfenv) == "function" then
		---@diagnostic disable-next-line: deprecated
		setfenv(func, env)
	end

	local ok, resultOrErr = xpcall(function()
		return packReturns(func())
	end, debug.traceback)

	return {
		ok = ok,
		output = table.concat(output, "\n"),
		returns = ok and resultOrErr or nil,
		err = ok and nil or tostring(resultOrErr),
	}
end

local function valuesEquivalent(a, b)
	local ta, tb = type(a), type(b)
	if ta ~= tb then
		return false
	end
	if ta == "number" or ta == "string" or ta == "boolean" or ta == "nil" then
		return a == b
	end
	return true
end

local function compareRuns(sourceRun, obfRun)
	if sourceRun.ok ~= obfRun.ok then
		return false, "runtime-status-mismatch"
	end
	if not sourceRun.ok then
		return false, "source-failed"
	end
	if sourceRun.output ~= obfRun.output then
		return false, "print-output-mismatch"
	end

	local sa = sourceRun.returns
	local sb = obfRun.returns
	if (sa and sa.n or 0) ~= (sb and sb.n or 0) then
		return false, "return-count-mismatch"
	end
	for i = 1, (sa and sa.n or 0) do
		if not valuesEquivalent(sa[i], sb[i]) then
			return false, "return-value-mismatch@" .. tostring(i)
		end
	end

	return true, "ok"
end

local function formatReturns(returns)
	if not returns then
		return "<none>"
	end
	local parts = {}
	for i = 1, returns.n do
		local v = returns[i]
		local tv = type(v)
		if tv == "number" or tv == "string" or tv == "boolean" or tv == "nil" then
			parts[#parts + 1] = tostring(v)
		else
			parts[#parts + 1] = "<" .. tv .. ">"
		end
	end
	return table.concat(parts, ", ")
end

local function logLine(handle, msg)
	handle:write(msg .. "\n")
	handle:flush()
	print(msg)
end

local options = parseArgs(arg)
Prometheus.colors.enabled = not options.noColors
Prometheus.Logger.logLevel = options.verbose and Prometheus.Logger.LogLevel.Info or Prometheus.Logger.LogLevel.Error

local timestamp = os.date("%Y%m%d-%H%M%S")
local outDir = options.outDir or ("artifacts/test-logs/" .. timestamp)
local failureDir = outDir .. "/failures"
ensureDir(outDir)
ensureDir(failureDir)

local summaryLog = assert(io.open(outDir .. "/summary.log", "wb"))
local csvLog = assert(io.open(outDir .. "/cases.csv", "wb"))
csvLog:write("status,file,preset,iteration,reason,obf_ms,size_ratio,seed_source\n")

local testsDir = "./tests"
local files = listLuaFiles(testsDir)
if options.fileFilter then
	local filtered = {}
	for _, f in ipairs(files) do
		if options.fileFilter[f] then
			filtered[#filtered + 1] = f
		end
	end
	files = filtered
end

local presets = Prometheus.Presets
local presetNames = sortedPresetNames(presets, options.presetFilter)

if #files == 0 then
	logLine(summaryLog, "[ERROR] No test files selected.")
	os.exit(1)
end
if #presetNames == 0 then
	logLine(summaryLog, "[ERROR] No presets selected.")
	os.exit(1)
end

logLine(summaryLog, string.format(
	"[INFO] Starting extended tests: files=%d presets=%d iterations=%d out=%s",
	#files,
	#presetNames,
	options.iterations,
	outDir
))

local stats = {
	total = 0,
	passed = 0,
	failed = 0,
	byPreset = {},
}

for _, presetName in ipairs(presetNames) do
	stats.byPreset[presetName] = {
		count = 0,
		pass = 0,
		fail = 0,
		time = 0,
	}
end

local function writeFailureArtifacts(caseKey, sourceCode, obfuscatedCode, detail)
	local base = failureDir .. "/" .. sanitizeName(caseKey)
	writeFile(base .. ".source.lua", sourceCode or "")
	writeFile(base .. ".obfuscated.lua", obfuscatedCode or "")
	writeFile(base .. ".detail.txt", detail or "")
end

local function loadChunkCompat(code, chunkName)
	---@diagnostic disable-next-line: deprecated
	if type(loadstring) == "function" then
		---@diagnostic disable-next-line: deprecated
		return loadstring(code, chunkName)
	end
	if type(load) == "function" then
		return load(code, chunkName, "t", {})
	end
	return nil, "No Lua loader available"
end

for _, filename in ipairs(files) do
	local sourcePath = testsDir .. "/" .. filename
	local sourceHandle = io.open(sourcePath, "rb")
	if not sourceHandle then
		logLine(summaryLog, "[ERROR] Cannot read source file: " .. sourcePath)
		if options.failFast then break end
	else
		local sourceCode = sourceHandle:read("*a")
		sourceHandle:close()

		for _, presetName in ipairs(presetNames) do
			local baseConfig = deepCopy(presets[presetName])
			if not options.includeAntiTamper then
				removeAntiTamperSteps(baseConfig)
			end
			if options.seedOverride then
				baseConfig.Seed = options.seedOverride
			end

			for iteration = 1, options.iterations do
				stats.total = stats.total + 1
				stats.byPreset[presetName].count = stats.byPreset[presetName].count + 1

				local caseKey = string.format("%s__%s__%d", filename, presetName, iteration)
				local t0 = os.clock()
				local pipeline = Prometheus.Pipeline:fromConfig(deepCopy(baseConfig))

				local okObf, obfOrErr = xpcall(function()
					return pipeline:apply(sourceCode, sourcePath)
				end, debug.traceback)
				local obfMs = (os.clock() - t0) * 1000
				stats.byPreset[presetName].time = stats.byPreset[presetName].time + obfMs

				local obfuscated = okObf and obfOrErr or nil
				local reason = "ok"
				local passed = false
				local seedSource = "unknown"
				if type(pipeline.random) == "table" then
					seedSource = tostring(rawget(pipeline.random, "SeedSource") or "unknown")
				end

				if not okObf then
					reason = "obfuscation-error"
					writeFailureArtifacts(caseKey, sourceCode, "", "Obfuscation error:\n" .. tostring(obfOrErr))
				else
					local sourceFunc, sourceCompileErr = loadChunkCompat(sourceCode, "@" .. sourcePath)
					local obfText = type(obfuscated) == "string" and obfuscated or ""
					local obfFunc, obfCompileErr = loadChunkCompat(obfText, "@" .. caseKey .. ".obfuscated")

					if not sourceFunc then
						reason = "source-compile-error"
						writeFailureArtifacts(caseKey, sourceCode, obfuscated, "Source compile error:\n" .. tostring(sourceCompileErr))
					elseif not obfFunc then
						reason = "obfuscated-compile-error"
						writeFailureArtifacts(caseKey, sourceCode, obfuscated, "Obfuscated compile error:\n" .. tostring(obfCompileErr))
					else
						local sourceRun = captureRun(sourceFunc)
						local obfRun = captureRun(obfFunc)
						local same, compareReason = compareRuns(sourceRun, obfRun)
						if same then
							passed = true
						else
							reason = compareReason
							local detail = table.concat({
								"Reason: " .. tostring(compareReason),
								"\n[Source output]\n" .. tostring(sourceRun.output),
								"\n[Obfuscated output]\n" .. tostring(obfRun.output),
								"\n[Source returns]\n" .. formatReturns(sourceRun.returns),
								"\n[Obfuscated returns]\n" .. formatReturns(obfRun.returns),
								"\n[Source err]\n" .. tostring(sourceRun.err),
								"\n[Obfuscated err]\n" .. tostring(obfRun.err),
							}, "\n")
							writeFailureArtifacts(caseKey, sourceCode, obfuscated, detail)
						end
					end
				end

				local ratio = obfuscated and (#obfuscated / math.max(#sourceCode, 1) * 100) or 0
				local status = passed and "PASS" or "FAIL"
				local row = string.format("%s,%s,%s,%d,%s,%.3f,%.3f,%s\n",
					status,
					filename,
					presetName,
					iteration,
					reason,
					obfMs,
					ratio,
					seedSource
				)
				csvLog:write(row)
				csvLog:flush()

				if passed then
					stats.passed = stats.passed + 1
					stats.byPreset[presetName].pass = stats.byPreset[presetName].pass + 1
				else
					stats.failed = stats.failed + 1
					stats.byPreset[presetName].fail = stats.byPreset[presetName].fail + 1
				end

				logLine(summaryLog, string.format(
					"[%s] file=%s preset=%s iter=%d reason=%s obf_ms=%.2f ratio=%.2f%% seed=%s",
					status,
					filename,
					presetName,
					iteration,
					reason,
					obfMs,
					ratio,
					seedSource
				))

				if options.failFast and not passed then
					break
				end
			end

			if options.failFast and stats.failed > 0 then
				break
			end
		end
	end

	if options.failFast and stats.failed > 0 then
		break
	end
end

logLine(summaryLog, "")
logLine(summaryLog, "========== SUMMARY ==========")
logLine(summaryLog, string.format("Total Cases: %d", stats.total))
logLine(summaryLog, string.format("Passed: %d", stats.passed))
logLine(summaryLog, string.format("Failed: %d", stats.failed))

for _, presetName in ipairs(presetNames) do
	local p = stats.byPreset[presetName]
	local avg = p.count > 0 and (p.time / p.count) or 0
	logLine(summaryLog, string.format(
		"Preset=%s total=%d pass=%d fail=%d avg_obf_ms=%.2f",
		presetName,
		p.count,
		p.pass,
		p.fail,
		avg
	))
end

summaryLog:close()
csvLog:close()

if stats.failed > 0 then
	if options.ciMode then
		error("Extended tests failed. See: " .. outDir)
	end
	print(Prometheus.colors("[FAILED]", "red") .. " Extended tests failed. Logs: " .. outDir)
	os.exit(1)
else
	print(Prometheus.colors("[PASSED]", "green") .. " Extended tests passed. Logs: " .. outDir)
	os.exit(0)
end
