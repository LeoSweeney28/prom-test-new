-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- Vmify.lua
--
-- This Script provides a Complex Obfuscation Step that will compile the entire Script to  a fully custom bytecode that does not share it's instructions
-- with lua, making it much harder to crack than other lua obfuscators

local Step = require("prometheus.step");
local Compiler = require("prometheus.compiler.compiler");

local Vmify = Step:extend();
Vmify.Description = "This Step will Compile your script into a fully-custom (not a half custom like other lua obfuscators) Bytecode Format and emit a vm for executing it.";
Vmify.Name = "Vmify";

Vmify.SettingsDescriptor = {}

function Vmify:init(_) end

function Vmify:apply(ast, pipeline)
    local compilerSeed;
    if pipeline and type(pipeline.getRandom) == "function" then
        local rng = pipeline:getRandom();
        if rng and type(rng.derive) == "function" then
            rng = rng:derive("Vmify");
        end
        if rng and type(rng.range) == "function" then
            compilerSeed = rng:range(1, 2147483646);
        end
    end

    -- Create Compiler
    local compiler = Compiler:new({ Seed = compilerSeed; });

    -- Compile the Script into a bytecode vm
    return compiler:compile(ast);
end

return Vmify;