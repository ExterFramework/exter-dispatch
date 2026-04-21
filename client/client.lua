local activeBlips = {}
local callbackResolvers = {}
local callbackNonce = 0
local framework = nil
local coreObject = nil

local lastShotDispatch = 0
local lastSpeedDispatch = 0
local lastDeathDispatch = 0
local deathReported = false

local function countEntries(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function detectFramework()
    if Config.Framework ~= "auto" then
        return Config.Framework
    end

    if GetResourceState("qbx_core") == "started" then
        return "qbox"
    end

    if GetResourceState("qb-core") == "started" then
        return "qbcore"
    end

    if GetResourceState("es_extended") == "started" then
        return "esx"
    end

    return "standalone"
end

local function initFramework()
    framework = detectFramework()

    if framework == "qbcore" then
        coreObject = exports['qb-core']:GetCoreObject()
    elseif framework == "esx" then
        coreObject = exports['es_extended']:getSharedObject()
    end

    print(("[exter-dispatch] Client framework: %s"):format(framework))
end

local function getPlayerJob()
    if framework == "qbcore" and coreObject then
        local pd = coreObject.Functions.GetPlayerData()
        return pd and pd.job and pd.job.name or "unemployed"
    elseif framework == "esx" and coreObject then
        local pd = coreObject.GetPlayerData()
        return pd and pd.job and pd.job.name or "unemployed"
    end
    return "standalone"
end

local function notify(msg, nType)
    if Config.Notifications.prefer == "ox_lib" or (Config.Notifications.prefer == "auto" and GetResourceState("ox_lib") == "started") then
        lib.notify({ title = Config.Notifications.title, description = msg, type = nType or "inform" })
        return
    end

    if framework == "qbcore" and coreObject then
        coreObject.Functions.Notify(msg, nType or "primary")
        return
    end

    if framework == "esx" then
        TriggerEvent('esx:showNotification', msg)
        return
    end

    TriggerEvent('chat:addMessage', { args = { "DISPATCH", msg } })
end

local function triggerServerCallback(name, payload, cb)
    callbackNonce = callbackNonce + 1
    local requestId = callbackNonce
    callbackResolvers[requestId] = cb
    TriggerServerEvent('exter-dispatch:server:triggerCallback', name, requestId, payload)
end

RegisterNetEvent('exter-dispatch:client:callbackResponse', function(requestId, data)
    if callbackResolvers[requestId] then
        callbackResolvers[requestId](data)
        callbackResolvers[requestId] = nil
    end
end)

local function getStreet(coords)
    local streetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    return GetStreetNameFromHashKey(streetHash)
end

local function getWeaponDescriptor(weapon)
    local label = GetLabelText(GetWeaponDisplayNameFromHash(weapon))
    if not label or label == "NULL" then
        label = "Unknown Weapon"
    end

    local group = GetWeapontypeGroup(weapon)
    local groupMap = {
        [416676503] = "Pistol",
        [-957766203] = "SMG",
        [970310034] = "Assault Rifle",
        [860033945] = "Shotgun",
        [3082541095] = "Sniper",
        [1159398588] = "LMG",
        [2725924767] = "Heavy",
        [1548507267] = "Throwable",
        [3566412244] = "Melee",
    }

    return label, groupMap[group] or ("Group " .. tostring(group))
end

function sendDispatch(data)
    TriggerServerEvent('exter-dispatch:addDispatch', data)
end
exports('sendDispatch', sendDispatch)

RegisterCommand(Config.MenuCommand, function()
    triggerServerCallback('exter-dispatch:getDispatchs', nil, function(dispatchData)
        triggerServerCallback('exter-dispatch:getMyUnit', nil, function(unitData)
            SendNUIMessage({
                action = "openMenu",
                data = dispatchData,
                unit = unitData,
                myjob = getPlayerJob()
            })
            SetNuiFocus(true, true)
        end)
    end)
end)

RegisterKeyMapping(Config.MenuCommand, 'Open Dispatch Menu', 'keyboard', Config.MenuKey)

RegisterNUICallback('getPlayers', function(_, cb)
    triggerServerCallback('exter-dispatch:getJobPlayers', nil, cb)
end)

RegisterNUICallback('getUnits', function(_, cb)
    triggerServerCallback('exter-dispatch:getUnits', nil, cb)
end)

RegisterNUICallback('canAddtoUnit', function(data, cb)
    triggerServerCallback('exter-dispatch:canAddtoUnit', data.id, cb)
end)

RegisterNUICallback('createUnit', function(data, cb)
    triggerServerCallback('exter-dispatch:createUnit', data, cb)
end)

RegisterNUICallback('leaveUnit', function(_, cb)
    triggerServerCallback('exter-dispatch:leaveUnit', nil, cb)
end)

RegisterNUICallback('deleteUnit', function(_, cb)
    triggerServerCallback('exter-dispatch:deleteUnit', nil, cb)
end)

RegisterNUICallback('setLocation', function(data, cb)
    triggerServerCallback('exter-dispatch:getLocation', data.id, function(location)
        if location and location.x and location.y then
            SetNewWaypoint(location.x, location.y)
            cb(true)
            return
        end
        cb(false)
    end)
end)

RegisterNUICallback('closeMenu', function(_, cb)
    SetNuiFocus(false, false)
    cb(true)
end)

RegisterNUICallback('setActive', function(data, cb)
    TriggerServerEvent('exter-dispatch:setActive', data.id)
    ExecuteCommand(Config.MenuCommand)
    cb(true)
end)

RegisterNetEvent('exter-dispatch:client:dispatch', function(data)
    local job = getPlayerJob()
    local canSee = false
    for _, targetJob in pairs(data.jobs or {}) do
        if targetJob == job then
            canSee = true
            break
        end
    end
    if not canSee then return end

    SendNUIMessage({ action = "addispatch", data = data })
    DispatchBlip(data)
end)

CreateThread(function()
    while true do
        Wait(100)
        local ped = PlayerPedId()

        if IsPedShooting(ped) and not IsPedCurrentWeaponSilenced(ped) then
            local now = GetGameTimer()
            if (now - lastShotDispatch) < Config.ShotsDispatchCooldownMs then
                goto continue
            end

            local _, weapon = GetCurrentPedWeapon(ped)
            local coords = GetEntityCoords(ped)
            local street = getStreet(coords)
            local weaponLabel, weaponType = getWeaponDescriptor(weapon)

            sendDispatch({
                title = "Shots Fired",
                code = "10-71",
                values = {
                    { text = street, icon = "fa-solid fa-road" },
                    { text = weaponLabel, icon = "fa-solid fa-gun" },
                    { text = weaponType, icon = "fa-solid fa-layer-group" }
                },
                jobs = {"police"},
                coords = coords,
                blip = { blipid = 110, blipcolor = 1, radius = 120.0 }
            })

            lastShotDispatch = now
        end
        ::continue::
    end
end)

CreateThread(function()
    while true do
        Wait(600)
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            if GetPedInVehicleSeat(vehicle, -1) == ped then
                local mph = math.floor(GetEntitySpeed(vehicle) * 2.236936)
                local now = GetGameTimer()
                if mph >= Config.SpeedThresholdMph and (now - lastSpeedDispatch) > Config.SpeedDispatchCooldownMs then
                    local coords = GetEntityCoords(ped)
                    sendDispatch({
                        title = "High Speed Vehicle",
                        code = "10-11",
                        values = {
                            { text = getStreet(coords), icon = "fa-solid fa-road" },
                            { text = ("%d MPH"):format(mph), icon = "fa-solid fa-gauge-high" }
                        },
                        jobs = {"police"},
                        coords = coords,
                        blip = { blipid = 225, blipcolor = 47, radius = 80.0 }
                    })
                    lastSpeedDispatch = now
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        local isDead = IsEntityDead(ped)

        if isDead and not deathReported and (GetGameTimer() - lastDeathDispatch) > Config.DeathDispatchCooldownMs then
            local coords = GetEntityCoords(ped)
            local jobs = {"ambulance"}
            if Config.SendDeathToPolice then jobs[#jobs + 1] = "police" end

            sendDispatch({
                title = "Person Down",
                code = "10-47",
                values = {
                    { text = getStreet(coords), icon = "fa-solid fa-map-location-dot" },
                    { text = "Medical assistance required", icon = "fa-solid fa-heart-pulse" }
                },
                jobs = jobs,
                coords = coords,
                blip = { blipid = 153, blipcolor = 1, radius = 60.0 }
            })

            deathReported = true
            lastDeathDispatch = GetGameTimer()
        elseif not isDead then
            deathReported = false
        end
    end
end)

if type(DispatchBlip) ~= "function" then
    function DispatchBlip(data)
        if not data.coords then return end

        local main = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
        SetBlipSprite(main, data.blip and data.blip.blipid or 161)
        SetBlipColour(main, data.blip and data.blip.blipcolor or 1)
        SetBlipScale(main, Config.BlipScale)
        SetBlipAsShortRange(main, false)
        SetBlipFlashes(main, true)
        SetBlipFlashInterval(main, Config.BlipFlashInterval)
        SetBlipRoute(main, true)

        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(('%s [#%s]'):format(data.title or "Dispatch", tostring(data.dispatchnumber or "?")))
        EndTextCommandSetBlipName(main)

        local radius = AddBlipForRadius(data.coords.x, data.coords.y, data.coords.z, data.blip and data.blip.radius or 70.0)
        SetBlipColour(radius, data.blip and data.blip.blipcolor or 1)
        SetBlipAlpha(radius, 90)

        activeBlips[data.dispatchnumber or #activeBlips + 1] = { main = main, radius = radius, data = data }

        SendNUIMessage({
            action = "updateMapState",
            map = {
                totalBlips = countEntries(activeBlips),
                last = {
                    title = data.title,
                    x = math.floor(data.coords.x),
                    y = math.floor(data.coords.y)
                }
            }
        })

        SetTimeout(Config.RemoveBlipAfter, function()
            if DoesBlipExist(main) then RemoveBlip(main) end
            if DoesBlipExist(radius) then RemoveBlip(radius) end
            activeBlips[data.dispatchnumber or 0] = nil
        end)
    end
end

initFramework()
