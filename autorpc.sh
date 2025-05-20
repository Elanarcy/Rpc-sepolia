#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print ASCII art
print_ascii_art() {
    cat << "EOF"
███████╗██╗░░░░░░█████╗░███╗░░██╗░█████╗░██████╗░░█████╗░██╗░░░██╗  ░█████╗░░██████╗░██████╗
██╔════╝██║░░░░░██╔══██╗████╗░██║██╔══██╗██╔══██╗██╔══██╗╚██╗░██╔╝  ██╔══██╗██╔════╝██╔════╝
█████╗░░██║░░░░░███████║██╔██╗██║███████║██████╔╝██║░░╚═╝░╚████╔╝░  ██║░░╚═╝╚█████╗░╚█████╗░
██╔══╝░░██║░░░░░██╔══██║██║╚████║██╔══██║██╔══██╗██║░░██╗░░╚██╔╝░░  ██║░░██╗░╚═══██╗░╚═══██╗
███████╗███████╗██║░░██║██║░╚███║██║░░██║██║░░██║╚█████╔╝░░░██║░░░  ╚█████╔╝██████╔╝██████╔╝
╚══════╝╚══════╝╚═╝░░╚═╝╚═╝░░╚══╝╚═╝░░╚═╝╚═╝░░╚═╝░╚════╝░░░░╚═╝░░░  ░╚════╝░╚═════╝░╚═════╝░
EOF
}

# Function to print introduction
print_intro() {
    echo -e "${YELLOW}Welcome to the Ethereum Sepolia Testnet Node Installer!${NC}"
    echo "This script will set up an Ethereum Sepolia RPC (Geth) and Beacon (Prysm) node on your system."
    echo "Join our Telegram channel for updates and support: ${GREEN}https://t.me/cssurabaya${NC}"
    echo ""
    echo "Press Enter to continue or Ctrl+C to cancel..."
    read
}

# Function to check if a command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}Error: $1 is not installed. Please install it and try again.${NC}"
        exit 1
    fi
}

# Function to check port availability
check_ports() {
    local ports=("30303" "8545" "8546" "8551" "4000" "3500")
    for port in "${ports[@]}"; do
        if netstat -tuln | grep -q ":${port} "; then
            echo -e "${RED}Error: Port ${port} is in use. Please free it or modify docker-compose.yml to use a different port.${NC}"
            exit 1
        fi
    done
}

# Function to handle errors
handle_error() {
    echo -e "${RED}Error: $1${NC}"
    exit 1
}

# Print ASCII art and introduction
print_ascii_art
print_intro

# Step 1: Install Dependencies
echo -e "${YELLOW}Step 1: Installing dependencies...${NC}"
sudo apt-get update && sudo apt-get upgrade -y || handle_error "Failed to update and upgrade packages"
sudo apt install -y curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev || handle_error "Failed to install packages"

# Install Docker
echo -e "${YELLOW}Installing Docker...${NC}"
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    sudo apt-get remove -y $pkg 2>/dev/null
done

sudo apt-get update || handle_error "Failed to update package list"
sudo apt-get install -y ca-certificates curl gnupg || handle_error "Failed to install Docker prerequisites"
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || handle_error "Failed to download Docker GPG key"
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || handle_error "Failed to set up Docker repository"

sudo apt-get update || handle_error "Failed to update package list after adding Docker repo"
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || handle_error "Failed to install Docker"

# Test Docker
echo -e "${YELLOW}Testing Docker installation...${NC}"
sudo docker run hello-world || handle_error "Docker test failed. Please check Docker installation."

sudo systemctl enable docker || handle_error "Failed to enable Docker service"
sudo systemctl restart docker || handle_error "Failed to restart Docker service"

# Step 2: Create Directories
echo -e "${YELLOW}Step 2: Creating directories...${NC}"
mkdir -p /root/ethereum/execution /root/ethereum/consensus || handle_error "Failed to create directories"

# Step 3: Generate JWT Secret
echo -e "${YELLOW}Step 3: Generating JWT secret...${NC}"
openssl rand -hex 32 > /root/ethereum/jwt.hex || handle_error "Failed to generate JWT secret"
echo "JWT secret generated. Verifying..."
cat /root/ethereum/jwt.hex || handle_error "JWT secret file is empty or missing"

# Step 4: Configure docker-compose.yml
echo -e "${YELLOW}Step 4: Configuring docker-compose.yml...${NC}"
cd /root/ethereum || handle_error "Failed to change to /root/ethereum directory"
cat << EOF > docker-compose.yml
services:
  geth:
    image: ethereum/client-go:stable
    container_name: geth
    network_mode: host
    restart: unless-stopped
    ports:
      - 30303:30303
      - 30303:30303/udp
      - 8545:8545
      - 8546:8546
      - 8551:8551
    volumes:
      - /root/ethereum/execution:/data
      - /root/ethereum/jwt.hex:/data/jwt.hex
    command:
      - --sepolia
      - --http
      - --http.api=eth,net,web3
      - --http.addr=0.0.0.0
      - --authrpc.addr=0.0.0.0
      - --authrpc.vhosts=*
      - --authrpc.jwtsecret=/data/jwt.hex
      - --authrpc.port=8551
      - --syncmode=snap
      - --gcmode=full
      - --datadir=/data
      - --cache=4024
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  prysm:
    image: gcr.io/prysmaticlabs/prysm/beacon-chain
    container_name: prysm
    network_mode: host
    restart: unless-stopped
    volumes:
      - /root/ethereum/consensus:/data
      - /root/ethereum/jwt.hex:/data/jwt.hex
    depends_on:
      - geth
    ports:
      - 4000:4000
      - 3500:3500
    command:
      - --sepolia
      - --accept-terms-of-use
      - --datadir=/data
      - --disable-monitoring
      - --rpc-host=0.0.0.0
      - --execution-endpoint=http://127.0.0.1:8551
      - --jwt-secret=/data/jwt.hex
      - --rpc-port=4000
      - --grpc-gateway-corsdomain=*
      - --grpc-gateway-host=0.0.0.0
      - --grpc-gateway-port=3500
      - --min-sync-peers=3
      - --checkpoint-sync-url=https://checkpoint-sync.sepolia.ethpandaops.io
      - --genesis-beacon-api-url=https://checkpoint-sync.sepolia.ethpandaops.io
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
echo "docker-compose.yml created successfully."

# Step 5: Check for Port Conflicts
echo -e "${YELLOW}Step 5: Checking for port conflicts...${NC}"
check_ports
echo -e "${GREEN}All required ports are free.${NC}"

# Step 6: Run Geth & Prysm Nodes
echo -e "${YELLOW}Step 6: Starting Geth and Prysm nodes...${NC}"
docker compose up -d || handle_error "Failed to start Docker containers"

# Verify Containers
echo -e "${YELLOW}Verifying running containers...${NC}"
if docker ps | grep -q "geth" && docker ps | grep -q "prysm"; then
    echo -e "${GREEN}Geth and Prysm containers are running successfully!${NC}"
else
    echo -e "${RED}Error: One or both containers failed to start. Check logs with: docker compose logs -f${NC}"
    exit 1
fi

# Display Logs Instructions
echo -e "${YELLOW}Setup complete!${NC}"
echo "To view all logs: ${GREEN}docker compose logs -f${NC}"
echo "To view the last 100 lines of logs: ${GREEN}docker compose logs -fn 100${NC}"
echo ""
echo -e "${YELLOW}Join our Telegram channel for support and updates: ${GREEN}https://t.me/cssurabaya${NC}"
echo -e "${GREEN}Thank you for using the Sepolia Node Installer!${NC}"
