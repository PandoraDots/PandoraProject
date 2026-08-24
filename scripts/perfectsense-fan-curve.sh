#!/usr/bin/env bash
# Curva userspace PerfectSense — SOMENTE no modo automático de fans.
# Por eixo: só a fan da CPU sobe se a CPU esquentar; GPU idem.
# Duty 0 num eixo = EC auto naquele eixo (não força a outra fan).
# Controle manual = zero interferência. UI permanece em "Auto".
set -euo pipefail

PANDORA_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/pandora"
STATE_FILE="$STATE_DIR/perfectsense.json"
FAN_SYS="/sys/devices/platform/acer-wmi/predator_sense/fan_speed"
[[ -e "$FAN_SYS" ]] || FAN_SYS="/sys/module/nekro_sense/drivers/platform:acer-wmi/acer-wmi/predator_sense/fan_speed"
PLATFORM_PROFILE="/sys/firmware/acpi/platform_profile"
INTERVAL_SEC="${PANDORA_FAN_CURVE_INTERVAL:-2}"
# Histerese entre faixas soft/agressivo
HYST_C=2

# Curva PHN16-72 (i7-14700HX TJMax 100°C; Acer projeta 90–100°C sob carga)
# -----------------------------------------------------------------
# <88°C  → EC auto (0) — silencioso, firmware cuida
# 88–93  → ~5 pontos % acima do EC (estima duty via RPM + 5)
# ≥94°C  → 100% agressivo (só perto do teto térmico)
# Por eixo; só no modo automático do usuário.

mkdir -p "$STATE_DIR"

json_get() {
    local key="$1" default="${2:-}"
    [[ -f "$STATE_FILE" ]] || { printf '%s' "$default"; return; }
    jq -r --arg k "$key" --arg d "$default" '.[$k] // $d' "$STATE_FILE" 2>/dev/null || printf '%s' "$default"
}

json_set() {
    local tmp
    tmp="$(mktemp)"
    if [[ -f "$STATE_FILE" ]]; then
        jq -c --argjson patch "$1" '. * $patch' "$STATE_FILE" >"$tmp"
    else
        printf '%s\n' "$1" >"$tmp"
    fi
    mv -f "$tmp" "$STATE_FILE"
}

read_text() {
    local f="$1"
    [[ -r "$f" ]] || { echo ""; return 1; }
    tr -d '\n' <"$f" | sed 's/[[:space:]]*$//'
}

write_fans() {
    local val="$1"
    [[ -e "$FAN_SYS" ]] || return 1
    if [[ -w "$FAN_SYS" ]]; then
        printf '%s\n' "$val" >"$FAN_SYS" 2>/dev/null || return 1
        return 0
    fi
    if [[ -x /usr/local/bin/pandora-sysfs-write ]]; then
        sudo -n /usr/local/bin/pandora-sysfs-write "$FAN_SYS" "$val" 2>/dev/null || return 1
        return 0
    fi
    return 1
}

find_acer_hwmon() {
    local d
    for d in /sys/class/hwmon/hwmon*; do
        [[ -f "$d/name" ]] || continue
        if [[ "$(cat "$d/name" 2>/dev/null)" == "acer" ]]; then
            printf '%s' "$d"
            return 0
        fi
    done
    return 1
}

# Temps °C: CPU = max(acer temp1, package); GPU = acer temp2
read_temps() {
    local acer tcpu=0 tgpu=0 v
    acer="$(find_acer_hwmon || true)"
    if [[ -n "$acer" ]]; then
        if [[ -r "$acer/temp1_input" ]]; then
            v="$(cat "$acer/temp1_input")"
            tcpu=$((v / 1000))
        fi
        if [[ -r "$acer/temp2_input" ]]; then
            v="$(cat "$acer/temp2_input")"
            tgpu=$((v / 1000))
        fi
    fi
    if [[ -r /sys/class/hwmon/hwmon8/temp1_input ]] \
        && [[ "$(cat /sys/class/hwmon/hwmon8/temp1_label 2>/dev/null || true)" == "Package id 0" ]]; then
        v="$(cat /sys/class/hwmon/hwmon8/temp1_input)"
        v=$((v / 1000))
        ((v > tcpu)) && tcpu=$v
    fi
    printf '%s %s' "$tcpu" "$tgpu"
}

# Faixas térmicas (iguais em todos os perfis EC — o silício tolera 90–100°C)
# auto <88 | soft 88–93 (~EC+5) | agressivo ≥94
band_for_temp() {
    local temp="$1"
    if ((temp < 88)); then echo auto
    elif ((temp < 94)); then echo soft
    else echo agressivo
    fi
}

# Estima duty EC a partir do RPM (calibração PHN16-72)
# CPU ~8000 RPM @100%; GPU ~7500 RPM @100% (observado neste chassis)
rpm_to_duty() {
    local rpm="$1" max_rpm="$2"
    local d
    ((rpm < 0)) && rpm=0
    ((max_rpm < 1)) && { echo 0; return; }
    d=$((rpm * 100 / max_rpm))
    ((d > 100)) && d=100
    ((d < 0)) && d=0
    echo "$d"
}

# Soft = estimativa do automático + 5 pontos percentuais (silencioso)
soft_from_rpm() {
    local rpm="$1" max_rpm="$2"
    local base boost
    base="$(rpm_to_duty "$rpm" "$max_rpm")"
    boost=$((base + 5))
    ((boost > 100)) && boost=100
    # Se EC ainda está quase parado, um toque mínimo de +5
    ((boost < 5)) && boost=5
    echo "$boost"
}

read_fan_rpms() {
    local acer rpm_c=0 rpm_g=0
    acer="$(find_acer_hwmon || true)"
    if [[ -n "$acer" ]]; then
        [[ -r "$acer/fan1_input" ]] && rpm_c="$(cat "$acer/fan1_input")"
        [[ -r "$acer/fan2_input" ]] && rpm_g="$(cat "$acer/fan2_input")"
    fi
    printf '%s %s' "${rpm_c:-0}" "${rpm_g:-0}"
}

# Resolve duty de um eixo: auto→0 | soft→EC+5 | agressivo→100
# soft_sample=1 → eixo em 0 neste tick p/ amostrar RPM do EC
duty_for_band() {
    local band="$1" rpm="$2" max_rpm="$3" soft_sample="$4"
    case "$band" in
        auto) echo 0 ;;
        agressivo) echo 100 ;;
        soft)
            if [[ "$soft_sample" == "1" ]]; then
                echo 0
            else
                soft_from_rpm "$rpm" "$max_rpm"
            fi
            ;;
        *) echo 0 ;;
    esac
}

# Tier só p/ histerese de faixa (0=auto 1=soft 2=agressivo)
tier_for_band() {
    case "$1" in
        auto) echo 0 ;;
        soft) echo 1 ;;
        *) echo 2 ;;
    esac
}

band_for_tier() {
    case "$1" in
        0) echo auto ;;
        1) echo soft ;;
        *) echo agressivo ;;
    esac
}

min_temp_for_tier() {
    local tier="$1"
    case "$tier" in
        0) echo 0 ;;
        1) echo $((88 - HYST_C)) ;;
        *) echo $((94 - HYST_C)) ;;
    esac
}

# Compat: duty_axis usado só indiretamente via band
duty_axis() {
    local temp="$1"
    case "$(band_for_temp "$temp")" in
        auto) echo 0 ;;
        soft) echo 1 ;; # marcador; duty real vem do RPM
        *) echo 100 ;;
    esac
}

tier_axis() {
    case "$1" in
        0) echo 0 ;;
        100) echo 2 ;;
        *) echo 1 ;;
    esac
}

duty_for_tier() {
    # Mantido por compat com resolve_axis antigo — não usar duty fixo no soft
    case "$1" in
        0) echo 0 ;;
        1) echo 1 ;;
        *) echo 100 ;;
    esac
}

# Aplica histerese de faixa (auto/soft/agressivo) por eixo
resolve_band() {
    local temp="$1" last_tier="$2"
    local want min_keep band
    band="$(band_for_temp "$temp")"
    want="$(tier_for_band "$band")"
    if ((want < last_tier)); then
        min_keep="$(min_temp_for_tier "$last_tier")"
        if ((temp > min_keep)); then
            want=$last_tier
        fi
    fi
    printf '%s %s' "$want" "$(band_for_tier "$want")"
}

LAST_TIER_CPU=0
LAST_TIER_GPU=0
LAST_DUTY=""
OWNED=0
SOFT_PHASE_CPU=sample
SOFT_PHASE_GPU=sample
SOFT_HOLD_CPU=""
SOFT_HOLD_GPU=""
SOFT_HOLD_UNTIL_CPU=0
SOFT_HOLD_UNTIL_GPU=0
TICK_N=0
CPU_RPM_MAX=8000
GPU_RPM_MAX=7500

tick() {
    local enabled manual temps tcpu tgpu
    local tier_c band_c tier_g band_g duty_c duty_g duty cur
    local rpms rpm_c rpm_g

    enabled="$(json_get fan_curve_enabled 1)"
    manual="$(json_get fan_curve_manual 0)"
    TICK_N=$((TICK_N + 1))

    # Curva SOMENTE no automático. Manual = não toca.
    if [[ "$manual" == "1" ]]; then
        OWNED=0
        LAST_DUTY=""
        LAST_TIER_CPU=0
        LAST_TIER_GPU=0
        SOFT_PHASE_CPU=sample
        SOFT_PHASE_GPU=sample
        return 0
    fi

    if [[ "$enabled" != "1" ]]; then
        if ((OWNED)); then
            write_fans "0,0" || true
            OWNED=0
            LAST_DUTY="0,0"
            LAST_TIER_CPU=0
            LAST_TIER_GPU=0
            json_set '{"fan_curve_last":"0,0","fan_curve_tier_cpu":0,"fan_curve_tier_gpu":0}'
        fi
        return 0
    fi

    temps="$(read_temps)"
    tcpu="${temps%% *}"
    tgpu="${temps##* }"
    [[ -n "$tcpu" && "$tcpu" -ge 0 ]] || return 0

    read -r tier_c band_c <<<"$(resolve_band "$tcpu" "$LAST_TIER_CPU")"
    read -r tier_g band_g <<<"$(resolve_band "${tgpu:-0}" "$LAST_TIER_GPU")"

    rpms="$(read_fan_rpms)"
    rpm_c="${rpms%% *}"
    rpm_g="${rpms##* }"

    # CPU
    case "$band_c" in
        auto)
            duty_c=0
            SOFT_PHASE_CPU=sample
            SOFT_HOLD_CPU=""
            ;;
        agressivo)
            duty_c=100
            SOFT_PHASE_CPU=sample
            SOFT_HOLD_CPU=""
            ;;
        soft)
            case "${SOFT_PHASE_CPU:-sample}" in
                sample)
                    duty_c=0
                    SOFT_PHASE_CPU=measure
                    ;;
                measure)
                    duty_c="$(soft_from_rpm "$rpm_c" "$CPU_RPM_MAX")"
                    SOFT_HOLD_CPU="$duty_c"
                    SOFT_PHASE_CPU=hold
                    SOFT_HOLD_UNTIL_CPU=$((TICK_N + 8))
                    ;;
                hold)
                    if ((TICK_N >= SOFT_HOLD_UNTIL_CPU)); then
                        duty_c=0
                        SOFT_PHASE_CPU=measure
                    else
                        duty_c="${SOFT_HOLD_CPU:-$(soft_from_rpm "$rpm_c" "$CPU_RPM_MAX")}"
                    fi
                    ;;
                *)
                    duty_c=0
                    SOFT_PHASE_CPU=sample
                    ;;
            esac
            ;;
        *) duty_c=0 ;;
    esac

    # GPU
    case "$band_g" in
        auto)
            duty_g=0
            SOFT_PHASE_GPU=sample
            SOFT_HOLD_GPU=""
            ;;
        agressivo)
            duty_g=100
            SOFT_PHASE_GPU=sample
            SOFT_HOLD_GPU=""
            ;;
        soft)
            case "${SOFT_PHASE_GPU:-sample}" in
                sample)
                    duty_g=0
                    SOFT_PHASE_GPU=measure
                    ;;
                measure)
                    duty_g="$(soft_from_rpm "$rpm_g" "$GPU_RPM_MAX")"
                    SOFT_HOLD_GPU="$duty_g"
                    SOFT_PHASE_GPU=hold
                    SOFT_HOLD_UNTIL_GPU=$((TICK_N + 8))
                    ;;
                hold)
                    if ((TICK_N >= SOFT_HOLD_UNTIL_GPU)); then
                        duty_g=0
                        SOFT_PHASE_GPU=measure
                    else
                        duty_g="${SOFT_HOLD_GPU:-$(soft_from_rpm "$rpm_g" "$GPU_RPM_MAX")}"
                    fi
                    ;;
                *)
                    duty_g=0
                    SOFT_PHASE_GPU=sample
                    ;;
            esac
            ;;
        *) duty_g=0 ;;
    esac

    duty="${duty_c},${duty_g}"
    cur="$(read_text "$FAN_SYS" 2>/dev/null || true)"

    # Mudança externa enquanto donos
    if ((OWNED)) && [[ -n "$cur" && -n "$LAST_DUTY" && "$cur" != "$LAST_DUTY" ]]; then
        if [[ "$cur" == "0,0" ]]; then
            OWNED=0
            json_set '{"fan_curve_manual":0}'
        else
            json_set '{"fan_curve_manual":1}'
            OWNED=0
            LAST_DUTY=""
            LAST_TIER_CPU=0
            LAST_TIER_GPU=0
            return 0
        fi
    fi

    # Sem sermos donos: só entram a partir de auto puro (0,0)
    if ((!OWNED)) && [[ -n "$cur" && "$cur" != "0,0" ]]; then
        json_set '{"fan_curve_manual":1}'
        return 0
    fi

    if [[ "$duty" != "$cur" ]]; then
        write_fans "$duty" || return 0
    fi
    OWNED=1
    LAST_TIER_CPU=$tier_c
    LAST_TIER_GPU=$tier_g
    LAST_DUTY="$duty"
    json_set "$(jq -nc \
        --arg d "$duty" \
        --arg bc "$band_c" --arg bg "$band_g" \
        --argjson tc "$tier_c" --argjson tg "$tier_g" \
        --argjson c "$tcpu" --argjson g "${tgpu:-0}" \
        '{fan_curve_last:$d, fan_curve_band_cpu:$bc, fan_curve_band_gpu:$bg,
          fan_curve_tier_cpu:$tc, fan_curve_tier_gpu:$tg,
          fan_curve_temp_c:$c, fan_curve_temp_gpu_c:$g, fan_curve_manual:0}')"
}

if [[ "$(json_get fan_curve_enabled "")" == "" ]]; then
    json_set '{"fan_curve_enabled":1,"fan_curve_manual":0}'
fi

boot_fans="$(read_text "$FAN_SYS" 2>/dev/null || echo "0,0")"
if [[ "$(json_get fan_curve_manual 0)" == "1" ]]; then
    :
elif [[ "$boot_fans" != "0,0" ]]; then
    last="$(json_get fan_curve_last "")"
    if [[ -n "$last" && "$boot_fans" == "$last" && "$(json_get fan_curve_manual 0)" != "1" ]]; then
        OWNED=1
        LAST_TIER_CPU="$(json_get fan_curve_tier_cpu 0)"
        LAST_TIER_GPU="$(json_get fan_curve_tier_gpu 0)"
        LAST_DUTY="$last"
    else
        # Duty estranho no boot: se curve enabled e não marcado manual,
        # assume que era boost da curva anterior — retoma dono sem marcar manual
        if [[ "$(json_get fan_curve_enabled 1)" == "1" ]]; then
            OWNED=1
            LAST_DUTY="$boot_fans"
            LAST_TIER_CPU="$(json_get fan_curve_tier_cpu 5)"
            LAST_TIER_GPU="$(json_get fan_curve_tier_gpu 0)"
        else
            json_set '{"fan_curve_manual":1}'
        fi
    fi
fi

while true; do
    tick || true
    sleep "$INTERVAL_SEC"
done
