#!/bin/bash
# Patched vrnetlab IOL entrypoint (image vrnetlab c467f0d).
# The stock script starts iouyap after a fixed "sleep 5" and sizes the IOL slots
# from the interfaces present at that moment. On a large topology containerlab
# has not attached all links yet, so iouyap dies ("ioctl: No such device") and
# IOL boots with too few slots. This version waits for CLAB_INTFS data interfaces.

echo "Launching IOL with PID" $IOL_PID

# Clear ip addressing on eth0 (it 'belongs' to IOL now)
ip addr flush dev eth0
ip -6 addr flush dev eth0
echo "Flushed eth0 addresses"

expected=${CLAB_INTFS:-0}
timeout=${IOL_INTF_WAIT_TIMEOUT:-300}
waited=0
while :; do
  count=$(ls /sys/class/net | grep -cE '^eth[1-9][0-9]*$')
  [ "$count" -ge "$expected" ] && break
  if [ "$waited" -ge "$timeout" ]; then
    echo "ERROR: only $count/$expected data interfaces after ${timeout}s, aborting" >&2
    exit 1
  fi
  sleep 1
  waited=$((waited + 1))
done
echo "Data interfaces ready: $count/$expected after ${waited}s"

# Short settle delay so the last veth is fully up before iouyap binds to it
sleep 2

# Run IOUYAP
/usr/bin/iouyap 513 -q &

# Get the highest numbered eth interface
max_eth=$(ls /sys/class/net | grep eth | grep -o -E '[0-9]+' | sort -n | tail -1)
num_slots=$(( (max_eth + 4) / 4 ))

# Start IOL
exec /iol/iol.bin $IOL_PID -e $num_slots -s 0 -c config.txt -n 1024
