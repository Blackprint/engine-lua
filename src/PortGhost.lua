local Utils = require("@src/Utils.lua")
local Port = require("@src/Constructor/Port.lua")

local PortGhost = {}
PortGhost.__index = PortGhost

function PortGhost:destroy()
	self:disconnectAll(false)
end

-- Fake classes for ghost port creation
local fakeInstance = {
	emit = function() end
}

local fakeNode = {
	instance = fakeInstance
}

local fakeIface = {
	title = "Blackprint.PortGhost",
	isGhost = true,
	node = nil,
	emit = function() end,
	_iface = nil,
	input = {},
	output = {}
}

function fakeIface:__init()
	self.node = fakeNode
end

fakeIface._iface = fakeIface

-- OutputPort ghost class
local OutputPort = {}
function OutputPort.new(type)
	local type, def_, haveFeature = Utils.determinePortType(type, fakeIface)
	local this = Port.new('Blackprint.OutputPort', type, def_, 'output', fakeIface, haveFeature)
	this._ghost = true
	return this
end

-- InputPort ghost class
local InputPort = {}
function InputPort.new(type)
	local type, def_, haveFeature = Utils.determinePortType(type, fakeIface)
	local this = Port.new('Blackprint.InputPort', type, def_, 'input', fakeIface, haveFeature)
	this._ghost = true
	return this
end

return {
	PortGhost = PortGhost,
	OutputPort = OutputPort,
	InputPort = InputPort,
	fakeIface = fakeIface,
	fakeNode = fakeNode,
	fakeInstance = fakeInstance
}