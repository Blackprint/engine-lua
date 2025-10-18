local Types = require("@src/Types.lua")
local Internal = require("@src/Internal.lua")
local Utils = require("@src/Utils.lua")
local Port = nil -- Lazy load to avoid circular error

local Tools = {}

-- Extract skeleton from Blackprint nodes and documentation
-- @return string JSON string containing nodes structure and documentation
function Tools.extractSkeleton()
	-- local docs = Blackprint._docs or {}
	local nodes = {}
	local virtualType = {}

	-- Convert type to string representation
	local function vType(type_)
		if type(type_) == 'table' then
			if type_.virtualType then
				local result = {}
				for i, v in ipairs(type_.virtualType) do
					result[i] = v.name
				end
				return table.concat(result, ',')
			end
			if type_.type then
				type_ = type_.type
			end
		end

		if type_ == Types.Any then return 'BP.Any'
		elseif type_ == Types.Trigger then return 'BP.Trigger'
		elseif type_ == Types.Route then return 'BP.Route'
		else
			local typeStr = type(type_)
			if typeStr == "number" then return 'Number'
			elseif typeStr == "string" then return 'String'
			elseif typeStr == "table" then return 'Object'
			elseif typeStr == "boolean" then return 'Boolean'
			end
		end

		if type(type_) == "table" then
			local types = {}
			for i, t in ipairs(type_) do
				types[i] = vType(t)
			end
			return table.concat(types, ',')
		end

		local existIndex
		for i, vt in ipairs(virtualType) do
			if vt == type_ then
				existIndex = i
				break
			end
		end

		if not existIndex then
			existIndex = #virtualType + 1
			table.insert(virtualType, type_)
		end

		return type(type_) .. '.' .. existIndex
	end

	-- Recursively process nested structure
	local function deep(nest, save, first)
		for key, ref in pairs(nest) do
			-- if ref.hidden then continue end
			if Utils._stringStartsWith(key, 'BP') then continue end
			if key == 'class' or key == '__index'or key == 'new' then continue end

			ref = ref.class
			-- if type(ref) == "table" then
			-- 	if not save[key] then save[key] = {} end
			-- 	deep(ref, save[key])
			-- 	continue
			-- end
			-- else .. ref == class

			if not save[key] then save[key] = {} end
			local temp = save[key]
			temp.input = {}
			temp.output = {}

			for which, target in pairs(temp) do
				if not ref[which] then continue end

				local refTarget = ref[which]
				for name, type_ in pairs(refTarget) do
					local savePort = temp[which]

					if type_.feature then
						if type_.feature == Port.ArrayOf then
							savePort[name] = 'BP.ArrayOf<' .. vType(type_) .. '>'
						elseif type_.feature == Port.StructOf then
							savePort[name] = 'BP.StructOf<' .. vType(type_) .. '>'
						elseif type_.feature == Port.Trigger then
							savePort[name] = 'BP.Trigger'
						elseif type_.feature == Port.Union then
							savePort[name] = 'BP.Union<' .. vType(type_) .. '>'
						elseif type_.feature == Port.VirtualType then
							savePort[name] = 'VirtualType<' .. vType(type_) .. '>'
						end
					elseif type_ == Types.Any then savePort[name] = 'BP.Any'
					elseif type_ == Types.Trigger then savePort[name] = 'BP.Trigger'
					elseif type_ == Types.Route then savePort[name] = 'BP.Route'
					else
						local typeStr = type(type_)
						if typeStr == "number" then savePort[name] = 'Number'
						elseif typeStr == "string" then savePort[name] = 'String'
						elseif typeStr == "table" then savePort[name] = 'Object'
						elseif typeStr == "boolean" then savePort[name] = 'Boolean'
						else savePort[name] = 'VirtualType<' .. vType(type_) .. '>'
						end
					end
				end
			end

			-- Rename
			temp['$input'] = temp.input
			temp['$output'] = temp.output

			temp.input = nil
			temp.output = nil
		end
	end

	-- Lazy load Port module
	if not Port then Port = require("@src/Port/PortFeature.lua") end

	-- Get nodes from Blackprint module
	local nodesDict = Internal.nodes or {}
	deep(nodesDict, nodes)

	-- Convert to JSON (using JSON library if available, otherwise simple string conversion)
	local result = {
		nodes = nodes,
		-- docs = docs
	}

	-- Try to use JSON library, fallback to simple string conversion
	if pcall(function()
		local json = require("json")
		return json.encode(result)
	end) then
		local json = require("json")
		return json.encode(result)
	else
		-- Simple fallback for environments without JSON library
		local function encodeValue(val, indent)
			if type(val) == "string" then
				return string.format("%q", val)
			elseif type(val) == "number" or type(val) == "boolean" then
				return tostring(val)
			elseif type(val) == "table" then
				local result = "{"
				local first = true
				for k, v in pairs(val) do
					if not first then result = result .. "," end
					result = result .. "\n" .. (indent or "") .. "  "
					if type(k) == "string" then
						result = result .. string.format("%q", k) .. ": "
					else
						result = result .. tostring(k) .. ": "
					end
					result = result .. encodeValue(v, (indent or "") .. "  ")
					first = false
				end
				if #result > 1 then -- Only add newline if we added content
					result = result .. "\n" .. (indent or "")
				end
				result = result .. "}"
				return result
			else
				return "null"
			end
		end

		return encodeValue(result, "")
	end
end

return Tools