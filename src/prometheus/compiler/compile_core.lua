-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- compile_core.lua
-- This Script contains the core compilation functions: compileTopNode, compileFunction, compileBlock,
-- compileStatement, and compileExpression

local compileTop = require("prometheus.compiler.compile_top");
local statementHandlers = require("prometheus.compiler.statements");
local expressionHandlers = require("prometheus.compiler.expressions");
local Ast = require("prometheus.ast");
local logger = require("logger");

return function(Compiler)
    compileTop(Compiler);

    function Compiler:compileStatement(statement, funcDepth)
        if not statement then return end
        local handler = statement.kind and statementHandlers[statement.kind];
        if handler then
            handler(self, statement, funcDepth);
            return;
        end
        logger:error(string.format("%s is not a compilable statement!", statement.kind or "nil"));
    end

    function Compiler:compileExpression(expression, funcDepth, numReturns)
        if not expression then return nil end
        local handler = expression.kind and expressionHandlers[expression.kind];
        if handler then
            return handler(self, expression, funcDepth, numReturns);
        end
        logger:error(string.format("%s is not a compilable expression!", expression.kind or "nil"));
    end
end
