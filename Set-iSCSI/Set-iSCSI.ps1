<#
Set-iSCSI Script
East West Bank
benjamin.burrill@eastwestbank.com
#>

param (
    [Parameter(Mandatory=$false)]
    [string]$site,

    [Parameter(Mandatory=$false)]
    [string]$san
)

<#
.SYNOPSIS
    Configures iSCSI connections between a Windows Server and one (or more) of the EWBC SANs.

.DESCRIPTION
    This applet

.PARAMETER site
    Optional parameter for the user to specify the datacenter site where the Windows Server client is located.

.PARAMETER san
    Optional parameter for the user to specify the SAN which should be targeted by the iSCSI initiator

.EXAMPLE
    If you are are calling this from another script or program or the CLI, this is the format:
   

.NOTES

#>


# Constants




# Variables
$site = $null
$san = $null
$ipaddr = $null
$datacenter = $null
$iSCSITargets = $null


function Get-PrimarySubnet {
    param (
        
    )
    
    # Regex (first octet fixed to 10, excludes third-octet 100 and 102, the iSCSI storage networks):
    #  What it does:
    #
    # ^10. — requires the first octet to be 10.
    # (?:25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d) — standard 0–255 octet pattern (used for 2nd, 3rd and 4th octets).
    # (?!(?:100|102).) — negative lookahead before the third octet to forbid 100 or 102.
    # $ — anchors the end of string so the whole string must be a single IPv4 address.
    # Examples

    # Matches: 10.0.0.1, 10.12.99.5, 10.255.101.255
    # Does NOT match: 10.1.100.5, 10.1.102.5, 127.0.0.1 (already excluded by 10. prefix)
    
    $regex = "^10\.(?:25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\.(?!(?:100|102)\.)(?:25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\.(?:25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)$"

    $ipaddress = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -match $regex} | Select-Object -ExpandProperty IPAddress

    return $ipaddress
}


function Get-Datacenter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ipaddress
    )

    # datacenter prefixes (hashtable used for key->prefix mapping)
    $datacenters = @{
        PHX = '10.6.'
        LAS = '10.24.'
    }

    $ip = $ipaddress.Trim()

    foreach ($entry in $datacenters.GetEnumerator()) {
        $prefix = $entry.Value
        if (-not $prefix.EndsWith('.')) { $prefix += '.' }   # normalize
        if ($ip.StartsWith($prefix)) {
            return $entry.Key
        }
    }

    return $null   # not found — caller can interpret $null as "unknown"
}

function Get-iSCSITargets {
    param (
        [Parameter(Mandatory = $true)]
        [string]$datacenter
    )
    
    # SAN target IPs (hashtable of arrays)
    $PHX_Nimble_100 = '10.6.100.180'
    $PHX_Nimble_102 = '10.6.102.180'
    $LAS_Nimble_100 = 'something'
    $LAS_Nimble_100 = 'something'

    $sanTargets = @{

        PHX  = @($PHX_Nimble_100 ,$PHX_Nimble_102) 
        LAS  = @($LAS_Nimble_100 ,$LAS_Nimble_102) 
        HK   = @()
        HKDR = @()
        SHEN = @()
        SHAN = @()
    }


    if ($sanTargets.ContainsKey($datacenter)) {
        return $sanTargets[$datacenter]
    }

}

# Main script logic

## Get the primary subnet IP address (non-storage network)
$ipaddr = Get-PrimarySubnet

## Go get the datacenter from the IP address
if ($null -eq $ipaddr) {
    Write-Error "Could not determine any non storage network IP address. Exiting."
    exit 1
}
else {
    $datacenter = Get-Datacenter $ipaddr
}

## Get the iSCSI target(s) for the datacenter
if ($null -eq $datacenter) {
    Write-Error "Could not determine datacenter from IP address $ipaddr. Exiting."
    exit 1
}
else {
    $iSCSITargets = Get-iSCSITargets $datacenter
}


$iSCSITargets

# # Ensure the iSCSI service is running

if (Get-Service -Name 'MSiSCSI' -ErrorAction SilentlyContinue) {
    Write-Host "MSiSCSI service is present."
    if ((Get-Service -Name 'MSiSCSI').Status -ne 'Running') {
        Write-Host "MSiSCSI service is not running. Starting service..."
        Start-Service -Name 'MSiSCSI'
    } else {
        Write-Host "MSiSCSI service is already running."
    }
} else {
    Write-Error "MSiSCSI service is not present on this system."
    exit 1
}

# Connect to the target portal(s)

foreach ($target in $iSCSITargets)
{
    New-IscsiTargetPortal -TargetPortalAddress $target
    $t = Get-IscsiTarget
    Connect-IscsiTarget -NodeAddress $t.NodeAddress -IsPersistent $true
}


# Rescan the disks using diskpart
diskpart
rescan
exit
