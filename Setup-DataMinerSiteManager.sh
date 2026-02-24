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
    if [[ "$1" == "<AccountToken>" || "$2" == "<SiteName>" ]]; then
        echo "You must replace the placeholder values <AccountToken> and <SiteName> with your actual account token and site name."
        echo "Example:"
        echo "    sudo ./Setup-DataMinerSiteManager.sh install 3G67gmYPhaww \"Skyline HQ\""
        exit 1
    fi
}

install_zrok_agent() {
    assert_sudo
    local -r account_token="$1"
    local -r site_name="$2"

    assert_no_placeholder_values "$account_token" "$site_name"

    if systemctl status "$SERVICE_NAME" &>/dev/null; then
        echo "Service ${SERVICE_NAME} is already installed."
        exit 0
    fi

    local -r ZROK_VERSION="1.1.5"
    local -r MODULE_NAME="dataminer-sitemanager"

    local download_directory=/var/tmp/skyline-communications/${MODULE_NAME}
    mkdir -p "$download_directory"

    local zrok_download_file_name="zrok_${ZROK_VERSION}_linux_amd64.tar.gz"
    local zrok_download_path="${download_directory}/${zrok_download_file_name}"
    local zrok_download_url="https://github.com/openziti/zrok/releases/download/v${ZROK_VERSION}/${zrok_download_file_name}"

    echo "Downloading zrok version ${ZROK_VERSION}..."
    curl -L --fail -o "$zrok_download_path" --progress-bar "$zrok_download_url"

    tar -xzf "$zrok_download_path" -C "$download_directory"

    mkdir -p "$BINARIES_DIRECTORY"
    mv "${download_directory}/zrok" "${BINARIES_DIRECTORY}/zrok"
    mv "${download_directory}/LICENSE" "${BINARIES_DIRECTORY}/LICENSE"

    echo "Deleting the downloaded files..."
    rm -rf "$download_directory"
    rmdir --ignore-fail-on-non-empty /var/tmp/skyline-communications 2>/dev/null || true

    ln -sf /opt/skyline-communications/dataminer-sitemanager/zrok/zrok /usr/local/bin/zrok

    runuser -u "$SUDO_USER" -- bash -lc "zrok config set apiEndpoint https://api.zrok.dataminer.services && zrok enable \"$account_token\" --description \"$site_name\""

    echo "Installing the ${SERVICE_NAME} service..."
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
    echo "The ${SERVICE_NAME} service is installed and started."
    echo "Installation completed successfully."
}

uninstall_zrok_agent() {
    assert_sudo
    if ! systemctl status "$SERVICE_NAME" &>/dev/null; then
        echo "Service ${SERVICE_NAME} is not installed."
        exit 0
    fi

    local service_user=$(ps -o user= -p $(systemctl show -p MainPID --value ${SERVICE_NAME}))
    echo "Disabling the zrok environment..."
    runuser -u "$SUDO_USER" -- bash -lc "zrok disable"

    echo "Stopping the ${SERVICE_NAME} service..."
    systemctl stop "$SERVICE_NAME"

    echo "Disabling the ${SERVICE_NAME} service..."
    systemctl disable "$SERVICE_NAME"

    echo "Deleting the ${SERVICE_NAME} service..."
    rm -f "$SYSTEMD_SERVICE_FILE"
    systemctl daemon-reload

    echo "Cleaning up the zrok profile..."
    rm "/usr/local/bin/zrok"
    rm -rf "/home/${service_user}/.zrok"

    echo "Cleaning up the binaries folder..."
    rm -rf "$BINARIES_DIRECTORY"
    rmdir --ignore-fail-on-non-empty "/opt/skyline-communications/dataminer-sitemanager" 2>/dev/null || true
    rmdir --ignore-fail-on-non-empty "/opt/skyline-communications" 2>/dev/null || true

    echo "Uninstallation completed successfully."
}

show_help() {
    cat <<EOF
Usage:
    sudo ./Setup-DataMinerSiteManager.sh install <AccountToken> "<SiteName>"
    sudo ./Setup-DataMinerSiteManager.sh uninstall
    sudo ./Setup-DataMinerSiteManager.sh help

Commands:
    install     Installs the ${SERVICE_NAME} as a systemd service.
                Requires <AccountToken> and <SiteName>.
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
        if [[ $# -eq 1 ]]; then
            echo "An account token needs to be passed in order to complete the installation."
            show_help
            exit 1
        fi
        if [[ $# -eq 2 ]]; then
            echo "A site name needs to be passed in order to complete the installation."
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