# iPXE Kernel and Initrd Loading Mechanics — VFS Kernel Panic Root Causes and Fixes

## What does "unknown-block(0,0)" specifically mean and why does it happen?

### Takeaway
The panic `VFS: Unable to mount root fs on unknown-block(0,0)` means the kernel booted without any usable root device — the initrd was either never loaded, was not found by the kernel, or a wrong/missing `root=` parameter caused it to fall through to an absent block device.

### Cited Findings
- When iPXE loads the kernel but the initrd is not present in memory, the kernel has no root filesystem to mount, resulting in this panic — [iPXE Forum thread tid=7589](https://forum.ipxe.org/showthread.php?tid=7589)
- On UEFI, the kernel cannot find an initrd that iPXE already loaded into memory unless the kernel command line explicitly names it with `initrd=<filename>` — [iPXE Forum thread tid=10770](https://forum.ipxe.org/showthread.php?tid=10770)
- The kernel requires a `root=` argument that matches what the initrd's init scripts expect; an absent or wrong `root=` leads to this error — [iPXE Forum thread tid=7589](https://forum.ipxe.org/showthread.php?tid=7589)
- On pre-3.16 kernels there is a known bug that produces this panic regardless of initrd setup — [iPXE Forum thread tid=7589](https://forum.ipxe.org/showthread.php?tid=7589)

### Inferences
- In the current project's `custom.ipxe`, the `kernel` line does NOT include `initrd=initrd.img`. On UEFI clients this would cause the Linux EFI stub to never locate the initrd iPXE loaded, resulting in the VFS panic. On legacy BIOS the `initrd` command alone may suffice, but adding `initrd=initrd.img` is universally safe.

### Gaps
- The exact kernel behavior when `root=` is absent versus when initrd is absent has not been tested in this specific Proxmox VE 9.2 context.

---

## What is the correct order of `kernel` and `initrd` commands in iPXE?

### Takeaway
iPXE forum examples show both orderings in the wild (`initrd` before `kernel`, and `kernel` before `initrd`), but the canonical working pattern used in confirmed Proxmox PXE setups is `initrd` first, then `kernel`, then `boot`.

### Cited Findings
- A confirmed working Proxmox VE 9.1 iPXE script uses `initrd` on the first line, then `kernel` (with `initrd=initrd.img` on the kernel line), then `boot` — [Proxmox Forum automated-installation-pxe-boot thread](https://forum.proxmox.com/threads/automated-installation-pxe-boot.169009/)
- Multiple iPXE forum examples show `kernel` before `initrd` and report success on both UEFI and BIOS — [iPXE Forum thread tid=8058](https://forum.ipxe.org/showthread.php?tid=8058)
- No iPXE documentation found that mandates a specific order between `kernel` and `initrd` commands; both orderings appear functional
- The `boot` command must come last — [iPXE Forum thread tid=8058](https://forum.ipxe.org/showthread.php?tid=8058)

### Inferences
- The current `custom.ipxe` loads `kernel` before `initrd`, then calls `boot`. This order itself is not the root cause of the panic; the missing `initrd=` parameter on the kernel line is more likely to be the issue.

### Gaps
- No authoritative iPXE documentation was found specifying order requirements; findings are from forum examples only.

---

## Does having `initrd=filename` as a kernel command-line parameter cause problems?

### Takeaway
No — `initrd=<filename>` on the kernel line is required on UEFI and harmless on BIOS, and it is the recommended fix for VFS panics when booting via iPXE.

### Cited Findings
- On UEFI, the Linux EFI stub reads `initrd=<filename>` from the kernel command line to locate the initrd in iPXE's virtual filesystem; without it the initrd is never used — [iPXE Forum thread tid=10770](https://forum.ipxe.org/showthread.php?tid=10770)
- On legacy BIOS, `initrd=<filename>` is a no-op and does not cause any harm — [iPXE Forum thread tid=8058](https://forum.ipxe.org/showthread.php?tid=8058)
- The recommended practice is to always include `initrd=<filename>` so a single iPXE script works on both BIOS and UEFI: `kernel vmlinuz initrd=myinitrd.gz` + `initrd myinitrd.gz` — [iPXE Forum thread tid=8058](https://forum.ipxe.org/showthread.php?tid=8058)
- The filename in `initrd=` must be a plain basename (not a URL) that matches what iPXE registered the image under — [iPXE Forum thread pid=11158](https://forum.ipxe.org/showthread.php?pid=11158); [iPXE developer list 2020-August](https://lists.ipxe.org/pipermail/ipxe-devel/2020-August/007254.html)
- iPXE derives the image name from the last component of the URL path; the OpenStack Ironic project documented this as a source of filename mismatches — [Ironic release note](https://gitea14.opendev.org:3081/openstack/ironic/src/branch/master/releasenotes/notes/initrd_filename-ac68e96f1c9fb576.yaml)
- One confirmed fix: a user who was getting a kernel panic added `initrd=initrd.img` to the kernel line and the panic went away — [Proxmox Forum automated-installation-pxe-boot thread](https://forum.proxmox.com/threads/automated-installation-pxe-boot.169009/)
- One developer comment that including `initrd=` when iPXE already loaded it is "unnecessary" on BIOS, but this does not apply to UEFI — [iPXE Forum thread tid=7551](https://forum.ipxe.org/showthread.php?tid=7551)

### Inferences
- The current `custom.ipxe` is missing `initrd=initrd.img` on the kernel line. For UEFI clients this is the direct cause of the VFS panic. Fix: add `initrd=initrd.img` to the `kernel` line parameters.
- Since the URL is `${pve_url}/initrd.img`, iPXE will register the image under the basename `initrd.img`, so `initrd=initrd.img` is the correct parameter value.

### Gaps
- No gap; this is well-documented across multiple independent sources.

---

## Does `ramdisk_size=` affect initramfs (modern) vs legacy initrd loading?

### Takeaway
`ramdisk_size=` controls the RAM disk block device driver's disk size, which is relevant only for legacy filesystem-image initrd (mounted via `/dev/ram0`). Modern initramfs (cpio archive) does not use the RAM disk block device and is unaffected by this parameter.

### Cited Findings
- Kernel documentation (6.4–6.6) lists `ramdisk_size=N` as setting the size of the RAM disk driver's disks in KB; default is 4096 (4 MB) — [Linux Kernel Docs 6.6 ramdisk](https://docs.kernel.org/6.6/admin-guide/blockdev/ramdisk.html)
- Modern kernels use `/dev/ram0` for initrd (the legacy filesystem-image variant), not for initramfs (cpio archive) — [Linux Kernel Docs 6.6 ramdisk](https://docs.kernel.org/6.6/admin-guide/blockdev/ramdisk.html)
- A 2011 kernel developer informally noted that filesystem-image ramdisks are "pretty obsolete and probably doesn't get much testing" — [syslinux mailing list 2011](https://www.syslinux.org/archives/2011-April/016682.html) (informal opinion)
- Modern initramfs is a cpio archive unpacked directly into tmpfs by the kernel; it does not go through the RAM disk block device at all, so `ramdisk_size=` has no effect on it — this is established Linux kernel design, consistent across sources

### Inferences
- Proxmox VE's `initrd.img` is a cpio-based initramfs (standard for all modern Debian-based distributions). The `ramdisk_size=16777216` parameter in `custom.ipxe` is therefore a no-op for the actual initrd loading.
- Including `ramdisk_size=16777216` is harmless but provides no benefit for Proxmox 9.2. It was likely copied from older pxelinux-era configurations where it was relevant.

### Gaps
- No authoritative confirmation that Proxmox 9.2's `initrd.img` is cpio-based (vs. legacy filesystem image), though this is virtually certain given Proxmox's Debian base and post-2010 kernel.

---

## What is the correct way to specify initrd in iPXE for modern Linux kernels using initramfs?

### Takeaway
Use both the iPXE `initrd <url>` command AND `initrd=<basename>` on the kernel command line. The URL fetches the file; the kernel parameter tells the EFI stub where to find it in iPXE's virtual filesystem.

### Cited Findings
- Confirmed working pattern for Proxmox VE 9.1 with iPXE:
  ```
  #!ipxe
  dhcp
  initrd http://server/proxmox/initrd.img
  kernel http://server/proxmox/vmlinuz initrd=initrd.img ramdisk_size=16777216 rw quiet splash=silent proxmox-start-auto-installer
  boot
  ```
  — [Proxmox Forum automated-installation-pxe-boot thread](https://forum.proxmox.com/threads/automated-installation-pxe-boot.169009/)
- iPXE makes the downloaded image available in its virtual filesystem under the name shown by `imgstat`; the kernel's EFI stub then locates it by that name via the `initrd=` kernel argument — [iPXE developer list 2020-August](https://lists.ipxe.org/pipermail/ipxe-devel/2020-August/007254.html)
- The basename in `initrd=` must match the last path component of the URL used in the `initrd` command (e.g., if URL ends in `/initrd.img`, use `initrd=initrd.img`) — [Ironic release note](https://gitea14.opendev.org:3081/openstack/ironic/src/branch/master/releasenotes/notes/initrd_filename-ac68e96f1c9fb576.yaml)
- On BIOS, iPXE automatically builds a CPIO archive from downloaded initrds; on UEFI the virtual filesystem approach is used instead — [iPXE developer list 2020-August](https://lists.ipxe.org/pipermail/ipxe-devel/2020-August/007254.html)

### Inferences
- The current `custom.ipxe` needs `initrd=initrd.img` added to the kernel line to work correctly on UEFI. The rest of the script structure (`kernel` then `initrd` then `boot`) is functionally fine.
- Corrected kernel line should be:
  ```
  kernel ${pve_url}/linux26 initrd=initrd.img vga=791 video=vesafb:ywrap,mtrr ramdisk_size=16777216 splash=verbose proxmox-auto-install-mode=answer-file proxmox-auto-install-url=${answer_url} proxmox-auto-install-iso-url=${pve_url}/proxmox.iso
  ```

### Gaps
- Proxmox 9.2 uses `linux26` as the kernel filename (vs `vmlinuz` in 9.1 examples). No source confirms whether this renaming affects iPXE behavior — likely no impact since iPXE loads it by URL regardless of filename.

---

## Are there known issues with large initrd files over TFTP or HTTP in iPXE?

### Takeaway
Large initrd files over TFTP have well-known failure modes (block rollover at ~32MB, memory exhaustion). HTTP largely avoids these problems. iPXE needs approximately 2x the initrd size in RAM because it concatenates downloads into a contiguous block before passing to the kernel.

### Cited Findings
- TFTP block number rollover causes silent truncation around 32–45 MB without the blksize extension; the standard fix is to load the kernel and initrd over HTTP instead of TFTP — [syslinux mailing list 2017](https://www.syslinux.org/archives/2017-October/025912.html)
- iPXE concatenates all downloaded initrds into a single contiguous image before passing to the kernel; it needs RAM for both the originals and the combined copy, meaning ~2x the initrd size is required — [iPXE developer list 2012-March](https://lists.ipxe.org/pipermail/ipxe-devel/2012-March/001342.html)
- 32-bit iPXE builds (pcbios) have no PAE/long-mode support and cannot address all system RAM, making large initrd failures more likely on 32-bit builds — [iPXE developer list 2012-March](https://lists.ipxe.org/pipermail/ipxe-devel/2012-March/001342.html)
- Error code `0x2a818006` (seen in Proxmox 9.2 PXE failure reports) is related to memory exhaustion when loading large images in iPXE — [Proxmox Forum PXE boot error thread](https://forum.proxmox.com/goto/post?id=858114); [iPXE developer list 2012-March](https://lists.ipxe.org/pipermail/ipxe-devel/2012-March/001342.html)
- One Proxmox user reported a 1.6 GB initrd failing over PXE, attributed to PXE size limitations; migrating to iPXE with HTTP was the resolution — [Proxmox Forum automated-installation-pxe-boot thread](https://forum.proxmox.com/threads/automated-installation-pxe-boot.169009/)
- Using a current/recent build of iPXE fixes many HTTP transfer failures for large files that affected older builds — [iPXE Forum thread tid=6030](https://forum.ipxe.org/printthread.php?tid=6030)

### Inferences
- The current project already uses HTTP (`${live_endpoint_local}/proxmox/9.2/...`), which is the correct approach. TFTP should be avoided for anything beyond the initial iPXE bootstrap.
- If the Proxmox `initrd.img` is very large (hundreds of MB or over 1 GB for auto-install variants), ensure the target hosts have sufficient RAM (the machine needs 2x initrd size + kernel + headroom) and use a 64-bit iPXE build.
- Error `0x2a818006` during iPXE itself (before the kernel even starts) indicates a memory/loading failure distinct from the VFS kernel panic; both are possible failure modes and have different root causes.

### Gaps
- The exact size of Proxmox VE 9.2's `initrd.img` (as used for auto-install) was not confirmed in sources. The 1.6 GB figure from one user likely refers to an ISO-embedding variant, not the standard installer initrd.
- No source confirms whether iPXE 2.0.x (current as of 2025–2026) has resolved the memory-handling issues documented in the 2012 developer thread.
