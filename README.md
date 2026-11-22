# containerlab
Generic, reusable network lab topologies built with Containerlab. Features various NOS (Tarvos, Cisco IOL, VyOS), L2/L3 configurations, and automated deployment scripts for quick, efficient network experimentation and validation.

## Showroom: Cisco IOL flash
Each Cisco IOL node mounts `showroom/flash/<node>` as `unix:/flash/` (persistent snapshots and rollback files,
kept outside `clab-showroom/` so `--reconfigure` does not remove them). Containerlab requires the folders to
exist before deploying:
```
mkdir -p showroom/flash/{core1,core2,dist1-1,dist1-2,dist2-1,dist2-2,access1-1,access1-2,access2-1,access2-2}
containerlab deploy -t showroom/showroom.clab.yml --reconfigure
```

## Showroom: Tarvos data-center fabric
The data center (BorderLeaf-1/2, Spine-1/2, Leaf-1/2/3, mgmt 10.16.10.21-27) runs [Tarvos](https://github.com/devogs/tarvos) (`matt13290/tarvos`,
FRR + NETCONF), as the `linux` kind with the capabilities of its docker-compose file. Ports are `eth1`, `eth2`, ... (`eth0` is in VRF `mgmt`).
The nodes boot empty: the fabric is configured by showroom-ansible over NETCONF (`playbooks/day1_datacenter.yml`), from NetBox.
Export the two secrets of the group before deploying, they are only read at deploy time (the TACACS+ servers and key are then set by
Ansible over NETCONF, tag `tacacs`):
```
export TACACS_KEY=...              # TACACS_KEY of showroom-identity/.env
export TARVOS_ADMIN_PASSWORD=...   # local admin (break-glass), TARVOS_SSH_PASSWORD of showroom-ansible/.env
```
Syslog (10.16.10.100), gNMI (57400) and LLDP come from the environment of the group. NTP is the host clock (container).

## Showroom: CPU limits
The containers of the showroom are capped so a broadcast or DHCP storm cannot take the whole host (the Cisco IOL L2 images
reject `storm-control` and MQC `service-policy`, so the container is the only place to limit them). Host of 16 CPUs:

| CPUs | Used by | Cap |
|---|---|---|
| 0-5 | Tarvos, the 7 nodes share them (`cpu-set: "0-5"` in their group) | `cpu: 1`, `memory: 1gb` each (~115 MiB used) |
| 6-11 | VyOS, Cisco IOL and the Alpine clients and servers (`cpu-set: "6-11"` in their groups) | VyOS `cpu: 1.5`, IOL `cpu: 0.5`, clients/servers `cpu: 0.25` each; memory caps: VyOS `2gb`, IOL `768mb`, clients/servers `64mb` |
| 12-15 | the other services of the host (NetBox, LibreNMS, OpenObserve, Semaphore) | none |

At idle each IOL node uses about 1% and each firewall 0.3%. The limits apply at deploy time: redeploy to change them
(`docker update --cpus <n> --cpuset-cpus 6-11 <container>` changes a running container until the next deploy).
Check with `docker inspect clab-showroom-core1 --format '{{.HostConfig.CpuQuota}} {{.HostConfig.CpusetCpus}}'`
(`50000 6-11`).

## Showroom: VyOS logs are streamed, not kept
The firewalls send their syslog to the collector and keep nothing (twelve-factor logs). `showroom/configs/vyos-journald.conf`
is mounted as a journald drop-in: volatile journal (RAM), 32M maximum, 500 messages per 30 s and service. Without it the
persistent journal grew to 3.9 GB in a DHCP storm (Kea logs every packet). The local syslog sink is removed by Ansible
(`day1_campus`, tag `syslog`). Check: `docker exec clab-showroom-FW1 systemd-analyze cat-config systemd/journald.conf`.

## Showroom: iperf3 servers
`server5` (Leaf-3 `eth10`, DC-APP-A) and `server6` (Leaf-3 `eth11`, DC-APP-B) run `iperf3 -s` (5201/tcp) with a static eth1
and no management interface. The image is `networkstatic/iperf3` plus `iproute2` and `ping` (the upstream image has no `ip`), built locally
before the deploy (`image-pull-policy: never`):
```
docker build -t showroom/iperf3:latest showroom/images/iperf3
```
Check: `docker exec clab-showroom-server5 ss -ltn` (5201 listening). They are the pool of the HAProxy service of the firewalls
(`day2_security`, tag `haproxy`).
