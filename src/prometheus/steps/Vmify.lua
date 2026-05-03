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

Vmify.SettingsDescriptor = {
    MaxStatements = {
        name = "MaxStatements",
        description = "Maximum number of statements per hardened VM dispatcher block",
        type = "number",
        default = 1000,
        min = 1,
    },
}
Vmify.SettingsAliases = {
    MaxStatementsPerBlock = "MaxStatements",
}

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

    -- Optional dynamic opaque-predicate control-flow wrapper (stronger obfuscation)
    local _enableVmControlFlow = false
    if pipeline and type(pipeline.getSetting) == "function" then
        local ok, val = pcall(function() return pipeline:getSetting("VMControlFlow") end)
        if ok and type(val) == "boolean" then
            _enableVmControlFlow = val
        end
    end

    if _enableVmControlFlow and ast and ast.body then
        -- Build an opaque predicate tied to the VM seed. This predicate always evaluates to true
        -- for the current seed, but is not trivially detectable by analysis.
        local seedForPredicate = compilerSeed or 0
        local leftExpr = Ast.AddExpression(Ast.NumberExpression(seedForPredicate), Ast.NumberExpression(0))
        local rightExpr = Ast.AddExpression(Ast.NumberExpression(seedForPredicate), Ast.NumberExpression(0))
        local opaquePredicate = Ast.EqualsExpression(leftExpr, rightExpr, false)
        local inner = ast.body
        local wrapperIf = Ast.IfStatement(opaquePredicate, inner, {}, nil)
        ast.body = Ast.Block({ wrapperIf }, inner.scope or Scope:new(nil, nil))
    end

    -- Create Compiler
    local compiler = Compiler:new({
        Seed = compilerSeed;
        MaxStatements = self.MaxStatements;
    });

    -- Compile the Script into a bytecode vm
    return compiler:compile(ast);
end

return Vmify;
