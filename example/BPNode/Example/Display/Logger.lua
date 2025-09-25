local Blackprint = _G.Blackprint
local utils = require("@src/utils.lua")

-- Register the Logger node
Blackprint.registerNode('Example/Display/Logger', function(class, extends)
	-- Define input ports
	class.input = {
		Any = Blackprint.Port.ArrayOf(Blackprint.Types.Any)
	}

	-- Create interface for puppet node
	class.interfaceSync = {
		{type = "text_out", id = "log", placeholder = "...", tooltip = "Output will written here"}
	}

	function class:constructor()
		-- Set interface
		self.iface = self:setInterface('BPIC/Example/Logger')
		self.iface.title = "Logger"
	end

	function class:refreshLogger(val)
		if val == nil then
			val = 'None'
			self.iface.log = val
		elseif type(val) == "string" or type(val) == "number" then
			self.iface.log = tostring(val)
		else
			val = Blackprint.LuaUtils.JSON.stringify(val)
			self.iface.log = val
		end
	end

	function class:init()
		local iface = self.iface

		-- Let's show data after new cable was connected or disconnected
		iface:on('cable.connect cable.disconnect', function()
			utils.colorLog("Logger (" .. (iface.id or '') .. "):", "A cable was changed on Logger, now refresing the input element")
		end)

		-- Handle value changes
		iface.input.Any:on('value', function(ev)
			local target = ev.target
			utils.colorLog("Logger (" .. (iface.id or '') .. "):",
				string.format("I connected to %s (%s), that have new value: %s",
					target.name, target.iface.namespace, tostring(target.value)))
		end)
	end

	function class:update(cable)
		-- Let's take all data from all connected nodes
		-- Instead showing new single data-> val
		self:refreshLogger(self.input.Any)
	end

	-- Remote sync in
	function class:syncIn(id, data)
		if id == 'log' then
			self.iface.log = data
		end
	end
end)

-- Register the Logger interface
Blackprint.registerInterface('BPIC/Example/Logger', function(class, extends)
	function class:constructor()
		self._log = "..."
	end

	class.root_config = {
		get = {
			log = function(iface)
				return iface._log
			end
		},
		set = {
			log = function(iface, val)
				iface._log = val
				utils.colorLog("Logger (" .. (iface.id or '') .. ") Data:", tostring(val))
				iface.node:syncOut('log', val)
			end
		},
	}
end)