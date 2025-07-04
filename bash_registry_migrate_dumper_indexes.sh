#!/bin/bash
# SCRIPT: bash_registry_migrate_auto.sh
# AUTHOR: Ben Chambers
# DATE: August 2024
# VERSION: 1.00
# PLATFORM: Linux
# PURPOSE: This script moves domains from the old registry servers to the new MES 2019 environment. It works sequentially, 1 domain at a time
# until all escaped domains in the list have been processed. It logs the duration so timings can be accurately recorded.
# It also performs verification steps at every stage, aborting and logging the failure for any domains missing crucial tables.

# High level steps.
# 1: View of each registry which contains the domain's which are active. 2 columns, 1 which will be the escaped domain, 1 which will be the original name using replace function.
# 2: This generates a list to be used by mydumper
# 3: Inital dump of schemas only using mydumper
# 4: Convert any MyISAM tables to InnoDB
# 5: Restore schemas using myloader
# 6: Drop Indexes From Schemas except primary key
# 7: Dump of data using mydumper
# 8: Restore of data using myloader
# 9: Call Proc to convert to new format

# Pre-requisites.
# 1: The stored procedure 'sp_registry_convert_to_new_format' must be present on the 'message' db on the new environment.
# 2: The message table being moved to must not contain test data.
# 3: Enough storage must be available on the new environment.
# 4: The up to date vw_domains_not_moving (found in Registry Migration View) should be present on all registry servers. Otherwise the list won't generate.

# Initial and increment
- Initial mydumper
- update records on isp
- Incremental catching any changes
- convert to new format

^ Considerations
- Could do an initial mydumper on a certain date. Restore bulk of data this way.
- Then on the day, just do dumps from where the date is the day before the mydumper (to catch any overlap)
- This would catch any new domains created since the mydumper was done

# Update
- Update records on isp
- Mydumper of all data
- Convert to new format

2 scripts
1 to move any low storage DB's
1 to move any high storage DB's
Usage based, create buckets
Buckets
For small
For really big lads 



For high usage
For low / normal usage

Usage dictated by 
Queries against dropzone
Who's writing email
