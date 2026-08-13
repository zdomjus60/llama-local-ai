#!/bin/bash
# Create the Open WebUI admin credentials interactively.
# Run once during installation, or again to change them.
# The values are written to $BASE_DIR/owui.env; nothing is hardcoded here.

set -euo pipefail

BASE_DIR="${BASE_DIR:-$HOME/llama-ai}"
ENV_FILE="$BASE_DIR/owui.env"

echo
echo "Open WebUI - create the admin account"
echo "====================================="
echo "What you type now is saved in $ENV_FILE"
echo "(that file is only readable by you)."
echo

read -rp "Email: " EMAIL
while ! [[ "$EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; do
  echo "  A valid email is required (something@example.com)."
  read -rp "Email: " EMAIL
done

read -rp "Name (press Enter for \"Admin\"): " NAME
[ -z "$NAME" ] && NAME="Admin"

while true; do
  read -rsp "Password (min 8 characters): " PASS1
  echo
  if [ "${#PASS1}" -lt 8 ]; then
    echo "  Too short. The password must be at least 8 characters."
    continue
  fi
  read -rsp "Password (again): " PASS2
  echo
  if [ "$PASS1" = "$PASS2" ]; then
    break
  fi
  echo "  The two passwords do not match. Try again."
done

mkdir -p "$BASE_DIR"
umask 077
cat > "$ENV_FILE" <<EOF
WEBUI_ADMIN_EMAIL="$EMAIL"
WEBUI_ADMIN_PASSWORD="$PASS1"
WEBUI_ADMIN_NAME="$NAME"
EOF

echo
echo "Saved. $ENV_FILE"
