local utils = {}
function utils.colorLog(category, message)
    local colors = {
        reset = "\27[0m",
        red = "\27[31m",
        green = "\27[32m",
        yellow = "\27[33m",
        blue = "\27[34m",
        magenta = "\27[35m",
        cyan = "\27[36m",
        white = "\27[37m",
    }

    local category_color = colors.cyan
    if category:match("Button") then
        category_color = colors.blue
    elseif category:match("Logger") then
        category_color = colors.green
    elseif category:match("Input") then
        category_color = colors.yellow
    elseif category:match("Math") then
        category_color = colors.magenta
    end

    print(string.format("%s%s%s %s%s%s",
        category_color, category, colors.reset,
        colors.white, message, colors.reset
    ))
end

return utils