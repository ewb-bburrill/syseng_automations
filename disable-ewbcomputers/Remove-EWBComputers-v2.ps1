param(
    [Parameter(Mandatory=$true)]
    [string]$domain,

    [Parameter(Mandatory = $true)]
    [string]$inputCSV,

    [Parameter(Mandatory = $false)]
    [string]$OU,

    [Parameter(Mandatory = $false)]
    [int]$AgeInDays = 160,

    [Parameter(Mandatory = $false)]
    [bool]$TestOnly = $true
    
)
# Constants
$domain_name_pattern = '^(?=.{1,255}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$'
$output_filename = "Removed_EWB_Computers_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"

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
    $OUPath = $arrDomain -join ','
    Write-Verbose " OU Path: $OUPath"

    return $OUPath
}


function Replace-OUPath {
  param(
    [Parameter(Mandatory = $true)] [string] $DeviceFullOUPath,
    [Parameter(Mandatory = $true)] [string] $OUPath
  )

  if (-not $DeviceFullOUPath) { return $null }

  $idx = $DeviceFullOUPath.IndexOf(',')
  if ($idx -lt 0) {
    # no comma found — return original (or change this to append the OU if you prefer)
    return $DeviceFullOUPath
  }

  # normalize OUPath so we don't get two commas
  $newOU = $OUPath.Trim()
  if ($newOU.StartsWith(',')) { $newOU = $newOU.TrimStart(',') }

  # include the first comma from the original and append the new OU
  return $DeviceFullOUPath.Substring(0, $idx + 1) + $newOU
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
        $tableString = "The following inactive computer accounts were removed:`r`n"
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


# Remove elements of $computers that are less than $AgeinDays old
$computersToBeRemoved =  $computers | Where-Object { $_.DaysSincePasswordLastSet -gt $AgeinDays }

# Modify the OU path so that only computer objects in the specified OU are considered (if provided)


# Critical Info:
Write-Output "Domain: $domain"
Write-Output "DC to use: $DC"
Write-Output "Input file: $inputCSV"
Write-Output "Disabled Computers Path: $OUPath"
Write-Output "Number of Stale Computers: $($computers.Count)"
Write-Output "Number of Computers to be Removed: $($computersToBeRemoved.Count)"

# Main logic
$results = [System.Collections.ArrayList]::new()
foreach ($computer in $computersToBeRemoved) {

    $FullOUPathDisabled = Replace-OUPath -DeviceFullOUPath $computer.deviceFullOUPath -OUPath $OUPath

    Write-Verbose "Processing Object: $($computer.ComputerName)" 
    Write-Verbose "Full Original OU Path: $($computer.deviceFullOUPath)"
    Write-Verbose "Full Disabled OU Path: $($FullOUPathDisabled)"
    Write-Verbose "Days Since Last Logon: $($computer.DaysSincePasswordLastSet)"

    $whatifFlag = ""
    if ($TestOnly) {
        Write-Output "TestOnly is set to true. No deletion of computer object."
        $whatifFlag = "-WhatIf"
    }
    $result = [PSCustomObject]@{
        ComputerName = $computer.ComputerName
        OperatingSystem = $computer.operatingSystem 
        PasswordLastSet = $computer.PasswordLastSet
        DaysSincePasswordLastSet = $computer.daysSincePasswordLastSet
        deviceEnabled = $computer.Enabled
        deviceFullOUPath = $computer.deviceFullOUPath
        deviceDisabledOUPath = $FullOUPathDisabled
        Owner = $computer.Owner
        WhatIf = $whatifFlag
        Result = $null
    }
    $command = "Remove-ADComputer -Identity `"$($FullOUPathDisabled.ToString())`" -Server $DC -Confirm:`$`(`$false`) $whatifFlag"
    Write-Verbose "Executing command: $command"
    try {
        Invoke-Expression $command
        $result.Result = "Deleted computer object: $($computer.ComputerName)"
        Write-Output $result.Result   
    } catch {
        $result.Result = "Failed to delete computer account: $($computer.ComputerName). Error: $($_.Exception.Message)"
        Write-Warning $result.Result
    }
    $results.Add($result)
}



if (@($result).Count -eq 0) {
    Write-Output "No results"
} else {
    Write-ResultsAsTableToEventLog -Results $results -Source 'EWB Inactive Computers Scripts' -LogName 'Application' -EntryType 'Information' -EventId 3001 -TableWidth 200 -Properties @('ComputerName','OperatingSystem','PasswordLastSet','DaysSincePasswordLastSet','deviceEnabled','deviceFullOUPath','Owner')
    $exportPath = Join-Path -Path (Get-Location) -ChildPath $output_filename
    $results | Export-Csv -Path $exportPath -NoTypeInformation -Force
    Write-Output "Results written to the Event Log and to $exportPath"
}

