local Enums = require("@src/Nodes/Enums.lua")
local BPFunction = require("@src/Nodes/BPFunction.lua").BPFunction
local VarScope = require("@src/Nodes/BPVariable.lua").VarScope
local BPVariable = require("@src/Nodes/BPVariable.lua").BPVariable
local BPEvent = require("@src/Nodes/BPEvent.lua")
local Types = require("@src/Types.lua")
local Environment = require("@src/Environment.lua")
local Utils = require("@src/Utils.lua")
local Internal = require("@src/Internal.lua")
local Port = require("@src/Port/PortFeature.lua")
local CustomEvent = require("@src/Constructor/CustomEvent.lua")
local ExecutionOrder = require("@src/Constructor/ExecutionOrder.lua")
local Cable = require("@src/Constructor/Cable.lua")
local InstanceEvents = require("@src/Constructor/InstanceEvent.lua")
local Event = require("@src/Event.lua")
local JSON = require("@src/LuaUtils/JSON.lua")
local Bit32 = require("@src/LuaUtils/Bit32.lua")
local Class = require("@src/LuaUtils/Class.lua")
local Array = require("@src/LuaUtils/Array.lua")

local NodePortList = {'input', 'output'}

local Engine = {}
Engine.__index = Class._create(Engine, CustomEvent)

function Engine.new()
	local instance = setmetatable(CustomEvent.new(), Engine)

	instance.iface = {} -- { id => IFace }
	instance.ifaceList = Array.new() -- Note: index start from 0
	instance.disablePorts = false -- true = disable port data sync and disable route
	instance.throwOnError = true
	instance._settings = {}

	-- Private or function node's instance only
	instance.sharedVariables = nil

	instance.variables = {} -- { category => BPVariable{ name, value, type }, category => { category } }
	instance.functions = {} -- { category => BPFunction{ name, variables, input, output, used: [], node, description }, category => { category } }
	instance.ref = {} -- { id => Port references }

	instance.rootInstance = nil
	instance._importing = false
	instance._destroying = false
	instance._ready = false
	instance._remote = nil
	instance._locked_ = false
	instance._eventsInsNew = false
	instance._destroyed_ = false
	instance.parentInterface = nil
	instance.rootInstance = nil

	instance.executionOrder = ExecutionOrder.new(instance)
	instance.events = InstanceEvents.new(instance)

	instance._envDeleted = function(data) instance:_envDeletedHandler(data) end
	Event:on('environment.deleted', instance._envDeleted)

	instance:once('json.imported', function(data) instance:_onJsonImported() end)

	-- For remote control
	instance.syncDataOut = true

	return instance
end

function Engine:deleteNode(iface)
	local list = self.ifaceList
	local i = list:indexOf(iface)

	iface._bpDestroy = true
	local eventData = { iface = iface }

	if i ~= -1 then
		self:_emit('node.delete', eventData)
		list:splice(i, 1)
	else
		if self.throwOnError then
			Utils.throwError("Node to be deleted was not found")
		end

		return self:_emit('error', {
			type = 'node_delete_not_found',
			data = {
				iface = iface
			}
		})
	end

	iface.node:destroy()
	iface:destroy()

	local check = NodePortList
	for _, val in ipairs(check) do
		if not iface[val] then continue end

		local portList = iface[val]
		for _, port in pairs(portList) do
			port:disconnectAll(self._remote ~= nil)
		end
	end

	local routes = iface.node.routes
	if #routes.inp ~= 0 then
		local inp = routes.inp
		for _, cable in ipairs(inp) do
			cable:disconnect()
		end
	end

	if routes.out ~= nil then routes.out:disconnect() end

	-- Delete reference
	if iface.id ~= nil and iface.id ~= "" then
		self.iface[iface.id] = nil
		self.ref[iface.id] = nil

		local parent = iface.node.bpFunction
		if parent ~= nil then
			parent.rootInstance.ref[iface.id] = nil
		end
	end

	self:_emit('node.deleted', eventData)
end

function Engine:clearNodes()
	if self._locked_ then Utils.throwError("This instance was locked") end
	self._destroying = true

	local ifaces = self.ifaceList
	for i = 0, ifaces.length-1 do
		local iface = ifaces[i]
		if iface == nil then continue end

		local eventData = {
			iface = iface
		}
		self:_emit('node.delete', eventData)

		iface.node:destroy()
		iface:destroy()

		self:_emit('node.deleted', eventData)
	end

	self.ifaceList = Array.new()
	self.iface = {}
	self.ref = {}

	self._destroying = false
end

function Engine:importJSON(json, options)
	if type(json) == "string" then
		json = JSON.parse(json)
	end

	-- Throw if no instance data in the JSON
	if not json.instance then
		Utils.throwError("Instance was not found in the JSON data")
	end

	options = options or {}
	options.appendMode = options.appendMode or false
	options.clean = options.clean ~= false and not options.appendMode
	options.noEnv = options.noEnv or false

	local appendMode = options.appendMode
	local reorderInputPort = {}

	self._importing = true

	if options.clean and not options.appendMode then
		self:clearNodes()
		self.functions = {}
		self.variables = {}
		self.events.list = {}
	elseif not options.appendMode then
		self:clearNodes()
	end

	self:emit("json.importing", { appendMode = options.appendMode, data = json })

	if json.environments and not options.noEnv then
		Environment.imports(json.environments)
	end

	if json.functions then
		for key, value in pairs(json.functions) do
			self:createFunction(key, value)
		end
	end

	if json.variables then
		for key, value in pairs(json.variables) do
			self:createVariable(key, value)
		end
	end

	if json.events then
		for path, value in pairs(json.events) do
			self.events:createEvent(path, value)
		end
	end

	local inserted = self.ifaceList
	local nodes = {}
	local appendLength = appendMode and inserted.length or 0
	local instance = json.instance

	-- Prepare all ifaces based on the namespace
	-- before we create cables for them
	local function loop(namespace, ifaces)
		-- Every ifaces that using this namespace name
		for _, conf in ipairs(ifaces) do
			conf.i = conf.i + appendLength
			local confOpt = { i = conf.i }

			if conf.data then confOpt.data = conf.data end
			if conf.id then confOpt.id = conf.id end
			if conf.input_d then confOpt.input_d = conf.input_d end
			if conf.output_sw then confOpt.output_sw = conf.output_sw end

			-- @var Interface | Nodes.FnMain
			local iface = self:createNode(namespace, confOpt, nodes)
			inserted[conf.i] = iface -- Don't add as it's already reference

			if conf.input then
				table.insert(reorderInputPort, {
					iface = iface,
					config = conf,
				})
			end

			-- For custom function node
			iface:_BpFnInit()
		end
	end
	-- Prioritize these node creation first
	if instance['BP/Fn/Input'] ~= nil then loop('BP/Fn/Input', instance['BP/Fn/Input']) end
	if instance['BP/Fn/Output'] ~= nil then loop('BP/Fn/Output', instance['BP/Fn/Output']) end
	for namespace, ifaces in pairs(instance) do
		if namespace == 'BP/Fn/Input' or namespace == 'BP/Fn/Output' then continue end
		loop(namespace, ifaces)
	end

	-- Create cable only from output and property
	-- > Important to be separated from above, so the cable can reference to loaded ifaces
	for namespace, ifaces in pairs(instance) do
		-- Every ifaces that using this namespace name
		for _, ifaceJSON in ipairs(ifaces) do
			local iface = inserted[ifaceJSON.i]

			if ifaceJSON.route then
				iface.node.routes:routeTo(inserted[ifaceJSON.route.i + appendLength])
			end

			-- If have output connection
			if ifaceJSON.output then
				local out = ifaceJSON.output

				-- Every output port that have connection
				for portName, ports in pairs(out) do
					local linkPortA = iface.output[portName]

					if linkPortA == nil then
						if iface._enum == Enums.BPFnInput then
							local target = self:_getTargetPortType(iface.node.instance, 'input', ports)
							linkPortA = iface:addPort(target, portName)

							if linkPortA == nil then
								Utils.throwError(string.format("Can't create output port (%s) for function (%s)", portName, iface.parentInterface.node.bpFunction.id))
							end
						elseif iface._enum == Enums.BPVarGet then
							local target = self:_getTargetPortType(self, 'input', ports)
							iface:useType(target)
							linkPortA = iface.output[portName]
						else
							Utils.throwError(string.format("Node port not found for iface (index: %s, title: %s), with port name: %s", ifaceJSON.i, iface.title, portName))
						end
					end

					-- Current output's available targets
					for _, target in ipairs(ports) do
						target.i = target.i + appendLength

						-- @var \Blackprint\Interfaces|\Blackprint\Nodes\BPFnInOut|\Blackprint\Nodes\BPVarGetSet
						local targetNode = inserted[target.i] -- iface

						if linkPortA.isRoute then
							local cable = Cable.new(linkPortA, nil)
							cable.isRoute = true
							cable.output = linkPortA
							table.insert(linkPortA.cables, cable)

							targetNode.node.routes:connectCable(cable)
							continue
						end

						-- output can only meet input port
						local linkPortB = targetNode.input[target.name]
						if linkPortB == nil then
							if targetNode._enum == Enums.BPFnOutput then
								linkPortB = targetNode:addPort(linkPortA, target.name)

								if linkPortB == nil then
									Utils.throwError(string.format("Can't create output port (%s) for function (%s)", target.name, targetNode.parentInterface.node.bpFunction.id))
								end
							elseif targetNode._enum == Enums.BPVarSet then
								targetNode:useType(linkPortA)
								linkPortB = targetNode.input[target.name]
							elseif linkPortA.type == Types.Route then
								linkPortB = targetNode.node.routes
							else
								Utils.throwError(string.format("Node port not found for targetNode.title with name: %s", target.name))
							end
						end

						linkPortA:connectPort(linkPortB)
					end
				end
			end
		end
	end

	-- Fix input port cable order
	for _, value in ipairs(reorderInputPort) do
		local iface = value.iface
		local cInput = value.config.input

		for key, conf in pairs(cInput) do
			local port = iface.input[key]
			local cables = port.cables
			local temp = {}
			for i = 1, #conf do temp[i] = nil end

			local a = 1
			for _, ref in ipairs(conf) do
				local name = ref.name
				local targetIface = inserted[ref.i + appendLength]

				for _, cable in ipairs(cables) do
					if cable.output.name == name and cable.output.iface == targetIface then
						temp[a] = cable
						break
					end
				end

				a = a + 1
			end

			for _, ref in ipairs(temp) do
				if ref == nil then print(string.format("Some cable failed to be ordered for (%s: %s)", iface.title, key)) end
			end

			port.cables = temp
		end
	end

	-- Call nodes init after creation processes was finished
	for _, val in ipairs(nodes) do
		val:init()
	end

	self._importing = false
	self:emit("json.imported", { appendMode = options.appendMode, startIndex = appendLength, nodes = inserted, data = json })
	Utils.runAsync(self.executionOrder:start())

	return inserted
end

function Engine:settings(which, val)
	if val == nil then
		return self._settings[which]
	end

	which = which:gsub('%.', '_')
	self._settings[which] = val
end

function Engine:linkVariables(vars)
	local bpFunction = self.parentInterface and self.parentInterface.node.bpFunction or nil

	for _, temp in ipairs(vars) do
		Utils.setDeepProperty(self.variables, Utils._stringSplit(temp.id, '/'), temp)
		self:_emit('variable.new', {
			scope = temp._scope,
			id = temp.id,
			bpFunction = bpFunction,
			reference = temp,
		})
	end
end

function Engine:_getTargetPortType(instance, whichPort, targetNodes)
	local target = targetNodes[1] -- ToDo: check all target in case if it's supporting Union type
	local targetIface = instance.ifaceList[target.i]

	if whichPort == 'input' then
		return targetIface.input[target.name]
	else
		return targetIface.output[target.name]
	end
end

function Engine:getNodes(namespace)
	local got = {}

	local ifaces = self.ifaceList
	for i = 0, ifaces.length-1 do
		local val = ifaces[i]

		if val.namespace == namespace then
			table.insert(got, val.node)
		end
	end

	return got
end

function Engine:createNode(namespace, options, nodes)
	local func = Internal.nodes[namespace]

	-- Try to load from registered namespace folder if exist
	local funcNode = nil
	if Utils._stringStartsWith(namespace, "BPI/F/") then
		func = self.functions[namespace:sub(7)]

		if func ~= nil then
			funcNode = func.node(self)
		end
	end

	if func == nil then
		Utils.throwError(string.format("Node nodes for namespace '%s' was not found, maybe .registerNode() haven't being called?", namespace))
	end

	-- @var Node
	local node = funcNode or func.new(self)
	local iface = node.iface

	-- Disable data flow on any node ports
	if self.disablePorts then node.disablePorts = true end

	if iface == nil then
		Utils.throwError(string.format("%s: Node interface was not found, do you forget to call node.setInterface() in the constructor?", namespace))
	end

	iface.namespace = namespace

	-- Create the linker between the nodes and the iface
	if funcNode == nil then
		iface:_prepare_(func.class)
	end

	if options.id then
		iface.id = options.id
		self.iface[iface.id] = iface
		self.ref[iface.id] = iface.ref

		local parent = iface.node.bpFunction
		if parent ~= nil then
			parent.rootInstance.ref[iface.id] = iface.ref
		end
	end

	local savedData = options.data
	local portSwitches = options.output_sw

	if options.i ~= nil then
		iface.i = options.i
		self.ifaceList[iface.i] = iface
	else
		self.ifaceList:push(iface)
	end

	node:initPorts(savedData)

	if options.input_d then
		local defaultInputData = options.input_d
		if defaultInputData ~= nil then
			iface:_importInputs(defaultInputData)
		end
	end

	if portSwitches ~= nil then
		for key, val in pairs(portSwitches) do
			local ref = iface.output[key]

			-- if (val & 1) then
			if Bit32.bitAnd(val, 1) then
				Port.StructOf_split(ref)
			end

			-- if (val & 2) then
			if Bit32.bitAnd(val, 2) then
				ref.allowResync = true
			end
		end
	end

	iface.importing = false

	iface:imported(savedData)
	node:imported(savedData)

	if nodes ~= nil then
		table.insert(nodes, node)
	else
		node:init()
		iface:init()
	end

	self:emit('node.created', { iface = iface })
	return iface
end

function Engine:createVariable(id, options)
	if self._locked_ then Utils.throwError("This instance was locked") end
	if Utils._stringHasSpace(id) then
		Utils.throwError(string.format("Id can't have space character: '%s'", id))
	end

	local ids = Utils._stringSplit(id, '/')
	local lastId = ids[#ids]
	local parentObj = Utils.getDeepProperty(self.variables, ids, 1)

	if parentObj ~= nil and parentObj[lastId] then
		if parentObj[lastId].isShared then return end

		self.variables[id]:destroy()
		self.variables[id] = nil
	end

	-- setDeepProperty

	-- BPVariable = ./nodes/Var.js
	local temp = BPVariable.new(id, options)
	Utils.setDeepProperty(self.variables, ids, temp)

	local bpFunction = self.parentInterface and self.parentInterface.node.bpFunction or nil
	temp._scope = VarScope.Public
	self:_emit('variable.new', {
		scope = temp._scope,
		id = temp.id,
		bpFunction = bpFunction,
		reference = temp,
	})

	return temp
end

function Engine:renameVariable(from_, to, scopeId)
	from_ = Utils._stringCleanSymbols(from_)
	to = Utils._stringCleanSymbols(to)

	local instance, varsObject = nil, nil
	if scopeId == VarScope.Public then
		instance = self.rootInstance or self
		varsObject = instance.variables
	elseif scopeId == VarScope.Private then
		instance = self
		if instance.rootInstance == nil then
			Utils.throwError("Can't rename private function variable from main instance")
		end
		varsObject = instance.variables
	elseif scopeId == VarScope.Shared then
		return -- Already handled on nodes/Fn.py
	end

	-- Old variable object
	local ids = Utils._stringSplit(from_, '/')
	local oldObj = Utils.getDeepProperty(varsObject, ids)
	if oldObj == nil then
		Utils.throwError(string.format("Variable with name '%s' was not found", from_))
	end

	-- New target variable object
	local ids2 = Utils._stringSplit(to, '/')
	if Utils.getDeepProperty(varsObject, ids2) ~= nil then
		Utils.throwError(string.format("Variable with similar name already exist in '%s'", to))
	end

	local map = oldObj.used
	for _, iface in ipairs(map) do
		iface.title = to
		iface.data.name = to
	end

	oldObj.id = to
	oldObj.title = to

	Utils.deleteDeepProperty(varsObject, ids, true)
	Utils.setDeepProperty(varsObject, ids2, oldObj)

	local bpFunction = self.parentInterface and self.parentInterface.node.bpFunction or nil
	if scopeId == VarScope.Private then
		instance:_emit('variable.renamed', {
			scope = scopeId, old = from_, now = to, bpFunction = bpFunction, reference = nil
		})
	else
		instance:_emit('variable.renamed', { scope = scopeId, old = from_, now = to, bpFunction = bpFunction, reference = oldObj })
	end
end

function Engine:deleteVariable(namespace, scopeId)
	local varsObject, instance = nil, self
	if scopeId == VarScope.Public then
		instance = self.rootInstance or self
		varsObject = instance.variables
	elseif scopeId == VarScope.Private then
		varsObject = instance.variables
	elseif scopeId == VarScope.Shared then
		varsObject = instance.sharedVariables
	end

	local path = Utils._stringSplit(namespace, '/')
	local oldObj = Utils.getDeepProperty(varsObject, path)
	if oldObj == nil then return end
	oldObj:destroy()

	local bpFunction = self.parentInterface and self.parentInterface.node.bpFunction or nil

	Utils.deleteDeepProperty(varsObject, path, true)
	self:_emit('variable.deleted', { scope = scopeId, id = oldObj.id, bpFunction = bpFunction })
end

function Engine:createFunction(id, options)
	if self._locked_ then Utils.throwError("This instance was locked") end
	if Utils._stringHasSpace(id) then
		Utils.throwError(string.format("Id can't have space character: '%s'", id))
	end

	local ids = Utils._stringSplit(id, '/')
	local lastId = ids[#ids]
	local parentObj = Utils.getDeepProperty(self.functions, ids, 1)

	if parentObj ~= nil and parentObj[lastId] then
		parentObj[lastId]:destroy()
		parentObj[lastId] = nil
	end

	-- BPFunction = ./nodes/Fn.js
	local temp = BPFunction.new(id, options, self)
	Utils.setDeepProperty(self.functions, ids, temp)

	if options.vars then
		local vars = options.vars
		for _, val in ipairs(vars) do
			temp:createVariable(val, { scope = VarScope.Shared })
		end
	end

	if options.privateVars then
		local privateVars = options.privateVars
		for _, val in ipairs(privateVars) do
			temp:createVariable(val, { scope = VarScope.Private })
		end
	end

	self:_emit('function.new', { reference = temp })
	return temp
end

function Engine:renameFunction(from_, to)
	from_ = Utils._stringCleanSymbols(from_)
	to = Utils._stringCleanSymbols(to)

	-- Old function object
	local ids = Utils._stringSplit(from_, '/')
	local oldObj = Utils.getDeepProperty(self.functions, ids)
	if oldObj == nil then
		Utils.throwError(string.format("Function with name '%s' was not found", from_))
	end

	-- New target function object
	local ids2 = Utils._stringSplit(to, '/')
	if Utils.getDeepProperty(self.functions, ids2) ~= nil then
		Utils.throwError(string.format("Function with similar name already exist in '%s'", to))
	end

	local map = oldObj.used
	for _, iface in ipairs(map) do
		iface.namespace = 'BPI/F/' .. to
		if iface.title == from_ then iface.title = to end
	end

	if oldObj.title == from_ then oldObj.title = to end
	oldObj.id = to

	Utils.deleteDeepProperty(self.functions, ids, true)
	Utils.setDeepProperty(self.functions, ids2, oldObj)

	self:_emit('function.renamed', { old = from_, now = to, reference = oldObj })
end

function Engine:deleteFunction(id)
	local path = Utils._stringSplit(id, '/')
	local oldObj = Utils.getDeepProperty(self.functions, path)
	if oldObj == nil then return end
	oldObj:destroy()

	Utils.deleteDeepProperty(self.functions, path, true)
	self:_emit('function.deleted', { id = oldObj.id, reference = oldObj })
end

function Engine:_log(data)
	data.instance = self

	if self.rootInstance ~= nil then
		self.rootInstance:_emit('log', data)
	else
		self:_emit('log', data)
	end
end

function Engine:_emit(evName, data)
	self:emit(evName, data)
	if self.parentInterface == nil then return end

	local rootInstance = self.parentInterface.node.bpFunction.rootInstance
	if rootInstance._remote == nil then return end
	rootInstance:emit(evName, data)
end

function Engine:_envDeletedHandler(key)
	local list = self.ifaceList
	for i = list.length-1, 0, -1 do
		local iface = list[i]
		if iface.namespace ~= 'BP/Env/Get' and iface.namespace ~= 'BP/Env/Set' then continue end
		if iface.data.name == key then self:deleteNode(iface) end
	end
end

function Engine:_onJsonImported()
	self._ready = true
	if self._readyResolve then
		self._readyResolve()
	end
end

function Engine:ready()
	return true -- There are no async function in Luau, so lets just return immediately
end

function Engine:changeNodeId(iface, newId)
	if self._locked_ then Utils.throwError("This instance was locked") end

	local sketch = iface.node.instance
	local oldId = iface.id
	if oldId == newId or iface.importing then return end

	if oldId ~= nil and oldId ~= "" then
		sketch.iface[oldId] = nil
		sketch.ref[oldId] = nil

		if sketch.parentInterface ~= nil then
			sketch.parentInterface.ref[oldId] = nil
		end
	end

	newId = newId or ''
	iface.id = newId

	if newId ~= '' then
		sketch.iface[newId] = iface
		sketch.ref[newId] = iface.ref

		if sketch.parentInterface ~= nil then
			sketch.parentInterface.ref[newId] = iface.ref
		end
	end

	iface.node.instance:emit('node.id.changed', { iface = iface, old = oldId, now = newId })
end

function Engine:_isInsideFunction(fnNamespace)
	if self.rootInstance == nil then return false end
	if self.parentInterface.namespace == fnNamespace then return true end
	return self.parentInterface.node.instance:_isInsideFunction(fnNamespace)
end

function Engine:_tryInitUpdateNode(node, rule, creatingNode)
	if (Bit32.bitAnd(rule, Enums.WhenCreatingNode)) then
		if not creatingNode then return end
	elseif creatingNode then return end

	-- There are no cable connected when creating node
	-- So.. let's skip these checks
	if not creatingNode then
		if (Bit32.bitAnd(rule, Enums.NoRouteIn)) and #node.routes.inp ~= 0 then return end
		if (Bit32.bitAnd(rule, Enums.NoInputCable)) then
			local input = node.iface.input
			for key in pairs(input) do
				if #input[key].cables ~= 0 then return end
			end
		end
	end

	node:update()
end

function Engine:destroy()
	self._locked_ = false
	self._destroyed_ = true
	self:clearNodes()

	Event:off('_eventInstance.new', self._eventsInsNew)
	Event:off('environment.deleted', self._envDeleted)
	self:emit('destroy')
end

return Engine