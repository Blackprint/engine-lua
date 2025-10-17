local Utils = require("@src/Utils.lua")

local CustomEvent = {}
CustomEvent.__index = CustomEvent

function CustomEvent.new(that)
	local this = that or setmetatable({}, CustomEvent)
	this._events = {}
	this._once = {}
	this._currentEventName = nil
	return this
end

function CustomEvent:on(eventName, func, once)
	if string.find(eventName, ' ') then
		local events = Utils._stringSplit(eventName, ' ')
		for _, val in ipairs(events) do
			self:on(val, func, once)
		end
		return
	end

	local events = once and self._once or self._events
	if not events[eventName] then
		events[eventName] = {}
	end

	table.insert(events[eventName], func)
end

function CustomEvent:once(eventName, func)
	self:on(eventName, func, true)
end

function CustomEvent:waitOnce(eventName)
	error(".waitOnce: Currently not implemented")
end

function CustomEvent:off(eventName, func)
	if string.find(eventName, ' ') then
		local events = Utils._stringSplit(eventName, ' ')
		for _, val in ipairs(events) do
			self:off(val, func)
		end
		return
	end

	if not func then
		self._events[eventName] = nil
		self._once[eventName] = nil
		return
	end

	if self._events[eventName] then
		local _events = self._events[eventName]
		local i = Utils.findFromList(_events, func)
		if i then
			table.remove(_events, i)
		end
	end

	if self._once[eventName] then
		local _once = self._once[eventName]
		local i = Utils.findFromList(_once, func)
		if i then
			table.remove(_once, i)
		end
	end
end

function CustomEvent:emit(eventName, data)
	local events = self._events
	local once = self._once
	self._currentEventName = eventName

	if events[eventName] then
		local evs = events[eventName]
		for _, val in ipairs(evs) do
			val(data)
		end
	end

	if once[eventName] then
		local evs = once[eventName]
		for _, val in ipairs(evs) do
			val(data)
		end

		once[eventName] = nil
	end

	self._currentEventName = nil
end

return CustomEvent