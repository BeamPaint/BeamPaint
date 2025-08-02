
local htmlTexture = require("htmlTexture")

local M = {}
M.isRightSkin = false
M.isInit = false
M.lastPaint = {}
M.currentPaint = {}

local function initLivery()
    htmlTexture.create("@dynamic_livery", "local://local/vehicles/common/dynamic_livery.html", 2048, 2048, 0, "manual")
    htmlTexture.call("@dynamic_livery", "init")
    local modelName = v.config.model or v.config.mainPartName
    obj:queueGameEngineLua("extensions.BeamPaint.setLiveryUsed(" .. obj:getID() .. ", \"" .. modelName .. "\")")
end

local function isRightSkin(partsTree)
    if partsTree then
        for key, part in pairs(partsTree) do
            if key == "paint_design" or key == "skin_lbe" then
                print(part.chosenPartName)
                if part.chosenPartName == "global_skin_dynamic" or part.chosenPartName == "global_skin_dynamic_lbe" then
                    return true
                end
            end
            if part.children then
                if isRightSkin(part.children) then return true end
            end
        end
        return false
    end
end

local function onExtensionLoaded()
    print("BeamPaint VE loaded!")
    -- M.isRightSkin = v.config.partsTree.paint_design == "global_skin_dynamic"
    -- M.isRightSkin = M.isRightSkin or v.config.partsTree.skin_lbe == "global_skin_dynamic_lbe"
    M.isRightSkin = isRightSkin(v.config.partsTree.children)
    if M.isRightSkin then
        initLivery()
        M.isInit = true
        obj:queueGameEngineLua("extensions.BeamPaint.updatePlayerVehiclePaint(" .. obj:getID() .. ")")
    end
end

local function updateLivery(src, needsGammaCorrection)
    local data = {}
    data.src = src
    data.needsGammaCorrection = needsGammaCorrection
    htmlTexture.call("@dynamic_livery", "updateLivery", data)
end

local function updateGFX(dt)
    if M.isRightSkin then
        if M.lastPaint ~= M.currentPaint and M.isInit then
            M.lastPaint = M.currentPaint
            local data = M.currentPaint
            htmlTexture.call("@dynamic_livery", "updatePaint", data)
        end
    end
end

local function updateCurrentPaint(r, g, b)
    M.currentPaint = {}
    M.currentPaint.baseColor = { r, g, b }
end

M.onExtensionLoaded = onExtensionLoaded
M.updateLivery = updateLivery
M.updateGFX = updateGFX
M.updateCurrentPaint = updateCurrentPaint

return M
