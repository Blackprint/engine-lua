local PortFeature = require("@src/Port/PortFeature.lua")
local Types = require("@src/Types.lua")
local Node = require("@src/Node.lua")
local Interface = require("@src/Interface.lua")
local Enums = require("@src/Nodes/Enums.lua")
local registerNode = require("@src/Internal.lua").registerNode
local registerInterface = require("@src/Internal.lua").registerInterface

local PortName = {}
function PortName.new(name)
	return { name = name }
end

local _Dummy_PortTrigger = PortFeature.Trigger(function() error("This can't be called") end)

local function getFnPortType(port, which, parentNode, ref)
	if port.feature == PortFeature.Trigger or port.type == Types.Trigger then
		-- Function Input (has output port inside, and input port on main node):
		if which == 'input' then
			return Types.Trigger
		else
			return _Dummy_PortTrigger
		end
	-- Skip ArrayOf port feature, and just use the type
	elseif port.feature == PortFeature.ArrayOf then
		return port.type
	elseif port._isSlot then
		error("Function node's input/output can't use port from an lazily assigned port type (Types.Slot)")
	else
		return port._config
	end
end

registerNode('BP/FnVar/Input', function(class, extends)
	class.output = {}

	function class:constructor(instance)
		local iface = self:setInterface('BPIC/BP/FnVar/Input')

		-- Specify data field from here to make it enumerable and exportable
		iface.data = { name = '' }
		iface.title = 'FnInput'
		iface._enum = Enums.BPFnVarInput
	end

	function class:imported(data)
		if self.routes then
			self.routes.disabled = true
		end
	end

	function class:request(cable)
		local iface = self.iface

		-- This will trigger the port to request from outside and assign to this node's port
		self.output['Val'] = iface.parentInterface.node.input[iface.data.name]
	end

	function class:destroy()
		local iface = self.iface
		if not iface._listener then return end

		local port = iface._proxyIface.output[iface.data.name]
		if port.feature == PortFeature.Trigger then
			port:off('call', iface._listener)
		else
			port:off('value', iface._listener)
		end
	end
end)

registerNode('BP/FnVar/Output', function(class, extends)
	class.input = {
		Val = Types.Any
	}

	function class:constructor(instance)
		print("Function Output Variable node is removed. Use BP/Fn/Output instead.")

		local iface = self:setInterface()
		iface.data = { name = '' }
		iface.title = 'Function Output Variable'
		iface.description = 'This will be removed in the future. Use BP/Fn/Output instead.'
		iface._enum = Enums.BPFnVarOutput
	end

	function class:update()
		-- Empty function
	end
end)

local BPFnVarInOut = setmetatable({}, { __index = Interface })
BPFnVarInOut.__index = BPFnVarInOut

function BPFnVarInOut.new(iface)
	iface._dynamicPort = true -- Port is initialized dynamically
end

function BPFnVarInOut:imported(data)
	if not data.name or data.name == '' then
		error("Parameter 'name' is required")
	end
	self.data.name = data.name
	self.parentInterface = self.node.instance.parentInterface
end

registerInterface('BPIC/BP/FnVar/Input', function(class, extends) extends(BPFnVarInOut)
	function class:constructor(node)
		BPFnVarInOut.new(self)
		self.type = 'bp-fnvar-input'
		self._listener = nil
		self._proxyIface = nil
		self._waitPortInit = nil
	end

	function class:imported(data)
		BPFnVarInOut.imported(self, data)
		local ports = self.parentInterface.ref.IInput
		local node = self.node

		self._proxyIface = self.parentInterface._proxyInput.iface

		-- Create temporary port if the main function doesn't have the port
		local name = data.name
		if ports[name] == nil then
			local iPort = node:createPort('output', 'Val', Types.Slot)
			local proxyIface = self._proxyIface

			-- Run when this node is being connected with other node
			local function onConnect(cable, port)
				-- Skip port with feature: ArrayOf
				if port.feature == PortFeature.ArrayOf then return end

				iPort.onConnect = nil
				proxyIface:off("_add." .. name, self._waitPortInit)
				self._waitPortInit = nil

				local portName = PortName.new(name)
				local portType = getFnPortType(port, 'input', self, portName)
				iPort:assignType(portType)
				iPort._name = portName

				proxyIface:addPort(port, name)
				local tPort = cable.owner == iPort and port or iPort
				tPort:connectCable(cable)

				self:_addListener()
				return true
			end

			iPort.onConnect = onConnect

			-- Run when main node is the missing port
			local function _waitPortInit(port)
				-- Skip port with feature: ArrayOf
				if port.feature == PortFeature.ArrayOf then return end

				iPort.onConnect = nil
				self._waitPortInit = nil

				local portType = getFnPortType(port, 'input', self, port._name)
				iPort:assignType(portType)
				self:_addListener()
			end

			self._waitPortInit = _waitPortInit
			proxyIface:once("_add." .. name, self._waitPortInit)

		else
			if not self.output.Val then
				local port = self.parentInterface._proxyInput.iface.output[name]
				local portType = getFnPortType(port, 'input', self, port._name)
				local newPort = node:createPort('output', 'Val', portType)
				newPort._name = port._name
			end

			self:_addListener()
		end
	end

	function class:_addListener()
		local port = self._proxyIface.output[self.data.name]

		if port.type == Types.Trigger then
			local function _listener(ev)
				self.ref.Output['Val']()
			end

			self._listener = _listener
			port:on('call', _listener)
		else
			local function _listener(dat)
				local port = dat.port

				if port.iface.node.routes.out then
					local Val = self.ref.IOutput['Val']
					Val.value = port.value -- Change value without trigger node.update

					local list = Val.cables
					for _, temp in ipairs(list) do
						-- Clear connected cable's cache
						temp.input._cache = nil
					end

					return
				end

				self.ref.Output['Val'] = port.value
			end

			self._listener = _listener
			port:on('value', _listener)
		end
	end
end)

return {
	getFnPortType = getFnPortType,
	PortName = PortName,
}