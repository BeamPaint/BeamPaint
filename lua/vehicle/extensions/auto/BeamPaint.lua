local htmlTexture = require("htmlTexture")

local M = {}

htmlTexture.create("@dynamic_livery", "local://local/vehicles/common/dynamic_livery.html", 1024, 1024, 0, "manual")
htmlTexture.call("@dynamic_livery", "init")

local function initLivery()
    obj:queueGameEngineLua("extensions.BeamPaint.setLiveryUsed(" .. obj:getID() .. ", \"" .. v.config.mainPartName .. "\")")
end

local function updateLivery(src)
    local data = {}
    data.src = src;
    htmlTexture.call("@dynamic_livery", "updateLivery", data)
end

M.onExtensionLoaded = initLivery
M.updateLivery = updateLivery

return M
