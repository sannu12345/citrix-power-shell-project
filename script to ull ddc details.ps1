# =====================================================================
# Citrix CVAD Broker Report Script
# Reads DDC hostnames from a text file, queries each via the Broker SDK,
# and exports a CSV report per DDC to the output folder.
# Requirements: Citrix Broker PowerShell SDK on the machine running this
# =====================================================================

[CmdletBinding()]
param (
    [string]$DDCFile      = "C:\Temp\ddchome\DDC_List.txt",
    [string]$OutputFolder = "C:\Temp\ddchome\CVAD_Reports"
)

# --- Snap-in Registration and Load --------------------------------------

# Common Citrix SDK install paths (covers CVAD 7.x and legacy XA/XD)
$CitrixSnapinPaths = @(
    "C:\Program Files\Citrix\Desktop Studio\Broker\snapin\Citrix.Broker.Admin.V2.dll",
    "C:\Program Files\Citrix\DelegatedAdmin\Broker\snapin\Citrix.Broker.Admin.V2.dll",
    "C:\Program Files (x86)\Citrix\Desktop Studio\Broker\snapin\Citrix.Broker.Admin.V2.dll"
)

$SnapinName = "Citrix.Broker.Admin.V2"

# Check if snap-in is already registered in the system
$IsRegistered = Get-PSSnapin -Registered -Name $SnapinName -ErrorAction SilentlyContinue

if (-not $IsRegistered) {
    Write-Host "Snap-in not registered. Attempting to register from known SDK paths..."

    $Registered = $false
    foreach ($Path in $CitrixSnapinPaths) {
        if (Test-Path $Path) {
            try {
                # InstallUtil registers the snap-in into the PowerShell registry
                $InstallUtil = "$([System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory())InstallUtil.exe"
                & $InstallUtil $Path | Out-Null
                Write-Host "  Snap-in registered from: $Path"
                $Registered = $true
                break
            }
            catch {
                Write-Warning "  Failed to register snap-in from ${Path}: $_"
            }
        }
    }

    if (-not $Registered) {
        Write-Error @"
Could not register Citrix Broker snap-in. Possible reasons:
  1. Citrix SDK is not installed on this machine.
  2. DLL path has changed — update the CitrixSnapinPaths list in the script.
  3. Script is not running as Administrator (required for InstallUtil).
Install the Citrix Virtual Apps and Desktops SDK from:
  https://www.citrix.com/downloads/citrix-virtual-apps-and-desktops/
"@
        exit 1
    }
}

# Load snap-in into current session if not already active
if (-not (Get-PSSnapin -Name $SnapinName -ErrorAction SilentlyContinue)) {
    try {
        Add-PSSnapin $SnapinName -ErrorAction Stop
        Write-Host "Citrix Broker snap-in loaded successfully."
    }
    catch {
        Write-Error "Snap-in is registered but failed to load: $_"
        exit 1
    }
}
else {
    Write-Host "Citrix Broker snap-in already active in this session."
}

# --- Preflight Checks ---------------------------------------------------

if (-not (Test-Path $DDCFile)) {
    Write-Error "DDC list file not found: $DDCFile"
    exit 1
}

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder | Out-Null
    Write-Host "Created output folder: $OutputFolder"
}

# --- Load and Validate DDC List -----------------------------------------

# Filter out blank lines and comment lines starting with #
$DDCs = Get-Content $DDCFile |
        Where-Object { $_.Trim() -ne "" -and $_ -notmatch "^\s*#" }

if (-not $DDCs) {
    Write-Error "DDC list file is empty or contains only comments: $DDCFile"
    exit 1
}

Write-Host "Found $($DDCs.Count) DDC(s) to process."

# --- Query Each DDC -----------------------------------------------------

$Success   = 0
$Failed    = 0
$DateStamp = Get-Date -Format "yyyyMMdd_HHmmss"

foreach ($DDC in $DDCs) {

    $DDC = $DDC.Trim()
    Write-Host "`nProcessing DDC: $DDC"

    try {
        # Raise MaxRecordCount if your environment has more than 10000 machines
        $Machines = Get-BrokerMachine -AdminAddress $DDC -MaxRecordCount 10000 -ErrorAction Stop

        if (-not $Machines) {
            Write-Warning "No machines returned from: $DDC"
            $Failed++
            continue
        }

        $Report = $Machines | Select-Object `
            MachineName,
            CatalogName,
            DesktopGroupName,
            ControllerDNSName,
            AgentVersion,
            IPAddress,
            OSType,
            ProvisioningType,
            SessionCount,
            PowerState,
            RegistrationState,
            MaintenanceMode

        # Sanitise DDC name for use in filename
        $SafeDDC    = $DDC -replace "[\\/:*?`"<>|]", "_"
        $OutputFile = Join-Path $OutputFolder "BrokerReport_${SafeDDC}_${DateStamp}.csv"

        $Report | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
        Write-Host "  Report saved: $OutputFile  ($($Report.Count) machines)"
        $Success++
    }
    catch {
        Write-Warning "  Failed to query ${DDC}: $_"
        $Failed++
    }
}

# --- Summary ------------------------------------------------------------

Write-Host "`n--- Run Summary ---"
Write-Host "  Succeeded : $Success"
Write-Host "  Failed    : $Failed"
Write-Host "  Reports in: $OutputFolder"