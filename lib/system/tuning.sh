#!/bin/bash

# --- NEW FUNCTION: Kernel & System Tuning ---
optimize_system_kernel() {
    color_echo "Applying System & Kernel Optimizations..."

    # 1. SYSCTL TUNING (Network Stack)
    local SYSCTL_CONF="/etc/sysctl.conf"
    local OPTIMIZATIONS=(
        "net.core.somaxconn 65535"
        "net.core.netdev_max_backlog 65535"
        "net.ipv4.tcp_max_syn_backlog 65535"
        "net.ipv4.tcp_tw_reuse 1"
        "net.ipv4.ip_local_port_range 1024 65535"
        "fs.file-max 2097152"
        "vm.swappiness 10"
        "net.core.default_qdisc fq"
        "net.ipv4.tcp_congestion_control bbr"
    )

    for setting in "${OPTIMIZATIONS[@]}"; do
        key=$(echo "$setting" | awk '{print $1}')
        val=$(echo "$setting" | awk '{print $2}')
        if grep -q "^$key" "$SYSCTL_CONF"; then
            sudo sed -i "s/^$key.*/$key = $val/" "$SYSCTL_CONF"
        else
            echo "$key = $val" | sudo tee -a "$SYSCTL_CONF" > /dev/null
        fi
    done
    sudo sysctl -p > /dev/null 2>&1 || true

    # 2. USER LIMITS (File Descriptors)
    local LIMITS_CONF="/etc/security/limits.conf"
    if ! grep -q "root soft nofile 65535" "$LIMITS_CONF"; then
        echo "* soft nofile 65535" | sudo tee -a "$LIMITS_CONF" > /dev/null
        echo "* hard nofile 65535" | sudo tee -a "$LIMITS_CONF" > /dev/null
        echo "root soft nofile 65535" | sudo tee -a "$LIMITS_CONF" > /dev/null
        echo "root hard nofile 65535" | sudo tee -a "$LIMITS_CONF" > /dev/null
    fi
    color_echo "System Optimized (BBR enabled, Limits increased)."
}
