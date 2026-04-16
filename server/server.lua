local QBCore = exports['qb-core']:GetCoreObject()
local dispatchs = {}

local units = {}
local playershaveunit = {}
local dispatchCooldowns = {}

local MAX_TEXT_LENGTH = 160
local DISPATCH_COOLDOWN_MS = 1500

local function trimText(value, maxLen)
    if type(value) ~= "string" then
        return ""
    end

    local cleaned = value:gsub("[%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #cleaned > maxLen then
        return cleaned:sub(1, maxLen)
    end

    return cleaned
end

local function getSafeCoords(coords, source)
    if type(coords) == "vector3" then
        return { x = coords.x, y = coords.y, z = coords.z }
    end

    if type(coords) == "table" and tonumber(coords.x) and tonumber(coords.y) and tonumber(coords.z) then
        return {
            x = tonumber(coords.x),
            y = tonumber(coords.y),
            z = tonumber(coords.z),
        }
    end

    local ped = GetPlayerPed(source)
    if ped and ped > 0 then
        local pedCoords = GetEntityCoords(ped)
        return { x = pedCoords.x, y = pedCoords.y, z = pedCoords.z }
    end

    return { x = 0.0, y = 0.0, z = 0.0 }
end

local function sanitizeDispatchData(source, data)
    if type(data) ~= "table" then
        return nil
    end

    local safeJobs = {}
    local allowedJobs = {}
    for _, jobConfig in ipairs(Config.EmergencyJobs or {}) do
        allowedJobs[jobConfig.name] = true
    end

    if type(data.jobs) == "table" then
        for _, jobName in ipairs(data.jobs) do
            if type(jobName) == "string" and allowedJobs[jobName] then
                safeJobs[#safeJobs + 1] = jobName
            end
        end
    end

    if #safeJobs == 0 then
        return nil
    end

    local safeValues = {}
    if type(data.values) == "table" then
        for i = 1, math.min(#data.values, 6) do
            local item = data.values[i]
            if type(item) == "table" then
                safeValues[#safeValues + 1] = {
                    text = trimText(item.text, MAX_TEXT_LENGTH),
                    icon = trimText(item.icon, 64),
                }
            end
        end
    end

    if #safeValues == 0 then
        safeValues = {
            {
                text = "New Dispatch",
                icon = "fa-solid fa-bell",
            }
        }
    end

    local safeBlip = {
        blipid = tonumber(data.blip and data.blip.blipid) or 1,
        blipcolor = tonumber(data.blip and data.blip.blipcolor) or 1
    }

    return {
        title = trimText(data.title, 80),
        code = trimText(data.code, 24),
        values = safeValues,
        valuestwo = {},
        jobs = safeJobs,
        coords = getSafeCoords(data.coords, source),
        blip = safeBlip,
        active = false,
        dispatchnumber = nil
    }
end

local function pushDispatch(data)
    data.dispatchnumber = #dispatchs + 1
    data.date = os.date("%Y-%m-%d %H:%M:%S")
    dispatchs[#dispatchs + 1] = data
    TriggerClientEvent('exter-dispatch:client:dispatch', -1, data)
end

RegisterServerEvent('exter-dispatch:addDispatch')
AddEventHandler('exter-dispatch:addDispatch', function(data)
    local src = source
    local now = GetGameTimer()

    if dispatchCooldowns[src] and (now - dispatchCooldowns[src]) < DISPATCH_COOLDOWN_MS then
        return
    end

    dispatchCooldowns[src] = now
    local safeData = sanitizeDispatchData(src, data)
    if not safeData then
        return
    end

    pushDispatch(safeData)
end)

QBCore.Functions.CreateCallback('exter-dispatch:getDispatchs', function(source, cb)
    cb(dispatchs)
end)

function getActiveJobPlayers(jobname)
    local players = QBCore.Functions.GetQBPlayers()
    local selectedplayers = {}
    for k, v in pairs(players) do
        local pdata = v.PlayerData
        if pdata.job.name == jobname then
            local selectedData = {
                source = pdata.source,
                name = pdata.charinfo.firstname .. " " .. pdata.charinfo.lastname,
                callsign = pdata.metadata.callsign,
                job = pdata.job
            }
            selectedplayers[#selectedplayers + 1] = selectedData
        end
    end
    return selectedplayers
end

QBCore.Functions.CreateCallback('exter-dispatch:getJobPlayers', function(source, cb)
    local totaljobplayers = {}
    for k, v in pairs(Config.EmergencyJobs) do
        local activepl = getActiveJobPlayers(v.name)
        totaljobplayers[#totaljobplayers + 1] = {
            name = v.name,
            displayname = v.displayname,
            officers = activepl
        }
    end
    cb(totaljobplayers)
end)

function createUnit(source, players, teamname, callsign)
    local officers = {}
    local groupid = #units + 1
    local self = QBCore.Functions.GetPlayer(source)
    for k, v in pairs(players) do
        local player = QBCore.Functions.GetPlayer(tonumber(v))
        if player then
            if player.PlayerData.job.name == self.PlayerData.job.name then
                officers[#officers + 1] = {
                    callsign = player.PlayerData.metadata.callsign,
                    name = player.PlayerData.charinfo.firstname .. " " .. player.PlayerData.charinfo.lastname,
                    source = player.PlayerData.source,
                    unithead = false
                }
                playershaveunit[player.PlayerData.source] = groupid
            end
        end
    end
    officers[#officers + 1] = {
        callsign = self.PlayerData.metadata.callsign,
        name = self.PlayerData.charinfo.firstname .. " " .. self.PlayerData.charinfo.lastname,
        source = self.PlayerData.source,
        unithead = true
    }
    playershaveunit[source] = groupid

    local unit = {
        active = true,
        unithead = source,
        officer = officers,
        name = teamname,
        callname = callsign,
        job = self.PlayerData.job.name
    }

    units[groupid] = unit
    return true
end

function leaveUnit(source)
    local unitid = playershaveunit[source]
    if unitid and units[unitid] then
        for k, v in pairs(units[unitid].officer) do
            if v.source == source then
                table.remove(units[unitid].officer, k)
                playershaveunit[source] = nil
                break
            end
        end
    end
    return true
end

function deleteUnit(source)
    local unitid = playershaveunit[source]
    if unitid and units[unitid] then
        if units[unitid].unithead == source then
            for k, v in pairs(units[unitid].officer) do
                playershaveunit[v.source] = nil
            end
        else
            return false
        end
        table.remove(units, unitid)
    end
    return true
end

QBCore.Functions.CreateCallback('exter-dispatch:getUnits', function(source, cb)
    local totaljobplayers = {}
    for k, v in pairs(Config.EmergencyJobs) do
        local jobunitsx = {}
        for c, x in pairs(units) do
            if x.job == v.name then
                jobunitsx[#jobunitsx + 1] = units[c]
            end
        end

        totaljobplayers[#totaljobplayers + 1] = {
            name = v.name,
            displayname = v.displayname,
            jobunits = jobunitsx
        }
    end
    cb(totaljobplayers)
end)

QBCore.Functions.CreateCallback('exter-dispatch:getMyUnit', function(source, cb)
    local myunit = playershaveunit[source]
    if myunit then
        local iamowner = false
        if units[myunit].unithead == source then
            iamowner = true
        end

        cb({
            unitid = myunit,
            unithead = iamowner,
            hasaunit = true
        })
    else
        cb(false)
    end
end)

QBCore.Functions.CreateCallback('exter-dispatch:canAddtoUnit', function(source, cb, id)
    local player = QBCore.Functions.GetPlayer(id)
    local me = QBCore.Functions.GetPlayer(source)
    if player then
        local unit = playershaveunit[id]
        if unit then
            cb(false)
        else
            if player.PlayerData.job.name == me.PlayerData.job.name then
                cb(true)
            else
                cb(false)
            end
        end
    else
        cb(false)
    end
end)

QBCore.Functions.CreateCallback('exter-dispatch:createUnit', function(source, cb, data)
    cb(createUnit(source, data.personlist, data.name, data.callcode))
end)

QBCore.Functions.CreateCallback('exter-dispatch:leaveUnit', function(source, cb)
    cb(leaveUnit(source))
end)

QBCore.Functions.CreateCallback('exter-dispatch:deleteUnit', function(source, cb)
    cb(deleteUnit(source))
end)

AddEventHandler('playerDropped', function(reason)
    local myunit = playershaveunit[source]
    if myunit then
        if units[myunit].unithead == source then
            deleteUnit(source)
        else
            leaveUnit(source)
        end
    end
end)

RegisterServerEvent('exter-dispatch:setActive', function(id)
    local src = source
    local myunit = playershaveunit[source]
    local dispatchId = tonumber(id)
    if not dispatchId or not dispatchs[dispatchId] then
        return
    end
    if myunit and units[myunit] then
        local unitcallcode = units[myunit].callname
        dispatchs[dispatchId].active = true
        dispatchs[dispatchId].valuestwo = {{
            text = unitcallcode,
            icon = "fa-solid fa-walkie-talkie"
        }}
    else
        TriggerClientEvent('QBCore:Notify', src, 'You dont have a unit. You cant active the dispatch.')
    end
end)

QBCore.Functions.CreateCallback('exter-dispatch:getLocation', function(source, cb, id)
    local dispatchId = tonumber(id)
    if dispatchId and dispatchs[dispatchId] and dispatchs[dispatchId].coords then
        cb(dispatchs[dispatchId].coords)
        return
    end
    cb(nil)
end)

RegisterServerEvent("exter-dispatch:getJobById")
AddEventHandler("exter-dispatch:getJobById", function(targetId)
    local src = source
    local target = QBCore.Functions.GetPlayer(targetId)

    if target then
        local coords = GetEntityCoords(GetPlayerPed(src))
        TriggerClientEvent("exter-dispatch:jobResult", src, target.PlayerData.job.name, coords)
    end
end)

RegisterServerEvent('exter-dispatch:checkPoliceShoot')
AddEventHandler('exter-dispatch:checkPoliceShoot', function(targetId)
    local shooter = source
    local target = QBCore.Functions.GetPlayer(targetId)

    if target and target.PlayerData.job.name == "police" then
        pushDispatch({
            title = "Officer Under Fire",
            code = "10-99",
            values = {{
                text = "Officer Under Fire",
                icon = "fa-solid fa-gun"
            }, {
                text = os.date("%H:%M:%S"),
                icon = "fa-solid fa-clock"
            }},
            valuestwo = {},
            jobs = {"police"},
            coords = getSafeCoords(GetEntityCoords(GetPlayerPed(shooter)), shooter),
            blip = {
                blipid = 161,
                blipcolor = 1
            },
            active = false,
            dispatchnumber = nil
        })
    end
end)
