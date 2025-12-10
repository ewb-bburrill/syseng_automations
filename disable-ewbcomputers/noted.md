# Requirements:

Weekly process
Runs on a DC in each domain
Outputs a CSV/JSON of computer objects which meet criteria
Separate types of objects
    Ser


Timeline 
60 Days - Flagged/Warned for deletion
120 Days - Threshold for deletion within 7 days
180 Days - Nothing



## Questions

Research hardware password expiration timeline (what if a laptop is owned by someone on medical leave)

## Decision tree for teams

OS Name contains server or "Windows"
OU path contains server
OU path contains Citrix
OU path contains VDI
 
Inversely:
Computer Name ends in "-L"
Computer Name ends in "-D"
Computer Name ends in "-ML"
Computer Name ends in "-SZ"
 