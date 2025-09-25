-- Import Blackprint engine
local Blackprint = require("../dist/Blackprint")

-- Register our nodes from BPNode folder
require("../dist/Example")

-- Create engine instance
local instance = Blackprint.Engine.new()

-- Import JSON configuration
local json_data = [[
    {"instance":{"Example/Math/Random":[{"i":0,"x":298,"y":73,"output":{"Out":[{"i":2,"name":"A"}]}},{"i":1,"x":298,"y":239,"output":{"Out":[{"i":2,"name":"B"}]}}],"Example/Math/Multiply":[{"i":2,"x":525,"y":155,"output":{"Result":[{"i":3,"name":"Any"}]}}],"Example/Display/Logger":[{"i":3,"id":"myLogger","x":763,"y":169}],"Example/Button/Simple":[{"i":4,"id":"myButton","x":41,"y":59,"output":{"Clicked":[{"i":2,"name":"Exec"}]}}],"Example/Input/Simple":[{"i":5,"id":"myInput","x":38,"y":281,"data":{"value":"saved input"},"output":{"Changed":[{"i":1,"name":"Re-seed"}],"Value":[{"i":3,"name":"Any"}]}}]},"moduleJS":["https://cdn.jsdelivr.net/npm/@blackprint/nodes@0.7/dist/nodes-example.mjs"]}
]]

-- Import the JSON to Blackprint Sketch
local imported_nodes = instance:importJSON(json_data)

-- Let's run something
local button = instance.iface['myButton']

print("\n>> I'm clicking the button")
button:clicked()

local logger = instance.iface['myLogger']
print("\n>> I got the output value: " .. logger.log)

print("\n>> I'm writing something to the input box")
local input = instance.iface['myInput']
input.data.value = 'hello wrold'

-- you can also use getNodes if you haven't set the ID
local logger_nodes = instance:getNodes('Example/Display/Logger')
if #logger_nodes > 0 then
    local logger_iface = logger_nodes[1].iface
    print("\n>> I got the output value: " .. logger_iface.log)
end