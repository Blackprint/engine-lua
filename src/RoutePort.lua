local Types = require("@src/Types.lua")
local Cable = require("@src/Constructor/Cable.lua")
local Enums = require("@src/Nodes/Enums.lua")
local CustomEvent = require("@src/Constructor/CustomEvent.lua")
local Utils = require("@src/Utils.lua")

local RoutePort = setmetatable({}, { __index = CustomEvent })
RoutePort.__index = RoutePort

function RoutePort.new(iface)
	local this = setmetatable(CustomEvent.new(), RoutePort)
	this.inp = {} -- Allow incoming route from multiple path
	this.out = nil -- Only one route/path
	this.disableOut = false
	this.disabled = false
	this.isRoute = true
	this.source = 'route'
	this.name = 'BPRoute'
	this.iface = iface
	this.type = Types.Route
	this._isPaused = false
	return this
end

-- Connect other route port (this .out to other .inp port)
function RoutePort:routeTo(iface)
	if self.out then
		self.out:disconnect()
	end

	if not iface then -- Route ended
		local cable = Cable.new(self, nil)
		cable.isRoute = true
		self.out = cable
		return true
	end

	local port = iface.node.routes

	local cable = Cable.new(self, port)
	cable.isRoute = true
	cable.output = self
	self.out = cable
	table.insert(port.inp, cable) -- ToDo: check if this is empty if the connected cable was disconnected

	cable:_connected()
	return true
end

-- Connect to input route
function RoutePort:connectCable(cable)
	if not cable.isRoute then
		Utils.throwError("Cable must be created from route port before can be connected to other route port. Please use .routeTo(interface) instead if possible.")
	end

	for _, existing in ipairs(self.inp) do
		if existing == cable then return false end
	end

	if not self.iface.node.update then
		cable:disconnect()
		Utils.throwError("node.update() was not defined for this node")
	end

	table.insert(self.inp, cable)
	cable.input = self
	cable.target = self
	cable.isRoute = true
	cable:_connected()

	return true
end

-- Route input (async)
function RoutePort:routeIn(_cable, _force)
	local node = self.iface.node
	if node.disablePorts then return end

	local executionOrder = node.instance.executionOrder
	if executionOrder.stop or executionOrder._rootExecOrder.stop then return end

	-- Add to execution list if the OrderedExecution is in Step Mode
	if executionOrder.stepMode and _cable and not _force then
		executionOrder:_addStepPending(_cable, 1)
		return
	end

	_cable:visualizeFlow()

	if self.iface._enum ~= Enums.BPFnInput then
		node:_bpUpdate()
	else
		self:routeOut()
	end
end

-- Route output (async)
function RoutePort:routeOut()
	if self.disableOut then return end
	if self.iface.node.disablePorts then return end
	if not self.out then
		if self.iface._enum == Enums.BPFnOutput then
			return self.iface.parentInterface.node.routes:routeIn()
		end
		return
	end

	local targetRoute = self.out.input
	if not targetRoute then return end

	local _enum = targetRoute.iface._enum

	if not _enum then
		return targetRoute:routeIn(self.out)
	end

	-- if(_enum == Enums.BPFnMain):
	-- 	return await targetRoute.iface._proxyInput.routes.routeIn(this.out)

	-- if(_enum == Enums.BPFnOutput):
	-- 	let temp = targetRoute.iface.node._bpUpdate()
	-- 	if(temp?.constructor === Promise) await temp; # Performance optimization
	-- 	return await targetRoute.iface.parentInterface.node.routes.routeOut()

	return targetRoute:routeIn(self.out)
end

return RoutePort