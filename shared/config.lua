Config = {}

Config.Framework = "auto" -- auto | qbcore | qbox | esx | standalone

Config.EmergencyJobs = {
    { name = "police", displayname = "LSPD" },
    { name = "ambulance", displayname = "LSMD" }
}

Config.MenuCommand = "openDispatchMenu"
Config.MenuKey = "INSERT"

Config.BlipScale = 1.0
Config.RemoveBlipAfter = 180000
Config.BlipFlashInterval = 500
Config.ShotsRequired = 4
Config.ShotsDispatchCooldownMs = 20000
Config.SpeedDispatchCooldownMs = 30000
Config.SpeedThresholdMph = 95
Config.DeathDispatchCooldownMs = 60000
Config.DispatchCooldownMs = 1500

Config.SendDeathToPolice = false

Config.AllowedInventoryResources = {
    "ox_inventory",
    "qb-inventory",
    "qs-inventory",
    "core_inventory",
    "mf-inventory"
}

Config.Notifications = {
    prefer = "auto", -- auto | qb | esx | ox_lib | chat
    title = "Dispatch"
}
