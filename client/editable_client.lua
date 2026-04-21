function DispatchBlip(data)
    local coords = data.coords
    if not coords then return end

    if GetResourceState('interact-sound') == 'started' then
        TriggerEvent('InteractSound_CL:PlayOnAll', 'panicbutton', 0.6)
    end

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, data.blip and data.blip.blipid or 161)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, Config.BlipScale)
    SetBlipColour(blip, data.blip and data.blip.blipcolor or 1)
    SetBlipAsShortRange(blip, false)
    SetBlipFlashes(blip, true)

    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString((data.title or "Dispatch") .. " [#" .. tostring(data.dispatchnumber or "?") .. "]")
    EndTextCommandSetBlipName(blip)

    local radius = AddBlipForRadius(coords.x, coords.y, coords.z, data.blip and data.blip.radius or 70.0)
    SetBlipColour(radius, data.blip and data.blip.blipcolor or 1)
    SetBlipAlpha(radius, 90)

    Wait(Config.RemoveBlipAfter)
    if DoesBlipExist(blip) then RemoveBlip(blip) end
    if DoesBlipExist(radius) then RemoveBlip(radius) end
end
