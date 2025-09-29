local Array = {}
function Array.__index(this, key)
	if type(key) == 'number' then return rawget(this, key)
	elseif key == 'length' then return rawget(Array, 'length')
	elseif key == 'indexOf' then return rawget(Array, 'indexOf')
	elseif key == 'push' then return rawget(Array, 'push')
	elseif key == 'unshift' then return rawget(Array, 'unshift')
	elseif key == 'splice' then return rawget(Array, 'splice')
	elseif key == 'pop' then return rawget(Array, 'pop')
	elseif key == 'shift' then return rawget(Array, 'shift')
	end
end
function Array.__newindex(this, key, val)
	if type(key) ~= 'number' then error("Assigning value to Array must use number as the index") end
	rawset(this, key, val)

	local length = rawget(this, 'length')
	if key >= length then
		rawset(this, 'length', key + 1)
	end
end

function Array.new()
	return setmetatable({ length = 0 }, Array)
end

function Array:push(val)
	local length = rawget(self, 'length')
	rawset(self, length, val)
	rawset(self, 'length', length + 1)
end

function Array:pop()
	local length = rawget(self, 'length')
	if length == 0 then return nil end

	local val = rawget(self, length - 1)
	rawset(self, length - 1, nil)
	rawset(self, 'length', length - 1)
	return val
end

function Array:shift()
	local length = rawget(self, 'length')
	if length == 0 then return nil end

	local val = rawget(self, 0)

	-- Shift all elements to the left
	for i = 0, length - 2 do
		rawset(self, i, rawget(self, i + 1))
	end

	-- Remove the last element
	rawset(self, length - 1, nil)
	rawset(self, 'length', length - 1)
	return val
end

function Array:unshift(val)
	local length = rawget(self, 'length')

	-- Shift all elements to the right
	for i = length - 1, 0, -1 do
		rawset(self, i + 1, rawget(self, i))
	end

	-- Insert the new element at the beginning
	rawset(self, 0, val)
	rawset(self, 'length', length + 1)
end

function Array:splice(start, deleteCount, ...)
	local length = rawget(self, 'length')

	-- Handle negative start index
	if start < 0 then
		start = math.max(0, length + start)
	else
		start = math.min(start, length)
	end

	-- Handle deleteCount
	if deleteCount == nil then
		deleteCount = length - start
	else
		deleteCount = math.max(0, math.min(deleteCount, length - start))
	end

	-- Collect elements to be removed
	local removed = {}
	for i = 0, deleteCount - 1 do
		table.insert(removed, rawget(self, start + i))
	end

	-- Shift elements to fill the gap
	if deleteCount > 0 then
		for i = start, length - deleteCount - 1 do
			rawset(self, i, rawget(self, i + deleteCount))
		end

		-- Clear the removed elements
		for i = length - deleteCount, length - 1 do
			rawset(self, i, nil)
		end

		rawset(self, 'length', length - deleteCount)
	end

	-- Insert new elements if provided
	local insertCount = select('#', ...)
	if insertCount > 0 then
		-- Shift elements to make room for new elements
		for i = length - deleteCount - 1, start - 1, -1 do
			rawset(self, i + insertCount, rawget(self, i))
		end

		-- Insert new elements
		for i = 0, insertCount - 1 do
			rawset(self, start + i, select(i + 1, ...))
		end

		rawset(self, 'length', length - deleteCount + insertCount)
	end

	return unpack(removed)
end

function Array:indexOf(searchElement, fromIndex)
	local length = rawget(self, 'length')

	-- Handle fromIndex parameter
	if fromIndex == nil then
		fromIndex = 0
	else
		if fromIndex < 0 then
			fromIndex = math.max(0, length + fromIndex)
		else
			fromIndex = math.min(fromIndex, length)
		end
	end

	-- Search for the element
	for i = fromIndex, length - 1 do
		if rawget(self, i) == searchElement then
			return i
		end
	end

	return -1
end

return Array