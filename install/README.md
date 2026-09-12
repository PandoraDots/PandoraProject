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

### Logs da instalação

Cada execução grava um arquivo exclusivo em `/var/log/pandora/install-DATA-HORA-XXXXXX.log`, mantendo a saída no terminal. O caminho aparece no início e no fim da execução. O log inclui a saída padrão e os erros dos módulos, horários e o código de saída final; em caso de falha, identifica o módulo em execução. Mensagens que os comandos redirecionam para `/dev/null` não são registradas.

Para consultar ou acompanhar um arquivo, use o caminho mostrado pelo instalador:

```bash
sudo less -R /var/log/pandora/install-DATA-HORA-XXXXXX.log
sudo tail -f /var/log/pandora/install-DATA-HORA-XXXXXX.log
```

Para escolher outro diretório: `sudo env PANDORA_LOG_DIR=/caminho/logs ./install/install.sh`. Os arquivos são acessíveis ao proprietário (normalmente root) e permanecem disponíveis após reiniciar.

## O que o módulo Noctalia faz (revisão docs)

1. Instala `noctalia` (extra), `umbriel-git` + portal, `noctalia-greeter`, `greetd`, `accountsservice`
2. Roda `/usr/share/noctalia-greeter/setup_greeter_system.sh` (PAM + state dir)
3. `/etc/greetd/config.toml` → `command = "/usr/bin/noctalia-greeter-session"` (path completo)
4. `greeter.toml` → `[user].default` + `[session].default = "Umbriel"` (`Name=` do `.desktop`)
5. Copia o **example empacotado** do Umbriel (não uma config mínima — isso apagaria keybinds)
6. Garante `autostart = ["noctalia"]` e, se Intel+NVIDIA existirem, `[drm] ignored_pci_addresses` na dGPU
7. Teclado **br / abnt2** no Umbriel + keybinds Fn de brilho; `video`/`input` no usuário
8. Visual estilo Caelestia no Umbriel: blur (size/radius 8, passes 2), opacity 0.95, sombra, rounding 15, gaps 5, beziers e timings Hyprland (`speed`×100 ms). Layers off (Noctalia anima sozinho). Sem scheme vermelho / widgets / shaders custom.
9. Keybinds Pandora: Cursor/Concord/Sung/Firefox (`--new-window`)/ZapZap, terminal com fastfetch, maximize `Mod+Alt+F`, floating `Mod+Alt+R`, scroll→workspace, focus-follows-mouse, overview também em `Mod+MouseBack/Forward`, `Mod+Alt+1..9` move janela. Scratchpads nomeados (= special workspace) abrem maximizados; ZapZap usa `app_id` `com.rtosta.zapzap`.
10. Desabilita outros DMs; habilita `greetd` + `accounts-daemon`
11. Tenta `noctalia-greeter passwordless-sync enable <user>` (greeter ≥ 1.5)

## Módulos

| # | Arquivo | O que faz |
|---|---------|-----------|
| 00 | `preflight` | multilib, zen headers, base, pipewire, mesa |
| 10 | `system-tuning` | pacman Color/ILoveCandy/ParallelDownloads=8, makepkg -j6, zram, fstrim, paccache, IPv4, fonts, bash history-search, teclado **br-abnt2** |
| 20 | `bootloader` | timeout **0** |
| 30 | `gpu-hybrid` | open-dkms, EnvyControl **hybrid**, GameMode (só pacote), OBS NVIDIA wrapper, `acpi_backlight=native` + blacklist `nvidia_wmi_ec_backlight` |
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
- Brilho no híbrido: `acpi_backlight=native` + blacklist do `nvidia_wmi_ec_backlight` (evita sysfs “falso” que não altera o painel na iGPU)

## Teclado

- Console: `KEYMAP=br-abnt2`
- Umbriel / Noctalia: `layout = "br"`, `variant = "abnt2"`
- Greeter: `XKB_DEFAULT_LAYOUT=br` + `XKB_DEFAULT_VARIANT=abnt2`

## Pós-install

1. `reboot`
2. Login no Noctalia Greeter (sessão Umbriel)
3. Em Noctalia: Settings → Security → Sync greeter (wallpaper/palette)
4. GameMode: configure quando quiser

Etapas já instaladas ou configuradas exibem `ok` e são ignoradas. Pacotes são
consultados antes de acessar os repositórios; arquivos gerenciados são comparados
antes da gravação; serviços habilitados e ativos não são reiniciados. Configurações
parciais continuam sendo completadas. A execução não serve para atualizar pacotes.

### Testes de regressão sem instalação

Execute `bash install/tests/package-failures.sh` para verificar, com comandos
simulados, a propagação de falhas do pacman/AUR, pacotes indisponíveis e pacotes
já instalados. Não exige rede nem privilégios de root.

Pacotes oficiais obrigatórios indisponíveis interrompem a etapa antes de instalar
o lote. Falhas de instalação preservam o código de erro para que o chamador
interrompa a execução ou execute o fallback explícito. Pacotes opcionais continuam
sendo tratados pelos respectivos chamadores.

O instalador apenas habilita o greetd durante a configuração. Depois de todos os módulos solicitados terminarem com sucesso e do log ser fechado, pergunta se deseja abrir a tela de login (`s`/`sim`). Enter, outra resposta ou execução sem terminal adiam o login até o próximo boot. A pergunta aparece quando a execução inclui o módulo 50 ou 80.

### Reexecução e recuperação

O módulo 50 repara o `greeter.toml` corrompido por versões anteriores e valida
TOML antes de gravar, mantendo backup. Comentários não contam como seções ou
opções ativas. Com Intel + NVIDIA presentes, garante o endereço PCI da NVIDIA
na lista ativa do Umbriel, preservando os demais endereços. Erros desconhecidos
de TOML interrompem o módulo sem substituir o arquivo por padrões.

Pacotes só são ignorados quando `pacman -Q` e `pacman -Qk` passam (registro e
presença dos arquivos). Para recuperar uma instalação, o script procura arquivos
compilados nos caches do pacman, Paru e no `BUILD_DIR`, conferindo identidade e
leitura do arquivo antes de instalar. Não força recompilação de pacotes saudáveis.
Essa validação não substitui testar o aplicativo em uma sessão gráfica.

Sung exige binário ELF com bibliotecas resolvidas, recursos, entrada de menu e
runtime Python com dependências compatíveis. Se a instalação estiver incompleta,
reutiliza o build CMake válido para reinstalar recursos e reparar o runtime.
Concord também reaproveita seu binário Cargo quando válido. As árvores de build
são preservadas; compilação necessária pode aproveitar os resultados incrementais.
O cache padrão em `/tmp` pode desaparecer ao reiniciar; instalações completas
continuam sendo reaproveitadas sem ele.

Testes adicionais, sem instalar aplicativos:

```bash
python3 install/tests/rerun.py
bash install/tests/build-reuse.sh
```
