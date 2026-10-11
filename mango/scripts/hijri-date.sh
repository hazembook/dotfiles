#!/usr/bin/env bash
# Hijri date for mangobar custom module
# Uses Aladhan API + local cache (1 hour)
# Outputs JSON: {"text": "...", "tooltip": "...", "class": "hijri-date"}

set -euo pipefail

# ============================================================
# CONFIGURATION
# ============================================================
LAT="32.8872"
LNG="13.1913"
METHOD=3

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/mangobar"
CACHE_FILE="$CACHE_DIR/hijri-date.json"
CACHE_DURATION=3600  # 1 hour

# Next weekday mapping (Aladhan returns English weekday)
declare -A NEXT_WEEKDAY_AR=(
    ["Saturday"]="الأحد"
    ["Sunday"]="الاثنين"
    ["Monday"]="الثلاثاء"
    ["Tuesday"]="الأربعاء"
    ["Wednesday"]="الخميس"
    ["Thursday"]="الجمعة"
    ["Friday"]="السبت"
)

# ============================================================
# HELPERS
# ============================================================
mkdir -p "$CACHE_DIR"

load_cache() {
    if [[ -f "$CACHE_FILE" ]]; then
        cat "$CACHE_FILE"
    else
        echo '{}'
    fi
}

save_cache() {
    printf '%s\n' "$1" > "$CACHE_FILE"
}

fetch_aladhan() {
    local date_str="$1"
    local url="https://api.aladhan.com/v1/timings/${date_str}?latitude=${LAT}&longitude=${LNG}&method=${METHOD}"
    curl -sSf --max-time 10 -H "User-Agent: mangobar-hijri/1.0" "$url" || return 1
}

# Extract JSON value using jq
json_get() {
    echo "$1" | jq -r "$2 // empty"
}

format_hijri() {
    local data="$1"
    local day month year weekday_ar
    day=$(json_get "$data" '.data.date.hijri.day')
    month=$(json_get "$data" '.data.date.hijri.month.ar')
    year=$(json_get "$data" '.data.date.hijri.year')
    weekday_ar=$(json_get "$data" '.data.date.hijri.weekday.ar')
    printf '%s %s %s %s' "$weekday_ar" "$day" "$month" "$year"
}

get_gregorian_weekday_en() {
    local data="$1"
    json_get "$data" '.data.date.gregorian.weekday.en'
}

get_maghrib() {
    local data="$1"
    json_get "$data" '.data.timings.Maghrib' | cut -d: -f1,2
}

# ============================================================
# MAIN LOGIC
# ============================================================
now=$(date +%s)
today_str=$(date '+%d-%m-%Y')
current_time=$(date '+%H:%M')

cache_json=$(load_cache)
cached_date=$(echo "$cache_json" | jq -r '.date // empty')
cached_at=$(echo "$cache_json" | jq -r '.cached_at // 0')
hijri_today=$(echo "$cache_json" | jq -r '.hijri_today // empty')
hijri_display=$(echo "$cache_json" | jq -r '.hijri_display // empty')
cached_maghrib=$(echo "$cache_json" | jq -r '.maghrib // "18:00"')

need_fetch=false
if [[ "$cached_date" != "$today_str" ]]; then
    need_fetch=true
elif (( now - cached_at >= CACHE_DURATION )); then
    need_fetch=true
fi

if [[ "$need_fetch" == "true" ]]; then
    response=$(fetch_aladhan "$today_str") || {
        # Network failed - use cache if we have it
        if [[ -n "$hijri_display" ]]; then
            display="$hijri_display"
        elif [[ -n "$hijri_today" ]]; then
            display="$hijri_today"
        else
            display="⚠ Hijri unavailable"
        fi
        output_json "$display"
        exit 0
    }

    # Parse response
    code=$(json_get "$response" '.code')
    if [[ "$code" != "200" ]]; then
        display="$hijri_display"
        if [[ -z "$display" ]]; then display="$hijri_today"; fi
        if [[ -z "$display" ]]; then display="⚠ Hijri unavailable"; fi
        output_json "$display"
        exit 0
    fi

    hijri_today=$(format_hijri "$response")
    maghrib=$(get_maghrib "$response")
    greg_weekday=$(get_gregorian_weekday_en "$response")

    # Determine if after Maghrib -> show tomorrow
    if [[ "$current_time" > "$maghrib" ]]; then
        # Try fetching tomorrow
        tomorrow=$(date -d '+1 day' '+%d-%m-%Y')
        tomorrow_response=$(fetch_aladhan "$tomorrow") || tomorrow_response=""
        
        if [[ -n "$tomorrow_response" ]] && [[ $(json_get "$tomorrow_response" '.code') == "200" ]]; then
            hijri_display=$(format_hijri "$tomorrow_response")
        else
            # Approximate tomorrow
            h_day=$(echo "$response" | jq -r '.data.date.hijri.day')
            h_month=$(echo "$response" | jq -r '.data.date.hijri.month.ar')
            h_year=$(echo "$response" | jq -r '.data.date.hijri.year')
            next_day=$((h_day + 1))
            next_weekday_ar="${NEXT_WEEKDAY_AR[$greg_weekday]:-$(echo "$response" | jq -r '.data.date.hijri.weekday.ar')}"
            if (( next_day > 30 )); then next_day=1; fi
            hijri_display=$(printf '%s %02d %s %s' "$next_weekday_ar" "$next_day" "$h_month" "$h_year")
        fi
    else
        hijri_display="$hijri_today"
    fi

    # Update cache
    cache_json=$(jq -n \
        --arg date "$today_str" \
        --arg hijri_today "$hijri_today" \
        --arg hijri_display "$hijri_display" \
        --arg maghrib "$maghrib" \
        --argjson cached_at "$now" \
        '{date: $date, hijri_today: $hijri_today, hijri_display: $hijri_display, maghrib: $maghrib, cached_at: $cached_at}')
    save_cache "$cache_json"

    # Set display for output
    display="$hijri_display"
else
    # Use cache - check Maghrib for display
    if [[ "$current_time" > "$cached_maghrib" ]]; then
        display="$hijri_display"
    else
        display="$hijri_today"
    fi
fi

# ============================================================
# OUTPUT JSON FOR MANGOBAR
# ============================================================
greg_text=$(date '+%a %d %b %Y | %I:%M %p')
jq -n \
    --arg text "$display" \
    --arg tooltip "Gregorian: $greg_text\nHijri: $display" \
    --arg class "hijri-date" \
    '{text: $text, tooltip: $tooltip, class: $class}'