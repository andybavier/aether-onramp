#!/usr/bin/env bash

set -euo pipefail

log() {
  echo "[ocudu-perf] $*"
}

maybe_sudo() {
  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    "$@"
  fi
}

set_governor() {
  shopt -s nullglob
  local governors=(/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor)
  shopt -u nullglob

  if [[ ${#governors[@]} -eq 0 ]]; then
    log "CPU governor controls are unavailable on this runner"
    return 0
  fi

  log "Setting CPU governor to performance"
  printf 'performance\n' | maybe_sudo tee "${governors[@]}" >/dev/null
}

set_kms_polling() {
  local kms_poll="/sys/module/drm_kms_helper/parameters/poll"

  if [[ ! -e "$kms_poll" ]]; then
    log "DRM KMS polling control is unavailable on this runner"
    return 0
  fi

  log "Disabling DRM KMS polling"
  printf 'N\n' | maybe_sudo tee "$kms_poll" >/dev/null
}

set_network_buffers() {
  log "Setting OCUDU-recommended network buffers"
  maybe_sudo sysctl -w net.core.wmem_max=33554432
  maybe_sudo sysctl -w net.core.rmem_max=33554432
  maybe_sudo sysctl -w net.core.wmem_default=33554432
  maybe_sudo sysctl -w net.core.rmem_default=33554432
}

set_governor
set_kms_polling
set_network_buffers
