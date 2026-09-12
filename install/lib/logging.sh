#!/usr/bin/env bash
# Capture installer and child-process output without changing their exit status.
start_install_log() {
  local log_dir="${PANDORA_LOG_DIR:-/var/log/pandora}"
  mkdir -p -- "$log_dir" || return 1
  INSTALL_LOG="$(mktemp "$log_dir/install-$(date +%Y%m%d-%H%M%S)-XXXXXX.log")" || return 1
  CURRENT_MODULE="inicialização"
  exec {LOG_STDOUT}>&1 {LOG_STDERR}>&2
  exec > >(tee -a -- "$INSTALL_LOG") 2>&1
  LOG_TEE_PID=$!
  trap 'finish_install_log "$?"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  printf 'Início: %s\nLog da instalação: %s\n' "$(date --iso-8601=seconds)" "$INSTALL_LOG"
}

finish_install_log() {
  local status="$1" log_status=0
  trap - EXIT
  printf '\nFim: %s | código de saída: %s | módulo: %s\n' \
    "$(date --iso-8601=seconds)" "$status" "$CURRENT_MODULE"
  printf 'Log da instalação: %s\n' "$INSTALL_LOG"
  # Close the pipe and flush tee before returning to the caller.
  exec 1>&"$LOG_STDOUT" 2>&"$LOG_STDERR"
  exec {LOG_STDOUT}>&- {LOG_STDERR}>&-
  wait "$LOG_TEE_PID" || log_status=$?
  if ((log_status != 0)); then
    printf 'Falha ao gravar o log: %s\n' "$INSTALL_LOG" >&2
    if ((status == 0)); then status=$log_status; fi
  fi
  if [[ "${2:-exit}" == return ]]; then
    return "$status"
  fi
  exit "$status"
}
