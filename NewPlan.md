Act as a senior DevOps and Network Engineer. I am setting up an automated, local network-booting (PXE) architecture using Docker. I need to integrate netboot.xyz (for iPXE serving/web UI) and dnsmasq (acting as a primary DHCP and DNS server, not a proxy) to provision Proxmox VE (PVE) locally.

Please review the architectural specification below and generate the deployment artifacts.

### 1. ENVIRONMENTAL PARAMETERS (.env)
We must use environment variables to keep the deployment dynamic.
- HOST_IP=192.168.1.50
- SUBNET_MASK=255.255.255.0
- DHCP_START=192.168.1.100
- DHCP_END=192.168.1.200
- DHCP_LEASE=12h
- ROUTER_GW=192.168.1.1
- DNS_SERVER=1.1.1.1

### 2. DOCKER COMPOSE CORE SPECIFICATION
- Service 1: `netbootxyz` using `lscr.io/linuxserver/netbootxyz:latest`. It must bind standard ports (3000:WebUI, 69/udp:TFTP, 80:HTTP Web Server) and map standard host volumes for `./config` and `./assets`. It runs without root network access.
- Service 2: `dnsmasq` using `alpine:latest`. It must run in `network_mode: host` and possess `NET_ADMIN` capabilities to allow raw DHCP socket binding on port 53 and port 67.
- Configuration Substitution: The dnsmasq container must execute a startup command that installs `gettext` to use `envsubst`, processes an `/etc/dnsmasq.conf.template` file into a writeable runtime directory (`/etc/dnsmasq_runtime/dnsmasq.conf`), and launches dnsmasq reading that dynamic file.

### 3. DNSMASQ CONFIGURATION TEMPLATE (`dnsmasq.conf.template`)
- Must run as an authoritative Primary DHCP server (no 'proxy' flag).
- Enable DNS handling on port 53.
- Map architectural options 60 (PXEClient:Arch:00000 -> bios, 00007/00009 -> efi64, 0000B -> efi64-3/arm64).
- Inject the bootfile and TFTP target string using `dhcp-boot` matching those architectural tags directly to \$HOST_IP. 
- Crucial: Strip or comment out any legacy `pxe-service` lines to avoid UEFI client handshake confusion in Primary DHCP mode.

### 4. LOCAL PROXMOX ASSET MANAGEMENT & IPXE CUSTOM MENUS
Proxmox cannot stream kernel images over WAN, so we host them locally on the container's Nginx asset instance.
- Asset Layout: Assume Proxmox 'linux26' (kernel) and 'initrd.img' (ramdisk) are extracted into `./assets/proxmox/8.2/`.
- Local iPXE Variables (`config/menus/local-vars.ipxe`): Point a `live_endpoint_local` variable to http://\$HOST_IP:80.
- Custom Boot Logic (`config/menus/custom.ipxe`): Create an iPXE selection script that references that local endpoint, arguments the kernel (`vga=791 video=vesafb:ywrap,mtrr ramdisk_size=16777216 splash=verbose`), chains the initrd file, and invokes `boot`.
- Master Chain-load: Append an option into the pre-existing `config/menus/menu.ipxe` to expose this "Local Custom Menus" file to the initial boot loader splash interface.

### WHAT I NEED FROM YOU:
1. Provide the complete, finalized `docker-compose.yml` leveraging the on-the-fly `envsubst` compilation trick.
2. Provide the exact text for `dnsmasq.conf.template` with proper variable substitution syntax.
3. Provide the precise iPXE scripting files (`local-vars.ipxe` and `custom.ipxe`) ensuring they parse the web asset routes seamlessly.
4. Give me a brief, punchy validation checklist to verify port 53 / port 67 availability on my host before executing `docker compose up -d`.
