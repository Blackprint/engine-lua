local Types = require("@src/Types.lua")

local Port = {}

-- This port can contain multiple cable as input
-- and the value will be array of 'type'
-- it's only one type, not union
-- for union port, please split it to different port to handle it

function Port.ArrayOf(type)
    return {
        feature = Port.ArrayOf,
        type = type
    }
end

function Port.ArrayOf_validate(type, target)
    if type == Types.Any or target == Types.Any or type == target then
        return true
    end

    if type(type) == "table" and type(target) == "table" and target.type == type then
        return true
    end

    return false
end

-- This port can have default value if no cable was connected
-- type = Type Data that allowed for the Port
-- value = default value for the port
function Port.Default(type, val)
    return {
        feature = Port.Default,
        type = type,
        value = val
    }
end

-- This port will be used as a trigger or callable input port
-- func = callback when the port was being called as a function
function Port.Trigger(func)
    if not func then error("Callback must not be None") end
    return {
        feature = Port.Trigger,
        type = Types.Trigger,
        func = func
    }
end

-- This port can allow multiple different types
-- like an 'any' port, but can only contain one value
--
-- Note:
-- Output port mustn't use union, it must only output one type
-- and one port can't output multiple possible type
-- In this case, Types.Any will be used you may want to cast the type with a node
function Port.Union(types)
    return {
        feature = Port.Union,
        type = types
    }
end

function Port.Union_validate(types, target)
    return target == Types.Any or (type(target) == "table" and target.type == types)
end

-- This port can allow multiple different types
-- like an 'any' port, but can only contain one value
function Port.StructOf(type, struct)
    return {
        feature = Port.StructOf,
        type = type,
        value = struct
    }
end

-- VirtualType is only for browser with Sketch library
function Port.VirtualType()
    error("VirtualType is only for browser with Sketch library")
end

function Port.StructOf_split(port)
    if port.source == 'input' then
        error("Port with feature 'StructOf' only supported for output port")
    end

    local node = port.iface.node
    local struct = port.struct

    if not port.structList then
        port.structList = {}
        for key in pairs(struct) do
            table.insert(port.structList, key)
        end
    end

    for key, val in pairs(struct) do
        if not val._name then
            val._name = port.name .. '.' .. key
        end

        local newPort = node:createPort('output', val._name, val.type)
        newPort._parent = port
        newPort._structSplitted = true
    end

    port.splitted = true
    port:disconnectAll()

    local data = node.output[port.name]
    if data then Port.StructOf_handle(port, data) end
end

function Port.StructOf_unsplit(port)
    local parent = port._parent
    if not parent and port.struct then
        parent = port
    end

    parent.splitted = false
    local struct = parent.struct
    local node = port.iface.node

    for _, val in pairs(struct) do
        node:deletePort('output', val._name)
    end
end

function Port.StructOf_handle(port, data)
    local struct = port.struct
    local output = port.iface.node.output

    local structList = port.structList
    if data then
        for _, key in ipairs(structList) do
            local ref = struct[key]

            if ref.field then
                output[ref._name] = data[ref.field]
            else
                output[ref._name] = ref.handle(data)
            end
        end
    else
        for _, key in ipairs(structList) do
            output[struct[key]._name] = nil
        end
    end
end

return Port