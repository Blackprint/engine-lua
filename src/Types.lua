local Types = {
    Any = { type = "Any", _internal = true },
    Slot = { type = "Slot", _internal = true },
    Route = { type = "Route", _internal = true },
    Trigger = { type = "Trigger", _internal = true },
}

-- Check if a type is a special Blackprint type
function Types.isType(type)
    if type == Types.Any then return true end
    if type == Types.Slot then return true end
    if type == Types.Route then return true end
    if type == Types.Trigger then return true end
    return false
end

return Types