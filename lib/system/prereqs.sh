#!/bin/bash

# Function to Check and Update system packages
check_update_system() {
    execute_quietly "Updating package lists" sudo apt-get update -y
    if [ "$(apt list --upgradable 2>/dev/null | grep -vc "Listing...")" -gt 0 ]; then
        color_echo "Package updates are available."
        execute_quietly "Upgrading system packages" sudo apt-get upgrade -y
        execute_quietly "Performing system cleanup (autoremove)" sudo apt-get autoremove -y
        color_echo "System update and upgrade process finished."
    else
        color_echo "No updates available. System is up to date."
    fi
}

# Function to check and install nginx
check_install_nginx() {
    if ! command -v nginx &> /dev/null; then
        execute_quietly "Installing Nginx" sudo apt-get install -y nginx
    else
        color_echo "Nginx is already installed."
    fi

    color_echo "Ensuring Nginx is enabled and started..."
    if ! sudo systemctl enable --now nginx; then 
        echo -e "${RED}Failed to start or enable Nginx. Aborting.${NC}"
        exit 1
    fi
    color_echo "Nginx is running."
}

# Function to check and install Certbot and its Nginx plugin
check_install_certbot() {
    if ! command -v certbot &> /dev/null; then
        if ! dpkg -s python3-certbot-nginx &> /dev/null; then
            color_echo "Certbot or its Nginx plugin not found. Installing..."
            execute_quietly "Installing Certbot and Nginx plugin (certbot python3-certbot-nginx)" sudo apt-get install -y certbot python3-certbot-nginx
        else
            execute_quietly "Installing Certbot" sudo apt-get install -y certbot
        fi
    else
        color_echo "Certbot is already installed."
    fi
}

# Function to check and install python3-venv
check_install_python_venv() {
    if ! dpkg -s python3-venv &> /dev/null; then
        execute_quietly "Installing python3-venv" sudo apt-get install -y python3-venv
    else
        color_echo "python3-venv is already installed."
    fi
}

check_install_lsof() {
    if ! command -v lsof &> /dev/null; then
        execute_quietly "Installing lsof for port checking" sudo apt-get install -y lsof
    fi
}
