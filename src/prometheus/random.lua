-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- random.lua
--
-- Dedicated pseudo-random service for build-time obfuscation.

local Random = {}

local MOD = 4294967296
local MUL = 1664525
local INC = 1013904223

local function toUInt32(n)
    n = math.floor(tonumber(n) or 0)
    n = n % MOD
    if n < 0 then
        n = n + MOD
    end
    return n
end

local function mix(seed, value)
    return (toUInt32(seed) + toUInt32(value) * 1597334677 + 12345) % MOD
end

local function parseHexSeed(hex)
    local seed = 0
    for i = 1, #hex do
        local byte = hex:byte(i)
        local digit
        if byte >= 48 and byte <= 57 then
            digit = byte - 48
        elseif byte >= 65 and byte <= 70 then
            digit = byte - 55
        elseif byte >= 97 and byte <= 102 then
            digit = byte - 87
        else
            return nil
        end
        seed = (seed * 16 + digit) % MOD
    end
    return seed
end

local function collectEntropySeed()
    local seed = 0x6D2B79F5
    local source = "fallback"

    seed = mix(seed, os.time() or 0)
    seed = mix(seed, math.floor((os.clock() or 0) * 1000000))
    seed = mix(seed, math.floor((collectgarbage("count") or 0) * 1000))

    local ptr = tostring({}):match("0x(%x+)")
    if ptr then
        seed = mix(seed, tonumber(ptr, 16) or 0)
    end

    local redirect = (package and package.config and package.config:sub(1, 1) == "\\") and "2>nul" or "2>/dev/null"
    local cmd = "openssl rand -hex 16 " .. redirect
    local proc = io.popen(cmd)
    if proc then
        local hex = (proc:read("*a") or ""):gsub("%s+", "")
        proc:close()
        local opensslSeed = parseHexSeed(hex)
        if opensslSeed then
            seed = mix(seed, opensslSeed)
            source = "openssl"
        end
    end

    seed = toUInt32(seed)
    if seed == 0 then
        seed = 0x6D2B79F5
    end

    return seed, source
end

function Random:new(seed)
    local realSeed = seed
    local source = "explicit"
    if type(realSeed) ~= "number" or realSeed <= 0 then
        realSeed, source = collectEntropySeed()
    end

    local instance = {
        _state = toUInt32(realSeed),
        SeedSource = source,
    }

    if instance._state == 0 then
        instance._state = 0x6D2B79F5
    end

    setmetatable(instance, self)
    self.__index = self
    return instance
end

function Random:nextUInt32()
    self._state = (MUL * self._state + INC) % MOD
    return self._state
end

function Random:range(minValue, maxValue)
    if minValue == nil and maxValue == nil then
        return self:nextUInt32() / MOD
    end

    if maxValue == nil then
        maxValue = minValue
        minValue = 1
    end

    minValue = math.floor(minValue)
    maxValue = math.floor(maxValue)

    if maxValue < minValue then
        minValue, maxValue = maxValue, minValue
    end

    local span = maxValue - minValue + 1
    if span <= 1 then
        return minValue
    end

    return minValue + (self:nextUInt32() % span)
end

function Random:chance(p)
    local chance = tonumber(p) or 0
    if chance <= 0 then
        return false
    end
    if chance >= 1 then
        return true
    end
    return self:range() <= chance
end

function Random:shuffle(list)
    for i = #list, 2, -1 do
        local j = self:range(1, i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

function Random:derive(label)
    local data = tostring(label or "")
    local seed = self:nextUInt32()
    for i = 1, #data do
        seed = mix(seed, data:byte(i) + i * 131)
    end
    return Random:new(seed)
end

function Random:seedGlobalMathRandom()
    math.randomseed(self:range(1, 2147483646))
end

return Random