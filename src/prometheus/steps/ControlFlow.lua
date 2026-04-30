local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local visitast = require("prometheus.visitast")

local AstKind = Ast.AstKind

local ControlFlow = Step:extend()
ControlFlow.Description = "This step adds lightweight control-flow obfuscation wrappers."
ControlFlow.Name = "Control Flow"

ControlFlow.SettingsDescriptor = {
	Treshold = {
		type = "number",
		default = 0.35,
		min = 0,
		max = 1,
	},
	OpaquePredicate = {
		type = "boolean",
		default = true,
	},
}

local EXCLUDED = {
	[AstKind.BreakStatement] = true,
	[AstKind.ContinueStatement] = true,
	[AstKind.ReturnStatement] = true,
}

function ControlFlow:init(_) end

local function isSafeStatement(statement)
	return statement and not EXCLUDED[statement.kind]
end

function ControlFlow:wrapStatement(statement, parentScope)
	local wrapperScope = Scope:new(parentScope)
	local innerBlock = Ast.Block({ statement }, wrapperScope)

	if self.OpaquePredicate then
		local cond = Ast.EqualsExpression(
			Ast.AddExpression(Ast.NumberExpression(9), Ast.NumberExpression(1), false),
			Ast.NumberExpression(10),
			false
		)
		return Ast.IfStatement(cond, innerBlock, {}, nil)
	end

	return Ast.DoStatement(innerBlock)
end

function ControlFlow:apply(ast)
	visitast(ast, function(node)
		if node.kind ~= AstKind.Block then
			return
		end

		local statements = node.statements
		for i = 1, #statements do
			local statement = statements[i]
			if isSafeStatement(statement) and math.random() <= self.Treshold then
				statements[i] = self:wrapStatement(statement, node.scope)
			end
		end
	end)

	return ast
end

return ControlFlow
