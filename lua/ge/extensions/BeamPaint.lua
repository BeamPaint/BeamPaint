local json = require("json")

local M = {}
M.dependencies = {"ui_imgui"}
local im = ui_imgui

M.markedReady = false
M.alreadySent = {}
M.incompleteTextureData = {}
M.texMap = {}
M.showReloadButton = false

-- TODO: Currently it assumes all packets arrive in order.
--       This should always be true, but we should probably
--       account for it anyway!
local function BP_receiveTextureData(json_data)
    print("Received texture data from server...")
    print(json_data)
    local data = json.decode(json_data)
    dump(data)
    print("Data size: " .. #data.raw)
    local tid = data.target_id
    local raw = mime.unb64(data.raw)
    M.incompleteTextureData[tid] = M.incompleteTextureData[tid] or ""
    -- for i=1,#data.raw do
    --     M.incompleteTextureData[tid][data.raw_offset + i] = data.raw[i]
    -- end
    M.incompleteTextureData[tid] = M.incompleteTextureData[tid] .. raw
    print("Total so far: " .. #M.incompleteTextureData[tid])
    TriggerServerEvent("BP_textureDataReceived", "" .. tid)
end
AddEventHandler("BP_receiveTextureData", BP_receiveTextureData)

local function BP_markTextureComplete(json_data)
    print("Received texture complete status from server...")
    local data = json.decode(json_data)
    local tid = data.target_id
    print("Writing data to a file...")
    local out = io.open("vehicles/common/" .. tid .. ".png", "wb")
    out:write(M.incompleteTextureData[tid])
    out:flush()
    out:close()
    print("Written to file!")
    M.incompleteTextureData[tid] = ""

    local objid = MPVehicleGE.getGameVehicleID(tid)
    M.texMap[objid] = tid
    be:getObjectByID(objid):queueLuaCommand("extensions.BeamPaint.updateLivery(\"" .. tid .. ".png\")")
end
AddEventHandler("BP_markTextureComplete", BP_markTextureComplete)

local function onUpdate(dtSim, dtRaw)
    if M.markedReady == false and worldReadyState >= 2 then
        M.markedReady = true
        TriggerServerEvent("BP_clientReady", "")
        print("Marked myself as ready")
    end
end

local function setLiveryUsed(objid, vehName)
    if MPVehicleGE.isOwn(objid) then
        if M.alreadySent[objid] ~= nil and M.alreadySent[objid].prevVehName == vehName then
            be:getObjectByID(objid):queueLuaCommand("extensions.BeamPaint.updateLivery(\"" .. M.texMap[objid] .. ".png\")")
        else
            M.alreadySent[objid] = { prevVehName = vehName }
            local serverid = MPVehicleGE.getServerVehicleID(objid)
            TriggerServerEvent("BP_setLiveryUsed", "" .. serverid .. ";" .. vehName)
        end
    else
        be:getObjectByID(objid):queueLuaCommand("extensions.BeamPaint.updateLivery(\"" .. M.texMap[objid] .. ".png\")")
    end
end

local function reloadLivery()
    local veh = be:getPlayerVehicle(0)
    if veh then
        local objID = veh:getID()
        M.alreadySent[objID] = nil
        veh:queueLuaCommand("extensions.BeamPaint.onExtensionLoaded()")
    end
end

local function BP_setPremium(json_data)
    local data = json.decode(json_data)
    local role = "BP_PREMIUM"
    if data.isDev then role = "BP_DEV" end
    MPVehicleGE.setVehicleRole(data.tid, role)
end
AddEventHandler("BP_setPremium", BP_setPremium)

local function init()
    MPVehicleGE.createRole("BP_DEV", "BeamPaint DEVELOPER", "BP DEV", 235, 64, 52)
    MPVehicleGE.createRole("BP_PREMIUM", "BeamPaint PREMIUM", "BP PREMIUM", 193, 87, 217)
end

local function onUiChangedState(state)
    M.showReloadButton = state == "menu.vehicleconfig.parts"
end

local function onUpdate(dt)
    if M.showReloadButton then
        if im.Begin("", im.BoolPtr(true), im.WindowFlags_AlwaysAutoResize + im.WindowFlags_NoDecoration) then
            if im.Button("Reload Livery") then
                reloadLivery()
            end
        end
    end
end

M.onExtensionLoaded = init
M.onUpdate = onUpdate
M.setLiveryUsed = setLiveryUsed
M.reloadLivery = reloadLivery
M.onUiChangedState = onUiChangedState
M.onUpdate = onUpdate

return M
