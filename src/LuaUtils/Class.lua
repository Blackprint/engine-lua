local Class = {}

-- do not modify, this just act like an enum/flag
local isCurrentClassRawGet = {}
local isThisRawGet = {}
local isAccessorDirectGet = {}
local isRootConfigGetter = {}

function Class._create(parentA, parentB, parentC, parentD, current_class)
	local indexCache = {}
	local defineProperty = nil
	if current_class then defineProperty = current_class.defineProperty end

	return function(this, key)
		local cached = indexCache[key]
		if cached then
			if cached == isThisRawGet then return rawget(this, key)
			elseif cached == isAccessorDirectGet then
				local _classData = rawget(this, '_classData')
				if _classData == nil then return end
				return _classData[key]
			elseif cached == isCurrentClassRawGet then return rawget(current_class, key)
			elseif cached == isRootConfigGetter then return defineProperty[key].get(this)
			end

			return cached
		end

		-- Check getter and setter first
		if defineProperty ~= nil then
			local getter = defineProperty[key]
			if getter then
				getter = getter.get
				if getter == true then
					indexCache[key] = isAccessorDirectGet
					local _classData = rawget(this, '_classData')
					if _classData == nil then return end
					return _classData[key]
				end
				if getter then
					indexCache[key] = isRootConfigGetter
					return getter(this) -- Invoke the getter
				end
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

function Class._prototype(func, parentC, parentD)
	local class = {}

	local parentA = nil
	local parentB = nil
	func(class, function(parentA_, parentB_) -- extends()
		parentA = parentA_
		parentB = parentB_
	end)

	-- Setup the getter and parent inherits
	class.__index = Class._create(parentA, parentB, parentC, parentD, class)

	-- Setup the setter
	if class.defineProperty then
		local defineProperty = class.defineProperty
		class.__newindex = function(this, key, val)
			local prop = defineProperty[key]
			if prop and prop.set then
				local retVal = prop.set(this, val) -- Invoke the setter

				if prop.get == true then
					local _classData = rawget(this, '_classData')
					if _classData == nil then
						_classData = {}
						rawset(this, '_classData', _classData)
					end

					_classData[key] = retVal
				end
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

function Class.create(func) return Class.extends(nil, func) end
function Class.extends(parentClass, func)
	if parentClass == nil then parentClass = {} end

	local defineProperty = {}
	local prototype = {
		prototype = parentClass.prototype,
	}
	local _metatable = {
		__index = function(this, key)
			local ref = defineProperty[key]

			if ref ~= nil then
				if ref.get == nil then
					return
				elseif ref.get == true then
					local temp = rawget(this, '_classData')
					if temp ~= nil then
						return temp[key]
					end
				else
					return ref.get(this, key)
				end
			end
			return prototype[key]
		end,
		__newindex = function(this, key, val)
			local ref = defineProperty[key]
			if ref ~= nil then
				if ref.set == nil then error("Setter is not defined for: " .. key) end

				local retVal = ref.set(val, this)
				if ref.get == true then
					local classData = rawget(this, '_classData')
					if classData == nil then
						classData = {}
						rawset(this, '_classData', classData)
					end

					classData[key] = retVal
				end
			else
				rawset(this, key, val)
			end
		end,
	}

	local static = {
		_metatable = _metatable,
		prototype = prototype
	}
	static.new = function(...)
		local obj = {}
		setmetatable(obj, _metatable)
		obj:constructor(...)
		obj.constructor = static
		return obj
	end

	func(prototype, parentClass.prototype, static)
	if prototype.defineProperty then defineProperty = prototype.defineProperty end

	local parentPrototype = parentClass.prototype
	if parentPrototype ~= nil then
		for key, value in pairs(parentPrototype) do
			if prototype[key] == nil and type(value) == "function" then
				prototype[key] = value
			end

			if key == 'defineProperty' then
				for key_, value_ in pairs(parentPrototype.defineProperty) do
					if defineProperty[key_] == nil then defineProperty[key_] = value_ end
				end
			end
		end
	end

	return static
end

return Class