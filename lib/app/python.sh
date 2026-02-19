#!/bin/bash

setup_python_env() {
    # --- REQUIREMENTS FILE HANDLING ---
    REQUIREMENTS_FILE_NAME="requirements.txt"
    SKIP_REQUIREMENTS_INSTALL=false
    local ESSENTIAL_DEPS="uvloop httptools" # Always install these for uvicorn

    # Check if default requirements.txt exists in the cloned repo
    # Running test -f as the app user inside the app directory
    if ! sudo -u "$APP_CODE_NAME" bash -c "cd '$APP_DIR' && test -f '$REQUIREMENTS_FILE_NAME'"; then
        color_echo "File '$REQUIREMENTS_FILE_NAME' not found in '$APP_DIR'."

        if [ "$INSTALLATION_MODE" = "Easy" ]; then
            color_echo "Easy Mode: Skipping project-specific dependencies as '$REQUIREMENTS_FILE_NAME' is missing."
            SKIP_REQUIREMENTS_INSTALL=true
        else # Advanced mode, ask the user
            while true; do
                read -p "Skip project dependencies, specify file, or abort? (Skip/File/Abort) [S/f/a, default: A]: " req_action
                req_action_lower=$(echo "${req_action:-A}" | tr '[:upper:]' '[:lower:]') # Default to Abort

                if [[ "$req_action_lower" == "s" || "$req_action_lower" == "skip" ]]; then
                    SKIP_REQUIREMENTS_INSTALL=true
                    color_echo "Skipping project-specific dependency installation."
                    break
                elif [[ "$req_action_lower" == "f" || "$req_action_lower" == "file" ]]; then
                    read -p "Enter the name of your requirements file (e.g., requirements-dev.txt): " new_req_file
                    if [ -z "$new_req_file" ]; then
                        echo -e "${RED}File name cannot be empty.${NC}"
                        continue
                    fi
                    if sudo -u "$APP_CODE_NAME" bash -c "cd '$APP_DIR' && test -f '$new_req_file'"; then
                        REQUIREMENTS_FILE_NAME="$new_req_file"
                        color_echo "Using '$REQUIREMENTS_FILE_NAME' for project dependencies."
                        break
                    else
                        color_echo "${RED}File '$new_req_file' not found in '$APP_DIR'. Please try again.${NC}"
                    fi
                elif [[ "$req_action_lower" == "a" || "$req_action_lower" == "abort" ]]; then
                    echo -e "${RED}Aborting installation due to requirements file issue.${NC}"
                    exit 1
                else
                    echo -e "${RED}Invalid choice. Please enter 'S' (Skip), 'F' (File), or 'A' (Abort).${NC}"
                fi
            done
        fi
    fi

    # --- PYTHON VIRTUAL ENVIRONMENT AND DEPENDENCIES ---
    execute_quietly "Creating Python virtual environment in $APP_DIR/venv" sudo -u "$APP_CODE_NAME" bash -c "cd '$APP_DIR' && python3 -m venv venv"
    color_echo "Virtual environment created."

    color_echo "Preparing to install Python dependencies..."

    # --- PIP INSTALLATION ---
    local PIP_INSTALL_CMD_BASE="source venv/bin/activate && pip install --no-cache-dir -q"

    local FULL_PIP_INSTALL_STRING=""
    if [ "$SKIP_REQUIREMENTS_INSTALL" = "false" ]; then
        color_echo "Project dependencies will be installed from '$REQUIREMENTS_FILE_NAME' along with essential packages."
        FULL_PIP_INSTALL_STRING="${PIP_INSTALL_CMD_BASE} -r '$REQUIREMENTS_FILE_NAME' && ${PIP_INSTALL_CMD_BASE} ${ESSENTIAL_DEPS}"
    else
        # This message is fine too
        color_echo "Skipping project-specific dependencies. Installing only essential packages: $ESSENTIAL_DEPS."
        FULL_PIP_INSTALL_STRING="${PIP_INSTALL_CMD_BASE} ${ESSENTIAL_DEPS}"
    fi

    color_echo "Installing Python dependencies (using pip -q, this may take a moment)..."
    local pip_command_to_execute="cd '$APP_DIR' && $FULL_PIP_INSTALL_STRING"
    local pip_output
    # Capture combined output to check if pip -q still produced anything (e.g., warnings)
    pip_output=$(sudo -u "$APP_CODE_NAME" bash -c "$pip_command_to_execute" 2>&1)
    local pip_status=$?

    if [ $pip_status -ne 0 ]; then
        echo -e "${RED}Failed to install Python dependencies.${NC}"
        echo -e "${YELLOW}Command executed: sudo -u \"$APP_CODE_NAME\" bash -c \"$pip_command_to_execute\"${NC}"
        echo -e "${YELLOW}Output from pip (even with -q, errors/warnings might appear):${NC}"
        echo "$pip_output" # Show the captured output from pip
        echo -e "${YELLOW}Consider running the pip commands manually without '-q' inside the venv for more details.${NC}"
        exit 1
    fi

    # Check if pip_output has anything significant. pip -q should be silent on success.
    if [ -z "$pip_output" ] || [[ "$pip_output" =~ ^WARNING:\ You\ are\ using\ pip\ version.* ]]; then # Ignore common pip version warning
         color_echo "Python dependencies installed successfully."
    else
         color_echo "Python dependencies installed. pip produced some output (e.g., warnings):"
         echo -e "${NC}$pip_output${NC}" # Show other minor warnings if any, reset color
    fi
    
    # Permissions for venv are usually fine if created by the user, but chown doesn't hurt.
    sudo chown -R "$APP_CODE_NAME:$APP_CODE_NAME" "$APP_DIR/venv" 
}
