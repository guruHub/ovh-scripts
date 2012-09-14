ovh-scripts
===========

Scripts to deal with OVH Servers


ovh-vrack-install.sh
--------------------

This script will take a fresh Debian OVH server and automatically:
+ 1) Configure Virtual Rack interface.
+ 2) Optional configure extra public IP's (failover, not Vrack RIPE)
+ 3) Optional configure extra vrack IP's
+ 4) Configure hostname & regenerate ssh keys
+ 5) apt update & upgrade (100% unattended)
+ 6) Add Backports repository and install puppet from backports
+ 7) Launch puppet.

Tested with EG SSD and MG SSD servers.

TODO: 
+ Add support for RIPE Vrack IPs.
+ Add support to dynamically add an url as post install on server request that would return the script preconfigured to avoid having to copy and run the script for each new server.



