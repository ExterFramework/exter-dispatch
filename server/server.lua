local dispatchs = {}
local units = {}
local playershaveunit = {}
local dispatchCooldowns = {}
local callbacks = {}

local MAX_TEXT_LENGTH = 160
local FRAMEWORK = nil
local CoreObject = nil

local function getActiveFramework()
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
    FRAMEWORK = getActiveFramework()
    if FRAMEWORK == "qbcore" then
        CoreObject = exports['qb-core']:GetCoreObject()
    elseif FRAMEWORK == "qbox" then
        CoreObject = exports.qbx_core
    elseif FRAMEWORK == "esx" then
        CoreObject = exports['es_extended']:getSharedObject()
    end
    print(("[exter-dispatch] Framework: %s"):format(FRAMEWORK))
end

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
        return { x = tonumber(coords.x), y = tonumber(coords.y), z = tonumber(coords.z) }
    end

    local ped = GetPlayerPed(source)
    if ped and ped > 0 then
        local pedCoords = GetEntityCoords(ped)
        return { x = pedCoords.x, y = pedCoords.y, z = pedCoords.z }
    end

    return { x = 0.0, y = 0.0, z = 0.0 }
end

local function getPlayerRecord(src)
    if FRAMEWORK == "qbcore" then
        local player = CoreObject.Functions.GetPlayer(src)
        if not player then return nil end
        local pd = player.PlayerData
        return {
            source = src,
            job = pd.job and pd.job.name or "unemployed",
            jobLabel = pd.job and (pd.job.label or pd.job.name) or "Unemployed",
            grade = pd.job and pd.job.grade and (pd.job.grade.name or tostring(pd.job.grade.level or 0)) or "0",
            name = ((pd.charinfo and pd.charinfo.firstname) or "Unknown") .. " " .. ((pd.charinfo and pd.charinfo.lastname) or "Citizen"),
            callsign = (pd.metadata and pd.metadata.callsign) or tostring(src)
        }
    elseif FRAMEWORK == "esx" then
        local xPlayer = CoreObject.GetPlayerFromId(src)
        if not xPlayer then return nil end
        local job = xPlayer.getJob and xPlayer.getJob() or {}
        return {
            source = src,
            job = job.name or "unemployed",
            jobLabel = job.label or job.name or "Unemployed",
            grade = job.grade_label or tostring(job.grade or 0),
            name = xPlayer.getName and xPlayer.getName() or ("Player " .. src),
            callsign = tostring(src)
        }
    end

    return {
        source = src,
        job = "standalone",
        jobLabel = "Standalone",
        grade = "N/A",
        name = GetPlayerName(src) or ("Player " .. src),
        callsign = tostring(src)
    }
end

local function getPlayersByJob(jobName)
    local selected = {}
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local record = getPlayerRecord(src)
        if record and record.job == jobName then
            selected[#selected + 1] = record
        end
    end
    return selected
end

local function sanitizeDispatchData(source, data)
    if type(data) ~= "table" then return nil end

    local allowedJobs = {}
    local safeJobs = {}
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

    if #safeJobs == 0 then return nil end

    local safeValues = {}
    if type(data.values) == "table" then
        for i = 1, math.min(#data.values, 7) do
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
        safeValues = {{ text = "New Dispatch", icon = "fa-solid fa-bell" }}
    end

    return {
        title = trimText(data.title, 80),
        code = trimText(data.code, 24),
        values = safeValues,
        valuestwo = {},
        jobs = safeJobs,
        coords = getSafeCoords(data.coords, source),
        blip = {
            blipid = tonumber(data.blip and data.blip.blipid) or 1,
            blipcolor = tonumber(data.blip and data.blip.blipcolor) or 1,
            radius = tonumber(data.blip and data.blip.radius) or 70.0,
        },
        active = false,
        dispatchnumber = nil,
    }
end

local function pushDispatch(data)
    data.dispatchnumber = #dispatchs + 1
    data.date = os.date("%Y-%m-%d %H:%M:%S")
    dispatchs[#dispatchs + 1] = data
    TriggerClientEvent('exter-dispatch:client:dispatch', -1, data)
end

local function registerCallback(name, fn)
    callbacks[name] = fn
end

RegisterNetEvent('exter-dispatch:server:triggerCallback', function(name, requestId, ...)
    local src = source
    local cb = callbacks[name]
    if not cb then
        TriggerClientEvent('exter-dispatch:client:callbackResponse', src, requestId, nil)
        return
    end

    cb(src, function(result)
        TriggerClientEvent('exter-dispatch:client:callbackResponse', src, requestId, result)
    end, ...)
end)

RegisterNetEvent('exter-dispatch:addDispatch', function(data)
    local src = source
    local now = GetGameTimer()

    if dispatchCooldowns[src] and (now - dispatchCooldowns[src]) < Config.DispatchCooldownMs then
        return
    end

    dispatchCooldowns[src] = now
    local safeData = sanitizeDispatchData(src, data)
    if safeData then
        pushDispatch(safeData)
    end
end)

registerCallback('exter-dispatch:getDispatchs', function(_, cb)
    cb(dispatchs)
end)

registerCallback('exter-dispatch:getJobPlayers', function(_, cb)
    local payload = {}
    for _, job in ipairs(Config.EmergencyJobs) do
        payload[#payload + 1] = {
            name = job.name,
            displayname = job.displayname,
            officers = getPlayersByJob(job.name)
        }
    end
    cb(payload)
end)

local function createUnit(source, players, teamname, callsign)
    local leader = getPlayerRecord(source)
    if not leader then return false end

    local officers = {}
    local groupid = #units + 1

    for _, v in pairs(players or {}) do
        local playerId = tonumber(v)
        local record = playerId and getPlayerRecord(playerId) or nil
        if record and record.job == leader.job then
            officers[#officers + 1] = {
                callsign = record.callsign,
                name = record.name,
                source = record.source,
                unithead = false
            }
            playershaveunit[record.source] = groupid
        end
    end

    officers[#officers + 1] = {
        callsign = leader.callsign,
        name = leader.name,
        source = leader.source,
        unithead = true
    }
    playershaveunit[source] = groupid

    units[groupid] = {
        active = true,
        unithead = source,
        officer = officers,
        name = trimText(teamname or "Unit", 32),
        callname = trimText(callsign or "10-8", 32),
        job = leader.job
    }

    return true
end

local function leaveUnit(source)
    local unitid = playershaveunit[source]
    if unitid and units[unitid] then
        for k, officer in ipairs(units[unitid].officer) do
            if officer.source == source then
                table.remove(units[unitid].officer, k)
                playershaveunit[source] = nil
                break
            end
        end
    end
    return true
end

local function deleteUnit(source)
    local unitid = playershaveunit[source]
    if unitid and units[unitid] then
        if units[unitid].unithead ~= source then return false end

        for _, officer in pairs(units[unitid].officer) do
            playershaveunit[officer.source] = nil
        end

        units[unitid] = nil
    end

    return true
end

registerCallback('exter-dispatch:getUnits', function(_, cb)
    local payload = {}
    for _, job in ipairs(Config.EmergencyJobs) do
        local jobUnits = {}
        for _, unit in pairs(units) do
            if unit.job == job.name then
                jobUnits[#jobUnits + 1] = unit
            end
        end

        payload[#payload + 1] = {
            name = job.name,
            displayname = job.displayname,
            jobunits = jobUnits
        }
    end

    cb(payload)
end)

registerCallback('exter-dispatch:getMyUnit', function(source, cb)
    local myunit = playershaveunit[source]
    if myunit and units[myunit] then
        cb({ unitid = myunit, unithead = units[myunit].unithead == source, hasaunit = true })
        return
    end
    cb(false)
end)

registerCallback('exter-dispatch:canAddtoUnit', function(source, cb, id)
    local me = getPlayerRecord(source)
    local target = getPlayerRecord(tonumber(id))

    if not me or not target then
        cb(false)
        return
    end

    if playershaveunit[target.source] then
        cb(false)
        return
    end

    cb(target.job == me.job)
end)

registerCallback('exter-dispatch:createUnit', function(source, cb, data)
    cb(createUnit(source, data and data.personlist, data and data.name, data and data.callcode))
end)

registerCallback('exter-dispatch:leaveUnit', function(source, cb)
    cb(leaveUnit(source))
end)

registerCallback('exter-dispatch:deleteUnit', function(source, cb)
    cb(deleteUnit(source))
end)

registerCallback('exter-dispatch:getLocation', function(_, cb, id)
    local dispatchId = tonumber(id)
    cb(dispatchId and dispatchs[dispatchId] and dispatchs[dispatchId].coords or nil)
end)

RegisterNetEvent('exter-dispatch:setActive', function(id)
    local src = source
    local dispatchId = tonumber(id)
    local myunit = playershaveunit[src]

    if not dispatchId or not dispatchs[dispatchId] then return end
    if not myunit or not units[myunit] then return end

    dispatchs[dispatchId].active = true
    dispatchs[dispatchId].valuestwo = {{
        text = units[myunit].callname,
        icon = "fa-solid fa-walkie-talkie"
    }}
end)

AddEventHandler('playerDropped', function()
    local src = source
    if playershaveunit[src] then
        if units[playershaveunit[src]] and units[playershaveunit[src]].unithead == src then
            deleteUnit(src)
        else
            leaveUnit(src)
        end
    end
end)

initFramework()
