#!/bin/bash
#
# Fix ASUS Nvidia ACPI Crashes - Complete Solution (v6)
#
# Problem: ASUS firmware confuses PCIe device D-states with system S-states,
#          causing ACPI crashes [0x00200800] when Nvidia GPU changes power state.
#          The AMD PSP interprets D3 transitions as S0 idle → system crash.
#
# Root cause layers discovered:
#   1. supergfxctl enables Nvidia Runtime PM → D3 transition → crash
#   2. tuned.service (Fedora) overrides udev rules, sets devices back to "auto"
#   3. nouveau driver has its own internal runpm parameter that triggers D3
#      independently of Linux sysfs power/control
#   4. Boot timing: ~12s window where devices are unprotected before services start
#   5. nouveau driver itself continues to trigger ACPI transitions despite runpm=0
#      → full blacklist required to remove driver from the crash path entirely
#   6. amdgpu (iGPU) also triggers ACPI transitions via its own runtime PM
#      independently of the Nvidia chain → must also be pinned to D0
#   7. amd_pmc (AMD S0ix/Modern Standby controller) manages CPU package
#      C-state (CC6/PC6) transitions; ASUS firmware misidentifies these as
#      S-state transitions → silent hard reset [0x00200800], no kernel log
#   8. Even with amd_pmc blacklisted, kernel reports "Low-power S0 idle used
#      by default" - cpuidle still enters C2+ states via acpi_idle driver
#      → processor.max_cstate=1 caps CPU at C1, eliminates remaining trigger
#
# Solution: 11 layers of defense (all needed on Fedora + ASUS ROG):
#   Layer 1:  pcie_port_pm=off         (kernel param, disables PCIe port PM at ~0.5s)
#   Layer 2:  pcie_aspm=off            (kernel param, disables global PCIe ASPM)
#   Layer 3:  nouveau.runpm=0          (kernel param, disables nouveau internal PM)
#   Layer 4:  amdgpu.runpm=0           (kernel param, disables amdgpu runtime PM)
#   Layer 5:  udev rule                (forces D0 at device detection, ~2s)
#   Layer 6:  systemd early service    (forces D0 at sysinit.target, ~5s)
#   Layer 7:  mask tuned.service       (prevents PM daemon from overriding)
#   Layer 8:  remove supergfxctl       (removes the original trigger)
#   Layer 9:  blacklist nouveau + disable sleep/suspend
#             (removes driver from crash path; blocks lid/idle/systemd sleep)
#   Layer 10: blacklist amd_pmc
#             (removes AMD S0ix controller from crash path; silent hard
#              reset [0x00200800] with no kernel log - discovered Apr 2026)
#   Layer 11: processor.max_cstate=1
#             (caps CPU idle at C1; prevents acpi_idle from entering C2+
#              even without amd_pmc; CPU stays POLL/C1 only - Apr 2026)
#
# Tested on: ASUS ROG Strix G15 / G713QM, Fedora 43, kernel 6.19.x
# Impact: +5-10W power consumption; Nvidia dGPU inaccessible via nouveau (compute
#         and display via dGPU unavailable until blacklist is reverted)
#

set -e

TOTAL_STEPS=12

echo "=============================================="
echo "  ASUS Nvidia ACPI Crash Fix (v6)"
echo "=============================================="
echo ""

# ============================================================================
# 1. DIAGNOSTIC
# ============================================================================
echo "[1/$TOTAL_STEPS] Running diagnostic..."
echo ""

NEEDS_FIX=0

# Check if supergfxctl is installed
if command -v supergfxctl &> /dev/null; then
    echo "  ⚠️  supergfxctl: INSTALLED"
    SUPERGFX_INSTALLED=1
    NEEDS_FIX=1

    if systemctl is-active --quiet supergfxd 2>/dev/null; then
        echo "      Status: ACTIVE (running)"
        SUPERGFX_ACTIVE=1
    else
        echo "      Status: inactive"
        SUPERGFX_ACTIVE=0
    fi
else
    echo "  ✓ supergfxctl: not installed"
    SUPERGFX_INSTALLED=0
    SUPERGFX_ACTIVE=0
fi

# Check Nvidia GPU power state
if [ -e /sys/bus/pci/devices/0000:01:00.0/power/control ]; then
    NVIDIA_STATE=$(cat /sys/bus/pci/devices/0000:01:00.0/power/control)
    echo "  📌 Nvidia GPU: Found ($(lspci -s 01:00.0 | cut -d: -f3-))"
    echo "      Power control: $NVIDIA_STATE"

    if [ "$NVIDIA_STATE" = "auto" ]; then
        echo "      ⚠️  WARNING: 'auto' mode causes ACPI crashes!"
        NEEDS_FIX=1
    fi
else
    echo "  ❌ Nvidia GPU: Not found at 0000:01:00.0"
    echo ""
    echo "Error: Cannot find Nvidia GPU. Check with: lspci | grep -i nvidia"
    exit 1
fi

# Check Nvidia Audio power state
if [ -e /sys/bus/pci/devices/0000:01:00.1/power/control ]; then
    NVIDIA_AUDIO_STATE=$(cat /sys/bus/pci/devices/0000:01:00.1/power/control)
    echo "  📌 Nvidia Audio: Found ($(lspci -s 01:00.1 | cut -d: -f3-))"
    echo "      Power control: $NVIDIA_AUDIO_STATE"

    if [ "$NVIDIA_AUDIO_STATE" = "auto" ]; then
        echo "      ⚠️  WARNING: 'auto' mode causes ACPI crashes!"
        NEEDS_FIX=1
    fi
fi

# Check PCIe Root Port power state
if [ -e /sys/bus/pci/devices/0000:00:01.1/power/control ]; then
    ROOT_PORT_STATE=$(cat /sys/bus/pci/devices/0000:00:01.1/power/control)
    echo "  📌 PCIe Root Port: Found (parent of Nvidia)"
    echo "      Power control: $ROOT_PORT_STATE"

    if [ "$ROOT_PORT_STATE" = "auto" ]; then
        echo "      ⚠️  WARNING: 'auto' mode can trigger crashes!"
        NEEDS_FIX=1
    fi
fi

# Check AMD GPU power state
if [ -e /sys/bus/pci/devices/0000:05:00.0/power/control ]; then
    AMDGPU_STATE=$(cat /sys/bus/pci/devices/0000:05:00.0/power/control)
    echo "  📌 AMD GPU (iGPU): Found ($(lspci -s 05:00.0 2>/dev/null | cut -d: -f3- || echo '?'))"
    echo "      Power control: $AMDGPU_STATE"

    if [ "$AMDGPU_STATE" = "auto" ]; then
        echo "      ⚠️  WARNING: 'auto' mode can trigger ACPI crashes!"
        NEEDS_FIX=1
    fi
fi

# Check kernel parameters
CMDLINE=$(cat /proc/cmdline)
if echo "$CMDLINE" | grep -q "pcie_port_pm=off"; then
    echo "  ✓ Kernel param: pcie_port_pm=off"
else
    echo "  ⚠️  Kernel param: pcie_port_pm=off NOT set"
    NEEDS_FIX=1
fi

if echo "$CMDLINE" | grep -q "pcie_aspm=off"; then
    echo "  ✓ Kernel param: pcie_aspm=off"
else
    echo "  ⚠️  Kernel param: pcie_aspm=off NOT set"
    NEEDS_FIX=1
fi

if echo "$CMDLINE" | grep -q "amdgpu.runpm=0"; then
    echo "  ✓ Kernel param: amdgpu.runpm=0"
else
    echo "  ⚠️  Kernel param: amdgpu.runpm=0 NOT set"
    NEEDS_FIX=1
fi

if echo "$CMDLINE" | grep -q "nouveau.runpm=0"; then
    echo "  ✓ Kernel param: nouveau.runpm=0"
else
    echo "  ⚠️  Kernel param: nouveau.runpm=0 NOT set"
    NEEDS_FIX=1
fi

# Check nouveau blacklist
NOUVEAU_BLACKLISTED=0
if echo "$CMDLINE" | grep -q "rd.driver.blacklist=nouveau" && \
   echo "$CMDLINE" | grep -q "modprobe.blacklist=nouveau" && \
   echo "$CMDLINE" | grep -q "nouveau.modeset=0"; then
    echo "  ✓ Kernel param: nouveau blacklist (rd.driver.blacklist + modprobe.blacklist + modeset=0)"
    NOUVEAU_BLACKLISTED=1
else
    echo "  ⚠️  Kernel param: nouveau blacklist NOT fully set"
    NEEDS_FIX=1
fi

# Check amd_pmc blacklist
if echo "$CMDLINE" | grep -q "rd.driver.blacklist=amd_pmc" && \
   echo "$CMDLINE" | grep -q "modprobe.blacklist=amd_pmc" && \
   [ -f /etc/modprobe.d/blacklist-amd-pmc.conf ]; then
    echo "  ✓ amd_pmc: blacklisted (GRUB params + modprobe.d)"
else
    echo "  ⚠️  amd_pmc: NOT fully blacklisted"
    NEEDS_FIX=1
fi

# Check amd_pmc module (should not be loaded if blacklisted)
if lsmod | grep -q '^amd_pmc'; then
    echo "  ⚠️  amd_pmc module: LOADED (will be blocked after reboot)"
    NEEDS_FIX=1
else
    echo "  ✓ amd_pmc module: not loaded"
fi

# Check processor.max_cstate=1
if echo "$CMDLINE" | grep -q "processor.max_cstate=1"; then
    echo "  ✓ Kernel param: processor.max_cstate=1"
    # Verify only POLL and C1 are available
    CSTATES=$(cat /sys/devices/system/cpu/cpu0/cpuidle/state*/name 2>/dev/null | tr '\n' ' ' || echo '?')
    echo "      Active C-states: $CSTATES"
else
    echo "  ⚠️  Kernel param: processor.max_cstate=1 NOT set"
    NEEDS_FIX=1
fi

# Check nouveau module runpm
if [ -e /sys/module/nouveau/parameters/runpm ]; then
    NOUVEAU_RUNPM=$(cat /sys/module/nouveau/parameters/runpm 2>/dev/null || echo "?")
    echo "  📌 nouveau.runpm (live): $NOUVEAU_RUNPM"
    if [ "$NOUVEAU_RUNPM" != "0" ]; then
        NEEDS_FIX=1
    fi
fi

# Check tuned status
TUNED_STATUS=$(systemctl is-enabled tuned.service 2>/dev/null || echo "not-found")
if [ "$TUNED_STATUS" = "masked" ]; then
    echo "  ✓ tuned.service: masked"
else
    echo "  ⚠️  tuned.service: $TUNED_STATUS (should be masked)"
    NEEDS_FIX=1
fi

# Check for udev rule
if [ -f /etc/udev/rules.d/80-nvidia-d0.rules ]; then
    echo "  ✓ Udev rule: present"
    UDEV_EXISTS=1
else
    echo "  ⚠️  Udev rule: not found"
    UDEV_EXISTS=0
    NEEDS_FIX=1
fi

# Check for early systemd service
if systemctl is-enabled nvidia-force-d0-early.service &>/dev/null; then
    echo "  ✓ Early service: enabled"
    EARLY_SERVICE_EXISTS=1
else
    echo "  ⚠️  Early service: not found"
    EARLY_SERVICE_EXISTS=0
    NEEDS_FIX=1
fi

# Check for recent ACPI crashes
CRASHES=$(sudo journalctl -k --since "7 days ago" 2>/dev/null | grep -c "0x00200800" || echo "0")
echo "  📊 ACPI crashes [0x00200800] (last 7 days): $CRASHES"
if [ "$CRASHES" -gt 0 ]; then
    echo "      ⚠️  System has experienced crashes!"
fi

echo ""

# ============================================================================
# 2. DECISION
# ============================================================================
if [ "$NEEDS_FIX" -eq 0 ]; then
    echo "=============================================="
    echo "✓ System already fully protected - no action needed"
    echo "=============================================="
    echo ""
    echo "All 11 defense layers active:"
    echo "  Layer 1:  pcie_port_pm=off (kernel)"
    echo "  Layer 2:  pcie_aspm=off (kernel)"
    echo "  Layer 3:  nouveau.runpm=0 (kernel)"
    echo "  Layer 4:  amdgpu.runpm=0 (kernel)"
    echo "  Layer 5:  udev rule (device detection)"
    echo "  Layer 6:  early systemd service (sysinit)"
    echo "  Layer 7:  tuned.service masked"
    echo "  Layer 8:  supergfxctl not installed"
    echo "  Layer 9:  nouveau blacklisted + sleep/suspend blocked"
    echo "  Layer 10: amd_pmc blacklisted (no CPU S0ix transitions)"
    echo "  Layer 11: processor.max_cstate=1 (CPU capped at C1)"
    echo ""
    exit 0
fi

echo "=============================================="
echo "  Fix Required"
echo "=============================================="
echo ""
echo "This script will apply 11 layers of defense:"
echo "  1. Add kernel params: pcie_port_pm=off + pcie_aspm=off + nouveau.runpm=0 + amdgpu.runpm=0"
echo "  2. Blacklist nouveau driver (rd.driver.blacklist + modprobe.blacklist + modeset=0)"
echo "  3. Blacklist amd_pmc driver (rd.driver.blacklist + modprobe.blacklist)"
echo "  4. Add processor.max_cstate=1 (cap CPU idle at C1)"
echo "  5. Create udev rule (force D0: Nvidia chain + AMD GPU)"
echo "  6. Create early systemd service (force D0 at sysinit)"
echo "  7. Mask tuned.service (prevent PM override)"
echo "  8. Remove supergfxctl (if installed)"
echo "  9. Force devices to D0 immediately"
echo "  10. Block all sleep/suspend paths (lid/idle/systemd targets)"
echo ""
echo "Trade-off: ~10W higher power usage for stable system"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled by user"
    exit 0
fi

echo ""

# ============================================================================
# 3. REMOVE SUPERGFXCTL (Layer 6)
# ============================================================================
if [ "$SUPERGFX_INSTALLED" -eq 1 ]; then
    echo "[2/$TOTAL_STEPS] Removing supergfxctl..."
    echo ""

    if [ "$SUPERGFX_ACTIVE" -eq 1 ]; then
        echo "  Stopping supergfxd service..."
        sudo systemctl stop supergfxd 2>/dev/null || true
        echo "  ✓ Service stopped"
    fi

    echo "  Disabling supergfxd from autostart..."
    sudo systemctl disable supergfxd 2>/dev/null || true
    echo "  ✓ Service disabled"

    echo "  Uninstalling supergfxctl package..."
    if command -v dnf &> /dev/null; then
        sudo dnf remove -y supergfxctl 2>&1 | grep -v "^$" || true
    elif command -v pacman &> /dev/null; then
        sudo pacman -Rns --noconfirm supergfxctl 2>&1 | grep -v "^$" || true
    else
        echo "  ⚠️  Unknown package manager - manual removal needed"
    fi

    if command -v supergfxctl &> /dev/null; then
        echo "  ⚠️  WARNING: supergfxctl still present (manual check needed)"
    else
        echo "  ✓ supergfxctl removed"
    fi

    echo ""
else
    echo "[2/$TOTAL_STEPS] Removing supergfxctl... (skipped - not installed)"
    echo ""
fi

# ============================================================================
# 4. FORCE DEVICES TO D0 (IMMEDIATE)
# ============================================================================
echo "[3/$TOTAL_STEPS] Forcing Nvidia + Root Port to D0 (immediate)..."
echo ""

for dev_info in "0000:00:01.1:PCIe Root Port" "0000:01:00.0:Nvidia GPU" "0000:01:00.1:Nvidia Audio" "0000:05:00.0:AMD GPU"; do
    dev="${dev_info%%:*}"
    # Remove first field to get label
    label="${dev_info#*:*:*:}"
    dev="${dev_info%:$label}"
    # Simpler approach
    IFS=: read -r d1 d2 d3 label <<< "$dev_info"
    dev="$d1:$d2:$d3"

    if [ -e "/sys/bus/pci/devices/$dev/power/control" ]; then
        OLD=$(cat "/sys/bus/pci/devices/$dev/power/control")
        sudo sh -c "echo on > /sys/bus/pci/devices/$dev/power/control" 2>/dev/null
        NEW=$(cat "/sys/bus/pci/devices/$dev/power/control")
        echo "  ✓ $label ($dev): $OLD → $NEW"
    fi
done

echo ""

# ============================================================================
# 5. KERNEL PARAMETERS (Layers 1 & 2 + ASPM hard-off)
# ============================================================================
echo "[4/$TOTAL_STEPS] Configuring kernel parameters..."
echo ""

GRUB_FILE="/etc/default/grub"
GRUB_CHANGED=0

if [ ! -f "$GRUB_FILE" ]; then
    echo "  ❌ ERROR: $GRUB_FILE not found"
    echo "  Skipping kernel parameter configuration"
else
    # Backup GRUB config
    sudo cp "$GRUB_FILE" "${GRUB_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "  ✓ GRUB config backed up"

    CURRENT_CMDLINE=$(grep '^GRUB_CMDLINE_LINUX=' "$GRUB_FILE" | head -1)

    # Add pcie_port_pm=off if not present
    if ! echo "$CURRENT_CMDLINE" | grep -q "pcie_port_pm=off"; then
        sudo sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 pcie_port_pm=off"/' "$GRUB_FILE"
        echo "  ✓ Added: pcie_port_pm=off"
        GRUB_CHANGED=1
    else
        echo "  ✓ Already set: pcie_port_pm=off"
    fi

    # Add pcie_aspm=off if not present
    if ! echo "$CURRENT_CMDLINE" | grep -q "pcie_aspm=off"; then
        sudo sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 pcie_aspm=off"/' "$GRUB_FILE"
        echo "  ✓ Added: pcie_aspm=off"
        GRUB_CHANGED=1
    else
        echo "  ✓ Already set: pcie_aspm=off"
    fi

    # Add nouveau.runpm=0 if not present
    if ! echo "$CURRENT_CMDLINE" | grep -q "nouveau.runpm=0"; then
        sudo sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 nouveau.runpm=0"/' "$GRUB_FILE"
        echo "  ✓ Added: nouveau.runpm=0"
        GRUB_CHANGED=1
    else
        echo "  ✓ Already set: nouveau.runpm=0"
    fi

    # Add amdgpu.runpm=0 if not present
    CURRENT_CMDLINE=$(grep '^GRUB_CMDLINE_LINUX=' "$GRUB_FILE" | head -1)
    if ! echo "$CURRENT_CMDLINE" | grep -q "amdgpu.runpm=0"; then
        sudo sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 amdgpu.runpm=0"/' "$GRUB_FILE"
        echo "  ✓ Added: amdgpu.runpm=0"
        GRUB_CHANGED=1
    else
        echo "  ✓ Already set: amdgpu.runpm=0"
    fi

    # Add nouveau blacklist params if not present
    CURRENT_CMDLINE=$(grep '^GRUB_CMDLINE_LINUX=' "$GRUB_FILE" | head -1)
    for BPARAM in "rd.driver.blacklist=nouveau" "modprobe.blacklist=nouveau" "nouveau.modeset=0"; do
        if ! echo "$CURRENT_CMDLINE" | grep -q "$BPARAM"; then
            sudo sed -i "s/GRUB_CMDLINE_LINUX=\"\(.*\)\"/GRUB_CMDLINE_LINUX=\"\1 $BPARAM\"/" "$GRUB_FILE"
            CURRENT_CMDLINE=$(grep '^GRUB_CMDLINE_LINUX=' "$GRUB_FILE" | head -1)
            echo "  ✓ Added: $BPARAM"
            GRUB_CHANGED=1
        else
            echo "  ✓ Already set: $BPARAM"
        fi
    done

    # Add amd_pmc blacklist params if not present
    CURRENT_CMDLINE=$(grep '^GRUB_CMDLINE_LINUX=' "$GRUB_FILE" | head -1)
    for BPARAM in "rd.driver.blacklist=amd_pmc" "modprobe.blacklist=amd_pmc"; do
        if ! echo "$CURRENT_CMDLINE" | grep -q "$BPARAM"; then
            sudo sed -i "s/GRUB_CMDLINE_LINUX=\"\(.*\)\"/GRUB_CMDLINE_LINUX=\"\1 $BPARAM\"/" "$GRUB_FILE"
            CURRENT_CMDLINE=$(grep '^GRUB_CMDLINE_LINUX=' "$GRUB_FILE" | head -1)
            echo "  ✓ Added: $BPARAM"
            GRUB_CHANGED=1
        else
            echo "  ✓ Already set: $BPARAM"
        fi
    done

    # Add processor.max_cstate=1 if not present
    CURRENT_CMDLINE=$(grep '^GRUB_CMDLINE_LINUX=' "$GRUB_FILE" | head -1)
    if ! echo "$CURRENT_CMDLINE" | grep -q "processor.max_cstate=1"; then
        sudo sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 processor.max_cstate=1"/' "$GRUB_FILE"
        echo "  ✓ Added: processor.max_cstate=1"
        GRUB_CHANGED=1
    else
        echo "  ✓ Already set: processor.max_cstate=1"
    fi

    # Regenerate GRUB if changed
    if [ "$GRUB_CHANGED" -eq 1 ]; then
        echo "  Regenerating GRUB config..."
        sudo grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1 | tail -3
        echo "  ✓ GRUB config regenerated"
    fi

    echo ""
    echo "  Final GRUB_CMDLINE_LINUX:"
    echo "  $(grep '^GRUB_CMDLINE_LINUX=' "$GRUB_FILE")"
fi

echo ""

# ============================================================================
# 6. UDEV RULE (Layer 3)
# ============================================================================
echo "[5/$TOTAL_STEPS] Creating udev rule..."
echo ""

sudo tee /etc/udev/rules.d/80-nvidia-d0.rules > /dev/null <<'EOF'
# Force Nvidia + AMD GPU + PCIe Root Port to D0 - ASUS firmware bug workaround
#
# Problem: ASUS firmware confuses PCIe device D-states with system S-states
# When ANY GPU device or PCIe Root Port changes power state, firmware incorrectly
# triggers ACPI suspend → crash [0x00200800]
#
# Solution: Keep ALL GPU-related devices + Root Port in D0 permanently
#
# PCIe Root Port (parent of Nvidia)
ACTION=="add", SUBSYSTEM=="pci", KERNEL=="0000:00:01.1", ATTR{power/control}="on"
# Nvidia devices (GPU + Audio) - matches vendor 0x10de
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{power/control}="on"
# AMD GPU (iGPU - amdgpu driver)
ACTION=="add", SUBSYSTEM=="pci", KERNEL=="0000:05:00.0", ATTR{power/control}="on"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=pci

echo "  ✓ Created: /etc/udev/rules.d/80-nvidia-d0.rules"
echo "  ✓ Udev rules reloaded"

echo ""

# ============================================================================
# 7. EARLY SYSTEMD SERVICE (Layer 4)
# ============================================================================
echo "[6/$TOTAL_STEPS] Creating early systemd service (sysinit.target)..."
echo ""

# Disable old service if it exists
if systemctl is-enabled nvidia-force-d0.service &>/dev/null; then
    sudo systemctl disable nvidia-force-d0.service 2>/dev/null || true
    echo "  ✓ Disabled old nvidia-force-d0.service (too late in boot)"
fi

# Create early service (runs at sysinit.target, before any PM daemon)
sudo tee /etc/systemd/system/nvidia-force-d0-early.service > /dev/null <<'SERVICE'
[Unit]
Description=Force Nvidia devices to D0 (EARLY - ASUS firmware bug workaround)
DefaultDependencies=no
After=local-fs.target
Before=sysinit.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for dev in 0000:00:01.1 0000:01:00.0 0000:01:00.1 0000:05:00.0; do [ -e /sys/bus/pci/devices/$dev/power/control ] && echo on > /sys/bus/pci/devices/$dev/power/control; done'
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable nvidia-force-d0-early.service 2>&1 | grep -v "^$" || true
sudo systemctl start nvidia-force-d0-early.service 2>&1 || true

echo "  ✓ Created: nvidia-force-d0-early.service"
echo "  ✓ Starts at sysinit.target (before tuned and other PM daemons)"

echo ""

# ============================================================================
# 7b. BLACKLIST NOUVEAU (Layer 8 - remove from crash path)
# ============================================================================
echo "[6b/$TOTAL_STEPS] Blacklisting nouveau via modprobe.d..."
echo ""

sudo tee /etc/modprobe.d/blacklist-nouveau.conf > /dev/null <<'EOF'
# Blacklist nouveau - ASUS ROG crash workaround
# nouveau triggers ACPI power state transitions even with runpm=0,
# causing system resets [0x00200800] on ASUS ROG + AMD hybrid platforms.
blacklist nouveau
options nouveau modeset=0
EOF

echo "  ✓ Created: /etc/modprobe.d/blacklist-nouveau.conf"
echo "  ℹ️  GRUB params (rd.driver.blacklist + modprobe.blacklist) set in step 4"
echo "  ℹ️  Effective after reboot"
echo ""

# ============================================================================
# 7c. BLACKLIST AMD_PMC (Layer 10 - remove CPU S0ix from crash path)
# ============================================================================
echo "[6c/$TOTAL_STEPS] Blacklisting amd_pmc via modprobe.d..."
echo ""

sudo tee /etc/modprobe.d/blacklist-amd-pmc.conf > /dev/null <<'EOF'
# Blacklist amd_pmc - ASUS ROG crash workaround
# amd_pmc manages AMD S0ix/Modern Standby (CC6/PC6) transitions.
# ASUS ROG firmware confuses CPU package C-state transitions with
# S-state transitions -> silent hard reset [0x00200800] with no kernel log.
blacklist amd_pmc
EOF

echo "  ✓ Created: /etc/modprobe.d/blacklist-amd-pmc.conf"
echo "  ℹ️  GRUB params (rd.driver.blacklist=amd_pmc + modprobe.blacklist=amd_pmc) set in step 4"
echo "  ℹ️  Effective after reboot"
echo ""

# ============================================================================
# 8. MASK TUNED SERVICE (Layer 6)
# ============================================================================
echo "[7/$TOTAL_STEPS] Masking tuned.service..."
echo ""

TUNED_STATUS=$(systemctl is-enabled tuned.service 2>/dev/null || echo "not-found")

if [ "$TUNED_STATUS" = "masked" ]; then
    echo "  ✓ tuned.service: already masked"
elif [ "$TUNED_STATUS" = "not-found" ]; then
    echo "  ✓ tuned.service: not installed (nothing to do)"
else
    sudo systemctl stop tuned.service 2>/dev/null || true
    sudo systemctl disable tuned.service 2>/dev/null || true
    sudo systemctl mask tuned.service 2>/dev/null || true
    echo "  ✓ tuned.service: stopped, disabled, masked"
    echo "  ℹ️  tuned was overriding device power states back to 'auto'"
    echo "     To unmask later: sudo systemctl unmask tuned.service"
fi

echo ""

# ============================================================================
# 9. DISABLE SLEEP/SUSPEND (Layer 7)
# ============================================================================
echo "[8/$TOTAL_STEPS] Disabling sleep/suspend paths..."
echo ""

# Force logind to ignore lid and idle sleep actions
sudo mkdir -p /etc/systemd/logind.conf.d /etc/systemd/sleep.conf.d

sudo tee /etc/systemd/logind.conf.d/10-homelab-no-sleep.conf > /dev/null <<'CONF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
CONF

# Disable all sleep modes at systemd level
sudo tee /etc/systemd/sleep.conf.d/10-homelab-disable-sleep.conf > /dev/null <<'CONF'
[Sleep]
AllowSuspend=no
AllowHibernation=no
AllowSuspendThenHibernate=no
AllowHybridSleep=no
CONF

# Mask sleep targets so no service can trigger them
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null || true
sudo systemctl daemon-reload
sudo systemctl restart systemd-logind

echo "  ✓ logind configured to ignore lid and idle sleep"
echo "  ✓ systemd sleep modes disabled"
echo "  ✓ sleep/suspend/hibernate targets masked"

echo ""

# ============================================================================
# 10. VERIFICATION
# ============================================================================
echo "[9/$TOTAL_STEPS] Verifying all protections..."
echo ""

VERIFY_OK=0
VERIFY_FAIL=0

verify() {
    local label="$1"
    local condition="$2"
    if eval "$condition"; then
        echo "  ✓ $label"
        ((VERIFY_OK++))
    else
        echo "  ⚠️  $label"
        ((VERIFY_FAIL++))
    fi
}

# Check devices
for dev_check in "0000:00:01.1:PCIe Root Port" "0000:01:00.0:Nvidia GPU" "0000:01:00.1:Nvidia Audio" "0000:05:00.0:AMD GPU"; do
    IFS=: read -r d1 d2 d3 label <<< "$dev_check"
    dev="$d1:$d2:$d3"
    if [ -e "/sys/bus/pci/devices/$dev/power/control" ]; then
        state=$(cat "/sys/bus/pci/devices/$dev/power/control")
        verify "$label ($dev): $state" "[[ '$state' == 'on' ]]"
    fi
done

# Check udev rule
verify "Udev rule present" "[ -f /etc/udev/rules.d/80-nvidia-d0.rules ]"

# Check early service
verify "Early service enabled" "systemctl is-enabled nvidia-force-d0-early.service &>/dev/null"

# Check tuned masked
TUNED_FINAL=$(systemctl is-enabled tuned.service 2>/dev/null || echo "not-found")
verify "tuned.service: $TUNED_FINAL" "[[ '$TUNED_FINAL' == 'masked' || '$TUNED_FINAL' == 'not-found' ]]"

# Check GRUB params
if [ -f "$GRUB_FILE" ]; then
    GRUB_LINE=$(grep '^GRUB_CMDLINE_LINUX=' "$GRUB_FILE")
    verify "GRUB: pcie_port_pm=off" "echo '$GRUB_LINE' | grep -q 'pcie_port_pm=off'"
    verify "GRUB: pcie_aspm=off" "echo '$GRUB_LINE' | grep -q 'pcie_aspm=off'"
    verify "GRUB: nouveau.runpm=0" "echo '$GRUB_LINE' | grep -q 'nouveau.runpm=0'"
        verify "GRUB: amdgpu.runpm=0" "echo '$GRUB_LINE' | grep -q 'amdgpu.runpm=0'"
        verify "GRUB: rd.driver.blacklist=nouveau" "echo '$GRUB_LINE' | grep -q 'rd.driver.blacklist=nouveau'"
        verify "GRUB: modprobe.blacklist=nouveau" "echo '$GRUB_LINE' | grep -q 'modprobe.blacklist=nouveau'"
        verify "GRUB: nouveau.modeset=0" "echo '$GRUB_LINE' | grep -q 'nouveau.modeset=0'"
        verify "GRUB: processor.max_cstate=1" "echo '$GRUB_LINE' | grep -q 'processor.max_cstate=1'"
    fi

# Check modprobe blacklist
    verify "modprobe.d blacklist-nouveau.conf" "[ -f /etc/modprobe.d/blacklist-nouveau.conf ]"
    verify "modprobe.d blacklist-amd-pmc.conf" "[ -f /etc/modprobe.d/blacklist-amd-pmc.conf ]"
    verify "Live kernel: rd.driver.blacklist=nouveau" "grep -q 'rd.driver.blacklist=nouveau' /proc/cmdline"
    verify "Live kernel: modprobe.blacklist=nouveau" "grep -q 'modprobe.blacklist=nouveau' /proc/cmdline"
    verify "Live kernel: rd.driver.blacklist=amd_pmc" "grep -q 'rd.driver.blacklist=amd_pmc' /proc/cmdline"
    verify "Live kernel: modprobe.blacklist=amd_pmc" "grep -q 'modprobe.blacklist=amd_pmc' /proc/cmdline"
    verify "Live kernel: amdgpu.runpm=0" "grep -q 'amdgpu.runpm=0' /proc/cmdline"
    verify "Live kernel: processor.max_cstate=1" "grep -q 'processor.max_cstate=1' /proc/cmdline"
    verify "nouveau module not loaded" "! lsmod | grep -q '^nouveau'"
    verify "amd_pmc module not loaded" "! lsmod | grep -q '^amd_pmc'"
    verify "CPU max C-state: C1 only" "! ls /sys/devices/system/cpu/cpu0/cpuidle/ 2>/dev/null | grep -q 'state2'"
# Check sleep targets masked
verify "sleep.target masked" "[[ '$(systemctl is-enabled sleep.target 2>/dev/null || true)' == 'masked' ]]"
verify "suspend.target masked" "[[ '$(systemctl is-enabled suspend.target 2>/dev/null || true)' == 'masked' ]]"
verify "hibernate.target masked" "[[ '$(systemctl is-enabled hibernate.target 2>/dev/null || true)' == 'masked' ]]"
verify "hybrid-sleep.target masked" "[[ '$(systemctl is-enabled hybrid-sleep.target 2>/dev/null || true)' == 'masked' ]]"

echo ""
echo "  Results: $VERIFY_OK passed, $VERIFY_FAIL issues"

echo ""

# ============================================================================
# SUMMARY
# ============================================================================
echo "=============================================="
if [ "$VERIFY_FAIL" -eq 0 ]; then
    echo "✓ All 11 Defense Layers Applied!"
else
    echo "⚠️  Fix Applied ($VERIFY_FAIL issues detected)"
fi
echo "=============================================="
echo ""
echo "Defense layers:"
echo "  Layer 1:  pcie_port_pm=off     → Kernel disables PCIe port PM (~0.5s)"
echo "  Layer 2:  pcie_aspm=off        → Kernel disables global PCIe ASPM"
echo "  Layer 3:  nouveau.runpm=0      → Disables nouveau internal Runtime PM"
echo "  Layer 4:  amdgpu.runpm=0       → Disables amdgpu (iGPU) Runtime PM"
echo "  Layer 5:  Udev rule            → Forces D0 at device detection (~2s)"
echo "  Layer 6:  Early systemd svc    → Forces D0 at sysinit.target (~5s)"
echo "  Layer 7:  tuned masked         → Prevents PM daemon override"
echo "  Layer 8:  supergfxctl removed  → Removes original trigger"
echo "  Layer 9:  nouveau blacklisted  → Removes driver from ACPI crash path"
echo "            sleep blocked        → Prevents lid/idle/systemd sleep transitions"
echo "  Layer 10: amd_pmc blacklisted  → Removes AMD S0ix from crash path"
echo "  Layer 11: processor.max_cstate=1 → Caps CPU at C1 (POLL+C1 only)"
echo "            (eliminates remaining acpi_idle C2+ transitions without amd_pmc)"
echo ""
echo "Impact:"
echo "  Power: +5-10W higher idle consumption"
echo "  Stability: Eliminates ACPI crashes [0x00200800]"
echo "  Nvidia dGPU: NOT usable via nouveau (blacklisted)"
echo "    To revert blacklist: remove GRUB params + /etc/modprobe.d/blacklist-nouveau.conf"
echo "  AMD iGPU: remains active (display works), only runtime PM is disabled"
echo "  amd_pmc:  AMD S0ix/Modern Standby disabled (no S0ix driver)"
echo "  C-states: CPU capped at C1 (processor.max_cstate=1); no deep idle states"
echo ""
if [ "$GRUB_CHANGED" -eq 1 ]; then
    echo "⚠️  REBOOT REQUIRED for kernel parameters to take effect"
    echo "   Current kernel params won't include the new values until reboot."
    echo ""
fi
echo "Monitoring commands:"
echo "  Check for crashes:  sudo dmesg | grep 'reset reason'"
echo "  Check devices:      cat /sys/bus/pci/devices/0000:{00:01.1,01:00.0,01:00.1}/power/control"
echo "  Check service:      systemctl status nvidia-force-d0-early.service"
echo "  Check nouveau:      cat /sys/module/nouveau/parameters/runpm"
echo "  Check amdgpu:       cat /sys/bus/pci/devices/0000:05:00.0/power/control"
echo "  Check amd_pmc:      lsmod | grep amd_pmc  (should be empty)"
echo "  Check tuned:        systemctl is-enabled tuned.service"
echo ""
