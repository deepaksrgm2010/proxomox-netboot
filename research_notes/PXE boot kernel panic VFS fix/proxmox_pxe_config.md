# Proxmox VE 9.x PXE Network Boot Configuration

## What are the correct kernel boot parameters for Proxmox VE 9.x PXE boot?

### Takeaway
The working kernel line for Proxmox VE 9.x iPXE boot is `ramdisk_size=16777216 rw quiet splash=silent initrd=initrd.img`, and the `initrd=initrd.img` argument on the kernel line is mandatory — its absence is the most commonly reported cause of a kernel panic.

### Cited Findings
- The `proxmox-auto-install-assistant prepare-iso` tool generates a `boot.ipxe` (when `--pxe-loader ipxe` is passed) whose kernel line reads: `kernel vmlinuz ramdisk_size=16777216 rw quiet initrd=initrd.img <extra_params>` — [Proxmox lore patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)
- For automated install, add `splash=silent proxmox-start-auto-installer` as extra params — [Proxmox lore patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)
- Full working iPXE config confirmed on PVE 9.1 (ririmia, Mar 2026):
  ```
  #!ipxe
  dhcp
  initrd http://my.http.server.address/proxmox/initrd.img
  kernel http://my.http.server.address/proxmox/vmlinuz initrd=initrd.img ramdisk_size=16777216 rw quiet splash=silent proxmox-start-auto-installer
  boot
  ```
  — [Proxmox Forum Tutorial Thread](https://forum.proxmox.com/threads/automated-installation-pxe-boot.169009/)
- Missing `initrd=initrd.img` on the kernel line is the reported cause of the PVE 9.1 kernel panic — [Proxmox Forum](https://forum.proxmox.com/posts/853098/)

### Inferences
- Both an `initrd` iPXE directive (to load the file) AND `initrd=initrd.img` on the kernel line (to tell the kernel where to find it) are required simultaneously.

### Gaps
- No official Proxmox wiki page explicitly documents the `proxmox-start-auto-installer` kernel parameter by name; this is derived from the patch source and community posts.

---

## What is the correct filename for the kernel and initrd?

### Takeaway
On the ISO the kernel is `/boot/linux26` and initrd is `/boot/initrd.img` (zstd-compressed). The `prepare-iso --pxe` tool renames the kernel to `vmlinuz` and recompresses initrd.img from zstd to gzip (since iPXE does not support zstd).

### Cited Findings
- `prepare-iso --pxe` extracts `/boot/linux26` from the ISO and writes it as `vmlinuz` — [Proxmox lore patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)
- `prepare-iso --pxe` extracts `/boot/initrd.img` (zstd), recompresses it to gzip, and writes it as `initrd.img` — [Proxmox lore patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)
- iPXE does not support zstd-compressed initrds; the recompression step is necessary — [Proxmox lore patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)

### Inferences
- If manually extracting from the ISO (without `prepare-iso`), you must: rename `/boot/linux26` → `vmlinuz` and recompress `/boot/initrd.img` from zstd to gzip before serving over PXE.

### Gaps
- None — this is well confirmed by the patch source.

---

## What does `proxmox-start-auto-installer` do vs `proxmox-auto-install-mode=answer-file`?

### Takeaway
`proxmox-start-auto-installer` is a kernel parameter that triggers the unattended installer. `proxmox-auto-install-mode` is not mentioned anywhere in the sources found; the install mode (http, iso, partition) is embedded into the prepared ISO at `prepare-iso` time via `auto-installer-mode.toml`.

### Cited Findings
- `proxmox-start-auto-installer` as a kernel parameter is listed as the "automated" install option in the boot menu; without it the installer opens in interactive GUI/TUI mode — [Proxmox lore patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)
- Other installer-mode parameters from the generated menu: `proxmox-tui-mode`, `proxmox-debug`, `vga=788`, `console=ttyS0,115200` — none of these control the answer-file fetch mode — [Proxmox lore patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)
- The fetch mode is written into the modified ISO's `auto-installer-mode.toml` at `prepare-iso` time; the iPXE config never references the answer file URL directly — [Proxmox lore patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)

### Inferences
- `proxmox-auto-install-mode` is not a real kernel parameter for PVE 9.x. The correct mechanism is to bake the fetch mode into the ISO with `prepare-iso --fetch-from http`.

### Gaps
- No source explicitly documents `proxmox-auto-install-mode` as a valid or invalid parameter. It may exist in older Proxmox versions or be entirely fictional.

---

## How should `proxmox-auto-install-url` be specified for fetching an answer file over HTTP?

### Takeaway
The answer file URL is NOT passed on the kernel line. It is embedded into the ISO at `prepare-iso` time using `--url`. In PXE mode the modified ISO is served alongside vmlinuz and initrd.img, and the installer reads the URL from the ISO's internal `auto-installer-mode.toml`.

### Cited Findings
- The `prepare-iso` command embeds the URL: `proxmox-auto-install-assistant prepare-iso /path/to/source.iso --fetch-from http --url "https://10.0.0.100/answer" --pxe --output /srv/tftp/proxmox-auto/` — [Proxmox VE Wiki: Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation)
- The patch notes confirm `--url` and `--cert-fingerprint` only affect the output file name suffix; the URL is stored inside the modified ISO — [Proxmox lore patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)
- HTTP is described as "the natural fit" for a fully network-based provisioning workflow — [Proxmox VE Wiki: Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation)
- A community workaround (when HTTP fetch fails) is to embed the answer file ISO as `/proxmox.iso` inside the initrd.img and repack it — [Proxmox Forum Tutorial Thread](https://forum.proxmox.com/threads/automated-installation-pxe-boot.169009/)
- One user reported the HTTP fetch method did not work when booting from the extracted kernel/initrd (without using `prepare-iso` correctly) — [Proxmox Forum](https://forum.proxmox.com/posts/853098/)

### Inferences
- The `proxmox-auto-install-url` kernel parameter may not exist at all as a runtime parameter. The URL must be injected into the ISO before PXE serving.

### Gaps
- No source confirms whether the URL can be overridden on the kernel command line at all.

---

## Are there official Proxmox docs or community guides for netboot/PXE of Proxmox VE 9.x?

### Takeaway
The official Proxmox wiki page "Automated Installation" covers the `prepare-iso --pxe` workflow but does not show the full iPXE script content or kernel parameters explicitly. The main detailed guide is a community tutorial thread on the Proxmox forum.

### Cited Findings
- Official wiki: [Proxmox VE Wiki: Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation) — covers the `prepare-iso` command and `--pxe`/`--pxe-loader` flags but does not show generated iPXE config text
- Proxmox lore mailing list patch that added PXE support: [lore.proxmox.com patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t) — contains the full iPXE template and file extraction logic; the patch is dated Feb 2026, revised Mar 2026
- Community tutorial: [Proxmox Forum Tutorial Thread](https://forum.proxmox.com/threads/automated-installation-pxe-boot.169009/) — the most complete working example with DHCP config, iPXE script, and troubleshooting for PVE 9.x
- Known failure thread for Proxmox 9.2 with iPXE error 0x2a818006: [Proxmox Forum](https://forum.proxmox.com/threads/pxe-boot-of-proxmox-9-8-fails-with-ipxe-error-0x2a818006.184393/) — unresolved as of the thread's last post

### Inferences
- The `--pxe-loader ipxe` flag was added relatively recently (patch Feb–Mar 2026) and may not be in all released versions of `proxmox-auto-install-assistant`.

### Gaps
- No official Proxmox documentation shows the full generated `boot.ipxe` content inline on the wiki.

---

## What files need to be extracted from the Proxmox ISO for PXE boot to work?

### Takeaway
Using `proxmox-auto-install-assistant prepare-iso --fetch-from http --url <url> --pxe-loader ipxe --output <dir>` produces all required files. Manually you need: `vmlinuz` (from `/boot/linux26`), `initrd.img` (from `/boot/initrd.img`, recompressed gzip), the modified ISO (with answer config baked in), and optionally `boot.ipxe`.

### Cited Findings
- Files produced by `prepare-iso --pxe`: `vmlinuz`, `initrd.img`, the modified ISO, and `boot.ipxe` (when `--pxe-loader ipxe` is passed) — [Proxmox lore patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)
- The modified ISO has its `/boot` directory removed to save ~100 MiB — [Proxmox lore patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)
- The ISO is served as `proxmox.iso` alongside the kernel and initrd; the init process mounts it at boot — [Proxmox lore patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)
- In the iPXE config, the ISO is loaded as a second initrd: `initrd {iso_filename} proxmox.iso` — [Proxmox lore patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)
- The full iPXE `load` block:
  ```
  :load
  initrd initrd.img
  initrd {iso_filename} proxmox.iso
  boot
  ```
  — [Proxmox lore patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)

### Inferences
- The ISO must be served over HTTP (iPXE can load large files via HTTP much better than TFTP). Putting the full ISO on TFTP risks size/memory errors.
- The zstd→gzip recompression of initrd.img is a hard requirement, not optional.

### Gaps
- Whether `prepare-iso` is available in the version of `proxmox-auto-install-assistant` shipping with PVE 9.2 specifically has not been confirmed from official release notes.

---

## Known Failures and Error Codes

### iPXE Error 0x2a818006
- Meaning: "No buffer space available" (from iPXE error code documentation) — [Proxmox Forum](https://forum.proxmox.com/threads/pxe-boot-of-proxmox-9-8-fails-with-ipxe-error-0x2a818006.184393/)
- Reported on Proxmox VE 9.2-1 and 8.x with legacy BIOS iPXE 2.0.0+ on ThinkPad X220 with 8 GB RAM — unresolved — [Proxmox Forum](https://forum.proxmox.com/threads/pxe-boot-of-proxmox-9-8-fails-with-ipxe-error-0x2a818006.184393/)
- Staff suggestion: may relate to insufficient memory for PXE installation even on systems with adequate RAM for normal operation

### Kernel Panic / VFS Unable to Mount Root FS
- Most common PXE cause: missing `initrd=initrd.img` on the kernel line (not just the iPXE `initrd` directive) — [Proxmox Forum](https://forum.proxmox.com/posts/853098/)
- Secondary cause: serving a zstd-compressed initrd.img directly (iPXE cannot decompress zstd) — [Proxmox lore patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)
- Tertiary cause: wrong initrd filename mismatch between iPXE `initrd` directive and `initrd=` kernel parameter — [Proxmox Forum](https://forum.proxmox.com/posts/853098/)
