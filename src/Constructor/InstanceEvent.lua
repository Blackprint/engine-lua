local Enums = require("@src/Nodes/Enums.lua")
local CustomEvent = require("@src/Constructor/CustomEvent.lua")
local Types = require("@src/Types.lua")
local Utils = require("@src/Utils.lua")

-- InstanceEvent class
local InstanceEvent = {}
InstanceEvent.__index = InstanceEvent

function InstanceEvent.new(options)
	local this = setmetatable({}, InstanceEvent)
	this.schema = options.schema
	this._root = options._root
	this.namespace = options.namespace
	this.used = {}
	return this
end

-- InstanceEvents class
local InstanceEvents = setmetatable({}, { __index = CustomEvent })
InstanceEvents.__index = InstanceEvents

function InstanceEvents.new(instance)
	local this = setmetatable(CustomEvent.new(), InstanceEvents)
	this.instance = instance
	this.list = {}
	return this
end

function InstanceEvents:createEvent(namespace, options)
	if self.list[namespace] then return end -- throw new Error(f"Event with name '{namespace}' already exist")

	-- if re.match(namespace, "/\\s/") then
	if string.find(namespace, "[ \t\n]") ~= nil then
		error(string.format("Namespace can't have space character: '%s'", namespace))
	end

	if options.schema and Utils._isList(options.schema) then
		-- print(options.schema)
		options.fields = options.schema
		options.schema = nil
		print(".createEvent: schema options need to be object, please re-export this instance and replace your old JSON")
	end

	local schema = options.schema or {}
	local list = options.fields
	if list then
		for _, value in ipairs(list) do
			schema[value] = Types.Any
		end
	end

	local obj = InstanceEvent.new({ schema = schema, namespace = namespace, _root = self })
	self.list[namespace] = obj

	self.instance:_emit('event.created', { reference = obj })
end

function InstanceEvents:renameEvent(from_, to)
	if self.list[to] then error(string.format("Event with name '%s' already exist", to)) end

	-- if re.match(to, "/\\s/") then
	if string.find(to, "[ \t\n]") ~= nil then
		error(string.format("Namespace can't have space character: '%s'", to))
	end

	local oldEvInstance = self.list[from_]
	local used = oldEvInstance.used
	oldEvInstance.namespace = to

	for _, iface in ipairs(used) do
		if iface._enum == Enums.BPEventListen then
			self:off(iface.data.namespace, iface._listener)
			self:on(to, iface._listener)
		end

		iface.data.namespace = to
		iface.title = table.concat({ Utils._stringSplit(to, '/') }, ' ', -2)
	end

	self.list[to] = self.list[from_]
	self.list[from_] = nil

	self.instance:_emit('event.renamed', { old = from_, now = to, reference = oldEvInstance })
end

function InstanceEvents:deleteEvent(namespace)
	local exist = self.list[namespace]
	if not exist then return end

	local map = exist.used -- This list can be altered multiple times when deleting a node
	for _, iface in ipairs(map) do
		iface.node.instance:deleteNode(iface)
	end

	self.list[namespace] = nil
	self.instance:_emit('event.deleted', { reference = exist })
end

function InstanceEvents:_renameFields(namespace, name, to)
	local schema = self.list[namespace]
	if not schema then return end
	schema = schema.schema
	if not schema then return end

	schema[to] = schema[name]
	schema[name] = nil

	self:refreshFields(namespace, name, to)
end

-- second and third parameter is only be used for renaming field
function InstanceEvents:refreshFields(namespace, _name, _to)
	local evInstance = self.list[namespace]
	local schema = evInstance and evInstance.schema
	if not schema then return end

	local function refreshPorts(iface, target)
		local ports = iface[target]
		local node = iface.node

		if _name then
			node:renamePort(target, _name, _to)
			return
		end

		-- Delete port that not exist or different type first
		local isEmitPort = target == 'input'
		for name, val in pairs(ports) do
			if isEmitPort then
				isEmitPort = false
				continue
			end
			if schema[name] ~= ports[name]._config then
				node:deletePort(target, name)
			end
		end

		-- Create port that not exist
		for name, val in pairs(schema) do
			if not ports[name] then
				node:createPort(target, name, schema[name])
			end
		end
	end

	local used = evInstance.used
	for _, iface in ipairs(used) do
		if iface._enum == Enums.BPEventListen then
			if iface.data.namespace == namespace then
				refreshPorts(iface, 'output')
			end
		elseif iface._enum == Enums.BPEventEmit then
			if iface.data.namespace == namespace then
				refreshPorts(iface, 'input')
			end
		else
			error("Unrecognized node in event list's stored nodes")
		end
	end
end

return InstanceEvents