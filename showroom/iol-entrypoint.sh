#!/bin/bash
# Patched vrnetlab IOL entrypoint (image vrnetlab c467f0d). It fixes two startup races of the stock script,
# which starts iouyap and IOL after a fixed "sleep 5":
#  1. Data links: iouyap and the IOL slot count (-e) use the eth* present at that moment. When containerlab
#     attaches the links later, iouyap dies ("ioctl: No such device") and IOL boots with too few slots.
#     Fix: wait for the CLAB_INTFS data interfaces.
#  2. Boot config: containerlab empties boot_config.txt (/iol/config.txt) at every deploy and writes it only in
#     its post-deploy step. On a redeploy that keeps nvram_* (destroy without --cleanup), that step also types
#     the mgmt IP on the console of each IOL node one after the other (~10 s each), so most nodes boot with an
#     empty config and stop at the setup dialog (no hostname, no mgmt IP, SSH closed).
#     Fix: wait until /iol/config.txt has content (the placeholder can hold a lone newline, so not just -s).

echo "Launching IOL with PID" $IOL_PID

# Clear ip addressing on eth0 (it 'belongs' to IOL now)
ip addr flush dev eth0
ip -6 addr flush dev eth0
echo "Flushed eth0 addresses"

# 1. Data interfaces
expected=${CLAB_INTFS:-0}
intf_timeout=${IOL_INTF_WAIT_TIMEOUT:-300}
waited=0
while :; do
  count=$(ls /sys/class/net | grep -cE '^eth[1-9][0-9]*$')
  [ "$count" -ge "$expected" ] && break
  if [ "$waited" -ge "$intf_timeout" ]; then
    echo "ERROR: only $count/$expected data interfaces after ${intf_timeout}s, aborting" >&2
    exit 1
  fi
  sleep 1
  waited=$((waited + 1))
done
echo "Data interfaces ready: $count/$expected after ${waited}s"

# 2. Boot config written by the containerlab post-deploy step
cfg_timeout=${IOL_CONFIG_WAIT_TIMEOUT:-900}
waited=0
while ! grep -q '[^[:space:]]' /iol/config.txt 2>/dev/null; do
  if [ "$waited" -ge "$cfg_timeout" ]; then
    echo "WARNING: /iol/config.txt still empty after ${cfg_timeout}s, booting without it" >&2
    break
  fi
  sleep 1
  waited=$((waited + 1))
done
grep -q '[^[:space:]]' /iol/config.txt 2>/dev/null && echo "Boot config ready: $(wc -c < /iol/config.txt) bytes after ${waited}s"

# Short settle delay: last veth fully up before iouyap binds to it, boot config fully written
sleep 2

# Run IOUYAP
/usr/bin/iouyap 513 -q &

# Get the highest numbered eth interface
max_eth=$(ls /sys/class/net | grep eth | grep -o -E '[0-9]+' | sort -n | tail -1)
num_slots=$(( (max_eth + 4) / 4 ))

# Start IOL
exec /iol/iol.bin $IOL_PID -e $num_slots -s 0 -c config.txt -n 1024
