local Node = require("@src/Node.lua")
local Interface = require("@src/Interface.lua")
local Enums = require("@src/Nodes/Enums.lua")
local PortFeature = require("@src/Port/PortFeature.lua")
local Types = require("@src/Types.lua")
local Utils = require("@src/Utils.lua")
local BPVariable = require("@src/Nodes/BPVariable.lua").BPVariable
local VarScope = require("@src/Nodes/BPVariable.lua").VarScope
local registerNode = require("@src/Internal.lua").registerNode
local registerInterface = require("@src/Internal.lua").registerInterface
local PortName = require("@src/Nodes/FnPortVar.lua").PortName
local getFnPortType = require("@src/Nodes/FnPortVar.lua").getFnPortType
local CustomEvent = require("@src/Constructor/CustomEvent.lua")

-- BPFunction class for function management
local BPFunction = setmetatable({}, { __index = CustomEvent })
BPFunction.__index = BPFunction

-- Main function node
local BPFunctionNode = setmetatable({}, { __index = Node })
BPFunctionNode.__index = BPFunctionNode

function BPFunction.new(id, options, instance)
    local obj = setmetatable(CustomEvent.new(), BPFunction)

    obj.node = nil -- Node constructor (Function)
    obj.variables = {} -- shared between function
    obj.privateVars = {} -- private variable (different from other function)
    obj.rootInstance = instance -- root instance (Blackprint.Engine)

    id = Utils._stringCleanSymbols(id)
    obj.id = id
    obj.title = options.title or id

    obj.input = {} -- Port template, in JS we use getter/setter, but in here lets just directly use this field
    obj.output = {} -- Port template, in JS we use getter/setter, but in here lets just directly use this field
    obj.used = {} -- [Interface, ...]

    -- This will be updated if the function sketch was modified
    if options.structure then
        obj.structure = options.structure
    else
        obj.structure = {
            instance = {
                ['BP/Fn/Input'] = {{i = 0}},
                ['BP/Fn/Output'] = {{i = 1}},
            },
        }
    end

    -- Event listeners for environment, variable, function, and event renaming
    obj._envNameListener = function(ev) obj:_onEnvironmentRenamed(ev) end
    obj._varNameListener = function(ev) obj:_onVariableRenamed(ev) end
    obj._funcNameListener = function(ev) obj:_onFunctionRenamed(ev) end
    obj._funcPortNameListener = function(ev) obj:_onFunctionPortRenamed(ev) end
    obj._eventNameListener = function(ev) obj:_onEventRenamed(ev) end

    -- Register event listeners
    obj.rootInstance:on('environment.renamed', obj._envNameListener)
    obj.rootInstance:on('variable.renamed', obj._varNameListener)
    obj.rootInstance:on('function.renamed', obj._funcNameListener)
    obj.rootInstance:on('function.port.renamed', obj._funcPortNameListener)
    obj.rootInstance:on('event.renamed', obj._eventNameListener)

    local temp = obj
    local uniqId = 0

    local function nodeContruct(instance_)
        BPFunctionNode.input = obj.input
        BPFunctionNode.output = obj.output
        BPFunctionNode.namespace = id
        BPFunctionNode.type = 'function'

        instance_.rootInstance = nil
        local node = BPFunctionNode.new(instance_)
        local iface = node.iface

        instance_.bpFunction = temp
        node.bpFunction = temp
        iface.title = temp.title
        iface.type = 'function'
        uniqId = uniqId + 1
        iface.uniqId = uniqId

        iface._enum = Enums.BPFnMain
        iface:_prepare_(BPFunctionNode)
        return node
    end

    obj.node = nodeContruct

    -- For direct function invocation
    obj.directInvokeFn = nil
    obj._syncing = false

    return obj
end

function BPFunction:_onEnvironmentRenamed(ev)
    local instance = self.structure.instance
    local list_ = {}

    if instance['BP/Env/Get'] then
        list_ = list_ or {}
        for _, item in ipairs(instance['BP/Env/Get']) do table.insert(list_, item) end
    end

    if instance['BP/Env/Set'] then
        list_ = list_ or {}
        for _, item in ipairs(instance['BP/Env/Set']) do table.insert(list_, item) end
    end

    for _, item in ipairs(list_) do
        if item.data.name == ev.old then
            item.data.name = ev.now
            item.data.title = ev.now
        end
    end
end

function BPFunction:_onVariableRenamed(ev)
    local instance = self.structure.instance
    if ev.scope == VarScope.public or ev.scope == VarScope.shared then
        local list_ = {}

        if instance['BP/Var/Get'] then
            list_ = list_ or {}
            for _, item in ipairs(instance['BP/Var/Get']) do table.insert(list_, item) end
        end

        if instance['BP/Var/Set'] then
            list_ = list_ or {}
            for _, item in ipairs(instance['BP/Var/Set']) do table.insert(list_, item) end
        end

        for _, item in ipairs(list_) do
            if item.data.scope == ev.scope and item.data.name == ev.old then
                item.data.name = ev.now
            end
        end
    end
end

function BPFunction:_onFunctionRenamed(ev)
    local instance = self.structure.instance
    local oldKey = 'BPI/F/' .. ev.old
    local newKey = 'BPI/F/' .. ev.now

    if instance[oldKey] then
        instance[newKey] = instance[oldKey]
        instance[oldKey] = nil
    end
end

function BPFunction:_onFunctionPortRenamed(ev)
    local instance = self.structure.instance
    local funcs = instance['BPI/F/' .. ev.reference.id]
    if not funcs then return end

    for _, item in ipairs(funcs) do
        if ev.which == 'output' then
            if item.output_sw and item.output_sw[ev.old] then
                item.output_sw[ev.now] = item.output_sw[ev.old]
                item.output_sw[ev.old] = nil
            end
        elseif ev.which == 'input' then
            if item.input_d and item.input_d[ev.old] then
                item.input_d[ev.now] = item.input_d[ev.old]
                item.input_d[ev.old] = nil
            end
        end
    end
end

function BPFunction:_onEventRenamed(ev)
    local instance = self.structure.instance
    local list_ = {}

    if instance['BP/Event/Listen'] then
        list_ = list_ or {}
        for _, item in ipairs(instance['BP/Event/Listen']) do table.insert(list_, item) end
    end

    if instance['BP/Event/Emit'] then
        list_ = list_ or {}
        for _, item in ipairs(instance['BP/Event/Emit']) do table.insert(list_, item) end
    end

    for _, item in ipairs(list_) do
        if item.data.namespace == ev.old then
            item.data.namespace = ev.now
        end
    end
end

function BPFunction:_onFuncChanges(eventName, obj, fromNode)
    local list = self.used

    for _, iface_ in ipairs(list) do
        if iface_.node == fromNode then continue end

        local nodeInstance = iface_.bpInstance
        nodeInstance.pendingRender = true -- Force recalculation for cable position

        if eventName == 'cable.connect' or eventName == 'cable.disconnect' then
            local cable = obj.cable
            local input = cable.input
            local output = cable.output
            local ifaceList = fromNode.iface.bpInstance.ifaceList

            -- Skip event that also triggered when deleting a node
            if input.iface._bpDestroy or output.iface._bpDestroy then continue end

            local inputIface = nodeInstance.ifaceList[Utils.findFromList(ifaceList, input.iface)]
            if not inputIface then error("Failed to get node input iface index") end

            local outputIface = nodeInstance.ifaceList[Utils.findFromList(ifaceList, output.iface)]
            if not outputIface then error("Failed to get node output iface index") end

            if inputIface.namespace ~= input.iface.namespace then
                print(inputIface.namespace .. ' != ' .. input.iface.namespace)
                error("Input iface namespace was different")
            end

            if outputIface.namespace ~= output.iface.namespace then
                print(outputIface.namespace .. ' != ' .. output.iface.namespace)
                error("Output iface namespace was different")
            end

            if eventName == 'cable.connect' then
                local targetInput = inputIface.input[input.name]
                local targetOutput = outputIface.output[output.name]

                if not targetInput then
                    if inputIface._enum == Enums.BPFnOutput then
                        targetInput = inputIface:addPort(targetOutput, output.name)
                    else
                        error("Output port was not found")
                    end
                end

                if not targetOutput then
                    if outputIface._enum == Enums.BPFnInput then
                        targetOutput = outputIface:addPort(targetInput, input.name)
                    else
                        error("Input port was not found")
                    end
                end

                targetInput:connectPort(targetOutput)
            elseif eventName == 'cable.disconnect' then
                local cables = inputIface.input[input.name].cables
                local outputPort = outputIface.output[output.name]

                for _, cable in ipairs(cables) do
                    if cable.output == outputPort then
                        cable:disconnect()
                        break
                    end
                end
            end
        elseif eventName == 'node.created' then
            local iface = obj.iface
            nodeInstance:createNode(iface.namespace, {
                data = iface.data
            })
        elseif eventName == 'node.delete' then
            local index = Utils.findFromList(fromNode.iface.bpInstance.ifaceList, obj.iface)
            if not index then error("Failed to get node index") end

            local iface = nodeInstance.ifaceList[index]
            if iface.namespace ~= obj.iface.namespace then
                print(iface.namespace .. ' ' .. obj.iface.namespace)
                error("Failed to delete node from other function instance")
            end

            nodeInstance:deleteNode(iface)
        end
    end
end

function BPFunction:createNode(instance, options)
    return instance:createNode(self.node, options)
end

function BPFunction:createVariable(id, options)
    if string.find(id, '/') then
        error("Slash symbol is reserved character and currently can't be used for creating path")
    end

    if options.scope == VarScope.private then
        if not Utils.findFromList(self.privateVars, id) then
            table.insert(self.privateVars, id)
            local eventData = {bpFunction = self, scope = VarScope.private, id = id}
            self:emit('variable.new', eventData)
            self.rootInstance:emit('variable.new', eventData)
        end

        -- Add private variable to all function instances
        for _, iface in ipairs(self.used) do
            local vars = iface.bpInstance.variables
            vars[id] = BPVariable.new(id)
        end
        return
    elseif options.scope == VarScope.public then
        error("Can't create public variable from a function")
    end

    -- Shared variable
    if self.variables[id] then
        error("Variable id already exist: " .. id)
    end

    local temp = BPVariable.new(id, options)
    temp.funcInstance = self
    temp._scope = options.scope
    self.variables[id] = temp

    local eventData = {
        reference = temp,
        scope = temp._scope,
        id = temp.id
    }
    self:emit('variable.new', eventData)
    self.rootInstance:emit('variable.new', eventData)
    return temp
end

function BPFunction:renameVariable(from_, to, scopeId)
    if not scopeId then error("Third parameter couldn't be null") end
    if string.find(to, '/') then
        error("Slash symbol is reserved character and currently can't be used for creating path")
    end

    to = Utils._stringCleanSymbols(to)

    if scopeId == VarScope.private then
        local index = Utils.findFromList(self.privateVars, from_)
        if index == -1 then
            error("Private variable with name '" .. from_ .. "' was not found on '" .. self.id .. "' function")
        end
        self.privateVars[index] = to
    elseif scopeId == VarScope.shared then
        local varObj = self.variables[from_]
        if not varObj then
            error("Shared variable with name '" .. from_ .. "' was not found on '" .. self.id .. "' function")
        end

        varObj.id = to
        varObj.title = to
        self.variables[to] = varObj
        if self.variables[from_] then self.variables[from_] = nil end

        self.rootInstance:emit('variable.renamed', {
            old = from_, now = to, reference = varObj, scope = scopeId,
        })
    else
        error("Can't rename variable from scopeId: " .. scopeId)
    end

    -- Update references in all function instances
    local lastInstance = nil
    if scopeId == VarScope.shared then
        local used = self.variables[to].used
        for _, iface in ipairs(used) do
            iface.title = to
            iface.data.name = to
            lastInstance = iface.node.instance
        end
    else
        for _, iface in ipairs(self.used) do
            lastInstance = iface.bpInstance
            lastInstance:renameVariable(from_, to, scopeId)
        end
    end
end

function BPFunction:deleteVariable(namespace, scopeId)
    if scopeId == VarScope.public then
        return self.rootInstance:deleteVariable(namespace, scopeId)
    end

    local used = self.used
    local path = Utils._stringSplit(namespace, '/')

    if scopeId == VarScope.private then
        local index = Utils.findFromList(self.privateVars, namespace)
        if index == -1 then return end
        table.remove(self.privateVars, index)

        used[1].bpInstance:deleteVariable(namespace, scopeId)

        -- Delete from all function node instances
        for i = 2, #used do
            local instance = used[i]
            local varsObject = instance.variables
            local oldObj = Utils.getDeepProperty(varsObject, path)
            if oldObj then
                if scopeId == VarScope.private then
                    oldObj:destroy()
                end
                Utils.deleteDeepProperty(varsObject, path, true)
                local eventData = {scope = oldObj._scope, id = oldObj.id, bpFunction = self}
                instance:emit('variable.deleted', eventData)
            end
        end
    elseif scopeId == VarScope.shared then
        local oldObj = Utils.getDeepProperty(self.variables, path)
        used[1].bpInstance:deleteVariable(namespace, scopeId)

        -- Delete from all function node instances
        local eventData = {scope = oldObj._scope, id = oldObj.id, reference = oldObj}
        for _, iface in ipairs(used) do
            iface.bpInstance:emit('variable.deleted', eventData)
        end
    end
end

function BPFunction:renamePort(which, fromName, toName)
    local main = self[which]
    main[toName] = main[fromName]
    main[fromName] = nil

    local used = self.used
    local proxyPort = 'input'
    if which == 'output' then proxyPort = 'output' end

    for _, iface in ipairs(used) do
        iface.node:renamePort(which, fromName, toName)

        if which == 'output' then
            local list_ = iface._proxyOutput
            for _, item in ipairs(list_) do
                item.iface:renamePort(proxyPort, fromName, toName)
            end
        else -- input
            local temp = iface._proxyInput
            if temp.iface and temp.iface[proxyPort] and temp.iface[proxyPort][fromName] then
                temp.iface[proxyPort][fromName]._name.name = toName
            end
            temp:renamePort(proxyPort, fromName, toName)
        end

        local ifaces = iface.bpInstance.ifaceList
        for _, proxyVar in ipairs(ifaces) do
            if (which == 'output' and proxyVar.namespace ~= "BP/FnVar/Output") or
               (which == 'input' and proxyVar.namespace ~= "BP/FnVar/Input") then
                continue
            end

            if proxyVar.data.name == fromName then
                proxyVar.data.name = toName
            end

            if which == 'output' and proxyVar.input and proxyVar.input['Val'] then
                proxyVar.input['Val']._name.name = toName
            end
        end
    end

    self.rootInstance:emit('function.port.renamed', {
        old = fromName, now = toName, reference = self, which = which,
    })
end

function BPFunction:deletePort(which, portName)
    local used = self.used
    if #used == 0 then
        error("One function node need to be placed to the instance before deleting port")
    end

    local main = self[which]
    main[portName] = nil

    local hasDeletion = false
    for _, iface in ipairs(used) do
        if which == 'output' then
            local list_ = iface._proxyOutput
            for _, item in ipairs(list_) do
                item.iface:deletePort(portName)
            end
            hasDeletion = true
        elseif which == 'input' then
            iface._proxyInput.iface:deletePort(portName)
            hasDeletion = true
        end
    end

    if hasDeletion then
        used[1]:_save(false, false, true)
        self.rootInstance:emit('function.port.deleted', {
            which = which, name = portName, reference = self,
        })
    end
end

function BPFunction:invoke(input)
    local iface = self.directInvokeFn
    if not iface then
        self.directInvokeFn = self:createNode(self.rootInstance)
        iface = self.directInvokeFn
        iface.bpInstance.executionOrder.stop = true -- Disable execution order and force to use route cable
        iface.bpInstance.pendingRender = true
        iface.isDirectInvoke = true -- Mark this node as direct invoke, for some optimization

        -- For sketch instance, we will remove it from sketch visibility
        local sketchScope = iface.node.instance.scope
        if sketchScope then
            local list_ = sketchScope('nodes').list
            if Utils.findFromList(list_, iface) then
                table.remove(list_, Utils.findFromList(list_, iface))
            end
        end

        -- Wait until ready - using event listener instead of Promise
        local ready_event = false

        local function on_ready()
            iface:off('ready', on_ready)
            ready_event = true
        end

        iface:once('ready', on_ready)
        while not ready_event do
            -- In Lua, we need to simulate waiting
            -- This is a simplified version - in real implementation you'd use coroutines
        end
    end

    local proxyInput = iface._proxyInput
    if not proxyInput.routes.out then
        error(self.id .. ": Blackprint function node must have route port that connected from input node to the output node")
    end

    local inputPorts = proxyInput.iface.output
    for key, port in pairs(inputPorts) do
        local val = input[key]

        if port.value == val then
            continue -- Skip if value is the same
        end

        -- Set the value if different, and reset cache and emit value event after this line
        port.value = val

        -- Check all connected cables, if any node need to synchronize
        local cables = port.cables
        for _, cable in ipairs(cables) do
            if cable.hasBranch then continue end
            local inp = cable.input
            if not inp then continue end

            inp._cache = nil
            inp:emit('value', {port = inp, target = iface, cable = cable})
        end
    end

    proxyInput.routes:routeOut()

    local ret = {}
    local outputs = iface.node.output
    for key, value in pairs(outputs) do
        ret[key] = value
    end

    return ret
end

function BPFunction:addPrivateVars(id)
    if string.find(id, '/') then
        error("Slash symbol is reserved character and currently can't be used for creating path")
    end

    if not Utils.findFromList(self.privateVars, id) then
        table.insert(self.privateVars, id)

        local evData = {
            instance = self,
            scope = VarScope.private,
            id = id,
        }
        self:emit('variable.new', evData)
        self.rootInstance:emit('variable.new', evData)
    else
        return
    end

    local list = self.used
    for _, iface in ipairs(list) do
        local vars = iface.bpInstance.variables
        vars[id] = BPVariable.new(id)
    end
end

function BPFunction:refreshPrivateVars(instance)
    local vars = instance.variables

    local list = self.privateVars
    for _, id in ipairs(list) do
        vars[id] = BPVariable.new(id)
    end
end

function BPFunction:destroy()
    local map = self.used
    for _, iface in ipairs(map) do
        iface.node.instance:deleteNode(iface)
    end
end

function BPFunctionNode.new(instance)
    local obj = setmetatable(Node.new(instance), BPFunctionNode)
    local iface = obj:setInterface("BPIC/BP/Fn/Main")
    iface.type = 'function'
    iface._enum = Enums.BPFnMain
    return obj
end

function BPFunctionNode:init()
    -- This is required when the node is created at runtime (maybe from remote or Sketch)
    if not self.iface._importOnce then self.iface:_BpFnInit() end
end

function BPFunctionNode:imported(data)
    local instance = self.bpFunction
    table.insert(instance.used, self.iface)
end

function BPFunctionNode:update(cable)
    local iface = self.iface._proxyInput.iface
    local Output = iface.node.output

    if not cable then -- Triggered by port route
        local IOutput = iface.output
        local thisInput = self.input

        -- Sync all port value
        for key, value in pairs(IOutput) do
            if value.type == Types.Trigger then continue end
            Output[key] = thisInput[key]
        end

        return
    end

    -- Update output value on the input node inside the function node
    Output[cable.input.name] = cable.value
end

function BPFunctionNode:destroy()
    local used = self.bpFunction.used
    local index = Utils.findFromList(used, self.iface)
    if index then table.remove(used, index) end

    self.iface.bpInstance:destroy()
end

registerNode('BP/Fn/Input', function(class, extends)
	class.output = {}

    function class:constructor(instance)
        local iface = self:setInterface('BPIC/BP/Fn/Input')
        iface._enum = Enums.BPFnInput
        iface._proxyInput = true -- Port is initialized dynamically

        local funcMain = instance.parentInterface
        iface.parentInterface = funcMain
        funcMain._proxyInput = self
    end

    function class:imported(data)
        local input = self.iface.parentInterface.node.bpFunction.input

        for key, value in pairs(input) do
            self:createPort('output', key, value)
        end
    end

    function class:request(cable)
        local name = cable.output.name

        -- This will trigger the port to request from outside and assign to this node's port
        self.output[name] = self.iface.parentInterface.node.input[name]
    end
end)

registerNode('BP/Fn/Output', function(class, extends)
    class.input = {}

    function class:constructor(instance)
        local iface = self:setInterface('BPIC/BP/Fn/Output')
        iface._enum = Enums.BPFnOutput
        iface._dynamicPort = true -- Port is initialized dynamically

        local funcMain = instance.parentInterface
        iface.parentInterface = funcMain
        funcMain._proxyOutput = self
    end

    function class:imported(data)
        local output = self.iface.parentInterface.node.bpFunction.output

        for key, value in pairs(output) do
            self:createPort('input', key, value)
        end
    end

    function class:update(cable)
        local iface = self.iface.parentInterface
        local Output = iface.node.output

        if not cable then -- Triggered by port route
            local IOutput = iface.output
            local thisInput = self.input

            -- Sync all port value
            for key, value in pairs(IOutput) do
                if value.type == Types.Trigger then continue end
                Output[key] = thisInput[key]
            end

            return
        end

        Output[cable.input.name] = cable.value
    end
end)

-- Interface classes
registerInterface('BPIC/BP/Fn/Main', function(class, extends)
    function class:constructor(node)
        self._importOnce = false
        self._save = nil
        self._portSw_ = nil
        self._proxyInput = nil
        self.uniqId = nil
    end

    function class:_BpFnInit()
        if self._importOnce then
            error("Can't import function more than once")
        end

        self._importOnce = true
        local node = self.node

        -- ToDo: will this be slower if we lazy import the module like below?
        local Engine = require("@src/Engine.lua")
        self.bpInstance = Engine.new()
        if self.data and self.data.pause then
            self.bpInstance.executionOrder.pause = true
        end

        local bpFunction = node.bpFunction
        local newInstance = self.bpInstance
        newInstance.variables = {} -- _for one function
        newInstance.sharedVariables = bpFunction.variables -- shared between function
        newInstance.functions = node.instance.functions
        newInstance.events = node.instance.events
        newInstance.parentInterface = self
        newInstance.rootInstance = bpFunction.rootInstance

        bpFunction:refreshPrivateVars(newInstance)

        local swallowCopy = {}
        for k, v in pairs(bpFunction.structure) do swallowCopy[k] = v end
        newInstance:importJSON(swallowCopy, {clean = false})

        -- Init port switches
        if self._portSw_ then
            self:_initPortSwitches(self._portSw_)
            self._portSw_ = nil

            local InputIface = self._proxyInput.iface
            if InputIface._portSw_ then
                InputIface:_initPortSwitches(InputIface._portSw_)
                InputIface._portSw_ = nil
            end
        end

        local function _save(ev, eventName, force)
            if force or bpFunction._syncing then return end

            newInstance.rootInstance:emit(eventName, ev)

            bpFunction._syncing = true
            bpFunction:_onFuncChanges(eventName, ev, self.node)
            bpFunction._syncing = false
        end

        self._save = _save
        self.bpInstance:on('cable.connect cable.disconnect node.created node.delete node.id.changed port.default.changed _port.split _port.unsplit _port.resync.allow _port.resync.disallow', self._save)
    end

    function class:imported(data) self.data = data end
    function class:renamePort(which, fromName, toName)
        self.node.bpFunction:renamePort(which, fromName, toName)
        self._save(false, false, true)
    end
end)

local BPFnInOut = setmetatable({}, { __index = Interface })
BPFnInOut.__index = BPFnInOut

function BPFnInOut.new(iface)
    iface._dynamicPort = true -- Port is initialized dynamically
end

function BPFnInOut:addPort(port, customName)
    if not port then return end

    if Utils._stringStartsWith(port.iface.namespace, "BP/Fn") then
        error("Function Input can't be connected directly to Output")
    end

    local name = ''
    if customName then
        if port._name then
            name = port._name.name
        else
            name = customName
        end
    else
        name = port.name
    end

    local nodeA = nil
    local nodeB = nil
    local refName = nil
    local portType = nil

    -- nodeA, nodeB # Main (input) . Input (output), Output (input) . Main (output)
    if self.type == 'bp-fn-input' then -- Main (input) . Input (output):
        local inc = 1
        while self.output[name] do
            if self.output[name .. inc] then inc = inc + 1
            else
                name = name .. inc
                break
            end
        end

        nodeA = self.parentInterface.node
        nodeB = self.node
        refName = PortName.new(name)

        portType = getFnPortType(port, 'input', self, refName)
        nodeA.bpFunction.input[name] = portType

    else -- Output (input) . Main (output)
        local inc = 1
        while self.input[name] do
            if self.input[name .. inc] then inc = inc + 1
            else
                name = name .. inc
                break
            end
        end

        nodeA = self.node
        nodeB = self.parentInterface.node
        refName = PortName.new(name)

        portType = getFnPortType(port, 'output', self, refName)
        nodeB.bpFunction.output[name] = portType
    end

    local outputPort = nodeB:createPort('output', name, portType)
    local inputPort = nil

    if portType == Types.Trigger then
        inputPort = nodeA:createPort('input', name, PortFeature.Trigger(function(port) outputPort:_callAll() end))
    else
        inputPort = nodeA:createPort('input', name, portType)
    end

    if self.type == 'bp-fn-input' then
        outputPort._name = refName -- When renaming port, this also need to be changed
        self:emit("_add." .. name, outputPort)
        return outputPort
    end

    inputPort._name = refName -- When renaming port, this also need to be changed
    self:emit("_add." .. name, inputPort)
    return inputPort
end

function BPFnInOut:renamePort(fromName, toName)
    local bpFunction = self.parentInterface.node.bpFunction

    -- Main (input) . Input (output)
    if self.type == 'bp-fn-input' then
        bpFunction:renamePort('input', fromName, toName)
    -- Output (input) . Main (output)
    else
        bpFunction:renamePort('output', fromName, toName)
    end
end

function BPFnInOut:deletePort(name)
    local funcMainNode = self.parentInterface.node
    if self.type == 'bp-fn-input' then -- Main (input): . Input (output):
        funcMainNode:deletePort('input', name)
        self.node:deletePort('output', name)
        funcMainNode.bpFunction.input[name] = nil
    else -- Output (input) . Main (output)
        funcMainNode:deletePort('output', name)
        self.node:deletePort('input', name)
        funcMainNode.bpFunction.output[name] = nil
    end
end

registerInterface('BPIC/BP/Fn/Input', function(class, extends) extends(BPFnInOut)
    function class:constructor(node)
        BPFnInOut.new(self)
        self.title = 'Input'
        self.type = 'bp-fn-input'
    end
end)

registerInterface('BPIC/BP/Fn/Output', function(class, extends) extends(BPFnInOut)
    function class:constructor(node)
        BPFnInOut.new(self)
        self.title = 'Output'
        self.type = 'bp-fn-output'
    end
end)

return {
    BPFunction = BPFunction,
}