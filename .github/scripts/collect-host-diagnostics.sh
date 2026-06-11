#!/usr/bin/env bash

set -uo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <output_dir> <file_prefix>" >&2
  exit 1
fi

output_dir="$1"
file_prefix="$2"
error_log="${output_dir}/${file_prefix}_host_diagnostics_errors.log"

mkdir -p "$output_dir"
: > "$error_log"

log_error() {
  echo "$1" | tee -a "$error_log" >&2
}

capture_to_file() {
  local destination="$1"
  shift

  if ! "$@" > "$destination" 2>&1; then
    log_error "Warning: failed to run command for $(basename "$destination")"
  fi
}

capture_shell_to_file() {
  local destination="$1"
  local script="$2"

  if ! bash -lc "$script" > "$destination" 2>&1; then
    log_error "Warning: failed to run shell command for $(basename "$destination")"
  fi
}

capture_to_file "${output_dir}/${file_prefix}_uname.log" uname -a
capture_to_file "${output_dir}/${file_prefix}_os_release.log" cat /etc/os-release
capture_to_file "${output_dir}/${file_prefix}_lscpu.log" lscpu
capture_to_file "${output_dir}/${file_prefix}_nproc.log" nproc
capture_to_file "${output_dir}/${file_prefix}_free.log" free -h
capture_to_file "${output_dir}/${file_prefix}_df.log" df -h
capture_to_file "${output_dir}/${file_prefix}_docker_version.log" docker version
capture_to_file "${output_dir}/${file_prefix}_docker_info.log" docker info
capture_to_file "${output_dir}/${file_prefix}_ip_addr.log" ip addr
capture_to_file "${output_dir}/${file_prefix}_ip_route.log" ip route
capture_to_file "${output_dir}/${file_prefix}_sysctl.log" sysctl \
  net.core.rmem_max \
  net.core.rmem_default \
  net.core.wmem_max \
  net.core.wmem_default \
  net.ipv4.ip_forward \
  net.ipv4.conf.all.rp_filter \
  net.ipv4.conf.default.rp_filter
capture_shell_to_file "${output_dir}/${file_prefix}_cpu_governor.log" \
  "cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null || true"
capture_shell_to_file "${output_dir}/${file_prefix}_drm_kms_poll.log" \
  "cat /sys/module/drm_kms_helper/parameters/poll 2>/dev/null || true"
capture_shell_to_file "${output_dir}/${file_prefix}_iptables.log" "iptables-save || true"
capture_shell_to_file "${output_dir}/${file_prefix}_nft.log" "nft list ruleset || true"
capture_shell_to_file "${output_dir}/${file_prefix}_dmesg_filtered.log" \
  "dmesg | grep -Ei 'illegal instruction|invalid opcode|segfault|oom|killed process|docker|containerd|veth|bridge|netfilter|conntrack' || true"
capture_shell_to_file "${output_dir}/${file_prefix}_journal_docker.log" \
  "journalctl -u docker --no-pager -n 400 || true"
capture_shell_to_file "${output_dir}/${file_prefix}_journal_containerd.log" \
  "journalctl -u containerd --no-pager -n 400 || true"

if [[ ! -s "$error_log" ]]; then
  rm -f "$error_log"
fi
