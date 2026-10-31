# proxmox-auto-install-assistant prepare-iso and PXE Boot

## What does `prepare-iso --fetch-from http` do to the ISO?

### Takeaway
`--fetch-from http` does NOT embed the answer file in the ISO. It configures the installer to POST system information to a URL at runtime and receive the answer file as a response. Only the URL (and optional auth token/cert fingerprint) is baked into the ISO.

### Cited Findings
- `prepare-iso --fetch-from http` writes the answer-file URL into the ISO. At install time, the installer sends an HTTP POST to that URL with system information (DMI data, disks, network interfaces), and the server responds with a TOML/JSON answer file. — [Proxmox Wiki: Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation)
- An optional `--answer-auth-token` can be embedded; the token is stored in plain text in the ISO. — [Proxmox Wiki: Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation)
- The `--fetch-from iso` mode is the one that embeds the full `answer.toml` directly in the ISO. `http` mode only embeds the URL pointer. — [Proxmox Wiki: Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation)
- The output filename from `prepare-iso` gets an `-auto-from-http` suffix when the HTTP method is used. — [pve-devel mailing list patch](https://lore.proxmox.com/all/DHH448MZN82C.1R4WQHA2X38OX@proxmox.com)

### Inferences
- Since only the URL is embedded, a single prepared ISO can serve multiple installs (the server decides what answer file to return based on the POSTed hardware info). This is the main advantage of `--fetch-from http` over `--fetch-from iso`.

### Gaps
- No primary source precisely documents what field(s) inside the ISO are modified (e.g., which file in the ISO filesystem holds the URL config).

---

## Does the prepared ISO's kernel/initrd differ from the original ISO's files?

### Takeaway
The kernel (`linux26`/`vmlinuz`) does NOT change. The initrd from a `prepare-iso` run (without `--pxe`) is also unchanged from the original — but the initrd must be further modified for PXE boot to work correctly.

### Cited Findings
- The `--pxe` flag (a newer addition to the assistant) extracts the kernel as `vmlinuz` and re-compresses the initrd from zstd to gzip (because iPXE does not support zstd). It also removes `/boot` from the ISO copy to save ~100 MiB. — [pve-devel mailing list patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)
- Without `--pxe`, the initrd inside the prepared ISO remains in zstd format, same as the original Proxmox ISO. — [pve-devel mailing list patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)
- Forum community workaround: a user extracted `linux26` and `initrd.img` from the prepared ISO, repacked the initrd with the prepared ISO embedded as `/proxmox.iso` (because the init script looks for that path), and booted that over iPXE. — [Proxmox Forum Tutorial](https://forum.proxmox.com/posts/846256/)
- The init script inside the Proxmox initrd looks for a `/proxmox.iso` file to load the rest of the installer from. — [Proxmox Forum Tutorial](https://forum.proxmox.com/posts/853098/)

### Inferences
- For PXE with `--fetch-from http`, one of the following is required: (a) use `--pxe` flag to get gzip-recompressed initrd and a `boot.ipxe` that loads the ISO as a secondary initrd, OR (b) manually repack the initrd with the prepared ISO embedded as `/proxmox.iso`.
- The kernel file itself is safe to take directly from either the original or prepared ISO — it is not modified.

### Gaps
- It is unclear whether the `--pxe` flag was included in the Proxmox 9.2 release build of `proxmox-auto-install-assistant` or only landed in a later package update. The patch was posted in early 2026; PVE 9.2 release timeline relative to that patch is unknown.

---

## Does the prepared ISO itself need to be served over HTTP for PXE boot?

### Takeaway
When using `--pxe` mode, the ISO must be reachable from the PXE server (TFTP or HTTP) because iPXE loads it as a secondary initrd. Without `--pxe`, the ISO is embedded inside the repacked initrd and does not need to be served separately — but then the initrd becomes very large (~700 MB+).

### Cited Findings
- With the `--pxe` flag, the generated `boot.ipxe` script loads the ISO via `initrd {iso_filename} proxmox.iso`. The ISO therefore must be accessible to the iPXE client at the configured URL/path. — [pve-devel mailing list patch](https://lore.proxmox.com/all/DHH448MZN82C.1R4WQHA2X38OX@proxmox.com)
- The patch author tested by copying `boot.ipxe`, `vmlinuz`, `initrd.img`, and the `.iso` to the TFTP root — the ISO was served over TFTP, not HTTP. — [pve-devel mailing list patch](https://lore.proxmox.com/all/DHH448MZN82C.1R4WQHA2X38OX@proxmox.com)
- In the forum community workaround (embedding ISO inside initrd), the ISO is not served separately — it is extracted at boot from within the initrd. — [Proxmox Forum Tutorial](https://forum.proxmox.com/posts/846256/)
- Plain PXE (non-iPXE) hit a memory error when the large ISO-embedded initrd was loaded. Switching to iPXE resolved this. — [Proxmox Forum Tutorial](https://forum.proxmox.com/posts/853098/)

### Inferences
- Serving the ISO over HTTP (as opposed to TFTP) is more efficient for large files (~1 GB ISO) since iPXE's HTTP support handles large files better. For a TFTP-only setup, serving the ISO over TFTP may work but is slower.

### Gaps
- No source clarifies whether there is a maximum file size limit for the ISO when served over TFTP with iPXE. The patch author tested with TFTP but didn't document file size constraints.

---

## What is the `proxmox-auto-install-iso-url` kernel parameter for?

### Takeaway
No official Proxmox documentation or mailing-list source was found that documents a kernel parameter named `proxmox-auto-install-iso-url`. It may not exist as a supported parameter, or may be a community-specific implementation.

### Cited Findings
- The documented kernel parameter for triggering automated installation is `proxmox-start-auto-installer`. — [Proxmox Forum Tutorial](https://forum.proxmox.com/posts/853098/)
- No search results or official docs mention `proxmox-auto-install-iso-url` as a valid kernel parameter. — multiple searches conducted
- A community script (`pve-iso-2-pxe.sh`) rebuilds the initrd and may use custom kernel parameters to pass the ISO or answer URL, but this is an unofficial workaround. — [GitHub: morph027/pve-iso-2-pxe](https://github.com/morph027/pve-iso-2-pxe/blob/master/pve-iso-2-pxe.sh)

### Inferences
- The parameter name `proxmox-auto-install-iso-url` may be from an older community workaround, a misremembered name, or from the `pve-iso-2-pxe.sh` community script, not from the official Proxmox installer.

### Gaps
- Could not confirm whether this parameter exists in any Proxmox installer version. The official docs and mailing list only reference `proxmox-start-auto-installer` as the relevant kernel parameter.

---

## Known issues extracting boot files from prepared vs original ISO

### Takeaway
The main practical issue is that the prepared ISO's initrd is zstd-compressed, which iPXE does not support. Additionally, booting the kernel and initrd without the ISO file accessible causes the installer to fail looking for `/proxmox.iso`.

### Cited Findings
- iPXE does not support zstd-compressed initrd. The `--pxe` flag in the assistant converts the initrd to gzip to work around this. Without the flag, users must manually recompress. — [pve-devel mailing list patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)
- A user on PVE 9.1 (similar to 9.2) got a kernel panic under iPXE that was fixed by adding `initrd=initrd.img` to the kernel line. — [Proxmox Forum Tutorial](https://forum.proxmox.com/posts/853098/)
- When the `--fetch-from http` mode was used with a PXE-extracted kernel/initrd (without the ISO accessible), the HTTP fetch method was reported as unavailable — the installer could not reach the answer file URL. — [Proxmox Forum Tutorial](https://forum.proxmox.com/posts/846256/)
- Repacking the initrd with zstd at level -19 takes ~15 minutes; using level -5 reduces this to ~1 minute with only modest size increase. — [Proxmox Forum Tutorial](https://forum.proxmox.com/posts/853098/)

### Inferences
- The "HTTP fetch unavailable" failure when booting via PXE without the ISO accessible likely occurs because the init script fails to mount the installer environment (from `/proxmox.iso`) before the network fetch code runs. Without the ISO mounted, the full installer never starts.
- For PVE 9.2 PXE boot with `--fetch-from http`: the correct approach is either (a) use `--pxe` flag to get proper gzip initrd + `boot.ipxe` that also loads the ISO, or (b) manually repack the initrd with the prepared ISO at `/proxmox.iso` AND recompress from zstd to gzip for iPXE compatibility.

### Gaps
- No source confirms whether `proxmox-auto-install-assistant` version shipped with PVE 9.2 includes the `--pxe` flag. The flag was proposed in a mailing-list patch in early 2026; it needs to be verified whether it landed in the 9.2 package.
- No authoritative documentation explains the exact init sequence and at what point the ISO must be available before HTTP fetch is attempted.
