local References = require("@src/Constructor/References.lua")
local CustomEvent = require("@src/Constructor/CustomEvent.lua")
local PortLink = require("@src/Constructor/PortLink.lua")
local PortClass = require("@src/Constructor/Port.lua")
local RoutePort = require("@src/RoutePort.lua")
local Port = require("@src/Port/PortFeature.lua")
local Bit32 = require("@src/LuaUtils/Bit32.lua")
local Class = require("@src/LuaUtils/Class.lua")

local Interface = {}
Interface.__index = Class._create(Interface, CustomEvent)

function Interface.new(node)
	local iface = setmetatable(CustomEvent.new(), Interface)
	iface.node = node
	return iface
end

-- Prepare the interface with node setup
function Interface:_prepare_(clazz)
	local node = self.node
	local ref = References.new()
	node.ref = ref
	self.ref = ref

	node.routes = RoutePort.new(self)

	if clazz.output then
		node.output = PortLink.new(node, 'output', clazz.output)
		ref.IOutput = self.output
		ref.Output = node.output
	end

	if clazz.input then
		node.input = PortLink.new(node, 'input', clazz.input)
		ref.IInput = self.input
		ref.Input = node.input
	end
end

-- Create a new port
function Interface:_newPort(portName, type, def_, which, haveFeature)
	return PortClass.new(portName, type, def_, which, self, haveFeature)
end

-- Initialize port switches
function Interface:_initPortSwitches(portSwitches)
	for key, value in pairs(portSwitches) do
		local ref = self.output[key]

		-- if (value & 1) == 1 then
		if Bit32.bitAnd(value, 1) == 1 then
			Port.StructOf_split(ref)
		end

		-- if (value & 2) == 2 then
		if Bit32.bitAnd(value, 2) == 2 then
			ref.allowResync = true
		end
	end
end

-- Import input port data
function Interface:_importInputs(ports)
	-- Load saved port data value
	local inputs = self.input
	for key, val in pairs(ports) do
		if inputs[key] then
			local port = inputs[key]
			port.default = val
		end
	end
end

-- Initialize function node interface
function Interface:_BpFnInit()
	-- Placeholder for function node specific initialization
end

-- Interface lifecycle methods
function Interface:init()
	-- Placeholder for interface initialization
end

function Interface:destroy()
	-- Placeholder for interface destruction
end

function Interface:imported(data)
	-- Placeholder for post-import processing
end

-- Interface properties
Interface.id = nil -- Named ID
Interface.i = 0 -- Generated Index
Interface.title = 'No title'
Interface.interface = 'BP/default'
Interface.namespace = nil
Interface.importing = true
Interface.isGhost = false
Interface.ref = nil
Interface.data = nil
Interface.parentInterface = nil
Interface._requesting = false
Interface._enum = nil
Interface._dynamicPort = false
Interface._bpDestroy = false

return Interface