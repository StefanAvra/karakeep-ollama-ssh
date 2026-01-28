#!/bin/bash
# ~/karakeep-ollama-ssh.sh

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Usage function
usage() {
    echo -e "${BLUE}Usage:${NC} $0 [-u user] [-s server] [-m model] [-t timeout_minutes]"
    echo ""
    echo "Options:"
    echo "  -u    Remote username (default: current user)"
    echo "  -s    Remote server hostname or IP (required)"
    echo "  -m    Ollama model to use (default: gemma3:4b)"
    echo "  -t    Timeout in minutes (default: 120)"
    echo ""
    echo "Example:"
    echo "  $0 -s myserver.com"
    echo "  $0 -u admin -s 192.168.1.100 -m llama3:8b"
    exit 1
}

# Default configuration
REMOTE_USER="$(whoami)"
REMOTE_HOST=""
OLLAMA_MODEL="gemma3:4b"
TIMEOUT_MINUTES=120

# Parse command line arguments
while getopts "u:s:m:t:h" opt; do
    case $opt in
        u) REMOTE_USER="$OPTARG" ;;
        s) REMOTE_HOST="$OPTARG" ;;
        m) OLLAMA_MODEL="$OPTARG" ;;
        t) TIMEOUT_MINUTES="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Prompt for server if not provided
if [ -z "$REMOTE_HOST" ]; then
    echo -e "${YELLOW}No server specified.${NC}"
    read -p "Enter remote server hostname or IP: " REMOTE_HOST
    if [ -z "$REMOTE_HOST" ]; then
        echo -e "${RED}❌ Server is required.${NC}"
        exit 1
    fi
fi

echo -e "${BLUE}🚀 Starting Karakeep Ollama SSH Tunnel${NC}"
echo -e "${BLUE}   User: ${REMOTE_USER}${NC}"
echo -e "${BLUE}   Server: ${REMOTE_HOST}${NC}"
echo -e "${BLUE}   Model: ${OLLAMA_MODEL}${NC}"
echo ""

# Check if Ollama is installed
if ! command -v ollama &> /dev/null; then
    echo -e "${RED}❌ Ollama not found. Please install it first.${NC}"
    exit 1
fi

# Check if model exists
echo -e "${YELLOW}📦 Checking if model ${OLLAMA_MODEL} is available...${NC}"
if ! ollama list | grep -q "${OLLAMA_MODEL}"; then
    echo -e "${YELLOW}⬇️  Model not found. Pulling ${OLLAMA_MODEL}...${NC}"
    ollama pull "${OLLAMA_MODEL}"
fi

# Kill any existing Ollama processes
echo -e "${YELLOW}🛑 Stopping any existing Ollama instances...${NC}"
pkill ollama 2>/dev/null
sleep 2

# Start Ollama with proper config
echo -e "${YELLOW}📦 Starting Ollama...${NC}"
export OLLAMA_HOST=0.0.0.0:11434
export OLLAMA_ORIGINS="*"
OLLAMA_HOST=0.0.0.0:11434 OLLAMA_ORIGINS="*" ollama serve > /tmp/ollama.log 2>&1 &
sleep 3

# Get the actual Ollama PID
OLLAMA_PID=$(pgrep -f "ollama serve" | head -n 1)

if [ -z "$OLLAMA_PID" ]; then
    echo -e "${RED}❌ Ollama failed to start. Check /tmp/ollama.log${NC}"
    exit 1
fi

# Verify Ollama is running
if ! curl -s http://localhost:11434/api/tags > /dev/null; then
    echo -e "${RED}❌ Ollama not responding. Check /tmp/ollama.log${NC}"
    kill $OLLAMA_PID 2>/dev/null
    exit 1
fi
echo -e "${GREEN}✅ Ollama is running (PID: $OLLAMA_PID)${NC}"

# Create SSH tunnel
echo -e "${YELLOW}🔌 Creating SSH reverse tunnel...${NC}"
ssh -R 11434:localhost:11434 ${REMOTE_USER}@${REMOTE_HOST} -N -o ServerAliveInterval=60 -o ServerAliveCountMax=3 > /tmp/ssh-tunnel.log 2>&1 &
SSH_PID=$!
sleep 3

# Verify SSH tunnel is active
if ! kill -0 $SSH_PID 2>/dev/null; then
    echo -e "${RED}❌ SSH tunnel failed to establish. Check /tmp/ssh-tunnel.log${NC}"
    kill $OLLAMA_PID 2>/dev/null
    exit 1
fi
echo -e "${GREEN}✅ SSH tunnel established (PID: $SSH_PID)${NC}"

# Start socat on remote server
echo -e "${YELLOW}🔀 Starting socat relay on remote server...${NC}"
ssh ${REMOTE_USER}@${REMOTE_HOST} "pkill socat; nohup socat TCP-LISTEN:11434,fork,bind=10.0.0.1 TCP:127.0.0.1:11434 > /tmp/socat.log 2>&1 &"
sleep 2

# Test the connection from remote server
echo -e "${YELLOW}🧪 Testing connection from remote server...${NC}"
if ssh ${REMOTE_USER}@${REMOTE_HOST} "curl -s http://10.0.0.1:11434/api/tags" > /dev/null; then
    echo -e "${GREEN}✅ Connection test successful!${NC}"
else
    echo -e "${RED}❌ Connection test failed${NC}"
    cleanup
    exit 1
fi

# Auto-timeout timer
(
    sleep $((TIMEOUT_MINUTES * 60))
    echo -e "\n${YELLOW}⏰ Timeout reached (${TIMEOUT_MINUTES} minutes). Auto-closing...${NC}"
    kill -INT $$ 2>/dev/null
) &
TIMEOUT_PID=$!

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Tunnel is ready!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}📋 Karakeep Configuration (already set):${NC}"
echo -e "   OLLAMA_BASE_URL=http://10.0.0.1:11434"
echo -e "   INFERENCE_TEXT_MODEL=${OLLAMA_MODEL}"
echo ""
echo -e "${BLUE}📝 Next Steps:${NC}"
echo -e "   1. Go to Karakeep Admin Panel → Background Jobs"
echo -e "   2. Click 'Regenerate tags for all bookmarks'"
echo -e "   3. Press ${YELLOW}Ctrl+C${NC} here when done"
echo ""
echo -e "${YELLOW}⏰ Auto-timeout in ${TIMEOUT_MINUTES} minutes${NC}"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 Cleaning up...${NC}"

    # Kill timeout timer
    kill $TIMEOUT_PID 2>/dev/null

    # Stop socat on remote
    echo -e "${YELLOW}   Stopping socat on remote server...${NC}"
    ssh ${REMOTE_USER}@${REMOTE_HOST} "pkill socat" 2>/dev/null

    # Kill SSH tunnel
    echo -e "${YELLOW}   Closing SSH tunnel...${NC}"
    kill $SSH_PID 2>/dev/null

    # Kill Ollama
    echo -e "${YELLOW}   Stopping Ollama...${NC}"
    kill $OLLAMA_PID 2>/dev/null

    echo ""
    echo -e "${GREEN}✅ Cleanup complete!${NC}"
    echo ""
    exit 0
}

# Trap signals
trap cleanup INT TERM EXIT

# Keep script running and monitor processes
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Monitoring processes... (Ctrl+C to stop)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

while true; do
    # Check if Ollama is still running
    if ! kill -0 $OLLAMA_PID 2>/dev/null; then
        echo -e "\n${RED}❌ Ollama process died! Cleaning up...${NC}"
        cleanup
        exit 1
    fi

    # Check if SSH tunnel is still running
    if ! kill -0 $SSH_PID 2>/dev/null; then
        echo -e "\n${RED}❌ SSH tunnel died! Cleaning up...${NC}"
        cleanup
        exit 1
    fi

    sleep 10
done
