# Pandora: interactive builds run through pandora-fast (16 jobs, top CPU/I/O priority).
# `command <tool>` bypasses this; PANDORA_FAST=0 disables it for the shell.
if [[ $- == *i* && "${PANDORA_FAST:-1}" != 0 ]] && command -v pandora-fast >/dev/null; then
  for _pandora_tool in cargo make ninja meson cmake makepkg paru yay pnpm npm; do
    eval "$_pandora_tool() { pandora-fast \"\$(type -P $_pandora_tool)\" \"\$@\"; }"
  done
  unset _pandora_tool
fi
