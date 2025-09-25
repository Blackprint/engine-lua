-- Import Blackprint engine
local Blackprint = require("../dist/Blackprint")

-- Register our nodes from BPNode folder
require("../dist/Example")

-- Set up environment variables
Blackprint.Environment.set('TEST', '12345')
Blackprint.Environment.imports({TEST2 = '54321'})
Blackprint.Environment.rule('TEST2', {
    allowGet = {}, -- empty = disable any connection
})

-- Import JSON configuration
local json_data = [[
    {"instance":{"BP/Env/Get":[{"i":0,"x":249,"y":190,"z":2,"id":"testOut","data":{"name":"TEST"},"output":{"Val":[{"i":4,"name":"Any","parentId":0}]},"_cable":{"Val":[{"x":407,"y":282,"branch":[{"id":0}]}]}},{"i":2,"x":484,"y":188,"z":3,"id":"test2Out","data":{"name":"TEST2"}}],"BP/Env/Set":[{"i":1,"x":248,"y":140,"z":1,"id":"test","data":{"name":"TEST"},"input_d":{"Val":""}},{"i":3,"x":483,"y":138,"z":0,"id":"test2","data":{"name":"TEST2"},"input_d":{"Val":""}}],"Example/Display/Logger":[{"i":4,"x":646,"y":232,"z":4,"id":"myLogger"}]},"moduleJS":["http://localhost:6789/dist/nodes-example.mjs"]}
]]

-- Create engine instance and import JSON
local instance = Blackprint.Engine.new()
local imported_nodes = instance:importJSON(json_data)

-- Get environment nodes
local TEST = instance.iface['test'] -- input
local TEST_ = instance.iface['testOut'] -- output
local TEST2 = instance.iface['test2'] -- input
local TEST2_ = instance.iface['test2Out'] -- output

local logger = instance.iface['myLogger']
print("\n>> I got the output value: " .. logger.log)

print("\n\n>> I'm writing env value 'hello' into the node")
-- Note: In Lua, we need to create a port and connect it
-- This is a simplified version of the Python example
local out = Blackprint.OutputPort.new("string")
out.value = 'hello'

-- Connect the port (simplified - actual implementation may vary)
TEST.ref.IInput['Val']:connectPort(out)
print("\n>> I got the output value: " .. logger.log)

print("\n\n>> I'm trying to connect ruled environment node, this must can't be connected")
-- Try to connect ruled environment node (should fail)
local success, err = pcall(function()
    TEST2_.output['Val']:connectPort(logger.input['Any'])
    print("Error: the cable was connected")
end)

if success then
    print("Error: the cable was connected")
else
    print("Looks OK")
end