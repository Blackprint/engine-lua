local References = {}
References.__index = References

function References.new()
	local this = setmetatable({}, References)
	this.IInput = {}
	this.Input = {}
	this.IOutput = {}
	this.Output = {}
	return this
end

return References