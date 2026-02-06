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
        echo -e "${YELLOW}[!] Alert: Firefox process is currently active.${NC}"
        echo -ne "${BOLD}Force execution? (y/N): ${NC}"
        read -r run_choice
        [[ ! "$run_choice" =~ ^[Yy]$ ]] && exit 0
    fi
}

get_profile() {
    clear
    echo -e "${BLUE}${BOLD}==================================================${NC}"
    echo -e "${BLUE}${BOLD}                   Arkenfox Installer             ${NC}"
    echo -e "${BLUE}${BOLD}==================================================${NC}"

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
        echo -e "${GREEN}[+] Discovery: Found ${#FOUND_PROFILES[@]} compatible profiles:${NC}"
        for i in "${!FOUND_PROFILES[@]}"; do
            echo -e "  $((i+1))) ${FOUND_PROFILES[$i]}"
        done
        echo -e "  m) Manual Entry"
        echo -ne "\n${BOLD}Select Target Profile: ${NC}"
        read -r choice

        if [[ "$choice" == "m" ]]; then
            read -r -p "Enter full absolute path: " TARGET_PROFILE
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -le "${#FOUND_PROFILES[@]}" ] && [ "$choice" -gt 0 ]; then
            TARGET_PROFILE="${FOUND_PROFILES[$((choice-1))]}"
        else
            exit_on_error "Invalid input selection."
        fi
    else
        read -r -p "Profile not detected. Provide path manually: " TARGET_PROFILE
    fi

    [[ ! -f "$TARGET_PROFILE/prefs.js" ]] && exit_on_error "Target directory is not a valid Firefox profile."
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
selected[2]=1
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

set_updater() {
    clear
    echo -e "${BLUE}${BOLD}--- SET AUTO-UPDATER ---${NC}"
    local script_path=$(realpath "$0")
    
    # Bilgisayar her açıldığında (@reboot) çalışacak şekilde crontab'a ekler
    (crontab -l 2>/dev/null | grep -v "$script_path"; echo "@reboot /bin/bash $script_path --auto-deploy") | crontab -
    
    echo -e "${GREEN}[✔] Success: Updater scheduled at every system startup.${NC}"
    echo -e "${YELLOW}[!] The script will now run once in the background whenever you boot up.${NC}"
    read -n 1 -s -p "Press any key to return..."
}

uninstall_arkenfox() {
    clear
    echo -e "${RED}${BOLD}--- UNINSTALL ARKENFOX ---${NC}"
    echo -e "${YELLOW}[!] Backups will be restored if available.${NC}"
    echo -ne "${BOLD}Continue? (y/N): ${NC}"
    read -r un_choice
    if [[ "$un_choice" =~ ^[Yy]$ ]]; then
        [ -f "$TARGET_PROFILE/user.js.bak" ] && mv "$TARGET_PROFILE/user.js.bak" "$TARGET_PROFILE/user.js" || rm -f "$TARGET_PROFILE/user.js"
        [ -f "$TARGET_PROFILE/prefs.js.bak" ] && mv "$TARGET_PROFILE/prefs.js.bak" "$TARGET_PROFILE/prefs.js"
        # Crontab kaydını da temizle
        local script_path=$(realpath "$0")
        crontab -l 2>/dev/null | grep -v "$script_path" | crontab -
        echo -e "${GREEN}[✔] Arkenfox removed and auto-updater unscheduled.${NC}"
    fi
    read -n 1 -s -p "Press any key to return..."
}

apply_changes() {
    [[ "$1" != "--silent" ]] && check_firefox_lock
    clear
    echo -e "${BLUE}${BOLD}--- EXECUTION LOGS ---${NC}"

    TMP_USERJS=$(mktemp) || exit_on_error "Environment error."

    if [ -f "$TARGET_PROFILE/user.js" ]; then
        cp "$TARGET_PROFILE/user.js" "$TARGET_PROFILE/user.js.bak"
        echo -e "${CYAN}[1/4] Status:${NC} Existing user.js archived."
    fi

    echo -ne "${CYAN}[2/4] Fetching:${NC} Downloading Arkenfox baseline..."
    curl -sL -o "$TMP_USERJS" https://raw.githubusercontent.com/arkenfox/user.js/master/user.js || exit_on_error "Network error."
    echo -e " ${GREEN}SUCCESS${NC}"

    echo -ne "${CYAN}[3/4] Injecting:${NC} Applying custom user overrides..."
    {
        echo -e "\n\n/** [UserOverrides] **/"
        [[ "${selected[0]}" -eq 1 ]] || [[ "$1" == "--silent" ]] && echo 'user_pref("browser.search.suggest.enabled", true);'
        [[ "${selected[1]}" -eq 1 ]] && echo 'user_pref("signon.rememberSignons", true);'
        if [ "${selected[2]}" -eq 1 ] || [ "$1" == "--silent" ]; then
            echo 'user_pref("browser.startup.homepage", "about:home");'
            echo 'user_pref("browser.newtabpage.enabled", true);'
            echo 'user_pref("browser.startup.page", 1);'
        fi
        [[ "${selected[3]}" -eq 1 ]] && echo 'user_pref("privacy.sanitize.sanitizeOnShutdown", false);'
        [[ "${selected[4]}" -eq 1 ]] && echo 'user_pref("webgl.disabled", false);'
        [[ "${selected[5]}" -eq 1 ]] && echo 'user_pref("privacy.resistFingerprinting", false);'
        echo -e "/** [UserOverrides] **/\n"
    } >> "$TMP_USERJS"

    mv "$TMP_USERJS" "$TARGET_PROFILE/user.js" || exit_on_error "Failed to write user.js"
    echo -e " ${GREEN}SUCCESS${NC}"

    echo -ne "${CYAN}[4/4] Optimizing:${NC} Synchronizing profile preferences..."
    [ -f "$TARGET_PROFILE/prefs.js" ] && cp "$TARGET_PROFILE/prefs.js" "$TARGET_PROFILE/prefs.js.bak"
    echo -e " ${GREEN}SUCCESS${NC}"

    echo -e "\n${GREEN}${BOLD}[✔] Success. Please restart Firefox.${NC}"
    [[ "$1" != "--silent" ]] && read -n 1 -s -p "Press any key to return..."
}

main_panel() {
    local main_options=("INSTALL / UPDATE" "UNINSTALL" "SET AUTO-UPDATER" "EXIT")
    local cur=0
    while true; do
        clear
        echo -e "${BLUE}${BOLD}==================================================${NC}"
        echo -e "${BLUE}${BOLD}            ARKENFOX MANAGEMENT PANEL             ${NC}"
        echo -e "${BLUE}${BOLD}==================================================${NC}"
        echo -e "${CYAN}Target Profile:${NC} $TARGET_PROFILE\n"

        for i in "${!main_options[@]}"; do
            if [[ "$i" -eq "$cur" ]]; then
                echo -e "${RED}  > ${NC}${BOLD}${CYAN}${main_options[$i]}${NC}"
            else
                echo -e "    ${main_options[$i]}"
            fi
        done

        IFS= read -rsn1 key
        [[ $key == $'\x1b' ]] && { read -rsn2 key; }
        case "$key" in
            "[A") ((cur--)); [ "$cur" -lt 0 ] && cur=$((${#main_options[@]} - 1)) ;;
            "[B") ((cur++)); [ "$cur" -ge "${#main_options[@]}" ] && cur=0 ;;
            "") 
                case $cur in
                    0) run_menu ;;
                    1) uninstall_arkenfox ;;
                    2) set_updater ;;
                    3) exit 0 ;;
                esac
                ;;
        esac
    done
}

# SESSİZ ÇALIŞMA MODU (CRON İÇİN)
if [[ "$1" == "--auto-deploy" ]]; then
    get_profile
    apply_changes "--silent"
    exit 0
fi

check_dependencies
get_profile
main_panel
