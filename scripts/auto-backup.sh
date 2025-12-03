#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo ""
echo "🤖 AUTOMATIC BACKUP WITH ROTATION"
echo "════════════════════════════════════════════"
echo ""

# Step 1: Create backup
log_step "Step 1/2: Creating backup..."
echo ""
"$SCRIPT_DIR/backup.sh"

echo ""
echo "════════════════════════════════════════════"
echo ""

# Step 2: Cleanup old backups
log_step "Step 2/2: Cleaning old backups..."
echo ""
"$SCRIPT_DIR/cleanup-backups.sh"

echo ""
echo "════════════════════════════════════════════"
echo "✅ AUTOMATIC BACKUP COMPLETE"
echo "════════════════════════════════════════════"
echo ""
log_info "Backup created and rotated successfully!"
echo ""