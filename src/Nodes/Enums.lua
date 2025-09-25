local Enums = {}

-- Node type enumerations
Enums.BPEnvGet = 1
Enums.BPEnvSet = 2
Enums.BPVarGet = 3
Enums.BPVarSet = 4
Enums.BPFnVarInput = 5
Enums.BPFnVarOutput = 6  -- Not used, but reserved
Enums.BPFnInput = 7
Enums.BPFnOutput = 8
Enums.BPFnMain = 9
Enums.BPEventListen = 10
Enums.BPEventEmit = 11

-- InitUpdate constants for node initialization rules
Enums.NoRouteIn = 2      -- Only when no input cable connected
Enums.NoInputCable = 4   -- Only when no input cable connected
Enums.WhenCreatingNode = 8  -- When all the cable haven't been connected (other flags may be affected)

return Enums