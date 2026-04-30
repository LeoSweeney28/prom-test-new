-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- boolean.lua
--
-- This Script contains the expression handler for the BooleanExpression.

local Ast = require("prometheus.ast");

local expressionEvaluators = {
    [Ast.GreaterThanExpression] = function(left, right)
        return left > right
    end,
    [Ast.LessThanExpression] = function(left, right)
        return left < right
    end,
    [Ast.GreaterThanOrEqualsExpression] = function(left, right)
        return left >= right
    end,
    [Ast.LessThanOrEqualsExpression] = function(left, right)
        return left <= right
    end,
    [Ast.NotEqualsExpression] = function(left, right)
        return left ~= right
    end,
}

local function createRandomASTCFlowExpression(compiler, resultBool)
    local expTB = {
        Ast.GreaterThanExpression,
        Ast.LessThanExpression,
        Ast.GreaterThanOrEqualsExpression,
        Ast.LessThanOrEqualsExpression,
        Ast.NotEqualsExpression
    }

    local leftInt, rightInt, boolResult, randomExp
    repeat
        randomExp = expTB[compiler:randRange(1, #expTB)]
        leftInt = Ast.NumberExpression(compiler:randRange(1, 2^24))
        rightInt = Ast.NumberExpression(compiler:randRange(1, 2^24))
        boolResult = expressionEvaluators[randomExp](leftInt.value, rightInt.value)
    until boolResult == resultBool

    return randomExp(leftInt, rightInt, false)
end

return function(self, expression, _, numReturns)
    local scope = self.activeBlock.scope;
    local regs = {};
    for i = 1, numReturns do
        regs[i] = self:allocRegister();
        if i == 1 then
            self:addStatement(self:setRegister(scope, regs[i], createRandomASTCFlowExpression(self, expression.value)), {regs[i]}, {}, false);
        else
            self:addStatement(self:setRegister(scope, regs[i], Ast.NilExpression()), {regs[i]}, {}, false);
        end
    end
    return regs;
end;
