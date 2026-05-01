local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")

local AstKind = Ast.AstKind

local ControlFlow = Step:extend()
ControlFlow.Description = "Enhanced control-flow obfuscation with randomized opaque predicates and wrappers."
ControlFlow.Name = "Control Flow++"

ControlFlow.SettingsDescriptor = {
	Treshold = {
		type = "number",
		default = 0.4,
		min = 0,
		max = 1,
	},
	OpaquePredicate = {
		type = "boolean",
		default = true,
	},
	MaxStatementsPerBlock = {
		type = "number",
		default = 100,
		min = 0,
		max = 128,
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

function ControlFlow:init() end

function ControlFlow:_randRange(minValue, maxValue)
	if self._rng and type(self._rng.range) == "function" then
		return self._rng:range(minValue, maxValue)
	end
	if maxValue == nil then
		return math.random(minValue)
	end
	return math.random(minValue, maxValue)
end

function ControlFlow:_randFloat()
	if self._rng and type(self._rng.range) == "function" then
		return self._rng:range()
	end
	return math.random()
end

local function canWrap(statement)
	return statement and not EXCLUDED[statement.kind]
end

-- More diverse opaque predicates
function ControlFlow:createOpaqueTrueExpression()
	local mode = self:_randRange(1, 3)

	if mode == 1 then
		-- arithmetic identity
		local a = self:_randRange(1000, 9000)
		local b = self:_randRange(20, 80)
		return Ast.EqualsExpression(
			Ast.SubExpression(
				Ast.NumberExpression(a * b),
				Ast.MulExpression(Ast.NumberExpression(a - 1), Ast.NumberExpression(b), false),
				false
			),
			Ast.NumberExpression(b),
			false
		)

	elseif mode == 2 then
		-- modulo invariant
		local a = self:_randRange(1000, 5000)
		local b = self:_randRange(2, 50)
		return Ast.EqualsExpression(
			Ast.ModExpression(
				Ast.NumberExpression(a * b),
				Ast.NumberExpression(b),
				false
			),
			Ast.NumberExpression(0),
			false
		)

	else
		-- double negation boolean
		return Ast.NotExpression(
			Ast.NotExpression(
				Ast.BooleanExpression(true),
				false
			),
			false
		)
	end
end

-- Dead false predicate
function ControlFlow:createOpaqueFalseExpression()
	return Ast.EqualsExpression(
		Ast.NumberExpression(self:_randRange(1, 1000)),
		Ast.NumberExpression(self:_randRange(1001, 2000)),
		false
	)
end

function ControlFlow:wrapStatement(statement, parentScope)
	local wrapperScope = Scope:new(parentScope)
	local innerBlock = Ast.Block({ statement }, wrapperScope)

	local mode = self:_randRange(1, 3)

	-- Mode 1: Simple if
	if mode == 1 and self.OpaquePredicate then
		return Ast.IfStatement(
			self:createOpaqueTrueExpression(),
			innerBlock,
			{},
			nil
		)

	-- Mode 2: If + dead branch
	elseif mode == 2 and self.OpaquePredicate then
		local deadBlock = Ast.Block({}, Scope:new(parentScope))

		return Ast.IfStatement(
			self:createOpaqueTrueExpression(),
			innerBlock,
			{},
			deadBlock
		)

	-- Mode 3: Nested Do + If
	else
		if self.OpaquePredicate then
			local innerIf = Ast.IfStatement(
				self:createOpaqueTrueExpression(),
				innerBlock,
				{},
				nil
			)
			return Ast.DoStatement(Ast.Block({ innerIf }, wrapperScope))
		else
			return Ast.DoStatement(innerBlock)
		end
	end
end

function ControlFlow:processBlock(block)
	if not block or block.kind ~= AstKind.Block then
		return
	end

	local count = 0
	local stmts = block.statements

	for i = 1, #stmts do
		local stmt = stmts[i]

		-- recurse safely
		if stmt.body then
			self:processBlock(stmt.body)
		end

		if stmt.elsebody then
			self:processBlock(stmt.elsebody)
		end

		if stmt.elseifs then
			for _, e in ipairs(stmt.elseifs) do
				self:processBlock(e.body)
			end
		end

		-- wrapping logic
		if count < self.MaxStatementsPerBlock
			and canWrap(stmt)
			and self:_randFloat() <= self.Treshold then

			stmts[i] = self:wrapStatement(stmt, block.scope)
			count = count + 1
		end
	end
end

function ControlFlow:apply(ast, pipeline)
	self._rng = nil
	if pipeline and type(pipeline.getRandom) == "function" then
		self._rng = pipeline:getRandom()
		if self._rng and type(self._rng.derive) == "function" then
			self._rng = self._rng:derive("ControlFlow")
		end
	end

	if ast and ast.body then
		self:processBlock(ast.body)
	end
	self._rng = nil
	return ast
end

return ControlFlow
