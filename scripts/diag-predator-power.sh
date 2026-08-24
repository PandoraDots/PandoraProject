#!/usr/bin/env bash
# Diagnóstico i7-14700HX / PredatorSense — somente leitura + profile/governor (sem wrmsr).
set -euo pipefail

OUT_DIR="${1:-/tmp/pandora-power-diag}"
mkdir -p "$OUT_DIR"
LOG="$OUT_DIR/report.txt"
: >"$LOG"

log() { echo "$*" | tee -a "$LOG"; }

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Precisa de root (sudo/pkexec)." >&2
    exit 1
  fi
}

need_root

# Governor/EPP performance em todas as CPUs online
for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  echo performance >"$g" 2>/dev/null || true
done
for e in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
  [[ -f "$e" ]] && echo performance >"$e" 2>/dev/null || true
done

log "=== $(date -Iseconds) ==="
log "kernel: $(uname -r)"
log "nproc: $(nproc)"
log "online: $(cat /sys/devices/system/cpu/online)"
log "AC online: $(cat /sys/class/power_supply/ACAD/online 2>/dev/null || echo '?')"
log "pstate: $(cat /sys/devices/system/cpu/intel_pstate/status) no_turbo=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo)"
log "gov0: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
log "epp0: $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo n/a)"
log "RAPL PL1_uw=$(cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw)"
log "RAPL PL2_uw=$(cat /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw)"
log "RAPL peak_uw=$(cat /sys/class/powercap/intel-rapl:0/constraint_2_power_limit_uw)"
log "RAPL c0_max_uw=$(cat /sys/class/powercap/intel-rapl:0/constraint_0_max_power_uw)"
log "mods: $(lsmod | awk '/nekro_sense|acer_wmi|acer_wireless/{print $1}' | tr '\n' ' ')"
log "cycle_gaming: $(cat /sys/module/nekro_sense/parameters/cycle_gaming_thermal_profile 2>/dev/null || echo n/a)"
log "profiles: $(cat /sys/firmware/acpi/platform_profile_choices)"

# throttle counters helper
throttle_snap() {
  local pkg_c=0 pkg_t=0 core_c=0 core_t=0
  local f
  for f in /sys/devices/system/cpu/cpu*/thermal_throttle/package_throttle_count; do
    pkg_c=$((pkg_c + $(cat "$f")))
  done
  for f in /sys/devices/system/cpu/cpu*/thermal_throttle/package_throttle_total_time_ms; do
    pkg_t=$((pkg_t + $(cat "$f")))
  done
  for f in /sys/devices/system/cpu/cpu*/thermal_throttle/core_throttle_count; do
    core_c=$((core_c + $(cat "$f")))
  done
  for f in /sys/devices/system/cpu/cpu*/thermal_throttle/core_throttle_total_time_ms; do
    core_t=$((core_t + $(cat "$f")))
  done
  echo "$pkg_c $pkg_t $core_c $core_t"
}

# MSR read (optional)
msr_snap() {
  if command -v rdmsr >/dev/null && [[ -c /dev/cpu/0/msr ]]; then
    modprobe msr 2>/dev/null || true
    echo "0x64f=$(rdmsr -p 0 0x64f 2>/dev/null || echo err) 0x1a2=$(rdmsr -p 0 0x1a2 2>/dev/null || echo err) 0x1b1=$(rdmsr -p 0 0x1b1 2>/dev/null || echo err) 0x19c=$(rdmsr -p 0 0x19c 2>/dev/null || echo err)"
  else
    echo "msr=unavailable"
  fi
}

run_profile() {
  local profile="$1"
  local dur="${2:-30}"
  local ncpu
  ncpu="$(nproc)"
  local out="$OUT_DIR/turbostat-${profile}.txt"
  local thr_before thr_after

  log ""
  log "===== PROFILE: $profile (${dur}s, stress-ng --cpu $ncpu) ====="
  echo "$profile" >/sys/firmware/acpi/platform_profile
  sleep 0.5
  local got
  got="$(cat /sys/firmware/acpi/platform_profile)"
  log "platform_profile now: $got"
  if [[ "$got" != "$profile" ]]; then
    log "WARN: requested $profile but got $got (skipping)"
    return 0
  fi

  log "msr idle: $(msr_snap)"
  thr_before="$(throttle_snap)"
  log "throttle_before: pkg_c,pkg_t_ms,core_c,core_t_ms = $thr_before"

  # turbostat in background summarizing every 1s; stress for dur seconds
  stress-ng --cpu "$ncpu" --timeout "${dur}s" >/dev/null 2>&1 &
  local spid=$!
  sleep 1
  log "msr load: $(msr_snap)"

  # Collect turbostat for remaining window
  timeout "$((dur))" turbostat --Summary --quiet --interval 1 \
    --show Busy%,Bzy_MHz,PkgWatt,CorWatt,PkgTmp,CoreTmp \
    >"$out" 2>&1 || true

  wait "$spid" 2>/dev/null || true
  thr_after="$(throttle_snap)"
  log "throttle_after: $thr_after"

  # Parse averages from last N lines (skip header)
  python3 - "$out" "$thr_before" "$thr_after" <<'PY' | tee -a "$LOG"
import sys, statistics as st
path, before, after = sys.argv[1], sys.argv[2], sys.argv[3]
rows=[]
with open(path) as f:
    for line in f:
        parts=line.split()
        if len(parts)>=6 and parts[0].replace('.','',1).isdigit():
            # Busy Bzy_MHz PkgWatt CorWatt PkgTmp CoreTmp  (order may vary - turbostat header)
            try:
                float(parts[0]); float(parts[1]); float(parts[2])
            except: continue
            rows.append([float(x) for x in parts[:6]])
# Read header for column names
header=None
with open(path) as f:
    for line in f:
        if 'PkgWatt' in line or 'Bzy_MHz' in line:
            header=line.split(); break
if not rows:
    print('NO_SAMPLES', path); raise SystemExit
# Assume turbostat order from --show: Busy%,Bzy_MHz,PkgWatt,CorWatt,PkgTmp,CoreTmp
# Drop first 3 samples (ramp)
stable=rows[3:] if len(rows)>5 else rows
def col(i): return [r[i] for r in stable]
print(f"samples={len(rows)} stable={len(stable)} header={header}")
print(f"Busy%  mean={st.mean(col(0)):.2f}  max={max(col(0)):.2f}")
print(f"Bzy_MHz mean={st.mean(col(1)):.0f}  max={max(col(1)):.0f}")
print(f"PkgWatt mean={st.mean(col(2)):.2f}  max={max(col(2)):.2f}  min={min(col(2)):.2f}")
print(f"CorWatt mean={st.mean(col(3)):.2f}  max={max(col(3)):.2f}")
print(f"PkgTmp  mean={st.mean(col(4)):.1f}  max={max(col(4)):.1f}")
print(f"CoreTmp mean={st.mean(col(5)):.1f}  max={max(col(5)):.1f}")
b=list(map(int, before.split())); a=list(map(int, after.split()))
print(f"throttle_delta pkg_events={a[0]-b[0]} pkg_ms={a[1]-b[1]} core_events={a[2]-b[2]} core_ms={a[3]-b[3]}")
PY
}

# Test order: quieter first then higher
for p in quiet balanced balanced-performance performance; do
  run_profile "$p" 30
done

# Also try low-power briefly (15s)
run_profile low-power 15

# Restore balanced at end (safer default)
echo balanced >/sys/firmware/acpi/platform_profile || true
for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  echo powersave >"$g" 2>/dev/null || true
done

log ""
log "DONE. Artifacts in $OUT_DIR"
log "Restored platform_profile=$(cat /sys/firmware/acpi/platform_profile)"
