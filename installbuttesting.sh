#!/bin/bash


BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

CONF_FILE="$HOME/.arkenfox.conf"
LOG_FILE="$HOME/.arkenfox-deploy.log"
TARGET_PROFILE=""
FOUND_PROFILES=()


fatal() {
    echo -e "\n${RED}[FATAL] $1${NC}"
    exit 1
}

init_system() {
    local deps=("curl" "find" "grep" "mktemp" "cp" "rm")
    for dep in "${deps[@]}"; do
        command -v "$dep" >/dev/null 2>&1 || fatal "Dependency '$dep' missing."
    done
}

core_config_io() {
    if [[ "$1" == "save" ]]; then
        echo "${selected[*]}" > "$CONF_FILE"
    else
        if [ -f "$CONF_FILE" ]; then
            selected=($(cat "$CONF_FILE"))
        else
            selected=(0 0 1 0 0 0)
        fi
    fi
}

process_lock_check() {
    local profile="$1"
    local mode="$2"
    if [ -f "$profile/parent.lock" ] || [ -f "$profile/.parentlock" ]; then
        if [[ "$mode" == "--silent" ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] SKIPPED: Firefox active at $(basename "$profile")" >> "$LOG_FILE"
            return 1
        fi
        echo -e "${YELLOW}[!] Firefox is active: $(basename "$profile")${NC}"
        echo -ne "${BOLD}Force execution? (y/N): ${NC}"
        read -r choice
        [[ ! "$choice" =~ ^[Yy]$ ]] && return 1
    fi
    return 0
}

resolve_profiles() {
    local search_dirs=(
        "$HOME/.var/app/org.mozilla.firefox/config/mozilla/firefox"
        "$HOME/.mozilla/firefox"
        "$HOME/snap/firefox/common/.mozilla/firefox"
    )
    FOUND_PROFILES=()
    for dir in "${search_dirs[@]}"; do
        if [ -d "$dir" ]; then
            while read -r p; do
                [[ -n "$p" ]] && FOUND_PROFILES+=("$(dirname "$p")")
            done < <(find "$dir" -maxdepth 3 -name "prefs.js" 2>/dev/null)
        fi
    done
}


ui_select_profile() {
    while true; do
        resolve_profiles
        local p_opts=("${FOUND_PROFILES[@]}" "Manual Entry" "Exit")
        local cursor=0
        
        while true; do
            clear
            echo -e "${BLUE}${BOLD}==================================================${NC}"
            echo -e "${BLUE}${BOLD}             FIREFOX PROFILE SELECTION            ${NC}"
            echo -e "${BLUE}${BOLD}==================================================${NC}"
            for i in "${!p_opts[@]}"; do
                [[ "$i" -eq "$cursor" ]] && echo -e "${RED}  > ${NC}${BOLD}${CYAN}${p_opts[$i]}${NC}" || echo -e "    ${p_opts[$i]}"
            done
            IFS= read -rsn1 k
            [[ $k == $'\x1b' ]] && { read -rsn2 k; }
            case "$k" in
                "[A") ((cursor--)); [ "$cursor" -lt 0 ] && cursor=$((${#p_opts[@]} - 1)) ;;
                "[B") ((cursor++)); [ "$cursor" -ge "${#p_opts[@]}" ] && cursor=0 ;;
                "") 
                    if [[ "$cursor" -eq $((${#p_opts[@]} - 1)) ]]; then exit 0;
                    elif [[ "$cursor" -eq $((${#p_opts[@]} - 2)) ]]; then
                        echo -ne "\nEnter full path (e.g. ~/my-profile): "
                        read -r TARGET_PROFILE
                        TARGET_PROFILE="${TARGET_PROFILE/#\~/$HOME}"
                        if [[ ! -d "$TARGET_PROFILE" || ! -f "$TARGET_PROFILE/prefs.js" ]]; then
                            echo -e "${RED}[!] Invalid directory or no prefs.js found.${NC}"
                            sleep 2
                            break
                        fi
                    else TARGET_PROFILE="${FOUND_PROFILES[$cursor]}"; fi
                    return 0 ;;
            esac
        done
    done
}

options=("Search Suggestions" "Password Manager" "Restore Homepage" "History Persistence" "WebGL Support" "Disable RFP" "[✔]CONFIRM" "[x]ABORT")
selected=()
core_config_io "load"

ui_render_config() {
    local cursor=0
    while true; do
        clear
        echo -e "${BLUE}${BOLD}--- CONFIGURATION PANEL ---${NC}"
        echo -e "${CYAN}Target Profile:${NC} $TARGET_PROFILE\n"
        for i in "${!options[@]}"; do
            prefix="    "
            [[ "$i" -eq "$cursor" ]] && prefix="${RED}  > ${NC}${BOLD}${CYAN}"
            if [ "$i" -lt $((${#options[@]}-2)) ]; then
                symbol="[ ]"
                [[ "${selected[$i]}" -eq 1 ]] && symbol="${GREEN}[X]${NC}"
                echo -e "${prefix}${symbol} ${options[$i]}${NC}"
            else echo -e "\n${prefix}  ${options[$i]}${NC}"; fi
        done
        IFS= read -rsn1 k
        [[ $k == $'\x1b' ]] && { read -rsn2 k; }
        case "$k" in
            "[A") ((cursor--)); [ "$cursor" -lt 0 ] && cursor=$((${#options[@]} - 1)) ;;
            "[B") ((cursor++)); [ "$cursor" -ge "${#options[@]}" ] && cursor=0 ;;
            " ") [ "$cursor" -lt $((${#options[@]}-2)) ] && { [[ "${selected[$cursor]}" -eq 1 ]] && selected[$cursor]=0 || selected[$cursor]=1; } ;;
            "") [[ "$cursor" -eq $((${#options[@]}-2)) ]] && { core_config_io "save"; execute_deployment "$TARGET_PROFILE"; break; }
                [[ "$cursor" -eq $((${#options[@]}-1)) ]] && break ;;
        esac
    done
}


execute_deployment() {
    local profile="$1"
    local mode="$2"
    local tmp=$(mktemp)

    [[ "$mode" != "--silent" ]] && clear && echo -e "${BLUE}${BOLD}--- DEPLOYMENT: $(basename "$profile") ---${NC}"
    
    # 1. Lock Check
    if ! process_lock_check "$profile" "$mode"; then
        rm -f "$tmp"; return 1
    fi

    
    if ! curl -sL -o "$tmp" https://raw.githubusercontent.com/arkenfox/user.js/master/user.js || [ ! -s "$tmp" ]; then
        [[ "$mode" == "--silent" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Network/File error at $(basename "$profile")" >> "$LOG_FILE"
        rm -f "$tmp"; return 1
    fi

sed -e 's/\/\* \(ESR[0-9]\{2,\}\.x still uses all.*\)/\/\/ \1/' "$tmp" > "$tmp.tmp" && mv "$tmp.tmp" "$tmp"
    
    [ -f "$profile/user.js" ] && [ ! -f "$profile/user.js.bak" ] && cp "$profile/user.js" "$profile/user.js.bak"
    [ -f "$profile/prefs.js" ] && [ ! -f "$profile/prefs.js.bak" ] && cp "$profile/prefs.js" "$profile/prefs.js.bak"

    
    {
        echo -e "\n/** [UserOverrides] **/"
        [[ "${selected[0]}" -eq 1 ]] && echo 'user_pref("browser.search.suggest.enabled", true);'
        [[ "${selected[1]}" -eq 1 ]] && echo 'user_pref("signon.rememberSignons", true);'
        if [ "${selected[2]}" -eq 1 ]; then
            echo 'user_pref("browser.startup.homepage", "about:home");'
            echo 'user_pref("browser.newtabpage.enabled", true);'
            echo 'user_pref("browser.startup.page", 1);'
        fi
        [[ "${selected[3]}" -eq 1 ]] && echo 'user_pref("privacy.sanitize.sanitizeOnShutdown", false);'
        [[ "${selected[4]}" -eq 1 ]] && echo 'user_pref("webgl.disabled", false);'
        [[ "${selected[5]}" -eq 1 ]] && echo 'user_pref("privacy.resistFingerprinting", false);'
        echo -e "/** [UserOverrides] **/\n"
    } >> "$tmp"

    # 5. Atomic Move (With Check)
    if mv "$tmp" "$profile/user.js"; then
        if [[ "$mode" == "--silent" ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: Updated $(basename "$profile")" >> "$LOG_FILE"
        else
            echo -e "${GREEN}[✔] Deployment completed successfully.${NC}"
            read -n 1 -s -p "Press any key..."
        fi
    else
        [[ "$mode" == "--silent" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: MV failed at $profile" >> "$LOG_FILE"
        rm -f "$tmp"; return 1
    fi
}


automation_setup() {
    clear
    local path=$(readlink -f "$0")
    if (crontab -l 2>/dev/null | grep -v "$path"; echo "@daily /bin/bash \"$path\" --auto-deploy") | crontab - 2>/dev/null; then
        echo -e "${GREEN}[✔] Auto-updater set to DAILY via Cron.${NC}"
    else
        echo -e "${RED}[!] Failed to set crontab. Check permissions.${NC}"
    fi
    read -n 1 -s -p "Press any key..."
}

system_purge() {
    clear
    echo -ne "${RED}Purge Arkenfox and restore original settings? (y/N): ${NC}"; read -r c
    if [[ "$c" =~ ^[Yy]$ ]]; then
        [ -f "$TARGET_PROFILE/user.js.bak" ] && mv "$TARGET_PROFILE/user.js.bak" "$TARGET_PROFILE/user.js" || rm -f "$TARGET_PROFILE/user.js"
        [ -f "$TARGET_PROFILE/prefs.js.bak" ] && mv "$TARGET_PROFILE/prefs.js.bak" "$TARGET_PROFILE/prefs.js"
        rm -f "$CONF_FILE"
        local path=$(readlink -f "$0")
        crontab -l 2>/dev/null | grep -v "$path" | crontab -
        echo -e "${GREEN}[✔] System purged and restored.${NC}"
    fi
    read -n 1 -s -p "Press any key..."
}

main_interface() {
    local opts=("INSTALL / UPDATE" "UNINSTALL" "SET AUTO-UPDATER" "EXIT")
    local cur=0
    while true; do
        clear
        echo -e "${BLUE}${BOLD}==================================================${NC}"
        echo -e "${BLUE}${BOLD}            ARKENFOX MANAGEMENT PANEL             ${NC}"
        echo -e "${BLUE}${BOLD}==================================================${NC}"
        [[ -n "$TARGET_PROFILE" ]] && echo -e "${CYAN}Active Profile:${NC} $TARGET_PROFILE\n"
        for i in "${!opts[@]}"; do
            [[ "$i" -eq "$cur" ]] && echo -e "${RED}  > ${NC}${BOLD}${CYAN}${opts[$i]}${NC}" || echo -e "    ${opts[$i]}"
        done
        IFS= read -rsn1 k
        [[ $k == $'\x1b' ]] && { read -rsn2 k; }
        case "$k" in
            "[A") ((cur--)); [ "$cur" -lt 0 ] && cur=3 ;;
            "[B") ((cur++)); [ "$cur" -gt 3 ] && cur=0 ;;
            "") case $cur in 0) ui_render_config ;; 1) system_purge ;; 2) automation_setup ;; 3) exit 0 ;; esac ;;
        esac
    done
}


init_system
if [[ "$1" == "--auto-deploy" ]]; then
    core_config_io "load" 
    resolve_profiles
    for profile in "${FOUND_PROFILES[@]}"; do
        execute_deployment "$profile" "--silent"
    done
else
    ui_select_profile
    main_interface
fi
