local JSON = {}

-- Check if we're in Roblox environment
local isRoblox = game and game.GetService

-- Check if we're in Lune environment
local luneSerde = nil
local isLune = pcall(function()
    luneSerde = require("@lune/serde")
	return luneSerde
end)

local luauJSON = isRoblox or isLune or require("@src/LuaUtils/ExternalDeps/JSON.lua")

-- JSON stringify function (Lua table to JSON string)
function JSON.stringify(data)
    -- Use built-in JSON decoder if available (Roblox)
    if isRoblox and game:GetService("HttpService") then
        local HttpService = game:GetService("HttpService")
        return HttpService:JSONEncode(data)
    end

    -- Use Lune serde if available
    if isLune then
        return luneSerde.encode("json", data)
    end

    -- Use rxi JSON as fallback
    if luauJSON then
        return luauJSON.encode(data)
    end

	error("Error: JSON parser in this environment was not found")
end

-- JSON parse function (JSON string to Lua table)
function JSON.parse(jsonStr)
    if type(jsonStr) ~= "string" then
        error("Expected string, got " .. type(jsonStr))
    end

    -- Trim whitespace
    jsonStr = string.match(jsonStr, "^%s*(.-)%s*$")

    if jsonStr == "" then
        error("Empty JSON string")
    end

    -- Use built-in JSON decoder if available (Roblox)
    if isRoblox and game:GetService("HttpService") then
        local HttpService = game:GetService("HttpService")
        return HttpService:JSONDecode(jsonStr)
    end

    -- Use Lune serde if available
    if isLune then
        return luneSerde.decode("json", jsonStr)
    end

    -- Use rxi JSON as fallback
    if luauJSON then
        return luauJSON.decode(jsonStr)
    end

	error("Error: JSON parser in this environment was not found")
end

return JSON