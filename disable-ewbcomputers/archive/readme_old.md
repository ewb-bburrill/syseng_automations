# Inactive Device Retrieval

## US Region By Default

The default region/domain if left unspecified is EWBC (US)

> When working in the console, it is recommended to output in a table using `Format-Table` or `ft`. You can also output to a GUI window with `Out-GridView`

```ps1

.\Get-EwbInactiveComputers.ps1 | ft
```

## Specific Regions

```ps
.\Get-EWBInactiveComputers.ps1 -US | ft # US is Default, but can also be specified
.\Get-EWBInactiveComputers.ps1 -HK | ft
.\Get-EWBInactiveComputers.ps1 -CN | ft
```

## Export to CSV

```ps1
.\Get-EWBInactiveComputers.ps1 | export-csv -Path "C:\Temp\InactiveComputersReport_US.csv" -NoTypeInformation
```

## Disabling & Moving Inactive Devices

The default region/domain if left unspecified is EWBC (US)

This command moves disables them and moves them to 

The Disabling cmdlet is dependent on region as well, and the regions must match. You can import the list from a CSV or pipe it frp, the `Get-EWBInactiveComputers.ps1` cmdlet. See below in [Piping Commands to Disable](#piping-commands-to-disable)

## Ask Confirmation

Because this is a riskier command, it is configured to prompt for confirmation with each device before disabling or removing, by default. This is helpful for a small number of devices, but more devices, if confirmed with another method, can bypass this check by forcing them all (see below):

```ps1
Import-Csv C:\Temp\InactiveComputersReport_US.csv | .\Disable-EWBComputers.ps1
```

## Force All (No Confirm)

```ps1
Import-Csv C:\Temp\InactiveComputersReport_US.csv | .\Disable-EWBComputers.ps1 -Confirm:$false
```

## What-If

Using the `-Whatif` parameter shows what actions would take place if the command were to be run, but **does not carry out the actions** (disable and move). You can specify it like so:

```ps1
Import-Csv C:\Temp\InactiveComputersReport_US.csv | .\Disable-Computers.ps1 -Whatif
```

## Disable Only

By default, the script will **move and disable the devices specified.**
To disable the devices and not move them, use the `-DisableOnly` switch.

```ps1
Import-Csv C:\Temp\InactiveComputersReport_US.csv | .\Disable-Computers.ps1 -DisableOnly
```

## Move Only

By default, the script will **move and disable the devices specified.**
To move the devices and not disable them, use the `-MoveOnly` switch.

```ps1
Import-Csv C:\Temp\InactiveComputersReport_US.csv | .\Disable-Computers.ps1 -MoveOnly
```

# Piping Commands to Disable/Move

You can chain these two cmdlets to identify and disable the computers specified. However **the regions must match**:

```ps1
# US Region Example
.\Get-EWBInactiveComputers.ps1 | .\Disable-Computers.ps1 -Confirm:$false

# HK Region Example
.\Get-EWBInactiveComputers.ps1 -HK | .\Disable-Computers.ps1 -HK -Confirm:$false
```
