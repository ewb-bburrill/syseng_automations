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


Make sure the required module is available
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
foreach 


# Critical Info:
Write-Output "Domain: $domain"
Write-Output "DC to use: $DC"
Write-Output "Input file: $inputCSV"

$computers[4]

foreach ($computer in $computers) {

    Write-Verbose "Processing Object: $($computer.ComputerName)" 
    Write-Verbose "Full OU Path: $($computer.deviceFullOUPath)"
    Write-Verbose "Days Since Last Logon: $($computer.DaysSincePasswordLastSet)"
    $whatifFlag = ""
    if ($TestOnly) {
        Write-Output "TestOnly is set to true. No deletion of computer object."
        $whatifFlag = "-WhatIf"
    }
    try {
        Remove-ADAccount -Identity $computer.deviceFullOUPath -Server $DC $whatifFlag
        Write-Output "Deleted computer object: $($computer.ComputerName)"
    } catch {
        Write-Warning "Failed to delete computer account: $($computer.ComputerName). Error: $($_.Exception.Message)"
    }
}