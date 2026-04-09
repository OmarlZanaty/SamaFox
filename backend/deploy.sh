#!/bin/bash

# SamaFox Backend Deployment Script
# This script automates the deployment process on AWS EC2

set -e  # Exit on error

echo "🦊 SamaFox Backend Deployment Script"
echo "====================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
    print_error "package.json not found. Please run this script from the samafox-backend directory."
    exit 1
fi

print_info "Starting deployment process..."
echo ""

# Step 1: Install dependencies
print_info "Step 1: Installing dependencies..."
npm install
print_success "Dependencies installed"
echo ""

# Step 2: Generate Prisma Client
print_info "Step 2: Generating Prisma Client..."
npx prisma generate
print_success "Prisma Client generated"
echo ""

# Step 3: Build TypeScript
print_info "Step 3: Building TypeScript code..."
npm run build
print_success "Build completed"
echo ""

# Step 4: Database setup
print_info "Step 4: Setting up database..."
if [ ! -f "prisma/dev.db" ]; then
    print_info "Database not found. Creating and seeding..."
    npx prisma db push
    npm run seed
    print_success "Database created and seeded"
else
    print_info "Database exists. Applying migrations..."
    npx prisma db push
    print_success "Database updated"
fi
echo ""

# Step 5: Create logs directory
print_info "Step 5: Creating logs directory..."
mkdir -p logs
print_success "Logs directory ready"
echo ""

# Step 6: PM2 Management
print_info "Step 6: Managing PM2 process..."

# Check if PM2 is installed
if ! command -v pm2 &> /dev/null; then
    print_error "PM2 is not installed. Installing PM2..."
    sudo npm install -g pm2
    print_success "PM2 installed"
fi

# Check if app is already running
if pm2 list | grep -q "samafox-api"; then
    print_info "Restarting existing PM2 process..."
    pm2 restart samafox-api
    print_success "Server restarted"
else
    print_info "Starting new PM2 process..."
    pm2 start ecosystem.config.js
    pm2 save
    print_success "Server started"
fi
echo ""

# Step 7: Display status
print_info "Step 7: Checking server status..."
pm2 status
echo ""

# Step 8: Test the server
print_info "Step 8: Testing server..."
sleep 3  # Wait for server to start

if curl -s http://localhost:3000/health | grep -q "ok"; then
    print_success "Server is running and healthy!"
else
    print_error "Server health check failed. Check logs with: pm2 logs samafox-api"
    exit 1
fi
echo ""

# Get public IP
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || echo "Unable to fetch")

# Final message
echo "🎉 Deployment completed successfully!"
echo ""
echo "📊 Server Information:"
echo "   • Status: Running"
echo "   • Port: 3000"
echo "   • Public IP: $PUBLIC_IP"
echo "   • API URL: http://$PUBLIC_IP:3000/api/v1/"
echo "   • Health Check: http://$PUBLIC_IP:3000/health"
echo ""
echo "📝 Useful Commands:"
echo "   • View logs: pm2 logs samafox-api"
echo "   • Restart: pm2 restart samafox-api"
echo "   • Stop: pm2 stop samafox-api"
echo "   • Monitor: pm2 monit"
echo ""
print_success "All done! Your SamaFox backend is live! 🚀"

