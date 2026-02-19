#!/bin/bash

clone_repository() {
    # --- GIT CLONE ---
    color_echo "Cloning repository from $GITHUB_REPO into $APP_DIR..."
    local CLONE_CMD="git clone --depth 1 $GITHUB_REPO $APP_DIR" # Shallow clone for speed
    if [[ "$GITHUB_REPO" == "https://"* ]] && [ -n "$GITHUB_USERNAME" ] && [ -n "$GITHUB_PAT" ]; then
        # For private HTTPS repositories
        local AUTH_REPO_URL=$(echo "$GITHUB_REPO" | sed "s|https://|https://$GITHUB_USERNAME:$GITHUB_PAT@|")
        CLONE_CMD="git clone --depth 1 $AUTH_REPO_URL $APP_DIR"
    fi

    # Execute clone as the app user to ensure correct permissions from the start
    # Redirect stderr to stdout to capture git errors, then check status
    local clone_output
    clone_output=$(sudo -u "$APP_CODE_NAME" bash -c "$CLONE_CMD" 2>&1)
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to clone repository:${NC}"
        echo "$clone_output"
        echo -e "${RED}Check repository URL, permissions, or network connectivity.${NC}"
        exit 1 # Cleanup will be triggered
    fi
    color_echo "Repository cloned successfully."
}
