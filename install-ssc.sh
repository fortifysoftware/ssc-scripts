#!/bin/bash

# Tomcat Variables
JAVA_HOME="/usr/lib/jvm/jdk-17"  # As of this writing, SSC Server requires Java 17 to run
TOMCAT_USER="tomcat"
CATALINA_BASE="/var/lib/$TOMCAT_USER"
TOMCAT_DIR="/opt/apache/tomcat"
CATALINA_HOME="$TOMCAT_DIR/default"  # "default" is a symlink to the actual version
SERVICE_NAME="tomcat"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
MAX_HEAP="12G"

# Fortify SSC Variables
FORTIFY_HOME="/var/lib/fortify"
SSC_URL="http://localhost:8080/ssc"  # For now, this script only supports the "/ssc" context path
JDBC_URL="jdbc:sqlserver://dp5550.local:1433;database=sscauto;sendStringParametersAsUnicode=false;encrypt=false"
DB_USERNAME="sscuser"
DB_PASSWORD="fortify"
PROCESS_SEED_BUNDLE="$(ls Fortify_Process_Seed*.zip)"
REPORT_SEED_BUNDLE="$(ls Fortify_Report_Seed*.zip)"
PCI_BASIC_SEED_BUNDLE="$(ls Fortify_PCI_Basic_Seed*.zip)"
PCI_SSF_SEED_BUNDLE="$(ls Fortify_PCI_SSF_Basic_Seed*.zip)"
LICENSE_FILE="fortify.license"

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "⚠️ This script must be run as root. Use sudo."
    exit 1
fi

# Check if license file exists
if [ ! -f "$LICENSE_FILE" ]; then
    echo "⚠️ fortify.license file not detected in current directory."
    echo "  Please make sure license file is available in the same directory as the script."
    echo "  Exiting..."
    exit 1
fi

# Check if seed bundle files exist
if [ ! -f "$PROCESS_SEED_BUNDLE" ]; then
    echo "⚠️ Process seed bundle zip file not detected in current directory."
    echo "  Please make sure the seed bundle files are available in the same directory as the script."
    echo "  Exiting..."
    exit 1
elif [ ! -f "$REPORT_SEED_BUNDLE" ]; then
    echo "⚠️ Report seed bundle zip file not detected in current directory."
    echo "  Please make sure the seed bundle files are available in the same directory as the script."
    echo "  Exiting..."
    exit 1
elif [ ! -f "$PCI_BASIC_SEED_BUNDLE" ]; then
    echo "⚠️ PCI basic seed bundle zip file not detected in current directory."
    echo "  Please make sure the seed bundle files are available in the same directory as the script."
    echo "  Exiting..."
    exit 1
elif [ ! -f "$PCI_SSF_SEED_BUNDLE" ]; then
    echo "⚠️ PCI SSF seed bundle zip file not detected in current directory."
    echo "  Please make sure the seed bundle files are available in the same directory as the script."
    echo "  Exiting..."
    exit 1
fi

# Determine architecture of machine
# Only x86_64 and aarch64 are supported
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    ARCH="x64"
fi

JDK_ZIP=$(ls jdk-17*linux* | grep $ARCH)

# Check if JDK file exists
if [ ! -f "$JDK_ZIP" ]; then
    echo "⚠️ Java 17 .tar.gz file not found. Please make sure the file exists in the"
    echo "  same directory as the script. Exiting..."
    exit 1
fi

JDK_VERSION=$(echo $JDK_ZIP | grep -oh -m1 '[0-9]\+\.[.0-9]\+')

# Check if JDK_VERSION is defined
if [ -z "$JDK_VERSION" ]; then
    echo "⚠️ Cannot determine Java version from filename. Exiting..."
    exit 1
fi

echo "Removing old JDK 17 symlink if it exists"
if [ -L /usr/lib/jvm/jdk-17 ]
then
        unlink /usr/lib/jvm/jdk-17
fi

echo "Check if /usr/lib/jvm exists"
if [ ! -d /usr/lib/jvm ]
then
        mkdir /usr/lib/jvm
fi
echo "Extracting the JDK .tar.gz file..."
tar xzf $JDK_ZIP -C $(dirname "$JAVA_HOME")
echo "Creating the jdk-17 symlink..."
ln -s jdk-$JDK_VERSION $JAVA_HOME

if [ -f "fonts.zip" ]; then
  echo "Extracting fonts.zip to /usr/share/fonts/truetype/"
  unzip -q fonts.zip -d /usr/share/fonts/truetype/
else
  echo "⚠️  fonts.zip not found. To install the fonts later,"
  echo -e "   copy the font files to \e[1m/usr/share/fonts/truetype/\e[0m"
fi

# Install Tomcat
TOMCAT_ZIP=$(ls apache-tomcat-10*.zip)
TOMCAT_VERSION=$(echo $TOMCAT_ZIP | grep -oh -m1 '[0-9]\+\.[0-9]\+\.[0-9]\+')
### Check if TOMCAT_DIR does not exist ###
if [ ! -d "$TOMCAT_DIR" ]
then
    mkdir -p $TOMCAT_DIR
fi
unzip -q $TOMCAT_ZIP -d $TOMCAT_DIR
mv $TOMCAT_DIR/apache-tomcat-$TOMCAT_VERSION $TOMCAT_DIR/$TOMCAT_VERSION
chown -R root:root $TOMCAT_DIR
ln -s $TOMCAT_VERSION $CATALINA_HOME
rm $CATALINA_HOME/bin/*.bat
chmod +x $CATALINA_HOME/bin/*.sh

# Check for and create tomcat user
if ! id "$TOMCAT_USER" &>/dev/null; then
    echo "Creating system user '$TOMCAT_USER'..."
    useradd -r -s /sbin/nologin -c "Tomcat system (non-login) account" "$TOMCAT_USER"
fi

# Add current user to tomcat group
echo "Adding the current user to the $TOMCAT_USER group..."
usermod -aG "$TOMCAT_USER" "$(logname)"

# Create necessary directories
echo "Creating $CATALINA_BASE and $FORTIFY_HOME..."
mkdir -p "$CATALINA_BASE" "$FORTIFY_HOME/index"

# Copy Tomcat conf folder to CATALINA_BASE
cp -p -r $CATALINA_HOME/conf $CATALINA_BASE

# Create required folders under CATALINA_BASE
mkdir $CATALINA_BASE/bin $CATALINA_BASE/logs $CATALINA_BASE/temp $CATALINA_BASE/webapps $CATALINA_BASE/work

# Create setenv.sh file
echo "Creating $CATALINA_BASE/bin/setenv.sh file..."
cat <<EOF > "$CATALINA_BASE/bin/setenv.sh"
JAVA_HOME=$JAVA_HOME
CATALINA_OPTS="-Xmx$MAX_HEAP -Dfile.encoding=UTF-8 -Dfortify.home=$FORTIFY_HOME -Djava.awt.headless=true -Djava.library.path=/usr/lib64"
EOF

# Copy seed bundle zip files
echo "Creating directory $FORTIFY_HOME/bundles..."
mkdir -p $FORTIFY_HOME/bundles
echo "Copying seed bundle zip files to $FORTIFY_HOME/bundles/"
cp -p Fortify_*Seed*.zip $FORTIFY_HOME/bundles/

# Create ssc.autoconfig file
echo "Creating $FORTIFY_HOME/ssc.autoconfig file..."
cat <<EOF > "$FORTIFY_HOME/ssc.autoconfig"
appProperties:
  host.url: '$SSC_URL'
  searchIndex.location: '$FORTIFY_HOME/index'

datasourceProperties:
  db.username: '$DB_USERNAME'
  db.password: '$DB_PASSWORD'
  jdbc.url: '$JDBC_URL'

dbMigrationProperties:
  migration.enabled: true

seeds:
- '$FORTIFY_HOME/bundles/$PROCESS_SEED_BUNDLE'
- '$FORTIFY_HOME/bundles/$REPORT_SEED_BUNDLE'
- '$FORTIFY_HOME/bundles/$PCI_BASIC_SEED_BUNDLE'
- '$FORTIFY_HOME/bundles/$PCI_SSF_SEED_BUNDLE'
EOF

# Copy fortify.license file
echo "Copying fortify.license file to $FORTIFY_HOME/ directory..."
cp -p $LICENSE_FILE $FORTIFY_HOME/

ln -s $CATALINA_HOME/bin/tomcat-juli.jar $CATALINA_BASE/bin/tomcat-juli.jar

# Expand ssc.war under webapps directory
unzip -q ssc.war -d $CATALINA_BASE/webapps/ssc

# Modify ownership
chown -R "$TOMCAT_USER":"$TOMCAT_USER" "$CATALINA_BASE"
chown -R "$TOMCAT_USER":"$TOMCAT_USER" "$FORTIFY_HOME"

# Create systemd service file
echo "Creating systemd service file at $SERVICE_FILE..."
cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
LimitNOFILE=16384

Environment="CATALINA_HOME=$CATALINA_HOME"
Environment="CATALINA_BASE=$CATALINA_BASE"

WorkingDirectory=$CATALINA_BASE

ExecStart=$CATALINA_HOME/bin/startup.sh
ExecStop=$CATALINA_HOME/bin/shutdown.sh

SuccessExitStatus=143

User=$TOMCAT_USER
Group=$TOMCAT_USER
UMask=0007
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Set permissions
chmod 644 "$SERVICE_FILE"

# Reload systemd and enable the service
echo "Reloading systemd and enabling the service..."
systemctl daemon-reload
systemctl enable $SERVICE_NAME

# Final messages
echo -e "\n✅ Apache Tomcat installation is complete! 🍻\n"
echo -e "❗\e[1mIMPORTANT\e[0m❗"
echo "  ‾‾‾‾‾‾‾‾‾"
echo "• The Tomcat service has not been started in case further configuration"
echo "  changes are required (such as enabling HTTPS or using a different port)."
echo -e "  If so, the Tomcat \e[1mserver.xml\e[0m file can be opened with the following command:"
echo -e "  \e[1;32msudo -u $TOMCAT_USER \e[1;34mvi \e[0m\e[1m$CATALINA_BASE/config/server.xml\e[0m"
echo -e "• \e[5;31mTo start the service and kick off the SSC initialization, run the following:\e[0m"
echo -e "  \e[1;32msudo\e[0m \e[1;34msystemctl start $SERVICE_NAME\e[0m"
echo "• To check the status of the service, run the following:"
echo -e "  \e[1;32msudo\e[0m \e[1;34msystemctl status $SERVICE_NAME\e[0m"
echo "• To stop the service, run the following:"
echo -e "  \e[1;32msudo\e[0m \e[1;34msystemctl stop $SERVICE_NAME\e[0m"
echo "• Once SSC is up and running, navigate to"
echo "  🔗 $SSC_URL"
echo -e "  and login with the following default credentials: \e[1madmin/admin\e[0m"
echo "• After SSC initialization is complete, feel free to remove the following files and folders:"
echo -e "  - \e[1m$FORTIFY_HOME/ssc.autoconfig\e[0m"
echo -e "  - \e[1m$FORTIFY_HOME/bundles/\e[0m"
echo "• The Fortify SSC Server documentation can be found here:"
echo "  🔗 https://www.microfocus.com/documentation/fortify-software-security-center/"
echo "• Apache Tomcat logs can be found under:"
echo -e "  🐱 \e[1m$CATALINA_BASE/logs/\e[0m"
echo "• SSC Server logs can be found under:"
echo -e "  🇫  \e[1m$FORTIFY_HOME/ssc/logs/\e[0m"
