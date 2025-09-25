local Blackprint = _G.Blackprint
local utils = require("@src/utils.lua")

-- InputIFaceData class
local InputIFaceData = {
    __index = function(this, key)
        if key == "value" then
            return this._data.value
        end
        return rawget(this, key)
    end,
    __newindex = function(this, key, val)
        if key == "value" then
            this._data.value = val
            this._iface:changed(val)
        else
            rawset(this, key, val)
        end
    end
}

function InputIFaceData.new(iface)
    return setmetatable({
        _iface = iface,
        _data = {value = '...'}
    }, InputIFaceData)
end

-- Register the Simple Input node
Blackprint.registerNode('Example/Input/Simple', function(class, extends)
    -- Define output ports
    class.output = {
        Changed = Blackprint.Types.Trigger,
        Value = "string"
    }

    -- Create interface for puppet node
    class.interfaceSync = {
        {type = "text_in", id = "value", placeholder = "Type text here..."}
    }

    function class:constructor()
        -- Set interface
        self.iface = self:setInterface('BPIC/Example/Input')
        self.iface.title = "Input"
    end

    -- Bring value from imported iface to node output
    function class:imported(data)
        if not data then return end

        local val = data.value
        utils.colorLog("Input/Simple:", "Old data: " .. tostring(self.iface.data.value))
        if val then utils.colorLog("Input/Simple:", "Imported data: " .. tostring(val)) end

        self.iface.data.value = val
    end

    -- Remote sync in
    function class:syncIn(id, data)
        if id == 'data' then
            self.iface.data.value = data.value
            self.iface:changed(data.value)
        elseif id == 'value' then
            self.iface.data.value = data
            self.iface:changed(data)
        end
    end
end)

-- Register the Input interface
Blackprint.registerInterface('BPIC/Example/Input', function(class, extends)
    function class:constructor()
        self.data = InputIFaceData.new(self)
    end

    function class:changed(val)
        -- This node still being imported
        if self.importing ~= false then
            return
        end

        utils.colorLog("Input/Simple:", "The input box have new value: " .. tostring(val))
        self.node.output.Value = val
        self.node:syncOut('data', {value = self.data.value})

        -- This will call every connected node
        self.node.output.Changed()
    end
end)