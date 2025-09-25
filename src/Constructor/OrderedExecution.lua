local PortFeature = require("@src/Port/PortFeature.lua")
local Enums = require("@src/Nodes/Enums.lua")
local Utils = require("@src/Utils.lua")

local OrderedExecution = {}
OrderedExecution.__index = OrderedExecution

function OrderedExecution.new(instance, size)
	local this = setmetatable({}, OrderedExecution)
	this.instance = instance
	this.initialSize = size or 30
	this.list = {}
	for i = 1, this.initialSize do
		this.list[i] = nil
	end
	this.index = 0
	this.length = 0
	this.stop = false
	this.pause = false
	this.stepMode = false
	this._processing = false
	this._rootExecOrder = { stop = false }

	-- Pending because stepMode
	this._pRequest = {}
	this._pRequestLast = {}
	this._pTrigger = {}
	this._pRoute = {}
	this._hasStepPending = false
	this._tCable = {}
	this._lastCable = nil
	this._lastBeforeNode = nil
	this._execCounter = nil

	return this
end

function OrderedExecution:isPending(node)
	return self.list[node] ~= nil
end

function OrderedExecution:clear()
	local list = self.list
	for i = self.index, self.length do
		list[i] = nil
	end

	self.length = 0
	self.index = 0
end

function OrderedExecution:add(node, _cable)
	if self.stop or self._rootExecOrder.stop or self:isPending(node) then
		return
	end

	self:_isReachLimit()

	self.list[self.length + 1] = node
	self.length = self.length + 1

	if self.stepMode then
		if _cable then self:_tCableAdd(node, _cable) end
		self:_emitNextExecution()
	end
end

function OrderedExecution:_tCableAdd(node, cable)
	if self.stop or self._rootExecOrder.stop then
		return
	end

	local tCable = self._tCable -- Cable triggerer
	local sets = tCable[node]
	if not sets then
		sets = {}
		tCable[node] = sets
	end

	sets[cable] = true
end

function OrderedExecution:_isReachLimit()
	local i = self.index + 1
	if i >= self.initialSize or self.length >= self.initialSize then
		error("Execution order limit was exceeded")
	end
end

function OrderedExecution:_next()
	if self.stop or self._rootExecOrder.stop then
		return
	end
	if self.index >= self.length then
		return
	end

	local i = self.index + 1 -- Lua array index start from 1, so we add 1 here...
	local temp = self.list[i]
	self.list[i] = nil
	self.index = self.index + 1

	if self.stepMode and self._tCable[temp] then
		self._tCable[temp] = nil
	end

	if self.index >= self.length then
		self.index = 0
		self.length = 0
	end

	return temp
end

function OrderedExecution:_emitPaused(afterNode, beforeNode, triggerSource, cable, cables)
	self.instance:_emit('execution.paused', {
		afterNode = afterNode,
		beforeNode = beforeNode,
		cable = cable,
		cables = cables,
		triggerSource = triggerSource,
	})
end

function OrderedExecution:_addStepPending(cable, triggerSource)
	if self.stop or self._rootExecOrder.stop then
		return
	end

	-- 0 = execution order, 1 = route, 2 = trigger port, 3 = request
	if triggerSource == 1 and not Utils.findFromList(self._pRoute, cable) then
		table.insert(self._pRoute, cable)
	end
	if triggerSource == 2 and not Utils.findFromList(self._pTrigger, cable) then
		table.insert(self._pTrigger, cable)
	end
	if triggerSource == 3 then
		local hasCable = false
		local list = self._pRequest
		for _, val in ipairs(list) do
			if val.cable == cable then
				hasCable = true
				break
			end
		end

		if not hasCable then
			local cableCall = nil
			local inputPorts = cable.input.iface.input

			for key, port in pairs(inputPorts) do
				if port._calling then
					local cables = port.cables
					for _cable in cables do
						if _cable._calling then
							cableCall = _cable
							break
						end
					end
					break
				end
			end

			table.insert(list, {
				cableCall = cableCall,
				cable = cable,
			})
		end
	end

	self._hasStepPending = true
	self:_emitNextExecution()
end

-- For step mode
function OrderedExecution:_emitNextExecution(afterNode)
	if self.stop or self._rootExecOrder.stop then
		return
	end

	local triggerSource = 0
	local beforeNode = nil
	local cable = nil
	local inputNode = nil
	local outputNode = nil

	if #self._pRequest > 0 then
		triggerSource = 3
		cable = self._pRequest[1].cable
	elseif #self._pRequestLast > 0 then
		triggerSource = 0
		beforeNode = self._pRequestLast[1].node
	elseif #self._pTrigger > 0 then
		triggerSource = 2
		cable = self._pTrigger[1]
	elseif #self._pRoute > 0 then
		triggerSource = 1
		cable = self._pRoute[1]
	end

	if cable then
		if self._lastCable == cable then return end -- avoid duplicate event trigger

		inputNode = cable.input.iface.node
		outputNode = cable.output.iface.node
	end

	if triggerSource == 0 then
		if not beforeNode then
			beforeNode = self.list[self.index]
		end

		-- avoid duplicate event trigger
		if self._lastBeforeNode == beforeNode then return end

		local cables = self._tCable[beforeNode] -- Set<Cables>
		if cables then
			cables = {}
			for k, v in pairs(cables) do
				table.insert(cables, k)
			end
		end

		return self:_emitPaused(afterNode, beforeNode, 0, nil, cables)
	elseif triggerSource == 3 then
		return self:_emitPaused(inputNode, outputNode, triggerSource, cable)
	else
		return self:_emitPaused(outputNode, inputNode, triggerSource, cable)
	end
end

function OrderedExecution:_checkExecutionLimit()
	local limit = self.instance._settings and self.instance._settings.singleNodeExecutionLoopLimit
	if not limit or limit == 0 then
		self._execCounter = nil
		return
	end

	if self.length - self.index == 0 then
		if self._execCounter then
			self._execCounter = {}
		end
		return
	end

	local node = self.list[self.index]
	if not node then
		error("Empty")
	end

	if not self._execCounter then
		self._execCounter = {}
	end

	if not self._execCounter[node] then
		self._execCounter[node] = 0
	end

	local count = self._execCounter[node] + 1
	self._execCounter[node] = count

	if count > limit then
		print(string.format("Execution terminated at %s", node.iface))
		self.stepMode = true
		self.pause = true
		self._execCounter = {}

		local message = string.format("Single node execution loop exceeded the limit (%s): %s", limit, node.iface.namespace)
		self.instance:_emit('execution.terminated', { reason = message, iface = node.iface })
		return true
	end
end

function OrderedExecution:_checkStepPending()
	if self.stop or self._rootExecOrder.stop then
		return
	end
	if self:_checkExecutionLimit() then
		return
	end

	if not self._hasStepPending then return end

	local _pRequest = self._pRequest
	local _pRequestLast = self._pRequestLast
	local _pTrigger = self._pTrigger
	local _pRoute = self._pRoute

	if #_pRequest > 0 then
		local item = table.remove(_pRequest, 1)
		local cable = item.cable
		local cableCall = item.cableCall
		local currentIface = cable.output.iface
		local current = currentIface.node

		-- cable.visualizeFlow()
		currentIface._requesting = true
		current:request(cable)
		currentIface._requesting = false

		local inpIface = cable.input.iface

		-- Check if the cable was the last requester from a node
		local isLast = true
		for _, value in ipairs(_pRequest) do
			if value.cable.input.iface == inpIface then
				isLast = false
			end
		end

		if isLast then
			table.insert(self._pRequestLast, {
				node = inpIface.node,
				cableCall = cableCall,
			})

			if cableCall then
				self:_tCableAdd(cableCall.input.iface.node, cableCall)
			end
		end

		self:_tCableAdd(inpIface.node, cable)
		self:_emitNextExecution()
	elseif #_pRequestLast > 0 then
		local item = table.remove(_pRequestLast)
		local node = item.node
		local cableCall = item.cableCall

		local temp = node:update(nil)
		if temp and temp.__type == "coroutine" then
			-- Handle async in Lua
			local co = coroutine.create(function()
				temp()
			end)
			coroutine.resume(co)
		end

		if cableCall then
			cableCall.input:_call(cableCall)
		end

		if self._tCable[node] then
			self._tCable[node] = nil
		end
		self:_emitNextExecution()
	elseif #_pTrigger > 0 then
		local cable = table.remove(_pTrigger, 1)
		local current = cable.input

		-- cable.visualizeFlow()
		current:_call(cable)

		self:_emitNextExecution()
	elseif #_pRoute > 0 then
		local cable = table.remove(_pRoute, 1)

		-- cable.visualizeFlow()
		cable.input:routeIn(cable, true)

		self:_emitNextExecution()
	else
		return false
	end

	if #_pRequest == 0 and #_pRequestLast == 0 and #_pTrigger == 0 and #_pRoute == 0 then
		self._hasStepPending = false
	end

	return true
end

function OrderedExecution:next(force)
	if self.stop or self._rootExecOrder.stop then
		return
	end
	if self.stepMode then self.pause = true end
	if self.pause and not force then return end
	if #self.instance.ifaceList == 0 then return end

	if self:_checkStepPending() then return end

	local next = self:_next() -- next: node
	if not next then return end

	local skipUpdate = #next.routes.inp > 0
	local nextIface = next.iface
	next._bpUpdating = true

	if next.partialUpdate and not next.update then
		next.partialUpdate = false
	end

	local _proxyInput = nil
	if nextIface._enum == Enums.BPFnMain then
		_proxyInput = nextIface._proxyInput
		_proxyInput._bpUpdating = true
	end

	local success, err = pcall(function()
		if next.partialUpdate then
			local portList = nextIface.input._portList
			for _, inp in ipairs(portList) do
				if inp.feature == PortFeature.ArrayOf then
					if inp._hasUpdate then
						inp._hasUpdate = false

						if not skipUpdate then
							local cables = inp.cables
							for _, cable in ipairs(cables) do
								if not cable._hasUpdate then continue end
								cable._hasUpdate = false

								local temp = next:update(cable)
								if temp and temp.__type == "coroutine" then
									local co = coroutine.create(function()
										temp()
									end)
									coroutine.resume(co)
								end
							end
						end
					end
				elseif inp._hasUpdateCable then
					local cable = inp._hasUpdateCable
					inp._hasUpdateCable = nil

					if not skipUpdate then
						local temp = next:update(cable)
						if temp and temp.__type == "coroutine" then
							local co = coroutine.create(function()
								temp()
							end)
							coroutine.resume(co)
						end
					end
				end
			end
		end

		next._bpUpdating = false
		if _proxyInput then _proxyInput._bpUpdating = false end

		if not next.partialUpdate and not skipUpdate then
			next:_bpUpdate()
		end
	end)

	if not success then
		if _proxyInput then _proxyInput._bpUpdating = false end
		self:clear()
		error(err)
	end

	if self.stepMode then self:_emitNextExecution(next) end
end

return OrderedExecution