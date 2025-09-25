local Timer = require("@src/LuaUtils/Timer.lua")
local Promise = {}
Promise.__index = Promise

-- Promise.new(executor: (resolve, reject) → ())
function Promise.new(executor)
	local self = setmetatable({}, Promise)
	self.status = "pending"
	self.value = nil
	self.reason = nil
	self.onFulfilled = {}
	self.onRejected = {}

	local function resolve(value)
		if self.status == "pending" then
			self.status = "fulfilled"
			self.value = value
			for _, cb in ipairs(self.onFulfilled) do cb(value) end
		end
	end

	local function reject(reason)
		if self.status == "pending" then
			self.status = "rejected"
			self.reason = reason
			for _, cb in ipairs(self.onRejected) do cb(reason) end
		end
	end

	local function job()
		local ok, err = pcall(function() executor(resolve, reject) end)
		if not ok then reject(err) end
	end

	if Timer.task == nil then
		coroutine.wrap(job)()
	else
		Timer.task.spawn(job)
	end

	return self
end

-- then_(onFulfilled, onRejected)
function Promise:then_(onFulfilled, onRejected)
	if self.status == "fulfilled" then
		if onFulfilled then onFulfilled(self.value) end
	elseif self.status == "rejected" then
		if onRejected then onRejected(self.reason) end
	else
		if onFulfilled then table.insert(self.onFulfilled, onFulfilled) end
		if onRejected then table.insert(self.onRejected, onRejected) end
	end
	return self
end

-- catch_(onRejected)
function Promise:catch_(onRejected)
	return self:then_(nil, onRejected)
end

-- Promise.all([...])
function Promise.all(promises)
	return Promise.new(function(resolve, reject)
		local results = {}
		local count = 0
		for i, p in ipairs(promises) do
			p:then_(function(value)
				results[i] = value
				count = count + 1
				if count == #promises then resolve(results) end
			end, reject)
		end
	end)
end

-- Promise.race([...])
function Promise.race(promises)
	return Promise.new(function(resolve, reject)
		for _, p in ipairs(promises) do
			p:then_(resolve, reject)
		end
	end)
end

-- Promise.allSettled([...])
function Promise.allSettled(promises)
	return Promise.new(function(resolve)
		local results = {}
		local count = 0
		for i, p in ipairs(promises) do
			p:then_(function(value)
				results[i] = { status = "fulfilled", value = value }
				count = count + 1
				if count == #promises then resolve(results) end
			end, function(reason)
				results[i] = { status = "rejected", reason = reason }
				count = count + 1
				if count == #promises then resolve(results) end
			end)
		end
	end)
end

return Promise
