local Blackprint = _G.Blackprint
local utils = require("@src/utils.lua")

-- Execute function for the trigger port
local function Exec(port)
	local node = port.iface.node

	node.output.Result = node:multiply()
	utils.colorLog("Math/Multiply:", "Result has been set: " .. tostring(node.output.Result))

	if port.iface._inactive_ ~= false then
		port.iface._inactive_ = false
	end
end

-- Register the Multiply node
Blackprint.registerNode('Example/Math/Multiply', function(class, extends)
	-- Define input ports
	class.input = {
		Exec = Blackprint.Port.Trigger(Exec),
		A = "number",
		B = Blackprint.Types.Any
	}

	-- Define output ports
	class.output = {
		Result = "number"
	}

	function class:constructor()
		-- Set interface
		self.iface = self:setInterface() -- default interface
		self.iface.title = "Multiply"
		self.iface._inactive_ = true
	end

	function class:init()
		local iface = self.iface

		-- Handle cable connections
		iface:on('cable.connect', function(ev)
			utils.colorLog("Math/Multiply:",
				string.format("Cable connected from %s (%s) to %s (%s)",
					ev.port.iface.title, ev.port.name,
					ev.target.iface.title, ev.target.name))
		end)
	end

	-- When any output value from other node are updated
	-- Let's immediately change current node result
	function class:update(cable)
		if self.iface._inactive_ then return end
		self.output.Result = self:multiply()
	end

	-- Your own processing mechanism
	function class:multiply()
		local input = self.input

		utils.colorLog("Math/Multiply:",
			string.format("Multiplying %s with %s",
				tostring(input.A), tostring(input.B)))

		-- Convert to numbers if they're not already
		local a = tonumber(input.A) or 0
		local b = tonumber(input.B) or 0

		return a * b
	end
end)