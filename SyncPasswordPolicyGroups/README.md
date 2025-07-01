# SyncPasswordPolicyGroups

## Summary

Automation that updates Admin and Service account groups membership in EWCN; running on PRVADCN105W as SYSTEM, every day at 6am PST

## Description

Automation scripts using Powershell  which keeps the membership of:

EWCN\PWD_Policy_Exclusion_Service_Accounts

EWCN\PWD_Policy_Exclusion_Admin_Accounts

… populated by the user accounts which are in the corresponding following OUs:

OU=IT,DC=EWCN,DC=EWBC,DC=NET

OU=ServiceAccounts,DC=EWCN,DC=EWBC,DC=NET

This includes new accounts and the removal of deleted accounts.  

It includes exceptions for objects which should not have the fine grained password policy applied to them.

It applies to user accounts that are found in child OUs within those AD locations.

## Implementation Details

- Server or Service running automation:  PRVADCN105W.ewcn.ewbc.net
- Permissions:  Runs as the SYSTEM account on PRVADCN105W
- Schedule: Runs daily at 6am PT