local Blackprint = _G.Blackprint
local utils = require("@src/utils.lua")

-- Register the Simple Button node
Blackprint.registerNode('Example/Button/Simple', function(class, extends)
	-- Define output ports
	class.output = {
		Clicked = Blackprint.Types.Trigger
	}

	-- Create interface for puppet node
	class.interfaceSync = {
		{type = "button_in", id = "click", text = "Trigger", tooltip = "Trigger", inline = true}
	}

	function class:constructor()
		self.iface = self:setInterface('BPIC/Example/Button')
		self.iface.title = "Button"
	end

	function class:syncIn(id, data)
		if id == 'click' and data == true then
			self.iface:clicked()
		end
	end
end)

-- Register the Button interface
Blackprint.registerInterface('BPIC/Example/Button', function(class, extends)
	function class:clicked(ev)
		utils.colorLog("Button/Simple:", "'Trigger' button clicked")
		self.node.output.Clicked()
		self.node:syncOut('click', true)
	end
end)