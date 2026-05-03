-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- emit.lua
--
-- This Script contains the container function body emission for the compiler.

local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local util = require("prometheus.util");
local constants = require("prometheus.compiler.constants");
local MAX_REGS = constants.MAX_REGS;
local BlockOptimizer = require("prometheus.compiler.block_optimizer");
local VmHardening = require("prometheus.compiler.vm_hardening");

return function(Compiler)
    local function shuffleWithCompilerRng(list, randRange)
        for i = #list, 2, -1 do
            local j = randRange(1, i)
            list[i], list[j] = list[j], list[i]
        end
        return list
    end

    -- Add dispatcher obfuscation: wrap with do/end block
    function Compiler:wrapDispatcherInObfuscation(dispatcherBlock)
        -- Wrap dispatcher in a do/end block for an extra control-flow layer
        local wrappedScope = Scope:new(dispatcherBlock.scope);
        return Ast.Block({
            Ast.DoStatement(dispatcherBlock)
        }, wrappedScope);
    end

    -- Add unreachable but syntactically valid decoy statements
    function Compiler:addDecoyDeclarations(scope, count)
        local decoys = {};
        for i = 1, count do
            if self:randRange(1, 2) == 1 then
                local decoyId = scope:addVariable("_D" .. self:randRange(1000, 9999));
                table.insert(decoys, Ast.LocalVariableDeclaration(
                    scope,
                    {decoyId},
                    {Ast.NumberExpression(self:randRange(-65536, 65536))}
                ));
            end
        end
        return decoys;
    end

    -- Add complex decoy expressions (computed values, not just constants)
    function Compiler:addComplexDecoyDeclarations(scope, count)
        local decoys = {};
        for i = 1, count do
            if self:randRange(1, 3) == 1 then
                -- Create computed decoy: random arithmetic expression
                local left = Ast.NumberExpression(self:randRange(1, 1000));
                local right = Ast.NumberExpression(self:randRange(1, 1000));
                local op = self:randRange(1, 4);
                local expr;
                
                if op == 1 then
                    expr = Ast.AddExpression(left, right);
                elseif op == 2 then
                    expr = Ast.SubtractExpression(left, right);
                elseif op == 3 then
                    expr = Ast.MultiplyExpression(left, right);
                else
                    expr = Ast.PowerExpression(left, Ast.NumberExpression(2));
                end
                
                local decoyId = scope:addVariable("_CD" .. self:randRange(1000, 9999));
                table.insert(decoys, Ast.LocalVariableDeclaration(
                    scope,
                    {decoyId},
                    {expr}
                ));
            end
        end
        return decoys;
    end

    -- Cache dispatcher bounds to avoid redundant calculations
    function Compiler:cacheDispatcherBounds(blocks)
        local boundsCache = {};
        for i = 1, #blocks - 1 do
            local leftId = blocks[i].id;
            local rightId = blocks[i + 1].id;
            local bound = math.floor((leftId + rightId) / 2);
            boundsCache[i] = bound;
        end
        return boundsCache;
    end

    function Compiler:emitContainerFuncBody()
        local blocks = {};

        local hardenedBlocks = VmHardening:hardenBlocks(self.blocks, {
            randRange = function(a, b) return self:randRange(a, b) end,
            maxStatements = self._maxStatements or 1000,
        });

        shuffleWithCompilerRng(hardenedBlocks, function(a, b) return self:randRange(a, b) end);

        for i, block in ipairs(hardenedBlocks) do
            local id = block.id;
            local blockstats = block.statements;

            if not block.scope then
                block.scope = Scope:new(self.containerFuncScope or self.scope);
            end

            blockstats = BlockOptimizer:reorderStatements(blockstats, function(a, b) return self:randRange(a, b) end);

            local mergedBlockStats = BlockOptimizer:mergeUntilStable(blockstats);

            blockstats = {};
            for idx, stat in ipairs(mergedBlockStats) do
                blockstats[idx] = stat.statement;
            end

            if block.splitNextBlockId then
                if block.scope then
                    table.insert(blockstats, self:setPos(block.scope, block.splitNextBlockId));
                end
            end

            local blockScope = block.scope or Scope:new(self.containerFuncScope or self.scope)
            local block = { id = id, index = i, block = Ast.Block(blockstats, blockScope) }
            table.insert(blocks, block);
            blocks[id] = block;
        end

        table.sort(blocks, function(a, b) return a.id < b.id end);

        -- Build a strict threshold condition between adjacent block IDs.
        -- Using a midpoint avoids exact-id comparisons while preserving dispatch.
        local function buildBlockThresholdCondition(scope, leftId, rightId, useAndOr)
            if not scope then
                scope = Scope:new(self.containerFuncScope or self.scope)
            end
            local bound = math.floor((leftId + rightId) / 2);
            local posExpr = self:pos(scope);
            local boundExpr = Ast.NumberExpression(bound);

            if useAndOr then
                -- Kept for compatibility with caller variations.
                return Ast.LessThanExpression(posExpr, boundExpr);
            else
                local variant = self:randRange(1, 2);
                if variant == 1 then
                    return Ast.LessThanExpression(posExpr, boundExpr);
                else
                    return Ast.GreaterThanExpression(boundExpr, posExpr);
                end
            end
        end

        -- Build an elseif chain for a range of blocks
        local function buildElseifChain(tb, l, r, pScope)
            -- Handle invalid range by returning an empty block
            if r < l then
                local emptyScope = Scope:new(pScope);
                return Ast.Block({}, emptyScope);
            end

            local len = r - l + 1;

            -- For single block
            if len == 1 then
                tb[l].block.scope:setParent(pScope);
                return tb[l].block;
            end

            -- For small ranges, use elseif chain
            if len <= 4 then
                local ifScope = Scope:new(pScope);
                local elseifs = {};

                -- First block uses the first midpoint threshold
                tb[l].block.scope:setParent(ifScope);
                local firstCondition = buildBlockThresholdCondition(ifScope, tb[l].id, tb[l + 1].id, false);
                local firstBlock = tb[l].block;

                -- Middle blocks use their upper midpoint threshold
                for i = l + 1, r - 1 do
                    tb[i].block.scope:setParent(ifScope);
                    local condition = buildBlockThresholdCondition(ifScope, tb[i].id, tb[i + 1].id, false);
                    table.insert(elseifs, {
                        condition = condition,
                        body = tb[i].block
                    });
                end

                -- Last block becomes else
                tb[r].block.scope:setParent(ifScope);
                local elseBlock = tb[r].block;

                return Ast.Block({
                    Ast.IfStatement(firstCondition, firstBlock, elseifs, elseBlock);
                }, ifScope);
            end

            -- For larger ranges, use binary split with and/or chaining
            local mid = l + math.ceil(len / 2);
            local leftMaxId = tb[mid - 1].id;
            local rightMinId = tb[mid].id;
            -- Float-safe split: any bound strictly between adjacent IDs works.
            -- Midpoint avoids integer-only math.random(min, max) behavior.
            local bound = math.floor((leftMaxId + rightMinId) / 2);
            local ifScope = Scope:new(pScope);

            local lBlock = buildElseifChain(tb, l, mid - 1, pScope);
            local rBlock = buildElseifChain(tb, mid, r, pScope);

            -- Randomly choose between different condition styles
            local condStyle = self:randRange(1, 3);
            local condition;
            local trueBlock, falseBlock;

            if condStyle == 1 then
                -- pos < bound
                condition = Ast.LessThanExpression(self:pos(ifScope), Ast.NumberExpression(bound));
                trueBlock, falseBlock = lBlock, rBlock;
            elseif condStyle == 2 then
                -- bound > pos
                condition = Ast.GreaterThanExpression(Ast.NumberExpression(bound), self:pos(ifScope));
                trueBlock, falseBlock = lBlock, rBlock;
            else
                -- Equivalent split using strict > with branches reversed.
                condition = Ast.GreaterThanExpression(self:pos(ifScope), Ast.NumberExpression(bound));
                trueBlock, falseBlock = rBlock, lBlock;
            end

            return Ast.Block({
                Ast.IfStatement(condition, trueBlock, {}, falseBlock);
            }, ifScope);
        end

        local whileBody = buildElseifChain(blocks, 1, #blocks, self.containerFuncScope);
        
        -- Apply obfuscation wrapper to dispatcher
        whileBody = self:wrapDispatcherInObfuscation(whileBody);
        
        if self.whileScope then
            -- Ensure whileScope is properly connected
            self.whileScope:setParent(self.containerFuncScope);
        end

        self.whileScope:addReferenceToHigherScope(self.containerFuncScope, self.returnVar, 1);
        self.whileScope:addReferenceToHigherScope(self.containerFuncScope, self.posVar);

        self.containerFuncScope:addReferenceToHigherScope(self.scope, self.unpackVar);

        local declarations = {
            self.returnVar,
        }

        for i, var in pairs(self.registerVars) do
            if(i ~= MAX_REGS) then
                table.insert(declarations, var);
            end
        end

        local stats = {}

        if self.maxUsedRegister >= MAX_REGS then
            table.insert(stats, Ast.LocalVariableDeclaration(self.containerFuncScope, {self.registerVars[MAX_REGS]}, {Ast.TableConstructorExpression({})}));
        end

        table.insert(stats, Ast.LocalVariableDeclaration(self.containerFuncScope, util.shuffle(declarations), {}));
        
        -- Add optional decoy declarations for obfuscation
        local decoys = self:addDecoyDeclarations(self.containerFuncScope, self:randRange(0, 3));
        for _, decoy in ipairs(decoys) do
            table.insert(stats, decoy);
        end

        table.insert(stats, Ast.WhileStatement(
            Ast.VariableExpression(self.containerFuncScope, self.posVar),
            whileBody
        ));

        -- Ensure returnVar always has a valid value before returning
        table.insert(stats, Ast.AssignmentStatement({
            Ast.AssignmentVariable(self.containerFuncScope, self.returnVar)
        }, {
            Ast.TableConstructorExpression({})
        }));

        table.insert(stats, Ast.AssignmentStatement({
            Ast.AssignmentVariable(self.containerFuncScope, self.posVar)
        }, {
            Ast.LenExpression(Ast.VariableExpression(self.containerFuncScope, self.detectGcCollectVar))
        }));

        -- Ensure returnVar has a fallback value
        table.insert(stats, Ast.AssignmentStatement({
            Ast.AssignmentVariable(self.containerFuncScope, self.returnVar)
        }, {
            Ast.VariableExpression(self.containerFuncScope, self.returnVar)
        }));

        table.insert(stats, Ast.ReturnStatement{
            Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.unpackVar), {
                Ast.VariableExpression(self.containerFuncScope, self.returnVar)
            })
        });

        -- Ensure we always return a valid value even if VM fails
        table.insert(stats, 1, Ast.AssignmentStatement({
            Ast.AssignmentVariable(self.containerFuncScope, self.returnVar)
        }, {
            Ast.TableConstructorExpression({})
        }));

        table.insert(stats, Ast.AssignmentStatement({
            Ast.AssignmentVariable(self.containerFuncScope, self.posVar)
        }, {
            Ast.LenExpression(Ast.VariableExpression(self.containerFuncScope, self.detectGcCollectVar))
        }));
        });

        return Ast.Block(stats, self.containerFuncScope);
    end
end
