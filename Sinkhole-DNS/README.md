# Sinkhole DNS Script

## Rasouin d'etre

EWBC has created local (non-replicated) DNS zones on the primary DNS servers:

- PRVADC105W
- PRVADC206W

for the purpose of creating a DNS sinkhole.

When end users try to reach public DNS domains that are hosted on known malicious domains internal DNS redirects that DNS request to an internal security tool. [Add name later]

## Current Process

The current process for creating these DNS domains:

- InfoSec maintains a list of malicious domains.  
- In the case of a new domain added to the list, a story in Jira is created and the entire list is attached.
- SysEng takes the list and runs the Sinkhole-DNS.ps1 script on both DNS servers listed above:

`.\Sinkhole-DNS.ps1 -inputfile ListOfDomainsForSinkhole.txt -includewildcard`

Sample Output:

```


PS C:\Users\^bburrill\Documents> .\Sinkhole-DNS.ps1 -inputfile "7-7-25-DNS Sinkholes.txt" -includewildcard

63 domain(s) to sinkhole to 10.6.201.128.

The 000-sinkholed-domain.local zone already exists, deleting its existing DNS records.
Created default DNS record for the 000-sinkholed-domain.local zone (10.6.201.128).
Created the wildcard (*) record for the 000-sinkholed-domain.local zone (10.6.201.128).
Updated the zone file for 000-sinkholed-domain.local.

Sinkhole domains created at the DNS server: 2

Domains NOT created (maybe already existed): 61

 ```

## Future Improvements

- Create internal public Github repo
- Move the canonical list of sinkholed domains to the internal public Github repo
- Automate process with CI
  - Use PSSession Windows Powershell command-lets to connect to the DNS servers and make the changes
  - Log in the CI when the changes occur
  - When an update is made to the list of domains, a merge to the main branch will trigger the CI
