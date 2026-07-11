# PandoraProject

Dotfiles personalizados baseados no [Caelestia](https://github.com/caelestia-dots/caelestia), com instalação automatizada para CachyOS minimal e suporte ao Acer Predator PHN16-72.

## Instalação rápida (CachyOS minimal)

```bash
git clone https://github.com/PandoraDots/PandoraProject.git ~/PandoraProject
cd ~/PandoraProject
chmod +x install.sh install/*.sh scripts/*.sh
./install.sh
```

Reinicie a sessão após a instalação.

Se os forks `cli`, `caelestia` e `shell` existirem como pastas irmãs do PandoraProject (ex.: `~/dotfile/cli`), o instalador usa essas cópias locais automaticamente em vez de clonar do GitHub.

## O que o script faz

1. Instala pré-requisitos (Hyprland, paru, dependências Caelestia)
2. Configura sessão greetd + uwsm + Hyprland
3. Instala drivers NVIDIA/Intel e [nekro-sense](https://github.com/PandoraDots/nekro-sense) para PHN16-72
4. Compila e instala `caelestia` CLI + shell dos forks PandoraDots (sem AUR)
5. Executa `caelestia install` com Spotify/Spicetify, Cursor e Equicord (equibop-bin)
6. Instala Waywallen (AppImage) com bridge para o seletor de wallpaper do Caelestia
7. Aplica schema **inferno** (vermelho escuro), wallpaper `glassesredjapan.jpg`, RGB vermelho e perfil performance

## Modelos de hardware

```bash
./install.sh --model phn16-72   # padrão — Predator Helios Neo PHN16-72
```

Perfis em `models/*.json`.

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
| `overlays/hypr-user.lua` | Monitor 2560×1600@240Hz scale 1.25, autostart Waywallen |
| `scripts/gpu-profile.sh` | Intel em economia, NVIDIA nos demais perfis |

## Forks PandoraDots

- [caelestia](https://github.com/PandoraDots/caelestia) — dots + cursor + equicord
- [cli](https://github.com/PandoraDots/cli) — schema `inferno`
- [shell](https://github.com/PandoraDots/shell) — sem mudanças obrigatórias
- [nekro-sense](https://github.com/PandoraDots/nekro-sense) — driver PHN16-72

## Wallpapers

Pasta `Wallpapers/` — padrão: `glassesredjapan.jpg`. Symlink para `~/Pictures/Wallpapers`.
