#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Use sudo."
    exit 1
fi

# Variables
SERVICE_NAME="tomcat"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
TOMCAT_USER="tomcat"
CATALINA_BASE="/var/lib/$TOMCAT_USER"
TOMCAT_DIR="/opt/apache/tomcat"
JAVA_HOME="/usr/lib/jvm/jdk-17"
FORTIFY_HOME="/var/lib/fortify"
REMOVE_JAVA=true

# Remove the Tomcat service
echo "Removing the Tomcat service..."
systemctl stop $SERVICE_NAME
systemctl disable $SERVICE_NAME
rm $SERVICE_FILE
systemctl daemon-reload

# Remove current user from tomcat group
echo "Removing current user $(logname) from the $TOMCAT_USER group..."
gpasswd -d "$(logname)" "$TOMCAT_USER"

# Remove tomcat user and tomcat home directory
echo "Deleting the user $TOMCAT_USER..."
userdel -r "$TOMCAT_USER"

# Remove CATALINA_BASE and TOMCAT_DIR directories
echo "Removing the following directories:"
echo "- $CATALINA_BASE"
echo "- $TOMCAT_DIR"
echo "- $FORTIFY_HOME"
rm -rf $CATALINA_BASE $TOMCAT_DIR $FORTIFY_HOME

# Remove Java if REMOVE_JAVA is set to true
if [ "$REMOVE_JAVA" = true ]; then
    echo "Removing Java..."
    TARGET_DIR=$(readlink -f "$JAVA_HOME")
    echo "Removing $JAVA_HOME"
    rm -rf "$JAVA_HOME"
    if [ -n "$TARGET_DIR" ] && [ -d "$TARGET_DIR" ]; then
        echo "Removing actual directory: $TARGET_DIR"
        rm -rf "$TARGET_DIR"
    fi
fi

# Final message
echo "✅ Uninstall complete!"
