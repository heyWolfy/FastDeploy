#!/bin/bash

# --- FastDeploy: High Performance FastAPI Deployment Script ---
# Support: Ubuntu 20.04/22.04/24.04, Debian 11/12/13
# Optimizations: Nginx Keep-Alive, Systemd Limits, Kernel BBR, Uvicorn tuning

set -euo pipefail

# --- SOURCE MODULES ---
# Determine script directory to allow running from other locations (optional, but good practice)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Check if lib directory exists
if [ ! -d "$LIB_DIR" ]; then
    echo "Error: 'lib' directory not found at $LIB_DIR."
    echo "Please ensure the script is installed correctly with its dependencies."
    exit 1
fi

# Source Core
source "$LIB_DIR/core/utils.sh"
source "$LIB_DIR/core/input.sh"

# Set trap to call cleanup function on error or exit (defined in utils.sh)
trap cleanup ERR EXIT

# Source System
source "$LIB_DIR/system/prereqs.sh"
source "$LIB_DIR/system/tuning.sh"
source "$LIB_DIR/system/network.sh"

# Source App
source "$LIB_DIR/app/source.sh"
source "$LIB_DIR/app/python.sh"

# Source Services
source "$LIB_DIR/services/systemd.sh"
source "$LIB_DIR/services/nginx.sh"
source "$LIB_DIR/services/cleanup.sh"
source "$LIB_DIR/services/update.sh"


# Main function
main() {
    # --- SCRIPT START ---
    clear
    scan_installed_apps # Scan for existing apps to populate the registry

    echo -e "${GREEN}Welcome to the FastDeploy - FastAPI Application Deployment Script!${NC}"
    echo "This script will help you deploy a FastAPI application with Nginx and Systemd."
    echo -e "${YELLOW}You can press Ctrl+C/CMD+C at any point to abort the script. A cleanup will be attempted if necessary.${NC}"
    echo "--------------------------------------------------------------------------"

    # Choose mode
    while true; do
        read -p "Choose mode (Install/Configure/Uninstall) [I/c/u, default: I]: " MODE_CHOICE
        MODE_CHOICE=${MODE_CHOICE:-I}
        if [[ $MODE_CHOICE =~ ^[Ii]$ ]]; then
            MODE="Install"
            break
        elif [[ $MODE_CHOICE =~ ^[Cc]$ ]]; then
            MODE="Configure"
            break
        elif [[ $MODE_CHOICE =~ ^[Uu]$ ]]; then
            MODE="Uninstall"
            break
        else
            echo -e "${RED}Invalid input. Please enter 'I', 'C', or 'U'.${NC}"
        fi
    done

    if [ "$MODE" = "Configure" ]; then
        update_configs
        SCRIPT_EXITING_CLEANLY_AFTER_USER_ACTION="true"
        exit 0
    fi

    if [ "$MODE" = "Uninstall" ]; then
        uninstall_app
        exit 0
    fi

    # --- INSTALLATION MODE ---
    color_echo "Starting Installation Process..."

    # Get installation mode
    while true; do
        read -p "Choose Installation Mode (Easy/Advanced) [E/a, default: E]: " INSTALLATION_MODE_CHOICE
        INSTALLATION_MODE_CHOICE=${INSTALLATION_MODE_CHOICE:-E}
        if [[ $INSTALLATION_MODE_CHOICE =~ ^[Ee]$ ]]; then
            INSTALLATION_MODE="Easy"
            break
        elif [[ $INSTALLATION_MODE_CHOICE =~ ^[Aa]$ ]]; then
            INSTALLATION_MODE="Advanced"
            break
        else
            echo -e "${RED}Invalid input. Please enter 'E' (Easy) or 'A' (Advanced).${NC}"
        fi
    done

    # Calculate recommended number of workers
    local num_cores
    num_cores=$(nproc)
    recommended_workers=$(($num_cores * 2 + 1))

    # Calculate dynamic defaults
    local TOTAL_MEM_MB
    TOTAL_MEM_MB=$(free -m | awk '/^Mem:/{print $2}' 2>/dev/null)
    if ! [[ "$TOTAL_MEM_MB" =~ ^[0-9]+$ ]] || [ -z "$TOTAL_MEM_MB" ]; then
        TOTAL_MEM_MB=1024 # Fallback if 'free -m' fails or gives weird output
        color_echo "${YELLOW}Could not reliably determine total system memory. Assuming ${TOTAL_MEM_MB}MB for suggestions.${NC}"
    fi

    # Suggest MemoryMax as 1/8th of total RAM, with a minimum of 256M and max of e.g. 4G for this default
    local RECOMMENDED_MEM_MAX_RAW=$((TOTAL_MEM_MB / 8))
    if [ "$RECOMMENDED_MEM_MAX_RAW" -lt 256 ]; then
        DEFAULT_MEMORY_MAX="256M"
    elif [ "$RECOMMENDED_MEM_MAX_RAW" -gt 4096 ]; then # Cap suggestion at 4G
        DEFAULT_MEMORY_MAX="4G"
    else
        DEFAULT_MEMORY_MAX="${RECOMMENDED_MEM_MAX_RAW}M"
    fi
    color_echo "Suggesting MemoryMax for systemd: $DEFAULT_MEMORY_MAX (based on ${TOTAL_MEM_MB}MB total RAM)"

    # Default values (some might be overridden by "Easy" mode in get_input)
    DEFAULT_NUM_WORKERS=$recommended_workers
    DEFAULT_CONCURRENCY_LIMIT=1000
    DEFAULT_BACKLOG_SIZE=2048
    DEFAULT_NICE_VALUE=0
    DEFAULT_CPU_QUOTA="80%"
    DEFAULT_NGINX_GZIP_COMP_LEVEL=4
    DEFAULT_APP_PORT=3456
    DEFAULT_UVICORN_APP_MODULE="main:app"

    # Get user inputs
    get_input "Enter the Nice name of the app" APP_NICE_NAME validate_not_empty \
        "\\nEnter a descriptive, human-readable name for your application.
        This name will be used in the description of the systemd service
        (e.g., 'My Awesome Product API'). It's for display purposes and helps
        identify the service. Example: \`Customer Data API\`, \`Internal Reporting Service\`."
    
    get_input "Enter the code name of the app" APP_CODE_NAME validate_app_code_name \
        "Enter a short, unique 'code name' for this application. This name will be
        used to create the system user, group, systemd service file (e.g., \`app_code_name.service\`),
        Nginx configuration file, and the application directory (e.g., \`/var/www/app_code_name\`).
        Rules: Use only letters, numbers, hyphens (\`-\`), underscores (\`_\`), and periods (\`.\`).
        No spaces or other special characters. Keep it relatively short.
        Examples: \`my_cool_api\`, \`projectx-backend\`, \`webapp01\`."
    APP_DIR="/var/www/$APP_CODE_NAME" # Set APP_DIR globally for cleanup and other functions

    get_input "Enter the GitHub repo URL (HTTPS or SSH)" GITHUB_REPO validate_github_url \
        "Enter the full Git repository URL for your FastAPI application.
        HTTPS: \`https://github.com/your_username/your_repository.git\`
            (For private HTTPS, you'll be prompted for username/PAT).
        SSH:   \`git@github.com:your_username/your_repository.git\`
            (Requires SSH key setup on this server for the user \`$APP_CODE_NAME\`).
        NOTE: The script performs a shallow clone (\`--depth 1\`) for faster deployment."
    
    if [[ "$GITHUB_REPO" == "https://"* ]]; then
        get_input "Enter your GitHub username (optional, for private HTTPS repos)" GITHUB_USERNAME "" \
            "If your GitHub repository (using HTTPS URL) is private, enter your GitHub username.
            Public HTTPS Repo or SSH URL: Leave this blank and press Enter.
            This username, with a Personal Access Token (PAT), authenticates private repo cloning."
        if [ -n "$GITHUB_USERNAME" ]; then
            get_input "Enter your GitHub Personal Access Token (PAT)" GITHUB_PAT validate_not_empty \
                "If you provided a GitHub username for a private HTTPS repo, enter your PAT.
                Input is hidden for security.
                A PAT is like a password with specific scopes (permissions). Create one in your
                GitHub settings (Developer settings -> Personal access tokens).
                Required PAT scope: \`repo\` (to clone private repositories).
                This PAT is used only for \`git clone\` and not stored permanently." "" "true"
        else
            GITHUB_PAT="" # Ensure it's empty if username is blank
        fi
    fi
    
    get_input "Enter the domain name" DOMAIN_NAME validate_domain_name \
        "Enter the domain name (or subdomain) to access your application (e.g., \`api.example.com\`).
        Nginx will listen for requests on this domain.
        Important: You must own this domain and configure its DNS 'A' record (or 'CNAME')
        to point to this server's public IP address *after* successful deployment.
        SSL setup guidance will be provided later."

    local suggested_port
    suggested_port=$(generate_available_port) 

    if [ -n "$suggested_port" ]; then
        DEFAULT_APP_PORT="$suggested_port"
        color_echo "Suggested available port for the app (Uvicorn): $DEFAULT_APP_PORT"
    else
        color_echo "${YELLOW}Falling back to default port 8000 as an available one could not be automatically determined.${NC}"
        DEFAULT_APP_PORT=8000 
    fi

    # The get_input will then use this clean DEFAULT_APP_PORT
    get_input "Enter the port for the app to run on" APP_PORT validate_port \
        "Enter the internal port (1024-65535) for your FastAPI app (Uvicorn).
        This port is *not* directly public; Nginx proxies requests from port 80/443 to it.
        The script suggested \`$DEFAULT_APP_PORT\`. Using this is often a good choice.
        Ensure this port is not already in use. The script will check." "$DEFAULT_APP_PORT"

    # Crucial: After user provides APP_PORT (even if it's the suggested one), re-check it
    if check_port_in_use "$APP_PORT"; then # Use the global port check function
        echo -e "${RED}Error: Port $APP_PORT is already in use. Please choose a different port.${NC}"
        exit 1
    fi

    get_input "Enter Python module and FastAPI instance (e.g., main:app)" UVICORN_APP_MODULE validate_python_module_instance_format \
        "Specify the Python module path and the FastAPI application instance Uvicorn should run.
        Format: \`path.to.module:fastapi_instance_variable_name\`.
        Example 1 (Default): If your FastAPI app is in \`main.py\` and the instance is \`app = FastAPI()\`,
                    enter \`main:app\`.
        Example 2 (Package): If app is in \`my_project/api/server.py\` and instance is \`my_api = FastAPI()\`,
                    enter \`my_project.api.server:my_api\`.
        This corresponds to the \`APP\` argument for the \`uvicorn\` command." "$DEFAULT_UVICORN_APP_MODULE"

    get_input "Enter the number of Uvicorn workers" NUM_WORKERS validate_integer \
        "Enter the number of Uvicorn worker processes. These handle requests concurrently.
        Recommendation: \`(2 * number_of_CPU_cores) + 1\`. This server has $num_cores core(s).
        The script calculated a recommendation of: \`$recommended_workers\`.
        Considerations:
        - CPU-bound apps: More workers (up to recommendation) can help.
        - I/O-bound apps: Uvicorn is efficient; start with recommendation, adjust with load testing.
        - Memory: Each worker consumes memory. Too many can cause issues on low-RAM servers." "$DEFAULT_NUM_WORKERS"

    get_input "Enter Uvicorn concurrency limit" CONCURRENCY_LIMIT validate_integer \
        "Max concurrent connections/requests each Uvicorn worker will handle.
        Uvicorn uses \`asyncio\` for many connections per worker. This limits simultaneous handling.
        Default (\`$DEFAULT_CONCURRENCY_LIMIT\`) is high, suitable for I/O-bound apps (many waiting connections).
        If app has long, CPU-intensive tasks per request, a lower limit might ensure fairer distribution.
        Total concurrent capacity ~ \`NUM_WORKERS\` * \`CONCURRENCY_LIMIT\`." "$DEFAULT_CONCURRENCY_LIMIT"

    get_input "Enter Uvicorn backlog size" BACKLOG_SIZE validate_integer \
        "Max incoming connections the OS queues for Uvicorn if all workers are busy (TCP socket backlog).
        Default (\`$DEFAULT_BACKLOG_SIZE\`) is common for web servers.
        If clients get connection timeouts during high traffic spikes, increasing *might* help,
        but it's usually better to optimize the app or add workers.
        Setting too high can mask underlying performance issues." "$DEFAULT_BACKLOG_SIZE"

    get_input "Enter systemd Nice value for the app" NICE_VALUE validate_nice_value \
        "Set 'niceness' for your app's processes, influencing CPU scheduling priority.
        Range: \`-20\` (highest priority) to \`19\` (lowest priority). \`0\` is normal.
        Negative (e.g., \`-5\`): Higher priority. Use cautiously; can starve other system processes.
        Positive (e.g., \`5\`): Lower priority. Good for background/less critical tasks.
        Default (\`$DEFAULT_NICE_VALUE\`) is usually safe." "$DEFAULT_NICE_VALUE"

    get_input "Enter systemd CPUQuota" CPU_QUOTA validate_percentage \
        "Set a CPU usage limit for your application, as a percentage of *one CPU core's capacity*.
        How it works: \`CPUQuota=X%\` means your app can use up to \`X%\` of one CPU core's power.
        This server has $num_cores core(s).
        - On a single-core server: \`80%\` means 80% of total CPU.
        - On a multi-core server (like this one with $num_cores cores):
            - \`80%\` limits the app to 0.8 of *one* core's capacity.
            - To use up to 2 full cores, set \`200%\`.
            - To allow your \`$NUM_WORKERS\` workers to potentially use most of the $num_cores cores (e.g., 80% of total capacity),
            you might set this to \`$(($num_cores * 80))%\`.
        Default suggestion for this server: \`$DEFAULT_CPU_QUOTA\` (which is $DEFAULT_CPU_QUOTA of one core).
        Consider app needs and if other services run on this server." "$DEFAULT_CPU_QUOTA"

    get_input "Enter systemd MemoryMax" MEMORY_MAX "" \
        "Set the maximum RAM your application can use (e.g., \`512M\`, \`2G\`).
        Format: Suffixes \`K\` (Kilobytes), \`M\` (Megabytes), \`G\` (Gigabytes).
        The script suggests \`$DEFAULT_MEMORY_MAX\` based on system RAM (${TOTAL_MEM_MB}MB total).
        Too low: App might be killed by system (OOM killer).
        Too high on shared server: Can starve other apps.
        Python apps with multiple workers can use significant memory. Monitor actual usage and adjust." "$DEFAULT_MEMORY_MAX"

    get_input "Enter NGINX gzip compression level (1-9)" NGINX_GZIP_COMP_LEVEL validate_integer \
        "Nginx Gzip compression level for text responses (HTML, CSS, JS, JSON).
        Range: \`1\` (lowest compression, fastest) to \`9\` (highest, slowest, more CPU).
        Default (\`$DEFAULT_NGINX_GZIP_COMP_LEVEL\`) is a balance of compression & CPU usage.
        Levels 1-3: Light on CPU. Levels 7-9: More CPU for diminishing returns.
        For most apps, 4-6 is optimal. If CPU constrained, consider lower (e.g., 4)." "$DEFAULT_NGINX_GZIP_COMP_LEVEL"

    # --- SYSTEM PREPARATION ---
    check_update_system
    optimize_system_kernel
    check_install_nginx
    check_install_python_venv
    # Install Certbot automatically if in Easy Mode
    if [ "$INSTALLATION_MODE" = "Easy" ]; then
        check_install_certbot
    fi
    check_install_lsof # Added check for lsof

    if check_port_in_use "$APP_PORT"; then
        echo -e "${RED}Error: Port $APP_PORT is already in use. Please choose a different port.${NC}"
        exit 1
    fi

    # --- USER AND DIRECTORY SETUP ---
    color_echo "Creating system user '$APP_CODE_NAME' and group..."
    if ! sudo adduser --system --group --no-create-home --home "$APP_DIR" "$APP_CODE_NAME"; then # --no-create-home as we create $APP_DIR manually
        echo -e "${RED}Failed to create system user '$APP_CODE_NAME'. Check if user already exists or if you have sudo privileges.${NC}"
        exit 1
    fi
    sudo mkdir -p "$APP_DIR"
    sudo chown "$APP_CODE_NAME:$APP_CODE_NAME" "$APP_DIR"
    sudo chmod 750 "$APP_DIR" # Secure permissions

    # --- GIT CLONE ---
    clone_repository

    # --- PYTHON SETUP ---
    setup_python_env

    # --- SYSTEMD SERVICE ---
    create_systemd_service

    # --- NGINX CONFIGURATION ---
    create_nginx_config

    # Best effort to get a public IP. User might need to verify.
    SERVER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null)
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP="YOUR_SERVER_IP" # Fallback placeholder
    fi

    # --- FINAL MESSAGE ---
    echo -e "${GREEN}--------------------------------------------------------------------------${NC}"
    echo -e "${GREEN}Installation complete! Your FastAPI app '$APP_NICE_NAME' should be accessible soon.${NC}"
    echo -e "  System Name:    ${YELLOW}$APP_CODE_NAME${NC}"
    echo -e "  Domain:         ${YELLOW}http://$DOMAIN_NAME${NC} (and potentially https://$DOMAIN_NAME after SSL setup)"
    echo -e "  App Directory:  ${YELLOW}$APP_DIR${NC}"
    echo -e "  Service Status: ${YELLOW}sudo systemctl status $APP_CODE_NAME.service${NC}"
    echo -e "  Service Logs:   ${YELLOW}sudo journalctl -u $APP_CODE_NAME -f -e${NC}"
    if [ -n "$SERVER_IP" ] && [ "$SERVER_IP" != "YOUR_SERVER_IP" ]; then # Only show server IP if determined
        echo -e "  Server IP:      ${YELLOW}$SERVER_IP${NC} (use this for your DNS A record if setting up DNS manually)"
    fi
    echo -e "${GREEN}--------------------------------------------------------------------------${NC}"

    if [ "$INSTALLATION_MODE" = "Easy" ]; then
        echo -e "${YELLOW}Next Steps for Domain and SSL (Easy Mode Guidance):${NC}"
        echo "1.  **Point your domain to the server:**"
        if [ -n "$SERVER_IP" ] && [ "$SERVER_IP" != "YOUR_SERVER_IP" ]; then
            echo "    - Go to your domain registrar or DNS provider."
            echo "    - Create an 'A' record for '$DOMAIN_NAME' (and 'www.$DOMAIN_NAME' if desired) pointing to this server's IP address: $SERVER_IP"
            echo "    - DNS propagation can take some time (minutes to hours)."
        else
            echo "    - Go to your domain registrar or DNS provider."
            echo "    - Determine this server's public IP address."
            echo "    - Create an 'A' record for '$DOMAIN_NAME' (and 'www.$DOMAIN_NAME' if desired) pointing to this server's IP address."
            echo "    - DNS propagation can take some time (minutes to hours)."
        fi
        echo
        echo "2.  **Choose an SSL/HTTPS method (to secure your site with https://):**"
        echo "    a) **Using Let's Encrypt with Certbot (Installed during this setup):**"
        echo -e "       - Once DNS has propagated, run the following command: ${GREEN}sudo certbot --nginx -d $DOMAIN_NAME${NC}"
        echo -e "       - If you also want 'www.$DOMAIN_NAME', include it: ${GREEN}sudo certbot --nginx -d $DOMAIN_NAME -d www.$DOMAIN_NAME${NC}"
        echo "       - This installs a free SSL certificate directly on your server and configures Nginx for HTTPS."
        echo
        echo "    b) **Using Cloudflare (Flexible SSL - Easy Setup, Some Security Caveats):**"
        echo "       - Sign up for a free Cloudflare account at cloudflare.com."
        echo "       - Add your domain '$DOMAIN_NAME' to Cloudflare."
        echo "       - Cloudflare will provide you with new nameservers. Update your domain's nameservers at your registrar to point to Cloudflare's nameservers."
        echo "       - In your Cloudflare dashboard for '$DOMAIN_NAME', navigate to 'SSL/TLS' -> 'Overview'."
        echo "       - Select the **'Flexible'** SSL/TLS encryption mode."
        echo -e "       - ${YELLOW}Important Note:${NC} Flexible SSL means traffic between users and Cloudflare is encrypted, but traffic between Cloudflare and your server ($DOMAIN_NAME) remains HTTP (unencrypted)."
        echo "         This is easier to set up but less secure than Cloudflare's 'Full' or 'Full (Strict)' modes (which would require a certificate on your server, like one from Certbot)."
        echo
        echo "3.  **Test your application:**"
        echo "    - After DNS propagation and SSL setup (if chosen), visit http://$DOMAIN_NAME or https://$DOMAIN_NAME in your browser."
        echo
        echo "4.  **Monitor your application:**"
        echo "    - Use the service status and log commands provided above."
    else # Advanced Mode
        echo -e "${YELLOW}Next Steps (Advanced Mode):${NC}"
        echo -e "- Ensure your domain '$DOMAIN_NAME' is correctly pointed to this server's IP address."
        echo -e "- If using SSL (highly recommended), configure it for Nginx (e.g., using your own certificates, or a reverse proxy)."
        echo -e "- To use Let's Encrypt/Certbot (not installed by this script in Advanced mode):"
        echo -e "    Install it: ${GREEN}sudo apt update && sudo apt install certbot python3-certbot-nginx${NC}"
        echo -e "    Then run:   ${GREEN}sudo certbot --nginx -d $DOMAIN_NAME${NC}"
        echo -e "- Test your application by visiting http://$DOMAIN_NAME (or https://$DOMAIN_NAME if SSL is configured)."
        echo -e "- Monitor your application logs and server resources using the commands shown above."
    fi
    echo # Extra newline for spacing

    # Display Nice values of other user-installed apps (simple version)
    color_echo "Nice values of user processes (excluding root):"
    ps -eo nice,user:20,comm --sort=nice | awk '$2 != "root" && $2 != "USER" && NR > 1' | uniq | tail -n 20

    # Save the app code name to the registry
    save_app_code_name "$APP_CODE_NAME"

    # Mark install as successful BEFORE clearing APP_CODE_NAME for the EXIT trap

    ACTION_COMPLETED_APP_CLEARED="true"
    APP_CODE_NAME_SUCCESSFUL="$APP_CODE_NAME"
    APP_CODE_NAME=""
}

main
exit_status=$?
if [ $exit_status -eq 0 ] && [ -n "${APP_CODE_NAME_SUCCESSFUL:-}" ]; then
    echo -e "${GREEN}Deployment of '${APP_CODE_NAME_SUCCESSFUL}' was successful.${NC}"
else
    echo -e "${RED}Script encountered an error or was aborted.${NC}"
fi
exit $exit_status