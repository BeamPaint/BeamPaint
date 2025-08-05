
local M = {}

M.dependencies = {"ui_imgui"}

local im = ui_imgui

M.markedReady = false
M.alreadySent = {}
M.incompleteTextureData = {}
M.texMap = {}
M.inVehicleConfigMenu = false
M.inVehiclePaintMenu = false
M.singlePlayer = true
M.waitingForRole = {}
M.waitingForLivery = {}
M.waitingForSetLivery = {}

-- TODO: Currently it assumes all packets arrive in order.
--       This should always be true, but we should probably
--       account for it anyway!
local function BP_receiveTextureData(json_data)
    local data = jsonDecode(json_data)
    local tid = data.target_id
    local raw = mime.unb64(data.raw)
    M.incompleteTextureData[tid] = M.incompleteTextureData[tid] or ""
    M.incompleteTextureData[tid] = M.incompleteTextureData[tid] .. raw
    TriggerServerEvent("BP_textureDataReceived", "" .. tid)
end

local function BP_reportPlayerCache()
    local liveryCache = {}
    local pngs = FS:findFiles("vehicles/common/", '*.png', 0, false, false)
    for index, path in pairs(pngs) do
        if string.match(path, "(%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x)") then --look at my regex, dawg, I'm going to jail
            local hash = string.sub(path, 18)
            hash = string.sub(hash, 1, 36)
            liveryCache[index] = hash
        end
    end
    TriggerServerEvent("BP_cachedLiveryReport", jsonEncode(liveryCache))
end

local function BP_updatePlayerCache(hash)
    TriggerServerEvent("BP_cachedLiveryUpdate", hash)
end

local function BP_cacheUpdateComplete(type)
    if type == "report" then
        TriggerServerEvent("BP_clientReady", "")
    elseif type == "update" then
        
    end
end

local function applyLiveryAttempt()
    local tidHash = table.remove(M.waitingForLivery, 1)
    local tid = string.sub(tidHash, 1, 3)
    local hash = string.sub(tidHash, 4)
    local objid = MPVehicleGE.getGameVehicleID(tid)
    if objid and objid ~= -1 then
        local vehicle = MPVehicleGE.getVehicleByGameID(objid)
        if vehicle.isSpawned then
            M.texMap[objid] = tidHash
            be:getObjectByID(objid):queueLuaCommand("extensions.BeamPaint.updateLivery(\"" .. hash .. ".png\")")
        else
            table.insert(M.waitingForLivery, tidHash)
        end
    else
        table.insert(M.waitingForLivery, tidHash)
    end
end

local function BP_markTextureComplete(json_data)
    print("Received texture complete status from server...")
    local data = jsonDecode(json_data)
    local tid = data.target_id
    local hash = data.livery_id
    local tidHash = tid .. hash
    print("Writing data to a file...")
    local out = io.open("vehicles/common/" .. hash .. ".png", "wb")
    if out then
        out:write(M.incompleteTextureData[tid])
        out:flush()
        out:close()
        print("Written to file!")
    else
        print("Could not write to file!")
    end
    M.incompleteTextureData[tid] = ""
    table.insert(M.waitingForLivery, tidHash)
end

local function BP_textureSkip(json_data)
    print("Received texture skip status from server...")
    local data = jsonDecode(json_data)
    local tid = data.target_id
    local hash = data.livery_id
    local tidHash = tid .. hash
    print("Livery cached, applying now...")
    M.incompleteTextureData[tid] = ""
    table.insert(M.waitingForLivery, tidHash)
    BP_updatePlayerCache(hash)
end

local function setLiveryUsedAttempt(objid, vehName)
    if MPVehicleGE.isOwn(objid) then
        if M.alreadySent[objid] ~= nil and M.alreadySent[objid].prevVehName == vehName then
            local tidHash = M.texMap[objid]
            local tid = string.sub(tidHash, 1, 3)
            local hash = string.sub(tidHash, 4)
            if tid then
                be:getObjectByID(objid):queueLuaCommand("extensions.BeamPaint.updateLivery(\"" .. hash .. ".png\")")
                return false
            end
        else
            M.alreadySent[objid] = { prevVehName = vehName }
            local serverid = MPVehicleGE.getServerVehicleID(objid)
            if serverid then
                -- We messed up the name on our backend :(
                if vehName == "us_semi" then
                    vehName = "tseries"
                end
                TriggerServerEvent("BP_setLiveryUsed", "" .. serverid .. ";" .. vehName)
                return false
            end
        end
    else
        local tidHash = M.texMap[objid]
        if tidHash then
            local tid = string.sub(tidHash, 1, 3)
            local hash = string.sub(tidHash, 4)
            if tid then
                be:getObjectByID(objid):queueLuaCommand("extensions.BeamPaint.updateLivery(\"" .. hash .. ".png\")")
                return false
            end
        end
    end
    return true
end

local function setLiveryUsed(objid, vehName)
    if M.singlePlayer then
        -- We are in singleplayer!
        print("loading livery from " .. "/vehicles/common/" .. vehName .. ".png")
        if FS:fileExists("/vehicles/common/" .. vehName .. ".png") then
            be:getObjectByID(objid):queueLuaCommand("extensions.BeamPaint.updateLivery(\"" .. vehName .. ".png\", true)")
        end
    else
        -- We are in multiplayer!
        table.insert(M.waitingForSetLivery, { objid = objid, vehName = vehName })
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

local function setPremiumAttempt(data)
    local role = "BP_PREMIUM"
    if data.isAdmin then
        role = "BP_ADMIN"
    end
    if MPVehicleGE.setVehicleRole(data.tid, role, 0) == 0 then
        return true
    end
    return false
end

local function BP_setPremium(json_data)
    local data = jsonDecode(json_data)
    if MPVehicleGE.setPlayerRole then
        local tmp = split(data.tid, "-")
        local pid = tonumber(tmp[1])

        local role = "BeamPaint Premium"
        local roleShort = "BP Premium"
        local roleR, roleG, roleB = 193, 87, 217
        if data.isAdmin then
            role = "BeamPaint Admin"
            roleShort = "BP Admin"
            roleR, roleG, roleB = 235, 64, 52
        end
        print("setPlayerRole:")
        dump(MPVehicleGE.setPlayerRole(pid, role, roleShort, roleR, roleG, roleB))
    else
        table.insert(M.waitingForRole, data)
    end
end

local function BP_informSignup()
    guihooks.trigger(
        "ConfirmationDialogOpen",
        "BeamPaint: You need to register!",
        "Please register at <b>beampaint.com/account</b>!<br>If you have already registered and still encounter this issue, please read the <b>Quickstart</b> guide.",
        "Understood!",
        "extensions.BeamPaint.closeInformSignup()"
    )
end

local function closeInformSignup()
    guihooks.trigger("ConfirmationDialogClose", "BeamPaint: You need to register!")
end

local function init()
    if MPCoreNetwork then
        if MPCoreNetwork.isMPSession() == true then
            M.singlePlayer = false
            AddEventHandler("BP_cacheUpdateComplete", BP_cacheUpdateComplete)
            AddEventHandler("BP_receiveTextureData", BP_receiveTextureData)
            AddEventHandler("BP_markTextureComplete", BP_markTextureComplete)
            AddEventHandler("BP_textureSkip", BP_textureSkip)
            AddEventHandler("BP_setPremium", BP_setPremium)
            AddEventHandler("BP_informSignup", BP_informSignup)
            if not MPVehicleGE.setPlayerRole then
                MPVehicleGE.createRole("BP_ADMIN", "BeamPaint Admin", "BP Admin", 235, 64, 52)
                MPVehicleGE.createRole("BP_PREMIUM", "BeamPaint Premium", "BP Premium", 193, 87, 217)
            end
        end
    end
end

local function onUiChangedState(state)
    M.inVehicleConfigMenu = state == "menu.vehicleconfig.parts"
    M.inVehiclePaintMenu = state == "menu.vehicleconfig.color"
end

local function onUpdate(dt)
    if M.markedReady == false and worldReadyState >= 2 then
        M.markedReady = true
        if not M.singlePlayer then
            BP_reportPlayerCache()
        end
    end
    if #M.waitingForRole > 0 then
        local data = table.remove(M.waitingForRole, 1)
        if setPremiumAttempt(data) then
            table.insert(M.waitingForRole, data)
        end
    end
    if #M.waitingForLivery > 0 then
        applyLiveryAttempt()
    end
    if #M.waitingForSetLivery > 0 then
        local data = table.remove(M.waitingForSetLivery, 1)
        if setLiveryUsedAttempt(data.objid, data.vehName) then
            table.insert(M.waitingForSetLivery, data)
        end
    end
    if M.inVehiclePaintMenu then
        -- Update the current player vehicle paint data
        M.updatePlayerVehiclePaint(be:getPlayerVehicleID(0))
    end
    if M.inVehicleConfigMenu then
        -- Show the "Reload livery" UI
        if im.Begin("BeamPaint", im.BoolPtr(true), im.WindowFlags_AlwaysAutoResize) then
            if im.Button("Reload Livery") then
                reloadLivery()
            end
            if M.singlePlayer then
                im.Separator()
                im.Text("Liveries are loaded from /vehicles/common/<vehName>.png!")
                im.Text("If you want to preview a livery, simply put it in there with the right name and hit \"Reload Livery\".")
                local vehName = be:getPlayerVehicle(0):getField("JBeam", 0)
                im.Text("For the current vehicle: \"/vehicles/common/" .. vehName .. ".png\"")
                if im.Button("Open folder...") then
                    Engine.Platform.exploreFolder("/vehicles/common/")
                end
            else
                -- TODO: Show current livery?
            end
        end
    end
end

local function updatePlayerVehiclePaint(vehID)
    local veh = be:getObjectByID(vehID)
    local r = veh.color.x
    local g = veh.color.y
    local b = veh.color.z
    veh:queueLuaCommand("extensions.BeamPaint.updateCurrentPaint(" .. r .. "," .. g .. "," .. b ..")")
end

M.onExtensionLoaded = init
M.setLiveryUsed = setLiveryUsed
M.reloadLivery = reloadLivery
M.onUiChangedState = onUiChangedState
M.onUpdate = onUpdate
M.closeInformSignup = closeInformSignup
M.updatePlayerVehiclePaint = updatePlayerVehiclePaint

M.BP_informSignup = BP_informSignup

return M
