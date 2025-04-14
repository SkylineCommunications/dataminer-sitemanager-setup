param(
    [string]$Command = "help",
    [string]$ZrokOrganizationToken,
    [string]$ZrokEnvironmentDescription
)

$SERVICE_NAME = "zrok-agent"

function Initialize-ScriptContext {
    $script:BinariesDirectory = [System.IO.Path]::Combine($env:ProgramFiles, "Skyline Communications", "DataMiner SiteManager")
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

function Assert-ZrokOrganizationTokenRequirement {
    if(-not $ZrokOrganizationToken) {
        Write-Host "A zrok organization token needs to be passed in order to complete the installation."
        Exit
    }
}

function Test-ZrokAgentServiceExists {
    return [bool](Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue)
}

function Install-ZrokAgent {
    Assert-WindowsVersionRequirement
    Assert-AdministratorRoleRequirement
    Assert-ZrokOrganizationTokenRequirement

    if(Test-ZrokAgentServiceExists) {
        Write-Host "Service already installed."
        Exit
    }

    if(-not $ZrokEnvironmentDescription) {
        Write-Host "No zrok environment description passed, using hostname instead."
        $ZrokEnvironmentDescription = hostname
    }

    $ZROK_VERSION = "1.0.2"
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

    Get-ChildItem -Path $DownloadDirectory -Recurse -Filter *.exe | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $script:BinariesDirectory -Force
    }

    Write-Host "Deleting the downloaded files.."
    Remove-Item -Path $DownloadDirectory -Recurse -Force

    if (-not ($script:MachinePath -contains $script:BinariesDirectory)) {
        $NewMachinePath = ($script:MachinePath + $script:BinariesDirectory) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $NewMachinePath, "Machine")
        $env:Path = $NewMachinePath
    }

    zrok.exe enable $ZrokOrganizationToken --description $ZrokEnvironmentDescription

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
    $ZrokConfigPath = [System.IO.Path]::Combine($script:SystemProfilePath, ".zrok")
    Remove-Item -Path $ZrokConfigPath -Recurse -Force

    Write-Host "Restoring PATH environment variables..."
    $NewMachinePath = $script:MachinePath | Where-Object { $_ -ne $script:BinariesDirectory }
    [Environment]::SetEnvironmentVariable("Path", ($NewMachinePath -join ";"), "Machine")

    Write-Host "Cleaning up the binaries folder..."
    Remove-Item -Path $script:BinariesDirectory -Recurse -Force
}

function Show-Help {
    Write-Host @"
Usage:
    .\setup.ps1 -Command <install|uninstall|help> [-ZrokOrganizationToken <token>] [-ZrokEnvironmentDescription <description>]

Commands:
    install     Installs the zrok-agent as a Windows service.
                Requires -ZrokOrganizationToken.
                Optionally, you can specify -ZrokEnvironmentDescription to describe the site name.
                If not specified, the machine's hostname will be used.
    uninstall   Uninstalls the zrok-agent service and cleans up.
    help        Shows this help message.

Examples:
    .\setup.ps1 -Command install -ZrokOrganizationToken 3G67gmYPhaww -ZrokEnvironmentDescription "Skyline HQ"
    .\setup.ps1 -Command uninstall
"@
}

switch($Command.ToLower()) {
    "install" { Install-ZrokAgent }
    "uninstall" { Uninstall-ZrokAgent }
    "help" { Show-Help }
}
