-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- NumbersToExpressions.lua (TRANSFORMATIONS REMOVED)
--
-- This version keeps the step structure but disables all number transformations.

unpack = unpack or table.unpack

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local AstKind = Ast.AstKind

local NumbersToExpressions = Step:extend()
NumbersToExpressions.Description = "No-op step (number transformations removed)"
NumbersToExpressions.Name = "Numbers To Expressions (Disabled)"

NumbersToExpressions.SettingsDescriptor = {
	Threshold = {
		type = "number",
		default = 0,
		min = 0,
		max = 1,
	},
}

function NumbersToExpressions:init(_)
	-- No generators needed
end

function NumbersToExpressions:CreateNumberExpression(val, _)
	-- Always return the original number expression
	return Ast.NumberExpression(val)
end

function NumbersToExpressions:apply(ast, _)
	visitast(ast, nil, function(node, _)
		if not node then return nil end
		if node.kind == AstKind.NumberExpression then
			-- Return node unchanged (no transformation)
			return node
		end
	end)
end

return NumbersToExpressions