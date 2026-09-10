# Pandora Noctalia — Arch post-install

Scripts para configurar um Arch **puro** (via `archinstall`) com:

- **Umbriel** (compositor) + **Noctalia Shell v5** + **noctalia-greeter** (`greetd`)
- **linux-zen** + **nvidia-open-dkms** (híbrido via EnvyControl)
- PerfectSense, apps, toolchains e tunings de sistema

## Antes (archinstall)

Escolha / confirme:

| Item | Valor recomendado |
|------|-------------------|
| Kernel | `linux-zen` (+ headers) |
| NVIDIA | `nvidia-open-dkms` |
| Bootloader | **systemd-boot** (mais simples / boot rápido) |
| Secure Boot | desligado |
| Usuário | um usuário no grupo `wheel` (sudo) |
| Desktop | nenhum (o script instala Umbriel+Noctalia) |

Timezone, locale e hostname: deixe como quiser — **o script não mexe**.

## Uso

```bash
# clone deste repo (branch noctalia) após o primeiro boot
sudo pacman -S --needed git
git clone -b noctalia https://github.com/PandoraDots/PandoraProject.git
cd PandoraProject
chmod +x install/install.sh install/validate.sh install/modules/*.sh

# opcional: validar pacotes/sintaxe
./install/validate.sh

# instalação completa
sudo ./install/install.sh
```

Módulo único:

```bash
sudo ./install/install.sh 30-gpu-hybrid
# ou
sudo ./install/install.sh 50-noctalia-stack
```

## Módulos

| # | Arquivo | O que faz |
|---|---------|-----------|
| 00 | `preflight` | multilib, zen headers, base, pipewire, mesa |
| 10 | `system-tuning` | pacman Color/ILoveCandy/ParallelDownloads=8, makepkg -j6, zram, fstrim, paccache, IPv4, fonts, bash history-search |
| 20 | `bootloader` | timeout **0** (systemd-boot ideal; se GRUB, só zera timeout) |
| 30 | `gpu-hybrid` | open-dkms stack, EnvyControl **hybrid**, GameMode (só pacote), OBS NVIDIA wrapper, MangoHud/GOverlay |
| 40 | `perfectsense` | clone + makepkg do PerfectSense |
| 50 | `noctalia-stack` | noctalia + umbriel-git + greeter + greetd |
| 60 | `dev` | vim, node, .NET 8+10, Rider, C/C++, Rust, Cursor |
| 70 | `apps` | codecs, VLC, Dolphin, Steam, Heroic, Stremio, Concord, Sung, Hydra, ZapZap, LabyMod, Proton VPN, Blockbench |
| 80 | `finalize` | PATH local, lembretes |

**Fora de escopo (de propósito):** Ananicy-Cpp, `nvidia-persistenced`, config profunda do GameMode, hostname/locale/tz.

## GPU

- Desktop/WM na **iGPU**
- Jogos / OBS / apps pesados: `prime-run <app>` ou `obs-nvidia`
- EnvyControl default: **hybrid**

## Notas

- Sung instala em `~/.local` (build do GitHub).
- Rider/Hydra/Cursor vêm do AUR (ou AppImage no fallback do Hydra).
- Após DKMS/EnvyControl: **reboot**.
