param(
    [Parameter(Mandatory=$true)]
    [string]$domain,

    [Parameter(Mandatory = $true)]
    [string]$inputCSV,

    [Parameter(Mandatory = $false)]
    [string]$OU,

    [Parameter(Mandatory = $false)]
    [int]$AgeInDays = 120,

    [Parameter(Mandatory = $false)]
    [bool]$TestOnly = $true
    
)
# Constants
$domain_name_pattern = '^(?=.{1,255}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$'
$output_filename = "Disabled_EWB_Computers_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"

function Test-Domain{
    param (
        [string] $domain
    )

    # Verify we have a domain value to work with
    if ($null -eq $domain) {
        Write-Error "No domain specified. Exiting."
        exit 1
    }

    # Verify the domain is valid
    if ($domain -match $domain_name_pattern){
        Write-Output "Valid DNS AD domain name"
        return $true
    } else {
        Write-Error "Invalid AD DNS name"
        Exit 1
    }
}

function Get-OUPath {
    # Convert the DNS Domain to an OU/LDAP path to the DisabledComputers OU off the root of the domain
    param (
        [string] $domain
    )

    $domain = "DisabledComputers." + $domain
    $arrDomain = $domain -split '\.'
    #$arrDomain.Length
    $arrDomain = $arrDomain.ForEach({ "DC=$_"})
    $arrDomain[0] = $arrDomain[0].Replace('DC','OU')
    $OUPath = ($arrDomain -join ',').ToString()
    Write-Verbose " OU Path: $OUPath"

    return $OUPath
}

function Unprotect-ADObjectIfProtected {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$DeviceFullOUPath,    # expected: distinguishedName (e.g. "CN=PC01,OU=Computers,DC=contoso,DC=com")
        [switch]$Force                # suppress confirmation when present
    )

    process {
        # Try to resolve the object by DN; fall back to Get-ADComputer if needed
        try {
            $obj = Get-ADObject -Identity $DeviceFullOUPath -Properties ProtectedFromAccidentalDeletion -ErrorAction Stop
        } catch {
            try {
                $obj = Get-ADComputer -Identity $DeviceFullOUPath -Properties ProtectedFromAccidentalDeletion -ErrorAction Stop
            } catch {
                Write-Error "AD object not found: $DeviceFullOUPath"
                return
            }
        }

        $dn = $obj.DistinguishedName
        $isProtected = [bool]$obj.ProtectedFromAccidentalDeletion

        if ($isProtected) {
            Write-Verbose "Object $dn is protected from accidental deletion."

            if ($PSCmdlet.ShouldProcess($dn, 'Clear ProtectFromAccidentalDeletion')) {
                # Use -Confirm:$false when -Force supplied, otherwise respect confirmations.
                $confirmSwitch = if ($Force) { $false } else { $true }

                try {
                    Set-ADObject -Identity $dn -ProtectedFromAccidentalDeletion:$false -Confirm:$confirmSwitch -ErrorAction Stop
                    Write-Output "Protection cleared for $dn"
                } catch {
                    Write-Error "Failed to clear protection for $dn : $($_.Exception.Message)"
                }
            }
        } else {
            Write-Verbose "AD Object not protected: $dn"
        }
    }
}


function Write-ResultsAsTableToEventLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.Object[]] $Results,

        [string] $Source = 'MyApp',
        [string] $LogName = 'Application',

        [ValidateSet('Information','Warning','Error','SuccessAudit','FailureAudit')]
        [string] $EntryType = 'Information',

        [int] $EventId = 1000,

        [int] $TableWidth = 160,      # width passed to Out-String to reduce wrapping
        [int] $MaxMessageLength = 31839,  # safety truncation (adjust if needed)

        [string[]] $Properties         # optional: column order/filter, e.g. 'User','Action','Time'
    )

    Begin {
        # Ensure the event source exists (Write-EventLog requires a registered source)
        if (-not [System.Diagnostics.EventLog]::SourceExists($Source)) {
            try {
                New-EventLog -LogName $LogName -Source $Source
            } catch {
                Throw "Failed to create/register event source '$Source' for log '$LogName'. Run as Administrator or pre-create the source. $_"
            }
        }
    }

    Process {
        if (-not $Results -or $Results.Count -eq 0) {
            Throw "No objects provided in `\$Results`."
        }

        # Optionally select only specific properties/columns in the requested order
        $toFormat = if ($Properties) { $Results | Select-Object -Property $Properties } else { $Results }

        # Create a table string. -AutoSize then Out-String -Width controls wrapping.
        $tableString = "The following inactive computer accounts were disabled:`r`n"
        $tableString += $toFormat | Format-Table -AutoSize | Out-String -Width $TableWidth
        $message = $tableString.TrimEnd()

        # Truncate to avoid exceeding event log maximums
        if ($message.Length -gt $MaxMessageLength) {
            $message = $message.Substring(0, $MaxMessageLength) + "`r`n...[truncated]"
        }

        # Write a single event containing the full table
        Write-EventLog -LogName $LogName -Source $Source -EntryType $EntryType -EventId $EventId -Message $message
    }
}

# Make sure the required module is available
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error "The ActiveDirectory module is not available. Please install the RSAT tools for Active Directory and try again."
    exit 1
}

# Test the domain parameter
Test-Domain -domain $domain | Out-Null

# Get the Disabled Computers OU Path
$OUPath = Get-OUPath -domain $domain

# Get the domain controller
$dc = [string](Get-ADDomainController -DomainName $domain -Discover).HostName

# Import the CSV file
if (Test-Path -Path $inputCSV) {
    Write-Output "Importing CSV file from path: $inputCSV"
    $computers = Import-Csv -Path $inputCSV
} else {
    Write-Error "The specified CSV file path does not exist: $inputCSV"
    Exit 1
}

# Critical Info:
Write-Output "Domain: $domain"
Write-Output "OU to move disabled objects to: $OUPath"
Write-Output "DC to use: $DC"
Write-Output "Input file: $inputCSV"

$whatifFlag = ""
if ($TestOnly) {
    Write-Output "TestOnly is set to true. No changes will be made."
    $whatifFlag = "-WhatIf"
}

$results = [System.Collections.ArrayList]::new()
foreach ($computer in $computers) {

    Write-Verbose "Processing Object: $($computer.ComputerName)" 
    Write-Verbose "Full OU Path: $($computer.deviceFullOUPath)"
    Write-Verbose "Days Since Last Logon: $($computer.DaysSincePasswordLastSet)"
    $command = "Disable-ADAccount -Identity `"$($computer.deviceFullOUPath.ToString())`" -Server $DC $whatifFlag"
    Write-Verbose "Executing command: $command"
    $result = [PSCustomObject]@{
        ComputerName = $computer.ComputerName
        Domain = $domain
        OperatingSystem = $computer.operatingSystem 
        PasswordLastSet = $computer.PasswordLastSet
        DaysSincePasswordLastSet = $computer.daysSincePasswordLastSet
        deviceEnabled = $computer.deviceEnabled
        deviceFullOUPath = $computer.deviceFullOUPath
        Owner = $computer.Owner
        Whatif = $whatifFlag
        Result = $null
        }
    if ($computer.deviceEnabled -eq "TRUE"){
        try {
            $command = "Disable-ADAccount -Identity `"$($computer.deviceFullOUPath.ToString())`" -Server $DC $whatifFlag"
            Write-Verbose "Executing command: $command"
            Invoke-Expression $command
            Write-Output "Disabled computer account: $($computer.ComputerName)"
            $result.deviceEnabled = "FALSE"
        } catch {
            $result.Result = "Failed to disable computer account: $($computer.ComputerName). Error: $($_.Exception.Message)"
            Write-Warning $result.Result
        }
    }

    try {
        Unprotect-ADObjectIfProtected $computer.deviceFullOUPath -Force
        $command = "Move-ADObject -Identity `"$($computer.deviceFullOUPath.ToString())`" -TargetPath `"$OUPath`" -Server $DC $whatifFlag"
        Write-Verbose "Executing command: $command"
        Invoke-Expression $command
       
        Write-Output "Moved computer account: $($computer.ComputerName) to $OUPath"
    } catch {
        $result.Result = "Failed to move computer account: $($computer.ComputerName). Error: $($_.Exception.Message)"
        Write-Warning $result.Result        
    }
    $results.Add($result)
}

if (@($results).Count -eq 0) {
    Write-Output "No results"
} else {
    Write-ResultsAsTableToEventLog -Results $results -Source "EWB Inactive Computers Scripts" -LogName "Application" -EntryType Information -EventId 3001 -TableWidth 200 -Properties @('ComputerName','OperatingSystem','PasswordLastSet','DaysSincePasswordLastSet','deviceEnabled','deviceFullOUPath','Owner')
    $results | Export-Csv -Path .\$output_filename -NoTypeInformation -Force
    Write-Output "Results written to the Event Log and to $output_filename"
}