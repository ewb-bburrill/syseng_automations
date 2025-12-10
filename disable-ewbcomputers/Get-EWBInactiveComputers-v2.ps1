
param(
    [Parameter(Mandatory=$false)]
    [string]$domain,
    [int]$TimePeriodDays = 120
)

# Constants
$domain_name_pattern = '^(?=.{1,255}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$'

function Get-DomainInactiveComputers {
    param (
        [string] $OU,
        [string] $DC,
        [int]   $TimePeriodDays
    )

    $TimePeriodDaysDate = (Get-Date).AddDays($TimePeriodDays * -1)
    $results = @()
    Write-Verbose "Get-ADComputer -Filter {LastLogonDate -lt $TimePeriodDaysDate} -SearchBase $OU -Server $DC -Properties LastLogonDate, OperatingSystem, PasswordLastSet"
    $computers = Get-ADComputer -Filter {LastLogonDate -lt $TimePeriodDaysDate} -SearchBase $OU -Server $DC -Properties LastLogonDate, OperatingSystem, PasswordLastSet

    foreach ($computer in $computers) {
        try {
            $daysSincePasswordLastSet = (New-TimeSpan -Start $computer.PasswordLastSet -End (Get-Date)).Days
        } catch {
            $daysSincePasswordLastSet = "n/a"
        }
        $operatingSystem = if ($null -ne $computer.OperatingSystem) { $computer.OperatingSystem } else { '' }
        $results += [PSCustomObject]@{
            ComputerName = $computer.Name
            OperatingSystem = $operatingSystem 
            PasswordLastSet = $computer.PasswordLastSet
            DaysSincePasswordLastSet = $daysSincePasswordLastSet
            deviceEnabled = $computer.Enabled
            deviceFullOUPath = $computer.DistinguishedName
            Owner = $null
        }
    }
    return $results
}

function Get-OUPath {
    # Convert the DNS Domain to an OU/LDAP path to the root of the domain
    param (
        [string] $domain
    )

    $arrDomain = $domain -split '\.'
    #$arrDomain.Length
    $arrDomain = $arrDomain.ForEach({ "DC=$_"})
    $OUPath = $arrDomain -join ','
    Write-Verbose " OU Path: $OUPath"

    return $OUPath
}

function Get-OutputFile {
    param (
        [string] $domain
    )
    $domainlessdot = $domain.Replace(".","_")
    $date = Get-Date -Format "yyyyMMdd"
    $filename = "InactiveComputerObj_" + $domainlessdot + "_" + $date + ".csv"
  
    return $filename
}
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
        $tableString = "The following inactive computer accounts were found:`r`n`r`n"
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

# Main script logic

# Test the domain parameter
Test-Domain -domain $domain

# Make sure the required module is available
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error "The ActiveDirectory module is not available. Please install the RSAT tools for Active Directory and try again."
    exit 1
}

# Convert the DNS Domain to an OU/LDAP path at the root of the domain
$OU = Get-OUPath -domain $domain
# Get a domain controller to query
$DC = [string](Get-ADDomainController -DomainName $domain -Discover).HostName

#Create the output filename
$output_filename = Get-OutputFile -domain $domain

# OUtput the parameters being used
Write-Output "Domain to be queried: $domain"
Write-Output "OU to be queried: $OU"
Write-Output "DC to be queried: $DC"
Write-Output "Output file: $output_filename"

# Get the inactive computers
$result = Get-DomainInactiveComputers -OU $OU -DC $DC -TimePeriodDays $TimePeriodDays

# Return the results
#$result | ConvertTo-Json
Write-Output "Number of inactive computer objects found: $($result.Length)"


# Clean up the results and add owners data
foreach ($object in $result){
    #Write-Verbose $object.OperatingSystem
    if (($object.OperatingSystem.Contains("Windows Server")) -or 
        ($object.deviceFullOUPath.Contains("OU=Servers")   ) -or
        ($object.deviceFullOUPath.Contains("OU=VDI")       ) -or
        ($object.deviceFullOUPath.Contains("OU=CITRIX" )   ) -or
        ($object.deviceFullOUPath.Contains("OU=Telecom" )  ) )
    {
        $object.Owner = "SysEng"
    }
       
    elseif (($null -eq $object.Owner) -and 
         ($object.ComputerName -match '^\d{6}-(?:SZ|ML|L|D)$'))
    {
        $object.Owner = "Vulnerability Management"
    }

    else {
        $object.Owner = "Unknown"
        $warning_update = $object.ComputerName + " has an unknown owner."
        Write-Warning $warning_update
    }

    Write-Verbose "$($object.ComputerName) is owned by $($object.Owner) "
}



# Output the results to the event log and to a CSV file
if (@($result).Count -eq 0) {
    Write-Output "No results"
} else {
    Write-ResultsAsTableToEventLog -Results $result -Source "EWB Inactive Computers Script" -LogName "Application" -EntryType Information -EventId 3001 -TableWidth 200 -Properties @('ComputerName','OperatingSystem','PasswordLastSet','DaysSincePasswordLastSet','deviceEnabled','deviceFullOUPath','Owner')
    $result | Export-Csv -Path .\$output_filename -NoTypeInformation -Force
    Write-Output "Results written to the Event Log and to $output_filename"
}