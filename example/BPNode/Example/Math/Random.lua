local Blackprint = _G.Blackprint
local utils = require("@src/utils.lua")

-- ReSeed function for the trigger port
local function ReSeed(port)
    local node = port.iface.node

    node.executed = true
    node.output.Out = math.random(0, 100)

    -- print("Re-seed called")
end

-- Register the Random node
Blackprint.registerNode('Example/Math/Random', function(class, extends)
    -- Define output ports
    class.output = {
        Out = "number"
    }

    -- Define input ports
    class.input = {
        ["Re-seed"] = Blackprint.Port.Trigger(ReSeed)
    }

    function class:constructor()
        -- Set interface
        self.iface = self:setInterface() -- default interface
        self.iface.title = "Random"

        -- When the connected node is requesting for the output value
        self.executed = false
    end

    function class:request(cable)
        -- Only run once this node never been executed
        -- Return false if no value was changed
        if self.executed then return false end

        utils.colorLog("Math/Random:",
            string.format("Value request for port: %s, from node: %s",
                cable.output.name, cable.input.iface.title))

        -- Let's create the value for him
        self.input["Re-seed"]()
    end
end)