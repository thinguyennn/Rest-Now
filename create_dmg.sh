#!/bin/bash

set -e

APP_NAME="RestNow"
APP_PATH="build/RestNow.app"

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH not found!"
    exit 1
fi

echo "Creating DMG installer..."
create-dmg --overwrite "$APP_PATH"

echo "✓ DMG created successfully!"
