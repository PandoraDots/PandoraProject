-- PandoraProject overlay — PHN16-72 display, Waywallen autostart, GPU env.

local function load_gpu_env()
    local path = os.getenv("HOME") .. "/.config/caelestia/gpu-profile.env"
    local f = io.open(path, "r")
    if not f then return end
    for line in f:lines() do
        local key, val = line:match("^export ([%w_]+)=(.+)$")
        if key and val then
            val = val:gsub('^"', ""):gsub('"$', "")
            hl.env(key, val)
        end
    end
    f:close()
end

load_gpu_env()

hl.monitor({
    output   = "",
    mode     = "2560x1600@240",
    position = "0,0",
    scale    = 1.25,
})

hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start waywallen.service")
    hl.exec_cmd("systemctl --user start pandora-gpu-profile.path")
    hl.exec_cmd("__PANDORA_ROOT__/scripts/gpu-profile.sh")
end)
