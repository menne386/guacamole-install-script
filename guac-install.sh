#!/bin/bash
#Basic guacamole install script. 



# Check if user is root or sudo
if ! [ $( id -u ) = 0 ]; then
    echo "Please run this script as sudo or root" 1>&2
    exit 1
fi

# Check to see if any old files left over
if [ "$( find . -maxdepth 1 \( -name 'guacamole-*' -o -name 'mysql-connector-java-*' \) )" != "" ]; then
    echo "Possible temp files detected. Please review 'guacamole-*' & 'mysql-connector-java-*'" 1>&2
    exit 1
fi


# Version number of Guacamole to install
# Homepage ~ https://guacamole.apache.org/releases/
GUACVERSION="1.2.0"

# Latest Version of MySQL Connector/J if manual install is required (if libmariadb-java/libmysql-java is not available via apt)
# Homepage ~ https://dev.mysql.com/downloads/connector/j/
MCJVER="8.0.19"

# Colors to use for output
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Log Location
LOG="/tmp/guacamole_${GUACVERSION}_build.log"

# Initialize variable values
PROMPT=""
MYSQL=""



# Different version of Ubuntu and Debian have different package names...
source /etc/os-release
if [[ "${NAME}" == "Ubuntu" ]]; then
    # Ubuntu > 18.04 does not include universe repo by default
    # Add the "Universe" repo, don't update
    add-apt-repository -yn universe
    # Set package names depending on version
    JPEGTURBO="libjpeg-turbo8-dev"
    if [[ "${VERSION_ID}" == "16.04" ]]; then
        LIBPNG="libpng12-dev"
    else
        LIBPNG="libpng-dev"
    fi
elif [[ "${NAME}" == *"Debian"* ]] || [[ "${NAME}" == *"Raspbian GNU/Linux"* ]] || [[ "${NAME}" == *"Kali GNU/Linux"* ]]; then
    JPEGTURBO="libjpeg62-turbo-dev"
    if [[ "${PRETTY_NAME}" == *"stretch"* ]] || [[ "${PRETTY_NAME}" == *"buster"* ]] || [[ "${PRETTY_NAME}" == *"Kali GNU/Linux Rolling"* ]]; then
        LIBPNG="libpng-dev"
    else
        LIBPNG="libpng12-dev"
    fi
else
    echo "Unsupported distribution - Debian, Kali, Raspbian or Ubuntu only"
    exit 1
fi

# Update apt so we can search apt-cache for newest Tomcat version supported & libmariadb-java/libmysql-java
echo -e "${BLUE}Updating apt...${NC}"
apt-get -qq update

# tomcat9 is the latest version
# tomcat8.0 is end of life, but tomcat8.5 is current
# fallback is tomcat7
if [[ $( apt-cache show tomcat9 2> /dev/null | egrep "Version: 9" | wc -l ) -gt 0 ]]; then
    echo -e "${BLUE}Found tomcat9 package...${NC}"
    TOMCAT="tomcat9"
elif [[ $( apt-cache show tomcat8 2> /dev/null | egrep "Version: 8.[5-9]" | wc -l ) -gt 0 ]]; then
    echo -e "${BLUE}Found tomcat8.5+ package...${NC}"
    TOMCAT="tomcat8"
elif [[ $( apt-cache show tomcat7 2> /dev/null | egrep "Version: 7" | wc -l ) -gt 0 ]]; then
    echo -e "${BLUE}Found tomcat7 package...${NC}"
    TOMCAT="tomcat7"
else
    echo -e "${RED}Failed. Can't find Tomcat package${NC}" 1>&2
    exit 1
fi

# Install features
echo -e "${BLUE}Installing packages. This might take a few minutes...${NC}"

# Don't prompt during install
export DEBIAN_FRONTEND=noninteractive

# Required packages
apt-get -y install build-essential libcairo2-dev ${JPEGTURBO} ${LIBPNG} libossp-uuid-dev libavcodec-dev libavformat-dev libavutil-dev \
libswscale-dev freerdp2-dev libpango1.0-dev libssh2-1-dev libtelnet-dev libvncserver-dev libpulse-dev libssl-dev \
libvorbis-dev libwebp-dev libwebsockets-dev freerdp2-x11 libtool-bin ghostscript dpkg-dev wget crudini \
nginx php7.3-fpm php7.3-curl php7.3-xml php7.3-zip php-redis redis-server \
${TOMCAT} &>> ${LOG}

# If apt fails to run completely the rest of this isn't going to work...
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed. See ${LOG}${NC}" 1>&2
    exit 1
else
    echo -e "${GREEN}OK${NC}"
fi
echo

# Set SERVER to be the preferred download server from the Apache CDN
SERVER="http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUACVERSION}"
echo -e "${BLUE}Downloading files...${NC}"

# Download Guacamole Server
wget -q --show-progress -O guacamole-server-${GUACVERSION}.tar.gz ${SERVER}/source/guacamole-server-${GUACVERSION}.tar.gz
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to download guacamole-server-${GUACVERSION}.tar.gz" 1>&2
    echo -e "${SERVER}/source/guacamole-server-${GUACVERSION}.tar.gz${NC}"
    exit 1
else
    # Extract Guacamole Files
    tar -xzf guacamole-server-${GUACVERSION}.tar.gz
fi
echo -e "${GREEN}Downloaded guacamole-server-${GUACVERSION}.tar.gz${NC}"

# Download Guacamole Client
wget -q --show-progress -O guacamole-${GUACVERSION}.war ${SERVER}/binary/guacamole-${GUACVERSION}.war
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to download guacamole-${GUACVERSION}.war" 1>&2
    echo -e "${SERVER}/binary/guacamole-${GUACVERSION}.war${NC}"
    exit 1
fi
echo -e "${GREEN}Downloaded guacamole-${GUACVERSION}.war${NC}"


# Make directories
rm -rf /etc/guacamole/lib/
rm -rf /etc/guacamole/extensions/
mkdir -p /etc/guacamole/lib/
mkdir -p /etc/guacamole/extensions/

# Install guacd (Guacamole-server)
cd guacamole-server-${GUACVERSION}/

echo -e "${BLUE}Building Guacamole-Server with GCC $( gcc --version | head -n1 | grep -oP '\)\K.*' | awk '{print $1}' ) ${NC}"

echo -e "${BLUE}Configuring Guacamole-Server. This might take a minute...${NC}"
./configure --with-init-dir=/etc/init.d  --enable-allow-freerdp-snapshots &>> ${LOG}
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed. See ${LOG}${NC}" 1>&2
    exit 1
else
    echo -e "${GREEN}OK${NC}"
fi

echo -e "${BLUE}Running Make on Guacamole-Server. This might take a few minutes...${NC}"
make &>> ${LOG}
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed. See ${LOG}${NC}" 1>&2
    exit 1
else
    echo -e "${GREEN}OK${NC}"
fi

echo -e "${BLUE}Running Make Install on Guacamole-Server...${NC}"
make install &>> ${LOG}
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed. See ${LOG}${NC}" 1>&2
    exit 1
else
    echo -e "${GREEN}OK${NC}"
fi
ldconfig
echo

# Move files to correct locations (guacamole-client & Guacamole authentication extensions)
cd ..
mv -f guacamole-${GUACVERSION}.war /etc/guacamole/guacamole.war

# Create Symbolic Link for Tomcat
ln -sf /etc/guacamole/guacamole.war /var/lib/${TOMCAT}/webapps/


# Configure guacamole.properties
rm -f /etc/guacamole/guacamole.properties
touch /etc/guacamole/guacamole.properties

# Restart Tomcat
echo -e "${BLUE}Restarting Tomcat service & enable at boot...${NC}"
service ${TOMCAT} restart
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed${NC}" 1>&2
    exit 1
else
    echo -e "${GREEN}OK${NC}"
fi
# Start at boot
systemctl enable ${TOMCAT}
echo

# Ensure guacd is started
echo -e "${BLUE}Starting guacd service & enable at boot...${NC}"
service guacd stop 2>/dev/null
service guacd start
systemctl enable guacd
echo

# Deal with ufw and/or iptables

# Check if ufw is a valid command
if [ -x "$( command -v ufw )" ]; then
    # Check if ufw is active (active|inactive)
    if [[ $(ufw status | grep inactive | wc -l) -eq 0 ]]; then
        # Check if 8080 is not already allowed
        if [[ $(ufw status | grep "8080/tcp" | grep "ALLOW" | grep "Anywhere" | wc -l) -eq 0 ]]; then
            # ufw is running, but 8080 is not allowed, add it
            ufw allow 8080/tcp comment 'allow tomcat'
        fi
    fi
fi    

# It's possible that someone is just running pure iptables...

# Check if iptables is a valid running service
systemctl is-active --quiet iptables
if [ $? -eq 0 ]; then
    # Check if 8080 is not already allowed
    # FYI: This same command matches the rule added with ufw (-A ufw-user-input -p tcp -m tcp --dport 22 -j ACCEPT)
    if [[ $(iptables --list-rules | grep -- "-p tcp" | grep -- "--dport 8080" | grep -- "-j ACCEPT" | wc -l) -eq 0 ]]; then
        # ALlow it
        iptables -A INPUT -p tcp --dport 8080 --jump ACCEPT
    fi
fi

# I think there is another service called firewalld that some people could be running instead
# Unless someone opens an issue about it or submits a pull request, I'm going to ignore it for now

# Cleanup
echo -e "${BLUE}Cleanup install files...${NC}"
rm -rf guacamole-*
echo

# Done
echo -e "${BLUE}Installation Complete\n"


