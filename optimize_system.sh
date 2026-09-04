#!/usr/bin/env bash
set -u

SCRIPT_NAME="$(basename "$0")"
LOG_FILE="/tmp/system_optimize.log"

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE" >&2
}

usage() {
  cat <<EOF
Uso: ./$SCRIPT_NAME [--status] [--auto] [--hard-clean] [--kill-vscode]

Opções:
  --status       Exibe diagnóstico do sistema atual
  --auto         Faz uma otimização segura sem matar processos essenciais
  --hard-clean   Limpeza mais agressiva de caches temporários (requer sudo)
  --kill-vscode  Fecha processos pesados do VS Code (uso opcional)
  -h, --help     Mostra esta ajuda

Observações:
  - A otimização segura NÃO mata processos do sistema essenciais.
  - A limpeza pesada pode exigir permissões de administrador.
EOF
}

show_status() {
  echo "========================================"
  echo "Diagnóstico do sistema"
  echo "========================================"
  echo "Data: $(date)"
  echo
  echo "## Carga do sistema"
  cat /proc/loadavg 2>/dev/null || uptime
  echo
  echo "## CPU"
  top -bn1 | head -n 15
  echo
  echo "## Memória"
  free -h
  echo
  echo "## Disco"
  df -h / /home 2>/dev/null || df -h
  echo
  echo "## Processos mais pesados"
  ps -eo pid,comm,%cpu,%mem,rss --sort=-%cpu --no-headers | head -n 10
  echo "========================================"
}

safe_cleanup() {
  log "Iniciando limpeza segura..."

  # Limpa temporários do usuário
  find "${HOME}/.cache" -type f -atime +7 -delete 2>/dev/null || true
  find /tmp -type f -atime +2 -delete 2>/dev/null || true

  # Cache do Python do usuário
  if command -v python3 >/dev/null 2>&1; then
    python3 -m pip cache purge >/dev/null 2>&1 || true
  fi

  # Ajusta prioridade de processos do editor para reduzir carga
  for pid in $(ps -eo pid,comm --no-headers | awk '$2 ~ /code|Code/ {print $1}'); do
    renice +10 "$pid" >/dev/null 2>&1 || true
  done

  log "Limpeza segura concluída."
}

hard_cleanup() {
  if [ "$(id -u)" -ne 0 ]; then
    log "Limpeza agressiva exige sudo. Execute: sudo $0 --hard-clean"
    return 1
  fi

  log "Iniciando limpeza agressiva..."
  apt-get clean >/dev/null 2>&1 || true
  journalctl --vacuum-time=2d >/dev/null 2>&1 || true
  find /var/tmp -type f -atime +2 -delete 2>/dev/null || true
  sync
  echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
  log "Limpeza agressiva concluída."
}

kill_vscode() {
  log "Forçando fechamento de processos do VS Code pesados..."
  for proc in code Code; do
    pkill -f "$proc" 2>/dev/null || true
  done
  log "Processos do VS Code foram encerrados."
}

auto_optimize() {
  log "Executando otimização automática..."
  show_status
  safe_cleanup

  echo
  echo "Resumo:
  - limpeza de cache do usuário
  - redução de prioridade de processos pesados do editor
  - sem encerramento de processos essenciais do sistema"
  echo
  log "Otimização automática concluída."
}

case "${1:-}" in
  --status)
    show_status
    ;;
  --auto)
    auto_optimize
    ;;
  --hard-clean)
    hard_cleanup
    ;;
  --kill-vscode)
    kill_vscode
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    echo "Opção inválida: $1"
    usage
    exit 1
    ;;
 esac
