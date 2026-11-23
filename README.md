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

## Showroom: Cisco IOL entrypoint
The IOL images (vrnetlab c467f0d) start `iouyap` and IOL after a fixed `sleep 5`. Two races follow:
- **Data links:** `iouyap` and the IOL slot count use the `eth*` present at that moment. A link attached later
  makes `iouyap` exit (`docker logs`: `iouyap: ioctl: No such device`) and IOL run with `-e 1`.
- **Boot config:** containerlab empties `boot_config.txt` (`/iol/config.txt`) at every deploy and writes it in its
  post-deploy step. That step runs one node at a time, and on a redeploy that keeps `nvram_*` (destroy without
  `--cleanup`) it also types the mgmt IP on each IOL console and waits for the prompt. IOS then boots with an empty
  config: setup dialog or `Switch>`, no mgmt IP, SSH closed. Containerlab's own `wr` can then save that empty
  config to nvram, so the node stays broken on later redeploys until `--cleanup`.

`showroom/iol-entrypoint.sh` is bind-mounted over `/entrypoint.sh` in the `cisco` group (the file must stay
executable). It waits for the `CLAB_INTFS` data interfaces (`IOL_INTF_WAIT_TIMEOUT`, 300 s, then exit 1) and for
a non-empty `/iol/config.txt` (`IOL_CONFIG_WAIT_TIMEOUT`, 900 s, then boot anyway). Check a node with
`docker logs clab-showroom-core1 | grep -E 'Data interfaces ready|Boot config ready'`.

Redeploy times on this topology: `destroy --cleanup` then `deploy` takes ~25 s (first boot, no console step).
A plain `destroy` then `deploy` works too, but takes ~6 min because containerlab boots and configures the IOL nodes
one after the other. Use `--cleanup` unless the IOL nvram must be kept (snapshots in `showroom/flash/` are kept
either way).

## Showroom: CPU limits
The containers of the showroom are capped so a broadcast or DHCP storm cannot take the whole host (the Cisco IOL L2 images
reject `storm-control` and MQC `service-policy`, so the container is the only place to limit them). Host of 16 CPUs:

| CPUs | Used by | Cap |
|---|---|---|
| 0-5 | SR Linux, one core per node (`cpu-set` per node) | `cpu: 1`, `memory: 4gb` each |
| 6-11 | VyOS, Cisco IOL and the Alpine hosts (`cpu-set: "6-11"` in their groups) | VyOS `cpu: 1.5`, IOL `cpu: 0.5`, hosts `cpu: 0.25` each; memory caps: VyOS `2gb`, IOL `768mb`, hosts `64mb` |
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
`server9` (Leaf-1 `ethernet-1/12`, DC-APP-A) and `server10` (Leaf-2 `ethernet-1/12`, DC-APP-B) run `iperf3 -s` (5201/tcp) with a static eth1
and no management interface. The image is `networkstatic/iperf3` plus `iproute2` and `ping` (the upstream image has no `ip`), built locally
before the deploy (`image-pull-policy: never`):
```
docker build -t showroom/iperf3:latest showroom/images/iperf3
```
Check: `docker exec clab-showroom-server9 ss -ltn` (5201 listening). They are the pool of the HAProxy service of the firewalls
(`day2_security`, tag `haproxy`).
