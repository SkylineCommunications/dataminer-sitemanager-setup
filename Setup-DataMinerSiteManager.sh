#!/bin/bash

SERVICE_NAME="zrok-agent"
ZROK_VERSION="1.0.7"
MODULE_NAME="DataMiner SiteManager"
BINARIES_DIR="/opt/skyline/dataminer-sitemanager/zrok"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

function show_help {
    cat <<EOF
Usage:
    sudo ./Setup-DataMinerSiteManager.sh install <token> "<description>"
    sudo ./Setup-DataMinerSiteManager.sh uninstall
    sudo ./Setup-DataMinerSiteManager.sh help

Commands:
    install     Installs the zrok-agent as a systemd service.
                Requires <token> and <description>.
    uninstall   Uninstalls the zrok-agent service and cleans up.
    help        Shows this help message.

Examples:
    sudo ./Setup-DataMinerSiteManager.sh install 3G67gmYPhaww "Skyline HQ"
    sudo ./Setup-DataMinerSiteManager.sh uninstall
EOF
}

function assert_no_placeholder_values {
    if [[ "$1" == "<token>" || "$2" == "<description>" ]]; then
        echo "ERROR: You must replace the placeholder values <token> and <description> with your actual zrok account token and environment description."
        echo "Example:"
        echo "    sudo ./Setup-DataMinerSiteManager.sh install 3G67gmYPhaww \"Skyline HQ\""
        exit 1
    fi
}

function install_zrok_agent {
    TOKEN="$1"
    DESCRIPTION="$2"
    assert_no_placeholder_values "$TOKEN" "$DESCRIPTION"

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "Service already installed."
        exit 0
    fi

    mkdir -p "$BINARIES_DIR"
    cd "$BINARIES_DIR"

    ZROK_FILENAME="zrok_${ZROK_VERSION}_linux_amd64.tar.gz"
    ZROK_URL="https://github.com/openziti/zrok/releases/download/v${ZROK_VERSION}/${ZROK_FILENAME}"

    echo "Downloading zrok version ${ZROK_VERSION}..."
    curl -L -o "$ZROK_FILENAME" "$ZROK_URL"
    tar -xzf "$ZROK_FILENAME"
    rm "$ZROK_FILENAME"

    chmod +x zrok

    ./zrok config set apiEndpoint https://api.zrok.dataminer.services
    ./zrok enable "$TOKEN" --description "$DESCRIPTION"

    echo "Creating systemd service..."
    cat <<SERVICE > "$SYSTEMD_SERVICE_FILE"
[Unit]
Description=Zrok Agent Service

[Service]
ExecStart=$BINARIES_DIR/zrok agent start
Restart=always
User=root

[Install]
WantedBy=multi-user.target
SERVICE

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
    echo "zrok-agent service installed and started."
}

function uninstall_zrok_agent {
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "Service zrok-agent is not installed."
        exit 0
    fi

    echo "Disabling the zrok environment..."
    "$BINARIES_DIR/zrok" disable

    echo "Stopping and removing the zrok-agent service..."
    systemctl stop "$SERVICE_NAME"
    systemctl disable "$SERVICE_NAME"
    rm -f "$SYSTEMD_SERVICE_FILE"
    systemctl daemon-reload

    echo "Cleaning up binaries..."
    rm -rf "$BINARIES_DIR"
    echo "Uninstall complete."
}

COMMAND="$1"
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