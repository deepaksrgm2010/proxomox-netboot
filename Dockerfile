FROM ghcr.io/netbootxyz/netbootxyz

RUN apk add --no-cache gettext dnsmasq

COPY profiles/proxmox/dnsmasq.conf /etc/dnsmasq.conf

