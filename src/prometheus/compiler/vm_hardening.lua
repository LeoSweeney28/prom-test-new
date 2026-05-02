-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- vm_hardening.lua
--
-- Defensive normalization and hardening helpers for VM compilation/emission.

local Ast = require("prometheus.ast")
local AstKind = Ast.AstKind

local VmHardening = {}

local function cloneLookup(src)
    local out = {}
    for k, v in pairs(src or {}) do
        out[k] = v
    end
    return out
end

local function isTable(t)
    return type(t) == "table"
end

function VmHardening:normalizeStatementMeta(stat)
    if type(stat) ~= "table" then
        return {
            statement = stat,
            writes = {},
            reads = {},
            usesUpvals = false,
        }
    end

    -- Only create DoStatement if stat.statement is nil or invalid
    -- This prevents empty do end blocks in the output
    if stat.statement == nil or type(stat.statement) ~= "table" then
        -- Instead of creating an empty block, mark this as invalid
        -- The compiler should skip invalid statements
        stat.statement = nil
        stat.skipEmit = true
    end

    if not isTable(stat.writes) then
        stat.writes = {}
    end
    if not isTable(stat.reads) then
        stat.reads = {}
    end
    if stat.usesUpvals == nil then
        stat.usesUpvals = false
    end

    return stat
end

function VmHardening:normalizeBlock(block)
    if type(block) ~= "table" then
        return {
            id = 0,
            statements = {},
            scope = nil,
            advanceToNextBlock = false,
        }
    end

    block.id = tonumber(block.id) or 0
    if not isTable(block.statements) then
        block.statements = {}
    end
    if block.advanceToNextBlock == nil then
        block.advanceToNextBlock = true
    end

    local normalizedStatements = {}
    for i = 1, #block.statements do
        local normalized = self:normalizeStatementMeta(block.statements[i])
        normalizedStatements[#normalizedStatements + 1] = normalized
    end
    block.statements = normalizedStatements

    return block
end

function VmHardening:ensureUniqueBlockIds(blocks, randRange)
    local used = {}
    for _, block in ipairs(blocks or {}) do
        self:normalizeBlock(block)
        local id = block.id
        if used[id] then
            local newId
            repeat
                newId = randRange(0, 2 ^ 24)
            until not used[newId]
            block.id = newId
            used[newId] = true
        else
            used[id] = true
        end
    end
end

function VmHardening:compactReadsWrites(stat)
    stat = self:normalizeStatementMeta(stat)

    local reads = cloneLookup(stat.reads)
    local writes = cloneLookup(stat.writes)

    for reg in pairs(writes) do
        if reads[reg] then
            reads[reg] = nil
        end
    end

    stat.reads = reads
    stat.writes = writes
    return stat
end

function VmHardening:compactBlockMetadata(block)
    block = self:normalizeBlock(block)
    for i = 1, #block.statements do
        block.statements[i] = self:compactReadsWrites(block.statements[i])
    end
    return block
end

function VmHardening:isTrivialAssignment(statement)
    if type(statement) ~= "table" then
        return false
    end
    if statement.kind ~= AstKind.AssignmentStatement then
        return false
    end
    if type(statement.lhs) ~= "table" or type(statement.rhs) ~= "table" then
        return false
    end
    if #statement.lhs ~= 1 or #statement.rhs ~= 1 then
        return false
    end

    local lhs = statement.lhs[1]
    local rhs = statement.rhs[1]
    if type(lhs) ~= "table" or type(rhs) ~= "table" then
        return false
    end

    if lhs.kind == AstKind.AssignmentVariable and rhs.kind == AstKind.VariableExpression then
        return lhs.id == rhs.id
    end

    return false
end

function VmHardening:removeTrivialSelfAssignments(block)
    block = self:normalizeBlock(block)
    local out = {}
    for i = 1, #block.statements do
        local stat = self:normalizeStatementMeta(block.statements[i])
        local statement = stat.statement
        if not self:isTrivialAssignment(statement) then
            out[#out + 1] = stat
        end
    end
    block.statements = out
    return block
end

function VmHardening:splitHugeBlocks(block, maxStatements, randRange)
    block = self:normalizeBlock(block)
    maxStatements = tonumber(maxStatements) or 128

    if #block.statements <= maxStatements then
        return { block }
    end

    local chunks = {}
    local cursor = 1
    while cursor <= #block.statements do
        local upper = math.min(cursor + maxStatements - 1, #block.statements)
        local newBlock = {
            id = randRange(0, 2 ^ 24),
            statements = {},
            scope = block.scope,
            advanceToNextBlock = block.advanceToNextBlock,
        }
        for i = cursor, upper do
            newBlock.statements[#newBlock.statements + 1] = block.statements[i]
        end
        chunks[#chunks + 1] = newBlock
        cursor = upper + 1
    end

    return chunks
end

function VmHardening:hardenBlocks(blocks, opts)
    opts = opts or {}
    local randRange = opts.randRange or math.random
    local maxStatements = opts.maxStatements or 140

    local normalized = {}
    for i = 1, #(blocks or {}) do
        local block = self:normalizeBlock(blocks[i])
        block = self:compactBlockMetadata(block)
        block = self:removeTrivialSelfAssignments(block)
        normalized[#normalized + 1] = block
    end

    self:ensureUniqueBlockIds(normalized, randRange)

    local expanded = {}
    for i = 1, #normalized do
        local parts = self:splitHugeBlocks(normalized[i], maxStatements, randRange)
        for j = 1, #parts do
            expanded[#expanded + 1] = parts[j]
        end
    end

    self:ensureUniqueBlockIds(expanded, randRange)
    return expanded
end

return VmHardening
