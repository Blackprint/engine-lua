local Utils = require("@src/Utils.lua")
local InstanceEvent = require("@src/Constructor/InstanceEvent.lua")
local Types = require("@src/Types.lua")
local Class = require("@src/LuaUtils/Class.lua")

local Internal = {}

-- Internal registries
Internal.nodes = {} -- { namespace => class }
Internal.interface = {} -- { templatePath => class }
Internal.events = {} -- { namespace => InstanceEvent }

-- Namespace loading (commented out for now, similar to Python version)
-- function Internal._loadNamespace(path)
--     -- Implementation would go here for namespace loading
-- end

-- Register a node class
-- Usage: @registerNode('Namespace/Node')
--        class MyNode(Node): pass
local function registerNode(namespace, clazz)
	if type(clazz) ~= "function" then
		print(string.format("registerNode('%s', ...): the second parameter must be a function", namespace))
		return
	end -- ignore for now

	namespace = namespace:gsub('\\', '/')
	if Internal.nodes[namespace] then
		Utils.patchClass(Internal.nodes[namespace], clazz)
		return Internal.nodes[namespace]
	end

	-- Lazy require here to avoid circular deps error
	local NodeClass = require("@src/Node.lua")
	clazz = Class.prototype(clazz, NodeClass, require("@src/Constructor/CustomEvent.lua"))

	Internal.nodes[namespace] = {
		new = function(instance)
			local node = NodeClass.new(instance) -- Construct using Blackprint.Node
			clazz.applyPrototype(node) -- Apply custom prototype from user/dev
			if clazz.prototype.constructor then
				clazz.prototype.constructor(node, instance) -- Call constructor from custom prototype
			end

			return node
		end,
		class = clazz.prototype
	}
end

-- Register an interface template
-- Usage: @registerInterface('BPIC/Template')
--        class MyInterface(Interface): pass
local function registerInterface(templatePath, clazz)
	if type(clazz) ~= "function" then
		print(string.format("registerInterface('%s', ...): the second parameter must be a function", templatePath))
		return
	end -- ignore for now

	templatePath = templatePath:gsub('\\', '/')

	if not Utils._stringStartsWith(templatePath, 'BPIC/') then
		Utils.throwError(string.format("%s: The first parameter of 'registerInterface' must be started with BPIC to avoid name conflict. Please name the interface similar with 'templatePrefix' for your module that you have set on 'blackprint.config.js'.", templatePath))
	end

	if Internal.interface[templatePath] then
		Utils.patchClass(Internal.interface[templatePath], clazz)
		return Internal.interface[templatePath]
	end

	-- Lazy require here to avoid circular deps error
	local InterfaceClass = require("@src/Interface.lua")
	clazz = Class.prototype(clazz, InterfaceClass, require("@src/Constructor/CustomEvent.lua"))

	Internal.interface[templatePath] = {
		new = function(node)
			local iface = InterfaceClass.new(node)
			clazz.applyPrototype(iface)
			if clazz.prototype.constructor then
				clazz.prototype.constructor(iface, node) -- Call constructor from custom prototype
			end
			return iface
		end,
		class = clazz.prototype
	}
end

-- Register an event with schema
local function registerEvent(namespace, options)
	if Utils._stringHasSpace(namespace) then
		Utils.throwError(string.format("Namespace can't have space character: '%s'", namespace))
	end

	local schema = options.schema
	if schema == nil then
		Utils.throwError("Registering an event must have a schema. If the event doesn't have a schema or dynamically created from an instance you may not need to do this registration.")
	end

	-- Validate schema types
	for key, obj in pairs(schema) do
		-- Must be a data type or type from Blackprint.Port.{Feature}
		if type(obj) ~= "table" or (obj.feature == nil and not Types.isType(obj)) then
			Utils.throwError(string.format("Unsupported schema type for field '%s' in '%s'", key, namespace))
		end
	end

	Internal.events[namespace] = InstanceEvent.new(options)
end

-- Create a shared variable
local function createVariable(namespace, options)
	if Utils._stringHasSpace(namespace) then
		Utils.throwError(string.format("Namespace can't have space character: '%s'", namespace))
	end

	-- Lazy load, only use when being used in this func
	local temp = require("@src/Nodes/BPVariable.lua").BPVariable.new(namespace, options)
	temp._scope = require("@src/Nodes/BPVariable.lua").VarScope.Public
	temp.isShared = true

	return temp
end

-- Return all internal functions and classes
return {
	nodes = Internal.nodes,
	interface = Internal.interface,
	events = Internal.events,
	registerNode = registerNode,
	registerInterface = registerInterface,
	registerEvent = registerEvent,
	createVariable = createVariable,
}