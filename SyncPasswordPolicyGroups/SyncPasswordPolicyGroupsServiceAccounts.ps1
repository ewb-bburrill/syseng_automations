<#
SyncPasswordPolicyGroups Script
East West Bank
benjamin.burrill@eastwestbank.com


This script keeps a specified security group ($GroupName) populated with the user objects
in a specfied OU (and in sub-OU).  If user objects are added or removed from the specified OU
path, they will be added or removed from the security group.

Also, $excludedUsers is a list of the accounts which are excluded (or ignored) from the sync.

Finally, when it runs it logs the results of the script to the Event Viewer Application Log.
#>

# Variables
$GroupName = "PWD_Policy_Exclusion_Service_Accounts"

$TargetOU = "OU=ServiceAccounts,DC=EWCN,DC=EWBC,DC=NET" # Replace with your OU's distinguished name

## Excluded users must be specified with their distinguished name:
$excludedUsers = @"

"@


## Script below; Make customizations above

function Write-ToEventViewer {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$LogName,

        [Parameter(Mandatory=$true)]
        [string]$Source,

        [Parameter(Mandatory=$true)]
        [int]$EventId,

        [Parameter(Mandatory=$true)]
        [string]$Message,

        [ValidateSet("Error", "Warning", "Information", "SuccessAudit", "FailureAudit")]
        [string]$EntryType = "Information"
    )

    # Check if the event source exists, if not, create it
    if (-not (Get-EventLog -List | Where-Object {$_.LogDisplayName -eq $LogName})) {
        Write-Warning "Log '$LogName' does not exist. Please ensure it is a valid log name."
        return
    }

    if (-not (Get-EventLog -LogName $LogName -Source $Source -ErrorAction SilentlyContinue)) {
        Write-Host "Creating event source '$Source' in log '$LogName'..."
        New-EventLog -LogName $LogName -Source $Source -ErrorAction Stop
        Write-Host "Event source '$Source' created successfully."
    }

    # Write the event to the Event Viewer
    try {
        Write-EventLog -LogName $LogName -Source $Source -EventID $EventId -EntryType $EntryType -Message $Message -ErrorAction Stop
        Write-Host "Event successfully written to '$LogName' log with Source '$Source' and Event ID '$EventId'."
    }
    catch {
        Write-Error "Failed to write event to Event Viewer: $($_.Exception.Message)"
    }
}

# Objects for logging
$RemovedUsers = New-Object System.Collections.ArrayList
$AddedUsers = New-Object System.Collections.ArrayList


# Get all users from the target OU and its sub-OUs
$UsersInOU = Get-ADUser -Filter * -SearchBase $TargetOU -SearchScope Subtree | Select-Object -ExpandProperty DistinguishedName

# Get current members of the security group
$CurrentGroupMembers = Get-ADGroupMember -Identity $GroupName | Select-Object -ExpandProperty DistinguishedName

## Add users who are in the OU but not in the group
foreach ($UserDN in $UsersInOU) {
    if ($excludedUsers.Contains($UserDN)){
        #Do nothing
    }
    elseif ($CurrentGroupMembers -notcontains $UserDN) {
        #Add-ADGroupMember -Identity $GroupName -Members $UserDN
        $AddedUsers.Add($UserDN)
        Write-Host "Added $UserDN to $GroupName"
    }
}

## Remove users who are in the group but no longer in the OU
foreach ($MemberDN in $CurrentGroupMembers) {
    if ($excludedUsers.Contains($MemberDN)){
        #Do nothing
    }
    elseif ($UsersInOU -notcontains $MemberDN) 
    {
        #Remove-ADGroupMember -Identity $GroupName -Members $MemberDN -Confirm:$false # Use -Confirm:$false for automation
        $RemovedUsers.Add($UserDN)
        Write-Host "Removed $MemberDN from $GroupName"
    }
}

## Logging and output:
$Message =  @"
The SyncPasswordPolicyGroups script ran and this is the output:

Users added to $GroupName Security Group:
$AddedUsers

Users removed from $GroupName Security Group:
$RemovedUsers

Dynamic group update complete for $GroupName.
"@

Write-Host $Message
Write-ToEventViewer -LogName "Application" -Source "SyncPasswordPolicyGroups" -EventId 1001 -Message $message -EntryType "Information"

