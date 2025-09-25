local Bit32 = {}
Bit32.__index = Bit32

-- https://stackoverflow.com/a/32389020
function Bit32.bitAnd(a, b)
   local r, m, s = 0, 2^31
   repeat
      s,a,b = a+b+m, a%m, b%m
      r,m = r + m*4%(s-a-b), m/2
   until m < 1
   return r
end
function Bit32.bitXor(a, b)
   local r, m, s = 0, 2^31
   repeat
      s,a,b = a+b+m, a%m, b%m
      r,m = r + m*3%(s-a-b), m/2
   until m < 1
   return r
end
function Bit32.bitOr(a, b)
   local r, m, s = 0, 2^31
   repeat
      s,a,b = a+b+m, a%m, b%m
      r,m = r + m*1%(s-a-b), m/2
   until m < 1
   return r
end

return Bit32