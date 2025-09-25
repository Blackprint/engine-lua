local Event = require("@src/Event.lua")

local Environment = {}

-- Static properties
Environment._noEvent = false
Environment.map = {} -- { key => value }
Environment._rules = {} -- { key => options }

-- Import environment variables from a dictionary
function Environment.imports(arr)
    Environment._noEvent = true
    for key, value in pairs(arr) do
        Environment.set(key, value)
    end

    Environment._noEvent = false
    Event:emit('environment.imported')
end

-- Set an environment variable
function Environment.set(key, val)
    -- Validate key format (must be uppercase, alphanumeric with underscores, not starting with number)
    if not string.match(key, "^[A-Z_][A-Z0-9_]*$") then
        error(string.format("Environment must be uppercase and not contain any symbol except underscore, and not started by a number. But got: %s", key))
    end

    -- Validate value type (must be string)
    if type(val) ~= "string" then
        error(string.format("Environment value must be a string (found \"%s\" in %s)", tostring(val), key))
    end

    Environment.map[key] = val

    if not Environment._noEvent then
        Event:emit('environment.added', {
            key = key,
            value = val,
        })
    end
end

-- Delete an environment variable
function Environment.delete(key)
    if Environment.map[key] then
        Environment.map[key] = nil
    end

    Event:emit('environment.deleted', {
        key = key,
    })
end

-- Rename an environment variable
function Environment._rename(keyA, keyB)
    if not keyB then return end

    -- Validate new key format
    if not string.match(keyB, "^[A-Z_][A-Z0-9_]*$") then
        error(string.format("Environment must be uppercase and not contain any symbol except underscore, and not started by a number. But got: %s", keyB))
    end

    if not Environment.map[keyA] then
        error(string.format("%s was not defined in the environment", keyA))
    end

    Environment.map[keyB] = Environment.map[keyA]
    Environment.map[keyA] = nil

    Event:emit('environment.renamed', { old = keyA, now = keyB })
end

-- Set rules for an environment variable
-- options = {allowGet: {}, allowSet: {}}
function Environment.rule(name, options)
    if not Environment.map[name] then
        error(string.format("'%s' was not found on Blackprint.Environment, maybe it haven't been added or imported", name))
    end

    if Environment._rules[name] then
        error("'rule' only allow first registration")
    end

    Environment._rules[name] = options
end

return Environment