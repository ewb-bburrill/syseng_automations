[cmdletbinding(SupportsShouldProcess=$True, DefaultParameterSetName="US")]
param(
    [Parameter(Mandatory=$false, ParameterSetName="US")]
    [switch]$US,

    [Parameter(Mandatory=$true, ParameterSetName="HK")]
    [switch]$HK,

    [Parameter(Mandatory=$true, ParameterSetName="CN")]
    [switch]$CN,

    [Parameter(ValueFromPipeline = $True, Mandatory = $True)]
    [PSObject[]]$Computers,

    [switch]$MoveOnly,

    [switch]$DisableOnly
    
)

# Put all computers in one collection (otherwise by default it will only take first result)
begin {
    $AllComputers = @()
} process {
    $AllComputers += $Computers
} end {
    switch ($PSCmdlet.ParameterSetName) {
        "US" {
            $TargetPath = "OU=DisabledComputers,DC=ewbc,DC=net"
            $TargetDomain = "ewbc.net"
            $Server = [string](Get-ADDomainController -DomainName $TargetDomain -Discover).HostName
            $Credential = Get-Credential -Message "US Server Admin Credential"
            if (($AllComputers[0] -like "*DC=ewcn*") -or ($AllComputers[0] -like "*DC=ewhk*")) {
                Write-Warning "Please specify the proper region parameter to process these computers (e.g. -US, -HK or -CN)"
                return
            }
        }
        "HK" {
            $TargetPath = "OU=DisabledComputers,DC=ewhk,DC=ewbc,DC=net"
            $TargetDomain = "ewhk.ewbc.net"
            $Server = [string](Get-ADDomainController -DomainName $TargetDomain -Discover).HostName
            $Credential = Get-Credential -Message "HK Server Admin Credential"
            if ($AllComputers[0] -notlike "*DC=ewhk*") {
                Write-Warning "Please specify the proper region parameter to process these computers (e.g. -US, -HK or -CN)"
                return
            }
        }
        "CN" {
            $TargetPath = "OU=DisabledComputers,DC=ewcn,DC=ewbc,DC=net"
            $TargetDomain = "ewcn.ewbc.net"
            $Server = [string](Get-ADDomainController -DomainName $TargetDomain -Discover).HostName
            $Credential = Get-Credential -Message "CN Server Admin Credential"
            if ($AllComputers[0] -notlike "*DC=ewcn*") {
                Write-Warning "Please specify the proper region parameter to process these computers (e.g. -US, -HK or -CN)"
                return
            }
        }
    }

    foreach ($computer in $AllComputers) {
        if(($PSCmdlet.ShouldProcess("$($computer.ComputerName)", "Disabling AD Computer Object")) -and (-not $MoveOnly)) {
            try{
                Disable-ADAccount $computer.deviceFullPath -Server $Server -Credential $Credential
                Write-Host "Successfully disabled device $($computer.ComputerName)." -ForegroundColor Green
            # } catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
            #     write-host $null
            } catch {
                Write-Warning "Unable to disable $($computer.ComputerName): $($_.Exception.Message)."
            }
        }
        
        if(($PSCmdlet.ShouldProcess("$($computer.ComputerName)", "Moving AD Computer Object")) -and (-not $DisableOnly)) {
            try {
                Move-ADObject -Identity $computer.deviceFullPath -TargetPath $TargetPath -Server $Server -Credential $Credential
                Write-Host "Successfully moved device $($computer.ComputerName)." -ForegroundColor Green
            } catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
                # Do Nothing
            } catch {
                Write-Warning "Unable to move $($computer.ComputerName): $($_.Exception.Message)."
            }
        }
    }
}