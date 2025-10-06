#!/bin/bash
set -euo pipefail

SERVICE_NAME="zrok-agent"
BINARIES_DIRECTORY="/opt/skyline-communications/dataminer-sitemanager/zrok"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

assert_sudo() {
    if [[ $EUID -ne 0 ]]; then
        echo "Setup script must be run with sudo, not as a regular user." >&2
        exit 1
    fi
    if [[ -z "${SUDO_USER-}" ]]; then
        echo "Setup script must be run with sudo, not as root directly." >&2
        exit 1
    fi
}
assert_no_placeholder_values() {
    if [[ "$1" == "<token>" || "$2" == "<description>" ]]; then
        echo "ERROR: You must replace the placeholder values <token> and <description> with your actual zrok account token and environment description."
        echo "Example:"
        echo "    sudo ./Setup-DataMinerSiteManager.sh install 3G67gmYPhaww \"Skyline HQ\""
        exit 1
    fi
}

install_zrok_agent() {
    assert_sudo
    TOKEN="$1"
    DESCRIPTION="$2"
    assert_no_placeholder_values "$TOKEN" "$DESCRIPTION"

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "Service already installed."
        exit 0
    fi

    local readonly ZROK_VERSION="1.1.5"
    local readonly MODULE_NAME="dataminer-sitemanager"

    local download_directory=/var/tmp/skyline-communications/${MODULE_NAME}
    mkdir -p "$download_directory"

    local zrok_download_file_name="zrok_${ZROK_VERSION}_linux_amd64.tar.gz"
    local zrok_download_path="${download_directory}/${zrok_download_file_name}"
    local zrok_download_url="https://github.com/openziti/zrok/releases/download/v${ZROK_VERSION}/${zrok_download_file_name}"

    echo "Downloading zrok version ${ZROK_VERSION}..."
    curl -L -o "$zrok_download_path" --progress-bar "$zrok_download_url"

    tar -xzf "$zrok_download_path" -C "$download_directory"

    mkdir -p "$BINARIES_DIRECTORY"
    mv "${download_directory}/zrok" "${BINARIES_DIRECTORY}/zrok"
    mv "${download_directory}/LICENSE" "${BINARIES_DIRECTORY}/LICENSE"

    rm -rf "$download_directory"
    rmdir --ignore-fail-on-non-empty /var/tmp/skyline-communications 2>/dev/null || true

    ln -sf /opt/skyline-communications/dataminer-sitemanager/zrok/zrok /usr/local/bin/zrok

    runuser -u "$SUDO_USER" -- bash -lc "zrok config set apiEndpoint https://api.zrok.dataminer.services && zrok enable \"$TOKEN\" --description \"$DESCRIPTION\""

    echo "Creating systemd service..."
    cat <<EOF > "$SYSTEMD_SERVICE_FILE"
[Unit]
Description=Zrok Agent Service

[Service]
ExecStart=zrok agent start
Restart=always
User=$SUDO_USER

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$SERVICE_NAME"
    echo "${SERVICE_NAME} service installed and started."
}

uninstall_zrok_agent() {
    assert_sudo
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "Service ${SERVICE_NAME} is not installed."
        exit 0
    fi

    local service_user=$(ps -o user= -p $(systemctl show -p MainPID --value ${SERVICE_NAME}))
    echo "Disabling the zrok environment..."
    runuser -u "$SUDO_USER" -- bash -lc "zrok disable"

    echo "Stopping and removing the ${SERVICE_NAME} service..."
    systemctl stop "$SERVICE_NAME"
    systemctl disable "$SERVICE_NAME"
    rm -f "$SYSTEMD_SERVICE_FILE"
    systemctl daemon-reload

    rm "/usr/local/bin/zrok"
    rm -rf "/home/${service_user}/.zrok"
    echo "Cleaning up binaries..."
    rm -rf "$BINARIES_DIRECTORY"
    rmdir --ignore-fail-on-non-empty "/opt/skyline-communications/dataminer-sitemanager" 2>/dev/null || true
    rmdir --ignore-fail-on-non-empty "/opt/skyline-communications" 2>/dev/null || true
    echo "Uninstall complete."
}

show_help() {
    cat <<EOF
Usage:
    sudo ./Setup-DataMinerSiteManager.sh install <token> "<description>"
    sudo ./Setup-DataMinerSiteManager.sh uninstall
    sudo ./Setup-DataMinerSiteManager.sh help

Commands:
    install     Installs the ${SERVICE_NAME} as a systemd service.
                Requires <token> and <description>.
    uninstall   Uninstalls the ${SERVICE_NAME} service and cleans up.
    help        Shows this help message.

Examples:
    sudo ./Setup-DataMinerSiteManager.sh install 3G67gmYPhaww "Skyline HQ"
    sudo ./Setup-DataMinerSiteManager.sh uninstall
EOF
}

COMMAND="${1:-}"
case "$COMMAND" in
    install)
        if [[ $# -ne 3 ]]; then
            echo "ERROR: install requires <token> and <description>."
            show_help
            exit 1
        fi
        install_zrok_agent "$2" "$3"
        ;;
    uninstall)
        uninstall_zrok_agent
        ;;
    help|*)
        show_help
        ;;
esac