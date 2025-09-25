local Environment = require("@src/Environment.lua")
local Node = require("@src/Node.lua")
local Interface = require("@src/Interface.lua")
local Event = require("@src/Event.lua")
local Enums = require("@src/Nodes/Enums.lua")
local registerNode = require("@src/Internal.lua").registerNode
local registerInterface = require("@src/Internal.lua").registerInterface

registerNode('BP/Env/Get', function(class, extends)
	class.output = {
		Val = "string"
	}

	function class:constructor(instance)
		local iface = self:setInterface('BPIC/BP/Env/Get')

		-- Specify data field from here to make it enumerable and exportable
		iface.data = { name = '' }
		iface.title = 'EnvGet'
		iface.type = 'bp-env-get'
		iface._enum = Enums.BPEnvGet
	end

	function class:destroy()
		self.iface:destroyListener()
	end
end)

registerNode('BP/Env/Set', function(class, extends)
	class.input = {
		Val = "string"
	}

	function class:constructor(instance)
		local iface = self:setInterface('BPIC/BP/Env/Set')

		-- Specify data field from here to make it enumerable and exportable
		iface.data = { name = '' }
		iface.title = 'EnvSet'
		iface.type = 'bp-env-set'
		iface._enum = Enums.BPEnvSet
	end

	function class:update(cable)
		Environment.set(self.iface.data.name, self.input["Val"])

	end

	function class:destroy()
		self.iface:destroyListener()
	end
end)

local BPEnvGetSet = setmetatable({}, { __index = Interface })
BPEnvGetSet.__index = BPEnvGetSet

function BPEnvGetSet:imported(data)
	if not data.name or data.name == '' then
		error("Parameter 'name' is required")
	end

	self.title = data.name
	self.data.name = data.name

	-- Create environment if not exist
	if not Environment.map[data.name] then
		Environment.set(data.name, '')
	end

	-- Listen for name change
	self._nameListener = function(old, now)
		if self.data.name ~= old then return end
		self.data = { name = now, table.unpack(self.data) }
		self.title = now
	end
	Event:on('environment.renamed', self._nameListener)

	local name = self.data.name
	local rules = Environment._rules[name] or nil

	-- Only allow connection to certain node namespace
	if rules then
		if self._enum == Enums.BPEnvGet and rules.allowGet then
			local Val = self.output['Val']
			local callback = function(cable, targetPort)
				if not rules.allowGet[targetPort.iface.namespace] then
					Val:_cableConnectError('cable.rule.disallowed', {
						cable = cable,
						port = Val,
						target = targetPort
					})
					cable:disconnect()
					return true -- Disconnect cable or disallow connection
				end
			end
			Val.onConnect = callback
		elseif self._enum == Enums.BPEnvSet and rules.allowSet then
			local Val = self.input['Val']
			local callback = function(cable, targetPort)
				if not rules.allowSet[targetPort.iface.namespace] then
					Val:_cableConnectError('cable.rule.disallowed', {
						cable = cable,
						port = Val,
						target = targetPort
					})
					cable:disconnect()
					return true -- Disconnect cable or disallow connection
				end
			end
			Val.onConnect = callback
		end
	end
end

function BPEnvGetSet:destroyListener()
	if not self._nameListener then return end
	Event:off('environment.renamed', self._nameListener)
end

registerInterface('BPIC/BP/Env/Get', function(class, extends) extends(BPEnvGetSet)
	function class:constructor(node)
		self._listener = nil
	end

	function class:imported(data)
		BPEnvGetSet.imported(self, data)

		local _listener = function(v)
			if v.key ~= self.data.name then return end -- use full self.data.name
			self.ref.Output["Val"] = v.value
		end

		self._listener = _listener
		Event:on('environment.changed environment.added', _listener)
		self.ref.Output["Val"] = Environment.map[self.data.name]
	end

	function class:destroyListener()
		if not self._listener then return end
		Event:off('environment.changed environment.added', self._listener)
	end
end)

registerInterface('BPIC/BP/Env/Set', function(class, extends) extends(BPEnvGetSet)
	function class:_nothing()
		-- Empty function
	end
end)

return {}