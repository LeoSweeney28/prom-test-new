-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- ProxifyLocals.lua
--
-- This Script provides a Obfuscation Step for putting all Locals into Proxy Objects

local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local visitast = require("prometheus.visitast");
local RandomLiterals = require("prometheus.randomLiterals")

local AstKind = Ast.AstKind;

local ProxifyLocals = Step:extend();
ProxifyLocals.Description = "This Step wraps all locals into Proxy Objects";
ProxifyLocals.Name = "Proxify Locals";

ProxifyLocals.SettingsDescriptor = {
    LiteralType = {
        name = "LiteralType",
        description = "The type of the randomly generated literals",
        type = "enum",
        values = { "dictionary", "number", "string", "any" },
        default = "string",
    },
}

local MetatableExpressions = {
    { constructor = Ast.AddExpression,    key = "__add"    },
    { constructor = Ast.SubExpression,    key = "__sub"    },
    { constructor = Ast.IndexExpression,  key = "__index"  },
    { constructor = Ast.MulExpression,    key = "__mul"    },
    { constructor = Ast.DivExpression,    key = "__div"    },
    { constructor = Ast.PowExpression,    key = "__pow"    },
    { constructor = Ast.StrCatExpression, key = "__concat" },
}

local function callNameGenerator(generatorFunction, ...)
    if type(generatorFunction) == "table" then
        generatorFunction = generatorFunction.generateName
    end
    return generatorFunction(...)
end

local function shuffled(t, randRange)
    local result = {}
    for i = 1, #t do result[i] = t[i] end
    for i = #result, 2, -1 do
        local j = randRange(1, i)
        result[i], result[j] = result[j], result[i]
    end
    return result
end

local function generateLocalMetatableInfo(pipeline, randRange)
    local ops = shuffled(MetatableExpressions, randRange)
    return {
        setValue  = ops[1],
        getValue  = ops[2],
        index     = ops[3],
        valueName = callNameGenerator(pipeline.namegenerator, randRange(1, 4096)),
    }
end

function ProxifyLocals:init(_) end

function ProxifyLocals:CreateAssignmentExpression(info, expr, parentScope)
    local metatableVals = {}

    -- Setvalue Entry
    local setValueFunctionScope = Scope:new(parentScope)
    local setValueSelf = setValueFunctionScope:addVariable()
    local setValueArg  = setValueFunctionScope:addVariable()
    local setvalueFunctionLiteral = Ast.FunctionLiteralExpression(
        {
            Ast.VariableExpression(setValueFunctionScope, setValueSelf),
            Ast.VariableExpression(setValueFunctionScope, setValueArg),
        },
        Ast.Block({
            Ast.AssignmentStatement({
                Ast.AssignmentIndexing(
                    Ast.VariableExpression(setValueFunctionScope, setValueSelf),
                    Ast.StringExpression(info.valueName)
                )
            }, {
                Ast.VariableExpression(setValueFunctionScope, setValueArg)
            })
        }, setValueFunctionScope)
    )
    table.insert(metatableVals, Ast.KeyedTableEntry(Ast.StringExpression(info.setValue.key), setvalueFunctionLiteral))

    -- Getvalue Entry
    local getValueFunctionScope = Scope:new(parentScope)
    local getValueSelf = getValueFunctionScope:addVariable()
    local getValueArg  = getValueFunctionScope:addVariable()
    local getValueIdxExpr
    if info.getValue.key == "__index" or info.setValue.key == "__index" then
        getValueIdxExpr = Ast.FunctionCallExpression(
            Ast.VariableExpression(getValueFunctionScope:resolveGlobal("rawget")),
            {
                Ast.VariableExpression(getValueFunctionScope, getValueSelf),
                Ast.StringExpression(info.valueName),
            }
        )
    else
        getValueIdxExpr = Ast.IndexExpression(
            Ast.VariableExpression(getValueFunctionScope, getValueSelf),
            Ast.StringExpression(info.valueName)
        )
    end
    local getvalueFunctionLiteral = Ast.FunctionLiteralExpression(
        {
            Ast.VariableExpression(getValueFunctionScope, getValueSelf),
            Ast.VariableExpression(getValueFunctionScope, getValueArg),
        },
        Ast.Block({
            Ast.ReturnStatement({ getValueIdxExpr })
        }, getValueFunctionScope)
    )
    table.insert(metatableVals, Ast.KeyedTableEntry(Ast.StringExpression(info.getValue.key), getvalueFunctionLiteral))

    parentScope:addReferenceToHigherScope(self.setMetatableVarScope, self.setMetatableVarId)
    return Ast.FunctionCallExpression(
        Ast.VariableExpression(self.setMetatableVarScope, self.setMetatableVarId),
        {
            Ast.TableConstructorExpression({
                Ast.KeyedTableEntry(Ast.StringExpression(info.valueName), expr)
            }),
            Ast.TableConstructorExpression(metatableVals)
        }
    )
end

function ProxifyLocals:apply(ast, pipeline)
    local rng = nil
    if pipeline and type(pipeline.getRandom) == "function" then
        rng = pipeline:getRandom()
        if rng and type(rng.derive) == "function" then
            rng = rng:derive("ProxifyLocals")
        end
    end

    local randRange
    if rng and type(rng.range) == "function" then
        randRange = function(a, b) return rng:range(a, b) end
    else
        randRange = function(a, b)
            if b == nil then return math.random(a) end
            return math.random(a, b)
        end
    end

    local localMetatableInfos = {}

    -- Only looks up, never creates. Safe to call anywhere.
    local function getInfo(scope, id)
        if not scope or scope.isGlobal then return nil end
        local s = localMetatableInfos[scope]
        if not s then return nil end
        local entry = s[id]
        if entry == nil or entry.locked then return nil end
        return entry
    end

    -- Creates info on first access. Only call this at declaration sites.
    local function getOrCreateInfo(scope, id)
        if not scope or scope.isGlobal then return nil end
        local s = localMetatableInfos[scope]
        if not s then
            s = {}
            localMetatableInfos[scope] = s
        end
        local entry = s[id]
        if entry == nil then
            entry = generateLocalMetatableInfo(pipeline, randRange)
            s[id] = entry
        end
        if entry.locked then return nil end
        return entry
    end

    local function disableMetatableInfo(scope, id)
        if not scope or scope.isGlobal then return end
        localMetatableInfos[scope] = localMetatableInfos[scope] or {}
        localMetatableInfos[scope][id] = { locked = true }
    end

    -- Setup top-level variables
    self.setMetatableVarScope = ast.body.scope
    self.setMetatableVarId    = ast.body.scope:addVariable()
    self.emptyFunctionScope   = ast.body.scope
    self.emptyFunctionId      = ast.body.scope:addVariable()
    local emptyFunctionUsed   = false

    local literalType = self.LiteralType
    local function makeLiteral()
        if literalType == "dictionary" then
            return RandomLiterals.Dictionary(pipeline, rng)
        elseif literalType == "number" then
            return RandomLiterals.Number(pipeline, rng)
        elseif literalType == "string" then
            return RandomLiterals.String(pipeline, rng)
        else
            return RandomLiterals.Any(pipeline, rng)
        end
    end

    -- Pass 1: lock all variables that must not be proxified
    visitast(ast, function(node, data)
        if node.kind == AstKind.ForStatement then
            if node.scope then
                disableMetatableInfo(node.scope, node.id)
            end
        end

        if node.kind == AstKind.ForInStatement then
            if node.scope then
                for _, id in ipairs(node.ids) do
                    disableMetatableInfo(node.scope, id)
                end
            end
        end

        if node.kind == AstKind.FunctionDeclaration
        or node.kind == AstKind.LocalFunctionDeclaration
        or node.kind == AstKind.FunctionLiteralExpression then
            for _, expr in ipairs(node.args) do
                if expr.kind == AstKind.VariableExpression and expr.scope then
                    disableMetatableInfo(expr.scope, expr.id)
                end
            end
        end
    end, nil)

    -- Pass 2: transform
    visitast(ast, nil, function(node, data)
        -- Local Variable Declaration
        if node.kind == AstKind.LocalVariableDeclaration then
            if node.scope then
                for i, id in ipairs(node.ids) do
                    local info = getOrCreateInfo(node.scope, id)
                    if info then
                        local expr = node.expressions[i] or Ast.NilExpression()
                        node.expressions[i] = self:CreateAssignmentExpression(info, expr, node.scope)
                    end
                end
            end
        end

        -- Assignment Statement
        if node.kind == AstKind.AssignmentStatement then
            if #node.lhs == 1 and node.lhs[1].kind == AstKind.AssignmentVariable then
                local variable = node.lhs[1]
                if variable.scope and data.scope then
                    local info = getInfo(variable.scope, variable.id)
                    if info then
                        local vexp = Ast.VariableExpression(variable.scope, variable.id)
                        vexp.__ignoreProxifyLocals = true
                        local newRhs = { info.setValue.constructor(vexp, node.rhs[1]) }
                        for i = 2, #node.rhs do newRhs[i] = node.rhs[i] end
                        emptyFunctionUsed = true
                        data.scope:addReferenceToHigherScope(self.emptyFunctionScope, self.emptyFunctionId)
                        return Ast.FunctionCallStatement(
                            Ast.VariableExpression(self.emptyFunctionScope, self.emptyFunctionId),
                            newRhs
                        )
                    end
                end
            end
        end

        -- Variable Expression
        if node.kind == AstKind.VariableExpression and not node.__ignoreProxifyLocals then
            if node.scope then
                local info = getInfo(node.scope, node.id)
                if info then
                    return info.getValue.constructor(node, makeLiteral())
                end
            end
        end

        -- Assignment Variable
        if node.kind == AstKind.AssignmentVariable then
            if node.scope then
                local info = getInfo(node.scope, node.id)
                if info then
                    return Ast.AssignmentIndexing(node, Ast.StringExpression(info.valueName))
                end
            end
        end

        -- Local Function Declaration
        if node.kind == AstKind.LocalFunctionDeclaration then
            if node.scope then
                local info = getOrCreateInfo(node.scope, node.id)
                if info then
                    local funcLiteral = Ast.FunctionLiteralExpression(node.args, node.body)
                    local newExpr = self:CreateAssignmentExpression(info, funcLiteral, node.scope)
                    return Ast.LocalVariableDeclaration(node.scope, { node.id }, { newExpr })
                end
            end
        end

        -- Function Declaration
        if node.kind == AstKind.FunctionDeclaration then
            if node.scope then
                local info = getInfo(node.scope, node.id)
                if info then
                    table.insert(node.indices, 1, info.valueName)
                end
            end
        end
    end)

    -- Inject empty function if needed
    if emptyFunctionUsed then
        table.insert(ast.body.statements, 1, Ast.LocalVariableDeclaration(
            self.emptyFunctionScope,
            { self.emptyFunctionId },
            { Ast.FunctionLiteralExpression({}, Ast.Block({}, Scope:new(ast.body.scope))) }
        ))
    end

    -- Inject setmetatable local
    table.insert(ast.body.statements, 1, Ast.LocalVariableDeclaration(
        self.setMetatableVarScope,
        { self.setMetatableVarId },
        { Ast.VariableExpression(self.setMetatableVarScope:resolveGlobal("setmetatable")) }
    ))
end

return ProxifyLocals;