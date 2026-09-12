#!/usr/bin/env bash
# Called only after all requested modules succeed and the log is flushed.
offer_login() {
  local answer
  if [[ ! -t 0 ]]; then
    printf 'Sem terminal interativo; login disponível no próximo boot.\n'
    return 0
  fi
  printf 'Deseja ir para a tela de login agora? Salve seu trabalho antes de continuar. [s/N] '
  if ! IFS= read -r answer; then
    printf '\nLogin adiado.\n'
    return 0
  fi
  case "$answer" in
    s|S|sim|Sim|SIM)
      systemctl restart greetd.service
      ;;
    *) printf 'Login adiado; disponível no próximo boot.\n' ;;
  esac
}
