local Utils = require("@src/Utils.lua")
local PortFeature = require("@src/Port/PortFeature.lua")
local Types = require("@src/Types.lua")

local PortLink = {}

function PortLink.new(node, which, portMeta)
    local this = setmetatable({}, PortLink)
    local iface = node.iface
    this._iface = iface
    this._which = which

    local link = {}
    this._ifacePort = link

    if which == 'input' then
        iface.input = link
    else
        iface.output = link
    end

    -- Create linker for all port
    for portName, val in pairs(portMeta) do
        this:_add(portName, val)
    end

    return this
end

function PortLink:__index(key)
    local raw = rawget(self, key) or rawget(PortLink, key)
    if raw then return raw end

    local port = rawget(self, '_ifacePort')[key]

    -- This port must use values from connected output
    if port.source == 'input' then
        if port._cache ~= nil then return port._cache end

        local cableLen = #port.cables
        if cableLen == 0 then
            return port.default
        end

        local portIface = port.iface

        -- Flag current iface is requesting value to other iface
        portIface._requesting = true

        -- Return single data
        if cableLen == 1 then
            local cable = port.cables[1] -- Don't use pointer

            if not cable.connected or cable.disabled then
                portIface._requesting = false
                if port.feature == PortFeature.ArrayOf then
                    port._cache = {}
                else
                    port._cache = port.default
                end
                return port._cache
            end

            local output = cable.output

            -- Request the data first
            if not output.value then
                local node = output.iface.node
                local executionOrder = node.instance.executionOrder

                if executionOrder.stepMode and node.request then
                    executionOrder:_addStepPending(cable, 3)
                    return
                end

                output.iface.node:request(cable)
            end

            -- print(f"\n1. {port.name} . {output.name} ({output.value})")

            portIface._requesting = false

            if port.feature == PortFeature.ArrayOf then
                port._cache = {}

                if output.value ~= nil then
                    table.insert(port._cache, output.value)
                end

                return port._cache
            end

            local finalVal = output.value
            if not finalVal then
                finalVal = port.default
            end

            port._cache = finalVal
            return port._cache
        end

        local isNotArrayPort = port.feature ~= PortFeature.ArrayOf

        -- Return multiple data as an array
        local cables = port.cables
        local data = {}
        for _, cable in ipairs(cables) do
            if not cable.connected or cable.disabled then
                continue
            end

            local output = cable.output

            -- Request the data first
            if not output.value then
                output.iface.node:request(cable)
            end

            -- print(f"\n2. {port.name} . {output.name} ({output.value})")

            if isNotArrayPort then
                local finalVal = output.value
                if not finalVal then
                    finalVal = port.default
                end

                portIface._requesting = false
                port._cache = finalVal
                return port._cache
            end

            table.insert(data, output.value)
        end

        portIface._requesting = false

        port._cache = data
        return data
    end

    -- This may get called if the port is lazily assigned with Slot port feature
    if port.type == Types.Trigger then
        if not port._call_ then
            port._call_ = function() port:_callAll() end
        end

        return port._call_
    end

    return port.value
end

function PortLink:__newindex(key, val)
    if key == '_iface' or key == '_which' or key == '_ifacePort' then
        return rawset(self, key, val)
    end

    local port = rawget(self, '_ifacePort')[key]


    if not port then
        error(string.format("Port %s ('%s') was not found on node with namespace '%s'",
            self._which, key, self._iface.namespace))
    end

    -- setter (only for output port)
    if port.iface.node.disablePorts or (not (port.splitted or port.allowResync) and port.value == val) then
        return
    end

    if port.source == 'input' then
        error("Can't set data to input port")
    end

    if not val then
        val = port.default
    else
        -- Type check
        if port.type == Types.Any then
            -- pass
        elseif port.type == Types.Slot then
            error("Port type need to be assigned before giving any value")
        elseif type(val) == port.type then
            -- pass
        else
            error(string.format("Can't validate type: %s != %s", type(val), port.type))
        end
    end

    -- print(f"\n3. {port.iface.title}.{port.name} = {val}")

    port.value = val
    port:emit('value', {
        port = port
    })

    if port.feature == PortFeature.StructOf and port.splitted then
        PortFeature.StructOf_handle(port, val)
        return
    end

    if port._sync == false then
        return
    end

    port:sync()
end

function PortLink:__pairs()
    return pairs(self._ifacePort)
end

function PortLink:__len()
    return #self._ifacePort
end

function PortLink:__contains(x)
    return self._ifacePort[x] ~= nil
end

function PortLink:_add(portName, val)
    if portName == '' then
        error("Port name can't be empty")
    end

    if self._which == 'output' and type(val) == "table" and val.feature then
        if val.feature == PortFeature.Union then
            val = Types.Any
        elseif val.feature == PortFeature.Trigger then
            val = Types.Trigger
        elseif val.feature == PortFeature.ArrayOf then
            val = "table"
        elseif val.feature == PortFeature.Default then
            val = val.type
        end
    end

    local iPort = self._ifacePort

    if iPort[portName] then
        return iPort[portName]
    end

    -- Determine type and add default value for each type
    local type, def_, haveFeature = Utils.determinePortType(val, self)

    local linkedPort = self._iface:_newPort(portName, type, def_, self._which, haveFeature)
    iPort[portName] = linkedPort
    linkedPort._config = val

    if not (haveFeature == PortFeature.Trigger and self._which == 'input') then
        linkedPort:createLinker()
    end

    return linkedPort -- IFace Port
end

function PortLink:_delete(portName)
    local iPort = self._ifacePort

    -- Destroy cable first
    local port = iPort[portName]
    port:disconnectAll()

    iPort[portName] = nil
end

function PortLink:__tostring()
    local iPort = self._ifacePort
    local temp = {}

    for k, v in pairs(iPort) do
        temp[k] = self:__index(k)
    end

    return tostring(temp)
end

return PortLink