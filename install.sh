#!/bin/bash

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

exit_on_error() {
    echo -e "\n${RED}[ERROR] $1${NC}"
    exit 1
}

check_dependencies() {
    local deps=("curl" "find" "grep" "mktemp" "cp" "rm")
    for dep in "${deps[@]}"; do
        command -v "$dep" >/dev/null 2>&1 || exit_on_error "Required dependency '$dep' not found."
    done
}

check_firefox_lock() {
    if [ -f "$TARGET_PROFILE/parent.lock" ] || [ -f "$TARGET_PROFILE/.parentlock" ]; then
        if [[ "$1" == "--silent" ]]; then exit 0; fi # Sessiz modda hata verme, çık.
        echo -e "${YELLOW}[!] Alert: Firefox process is currently active.${NC}"
        echo -ne "${BOLD}Force execution? (y/N): ${NC}"
        read -r run_choice
        [[ ! "$run_choice" =~ ^[Yy]$ ]] && exit 0
    fi
}

get_profile() {
    local mode=$1
    SEARCH_PATHS=(
        "$HOME/.var/app/org.mozilla.firefox/config/mozilla/firefox"
        "$HOME/.mozilla/firefox"
        "$HOME/snap/firefox/common/.mozilla/firefox"
    )

    FOUND_PROFILES=()
    for path in "${SEARCH_PATHS[@]}"; do
        if [ -d "$path" ]; then
            while read -r folder; do
                [[ -n "$folder" ]] && FOUND_PROFILES+=("$folder")
            done < <(find "$path" -maxdepth 1 -type d -name "*.default-release" 2>/dev/null)
        fi
    done

    if [ ${#FOUND_PROFILES[@]} -gt 0 ]; then
        if [[ "$mode" == "--silent" ]]; then
            TARGET_PROFILE="${FOUND_PROFILES[0]}"
        else
            clear
            echo -e "${BLUE}${BOLD}==================================================${NC}"
            echo -e "${BLUE}${BOLD}                   Arkenfox Installer             ${NC}"
            echo -e "${BLUE}${BOLD}==================================================${NC}"
            echo -e "${GREEN}[+] Discovery: Found ${#FOUND_PROFILES[@]} profiles:${NC}"
            for i in "${!FOUND_PROFILES[@]}"; do
                echo -e "  $((i+1))) ${FOUND_PROFILES[$i]}"
            done
            echo -e "  m) Manual Entry"
            echo -ne "\n${BOLD}Select Target Profile (Default 1): ${NC}"
            read -r choice
            if [[ "$choice" == "m" ]]; then
                read -r -p "Enter full path: " TARGET_PROFILE
            elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -le "${#FOUND_PROFILES[@]}" ]; then
                TARGET_PROFILE="${FOUND_PROFILES[$((choice-1))]}"
            else
                TARGET_PROFILE="${FOUND_PROFILES[0]}"
            fi
        fi
    else
        [[ "$mode" == "--silent" ]] && exit 0
        read -r -p "Profile not detected. Provide path manually: " TARGET_PROFILE
    fi
    [[ ! -f "$TARGET_PROFILE/prefs.js" ]] && exit_on_error "Invalid Firefox profile."
}


options=(
    "Enable Search Suggestions"
    "Enable Password Manager"
    "Restore Default Homepage"
    "Keep Browsing History"
    "Enable WebGL Support"
    "Disable Fingerprint Resistance"
    "[✔]CONFIRM"
    "[x]ABORT"
)

selected=()
for ((i=0; i<${#options[@]}-2; i++)); do selected+=(0); done
selected[2]=1 # Homepage varsayılan seçili
cursor=0

draw_menu() {
    clear
    echo -e "${BLUE}${BOLD}--- CONFIGURATION INTERFACE ---${NC}"
    echo -e "${CYAN}Target Profile:${NC} $TARGET_PROFILE"
    echo -e "${YELLOW}Keys: [↑/↓] Navigate | [SPACE] Select | [ENTER] Confirm${NC}\n"

    for i in "${!options[@]}"; do
        prefix="    "
        [[ "$i" -eq "$cursor" ]] && prefix="${RED}  > ${NC}${BOLD}${CYAN}"
        if [ "$i" -lt $((${#options[@]}-2)) ]; then
            symbol="[ ]"
            [[ "${selected[$i]}" -eq 1 ]] && symbol="${GREEN}[X]${NC}"
            echo -e "${prefix}${symbol} ${options[$i]}${NC}"
        else
            echo -e "\n${prefix}  ${options[$i]}${NC}"
        fi
    done
}

run_menu() {
    while true; do
        draw_menu
        IFS= read -rsn1 key
        [[ $key == $'\x1b' ]] && { read -rsn2 key; }
        case "$key" in
            "[A") ((cursor--)); [ "$cursor" -lt 0 ] && cursor=$((${#options[@]} - 1)) ;;
            "[B") ((cursor++)); [ "$cursor" -ge "${#options[@]}" ] && cursor=0 ;;
            " ") [ "$cursor" -lt $((${#options[@]}-2)) ] && { [[ "${selected[$cursor]}" -eq 1 ]] && selected[$cursor]=0 || selected[$cursor]=1; } ;;
            "")
                [[ "$cursor" -eq $((${#options[@]}-2)) ]] && { apply_changes; break; }
                [[ "$cursor" -eq $((${#options[@]}-1)) ]] && break
                ;;
        esac
    done
}


apply_changes() {
    local mode=$1
    [[ "$mode" != "--silent" ]] && clear && echo -e "${BLUE}${BOLD}--- EXECUTION LOGS ---${NC}"
    check_firefox_lock "$mode"

    TMP_USERJS=$(mktemp) || exit_on_error "Temp file failed."
    [ -f "$TARGET_PROFILE/user.js" ] && cp "$TARGET_PROFILE/user.js" "$TARGET_PROFILE/user.js.bak"

    curl -sL -o "$TMP_USERJS" https://raw.githubusercontent.com/arkenfox/user.js/master/user.js || exit_on_error "Download failed."

    {
        echo -e "\n\n/** [UserOverrides] **/"
        if [[ "$mode" == "--silent" ]]; then
            # Sessiz mod varsayılanları
            echo 'user_pref("browser.search.suggest.enabled", true);'
            echo 'user_pref("browser.startup.homepage", "about:home");'
            echo 'user_pref("browser.newtabpage.enabled", true);'
            echo 'user_pref("browser.startup.page", 1);'
        else
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
        fi
        echo -e "/** [UserOverrides] **/\n"
    } >> "$TMP_USERJS"

    mv "$TMP_USERJS" "$TARGET_PROFILE/user.js"
    cp "$TARGET_PROFILE/prefs.js" "$TARGET_PROFILE/prefs.js.bak"
    
    if [[ "$mode" != "--silent" ]]; then
        echo -e "${GREEN}[✔] Success. Please restart Firefox.${NC}"
        read -n 1 -s -p "Press any key to return..."
    fi
}

set_updater() {
    clear
    local s_path=$(readlink -f "$0")
    (crontab -l 2>/dev/null | grep -v "$s_path"; echo "@reboot /bin/bash \"$s_path\" --auto-deploy") | crontab -
    echo -e "${GREEN}[✔] Success: Auto-updater set for system startup.${NC}"
    read -n 1 -s -p "Press any key to return..."
}

uninstall_arkenfox() {
    clear
    echo -ne "${RED}Uninstall Arkenfox and restore backups? (y/N): ${NC}"
    read -r un_choice
    if [[ "$un_choice" =~ ^[Yy]$ ]]; then
        [ -f "$TARGET_PROFILE/user.js.bak" ] && mv "$TARGET_PROFILE/user.js.bak" "$TARGET_PROFILE/user.js" || rm -f "$TARGET_PROFILE/user.js"
        [ -f "$TARGET_PROFILE/prefs.js.bak" ] && mv "$TARGET_PROFILE/prefs.js.bak" "$TARGET_PROFILE/prefs.js"
        local s_path=$(readlink -f "$0")
        crontab -l 2>/dev/null | grep -v "$s_path" | crontab -
        echo -e "${GREEN}[✔] Uninstalled.${NC}"
    fi
    read -n 1 -s -p "Press any key to return..."
}

main_panel() {
    local m_options=("INSTALL / UPDATE" "UNINSTALL" "SET AUTO-UPDATER" "EXIT")
    local cur=0
    while true; do
        clear
        echo -e "${BLUE}${BOLD}==================================================${NC}"
        echo -e "${BLUE}${BOLD}            ARKENFOX MANAGEMENT PANEL             ${NC}"
        echo -e "${BLUE}${BOLD}==================================================${NC}"
        for i in "${!m_options[@]}"; do
            [[ "$i" -eq "$cur" ]] && echo -e "${RED}  > ${NC}${BOLD}${CYAN}${m_options[$i]}${NC}" || echo -e "    ${m_options[$i]}"
        done
        IFS= read -rsn1 key
        [[ $key == $'\x1b' ]] && { read -rsn2 key; }
        case "$key" in
            "[A") ((cur--)); [ "$cur" -lt 0 ] && cur=3 ;;
            "[B") ((cur++)); [ "$cur" -gt 3 ] && cur=0 ;;
            "") case $cur in 0) run_menu ;; 1) uninstall_arkenfox ;; 2) set_updater ;; 3) exit 0 ;; esac ;;
        esac
    done
}

check_dependencies

if [[ "$1" == "--auto-deploy" ]]; then
    get_profile "--silent"
    apply_changes "--silent"
else
    get_profile
    main_panel
fi
