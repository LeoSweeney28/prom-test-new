-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- block_optimizer.lua
--
-- Helper routines for VM block-level statement scheduling and assignment coalescing.

local Ast = require("prometheus.ast")
local AstKind = Ast.AstKind

local BlockOptimizer = {}

local function hasAnyEntries(tbl)
    return type(tbl) == "table" and next(tbl) ~= nil
end

local function unionLookupTables(a, b)
    local out = {}
    for k, v in pairs(a or {}) do
        out[k] = v
    end
    for k, v in pairs(b or {}) do
        out[k] = v
    end
    return out
end

local function normalizeStatMeta(stat)
    if type(stat) ~= "table" then
        return {
            statement = stat,
            reads = {},
            writes = {},
            usesUpvals = false,
        }
    end

    if type(stat.reads) ~= "table" then
        stat.reads = {}
    end
    if type(stat.writes) ~= "table" then
        stat.writes = {}
    end
    if stat.usesUpvals == nil then
        stat.usesUpvals = false
    end
    return stat
end

local function hasUnsafeRhs(rhsList)
    for _, rhsExpr in ipairs(rhsList) do
        if type(rhsExpr) ~= "table" then
            return true
        end
        local kind = rhsExpr.kind
        if kind == AstKind.FunctionCallExpression
            or kind == AstKind.PassSelfFunctionCallExpression
            or kind == AstKind.VarargExpression then
            return true
        end
    end
    return false
end

local function canMergeParallelAssignmentStatements(statA, statB)
    statA = normalizeStatMeta(statA)
    statB = normalizeStatMeta(statB)

    if statA.usesUpvals or statB.usesUpvals then
        return false
    end

    local a = statA.statement
    local b = statB.statement
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    if a.kind ~= AstKind.AssignmentStatement or b.kind ~= AstKind.AssignmentStatement then
        return false
    end

    if type(a.lhs) ~= "table" or type(a.rhs) ~= "table" or type(b.lhs) ~= "table" or type(b.rhs) ~= "table" then
        return false
    end

    if #a.lhs ~= #a.rhs or #b.lhs ~= #b.rhs then
        return false
    end

    if hasUnsafeRhs(a.rhs) or hasUnsafeRhs(b.rhs) then
        return false
    end

    local aReads = statA.reads
    local aWrites = statA.writes
    local bReads = statB.reads
    local bWrites = statB.writes

    if not hasAnyEntries(aWrites) and not hasAnyEntries(bWrites) then
        return false
    end

    for r in pairs(aReads) do
        if bWrites[r] then
            return false
        end
    end

    for r in pairs(aWrites) do
        if bWrites[r] or bReads[r] then
            return false
        end
    end

    return true
end

local function mergeParallelAssignmentStatements(statA, statB)
    local lhs = {}
    local rhs = {}
    local aLhs, bLhs = statA.statement.lhs, statB.statement.lhs
    local aRhs, bRhs = statA.statement.rhs, statB.statement.rhs

    for i = 1, #aLhs do lhs[i] = aLhs[i] end
    for i = 1, #bLhs do lhs[#aLhs + i] = bLhs[i] end
    for i = 1, #aRhs do rhs[i] = aRhs[i] end
    for i = 1, #bRhs do rhs[#aRhs + i] = bRhs[i] end

    return {
        statement = Ast.AssignmentStatement(lhs, rhs),
        writes = unionLookupTables(statA.writes, statB.writes),
        reads = unionLookupTables(statA.reads, statB.reads),
        usesUpvals = statA.usesUpvals or statB.usesUpvals,
    }
end

function BlockOptimizer:canSwap(curr, prev)
    curr = normalizeStatMeta(curr)
    prev = normalizeStatMeta(prev)

    if prev.usesUpvals and curr.usesUpvals then
        return false
    end

    local reads = curr.reads
    local writes = curr.writes
    local reads2 = prev.reads
    local writes2 = prev.writes

    for r in pairs(reads2) do
        if writes[r] then
            return false
        end
    end

    for r in pairs(writes2) do
        if writes[r] or reads[r] then
            return false
        end
    end

    return true
end

function BlockOptimizer:reorderStatements(blockstats, randRange)
    for i = 2, #blockstats do
        local stat = normalizeStatMeta(blockstats[i])
        local maxShift = 0
        for shift = 1, i - 1 do
            local prev = normalizeStatMeta(blockstats[i - shift])
            if not self:canSwap(stat, prev) then
                break
            end
            maxShift = shift
        end

        local rng = randRange or math.random
        local shift = rng(0, maxShift)
        for j = 1, shift do
            blockstats[i - j], blockstats[i - j + 1] = blockstats[i - j + 1], blockstats[i - j]
        end
    end

    return blockstats
end

function BlockOptimizer:mergeAdjacentParallelAssignments(blockstats)
    local merged = {}
    local i = 1

    while i <= #blockstats do
        local stat = normalizeStatMeta(blockstats[i])
        i = i + 1

        while i <= #blockstats do
            local nextStat = normalizeStatMeta(blockstats[i])
            if not canMergeParallelAssignmentStatements(stat, nextStat) then
                break
            end
            stat = mergeParallelAssignmentStatements(stat, nextStat)
            i = i + 1
        end

        merged[#merged + 1] = stat
    end

    return merged
end

function BlockOptimizer:mergeUntilStable(blockstats)
    local merged = self:mergeAdjacentParallelAssignments(blockstats)
    for _ = 1, #merged do
        local nextMerged = self:mergeAdjacentParallelAssignments(merged)
        if #nextMerged == #merged then
            merged = nextMerged
            break
        end
        merged = nextMerged
    end
    return merged
end

return BlockOptimizer
