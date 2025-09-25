local Class = {}
local isCurrentClassRawGet = {} -- do not modify
local isThisRawGet = {} -- do not modify
local isRootConfigGetter = {} -- do not modify

function Class.extends(parentA, parentB, parentC, parentD, root_config, current_class)
	local indexCache = {}

	return function(this, key)
		local cached = indexCache[key]
		if cached then
			if cached == isThisRawGet then return rawget(this, key)
			elseif cached == isCurrentClassRawGet then return rawget(current_class, key)
			elseif cached == isRootConfigGetter then return root_config.get[key](this)
			end

			return cached
		end

		-- Check getter and setter first
		if root_config ~= nil then
			local val = root_config.get[key]
			if val then
				indexCache[key] = isRootConfigGetter
				return val(this) -- Invoke the getter
			end
		end

		-- Check if method or property exist on current object/table (ToDo: is the required? try remove this)
		local thisTemp = rawget(this, key)
		if thisTemp ~= nil then
			indexCache[key] = isThisRawGet
			return thisTemp
		end

		-- Check if method or property exist on current class
		if current_class ~= nil then
			local temp = rawget(current_class, key)
			if temp ~= nil then
				indexCache[key] = isCurrentClassRawGet
				return temp
			end
		end

		-- Check if method or property exist on parent class
		local found = nil
		if parentA ~= nil and parentA[key] ~= nil then
			found = parentA[key]
		elseif parentB ~= nil and parentB[key] ~= nil then
			found = parentB[key]
		elseif parentC ~= nil and parentC[key] ~= nil then
			found = parentC[key]
		elseif parentD ~= nil and parentD[key] ~= nil then
			found = parentD[key]
		end

		indexCache[key] = found
		return found
	end
end

function Class.prototype(func, parentC, parentD)
	local class = {}

	local parentA = nil
	local parentB = nil
	func(class, function(parentA_, parentB_) -- extends()
		parentA = parentA_
		parentB = parentB_
	end)

	-- Setup the getter and parent inherits
	class.__index = Class.extends(parentA, parentB, parentC, parentD, class.root_config, class)

	-- Setup the setter
	if class.root_config and class.root_config.set then
		local setter = class.root_config.set
		class.__newindex = function(this, key, val)
			local func = setter[key]
			if func then
				func(this, val) -- Invoke the setter
			else
				rawset(this, key, val)  -- Set other properties normally
			end
		end
	end

	return {
		applyPrototype = function(obj)
			return setmetatable(obj, class)
		end,
		prototype = class
	}
end

return Class