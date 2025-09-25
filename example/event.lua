-- Import Blackprint engine
local Blackprint = require("../dist/Blackprint")

-- Register our nodes from BPNode folder
require("../dist/Example")

-- Import JSON configuration
local json_data = [[
    {"instance":{"BP/Event/Listen":[{"i":0,"x":454,"y":177,"z":1,"data":{"namespace":"TestEvent"},"input_d":{"Limit":0},"output":{"test":[{"i":4,"name":"Any"}],"other":[{"i":4,"name":"Any"}]}}],"BP/Event/Emit":[{"i":1,"x":316,"y":177,"z":0,"data":{"namespace":"TestEvent"}}],"Example/Button/Simple":[{"i":2,"x":42,"y":143,"z":3,"id":"myButton","output":{"Clicked":[{"i":1,"name":"Emit"}]}}],"Example/Input/Simple":[{"i":3,"x":43,"y":285,"z":4,"id":"myInput","data":{"value":"123"},"output":{"Value":[{"i":1,"name":"other"}]}}],"Example/Display/Logger":[{"i":4,"x":713,"y":184,"z":2,"id":"myLogger","input":{"Any":[{"i":0,"name":"test"},{"i":0,"name":"other"}]}}]},"moduleJS":["http://localhost:6789/dist/nodes-example.mjs"],"events":{"TestEvent":{"schema":["test","other"]}}}
]]

-- Create engine instance and import JSON
local instance = Blackprint.Engine.new()
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

print("\n>> I'm clicking the button")
button:clicked()

-- you can also use getNodes if you haven't set the ID
local logger_nodes = instance:getNodes('Example/Display/Logger')
if #logger_nodes > 0 then
    local logger_iface = logger_nodes[1].iface
    print("\n>> I got the output value: " .. logger_iface.log)
end

print("\n\n>> I'm emitting event")
local data = {test = 123, other = 234}
instance.events:emit("TestEvent", data)

print("\n\n>> I got the output value: " .. logger.log)