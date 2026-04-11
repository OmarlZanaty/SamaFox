#!/bin/bash

# SamaFox Flutter Build Script

echo "🚀 Starting SamaFox Flutter build process..."
echo ""

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed. Please install Flutter first."
    exit 1
fi

echo "✅ Flutter found: $(flutter --version | head -n 1)"
echo ""

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean

# Get dependencies
echo "📦 Getting dependencies..."
flutter pub get

# Generate code for models and services
echo "🔨 Generating code for models and services..."
flutter pub run build_runner build --delete-conflicting-outputs

# Check for errors
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build process completed successfully!"
    echo ""
    echo "📱 To run the app:"
    echo "   flutter run"
    echo ""
    echo "🏗️  To build APK:"
    echo "   flutter build apk --release"
    echo ""
    echo "📦 To build App Bundle:"
    echo "   flutter build appbundle --release"
else
    echo ""
    echo "❌ Build process failed. Please check the errors above."
    exit 1
fi
