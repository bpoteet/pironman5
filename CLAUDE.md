# pironman5 — Arch Linux / Manjaro Support PR

## What This PR Does

The pironman5 installer (`install.py`, helper scripts) unconditionally uses `apt-get`,
which does not exist on Arch-based systems (Arch Linux ARM, Manjaro ARM, EndeavourOS ARM).
This PR adds distro detection and pacman-based installation paths so pironman5 can be
installed on Arch/Manjaro alongside the existing Debian/Ubuntu support.

**Target hardware:** Raspberry Pi 5  
**Test environment:** Vanilla Arch Linux ARM (aarch64) on Pi 5 with NVMe storage  
**Branch:** `arch-linux-support`

---

## The Approach

### 1. Distro Detection
Add a helper to `tools/sf_installer.py` that identifies the package manager at runtime:

```python
import shutil

def get_pkg_manager():
    if shutil.which("apt-get"):
        return "apt"
    elif shutil.which("pacman"):
        return "pacman"
    else:
        raise RuntimeError("No supported package manager found (apt-get or pacman)")
```

All package installation calls should branch on this result.

### 2. Package Name Mapping
Where apt packages are installed, provide pacman equivalents:

| apt package | pacman package |
|---|---|
| python3-pip | python-pip |
| python3-venv | python-virtualenv |
| git | git |
| curl | curl |
| influxdb | influxdb |
| kmod | kmod |
| libopenjp2-7 | openjpeg2 |
| libjpeg-dev | libjpeg-turbo |
| python3-gpiozero | (AUR: python-gpiozero)  ^`^t skipped on Arch; pip installs gpiozero into the venv |
| libfreetype6-dev | freetype2 |
| lsof | lsof |
| i2c-tools | i2c-tools |
| swig | swig |
| python3-dev | python (included) |
| python3-setuptools | python-setuptools |
| liblgpio-dev | (AUR: liblgpio) |
| python3-lgpio | (AUR: python-lgpio) |

### 3. Files to Change

| File | What changes |
|---|---|
| `tools/sf_installer.py` | Add distro detection, branch all apt-get calls |
| `scripts/install_lgpio.sh` | Add pacman path alongside apt path |
| `scripts/setup_influxdb.sh` | Skip Debian repo setup on Arch; use pacman instead |
| `pironman5/__init__.py` | Fix influxdb purge to use pacman on Arch |
| `README.md` | Add Arch/Manjaro prerequisites section |

### 4. InfluxDB Special Case
The `setup_influxdb.sh` script adds a Debian APT repo and GPG key — this entire
block must be skipped on Arch. InfluxDB is available in the Arch community repo via
`pacman -S influxdb`.

### 5. lgpio / rpi.lgpio Special Case
`rpi.lgpio` requires building the `lgpio` C library from source. On Arch this fails
because `liblgpio.so` is not in standard paths. The fix is to:
- Install `swig` via pacman (required to build the Python extension)
- Catch the `rpi.lgpio` pip failure gracefully and emit a clear message
- Direct Arch users to install `python-lgpio` from AUR as an alternative

---

## Files Already Identified (do not change unrelated code)

```
pironman5/
├── install.py                  # Main entry point — calls sf_installer.py
├── tools/
│   └── sf_installer.py         # Core installer class — PRIMARY TARGET
├── scripts/
│   ├── install_lgpio.sh        # lgpio helper — needs pacman branch
│   └── setup_influxdb.sh       # InfluxDB setup — needs Arch skip
├── pironman5/
│   └── __init__.py             # Uninstall logic — influxdb purge fix
└── README.md                   # Docs — add Arch prerequisites
```

---

## PR Guidelines

- Keep changes scoped — do not refactor unrelated code
- Match existing code style in sf_installer.py
- Test each change on Arch Linux ARM aarch64 on Pi 5
- Update README with Arch prerequisites

---

## Test Environment Setup

### Prerequisites: Arch Linux ARM on Raspberry Pi 5

The official Arch Linux ARM aarch64 image requires extra steps to boot on Pi 5
because it ships with U-Boot, which does not support Pi 5. The kernel must be
swapped for the Pi Foundation's `linux-rpi` kernel. Two variants are documented
below depending on storage type.

---

### Variant A: NVMe Drive

**Required:** Raspberry Pi 5, NVMe SSD via M.2 HAT (e.g. Pironman5 case), Linux machine for flashing

#### Step 1 — Partition the drive
Identify your NVMe drive with `lsblk`. It will appear as `/dev/sdX` when connected
via USB adapter. Replace `sdX` throughout with your actual device.

```bash
sudo fdisk /dev/sdX
```

At the fdisk prompt:
- `o` — clear all partitions
- `n` → `p` → `1` → Enter → `+512M` — create boot partition
- `t` → `c` — set FAT32
- `n` → `p` → `2` → Enter → Enter — create root partition
- `w` — write and exit

#### Step 2 — Format and extract
```bash
sudo mkfs.vfat /dev/sdX1
sudo mkfs.ext4 /dev/sdX2

mkdir boot root
sudo mount /dev/sdX1 boot
sudo mount /dev/sdX2 root

wget http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-aarch64-latest.tar.gz

sudo su
bsdtar -xpf ArchLinuxARM-rpi-aarch64-latest.tar.gz -C root
sync
mv root/boot/* boot
exit
```

#### Step 3 — Fix fstab for NVMe
```bash
sudo sed -i 's/mmcblk1p1/nvme0n1p1/g' root/etc/fstab
sudo bash -c 'echo "/dev/nvme0n1p2  /  ext4  defaults  0  1" >> root/etc/fstab'
```

#### Step 4 — Chroot and swap kernel
The image ships with `linux-aarch64` + U-Boot which does not support Pi 5.
Swap it for the Pi Foundation kernel:

```bash
sudo mount /dev/sdX1 root/boot   # must mount boot INSIDE root before chroot
sudo arch-chroot root /bin/bash
```

Inside the chroot:
```bash
# Fix pacman sandbox issue on non-Arch host kernels
sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf

pacman-key --init
pacman-key --populate archlinuxarm

# Swap kernel
pacman -R linux-aarch64 uboot-raspberrypi
pacman -Syu --overwrite "/boot/*" linux-rpi

# Fix missing vconsole.conf error
echo "KEYMAP=us" > /etc/vconsole.conf
mkinitcpio -p linux-rpi

exit
```

#### Step 5 — Fix boot configuration
```bash
# Fix cmdline.txt to point to NVMe root
sudo sed -i 's/mmcblk0p2/nvme0n1p2/g' root/boot/cmdline.txt

# Verify
cat root/boot/cmdline.txt
# Expected: root=/dev/nvme0n1p2 rw rootwait console=serial0,115200 console=tty1 fsck.repair=yes

# Fix config.txt for Pi 5 NVMe
cat > root/boot/config.txt << 'EOF'
enable_uart=1

[pi5]
dtparam=nvme
dtparam=pciex1_gen=3
EOF
```

#### Step 6 — Unmount and boot
```bash
sudo umount root/boot root
```

Insert the NVMe drive into the Pi 5 via M.2 HAT and power on.

#### First boot setup
Login as `root` / password `root`, then:
```bash
pacman-key --init
pacman-key --populate archlinuxarm
pacman -Syu
```

Create a user:
```bash
useradd -m -G wheel -s /bin/bash yourusername
passwd yourusername
pacman -S sudo
EDITOR=nano visudo  # uncomment %wheel ALL=(ALL:ALL) ALL
```

Enable SSH:
```bash
pacman -S openssh
systemctl enable sshd
reboot
```

---

### Variant B: SD Card

Same as NVMe but with these differences:

**Step 3 — fstab:** No changes needed. The default `mmcblk1p1` is correct for SD on Pi 5.
Add only the missing root entry:
```bash
sudo bash -c 'echo "/dev/mmcblk1p2  /  ext4  defaults  0  1" >> root/etc/fstab'
```

**Step 5 — cmdline.txt:** Use `mmcblk0p2` (Pi 5 sees SD as mmcblk0):
```bash
# cmdline.txt should already say mmcblk0p2 after kernel swap — verify:
cat root/boot/cmdline.txt
# If it says mmcblk1p2, fix it:
sudo sed -i 's/mmcblk1p2/mmcblk0p2/g' root/boot/cmdline.txt
```

**config.txt:** SD card does not need the NVMe dtparams:
```bash
cat > root/boot/config.txt << 'EOF'
enable_uart=1
EOF
```

**Note:** If using an SD card extender cable (e.g. inside a Pi case), you may
encounter I/O errors on boot. This is a known hardware reliability issue with
extender cables. Use a direct SD slot connection for testing where possible,
or use NVMe instead.

---

## Known Issues / Notes

- The `DisableSandbox` pacman.conf fix is only needed when running pacman inside
  a chroot on a non-Arch host. It is not needed on the Pi itself.
- `rpi.lgpio` pip install requires `swig` to be installed first on Arch.
- InfluxDB on Arch: skip the APT repo/key setup entirely, use `pacman -S influxdb`.
- The Pironman5 SD card extender introduces enough latency to cause intermittent
  boot failures on Arch. NVMe is the recommended storage for this case.
- `/usr/local/lib` is not in Arch's default linker search path — install_lgpio.sh 
  creates /etc/ld.so.conf.d/lgpio.conf to register it after source compilation.
