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

-- Workspace 1 — dashboard inferno (grid 2x2 + relógio/cmatrix)
local dash = {
    { class = "pandora-info",   w = 0.50, h = 0.50, x = 0.00, y = 0.00 },
    { class = "pandora-btop",   w = 0.50, h = 0.50, x = 0.50, y = 0.00 },
    { class = "pandora-cava",   w = 0.50, h = 0.50, x = 0.00, y = 0.50 },
    { class = "pandora-cmatrix", w = 0.25, h = 0.50, x = 0.50, y = 0.50 },
    { class = "pandora-clock",  w = 0.25, h = 0.50, x = 0.75, y = 0.50 },
}

for _, tile in ipairs(dash) do
    hl.window_rule({
        match     = { class = tile.class },
        workspace = "1",
        float     = true,
        center    = false,
        size      = ("(monitor_w*%.2f - 24) (monitor_h*%.2f - 24)"):format(tile.w, tile.h),
        move      = ("(monitor_w*%.2f + 12) (monitor_h*%.2f + 12)"):format(tile.x, tile.y),
    })
end

hl.on("hyprland.start", function()
    -- Uma execução; timer systemd cobre mudanças de perfil (sem path→reload loop)
    hl.exec_cmd("__PANDORA_ROOT__/scripts/gpu-profile.sh")
    hl.exec_cmd("sleep 1 && __PANDORA_ROOT__/scripts/workspace-dashboard.sh")
end)

-- Super+A → ZapZap (special:whatsapp)
hl.bind("SUPER + A", hl.dsp.exec_cmd("__PANDORA_ROOT__/scripts/toggle-whatsapp.sh"))
