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
#
# `prisma migrate deploy`, NOT `db push`. `db push` reshapes the schema and
# silently skips every migration's DATA work, and this history has three such
# steps that must run exactly once:
#   * 20260823000000 — reconciles historical تبديل التارجيت (without it, past
#     conversions are handed back a second time)
#   * 20260823020000 — backfills each agency's self-charge counter
#   * 20260825000000 — seeds gift_categories with the tabs the app ships
#
# The migration folder was re-baselined onto `0_init`, so a database created
# before that has the OLD migration names in `_prisma_migrations` and would try
# to replay `0_init` over live tables. Marking it as already applied is a no-op
# on a fresh database and the required fix on an existing one.
print_info "Step 4: Setting up database..."
# Which database is this?
#
# `migrate status` CANNOT answer that: it prints the name `0_init` both when the
# migration is pending and when it is missing locally, so grepping for it
# skipped the resolve in exactly the case that needs it (a live database) and
# `migrate deploy` then replayed 54 bare `CREATE TABLE`s over live tables.
#
# The honest test is whether the schema already exists. A `SELECT` against
# `users` fails on a fresh database and succeeds on a live one, and inside an
# `if` its exit code is not fatal under `set -e`.
#
# Marking 0_init applied is NOT safe on a fresh database — it would record the
# baseline without creating a single table, and every later ALTER would fail.
# So it runs only for a database that already has the schema.
if npx prisma db execute --schema=prisma/schema.prisma --stdin >/dev/null 2>&1 <<'SQL'
SELECT 1 FROM "users" LIMIT 1;
SQL
then
    print_info "Existing database detected — marking baseline 0_init as applied..."
    npx prisma migrate resolve --applied 0_init || true
else
    print_info "Fresh database — 0_init will be applied by migrate deploy"
fi

print_info "Applying migrations..."
npx prisma migrate deploy
print_success "Database migrated"

# Still posters for video products uploaded before posters existed. Idempotent:
# anything that already has one is skipped.
print_info "Backfilling store posters..."
npm run backfill:posters || print_info "Poster backfill skipped (ffmpeg unavailable?)"
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

