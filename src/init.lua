-- Import core modules that don't have circular dependencies
local CustomEvent = require("@src/Constructor/CustomEvent.lua")
local Environment = require("@src/Environment.lua")
local Event = require("@src/Event.lua")
local Types = require("@src/Types.lua")
local Internal = require("@src/Internal.lua")
local Utils = require("@src/Utils.lua")

-- Import modules that might have circular dependencies (specify order)
local Port = require("@src/Port/PortFeature.lua")
local PortClass = require("@src/Constructor/Port.lua")
local RoutePort = require("@src/RoutePort.lua")
local Node = require("@src/Node.lua")
local Interface = require("@src/Interface.lua")
local Engine = require("@src/Engine.lua")
local PortGhost = require("@src/PortGhost.lua")

-- Export all modules
_G.Blackprint = {
	CustomEvent = CustomEvent,
	Environment = Environment,
	Event = Event,
	Types = Types,

	Internal = Internal,
	registerNode = Internal.registerNode,
	registerInterface = Internal.registerInterface,
	createVariable = Internal.createVariable,

	Utils = Utils,
	Port = Port,
	PortClass = PortClass,
	RoutePort = RoutePort,
	Node = Node,
	Interface = Interface,
	Engine = Engine,
	OutputPort = PortGhost.OutputPort,
	InputPort = PortGhost.InputPort,

	LuaUtils = {
		Class = require("@src/LuaUtils/Class.lua"),
		JSON = require("@src/LuaUtils/JSON.lua"),
		Promise = require("@src/LuaUtils/Promise.lua"),
		Timer = require("@src/LuaUtils/Timer.lua"),
	},
}

return _G.Blackprint