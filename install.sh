#!/bin/bash

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

exit_on_error() {
    echo -e "\n${RED}[CRITICAL ERROR] $1${NC}"
    exit 1
}

check_dependencies() {
    local deps=("curl" "find" "grep" "mktemp" "cp" "rm")
    for dep in "${deps[@]}"; do
        command -v "$dep" >/dev/null 2>&1 || exit_on_error "Dependency '$dep' is missing. Please install it."
    done
}

check_firefox_lock() {
    if [ -f "$TARGET_PROFILE/parent.lock" ] || [ -f "$TARGET_PROFILE/.parentlock" ]; then
        echo -e "${YELLOW}[!] Warning: Firefox appears to be running.${NC}"
        echo -ne "${BOLD}Continue anyway? (y/N): ${NC}"
        read -r run_choice
        [[ ! "$run_choice" =~ ^[Yy]$ ]] && exit 0
    fi
}

get_profile() {
    clear
    echo -e "${BLUE}${BOLD}==================================================${NC}"
    echo -e "${BLUE}${BOLD}           ARKENFOX GLOBAL CONFIGURATOR           ${NC}"
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
        echo -e "${GREEN}[+] Active profiles detected:${NC}"
        for i in "${!FOUND_PROFILES[@]}"; do
            echo -e "  $((i+1))) ${FOUND_PROFILES[$i]}"
        done
        echo -e "  m) Manual Entry"
        echo -ne "\n${BOLD}Select Target Profile (1-${#FOUND_PROFILES[@]} or m): ${NC}"
        read -r choice

        if [[ "$choice" == "m" ]]; then
            read -r -p "Enter full absolute path: " TARGET_PROFILE
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -le "${#FOUND_PROFILES[@]}" ] && [ "$choice" -gt 0 ]; then
            TARGET_PROFILE="${FOUND_PROFILES[$((choice-1))]}"
        else
            exit_on_error "Invalid selection."
        fi
    else
        read -r -p "Provide profile path manually: " TARGET_PROFILE
    fi

    [[ ! -f "$TARGET_PROFILE/prefs.js" ]] && exit_on_error "Invalid Firefox profile."
    check_firefox_lock
}


options=(
    "Enable Search Suggestions"
    "Enable Password Manager"
    "Restore Default Homepage"
    "Keep Browsing History"
    "Enable WebGL Support"
    "Disable Fingerprint Resistance"
    "SAVE CHANGES"
    "ABORT"
)

selected=()
for ((i=0; i<${#options[@]}-2; i++)); do selected+=(0); done
selected[2]=1
cursor=0

draw_menu() {
    clear
    echo -e "${BLUE}${BOLD}--- Configuration ---${NC}"
    echo -e "${CYAN}Target Profile:${NC} $TARGET_PROFILE"
    echo -e "${YELLOW}Navigation: [↑/↓] | Toggle: [SPACE] | Confirm: [ENTER]${NC}\n"

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
                [[ "$cursor" -eq $((${#options[@]}-2)) ]] && break
                [[ "$cursor" -eq $((${#options[@]}-1)) ]] && exit 0
                ;;
        esac
    done
}

apply_changes() {
    clear
    echo -e "${BLUE}${BOLD}--- DEPLOYMENT LOGS ---${NC}"


    TMP_USERJS=$(mktemp) || exit_on_error "Could not create temporary file."


    if [ -f "$TARGET_PROFILE/user.js" ]; then
        cp "$TARGET_PROFILE/user.js" "$TARGET_PROFILE/user.js.bak" || exit_on_error "Backup failed."
        echo -e "${GREEN}[1/4] Backup created: user.js.bak${NC}"
    fi


    echo -ne "${CYAN}[2/4] Fetching Arkenfox Master...${NC}"
    curl -sL -o "$TMP_USERJS" https://raw.githubusercontent.com/arkenfox/user.js/master/user.js || exit_on_error "Download failed."
    echo -e " ${GREEN}DONE${NC}"


    echo -ne "${CYAN}[3/4] Injecting Overrides...${NC}"
    {
        echo -e "\n\n/** [UserOverrides] **/"
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
    } >> "$TMP_USERJS"


    mv "$TMP_USERJS" "$TARGET_PROFILE/user.js" || exit_on_error "Atomic write failed."
    echo -e " ${GREEN}DONE${NC}"


    echo -ne "${CYAN}[4/4] Purging Cache (prefs.js)...${NC}"
    [ -f "$TARGET_PROFILE/prefs.js" ] && mv "$TARGET_PROFILE/prefs.js" "$TARGET_PROFILE/prefs.js.bak"
    echo -e " ${GREEN}DONE${NC}"

    echo -e "\n${GREEN}${BOLD}İnstallation Success. Please Restart Firefox${NC}"
}

check_dependencies
get_profile
run_menu
apply_changes
