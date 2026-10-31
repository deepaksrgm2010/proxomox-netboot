# Three Bugs Cause Proxmox 9.2 PXE Boot Panic

The `Kernel Panic: VFS: Unable to mount root fs on unknown-block(0,0)` error when PXE booting Proxmox VE 9.2 via iPXE is caused by three compounding issues in the current pipeline: a missing `initrd=initrd.img` argument on the kernel command line (the primary and most common cause), a zstd-compressed initrd that iPXE cannot decompress, and a missing ISO file that the Proxmox init process requires at boot. Each of these independently causes a panic or installer failure; in the current setup, all three are present simultaneously. The fix requires switching to `proxmox-auto-install-assistant prepare-iso` with the `--pxe` flag, serving the prepared ISO as a second iPXE initrd, and adding `initrd=initrd.img` to the kernel line.

## Missing `initrd=` on the kernel line is the immediate panic trigger

On UEFI systems, the Linux EFI stub does not automatically discover an initrd that iPXE has loaded into memory. Instead, it relies on the `initrd=<basename>` kernel command-line argument to locate the file in iPXE's virtual filesystem by name. Without this argument, the kernel boots with no initramfs at all, finds no root device, and panics with `unknown-block(0,0)`. The current `custom.ipxe` includes an `initrd` iPXE directive to download the file, but omits `initrd=initrd.img` from the `kernel` line — exactly the failure mode confirmed on Proxmox VE 9.1, where adding `initrd=initrd.img` resolved the panic immediately ([Proxmox Forum](https://forum.proxmox.com/posts/853098/)). On legacy BIOS, iPXE automatically builds a CPIO archive from downloaded initrds, so BIOS machines may not exhibit this symptom — but the parameter is required for UEFI and harmless on BIOS ([iPXE Forum tid=8058](https://forum.ipxe.org/showthread.php?tid=8058)). The `initrd=` basename must match the last path component of the URL used in the `initrd` command; since the URL ends in `/initrd.img`, the correct value is `initrd=initrd.img` ([Ironic release note](https://gitea14.opendev.org:3081/openstack/ironic/src/branch/master/releasenotes/notes/initrd_filename-ac68e96f1c9fb576.yaml)).

## The Proxmox ISO's initrd is zstd-compressed and iPXE cannot load it

The second bug is in the pipeline's ISO extraction step. The Proxmox 9.2 ISO stores `boot/initrd.img` compressed with zstd. **iPXE has no zstd decompression support**, so loading the raw extracted `initrd.img` directly will either silently fail or cause a boot error before the kernel even starts ([pve-devel mailing list patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)). The current Docker pipeline uses `xorriso` to extract `boot/linux26` and `boot/initrd.img` from the prepared ISO without recompression — serving a zstd artifact that iPXE cannot handle. The official fix, introduced by the `--pxe` flag in `proxmox-auto-install-assistant`, is to decompress the initrd and recompress it as gzip before serving. If doing this manually, the recompression step is `zstd -d initrd.img | gzip > initrd.img.gz`; using `zstd -5` rather than the default `-19` reduces the ~15-minute recompression time to about 1 minute with minimal size increase ([Proxmox Forum](https://forum.proxmox.com/posts/853098/)).

## The ISO itself must be served as a second initrd, not just as a download

Even with the first two problems corrected, the installer will fail in a third way: the Proxmox init process inside the initramfs looks for `/proxmox.iso` at boot and mounts it to load the rest of the installer environment. If that file is absent, the installer never starts and the HTTP answer-file fetch never happens — which is why users reported the `--fetch-from http` fetch mode appearing "unavailable" when they only served the kernel and initrd without the ISO ([Proxmox Forum](https://forum.proxmox.com/posts/846256/)). The correct mechanism, documented in the `--pxe` patch, is to load the prepared ISO as a **second iPXE initrd** with an explicit target name: `initrd {iso_url} proxmox.iso`. iPXE passes this to the kernel alongside the initramfs, and the init process finds the ISO at the expected path ([pve-devel mailing list patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)). Serving a ~1 GB ISO over HTTP (not TFTP) is important here: TFTP has a ~32–45 MB silent truncation limit without block-size extensions, and iPXE's HTTP stack handles large files far more reliably ([syslinux mailing list 2017](https://www.syslinux.org/archives/2017-October/025912.html)).

## The correct pipeline and iPXE script

The `--pxe-loader` flag is no longer available in current releases of `proxmox-auto-install-assistant`, so the pipeline must handle file extraction and recompression manually. The complete corrected approach is:

**Step 1: prepare the ISO for HTTP-fetch mode** (this step is unchanged and still works):
```
proxmox-auto-install-assistant prepare-iso proxmox-ve_9.2.iso \
  --fetch-from http \
  --url https://<answer-server>/answer \
  --output /tmp/proxmox-prepared/
```
This bakes the answer-file URL into the ISO. Note that `proxmox-auto-install-mode`, `proxmox-auto-install-url`, and `proxmox-auto-install-iso-url` are **not** valid kernel parameters — the answer URL is embedded in the ISO at prepare time and cannot be overridden on the kernel line ([Proxmox VE Wiki: Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation)).

**Step 2: extract the kernel and recompress the initrd.** Extract `linux26` (the kernel) and `initrd.img` from the prepared ISO, then recompress `initrd.img` from zstd to gzip — iPXE has no zstd support, so this step is mandatory ([pve-devel mailing list patch](https://lore.proxmox.com/all/0e6560b3-c65c-4296-9c20-102a5b94b46d@proxmox.com/t)):
```bash
# extract from the prepared ISO
xorriso -osirrox on -indev proxmox-ve_9.2-auto-from-http.iso \
  -extract boot/linux26 linux26 \
  -extract boot/initrd.img initrd.img.zst

# recompress: zstd -5 is ~1 minute; default -19 takes ~15 minutes
zstd -d initrd.img.zst -c | gzip -5 > initrd.img
```

**Step 3: serve three files over HTTP** — `linux26` (or rename to `vmlinuz`), `initrd.img` (gzip), and the prepared ISO renamed to `proxmox.iso`. HTTP is required for the ISO; TFTP silently truncates files beyond ~32–45 MB ([syslinux mailing list 2017](https://www.syslinux.org/archives/2017-October/025912.html)).

**Step 4: correct iPXE script.** The confirmed working pattern for PVE 9.x is:
```
#!ipxe
dhcp
initrd http://<server>/proxmox/9.2/initrd.img
initrd http://<server>/proxmox/9.2/proxmox.iso proxmox.iso
kernel http://<server>/proxmox/9.2/linux26 initrd=initrd.img ramdisk_size=16777216 rw quiet splash=silent proxmox-start-auto-installer
boot
```
The second `initrd` line loads the prepared ISO and registers it under the name `proxmox.iso` so the init process finds it at `/proxmox.iso`. The `ramdisk_size=16777216` parameter is a legacy no-op for modern cpio initramfs but is harmless ([Linux Kernel Docs 6.6](https://docs.kernel.org/6.6/admin-guide/blockdev/ramdisk.html)). The correct trigger for unattended install is `proxmox-start-auto-installer`, not the `proxmox-auto-install-mode` parameter in the current script.

## Conclusion

All three failures — missing `initrd=` on the kernel line, zstd-compressed initrd, and absent ISO — must be fixed together; patching only one leaves the other two as boot-stoppers. Since `--pxe-loader` is no longer available, the manual path is the only path: extract `linux26` and `initrd.img` from the prepared ISO, recompress initrd from zstd to gzip, serve the prepared ISO as `proxmox.iso`, and modify the iPXE script to load it as a second `initrd` — while also adding `initrd=initrd.img` and replacing `proxmox-auto-install-mode` with `proxmox-start-auto-installer` on the kernel line.
