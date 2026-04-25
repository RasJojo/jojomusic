#!/bin/bash
# Setup Android SDK for JojoMusic builds

set -e

echo "🤖 Setting up Android SDK..."

# Create Android SDK directory
ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
mkdir -p "$ANDROID_SDK_ROOT"

# Export for this session
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"

echo "📦 Downloading Android SDK Command-line Tools..."
cd /tmp

# Download Android SDK command-line tools
# This is the latest cmdline-tools as of 2026
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip"
wget -q "$CMDLINE_TOOLS_URL" -O cmdline-tools.zip || curl -s -o cmdline-tools.zip "$CMDLINE_TOOLS_URL"

# Extract to proper location
unzip -q cmdline-tools.zip
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
mv cmdline-tools "$ANDROID_SDK_ROOT/cmdline-tools/latest"

rm cmdline-tools.zip

echo "✅ Android SDK installed to: $ANDROID_SDK_ROOT"

# Accept licenses
echo "📋 Accepting Android licenses..."
mkdir -p "$ANDROID_SDK_ROOT/licenses"
echo -e "\n24333f8a63b6825ea9c5514f83c2829b004d1fee" > "$ANDROID_SDK_ROOT/licenses/android-sdk-license"

# Update environment
echo ""
echo "⚙️ Add to your ~/.zshrc or ~/.bash_profile:"
echo ""
echo "export ANDROID_HOME=\$HOME/Library/Android/sdk"
echo "export PATH=\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH"
echo ""
echo "Then run: flutter doctor --android-licenses"
echo ""
