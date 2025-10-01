local Node = require("@src/Node.lua")
local Interface = require("@src/Interface.lua")
local Enums = require("@src/Nodes/Enums.lua")
local Utils = require("@src/Utils.lua")
local registerNode = require("@src/Internal.lua").registerNode
local registerInterface = require("@src/Internal.lua").registerInterface
local Types = require("@src/Types.lua")
local PortFeature = require("@src/Port/PortFeature.lua")

-- Don't delete even unused, this is needed for importing the internal node
local BPEnvGet = require("@src/Nodes/Environments.lua")
local CustomEvent = require("@src/Constructor/CustomEvent.lua")

-- For internal library use only
local VarScope = {}
VarScope.Public = 0
VarScope.Private = 1
VarScope.Shared = 2

-- used for instance.createVariable
local BPVariable = setmetatable({}, { __index = CustomEvent })
BPVariable.__index = function(this, key)
	if key == 'value' then return rawget(this, '_value') end
	return rawget(this, key) or rawget(BPVariable, key) or rawget(CustomEvent, key)
end
BPVariable.__newindex = function(this, key, val)
	if key == 'value' then
		if rawget(this, '_value') == val then return end
		rawset(this, '_value', val)
		this:emit('value')
	else
		rawset(this, key, val)
	end
end

function BPVariable.new(id, options)
	if options == nil then options = {} end

	local this = setmetatable(CustomEvent.new(), BPVariable)

	if string.find(id, "[^%w_]") or string.find(id, "[\\/]") then
		error("BPVariable id can't include symbol character except underscore")
	end

	this.id = id
	this.title = options.title or id

	-- The type need to be defined dynamically on first cable connect
	this.type = Types.Slot
	this.used = {}  -- [Interface, Interface, ...]

	this.totalSet = 0
	this.totalGet = 0
	this.value = nil

	return this
end

function BPVariable:destroy()
	local map = self.used  -- This list can be altered multiple times when deleting a node
	for _, iface in ipairs(map) do  -- Create a copy to avoid modification during iteration
		iface.node.instance:deleteNode(iface)
	end
	self:emit('destroy')
end

registerNode('BP/Var/Set', function(class, extends)
	class.input = {}

	function class:constructor(instance)
		local iface = self:setInterface('BPIC/BP/Var/Set')

		-- Specify data field from here to make it enumerable and exportable
		iface.data = {
			name = '',
			scope = VarScope.Public
		}

		iface.title = 'VarSet'
		iface.type = 'bp-var-set'
		iface._enum = Enums.BPVarSet
	end

	function class:update(cable)
		self.iface._bpVarRef.value = self.input['Val']
	end

	function class:destroy()
		self.iface:destroyIface()
	end
end)

registerNode('BP/Var/Get',  function(class, extends)
	class.output = {}

	function class:constructor(instance)
		local iface = self:setInterface('BPIC/BP/Var/Get')

		-- Specify data field from here to make it enumerable and exportable
		iface.data = {
			name = '',
			scope = VarScope.Public
		}

		iface.title = 'VarGet'
		iface.type = 'bp-var-get'
		iface._enum = Enums.BPVarGet
	end

	function class:destroy()
		self.iface:destroyIface()
	end
end)

local BPVarGetSet = setmetatable({}, { __index = Interface })
BPVarGetSet.__index = BPVarGetSet

function BPVarGetSet.new(iface)
	iface._dynamicPort = true -- Port is initialized dynamically
end

function BPVarGetSet:imported(data)
	if not data.scope or not data.name then
		error("'scope' and 'name' options is required for creating variable node")
	end

	self:changeVar(data.name, data.scope)
	local temp = self._bpVarRef
	table.insert(temp.used, self)
end

function BPVarGetSet:changeVar(name, scopeId)
	if self.data.name ~= '' then
		error("Can't change variable node that already be initialized")
	end

	self.data.name = name
	self.data.scope = scopeId

	local bpFunction = self.node.instance.parentInterface
	if bpFunction then
		bpFunction = bpFunction.node.bpFunction
	end

	if scopeId == VarScope.Public then
		if bpFunction and bpFunction.rootInstance then
			scope = bpFunction.rootInstance.variables
		else
			scope = self.node.instance.variables
		end
	elseif scopeId == VarScope.Shared then
		if bpFunction then
			scope = bpFunction.variables
		else
			error("Shared variable requires a function context")
		end
	else -- private
		scope = self.node.instance.variables
	end

	local construct = Utils.getDeepProperty(scope, Utils._stringSplit(name, '/'))

	if not construct then
		local _scopeName
		if scopeId == VarScope.Public then
			_scopeName = 'public'
		elseif scopeId == VarScope.Private then
			_scopeName = 'private'
		elseif scopeId == VarScope.Shared then
			_scopeName = 'shared'
		else
			_scopeName = 'unknown'
		end

		error(("'%s' variable was not defined on the '%s (scopeId: %d)' instance"):format(name, _scopeName, scopeId))
	end

	return construct
end

function BPVarGetSet:_reinitPort()
	error("It should only call child method and not the parent")
end

function BPVarGetSet:useType(port)
	local temp = self._bpVarRef
	if temp.type ~= Types.Slot then
		if not port then temp.type = Types.Slot
		end
		return
	end

	if not port then error("Can't set type with None") end
	temp.type = port._config or port.type
	if type(temp) == "table" and temp.type.feature == PortFeature.Trigger then
		temp.type = Types.Trigger
	end

	-- Disable support for using ArrayOf port feature, we can't guarantee the consistency
	if temp.type.feature == PortFeature.ArrayOf then
		temp.type = port.type
	end

	if port.type == Types.Slot then
		self:waitTypeChange(temp, port)
	else
		self:_recheckRoute()
		temp:emit('type.assigned')
	end

	-- Also create port for other node that using this variable
	local map = temp.used
	for _, item in ipairs(map) do
		temp = item:_reinitPort()
	end
end

function BPVarGetSet:waitTypeChange(bpVar, port)
	local callback
	if port then
		callback = function()
			bpVar.type = port._config or port.type
			if type(bpVar) == "table" then
				if bpVar.type.feature == PortFeature.Trigger then
					bpVar.type = Types.Trigger
				elseif bpVar.type.feature == PortFeature.ArrayOf then
					-- Disable support for using ArrayOf port feature, we can't guarantee the consistency
					bpVar.type = port.type
				end
			end

			bpVar:emit('type.assigned')
		end
	else
		callback = function()
			if self.input['Val'] then
				target = self.input['Val']
			else
				target = self.output['Val']
			end
			target:assignType(bpVar.type)
		end
	end

	self._waitTypeChange = callback
	self._destroyWaitType = function() bpVar:off('type.assigned', self._waitTypeChange) end

	local iPort = port or bpVar
	iPort:once('type.assigned', self._waitTypeChange)
end

function BPVarGetSet:_recheckRoute()
	if (self.input and self.input.Val and self.input.Val.type == Types.Trigger) or
	   (self.output and self.output.Val and self.output.Val.type == Types.Trigger) then
		local routes = self.node.routes
		routes.disableOut = true
		routes.noUpdate = true
	end
end

function BPVarGetSet:destroyIface()
	if self._destroyWaitType then
		self._destroyWaitType()
	end

	local temp = self._bpVarRef
	if not temp then return end

	local i = Utils.findFromList(temp.used, self)
	if i then table.remove(temp.used, i) end
end

registerInterface('BPIC/BP/Var/Get', function(class, extends) extends(BPVarGetSet)
	function class:constructor(node)
		BPVarGetSet.new(self)
		self._eventListen = nil
	end

	function class:changeVar(name, scopeId)
		if self.data.name ~= '' then
			error("Can't change variable node that already be initialized")
		end

		if self._onChanged then
			if self._bpVarRef then
				self._bpVarRef:off('value', self._onChanged)
			end
		end

		local varRef = BPVarGetSet.changeVar(self, name, scopeId)
		self.title = name:gsub('/', ' / ')

		self._bpVarRef = varRef
		if varRef.type == Types.Slot then return end

		self:_reinitPort()
		self:_recheckRoute()
	end

	function class:_reinitPort()
		local temp = self._bpVarRef
		local node = self.node

		if temp.type == Types.Slot then
			self:waitTypeChange(temp)
		end

		if self.output.Val then
			node:deletePort('output', 'Val')
		end

		local ref = node.output
		node:createPort('output', 'Val', temp.type)

		if temp.type == Types.Trigger then
			self._eventListen = 'call'
			local callback = function(ev) ref['Val']() end
			self._onChanged = callback
		else
			self._eventListen = 'value'
			local callback = function(ev) ref['Val'] = temp.value end
			self._onChanged = callback
		end

		if temp.type ~= Types.Trigger then
			node.output['Val'] = temp.value
		end

		temp:on(self._eventListen, self._onChanged)
		return self.output['Val']
	end

	function class:destroyIface()
		if self._eventListen then
			self._bpVarRef:off(self._eventListen, self._onChanged)
		end

		BPVarGetSet.destroyIface(self)
	end
end)

registerInterface('BPIC/BP/Var/Set', function(class, extends) extends(BPVarGetSet)
	function class:constructor(node)
		BPVarGetSet.new(self)
	end

	function class:changeVar(name, scopeId)
		local varRef = BPVarGetSet.changeVar(self, name, scopeId)
		self.title = name:gsub('/', ' / ')

		self._bpVarRef = varRef
		if varRef.type == Types.Slot then return end

		self:_reinitPort()
		self:_recheckRoute()
	end

	function class:_reinitPort()
		local input = self.input
		local node = self.node
		local temp = self._bpVarRef

		if temp.type == Types.Slot then
			self:waitTypeChange(temp)
		end

		if input.Val then
			node:deletePort('input', 'Val')
		end

		if temp.type == Types.Trigger then
			node:createPort('input', 'Val', PortFeature.Trigger(function(port) temp:emit('call') end))
		else
			node:createPort('input', 'Val', temp.type)
		end

		return input['Val']
	end
end)

return {
	VarScope = VarScope,
	BPVariable = BPVariable,
}