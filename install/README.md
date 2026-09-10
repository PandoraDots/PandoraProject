# Pandora Noctalia — Arch post-install

Scripts para configurar um Arch **puro** (via `archinstall`) com:

- **Umbriel** (compositor) + **Noctalia Shell v5** + **noctalia-greeter** (`greetd`)
- **linux-zen** + **nvidia-open-dkms** (híbrido via EnvyControl)
- PerfectSense, apps, toolchains e tunings de sistema

Documentação seguida:

- [Noctalia install](https://docs.noctalia.dev/noctalia/getting-started/installation/) → `pacman -S noctalia`
- [Running Noctalia](https://docs.noctalia.dev/noctalia/getting-started/running-the-shell/) → autostart no compositor
- [Umbriel + Noctalia](https://docs.noctalia.dev/noctalia/compositor-settings/umbriel/) → `autostart`, rules, keybinds
- [Umbriel install](https://docs.noctalia.dev/umbriel/installation/) → `umbriel-git` (AUR), sessão `start-umbriel`
- [Greeter install](https://docs.noctalia.dev/greeter/installation/) → `noctalia-greeter-session` no greetd
- [Greeter config](https://docs.noctalia.dev/greeter/configuration/) → `/var/lib/noctalia-greeter/greeter.toml`
- [Sync](https://docs.noctalia.dev/greeter/sync/) → opcional `passwordless-sync`

## Antes (archinstall)

| Item | Valor recomendado |
|------|-------------------|
| Kernel | `linux-zen` (+ headers) |
| NVIDIA | `nvidia-open-dkms` |
| Bootloader | **systemd-boot** (ou GRUB — o script só zera timeout) |
| Secure Boot | desligado |
| BIOS GPU | **Hybrid** (iGPU ligada) |
| Usuário | um usuário no grupo `wheel` (sudo) |
| Desktop | nenhum (o script instala Umbriel+Noctalia) |

Timezone, locale e hostname: **o script não mexe**.

## Uso

```bash
sudo pacman -S --needed git
git clone -b noctalia https://github.com/PandoraDots/PandoraProject.git
cd PandoraProject
chmod +x install/install.sh install/validate.sh install/modules/*.sh

./install/validate.sh          # sintaxe + pacotes
sudo ./install/install.sh      # instalação completa
```

Módulo único: `sudo ./install/install.sh 50-noctalia-stack`

## O que o módulo Noctalia faz (revisão docs)

1. Instala `noctalia` (extra), `umbriel-git` + portal, `noctalia-greeter`, `greetd`, `accountsservice`
2. Roda `/usr/share/noctalia-greeter/setup_greeter_system.sh` (PAM + state dir)
3. `/etc/greetd/config.toml` → `command = "/usr/bin/noctalia-greeter-session"` (path completo)
4. `greeter.toml` → `[user].default` + `[session].default = "Umbriel"` (`Name=` do `.desktop`)
5. Copia o **example empacotado** do Umbriel (não uma config mínima — isso apagaria keybinds)
6. Garante `autostart = ["noctalia"]` e, se Intel+NVIDIA existirem, `[drm] ignored_pci_addresses` na dGPU
7. Desabilita outros DMs; habilita `greetd` + `accounts-daemon`
8. Tenta `noctalia-greeter passwordless-sync enable <user>` (greeter ≥ 1.5)

## Módulos

| # | Arquivo | O que faz |
|---|---------|-----------|
| 00 | `preflight` | multilib, zen headers, base, pipewire, mesa |
| 10 | `system-tuning` | pacman Color/ILoveCandy/ParallelDownloads=8, makepkg -j6, zram, fstrim, paccache, IPv4, fonts, bash history-search |
| 20 | `bootloader` | timeout **0** |
| 30 | `gpu-hybrid` | open-dkms, EnvyControl **hybrid**, GameMode (só pacote), OBS NVIDIA wrapper |
| 40 | `perfectsense` | clone + makepkg |
| 50 | `noctalia-stack` | stack acima |
| 60 | `dev` | vim, node, .NET 8+10, Rider, C/C++, Rust, Cursor |
| 70 | `apps` | codecs, VLC, Dolphin, Steam, Heroic, Stremio, Concord, Sung, Hydra, … |
| 80 | `finalize` | PATH local, lembretes |

**Fora:** Ananicy-Cpp, `nvidia-persistenced`, config profunda do GameMode, hostname/locale/tz.

## GPU

- Desktop/WM na **iGPU** (Umbriel ignora PCI NVIDIA quando a Intel está visível)
- Jogos / OBS / Concord stream: `prime-run` / `obs-nvidia` / `concord-nvidia`
- EnvyControl: **hybrid**

## Pós-install

1. `reboot`
2. Login no Noctalia Greeter (sessão Umbriel)
3. Em Noctalia: Settings → Security → Sync greeter (wallpaper/palette)
4. GameMode: configure quando quiser
