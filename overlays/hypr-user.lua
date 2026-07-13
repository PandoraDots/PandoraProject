-- PandoraProject overlay — PHN16-72 display, Waywallen autostart, GPU env, apps.

hl.config({
    input = {
        kb_layout  = "br",
        kb_variant = "abnt2",
        kb_options = "",
    },
})

local function load_env_file(path)
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

local cfg = os.getenv("HOME") .. "/.config/caelestia"
load_env_file(cfg .. "/gpu-profile.env")
load_env_file(cfg .. "/shell-qml.env")

hl.monitor({
    output   = "",
    mode     = "2560x1600@240",
    position = "0x0",
    scale    = 1.25,
})

-- Special workspaces: ZapZap (WhatsApp) e Planify (TODO)
hl.window_rule({ match = { class = "zapzap" }, workspace = "special:whatsapp" })
hl.window_rule({
    match     = { class = "io.github.alainm23.planify|planify|Planify" },
    workspace = "special:todo",
})

-- Free Download Manager
hl.window_rule({ match = { class = "fdm" }, float = true, center = true })

-- Workspace 1 — dashboard inferno (grid 2x2 + cmatrix/clock)
-- size inicial importa p/ o cava (bars=32); move final é do script (center global).
local dash = {
    { class = "pandora-info",    size = "(monitor_w*0.5-18) (monitor_h*0.5-18)" },
    { class = "pandora-btop",    size = "(monitor_w*0.5-18) (monitor_h*0.5-18)" },
    { class = "pandora-cava",    size = "(monitor_w*0.5-18) (monitor_h*0.5-18)" },
    { class = "pandora-cmatrix", size = "(monitor_w*0.25-15) (monitor_h*0.5-18)" },
    { class = "pandora-clock",   size = "(monitor_w*0.25-15) (monitor_h*0.5-18)" },
}

for _, tile in ipairs(dash) do
    hl.window_rule({
        match     = { class = tile.class },
        workspace = "1",
        float     = true,
        center    = false,
        size      = tile.size,
    })
end

hl.on("hyprland.start", function()
    -- Uma execução; timer systemd cobre mudanças de perfil (sem path→reload loop)
    hl.exec_cmd("__PANDORA_ROOT__/scripts/gpu-profile.sh")
    hl.exec_cmd("sleep 1 && __PANDORA_ROOT__/scripts/workspace-dashboard.sh")
    -- Autologin: trava com lock Caelestia assim que o shell IPC estiver pronto
    hl.exec_cmd("bash -c 'for i in $(seq 1 40); do caelestia shell lock isLocked >/dev/null 2>&1 && break; sleep 0.25; done; caelestia shell lock lock'")
end)

-- Super+A → ZapZap (special:whatsapp)
hl.bind("SUPER + A", hl.dsp.exec_cmd("__PANDORA_ROOT__/scripts/toggle-whatsapp.sh"))
