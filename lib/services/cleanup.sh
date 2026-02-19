#!/bin/bash

function uninstall_app() {
    get_input "Enter the app code name to uninstall" APP_CODE_NAME validate_app_code_name \
            "Enter the unique 'code name' of the application you wish to uninstall.
            This is the short, system-level name (e.g., \`my_cool_api\`, \`project_x_backend\`)
            used when the application was initially installed. It identifies its systemd
            service, Nginx configuration, system user, and application directory
            (e.g., /var/www/app_code_name)."
    if [ -z "$APP_CODE_NAME" ]; then
        echo -e "${RED}No app code name provided or obtained. Cannot proceed with uninstall.${NC}"
        exit 1 
    fi

    APP_DIR="/var/www/$APP_CODE_NAME" 
    echo -e "${YELLOW}You are about to uninstall '$APP_CODE_NAME'. This will remove:"
    echo "- Systemd service: $APP_CODE_NAME.service"
    echo "- Nginx site: $APP_CODE_NAME"
    echo "- System user: $APP_CODE_NAME"
    echo "- Application directory: $APP_DIR"
    
    local confirm_uninstall=""
    read -p "Are you sure you want to proceed? [y/N]: " confirm_uninstall
    
    if [[ $confirm_uninstall =~ ^[Yy]$ ]]; then
        cleanup 
        echo -e "${GREEN}Uninstallation complete for '$APP_CODE_NAME'${NC}"
        ACTION_COMPLETED_APP_CLEARED="true" 
        APP_CODE_NAME="" 
        SCRIPT_EXITING_CLEANLY_AFTER_USER_ACTION="true" 
    else
        echo -e "${YELLOW}Uninstallation cancelled.${NC}"
        SCRIPT_EXITING_CLEANLY_AFTER_USER_ACTION="true" 
    fi
    exit 0 
}
