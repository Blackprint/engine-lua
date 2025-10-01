local Utils = require("@src/Utils.lua")
local Types = require("@src/Types.lua")

local Cable = {}
Cable.__index = function(this, key)
	-- Cable value property
	if key == 'value' then
		if this._disconnecting then return this.input.default end
		this:visualizeFlow()
		return this.output.value
	end
	return rawget(this, key) or rawget(Cable, key)
end

function Cable.new(owner, target)
	local this = setmetatable({}, Cable)
	this.type = owner.type
	this.owner = owner
	this.target = target
	this.source = owner.source

	if owner.source == 'input' then
		this.input = owner
		this.output = target
	else
		this.input = target
		this.output = owner
	end

	this.disabled = false
	this.isRoute = false
	this.connected = false
	this._hasUpdate = false
	this._ghost = false
	this._disconnecting = false
	this._calling = false

	-- For remote-control
	this._evDisconnected = false

	return this
end

function Cable:connecting()
	if self.disabled or self.input.type == Types.Slot or self.output.type == Types.Slot then
		-- inp.iface.node.instance:emit('cable.connecting', {
		-- 	port = input, target = output
		-- });
		return
	end

	self:connected()
end

function Cable:_connected()
	local owner = self.owner
	local target = self.target
	self.connected = true

	-- Skip event emit or node update for route cable connection
	if self.isRoute then return end

	local temp = {
		port = owner,
		target = target,
		cable = self,
	}
	owner:emit('cable.connect', temp)
	owner.iface:emit('cable.connect', temp)

	local temp2 = {
		port = target,
		target = owner,
		cable = self,
	}
	target:emit('cable.connect', temp2)
	target.iface:emit('cable.connect', temp2)

	if not self.output.value then return end

	local input = self.input
	local tempEv = {
		port = input,
		target = self.output,
		cable = self,
	}
	input:emit('value', tempEv)
	input.iface:emit('port.value', tempEv)

	local node = input.iface.node
	if node.instance._importing then
		node.instance.executionOrder:add(node, self)
	elseif #node.routes.inp == 0 then
		Utils.runAsync(node:_bpUpdate(self))
	end
end

-- For debugging
function Cable:_print()
	print(string.format("\nCable: %s.%s . %s.%s",
		self.output.iface.title, self.output.name,
		self.input.name, self.input.iface.title))
end

function Cable:visualizeFlow()
	local instance = self.owner.iface.node.instance
	if instance._remote ~= nil then
		instance:_emit('_flowEvent', {cable = self})
	end
end

function Cable:disconnect(which)
	local owner = self.owner
	local target = self.target

	if self.isRoute then
		local output = self.output

		if not output then return end

		if output.out == self then output.out = nil
		elseif self.input.out == self then self.input.out = nil
		end

		local i = Utils.findFromList(output.inp, self)
		if i then
			table.remove(output.inp, i)
		elseif self.input then
			i = Utils.findFromList(self.input.inp, self)
			if i then
				table.remove(self.input.inp, i)
			end
		end

		self.connected = false

		if not target then return end -- Skip disconnection event emit

		local temp1 = {
			port = owner,
			target = target,
			cable = self,
		}
		owner:emit('disconnect', temp1)
		owner.iface:emit('cable.disconnect', temp1)
		owner.iface.node.instance:emit('cable.disconnect', temp1)

		if not target then return end
		local temp2 = {
			port = target,
			target = owner,
			cable = self,
		}
		target:emit('disconnect', temp2)
		target.iface:emit('cable.disconnect', temp2)

		return
	end

	local alreadyEmitToInstance = false
	self._disconnecting = true

	local inputPort = self.input
	if inputPort then
		local oldVal = self.output.value
		inputPort._cache = nil

		local defaultVal = inputPort.default
		if defaultVal ~= nil and defaultVal ~= oldVal then
			local iface = inputPort.iface
			local node = iface.node
			local routes = node.routes -- PortGhost's node may not have routes

			if not iface._bpDestroy and routes and #routes.inp == 0 then
				local temp = {
					port = inputPort,
					target = self.output,
					cable = self,
				}
				inputPort:emit('value', temp)
				iface:emit('port.value', temp)
				node.instance.executionOrder:add(node)
			end
		end

		inputPort._hasUpdateCable = nil
	end

	-- Remove from cable owner
	if owner and (not which or owner == which) then
		local i = Utils.findFromList(owner.cables, self)
		if i then
			table.remove(owner.cables, i)
		end

		if self.connected then
			local temp = {
				port = owner,
				target = target,
				cable = self,
			}
			owner:emit('disconnect', temp)
			owner.iface:emit('cable.disconnect', temp)
			owner.iface.node.instance:emit('cable.disconnect', temp)
			alreadyEmitToInstance = true
		else
			local temp = {
				port = owner,
				target = nil,
				cable = self,
			}
			owner.iface:emit('cable.cancel', temp)
			-- owner.iface.node.instance:emit('cable.cancel', temp)
		end
	end

	-- Remove from connected target
	if target and self.connected and (not which or target == which) then
		local i = Utils.findFromList(target.cables, self)
		if i then
			table.remove(target.cables, i)
		end

		local temp = {
			port = target,
			target = owner,
			cable = self,
		}
		target:emit('disconnect', temp)
		target.iface:emit('cable.disconnect', temp)

		if not alreadyEmitToInstance then
			target.iface.node.instance:emit('cable.disconnect', temp)
		end
	end

	if owner or target then self.connected = false end
	self._disconnecting = false
end

return Cable