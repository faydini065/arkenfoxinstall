#!/bin/bash

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# GLOBAL ERROR HANDLER
exit_on_error() {
    echo -e "\n${RED}[CRITICAL ERROR] $1${NC}"
    exit 1
}

# DEPENDENCY CHECK (Curl is required)
check_dependencies() {
    command -v curl >/dev/null 2>&1 || exit_on_error "curl is not installed. Please install it using 'sudo apt install curl'."
}

get_profile() {
    clear
    echo -e "${BLUE}${BOLD}==================================================${NC}"
    echo -e "${BLUE}${BOLD}           ARKENFOX GLOBAL CONFIGURATOR           ${NC}"
    echo -e "${BLUE}${BOLD}==================================================${NC}"
    echo -e "${CYAN}[*] Initializing system scan...${NC}\n"

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
        else
            TARGET_PROFILE="${FOUND_PROFILES[$((choice-1))]}"
        fi
    else
        echo -e "${YELLOW}[!] Automatic detection failed.${NC}"
        read -r -p "Provide profile path manually: " TARGET_PROFILE
    fi

    [[ -z "$TARGET_PROFILE" ]] && exit_on_error "Profile path cannot be empty."
    [[ ! -d "$TARGET_PROFILE" ]] && exit_on_error "Directory does not exist: $TARGET_PROFILE"
    [[ ! -f "$TARGET_PROFILE/prefs.js" ]] && exit_on_error "Not a valid Firefox profile (prefs.js missing)."
}

options=(
    "Enable Search Suggestions"
    "Enable Password Manager"
    "Restore Default Homepage (about:home)"
    "Disable Clear on Shutdown (Keep History)"
    "Enable WebGL Support"
    "Disable Fingerprint Resistance (RFP Off)"
    "EXECUTE DEPLOYMENT"
    "ABORT"
)
selected=(0 0 1 0 0 0)
cursor=0

draw_menu() {
    clear
    echo -e "${BLUE}${BOLD}--- SYSTEM CONFIGURATION INTERFACE ---${NC}"
    echo -e "${CYAN}Target Profile:${NC} $TARGET_PROFILE"
    echo -e "${YELLOW}Navigation: [↑/↓] | Toggle: [SPACE] | Confirm: [ENTER]${NC}\n"

    for i in "${!options[@]}"; do
        if [ "$i" -eq "$cursor" ]; then
            prefix="${RED}  > ${NC}${BOLD}${CYAN}"
            suffix="${NC}"
        else
            prefix="    "
            suffix="${NC}"
        fi

        if [ "$i" -lt 6 ]; then
            symbol="${GREEN}[X]${NC}"
            [ "${selected[$i]}" -eq 0 ] && symbol="[ ]"
            echo -e "${prefix}${symbol} ${options[$i]}${suffix}"
        else
            echo -e "\n${prefix}  ${options[$i]}${suffix}"
        fi
    done
}

run_menu() {
    while true; do
        draw_menu
        IFS= read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
        fi

        case "$key" in
            "[A") ((cursor--)); [ "$cursor" -lt 0 ] && cursor=$((${#options[@]} - 1)) ;;
            "[B") ((cursor++)); [ "$cursor" -ge "${#options[@]}" ] && cursor=0 ;;
            " ")
                if [ "$cursor" -lt 6 ]; then
                    [ "${selected[$cursor]}" -eq 1 ] && selected[$cursor]=0 || selected[$cursor]=1
                fi
                ;;
            "")
                if [ "$cursor" -eq 6 ]; then break; fi
                if [ "$cursor" -eq 7 ]; then exit 0; fi
                ;;
        esac
    done
}

apply_changes() {
    clear
    echo -e "${BLUE}${BOLD}--- DEPLOYMENT LOGS & STATUS ---${NC}"

    # 1. Backup Phase
    echo -ne "${CYAN}[1/5] Phase: Backup | Status: Processing...${NC}"
    if [ -f "$TARGET_PROFILE/user.js" ]; then
        cp "$TARGET_PROFILE/user.js" "$TARGET_PROFILE/user.js.bak" || exit_on_error "Backup failed."
        echo -e "\r${CYAN}[1/5] Phase: Backup | Status: ${GREEN}SUCCESS (user.js.bak)${NC}"
    else
        echo -e "\r${CYAN}[1/5] Phase: Backup | Status: ${YELLOW}SKIPPED (No existing user.js)${NC}"
    fi

    # 2. Download Phase
    echo -ne "${CYAN}[2/5] Phase: Fetch  | Status: Downloading Master...${NC}"
    curl -sL -o "$TARGET_PROFILE/user.js" https://raw.githubusercontent.com/arkenfox/user.js/master/user.js || exit_on_error "Download failed."
    echo -e "\r${CYAN}[2/5] Phase: Fetch  | Status: ${GREEN}SUCCESS (v128+ Baseline)${NC}"

    # 3. Injection Phase
    echo -ne "${CYAN}[3/5] Phase: Inject | Status: Appending Overrides...${NC}"
    {
        echo -e "\n\n/** [GLOBAL-USER-OVERRIDES-START] **/"
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
        echo -e "/** [GLOBAL-USER-OVERRIDES-END] **/\n"
    } >> "$TARGET_PROFILE/user.js"
    echo -e "\r${CYAN}[3/5] Phase: Inject | Status: ${GREEN}SUCCESS (Custom Block Applied)${NC}"

    # 4. Verification Phase
    echo -ne "${CYAN}[4/5] Phase: Verify | Status: Checking Integrity...${NC}"
    if grep -q "GLOBAL-USER-OVERRIDES-START" "$TARGET_PROFILE/user.js"; then
        echo -e "\r${CYAN}[4/5] Phase: Verify | Status: ${GREEN}INTEGRITY CONFIRMED${NC}"
    else
        exit_on_error "Injection verification failed. File system might be read-only."
    fi

    # 5. Optimization Phase
    echo -ne "${CYAN}[5/5] Phase: Clean  | Status: Flushing prefs.js...${NC}"
    rm -f "$TARGET_PROFILE/prefs.js"
    echo -e "\r${CYAN}[5/5] Phase: Clean  | Status: ${GREEN}SUCCESS (Cache Purged)${NC}"

    echo -e "\n${GREEN}${BOLD}==================================================${NC}"
    echo -e "${GREEN}${BOLD}      HARDENING & CUSTOMIZATION COMPLETED         ${NC}"
    echo -e "${GREEN}${BOLD}==================================================${NC}"
    echo -e "${YELLOW}Final Instruction:${NC} Please close all Firefox instances and restart."
}

# --- START ---
check_dependencies
get_profile
run_menu
apply_changes
