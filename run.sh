#!/usr/bin/env bash
set -euo pipefail

PORT=20128
HOST="0.0.0.0"
BASE_URL="http://localhost:${PORT}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}9Router — build & tray launcher${NC}"

# --- Build first (old server keeps serving during build) ---
echo -e "${CYAN}Building...${NC}"
PORT=${PORT} HOSTNAME=${HOST} NEXT_PUBLIC_BASE_URL=${BASE_URL} npm run build
echo -e "${GREEN}Build complete${NC}"

# --- Kill old server only after build succeeds ---
PID=$(lsof -ti:${PORT} 2>/dev/null || true)
if [ -n "$PID" ]; then
  echo -e "${YELLOW}Killing existing process on port ${PORT} (PID: ${PID})${NC}"
  kill -9 $PID 2>/dev/null || true
  sleep 0.5
fi

# --- Start server in background ---
echo -e "${CYAN}Starting server on port ${PORT}...${NC}"
PORT=${PORT} HOSTNAME=${HOST} nohup npm run start > /dev/null 2>&1 &
SERVER_PID=$!
disown
echo "Server PID: ${SERVER_PID}"

# Wait for server to be ready
echo -ne "${CYAN}Waiting for server"
for i in $(seq 1 30); do
  if curl -sf http://localhost:${PORT} > /dev/null 2>&1; then
    echo -e "\n${GREEN}Server ready at ${BASE_URL}${NC}"
    break
  fi
  echo -n "."
  sleep 0.5
done

# --- Start tray (bypass CLI — no standalone build needed) ---
echo -e "${CYAN}Launching system tray...${NC}"
TRAY_LOG="${SCRIPT_DIR}/tray.log"
nohup node -e "
  process.env.TRAY_MODE = '1';
  process.on('SIGHUP', () => {});
  const { initTray } = require('${SCRIPT_DIR}/cli/src/cli/tray/tray');
  initTray({
    port: ${PORT},
    onQuit: () => { process.exit(0); },
    onOpenDashboard: () => {
      const { exec } = require('child_process');
      exec('open http://localhost:${PORT}/dashboard');
    }
  });
  console.log('Tray icon active.');
" > "$TRAY_LOG" 2>&1 &
disown

echo -e "${GREEN}Tray icon active. You can safely close this terminal.${NC}"
echo -e "  Server PID: ${SERVER_PID} | Tray log: ${TRAY_LOG}"
