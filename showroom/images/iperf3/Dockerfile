# iperf3 server of the data center: networkstatic/iperf3 plus the tools the topology needs to configure eth1 (the image has no `ip`)
# and to prime the MAC learning of the leaf (`ping`). Build before the deploy:
#   docker build -t showroom/iperf3:latest showroom/images/iperf3
FROM networkstatic/iperf3:latest
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends iproute2 iputils-ping \
    && rm -rf /var/lib/apt/lists/*
