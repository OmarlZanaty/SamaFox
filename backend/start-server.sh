#!/bin/bash

# SamaFox Backend Server Startup Script

echo "🦊 Starting SamaFox Backend Server..."
echo "=================================="

# Check if database exists
if [ ! -f "./prisma/dev.db" ]; then
  echo "⚠️  Database not found. Creating database..."
  npm run prisma:push
fi

# Check if node_modules exists
if [ ! -d "./node_modules" ]; then
  echo "⚠️  Dependencies not found. Installing..."
  npm install
fi

# Check if dist exists
if [ ! -d "./dist" ]; then
  echo "⚠️  Build not found. Building..."
  npm run build
fi

# Create uploads directory if it doesn't exist
mkdir -p uploads

# Start the server
echo "🚀 Starting server on port 3000..."
npm start

