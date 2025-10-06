# DataMiner Site Manager

This documentation describes how to install and uninstall the required **zrok-agent** component for DataMiner Site Manager on Windows and Linux systems.

## Windows

**Script:** `Setup-DataMinerSiteManager.ps1`

A PowerShell script to install the **zrok-agent** as a Windows service.

**Requirements:**

- Windows 10 or Windows Server 2019 (build 17134 or later)
- Must run the script as Administrator

<pre>
Usage:
    .\Setup-DataMinerSiteManager.ps1 -Command &lt;install|uninstall|help&gt; -AccountToken &lt;AccountToken&gt; -SiteName &lt;SiteName&gt;

Commands:
    install     Installs the zrok-agent as a Windows service.
                Requires -AccountToken and -SiteName.
    uninstall   Uninstalls the zrok-agent service and cleans up.
    help        Shows this help message.

Examples:
    .\Setup-DataMinerSiteManager.ps1 -Command install -AccountToken 3G67gmYPhaww -SiteName "Skyline HQ"
    .\Setup-DataMinerSiteManager.ps1 -Command uninstall
</pre>;

## Linux

**Script:** `Setup-DataMinerSiteManager.sh`

A Bash script to install the **zrok-agent** as a systemd service.

**Requirements:**

- Linux distribution using systemd as the service manager
- Must run the script via sudo

<pre>
Usage:
    sudo ./Setup-DataMinerSiteManager.sh install &lt;AccountToken&gt; "&lt;SiteName&gt;"
    sudo ./Setup-DataMinerSiteManager.sh uninstall
    sudo ./Setup-DataMinerSiteManager.sh help

Commands:
    install     Installs the zrok-agent as a systemd service.
                Requires &lt;AccountToken&gt; and &lt;SiteName&gt;.
    uninstall   Uninstalls the zrok-agent service and cleans up.
    help        Shows this help message.

Examples:
    sudo ./Setup-DataMinerSiteManager.sh install 3G67gmYPhaww "Skyline HQ"
    sudo ./Setup-DataMinerSiteManager.sh uninstall
</pre>
