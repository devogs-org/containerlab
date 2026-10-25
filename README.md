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

## Showroom: CPU limits
The containers of the showroom are capped so a broadcast or DHCP storm cannot take the whole host (the Cisco IOL L2 images
reject `storm-control` and MQC `service-policy`, so the container is the only place to limit them). Host of 16 CPUs:

| CPUs | Used by | Cap |
|---|---|---|
| 0-5 | SR Linux, one core per node (`cpu-set` per node) | `cpu: 1` each |
| 6-11 | VyOS, Cisco IOL and the Alpine hosts (`cpu-set: "6-11"` in their groups) | VyOS `cpu: 1.5`, IOL `cpu: 0.5`, hosts `cpu: 0.25` each |
| 12-15 | the other services of the host (NetBox, LibreNMS, OpenObserve, Semaphore) | none |

At idle each IOL node uses about 1% and each firewall 0.3%. The limits apply at deploy time: redeploy to change them
(`docker update --cpus <n> --cpuset-cpus 6-11 <container>` changes a running container until the next deploy).
Check with `docker inspect clab-showroom-core1 --format '{{.HostConfig.CpuQuota}} {{.HostConfig.CpusetCpus}}'`
(`50000 6-11`).
