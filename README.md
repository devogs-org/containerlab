# containerlab
Generic, reusable network lab topologies built with Containerlab. Features various NOS (SR Linux, cEOS, VyOS), L2/L3 configurations, and automated deployment scripts for quick, efficient network experimentation and validation.

## Showroom: Cisco IOL flash
Each Cisco IOL node mounts `showroom/flash/<node>` as `unix:/flash/` (persistent snapshots and rollback files,
kept outside `clab-showroom/` so `--reconfigure` does not remove them). Containerlab requires the folders to
exist before deploying:
```
mkdir -p showroom/flash/{core1,core2,dist1-1,dist1-2,dist2-1,dist2-2,access1-1,access1-2,access2-1,access2-2}
containerlab deploy -t showroom/showroom.clab.yml --reconfigure
```
