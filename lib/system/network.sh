#!/bin/bash

# Function to check if a port is in use
check_port_in_use() {
    if sudo lsof -Pi :"$1" -sTCP:LISTEN -t >/dev/null ; then
        return 0 # In use
    else
        return 1 # Not in use
    fi
}

generate_available_port() {
    local port
    local max_attempts=50
    local attempt=0
    # Send this informational message to stderr so it doesn't get captured by command substitution
    echo -e "${YELLOW}[INFO] Attempting to find an available random port...${NC}" >&2 

    while [ "$attempt" -lt "$max_attempts" ]; do
        port=$(( ( RANDOM % (65535 - 1024 + 1) ) + 1024 )) # Ports 1024-65535

        local is_known_service_port=false
        for known_port in "${KNOWN_SERVICE_PORTS[@]}"; do
            if [ "$port" -eq "$known_port" ]; then
                is_known_service_port=true
                break
            fi
        done

        if [ "$is_known_service_port" = true ]; then
            attempt=$((attempt + 1))
            continue # Skip known service ports
        fi

        if ! check_port_in_use "$port"; then # If NOT in use
            echo "$port" # THIS is the only stdout output for successful port finding
            return 0 # Success
        fi
        attempt=$((attempt + 1))
    done
    # Fallback if no port found after attempts
    echo -e "${RED}[ERROR] Could not automatically find an available port after $max_attempts attempts.${NC}" >&2
    echo "" # Return empty on stdout to indicate failure
    return 1 # Failure
}
