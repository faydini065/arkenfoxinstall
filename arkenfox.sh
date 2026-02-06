#!/bin/bash

# --- COLOR DEFINITIONS ---
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# --- 1. SMART PROFILE DISCOVERY ---
get_profile() {
    clear
    echo -e "${BLUE}${BOLD}==================================================${NC}"
    echo -e "${BLUE}${BOLD}            Arkenfox Installation Script          ${NC}"
    echo -e "${BLUE}${BOLD}==================================================${NC}"
    echo -e "${CYAN}[*] Scanning system for Firefox profiles...${NC}\n"

    # Search common paths including Flatpak, Snap, and Native
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
        echo -e "${GREEN}[+] Profiles discovered:${NC}"
        for i in "${!FOUND_PROFILES[@]}"; do
            echo -e "  $((i+1))) ${FOUND_PROFILES[$i]}"
        done
        echo -e "  m) Enter path manually"
        echo -ne "\n${BOLD}Select a profile (1-${#FOUND_PROFILES[@]} or m): ${NC}"
        read -r choice

        if [[ "$choice" == "m" ]]; then
            read -r -p "Enter full path: " TARGET_PROFILE
        else
            TARGET_PROFILE="${FOUND_PROFILES[$((choice-1))]}"
        fi
    else
        echo -e "${YELLOW}[!] No standard profiles found automatically.${NC}"
        read -r -p "Please paste your profile path manually: " TARGET_PROFILE
    fi

    # Validation
    if [ ! -d "$TARGET_PROFILE" ] || [ ! -f "$TARGET_PROFILE/prefs.js" ]; then
        echo -e "\n${RED}[ERROR] Invalid directory! Profile must contain 'prefs.js'.${NC}"
        exit 1
    fi
}

# --- 2. INTERACTIVE MENU (ARROWS & SPACE) ---
options=(
    "Enable Search Suggestions"
    "Enable Password Manager"
    "Restore Default Homepage (about:home)"
    "Disable 'Clear on Shutdown' (Keep History)"
    "Enable WebGL (For Maps/Games)"
    "Disable Fingerprint"
    "PROCEED WITH INSTALLATION"
    "EXIT"
)
selected=(0 0 1 0 0 0)
cursor=0

draw_menu() {
    clear
    echo -e "${BLUE}${BOLD}--- CONFIGURATION CUSTOMIZATION ---${NC}"
    echo -e "${CYAN}Target:${NC} $TARGET_PROFILE"
    echo -e "${YELLOW}Keys: ↑/↓ Navigate | SPACE Toggle | ENTER Confirm${NC}\n"

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
        # Advanced key handling for Space and Arrows
        IFS= read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
        fi

        case "$key" in
            "[A") ((cursor--)); [ "$cursor" -lt 0 ] && cursor=$((${#options[@]} - 1)) ;;
            "[B") ((cursor++)); [ "$cursor" -ge "${#options[@]}" ] && cursor=0 ;;
            " ") # SPACE toggle
                if [ "$cursor" -lt 6 ]; then
                    [ "${selected[$cursor]}" -eq 1 ] && selected[$cursor]=0 || selected[$cursor]=1
                fi
                ;;
            "") # ENTER
                if [ "$cursor" -eq 6 ]; then break; fi
                if [ "$cursor" -eq 7 ]; then exit 0; fi
                ;;
        esac
    done
}

# --- 3. EXECUTION & VERIFICATION ---
apply_changes() {
    clear
    echo -e "${BLUE}${BOLD}--- DEPLOYMENT LOGS ---${NC}"

    # Backup
    echo -ne "${CYAN}[1/5] Backing up existing user.js...${NC}"
    [ -f "$TARGET_PROFILE/user.js" ] && cp "$TARGET_PROFILE/user.js" "$TARGET_PROFILE/user.js.bak"
    echo -e " ${GREEN}DONE${NC}"

    # Download latest Arkenfox
    echo -ne "${CYAN}[2/5] Downloading latest Arkenfox master...${NC}"
    curl -sL -o "$TARGET_PROFILE/user.js" https://raw.githubusercontent.com/arkenfox/user.js/master/user.js
    if [ $? -ne 0 ]; then echo -e " ${RED}FAILED${NC}"; exit 1; fi
    echo -e " ${GREEN}DONE${NC}"

    # Direct Injection
    echo -ne "${CYAN}[3/5] Injecting custom overrides...${NC}"
    {
        echo -e "\n\n/** [SIYANWARE-INJECTION-START] **/"
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
        echo -e "/** [SIYANWARE-INJECTION-END] **/\n"
    } >> "$TARGET_PROFILE/user.js"
    echo -e " ${GREEN}DONE${NC}"

    # Verification
    echo -ne "${CYAN}[4/5] Verifying integrity...${NC}"
    if grep -q "SIYANWARE-INJECTION-START" "$TARGET_PROFILE/user.js"; then
        echo -e " ${GREEN}VERIFIED${NC}"
    else
        echo -e " ${RED}WRITE ERROR${NC}"; exit 1
    fi

    # Post-Install Clean
    echo -ne "${CYAN}[5/5] Flushing profile cache (prefs.js)...${NC}"
    rm -f "$TARGET_PROFILE/prefs.js"
    echo -e " ${GREEN}DONE${NC}"

    echo -e "\n${GREEN}${BOLD}SUCCESS: Arkenfox has been hardened and customized!${NC}"
    echo -e "${YELLOW}IMPORTANT:${NC} Please restart Firefox completely for changes to take effect."
}

# --- RUN ---
get_profile
run_menu
apply_changes
