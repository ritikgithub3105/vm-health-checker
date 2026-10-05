#!/usr/bin/env bash

set -u

THRESHOLD_CPU=80
THRESHOLD_MEMORY=80
THRESHOLD_DISK=80
THRESHOLD_SWAP=80
THRESHOLD_LOAD=1.5
EXPLAIN_MODE=false

if [[ "${1:-}" == "explain" ]]; then
  EXPLAIN_MODE=true
fi

print_header() {
  echo "========================================"
  echo " VM Health Check"
  echo "========================================"
  echo
}

get_cpu_usage() {
  local cpu_line
  cpu_line=$(grep '^cpu ' /proc/stat)
  read -r _ user nice system idle iowait irq softirq steal _ < <(echo "$cpu_line")

  local total_before=$((user + nice + system + idle + iowait + irq + softirq + steal))
  local idle_before=$idle

  sleep 1

  cpu_line=$(grep '^cpu ' /proc/stat)
  read -r _ user nice system idle iowait irq softirq steal _ < <(echo "$cpu_line")

  local total_after=$((user + nice + system + idle + iowait + irq + softirq + steal))
  local idle_after=$idle

  local total_delta=$((total_after - total_before))
  local idle_delta=$((idle_after - idle_before))

  if (( total_delta > 0 )); then
    echo $((100 - ((idle_delta * 100) / total_delta)))
  else
    echo "0"
  fi
}

get_memory_usage() {
  if [[ -r /proc/meminfo ]]; then
    local mem_total mem_available
    mem_total=$(awk '$1 == "MemTotal:" {print $2}' /proc/meminfo)
    mem_available=$(awk '$1 == "MemAvailable:" {print $2}' /proc/meminfo)

    if [[ -n "$mem_total" && -n "$mem_available" && "$mem_total" -gt 0 ]]; then
      local used=$((mem_total - mem_available))
      echo $(((used * 100) / mem_total))
    else
      echo "0"
    fi
  else
    echo "0"
  fi
}

get_disk_usage() {
  df -P / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%'
}

get_load_average() {
  uptime | sed -E 's/.*load average: //; s/, / /g' | awk '{print $1}'
}

get_uptime() {
  uptime -p 2>/dev/null || uptime
}

get_swap_usage() {
  if [[ -r /proc/meminfo ]]; then
    local swap_total swap_free
    swap_total=$(awk '$1 == "SwapTotal:" {print $2}' /proc/meminfo)
    swap_free=$(awk '$1 == "SwapFree:" {print $2}' /proc/meminfo)

    if [[ -n "$swap_total" && -n "$swap_free" && "$swap_total" -gt 0 ]]; then
      local used=$((swap_total - swap_free))
      echo $(((used * 100) / swap_total))
    else
      echo "0"
    fi
  else
    echo "0"
  fi
}

get_cpu_cores() {
  nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo "unknown"
}

format_status() {
  local value=$1
  local threshold=$2

  if (( value >= threshold )); then
    echo "WARNING"
  else
    echo "OK"
  fi
}

print_health_summary() {
  local cpu mem disk load swap cpu_cores
  cpu=$(get_cpu_usage)
  mem=$(get_memory_usage)
  disk=$(get_disk_usage)
  load=$(get_load_average)
  swap=$(get_swap_usage)
  cpu_cores=$(get_cpu_cores)

  echo "CPU usage: ${cpu}% $(format_status "$cpu" "$THRESHOLD_CPU")"
  echo "Memory usage: ${mem}% $(format_status "$mem" "$THRESHOLD_MEMORY")"
  echo "Disk usage: ${disk}% $(format_status "$disk" "$THRESHOLD_DISK")"
  echo "Load average: ${load} $(if (( $(awk 'BEGIN {print ('"$load"' >= '"$THRESHOLD_LOAD"') ? 1 : 0}') )); then echo "WARNING"; else echo "OK"; fi)"
  echo "Swap usage: ${swap}% $(format_status "$swap" "$THRESHOLD_SWAP")"
  echo "CPU cores: $cpu_cores"
  echo "Uptime: $(get_uptime)"
  echo
}

print_explanation() {
  echo "Detailed explanation:"
  echo
  echo "1. CPU health:"
  echo "   - CPU usage is measured from /proc/stat over a short interval."
  echo "   - Sustained high CPU usage indicates the VM is under heavy processing load."
  echo "   - Alert threshold: ${THRESHOLD_CPU}%"
  echo
  echo "2. Memory health:"
  echo "   - Memory usage is estimated using MemTotal and MemAvailable from /proc/meminfo."
  echo "   - High memory usage can cause increased swap activity and slower performance."
  echo "   - Alert threshold: ${THRESHOLD_MEMORY}%"
  echo
  echo "3. Disk health:"
  echo "   - Disk usage is based on the root filesystem percentage."
  echo "   - High disk usage can affect application writes and lead to instability."
  echo "   - Alert threshold: ${THRESHOLD_DISK}%"
  echo
  echo "4. Load average:"
  echo "   - Load average reflects recent system demand across CPU cores."
  echo "   - A value above ${THRESHOLD_LOAD} is a warning on many small VMs."
  echo "   - It can indicate CPU pressure or busy I/O wait."
  echo
  echo "5. Swap usage:"
  echo "   - Swap is used when RAM is exhausted."
  echo "   - High swap usage suggests memory pressure and possible performance degradation."
  echo "   - Alert threshold: ${THRESHOLD_SWAP}%"
  echo
  echo "6. Overall health status:"
  echo "   - Multiple warning signals often indicate resource pressure."
  echo "   - Investigate if the VM is frequently hitting warning thresholds."
}

main() {
  print_header
  print_health_summary

  if [[ "$EXPLAIN_MODE" == true ]]; then
    print_explanation
  fi
}

main "$@"
