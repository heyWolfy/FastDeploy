#!/bin/bash

# Function to get user input with validation and default values
get_input() {
    local prompt_text="${1:-}"
    local var_name="${2:-}"
    local validation_func="${3:-}"
    local original_explanation="${4:-}"
    local default_value="${5:-}"
    local is_sensitive="${6:-false}"
    local input_val

    # Clean the explanation: remove leading spaces and tabs from each line
    # The `echo "$original_explanation"` ensures multi-line strings are processed correctly by sed
    explanation=$(echo "$original_explanation" | sed 's/^[ \t]*//')

    if [ "$INSTALLATION_MODE" = "Easy" ] && [ -n "$default_value" ]; then
        printf -v "$var_name" '%s' "$default_value"
        echo "Using default value for $var_name: $default_value"
    else
        echo -e "${GREEN}$explanation${NC}"
        local effective_default="$default_value"
        
        local read_opts_array=()
        local sensitive_prompt_suffix=""

        if [ "$is_sensitive" = "true" ]; then
            read_opts_array+=(-s)
            sensitive_prompt_suffix=" (input hidden)" 
        fi

        if [ -n "$effective_default" ]; then
            local current_prompt_str 
            if [ "$is_sensitive" = "true" ]; then
                current_prompt_str="$prompt_text (default is set, input hidden): "
            else
                current_prompt_str="$prompt_text (default: $effective_default): "
            fi
            
            read -p "$current_prompt_str" "${read_opts_array[@]}" input_val
            if [ "$is_sensitive" = "true" ]; then echo; fi # Newline after sensitive input

            if [ -z "$input_val" ]; then
                input_val="$effective_default"
            fi
        else
            while true; do # Loop until valid input if no default or default not chosen
                read -p "$prompt_text$sensitive_prompt_suffix: " "${read_opts_array[@]}" input_val
                if [ "$is_sensitive" = "true" ]; then echo; fi
                if [ -n "$input_val" ]; then break; fi # Basic check: not empty
                echo -e "${RED}Input cannot be empty.${NC}"
            done
        fi

        # Validation loop
        if [ -n "$validation_func" ]; then
            while ! $validation_func "$input_val"; do
                echo -e "${RED}Invalid input. Please try again.${NC}"
                # For validation re-prompts, also use base prompt_text and append suffix if sensitive
                read -p "$prompt_text$sensitive_prompt_suffix: " "${read_opts_array[@]}" input_val
                if [ "$is_sensitive" = "true" ]; then echo; fi
                
                # If they entered nothing and there was a default, re-apply default and re-validate
                if [ -z "$input_val" ] && [ -n "$effective_default" ]; then
                    input_val="$effective_default"
                elif [ -z "$input_val" ]; then # If no default and empty input
                    echo -e "${RED}Input cannot be empty.${NC}"
                    continue # Re-prompt
                fi
            done
        fi
        printf -v "$var_name" '%s' "$input_val"
    fi

    if [ "$is_sensitive" = "false" ]; then
        echo -e "${YELLOW}$var_name set to: ${!var_name}${NC}"
    else
        echo -e "${YELLOW}$var_name has been set (value hidden).${NC}"
    fi
    echo # Add a newline for readability
}

# Validation functions
validate_port() {
    [[ $1 =~ ^[0-9]+$ ]] && [ "$1" -ge 1024 ] && [ "$1" -le 65535 ]
}
validate_integer() { [[ $1 =~ ^[0-9]+$ ]]; }
validate_percentage() { [[ $1 =~ ^[0-9]{1,3}%$ ]] && [ "${1%\%}" -ge 0 ] && [ "${1%\%}" -le 100 ]; } # Allow 0-100%
validate_nice_value() { [[ $1 =~ ^-?[0-9]+$ ]] && [ "$1" -ge -20 ] && [ "$1" -le 19 ]; }
validate_app_code_name() { [[ "$1" =~ ^[a-zA-Z0-9_.-]+$ ]] && [[ ! "$1" =~ \.\. ]]; } # Basic validation
validate_domain_name() { [[ "$1" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; } # Basic domain check
validate_not_empty() { [ -n "$1" ]; } # Simple not empty validation
validate_github_url() {
    [[ "$1" =~ ^https://github\.com/.+/.+(\.git)?$ ]] || [[ "$1" =~ ^git@github\.com:.+/.+(\.git)?$ ]];
}
validate_python_module_instance_format() {
    [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*:[a-zA-Z_][a-zA-Z0-9_]*$ ]]
}
