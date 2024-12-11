# Pre-Install Dependencies
apt-get update && apt-get install -y sudo openssl

## optional settings
MISP_PATH='/var/www/MISP'
APACHE_USER='www-data'
#GNUPGHOME='/var/www/MISP/.gnupg'

## GPG
GPG_EMAIL_ADDRESS="admin@admin.test"
GPG_PASSPHRASE="$(openssl rand -hex 32)"

# Some helper functions shamelessly copied from @da667's automisp install script.

logfile=/var/log/misp_install.log
mkfifo ${logfile}.pipe
tee < ${logfile}.pipe $logfile &
exec &> ${logfile}.pipe
rm ${logfile}.pipe

function install_packages ()
{
    install_params=("$@")
    for i in "${install_params[@]}";
    do
        sudo apt-get install -y "$i" &>> $logfile
        error_check "$i installation"
    done
}


function error_check
{
    if [ $? -eq 0 ]; then
        print_ok "$1 successfully completed."
    else
        print_error "$1 failed. Please check $logfile for more details."
    exit 1
    fi
}

function error_check_soft
{
    if [ $? -eq 0 ]; then
        print_ok "$1 successfully completed."
    else
        print_error "$1 failed. Please check $logfile for more details. This is not a blocking failure though, proceeding..."
    fi
}

function print_status ()
{
    echo -e "\x1B[01;34m[STATUS]\x1B[0m $1"
}

function print_ok ()
{
    echo -e "\x1B[01;32m[OK]\x1B[0m $1"
}

function print_error ()
{
    echo -e "\x1B[01;31m[ERROR]\x1B[0m $1"
}

function print_notification ()
{
	echo -e "\x1B[01;33m[NOTICE]\x1B[0m $1"
}

function os_version_check ()
{
    # Check if we're on Ubuntu 24.04 as expected:
    UBUNTU_VERSION=$(lsb_release -a | grep Release | grep -oP '[\d-]+.[\d-]+$')
    
    echo "Ubuntu version: $UBUNTU_VERSION"
    if [[ "$UBUNTU_VERSION" != "24.04" ]]; then
        print_error "This upgrade tool expects you to be running Ubuntu 24.04. If you are on a prior upgrade of Ubuntu, please make sure that you upgrade your distribution first, then execute this script again."
        exit 1
    fi
}

print_status "Updating base system..."
sudo apt-get update &>> $logfile
sudo apt-get upgrade -y &>> $logfile
error_check "Base system update"

print_status "Installing test dependencies (gpg curl git ca-certificates) ..."
declare -a packages=( gpg curl git ca-certificates );
install_packages ${packages[@]}
error_check "Test dependencies installation"

echo "GPG version"
sudo -u ${APACHE_USER} gpg --version

#sudo git config --global http.sslCAinfo /usr/local/share/ca-certificates/Zscaler.pem &>> $logfile

print_status "Cloning MISP"
sudo git clone https://github.com/MISP/MISP.git ${MISP_PATH}  &>> $logfile
error_check "MISP clonining"


# Create the MISP_PATH directory, if it does not exist
# This is done for us in the real script via git
mkdir -pv ${MISP_PATH}/app/webroot
sudo chown -R ${APACHE_USER}:${APACHE_USER} ${MISP_PATH} &>> $logfile
mkdir -pv ${GNUPGHOME}
sudo chown -R ${APACHE_USER}:${APACHE_USER} ${GNUPGHOME} &>> $logfile
sudo -u ${APACHE_USER} chmod 700 ${GNUPGHOME} &>> $logfile


print_status "Generating PGP key"

cat >/tmp/gpg-config <<EOF
%echo Generating OpenPGP key
Key-Type: ECDSA
Key-Curve: nistp256
Key-Usage: sign
Passphrase: ${GPG_PASSPHRASE}
Name-Email: ${GPG_EMAIL_ADDRESS}
Expire-Date: 0
%commit
%echo done
EOF

# The email address should match the one set in the config.php
# set in the configuration menu in the administration menu configuration file

#sudo -u ${APACHE_USER} gpg-agent --daemon -v --debug-all --homedir $GNUPGHOME

sudo -u ${APACHE_USER} gpg --verbose --debug-all --homedir ${MISP_PATH}/.gnupg --batch --generate-key /tmp/gpg-config  &>> $logfile
error_check "PGP key generation"

ls -alF ${MISP_PATH}/.gnupg

sudo -u ${APACHE_USER} gpg --homedir ${MISP_PATH}/.gnupg --list-keys &>> $logfile
# Export the public key to the webroot
sudo -u ${APACHE_USER} gpg --homedir ${MISP_PATH}/.gnupg --export --armor ${GPG_EMAIL_ADDRESS} | sudo -u ${APACHE_USER} tee ${MISP_PATH}/app/webroot/gpg.asc  &>> $logfile
error_check "PGP key export"

cat ${MISP_PATH}/app/webroot/gpg.asc

print_status "Try to keep container from exiting"
sleep infinity