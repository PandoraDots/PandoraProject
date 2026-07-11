# PandoraProject

Dotfiles personalizados baseados no [Caelestia](https://github.com/caelestia-dots/caelestia), com instalação automatizada para CachyOS minimal e suporte ao Acer Predator PHN16-72.

## Instalação rápida (CachyOS minimal)

```bash
git clone https://github.com/PandoraDots/PandoraProject.git ~/PandoraProject
cd ~/PandoraProject
chmod +x install.sh install/*.sh scripts/*.sh
./install.sh
```

Reinicie o sistema após a instalação (SDDM substitui greetd). Na primeira tela de login, escolha a sessão **Hyprland (uwsm-managed)**.

Se os forks `cli`, `caelestia` e `shell` existirem como pastas irmãs do PandoraProject (ex.: `~/dotfile/cli`), o instalador usa essas cópias locais automaticamente em vez de clonar do GitHub.

## O que o script faz

1. Instala pré-requisitos (Hyprland, paru, dependências Caelestia) — em **CachyOS**, prioriza pacotes dos repos otimizados (`cachyos-v3`, `cachyos-extra-v3`, etc.)
2. Configura SDDM com tema [Caelestia locklike](https://github.com/ItsABigIgloo/caelestia-sddm), teclado **br-abnt2** e sessão uwsm + Hyprland
3. Instala drivers NVIDIA/Intel e [nekro-sense](https://github.com/PandoraDots/nekro-sense) para PHN16-72 — no CachyOS usa `linux-cachyos*-nvidia-open` (pré-compilado) em vez de `nvidia-open-dkms`
4. Compila e instala `caelestia` CLI + shell dos forks PandoraDots (sem AUR)
5. Executa `caelestia install` com Spotify/Spicetify, Cursor e Equicord (equibop-bin)
6. Instala apps extras: FDM, ZapZap, Planify, VLC e suporte a compactação no Thunar
7. Instala Waywallen (AppImage) com bridge para o seletor de wallpaper do Caelestia
8. Aplica schema **inferno** (vermelho escuro), wallpaper `glassesredjapan.jpg`, ícone de usuário (`assets/icon.png` → `~/.face`), dashboard na **workspace 1** (fastfetch+Berserk, btop, cava, cmatrix, tty-clock), RGB vermelho e perfil performance
9. Executa **verificação pós-instalação** e salva relatório em texto

## Verificação pós-instalação

Ao final de `./install.sh`, o passo `99-verify` roda [`scripts/verify-install.sh`](scripts/verify-install.sh) e gera um relatório completo:

| Arquivo | Descrição |
|---------|-----------|
| `~/.local/state/pandora/verify-install-latest.log` | Symlink para o último relatório |
| `~/.local/state/pandora/verify-install-YYYYMMDD-HHMMSS.log` | Relatório com timestamp |

O relatório lista cada item como `[OK]`, `[WARN]`, `[FAIL]` ou `[INFO]` — pacotes, comandos, configs, systemd, SDDM, scheme inferno e checks de runtime. Ideal para colar em análise por IA.

Rodar manualmente:

```bash
~/PandoraProject/scripts/verify-install.sh --model phn16-72
```

Manifesto de checks: [`install/verify-manifest.json`](install/verify-manifest.json).

## Atalhos extras

| Atalho | App |
|--------|-----|
| `SUPER+A` | ZapZap (WhatsApp) — special workspace com ícone `chat` |
| `SUPER+R` | Planify (TODO) — special workspace com ícone `task_alt` |
| `SUPER+D` | Equicord (comunicação) |
| `SUPER+C` | Cursor |

## Modelos de hardware

```bash
./install.sh --model phn16-72   # padrão — Predator Helios Neo PHN16-72
```

Perfis em `models/*.json`.

### CachyOS (PHN16-72)

Em sistemas CachyOS, o instalador:

- Sincroniza os repos `cachyos*` antes de instalar
- Usa **paru** (do repo CachyOS) em vez de compilar do AUR quando possível
- Substitui `nvidia-open-dkms` por módulos pré-compilados `linux-cachyos*-nvidia-open` (um por kernel instalado)
- Resolve headers dinamicamente (`linux-cachyos-headers`, `linux-cachyos-lts-headers`, etc.)
- Mantém nomes iguais (`mesa`, `hyprland`, `intel-media-driver`) — o pacman já pega a build otimizada pelos repos CachyOS

Kernels monitorados em `models/phn16-72.json` → `cachyos.kernels`. Ajuste se usar outro flavor (ex.: `linux-cachyos-bore`).

## Atualizações

```bash
git -C ~/PandoraProject pull
~/PandoraProject/scripts/update.sh
```

O script faz merge do upstream `caelestia-dots` nos forks, rebuild cli/shell, `caelestia update` e reaplica overlays.

## Customizações (preservadas no update)

| Arquivo | Função |
|---------|--------|
| `overlays/cli.json` | URL dos dots, theming, bridge Waywallen |
| `overlays/shell.json` | Desabilita wallpaper interno do shell |
| `overlays/hypr-vars.lua` | Cursor como editor (`SUPER+C`) |
| `overlays/hypr-user.lua` | Teclado br-abnt2, monitor 2560×1600@240Hz scale 1.25, dashboard workspace 1, autostart Waywallen |
| `scripts/workspace-dashboard.sh` | Layout automático: fastfetch (logo Berserk), btop, cava, cmatrix, tty-clock |
| `overlays/fastfetch/config.jsonc` | Logo Berserk vermelho + infos do sistema |
| `overlays/cava/config` | Visualizador de áudio em tons vermelhos |
| `scripts/gpu-profile.sh` | Intel em economia, NVIDIA nos demais perfis |

## Forks PandoraDots

- [caelestia](https://github.com/PandoraDots/caelestia) — dots + cursor + equicord
- [cli](https://github.com/PandoraDots/cli) — schema `inferno`
- [shell](https://github.com/PandoraDots/shell) — sem mudanças obrigatórias
- [nekro-sense](https://github.com/PandoraDots/nekro-sense) — driver PHN16-72

## Wallpapers

Pasta `Wallpapers/` — padrão: `glassesredjapan.jpg`. Symlink para `~/Pictures/Wallpapers`.
