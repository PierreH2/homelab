#!/bin/bash
#
# btrfs-snapshot.sh - Btrfs snapshot management for homelab A/B rollback
#
# Uses snapper to create and manage Btrfs snapshots of the root filesystem.
# Allows rollback to a previous state after risky changes (kernel updates,
# system config changes, crash fix experiments, etc.)
#
# The filesystem is on Btrfs with the following subvolumes:
#   ID 256  /root   → mounted at /
#   ID 257  /home   → mounted at /home
#   ID 259  /.snapshots → managed by snapper
#
# Rollback mechanism:
#   snapper rollback <id> creates a new default subvolume from the snapshot.
#   After reboot, GRUB boots into the rolled-back state.
#   The old (failed) state is preserved as a snapshot for inspection.
#
# Usage:
#   btrfs-snapshot.sh list
#   btrfs-snapshot.sh create [description]
#   btrfs-snapshot.sh rollback <id>
#   btrfs-snapshot.sh delete <id>
#   btrfs-snapshot.sh diff <id1> <id2>
#   btrfs-snapshot.sh status
#

SNAPPER="snapper --no-dbus -c root"

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  list                  List all snapshots with IDs and descriptions
  create [description]  Create a new snapshot of current root state
  rollback <id>         Roll back to snapshot #id (reboot required to apply)
  delete <id>           Delete a snapshot
  diff <id1> <id2>      Show files changed between two snapshots
  status                Show snapper config and disk usage

Examples:
  $(basename "$0") create 'before-amd-pmc-blacklist'
  $(basename "$0") list
  $(basename "$0") rollback 3
  $(basename "$0") diff 2 4
  $(basename "$0") delete 1

Tip: Always create a snapshot before making system changes:
  sudo $(basename "$0") create "pre-<change-description>"
EOF
}

require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Error: This command requires root. Run with: sudo $(basename "$0") $*"
        exit 1
    fi
}

cmd="${1:-}"

case "$cmd" in
    list)
        sudo $SNAPPER list
        ;;

    create)
        require_root "$@"
        DESC="${2:-manual-$(date +%Y%m%d_%H%M)}"
        $SNAPPER create --description "$DESC" --cleanup-algorithm number
        echo ""
        echo "✓ Snapshot created: '$DESC'"
        echo ""
        $SNAPPER list
        ;;

    rollback)
        require_root "$@"
        ID="${2:-}"
        if [ -z "$ID" ]; then
            echo "Error: snapshot ID required."
            echo "Run '$(basename "$0") list' to see available snapshots."
            exit 1
        fi

        echo "=============================================="
        echo "  Rolling back to snapshot #$ID"
        echo "=============================================="
        echo ""
        sudo $SNAPPER list
        echo ""
        echo "⚠️  This will roll back the root filesystem to snapshot #$ID."
        echo "   The current state will be preserved as a new snapshot."
        echo "   A reboot is required to complete the rollback."
        echo ""
        read -p "Continue? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 0
        fi

        $SNAPPER rollback "$ID"
        echo ""
        echo "✓ Rollback prepared to snapshot #$ID."
        echo "  Reboot now to apply:"
        echo "    sudo reboot"
        echo ""
        echo "  After reboot, verify state with:"
        echo "    sudo $(basename "$0") list"
        ;;

    delete)
        require_root "$@"
        ID="${2:-}"
        if [ -z "$ID" ]; then
            echo "Error: snapshot ID required."
            exit 1
        fi
        $SNAPPER delete "$ID"
        echo "✓ Snapshot #$ID deleted."
        echo ""
        $SNAPPER list
        ;;

    diff)
        ID1="${2:-}"
        ID2="${3:-}"
        if [ -z "$ID1" ] || [ -z "$ID2" ]; then
            echo "Error: two snapshot IDs required."
            echo "Usage: $(basename "$0") diff <id1> <id2>"
            exit 1
        fi
        sudo $SNAPPER diff "${ID1}..${ID2}"
        ;;

    status)
        echo "=== Snapper config ==="
        sudo $SNAPPER get-config | grep -E "SUBVOLUME|NUMBER_LIMIT|TIMELINE_CREATE"
        echo ""
        echo "=== Snapshots ==="
        sudo $SNAPPER list
        echo ""
        echo "=== Btrfs disk usage ==="
        sudo btrfs filesystem usage / 2>/dev/null | head -12 || \
            df -h / /home
        echo ""
        echo "=== Subvolumes ==="
        sudo btrfs subvolume list / | grep -v containerd | head -20
        ;;

    ""|help|--help|-h)
        usage
        ;;

    *)
        echo "Unknown command: $cmd"
        echo ""
        usage
        exit 1
        ;;
esac
