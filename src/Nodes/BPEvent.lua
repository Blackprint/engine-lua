local Node = require("@src/Node.lua")
local Interface = require("@src/Interface.lua")
local Enums = require("@src/Nodes/Enums.lua")
local Types = require("@src/Types.lua")
local Utils = require("@src/Utils.lua")
local Port = require("@src/Port/PortFeature.lua")
local registerNode = require("@src/Internal.lua").registerNode
local registerInterface = require("@src/Internal.lua").registerInterface

registerNode('BP/Event/Listen', function(class, extends)
	-- Defined below this class
	class.input = {
		Limit = Port.Default("number", 0),
		Reset = Port.Trigger(function(port) port.iface.node:resetLimit() end),
		Off = Port.Trigger(function(port) port.iface.node:offEvent() end),
	}
	class.output = {}

    function class:constructor(instance)
        local iface = self:setInterface('BPIC/BP/Event/Listen')

        -- Specify data field from here to make it enumerable and exportable
        iface.data = { namespace = '' }
        iface.title = 'EventListen'
        iface.type = 'event'
        iface._enum = Enums.BPEventListen

        self._limit = -1 -- -1 = no limit
        self._off = false
    end

    function class:initPorts(data)
        self.iface:initPorts(data)
    end

    function class:resetLimit()
        local limit = self.input['Limit']
        self._limit = limit == 0 and -1 or limit

        if self._off then
            local iface = self.iface
            self.instance.events:on(iface.data.namespace, iface._listener)
        end
    end

    function class:eventUpdate(obj)
        if self._off or self._limit == 0 then return end
        if self._limit > 0 then self._limit = self._limit - 1 end

        -- Don't use object assign as we need to re-assign None/undefined field
        local output = self.iface.output
        for key, port in pairs(output) do
            port.value = obj[key]
            port:sync()
        end

        self.routes:routeOut()
    end

    function class:offEvent()
        if not self._off then
            local iface = self.iface
            self.instance.events:off(iface.data.namespace, iface._listener)
            self._off = true
        end
    end

    function class:destroy()
        local iface = self.iface
        iface:_removeFromList()

        if not iface._listener then return end
        iface._insEventsRef:off(iface.data.namespace, iface._listener)
    end
end)

registerNode('BP/Event/Emit', function(class, extends)
	-- Defined below this class
	class.input = {
		Emit = Port.Trigger(function(port) port.iface.node:trigger() end),
	}

    function class:constructor(instance)
        local iface = self:setInterface('BPIC/BP/Event/Emit')

        -- Specify data field from here to make it enumerable and exportable
        iface.data = { namespace = '' }
        iface.title = 'EventEmit'
        iface.type = 'event'
        iface._enum = Enums.BPEventEmit
    end

    function class:initPorts(data)
        self.iface:initPorts(data)
    end

    function class:trigger()
        local data = {} -- Copy data from input ports
        local IInput = self.iface.input
        local Input = self.input

        for key, value in pairs(IInput) do
            if key ~= 'Emit' then
                data[key] = Input[key] -- Obtain data by triggering the offsetGet (getter)
            end
        end

        self.instance.events:emit(self.iface.data.namespace, data)
    end

    function class:destroy()
        self.iface:_removeFromList()
    end
end)

local BPEventListenEmit = setmetatable({}, { __index = Interface })
BPEventListenEmit.__index = BPEventListenEmit

function BPEventListenEmit.new(this)
    this._insEventsRef = this.node.instance.events
end

function BPEventListenEmit:initPorts(data)
    local namespace = data.namespace
    if not namespace then error("Parameter 'namespace' is required") end

    self.data.namespace = namespace
    self.title = namespace

    self._eventRef = self.node.instance.events.list[namespace]
    if not self._eventRef then error("Events (namespace) is not defined") end

    local schema = self._eventRef.schema
    local createPortTarget = self._enum == Enums.BPEventListen and 'output' or 'input'

    for key in pairs(schema) do
        self.node:createPort(createPortTarget, key, Types.Any)
    end
end

function BPEventListenEmit:createField(name, type)
    local schema = self._eventRef.schema
    if schema[name] then return end

    schema[name] = type
    self._insEventsRef:refreshFields(self.data.namespace)
    self.node.instance:_emit('event.field.created', {
        name = name,
        namespace = self.data.namespace,
    })
end

function BPEventListenEmit:renameField(name, to)
    local schema = self._eventRef.schema
    if not schema[name] or schema[to] then return end

    self._insEventsRef:_renameFields(self.data.namespace, name, to)
    self.node.instance:_emit('event.field.renamed', {
        old = name,
        now = to,
        namespace = self.data.namespace,
    })
end

function BPEventListenEmit:deleteField(name)
    local schema = self._eventRef.schema
    if not schema[name] then return end

    schema[name] = nil
    self._insEventsRef:refreshFields(self.data.namespace)
    self.node.instance:_emit('event.field.deleted', {
        name = name,
        namespace = self.data.namespace,
    })
end

function BPEventListenEmit:_addToList()
    local used = self._insEventsRef.list[self.data.namespace].used
    if not Utils.findFromList(used, self) then
        table.insert(used, self)
    else
        print("Tried to adding this node to the InstanceEvents more than once")
    end
end

function BPEventListenEmit:_removeFromList()
    local used = self._insEventsRef.list[self.data.namespace].used
    local index = Utils.findFromList(used, self)
    if index then table.remove(used, index) end
end

registerInterface('BPIC/BP/Event/Listen', function(class, extends) extends(BPEventListenEmit)
    function class:constructor(node)
        BPEventListenEmit.new(self)
        self._listener = nil
    end

    function class:initPorts(data)
        BPEventListenEmit.initPorts(self, data)

        if self._listener then error("This node already listen to an event") end
        self._listener = function(ev) self.node:eventUpdate(ev) end

        self._insEventsRef:on(data.namespace, self._listener)
    end
end)

registerInterface('BPIC/BP/Event/Emit', function(class, extends) extends(BPEventListenEmit)
    function class:constructor(node)
        BPEventListenEmit.new(self)
    end
end)

return {
    -- BPEventListen = BPEventListen,
    -- BPEventEmit = BPEventEmit,
    -- IEventListen = IEventListen,
    -- IEnvEmit = IEnvEmit,
    -- BPEventListenEmit = BPEventListenEmit,
}