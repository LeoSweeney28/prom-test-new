local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")

local AstKind = Ast.AstKind

local ControlFlow = Step:extend()
ControlFlow.Description = "This step adds lightweight control-flow obfuscation wrappers."
ControlFlow.Name = "Control Flow"

ControlFlow.SettingsDescriptor = {
	Treshold = {
		type = "number",
		default = 0.85,
		min = 0,
		max = 1,
	},
	OpaquePredicate = {
		type = "boolean",
		default = true,
	},
	MaxStatementsPerBlock = {
		type = "number",
		default = 256,
		min = 0,
		max = 2048,
	},
	WrapLayers = {
		type = "number",
		default = 2,
		min = 1,
		max = 6,
	},
}

local EXCLUDED = {
	[AstKind.BreakStatement] = true,
	[AstKind.ContinueStatement] = true,
	[AstKind.ReturnStatement] = true,
	[AstKind.LocalVariableDeclaration] = true,
	[AstKind.LocalFunctionDeclaration] = true,
	[AstKind.FunctionDeclaration] = true,
	[AstKind.ForStatement] = true,
	[AstKind.ForInStatement] = true,
	[AstKind.WhileStatement] = true,
	[AstKind.RepeatStatement] = true,
}

function ControlFlow:init(_) end

local function canWrapStatement(statement)
	return statement and not EXCLUDED[statement.kind]
end

function ControlFlow:createOpaqueTrueExpression()
	local a = math.random(1200, 9999)
	local b = math.random(31, 97)
	local c = a * b

	return Ast.EqualsExpression(
		Ast.SubExpression(
			Ast.NumberExpression(c),
			Ast.MulExpression(Ast.NumberExpression(a - 1), Ast.NumberExpression(b), false),
			false
		),
		Ast.NumberExpression(b),
		false
	)
end

function ControlFlow:wrapStatement(statement, parentScope)
	local wrapped = statement
	for _ = 1, self.WrapLayers do
		local wrapperScope = Scope:new(parentScope)
		local innerBlock = Ast.Block({ wrapped }, wrapperScope)

		if self.OpaquePredicate then
			local cond = self:createOpaqueTrueExpression()
			wrapped = Ast.IfStatement(cond, innerBlock, {}, nil)
		else
			wrapped = Ast.DoStatement(innerBlock)
		end
	end

	return wrapped
end

function ControlFlow:processBlock(block)
	if not block or block.kind ~= AstKind.Block then
		return
	end

	local wrappedInBlock = 0
	local statements = block.statements
	for i = 1, #statements do
		local statement = statements[i]

		if statement.kind == AstKind.DoStatement and statement.body then
			self:processBlock(statement.body)
		elseif statement.kind == AstKind.IfStatement then
			self:processBlock(statement.body)
			for _, elseifPart in ipairs(statement.elseifs or {}) do
				self:processBlock(elseifPart.body)
			end
			self:processBlock(statement.elsebody)
		elseif statement.kind == AstKind.WhileStatement or statement.kind == AstKind.RepeatStatement then
			self:processBlock(statement.body)
		elseif statement.kind == AstKind.ForStatement or statement.kind == AstKind.ForInStatement then
			self:processBlock(statement.body)
		elseif statement.kind == AstKind.FunctionDeclaration or statement.kind == AstKind.LocalFunctionDeclaration then
			self:processBlock(statement.body)
		end

		if wrappedInBlock < self.MaxStatementsPerBlock and canWrapStatement(statement) and math.random() <= self.Treshold then
			statements[i] = self:wrapStatement(statement, block.scope)
			wrappedInBlock = wrappedInBlock + 1
		end
	end
end

function ControlFlow:apply(ast)
	self:processBlock(ast.body)
	return ast
end

return ControlFlow
