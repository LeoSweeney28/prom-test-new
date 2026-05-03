-- ProxifyLocals.lua (Fixed & Stable)

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local visitast = require("prometheus.visitast")
local RandomLiterals = require("prometheus.randomLiterals")

local AstKind = Ast.AstKind

local ipairs = ipairs
local pairs = pairs
local type = type

local ProxifyLocals = Step:extend()
ProxifyLocals.Description = "Wraps locals into Proxy Objects"
ProxifyLocals.Name = "Proxify Locals"

ProxifyLocals.SettingsDescriptor = {
    LiteralType = {
        name = "LiteralType",
        description = "Type of randomly generated literals",
        type = "enum",
        values = { "dictionary", "number", "string", "any" },
        default = "number",
    },
    MaxUsageCount = {
        name = "MaxUsageCount",
        description = "Only proxify locals used this many times or fewer",
        type = "number",
        default = 8,
        min = 0,
        max = nil,
    },
}

-- Metamethod pool
local MetatableExpressions = {
    { constructor = Ast.AddExpression, key = "__add" },
    { constructor = Ast.SubExpression, key = "__sub" },
    { constructor = Ast.MulExpression, key = "__mul" },
    { constructor = Ast.DivExpression, key = "__div" },
    { constructor = Ast.PowExpression, key = "__pow" },
    { constructor = Ast.StrCatExpression, key = "__concat" },
}


function ProxifyLocals:_range(min, max)
    if self._rng and self._rng.range then
        return self._rng:range(min, max)
    end
    return max and math.random(min, max) or math.random(min)
end

function ProxifyLocals:init(_)
    -- override base
end

-- Fisher–Yates shuffle
local function pickOps(rand)
    local ops = {}
    for i = 1, #MetatableExpressions do
        ops[i] = MetatableExpressions[i]
    end
    for i = #ops, 2, -1 do
        local j = rand(1, i)
        ops[i], ops[j] = ops[j], ops[i]
    end
    return {
        setValue = ops[1],
        getValue = ops[2],
    }
end

local function callNameGenerator(gen, ...)
    if type(gen) == "table" then
        gen = gen.generateName
    end
    return gen(...)
end

local function generateLocalMetatableInfo(self, pipeline)
    local ops = pickOps(function(a, b) return self:_range(a, b) end)

    local valueName = callNameGenerator(pipeline.namegenerator, self:_range(1, 4096))

    return {
        setValue = ops.setValue,
        getValue = ops.getValue,
        valueName = valueName,
        valueExpr = Ast.StringExpression(valueName),
    }
end

local function isSafeProxifyInitializer(expr)
    if not expr then
        return true
    end

    local kind = expr.kind
    return kind == AstKind.BooleanExpression
        or kind == AstKind.NumberExpression
        or kind == AstKind.StringExpression
        or kind == AstKind.TableConstructorExpression
end

local function hasOpenReturnExpression(expr)
    if not expr then
        return false
    end

    local kind = expr.kind
    return kind == AstKind.FunctionCallExpression
        or kind == AstKind.PassSelfFunctionCallExpression
        or kind == AstKind.VarargExpression
end

function ProxifyLocals:CreateAssignmentExpression(info, expr, parentScope)
    local entries = {}

    -- setValue
    local sScope = Scope:new(parentScope)
    local selfVar = sScope:addVariable()
    local valVar = sScope:addVariable()

    local setFunc = Ast.FunctionLiteralExpression(
        {
            Ast.VariableExpression(sScope, selfVar),
            Ast.VariableExpression(sScope, valVar),
        },
        Ast.Block({
            Ast.AssignmentStatement({
                Ast.AssignmentIndexing(
                    Ast.VariableExpression(sScope, selfVar),
                    info.valueExpr
                )
            }, {
                Ast.VariableExpression(sScope, valVar)
            })
        }, sScope)
    )

    entries[#entries + 1] = Ast.KeyedTableEntry(
        Ast.StringExpression(info.setValue.key),
        setFunc
    )

    -- getValue
    local gScope = Scope:new(parentScope)
    local gSelf = gScope:addVariable()

    local getExpr
    if info.getValue.key == "__index" or info.setValue.key == "__index" then
        getExpr = Ast.FunctionCallExpression(
            Ast.VariableExpression(gScope:resolveGlobal("rawget")),
            {
                Ast.VariableExpression(gScope, gSelf),
                info.valueExpr
            }
        )
    else
        getExpr = Ast.IndexExpression(
            Ast.VariableExpression(gScope, gSelf),
            info.valueExpr
        )
    end

    local getFunc = Ast.FunctionLiteralExpression(
        { Ast.VariableExpression(gScope, gSelf) },
        Ast.Block({
            Ast.ReturnStatement({ getExpr })
        }, gScope)
    )

    entries[#entries + 1] = Ast.KeyedTableEntry(
        Ast.StringExpression(info.getValue.key),
        getFunc
    )

    parentScope:addReferenceToHigherScope(self.setMetatableVarScope, self.setMetatableVarId)

    return Ast.FunctionCallExpression(
        Ast.VariableExpression(self.setMetatableVarScope, self.setMetatableVarId),
        {
            Ast.TableConstructorExpression({
                Ast.KeyedTableEntry(info.valueExpr, expr)
            }),
            Ast.TableConstructorExpression(entries)
        }
    )
end

function ProxifyLocals:apply(ast, pipeline)
    self._rng = pipeline and pipeline.getRandom and pipeline:getRandom()
    if self._rng and self._rng.derive then
        self._rng = self._rng:derive("ProxifyLocals")
    end

    local localInfos = {}
    local literalCache = {}
    local usageCounts = {}

    visitast(ast, function(node)
        if not node or not node.scope or node.scope.isGlobal then
            return
        end

        if node.kind == AstKind.VariableExpression or node.kind == AstKind.AssignmentVariable then
            usageCounts[node.scope] = usageCounts[node.scope] or {}
            usageCounts[node.scope][node.id] = (usageCounts[node.scope][node.id] or 0) + 1
        end
    end)

    local maxUsageCount = tonumber(self.MaxUsageCount) or 8

    local function getInfo(scope, id)
        if not scope or scope.isGlobal then return nil end
        if scope == self.setMetatableVarScope and id == self.setMetatableVarId then
            return nil
        end

        local scopeCounts = usageCounts[scope]
        if scopeCounts and (scopeCounts[id] or 0) > maxUsageCount then
            return nil
        end

        localInfos[scope] = localInfos[scope] or {}
        local entry = localInfos[scope][id]

        if entry ~= nil then
            return entry.locked and nil or entry
        end

        local info = generateLocalMetatableInfo(self, pipeline)
        localInfos[scope][id] = info
        return info
    end

    local function disable(scope, id)
        if not scope or scope.isGlobal then return end
        localInfos[scope] = localInfos[scope] or {}
        localInfos[scope][id] = { locked = true }
    end

    local function getLiteral(info)
        return literalCache[info] or (function()
            local lit
            if self.LiteralType == "dictionary" then
                lit = RandomLiterals.Dictionary(pipeline, self._rng)
            elseif self.LiteralType == "number" then
                lit = RandomLiterals.Number(pipeline, self._rng)
            elseif self.LiteralType == "string" then
                lit = RandomLiterals.String(pipeline, self._rng)
            else
                lit = RandomLiterals.Any(pipeline, self._rng)
            end
            literalCache[info] = lit
            return lit
        end)()
    end

    -- setmetatable binding
    self.setMetatableVarScope = ast.body.scope
    self.setMetatableVarId = ast.body.scope:addVariable()

    table.insert(ast.body.statements, 1,
        Ast.LocalVariableDeclaration(self.setMetatableVarScope, { self.setMetatableVarId }, {
            Ast.VariableExpression(self.setMetatableVarScope:resolveGlobal("setmetatable"))
        })
    )

    visitast(ast, function(node)
        if node.kind == AstKind.ForStatement then
            disable(node.scope, node.id)

        elseif node.kind == AstKind.ForInStatement then
            for _, id in ipairs(node.ids) do
                disable(node.scope, id)
            end

        elseif node.kind == AstKind.FunctionDeclaration
            or node.kind == AstKind.LocalFunctionDeclaration
            or node.kind == AstKind.FunctionLiteralExpression then

            for _, arg in ipairs(node.args) do
                if arg.kind == AstKind.VariableExpression then
                    disable(arg.scope, arg.id)
                end
            end
        elseif node.kind == AstKind.LocalVariableDeclaration then
            local exprCount = #node.expressions
            local lastExpr = node.expressions[exprCount]
            if #node.ids ~= exprCount or hasOpenReturnExpression(lastExpr) then
                for _, id in ipairs(node.ids) do
                    disable(node.scope, id)
                end
            end
        elseif node.kind == AstKind.AssignmentStatement then
            local rhsCount = #node.rhs
            local lastExpr = node.rhs[rhsCount]
            if #node.lhs ~= rhsCount or hasOpenReturnExpression(lastExpr) then
                for _, lhs in ipairs(node.lhs) do
                    if lhs.kind == AstKind.AssignmentVariable then
                        disable(lhs.scope, lhs.id)
                    end
                end
            end
        end
    end,
    function(node)
        -- Local declarations
        if node.kind == AstKind.LocalVariableDeclaration then
            for i, id in ipairs(node.ids) do
                local info = getInfo(node.scope, id)
                local expr = node.expressions[i] or Ast.NilExpression()
                if info and info.setValue and info.getValue and info.valueExpr and isSafeProxifyInitializer(expr) then
                    node.expressions[i] = self:CreateAssignmentExpression(info, expr, node.scope)
                elseif info then
                    disable(node.scope, id)
                end
            end

        -- Reading a local
        elseif node.kind == AstKind.VariableExpression and not node.__ignoreProxifyLocals then
            local info = getInfo(node.scope, node.id)
            if info and info.getValue then
                return info.getValue.constructor(node, getLiteral(info))
            end

        -- Writing to a local
        elseif node.kind == AstKind.AssignmentStatement then
            if #node.lhs == 1 and node.lhs[1].kind == AstKind.AssignmentVariable then
                local var = node.lhs[1]
                local info = getInfo(var.scope, var.id)

                if info and info.setValue then
                    local vexp = Ast.VariableExpression(var.scope, var.id)
                    vexp.__ignoreProxifyLocals = true

                    return Ast.AssignmentStatement(node.lhs, {
                        info.setValue.constructor(vexp, node.rhs[1])
                    })
                end
            end
        
        -- Replace plain assignment variable (some AST forms use this)
        elseif node.kind == AstKind.AssignmentVariable then
            local info = getInfo(node.scope, node.id)
            if info and info.valueExpr then
                local varExpr = Ast.VariableExpression(node.scope, node.id)
                varExpr.__ignoreProxifyLocals = true
                return Ast.AssignmentIndexing(varExpr, info.valueExpr)
            end

        -- Local functions
        elseif node.kind == AstKind.LocalFunctionDeclaration then
            local info = getInfo(node.scope, node.id)
            if info then
                local func = Ast.FunctionLiteralExpression(node.args, node.body)
                return Ast.LocalVariableDeclaration(node.scope, { node.id }, {
                    self:CreateAssignmentExpression(info, func, node.scope)
                })
            end

        -- Global function declarations
        elseif node.kind == AstKind.FunctionDeclaration then
            local info = getInfo(node.scope, node.id)
            if info then
                table.insert(node.indices, 1, info.valueName)
            end
        end
    end)

    self._rng = nil
end

return ProxifyLocals
