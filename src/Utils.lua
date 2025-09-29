local Types = require("@src/Types.lua")
local Port = require("@src/Port/PortFeature.lua")

local Utils = {}

Utils.NoOperation = function() end

-- Set a deep property in an object using a path
function Utils.setDeepProperty(obj, path, value, onCreate)
	if not path or #path == 0 then return end

	-- Check each path component type
	for i = 1, #path - 1 do
		local key = path[i]
		if type(key) ~= "string" and type(key) ~= "number" then
			error(string.format("Object field must be Number or String, but found: %s", tostring(key)))
		end

		-- Disallow diving into internal Lua properties
		if key == "__class" or key == "__dict" or key == "__weakref" or key == "__module" or key == "__bases" then
			return
		end

		if obj[key] == nil then
			obj[key] = {}
			if onCreate then
				onCreate(obj[key])
			end
		end

		obj = obj[key]
	end

	-- Check the last path component type
	local lastKey = path[#path]
	if type(lastKey) ~= "string" and type(lastKey) ~= "number" then
		error(string.format("Object field must be Number or String, but found: %s", tostring(lastKey)))
	end

	if lastKey == "__class" or lastKey == "__dict" or lastKey == "__weakref" or lastKey == "__module" or lastKey == "__bases" then
		return
	end

	obj[lastKey] = value
	return
end

-- Get a deep property from an object using a path
function Utils.getDeepProperty(obj, path, reduceLen)
	if not path or #path == 0 then return nil end

	local n = #path - (reduceLen or 0)
	if n <= 0 then return nil end

	for i = 1, n do
		local key = path[i]
		if obj[key] == nil then return nil end
		obj = obj[key]
	end

	return obj
end

-- Delete a deep property from an object using a path
function Utils.deleteDeepProperty(obj, path, deleteEmptyParent)
	if not path or #path == 0 then return end

	local lastPath = path[#path]
	local parents = {}

	-- Navigate to the parent of the target
	for i = 1, #path - 1 do
		local key = path[i]
		if obj[key] == nil then return end
		table.insert(parents, obj)
		obj = obj[key]
	end

	-- Delete the target property
	if obj[lastPath] ~= nil then
		obj[lastPath] = nil
	end

	-- Clean up empty parents if requested
	if deleteEmptyParent then
		for i = #parents, 1, -1 do
			local parent = parents[i]
			local key = path[i]
			if parent[key] == nil then continue end

			-- Check if the object is empty
			if type(parent[key]) == "table" then
				local is_empty = true
				for _ in pairs(parent[key]) do
					is_empty = false
					break
				end
				if is_empty then
					parent[key] = nil
				else
					break -- Object is not empty, stop cleaning up
				end
			else
				-- For non-container objects, assume they're "empty" if they have no attributes
				local has_attrs = false
				for _ in pairs(parent[key]) do
					has_attrs = true
					break
				end
				if not has_attrs then
					parent[key] = nil
				else
					break -- Object has attributes, stop cleaning up
				end
			end
		end
	end
end

-- Determine port type and return type, default value, and feature
function Utils.determinePortType(val, that)
	if val == nil then
		error(string.format("Port type can't be None, error when processing: %s, %s port", that._iface.namespace, that._which))
	end

	local type_ = val
	local def_ = nil
	local feature = nil

	if type(val) == "table" then
		feature = val.feature
		if feature == Port.Trigger then
			def_ = val.func
			type_ = val.type
		elseif feature == Port.ArrayOf then
			type_ = val.type
			if type_ == Types.Any then
				def_ = nil
			else
				def_ = {}
			end
		elseif feature == Port.Union then
			type_ = val.type
		elseif feature == Port.Default then
			type_ = val.type
			def_ = val.value
		end
	end

	-- Give default value for each primitive type
	if type_ == "number" then
		def_ = 0
	elseif type_ == "boolean" then
		def_ = false
	elseif type_ == "string" then
		def_ = ''
	elseif type_ == "table" then
		def_ = {}
	end
	return type_, def_, feature
end

-- Find an item in a list and return its index
function Utils.findFromList(list, item)
	for i, val in ipairs(list) do
		if val == item then
			return i
		end
	end
	return nil
end

-- Async task management
Utils._asyncTask = {}

-- Run an async coroutine
function Utils.runAsync(coroutine)
	if coroutine == nil then return end

	local success, result = pcall(function()
		-- Mock coroutine creation for now
		-- In a real implementation, you'd use a proper coroutine library
		local task = {
			coroutine = coroutine,
			add_done_callback = function(self, callback)
				-- Mock task completion
				callback()
			end
		}
		table.insert(Utils._asyncTask, task)
		task:add_done_callback(function()
			for i, t in ipairs(Utils._asyncTask) do
				if t == task then
					table.remove(Utils._asyncTask, i)
					break
				end
			end
		end)
	end)

	if not success then
		print("Error in async task: " .. tostring(result))
	end
end

-- Patch an old class with new class methods
function Utils.patchClass(old_class, new_class)
	-- Remove all non-private methods from old class
	for name, _ in pairs(old_class) do
		if not Utils._stringStartsWith(name, "__") then
			old_class[name] = nil
		end
	end

	-- Copy all non-private methods from new class
	for name, value in pairs(new_class) do
		if not Utils._stringStartsWith(name, "__") then
			old_class[name] = value
		end
	end
end

-- Combine two arrays
function Utils._combineArray(A, B)
	local list = {}
	if A ~= nil then
		for _, item in ipairs(A) do
			table.insert(list, item)
		end
	end
	if B ~= nil then
		for _, item in ipairs(B) do
			table.insert(list, item)
		end
	end
	return list
end

function Utils._stringHasSpace(str)
	if string.find(str, " ") or string.find(str, "\t") or string.find(str, "\n") then
		return true
	else
		return false
	end
end

function Utils._stringStartsWith(str, prefix)
	return str:sub(1, #prefix) == prefix
end

function Utils._stringSplit(str, delimiter)
	local result = {}
	for match in str:gmatch("([^" .. delimiter .. "]+)") do
		table.insert(result, match)
	end
	return result
end

function Utils._stringCleanSymbols(str)
	return str:gsub("[^a-zA-Z0-9_]", "_")
end

function Utils._isList(obj)
	local isList = true
	for i = 1, #obj do
		if obj[i] == nil then
			isList = false
			break
		end
		break
	end
	return isList
end

return Utils