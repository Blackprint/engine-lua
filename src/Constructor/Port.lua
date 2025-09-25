local CustomEvent = require("@src/Constructor/CustomEvent.lua")
local Cable = require("@src/Constructor/Cable.lua")
local PortFeature = require("@src/Port/PortFeature.lua")
local Types = require("@src/Types.lua")
local Enums = require("@src/Nodes/Enums.lua")
local Utils = require("@src/Utils.lua")
local RoutePort = require("@src/RoutePort.lua")

local Port = setmetatable({}, { __index = CustomEvent })
Port.__index = Port

function Port.new(portName, type, def_, which, iface, feature)
	local this = setmetatable(CustomEvent.new(), Port)

	this.name = portName
	this.type = type
	this.source = which
	this.iface = iface
	this.cables = {}
	this._node = iface.node
	this._isSlot = type == Types.Slot

	if feature == false then
		this.default = def_
		return this
	end

	-- this.value
	if feature == PortFeature.Trigger then
		this._callDef = def_
		this.default = function() Utils.runAsync(this:_call()) end
	elseif feature == PortFeature.StructOf then
		this.struct = def_
	else
		this.default = def_
	end

	this.feature = feature
	return this
end

function Port:_getPortFeature()
	if self.feature == PortFeature.ArrayOf then
		return PortFeature.ArrayOf(self.type)
	elseif self.feature == PortFeature.Default then
		return PortFeature.Default(self.type, self.default)
	elseif self.feature == PortFeature.Trigger then
		return PortFeature.Trigger(self._func)
	elseif self.feature == PortFeature.Union then
		return PortFeature.Union(self.type)
	end

	error("Port feature not recognized")
end

function Port:disconnectAll(hasRemote)
	local cables = self.cables
	for _, cable in ipairs(cables) do
		if hasRemote then
			cable._evDisconnected = true
		end

		cable:disconnect()
	end
end

function Port:_call(cable)
	local iface = self.iface

	if not cable then
		if not self._cable then
			self._cable = Cable.new(self, self)
		end
		cable = self._cable
	end

	if self._calling then
		local input = cable.input
		local output = cable.output
		error(string.format("Circular call stack detected:\nFrom: %s.%s\nTo: %s.%s",
			output.iface.title, output.name, input.iface.title, input.name))
	end

	self._calling = true
	cable._calling = true
	local success, err = pcall(function()
		self._callDef(self)
	end)

	self._calling = false
	cable._calling = false

	if not success then
		error(err)
	end

	if iface._enum ~= Enums.BPFnMain then
		Utils.runAsync(iface.node.routes:routeOut())
	end
end

function Port:_callAll()
	if self.type == Types.Route then
		local cables = self.cables
		local cable = cables[1]

		if not cable then return end
		if cable.hasBranch then cable = cables[2] end

		if not cable.input then return end
		cable.input:routeIn(cable)
	else
		local node = self.iface.node
		if node.disablePorts then return end
		local executionOrder = node.instance.executionOrder

		for _, cable in ipairs(self.cables) do
			local target = cable.input
			if not target then continue end

			if target._name then
				target.iface.parentInterface.node.iface.output[target._name.name]:_callAll()
			else
				if executionOrder.stepMode then
					executionOrder:_addStepPending(cable, 2)
					continue
				end

				target.iface.input[target.name]:_call(cable)
			end
		end

		self:emit('call')
	end
end

function Port:createLinker()
	-- Callable port
	if self.source == 'output' and (self.type == Types.Trigger or self.type == Types.Route) then
		-- Disable sync
		self._sync = false

		if self.type ~= Types.Trigger then
			self.isRoute = true
			self.iface.node.routes.disableOut = true
		end

		return function() self:_callAll() end
	end

	-- "var prepare = " is in PortLink.php (offsetGet)
end

-- Only for output port
function Port:sync()
	-- Check all connected cables, if any node need to synchronize
	local cables = self.cables
	local thisNode = self._node
	local skipSync = self.iface.node.routes.out ~= nil
	local instance = thisNode.instance

	local singlePortUpdate = false
	if not thisNode._bpUpdating then
		singlePortUpdate = true
		thisNode._bpUpdating = true
	end

	if thisNode.routes.out and thisNode.iface._enum == Enums.BPFnMain and thisNode.iface.bpInstance.executionOrder.length > 0 then
		skipSync = true
	end

	for _, cable in ipairs(cables) do
		local inp = cable.input
		if not inp then continue end
		inp._cache = nil

		if inp._cache and instance.executionOrder.stepMode then
			inp._oldCache = inp._cache
		end

		local inpIface = inp.iface
		local inpNode = inpIface.node
		local temp = {
			port = inp,
			target = self,
			cable = cable,
		}
		inp:emit('value', temp)
		inpIface:emit('port.value', temp)

		local nextUpdate = not inpIface._requesting and #inpNode.routes.inp == 0
		if not skipSync and thisNode._bpUpdating then
			if inpNode.partialUpdate then
				if inp.feature == PortFeature.ArrayOf then
					inp._hasUpdate = true
					cable._hasUpdate = true
				else
					inp._hasUpdateCable = cable
				end
			end

			if nextUpdate then
				instance.executionOrder:add(inp._node, cable)
			end
		end

		-- Skip sync if the node has route cable
		if skipSync or thisNode._bpUpdating then continue end

		if nextUpdate then
			Utils.runAsync(inpNode:_bpUpdate(cable))
		end
	end

	if singlePortUpdate then
		thisNode._bpUpdating = false
		Utils.runAsync(thisNode.instance.executionOrder:next())
	end
end

function Port:disableCables(enable)
	local cables = self.cables

	if enable == true then
		for _, cable in ipairs(cables) do
			cable.disabled = 1
		end
	elseif enable == false then
		for _, cable in ipairs(cables) do
			cable.disabled = 0
		end
	else
		for _, cable in ipairs(cables) do
			cable.disabled = cable.disabled + enable
		end
	end
end

function Port:_cableConnectError(name, obj, severe)
	local msg = string.format("Cable notify: %s", name)
	local iface = nil
	local port = nil
	local target = nil

	if obj.iface then
		msg = msg .. string.format("\nIFace: %s", obj.iface.namespace)
		iface = obj.iface
	end

	if obj.port then
		msg = msg .. string.format("\nFrom port: %s (iface: %s)\n - Type: %s (%s)",
			obj.port.name, obj.port.iface.namespace, obj.port.source, obj.port.type)
		port = obj.port
	end

	if obj.target then
		msg = msg .. string.format("\nTo port: %s (iface: %s)\n - Type: %s (%s)",
			obj.target.name, obj.target.iface.namespace, obj.target.source, obj.target.type)
		target = obj.target
	end

	local instance = self.iface.node.instance
	-- print(msg)

	if severe and instance.throwOnError then
		error(msg .. "\n")
	end

	instance:_emit(name, {
		iface = iface,
		port = port,
		target = target,
		message = msg,
	})
end

function Port:assignType(type_)
	if not type_ then error("Can't set type with undefined") end

	if self.type ~= Types.Slot then
		print(self.type)
		error("Can only assign type to port with 'Slot' type, this port already has type")
	end

	-- Skip if the assigned type is also Slot type
	if type_ == Types.Slot then return end

	-- Check current output value type
	if self.value then
		local gettype = type(self.value)
		local pass_ = false

		if type(self.value) == type_ then
			pass_ = true
		elseif type_ == Types.Any or gettype == type_ then
			pass_ = true
		end

		if not pass_ then
			error(string.format("The output value of this port is not instance of type that will be assigned: %s is not instance of %s",
				gettype, type_))
		end
	end

	-- Check connected cable's type
	for _, cable in ipairs(self.cables) do
		local inputPort = cable.input
		if not inputPort then continue end

		local portType = inputPort.type
		if portType == Types.Any then
			-- pass
		elseif portType == type_ then
			-- pass
		elseif portType == Types.Slot then
			-- pass
		elseif Types.isType(portType) or Types.isType(type_) then
			error(string.format("The target port's connection of this port is not instance of type that will be assigned: %s is not instance of %s",
				portType, type_))
		else
			local clazz
			if type(type_) == "table" and type_.type then
				clazz = type_.type
			else
				clazz = type_
			end

			if not portType:isSubclassOf(clazz) then
				error(string.format("The target port's connection of this port is not instance of type that will be assigned: %s is not instance of %s",
					portType, clazz))
			end
		end
	end

	if type(type_) == "table" and type_.feature then
		if self.source == 'output' then
			if type_.feature == PortFeature.Union then
				type_ = Types.Any
			elseif type_.feature == PortFeature.Trigger then
				type_ = type_.type
			elseif type_.feature == PortFeature.ArrayOf then
				type_ = "table"
			elseif type_.feature == PortFeature.Default then
				type_ = type_.type
			end
		else
			if not type_.type then error("Missing type for port feature") end

			self.feature = type_.feature
			self.type = type_.type

			if type_.feature == PortFeature.StructOf then
				self.struct = type_.value
				-- this.classAdd .= "BP-StructOf "
			end

			-- if(type.virtualType != None)
			-- 	this.virtualType = type.virtualType
		end
	else
		self.type = type_
	end

	-- Trigger `connect` event for every connected cable
	for _, cable in ipairs(self.cables) do
		if cable.disabled or not cable.target then continue end
		cable:_connected()
	end

	self._config = type_
	self:emit('type.assigned')
end

function Port:connectCable(cable)
	if cable.isRoute then
		self:_cableConnectError('cable.not_route_port', {
			cable = cable,
			port = self,
			target = cable.owner
		})

		cable:disconnect()
		return false
	end

	local cableOwner = cable.owner

	if cableOwner == self then -- It's referencing to same port
		cable:disconnect()
		return false
	end

	if (self.onConnect and self.onConnect(cable, cableOwner)) or
	   (cableOwner.onConnect and cableOwner.onConnect(cable, self)) then
		return false
	end

	-- Remove cable if ...
	if ((cable.source == 'output' and self.source ~= 'input') or -- Output source not connected to input
		(cable.source == 'input' and self.source ~= 'output')) then -- Input source not connected to output
		self:_cableConnectError('cable.wrong_pair', {
			cable = cable,
			port = self,
			target = cableOwner
		})
		cable:disconnect()
		return false
	end

	if cableOwner.source == 'output' then
		if ((self.feature == PortFeature.ArrayOf and not PortFeature.ArrayOf_validate(self.type, cableOwner.type)) or
			(self.feature == PortFeature.Union and not PortFeature.Union_validate(self.type, cableOwner.type))) then
			self:_cableConnectError('cable.wrong_type', {
				cable = cable,
				iface = self.iface,
				port = cableOwner,
				target = self
			})

			cable:disconnect()
			return false
		end
	elseif self.source == 'output' then
		if ((cableOwner.feature == PortFeature.ArrayOf and not PortFeature.ArrayOf_validate(cableOwner.type, self.type)) or
			(cableOwner.feature == PortFeature.Union and not PortFeature.Union_validate(cableOwner.type, self.type))) then
			self:_cableConnectError('cable.wrong_type', {
				cable = cable,
				iface = self.iface,
				port = self,
				target = cableOwner
			})

			cable:disconnect()
			return false
		end
	end

	-- ToDo: recheck why we need to check if the constructor is a function
	local isInstance = true
	if cableOwner.type ~= self.type and type(cableOwner.type) == "function" and type(self.type) == "function" then
		if cableOwner.source == 'output' then
			isInstance = cableOwner.type:isSubclassOf(self.type)
		else
			isInstance = self.type:isSubclassOf(cableOwner.type)
		end
	end

	-- Remove cable if type restriction
	if not isInstance or (
		cableOwner.type == Types.Trigger and self.type ~= Types.Trigger or
		cableOwner.type ~= Types.Trigger and self.type == Types.Trigger
	) then
		self:_cableConnectError('cable.wrong_type_pair', {
			cable = cable,
			port = self,
			target = cableOwner
		})

		cable:disconnect()
		return false
	end

	-- Restrict connection between function input/output node with variable node
	-- Connection to similar node function IO or variable node also restricted
	-- These port is created on runtime dynamically
	if self.iface._dynamicPort and cableOwner.iface._dynamicPort then
		self:_cableConnectError('cable.unsupported_dynamic_port', {
			cable = cable,
			port = self,
			target = cableOwner
		})

		cable:disconnect()
		return false
	end

	local sourceCables = cableOwner.cables

	-- Remove cable if there are similar connection for the ports
	for _, _cable in ipairs(sourceCables) do
		for _, existingCable in ipairs(self.cables) do
			if _cable == existingCable then
				self:_cableConnectError('cable.duplicate_removed', {
					cable = cable,
					port = self,
					target = cableOwner
				}, false)

				cable:disconnect()
				return false
			end
		end
	end

	-- Put port reference to the cable
	cable.target = self

	local inp = nil
	local out = nil
	if cable.target.source == 'input' then
		inp = cable.target
		out = cableOwner
	else
		inp = cableOwner
		out = cable.target
	end

	-- Remove old cable if the port not support array
	if inp.feature ~= PortFeature.ArrayOf and inp.type ~= Types.Trigger then
		local cables = inp.cables -- Cables in input port
		local cableLen = #cables

		if cableLen ~= 0 then
			local temp = cables[1]

			if temp == cable and cableLen == 1 then
				-- pass
			else
				temp = cables[2]

				if temp then
					inp:_cableConnectError('cable.replaced', {
						cable = cable,
						oldCable = temp,
						port = inp,
						target = out,
					}, false)
					temp:disconnect()
				end
			end
		end
	end

	-- Connect this cable into port's cable list
	table.insert(self.cables, cable)
	-- cable.connecting()
	cable:_connected()

	return true
end

function Port:connectPort(port)
	if self._node.instance._locked_ then
		error("This instance was locked")
	end

	if getmetatable(port) == Port then
		local cable = self:_createPortCable(port)
		if port._ghost then cable._ghost = true end

		table.insert(port.cables, cable)
		if self:connectCable(cable) then
			return true
		end

		return false
	elseif getmetatable(port) == RoutePort then
		if self.source == 'output' then
			local cable = self:_createPortCable(self)
			table.insert(self.cables, cable)
			return port:connectCable(cable)
		end
		error("Unhandled connection for RoutePort")
	end
	error("First parameter must be instance of Port or RoutePort")
end

function Port:_createPortCable(port)
	if port._scope and port._scope then
		return port:createCable(nil, true)
	end
	return Cable.new(port, self)
end

return Port