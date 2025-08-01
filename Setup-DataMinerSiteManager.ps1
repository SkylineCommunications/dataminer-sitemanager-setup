param(
    [string]$Command = "help",
    [string]$ZrokAccountToken,
    [string]$ZrokEnvironmentDescription
)

$SERVICE_NAME = "zrok-agent"

function Initialize-ScriptContext {
    $script:BinariesDirectory = [System.IO.Path]::Combine($env:ProgramW6432, "Skyline Communications", "DataMiner SiteManager", "zrok")
    $script:SystemProfilePath = Join-Path $env:SystemRoot "System32\config\systemprofile"
    $script:MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine") -split ";" | Where-Object { $_.Trim() -ne "" }
    $env:USERPROFILE = $SystemProfilePath
}

function Assert-WindowsVersionRequirement {
    # The Windows version Unix domain sockets got added to on which zrok-agent has a dependency.
    $MinimumSupportedVersion = [System.Version]"10.0.17134"

    $OperatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
    $Version = [System.Version]$OperatingSystem.Version

    if ($Version -lt $MinimumSupportedVersion) {
        Write-Host "Unsupported OS version: $Version. Requires Windows 10 / Windows Server 2019 or later."
        Exit
    }
}

function Assert-AdministratorRoleRequirement {
    $IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if(-not $IsAdministrator) {
        Write-Host "Setup script needs to run as administrator."
        Exit
    }
}

function Assert-ZrokAccountTokenRequirement {
    if(-not $ZrokAccountToken) {
        Write-Host "A zrok account token needs to be passed in order to complete the installation."
        Exit
    }
}

function Assert-ZrokEnvironmentDescriptionRequirement {
    if(-not $ZrokEnvironmentDescription) {
        Write-Host "A zrok environment description needs to be passed in order to complete the installation."
        Exit
    }
}

function Test-ZrokAgentServiceExists {
    return [bool](Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue)
}

function Install-ZrokAgent {
    Assert-WindowsVersionRequirement
    Assert-AdministratorRoleRequirement
    Assert-ZrokAccountTokenRequirement
    Assert-ZrokEnvironmentDescriptionRequirement

    if(Test-ZrokAgentServiceExists) {
        Write-Host "Service already installed."
        Exit
    }

    $ZROK_VERSION = "1.0.7"
    $NSSM_VERSION = "2.24"
    $MODULE_NAME = "DataMiner SiteManager"

    Initialize-ScriptContext

    $DownloadDirectory = [System.IO.Path]::Combine($env:TEMP, "Skyline Communications", $MODULE_NAME)
    New-Item -ItemType Directory -Path $DownloadDirectory -Force | Out-Null

    $ZrokDownloadFileName = "zrok_${ZROK_VERSION}_windows_amd64.tar.gz"
    $ZrokDownloadPath = [System.IO.Path]::Combine($DownloadDirectory, $ZrokDownloadFileName)
    $ZrokDownloadUrl = "https://github.com/openziti/zrok/releases/download/v${ZROK_VERSION}/${ZrokDownloadFileName}"

    Write-Host "Downloading zrok version ${ZROK_VERSION}"...
    curl.exe -L -o $ZrokDownloadPath --progress-bar $ZrokDownloadUrl

    $NssmDownloadFileName = "nssm-${NSSM_VERSION}.zip"
    $NssmDownloadPath = [System.IO.Path]::Combine($DownloadDirectory, $NssmDownloadFileName)
    $NssmDownloadUrl = "https://nssm.cc/release/${NssmDownloadFileName}"

    Write-Host "Downloading nssm version ${NSSM_VERSION}"...
    curl.exe -L -o $NssmDownloadPath --progress-bar $NssmDownloadUrl

    tar -xzf $ZrokDownloadPath -C $DownloadDirectory
    Expand-Archive -Path $NssmDownloadPath -DestinationPath $DownloadDirectory -Force

    New-Item -ItemType Directory -Path $script:BinariesDirectory -Force | Out-Null

    Get-ChildItem -Path $DownloadDirectory -Recurse -Include *.exe, LICENSE | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $script:BinariesDirectory -Force
    }

    Write-Host "Deleting the downloaded files..."
    Remove-Item -Path $DownloadDirectory -Recurse -Force

    if (-not ($script:MachinePath -contains $script:BinariesDirectory)) {
        $NewMachinePath = ($script:MachinePath + $script:BinariesDirectory) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $NewMachinePath, "Machine")
        $env:Path = $NewMachinePath
    }

    zrok.exe config set apiEndpoint https://api.zrok.dataminer.services
    zrok.exe enable $ZrokAccountToken --description $ZrokEnvironmentDescription

    Write-Host "Installing the zrok-agent service..."

    nssm.exe install zrok-agent "${script:BinariesDirectory}\zrok.exe" agent start
    nssm.exe set zrok-agent AppDirectory $script:SystemProfilePath
    nssm.exe set zrok-agent AppStdout "${script:SystemProfilePath}\.zrok\agent-stdout.log"
    nssm.exe set zrok-agent AppStderr "${script:SystemProfilePath}\.zrok\agent-stderr.log"

    sc.exe config zrok-agent start=delayed-auto
    sc.exe start zrok-agent
}

function Uninstall-ZrokAgent {
    Assert-AdministratorRoleRequirement
    if(-not (Test-ZrokAgentServiceExists)) {
        Write-Host "Service zrok-agent is not installed."
        Exit
    }

    Initialize-ScriptContext

    Write-Host "Disabling the zrok environment..."
    zrok.exe disable

    Write-Host "Stopping the zrok-agent service..."
    sc.exe stop zrok-agent

    Write-Host "Deleting the zrok-agent service..."
    sc.exe delete zrok-agent

    Write-Host "Cleaning up the zrok profile..."
    $System32Path = if (-not [Environment]::Is64BitProcess) {
        Join-Path $env:SystemRoot "sysnative"
    } else {
        Join-Path $env:SystemRoot "System32"
    }
    $ZrokConfigPath = Join-Path $System32Path "\config\systemprofile\.zrok"
    Remove-Item -Path $ZrokConfigPath -Recurse -Force

    Write-Host "Restoring PATH environment variables..."
    $NewMachinePath = $script:MachinePath | Where-Object { $_ -ne $script:BinariesDirectory }
    [Environment]::SetEnvironmentVariable("Path", ($NewMachinePath -join ";"), "Machine")

    Write-Host "Cleaning up the binaries folder..."
    Remove-Item -Path $script:BinariesDirectory -Recurse -Force
    $SiteManagerDirectory = Split-Path $script:BinariesDirectory -Parent
    if (-not (Get-ChildItem $SiteManagerDirectory)) {
        Remove-Item -Path $SiteManagerDirectory -Force
    }
}

function Show-Help {
    Write-Host @"
Usage:
    .\Setup-DataMinerSiteManager.ps1 -Command <install|uninstall|help> -ZrokAccountToken <token> -ZrokEnvironmentDescription <description>

Commands:
    install     Installs the zrok-agent as a Windows service.
                Requires -ZrokAccountToken and -ZrokEnvironmentDescription.
    uninstall   Uninstalls the zrok-agent service and cleans up.
    help        Shows this help message.

Examples:
    .\Setup-DataMinerSiteManager.ps1 -Command install -ZrokAccountToken 3G67gmYPhaww -ZrokEnvironmentDescription "Skyline HQ"
    .\Setup-DataMinerSiteManager.ps1 -Command uninstall
"@
}

switch($Command.ToLower()) {
    "install" { Install-ZrokAgent }
    "uninstall" { Uninstall-ZrokAgent }
    "help" { Show-Help }
}
