local CustomEvent = require("@src/Constructor/CustomEvent.lua")
local Internal = require("@src/Internal.lua")
local Enums = require("@src/Nodes/Enums.lua")
local Types = require("@src/Types.lua")
local PortFeature = require("@src/Port/PortFeature.lua")
local Interface = require("@src/Interface.lua")
local Class = require("@src/LuaUtils/Class.lua")
local Utils = require("@src/Utils.lua")

local Node = {}
Node.__index = Class._create(Node, CustomEvent)

function Node.new(instance)
	local node = setmetatable(CustomEvent.new(), Node)
	node.instance = instance
	node._constructed = true

	-- If enabled, syncIn will have 3 parameter, and syncOut will be send to related node in other function instances
	node.allowSyncToAllFunction = false

	return node
end

-- Set the interface for this node
function Node:setInterface(namespace)
	if self.iface then
		Utils.throwError('node.setInterface() can only be called once')
	end

	if namespace == nil then
		self.iface = Interface.new(self)
		return self.iface
	end

	if not self._constructed then
		Utils.throwError(string.format("%s isn't constructed, maybe there are some incorrect implementation?", namespace))
	end

	if not Internal.interface[namespace] then
		Utils.throwError(string.format("Node interface for '[%s]' was not found, maybe .registerInterface() haven't being called?", namespace))
	end

	local iface = Internal.interface[namespace].new(self)
	self.iface = iface

	return iface
end

-- Create a new port
function Node:createPort(which, name, type_)
	if self.instance._locked_ then
		Utils.throwError("This instance was locked")
	end

	if which ~= 'input' and which ~= 'output' then
		Utils.throwError("Can only create port for 'input' and 'output'")
	end

	if not type_ then
		Utils.throwError("Type is required for creating new port")
	end

	if type(name) ~= "string" then
		name = tostring(name)
	end

	-- Check if type is valid
	local isValidType = (
		type_ == Types.Slot or
		type_ == Types.Any or
		type_ == Types.Route or
		type_ == Types.Trigger or

		-- PortFeature
		(type(type_) == "table" and type_.feature and (
			type_.feature == PortFeature.ArrayOf or
			type_.feature == PortFeature.Default or
			type_.feature == PortFeature.Trigger or
			type_.feature == PortFeature.Union or
			type_.feature == PortFeature.StructOf
		)) or

		-- Primitive type
		type_ == 'string' or
		type_ == 'boolean' or
		type_ == 'number' or
		type_ == 'table' or
		type_ == 'function'
	)

	if isValidType then
		if which == "input" then
			return self.input:_add(name, type_)
		else
			return self.output:_add(name, type_)
		end
	else
		print("Get type:")
		print(type_)
		Utils.throwError("Type must be a class object or from Blackprint.Port.{feature}")
	end
end

-- Rename a port
function Node:renamePort(which, name, to)
	if self.instance._locked_ then
		Utils.throwError("This instance was locked")
	end

	local iPort = self.iface[which]

	if not iPort[name] then
		Utils.throwError(string.format("%s port with name '%s' was not found", which, name))
	end

	if iPort[to] then
		Utils.throwError(string.format("%s port with name '%s' already exist", which, to))
	end

	local temp = iPort[name]
	iPort[to] = temp
	iPort[name] = nil

	temp.name = to
	self[which][to] = self[which][name]
	self[which][name] = nil
end

-- Delete a port
function Node:deletePort(which, name)
	if self.instance._locked_ then
		Utils.throwError("This instance was locked")
	end

	if which ~= 'input' and which ~= 'output' then
		Utils.throwError("Can only delete port for 'input' and 'output'")
	end

	if type(name) ~= "string" then
		name = tostring(name)
	end

	local ret = self[which]._delete(name)
	return ret
end

-- Log a message
function Node:log(message)
	self.instance:_log({ iface = self.iface, message = message })
end

-- Update the node (async)
function Node:_bpUpdate(cable)
	local thisIface = self.iface
	local isMainFuncNode = thisIface._enum == Enums.BPFnMain
	local ref = self.instance.executionOrder

	if self.update then
		self._bpUpdating = true
		local success, result = pcall(function()
			local temp = self:update(cable)
			-- Handle async coroutine if needed
			if type(temp) == "table" and temp.__coroutine then
				-- Mock coroutine handling
				return temp
			end
			return temp
		end)

		if not success then
			print("Error in node (" .. thisIface.namespace .. ") update: " .. tostring(result))
		end

		self._bpUpdating = false
		self.iface:emit('updated')
	end

	if not self.routes.out then
		if isMainFuncNode and thisIface._proxyInput and thisIface._proxyInput.routes.out then
			thisIface._proxyInput.routes:routeOut()
		end
	else
		if not isMainFuncNode then
			self.routes:routeOut()
		else
			if thisIface._proxyInput then
				thisIface._proxyInput.routes:routeOut()
			end
		end
	end

	ref:next()
end

-- Sync to all function instances
function Node:_syncToAllFunction(id, data)
	local parentInterface = self.instance.parentInterface
	if not parentInterface then return end -- This is not in a function node

	local list = parentInterface.node.bpFunction.used
	local nodeIndex = self.iface.i
	local namespace = parentInterface.namespace

	for _, iface in ipairs(list) do
		if iface == parentInterface then continue end -- Skip self

		local target = iface.bpInstance.ifaceList[nodeIndex]
		if not target then
			Utils.throwError(string.format("Target node was not found on other function instance, maybe the node was not correctly synced? (%s);", namespace:sub(7)))
		end

		target.node:syncIn(id, data, false)
	end
end

-- Sync data out
function Node:syncOut(id, data, force)
	if self.allowSyncToAllFunction then
		self:_syncToAllFunction(id, data)
	end

	local instance = self.instance
	if instance.rootInstance then
		instance.rootInstance = instance.rootInstance -- Ensure rootInstance is set
	end

	local remote = instance._remote
	if remote then
		remote:nodeSyncOut(self, id, data, force)
	end
end

-- Node properties
Node.output = nil
Node.input = nil
Node.disablePorts = false
Node.partialUpdate = false
Node.iface = nil
Node.routes = nil
Node.ref = nil
Node.type = nil
Node.interfaceSync = nil
Node.interfaceDocs = nil
Node._bpUpdating = false
Node.bpFunction = nil
Node._contructed = true
Node._syncronizing = nil
Node.syncThrottle = 0
Node._syncWait = nil
Node._syncHasWait = nil

-- Overrideable methods
function Node:init() end
function Node:imported(data) end
function Node:update(cable) end
function Node:request(cable) end
function Node:initPorts(data) end
function Node:destroy() end
function Node:syncIn(id, data, isRemote) end
function Node:notifyEditorDataChanged() end -- Do nothing, this only required for Blackprint.Sketch

return Node