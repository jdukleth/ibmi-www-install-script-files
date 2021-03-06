#!/bin/bash

###################################################
# DISCLAIMER: Read this script before you run it
#    so you aren't surprised by anything it does
###################################################

###################################################
# PREREQUISITES
#    YUM installed on an IBM i (shorturl.at/duz02)
#    BASH terminal (don't use PASE)
###################################################

###################################################
# HOW TO RUN THIS SCRIPT
#  git clone (or unzip) folder onto target server
#  run these commands from BASH (not PASE)
#    `cd /path/to/folder`
#    `chmod +x www-install.sh`
#    `./www-install.sh`
#  if you want to overwrite .nginx/.php/.www-menu
#  folders from prior runs:
#    `./www-install.sh --nuke-files`
###################################################

###################################################
# WHAT NEXT?
#  after this script runs, type `WWW` on a 5250
#  session to control PHP-FPM & Nginx
#  website code:
#    DB2 ext doesn't exist yet (use ODBC for now)
#    Imagick ext doesn't exist yet (use Zebra_Image)
#    you may need to update code for latest PHP
###################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

###################################################
# Yum Repo/Package Installations
###################################################

# make yum-config-manager command available
yum -y install yum-utils

# add PHP-FPM repo (Kevin Adler)
yum-config-manager --add-repo http://repos.zend.com/ibmiphp/

# add additional PHP extensions repo (Calvin Buckley)
yum-config-manager --add-repo http://repo.qseco.fr

# update current repos & packages
yum clean all
yum -y update

# install all other requisite packages for PHP-FPM + Nginx
yum -y install php* nginx unixODBC unixODBC-devel sed-gnu rsync

# move errant php.ini location (remove after IBM releases fix)
PHPINIFROM=/QOpenSys/etc/php.ini
PHPINITO=/QOpenSys/etc/php/
if [ -f "$PHPINIFROM" ]; then
  mv $PHPINIFROM $PHPINITO
fi

###################################################
# Copy Files For Nginx/PHP-FPM/Menu Configuration
###################################################
cd "$SCRIPT_DIR" || exit

# overwrite files from prior runs if user supplies flag
if [[ $* == *--nuke-files* ]]; then
  cp -r .nginx /www/
  cp -r .php /www/
  cp -r .www-menu /www/
else
  rsync -zavh --ignore-existing .nginx /www/
  rsync -zavh --ignore-existing .php /www/
  rsync -zavh --ignore-existing .www-menu /www/
fi

###################################################
# Install IBM i Access ODBC Driver via Yum
###################################################
cd /www/.php/pase-acs/ppc64 || exit
yum -y install ibm-iaccess-*

###################################################
# extract SAVF files for WWW menu
# Move WWW menu files to WWWTOOLS library
# Compile menu and setup menu commands
###################################################

# extract SAVF files to WWWMENU
system 'DLTOBJ OBJ(QGPL/WWWSAVF) OBJTYPE(*FILE)'
system 'CRTSAVF FILE(QGPL/WWWSAVF)'
system "CPYFRMSTMF FROMSTMF('/www/.www-menu/WWWSAVF') TOMBR('/QSYS.LIB/QGPL.LIB/WWWSAVF.FILE') MBROPT(*REPLACE)"
system 'RSTLIB SAVLIB(SATOOLS4) DEV(*SAVF) SAVF(QGPL/WWWSAVF) RSTLIB(WWWMENU)'

# create files that Screen Design Assistant (SDA) would normally generate
system 'CRTDSPF FILE(WWWMENU/WWWMNU1) SRCFILE(WWWMENU/QDDSSRC)'
system 'DLTMSGF MSGF(WWWMENU/WWWMNU1)'
system 'CRTMSGF MSGF(WWWMENU/WWWMNU1)'
system 'CRTMNU MENU(WWWMENU/WWWMNU1) TYPE(*DSPF) DSPF(WWWMENU/*MENU) MSGF(WWWMENU/*MENU)'

# compile CL program to GO to menu
system 'CRTCLPGM PGM(WWWMENU/WWW) SRCFILE(WWWMENU/QCLSRC)'

# create 'WWW' system command
system 'CRTCMD PGM(WWWMENU/WWW) CMD(QGPL/WWW) SRCFILE(WWWMENU/QCMDSRC)'

printf "\n\n"
printf "#########################\n"
printf "#        WWW MENU       #\n"
printf "#########################\n"

NGINX_USER="QTMHHTTP"
read -r -p "Job User for Nginx [$NGINX_USER]: " I_NGINX_USER
I_NGINX_USER=${I_NGINX_USER:-$NGINX_USER}

PHPFPM_USER="QTMHHTTP"
read -r -p "Job User for PHP-FPM [$PHPFPM_USER]: " I_PHPFPM_USER
I_PHPFPM_USER=${I_PHPFPM_USER:-$PHPFPM_USER}

# give directory ownership based on user(s) running processes
chown -R "$I_PHPFPM_USER" /www/.php
chown -R "$I_NGINX_USER" /www/.nginx

# give Nginx/PHP permission on logs
chmod 755 -R /QOpenSys/var/log/nginx/
chmod 755 /www/.nginx/nginx.pid

# tie commands to menu options
system "ADDMSGD MSGID(USR0001) MSGF(WWWMENU/WWWMNU1) MSG('WRKACTJOB SBS(*ALL) JOB(QP0ZSPWP)')"
system "ADDMSGD MSGID(USR0003) MSGF(WWWMENU/WWWMNU1) MSG('SBMJOB CMD(QSH CMD(''/QOpenSys/pkgs/bin/nginx -s reload'')) JOBQ(QUSRNOMAX) ALWMLTTHD(*YES) USER($I_NGINX_USER) INLLIBL(*JOBD)')"
system "ADDMSGD MSGID(USR0004) MSGF(WWWMENU/WWWMNU1) MSG('SBMJOB CMD(QSH CMD(''/QOpenSys/pkgs/bin/nginx'')) JOBQ(QUSRNOMAX) ALWMLTTHD(*YES) USER($I_NGINX_USER) INLLIBL(*JOBD)')"
system "ADDMSGD MSGID(USR0005) MSGF(WWWMENU/WWWMNU1) MSG('SBMJOB CMD(QSH CMD(''/QOpenSys/pkgs/bin/nginx -s stop'')) JOBQ(QUSRNOMAX) USER($I_NGINX_USER) INLLIBL(*JOBD)')"
system "ADDMSGD MSGID(USR0006) MSGF(WWWMENU/WWWMNU1) MSG('wrklnk ''/www/.nginx/logs/error.log''')"
system "ADDMSGD MSGID(USR0007) MSGF(WWWMENU/WWWMNU1) MSG('wrklnk ''/www/.nginx/*''')"
system "ADDMSGD MSGID(USR0008) MSGF(WWWMENU/WWWMNU1) MSG('QSH CMD(''/QOpenSys/pkgs/bin/nginx -t'')')"
system "ADDMSGD MSGID(USR0010) MSGF(WWWMENU/WWWMNU1) MSG('SBMJOB CMD(QSH CMD(''/QOpenSys/pkgs/sbin/php-fpm -R'')) JOBQ(QUSRNOMAX) ALWMLTTHD(*YES) USER($I_PHPFPM_USER) INLLIBL(*JOBD)')"
system "ADDMSGD MSGID(USR0011) MSGF(WWWMENU/WWWMNU1) MSG('QSH CMD(''/QOpenSys/usr/bin/sh -c \"/www/.php/bin/stop-php.sh\"'')')"
system "ADDMSGD MSGID(USR0012) MSGF(WWWMENU/WWWMNU1) MSG('wrklnk ''/www/.php/logs/*''')"
system "ADDMSGD MSGID(USR0013) MSGF(WWWMENU/WWWMNU1) MSG('wrklnk ''/QOpenSys/etc/php/*''')"
system "ADDMSGD MSGID(USR0014) MSGF(WWWMENU/WWWMNU1) MSG('QSH CMD(''/QOpenSys/pkgs/sbin/php-fpm -t'')')"

###################################################
# Nginx: Configuration & Settings
###################################################

CONFFROM=/www/.nginx/nginx.conf
CONFTO=/QOpenSys/etc/nginx/nginx.conf
CONFBU=/QOpenSys/etc/nginx/nginx.conf-bu

# backup original conf if backup doesn't exist from prior runs
if [ -f "$CONFTO" ]; then
  if [ -f "$CONFBU" ]; then
    rm $CONFTO
  else
    mv $CONFTO $CONFBU
  fi
fi

# symlink our .conf file so that we can use `nginx` without -c flag
ln -s $CONFFROM $CONFTO

###################################################
# PHP: Configuration & Settings
###################################################

printf "\n\n"
printf "#########################\n"
printf "#    PHP.INI SETTINGS   #\n"
printf "#    escape / with \\    #\n"
printf "#########################\n"

# php.ini settings
MET="120"
read -r -p "max_execution_time [$MET]: " I_MET
I_MET=${I_MET:-$MET}
sed -i "/max_execution_time =/c\\max_execution_time = $I_MET" /QOpenSys/etc/php/php.ini

MEL="2048M"
read -r -p "memory_limit [$MEL]: " I_MEL
I_MEL=${I_MEL:-$MEL}
sed -i "/memory_limit =/c\\memory_limit = $I_MEL" /QOpenSys/etc/php/php.ini

EL="\/www\/.php\/logs\/php.log"
read -r -p "error_log [$EL]: " I_EL
I_EL=${I_EL:-$EL}
sed -i "s/;error_log = php_errors.log/error_log = $I_EL/g" /QOpenSys/etc/php/php.ini

FPI="1"
read -r -p "cgi.fix_pathinfo [$FPI]: " I_FPI
I_FPI=${I_FPI:-$FPI}
sed -i "/cgi.fix_pathinfo=/c\\cgi.fix_pathinfo=$I_FPI" /QOpenSys/etc/php/php.ini

UMF="8M"
read -r -p "upload_max_filesize [$UMF]: " I_UMF
I_UMF=${I_UMF:-$UMF}
sed -i "/upload_max_filesize =/c\\upload_max_filesize = $I_UMF" /QOpenSys/etc/php/php.ini

MXL="10080"
read -r -p "session.gc_maxlifetime [$MXL]: " I_MXL
I_MXL=${I_MXL:-$MXL}
sed -i "/session.gc_maxlifetime =/c\\session.gc_maxlifetime = $I_MXL" /QOpenSys/etc/php/php.ini

DTZ="America\/Chicago"
read -r -p "date.timezone [$DTZ]: " I_DTZ
I_DTZ=${I_DTZ:-$DTZ}
sed -i "/date.timezone =/c\\date.timezone = $I_DTZ" /QOpenSys/etc/php/php.ini

CCI="\/www\/.php\/ssl\/cacert.pem"
read -r -p "curl.cainfo [$CCI]: " I_CCI
I_CCI=${I_CCI:-$CCI}
sed -i "/curl.cainfo =/c\\curl.cainfo = $I_CCI" /QOpenSys/etc/php/php.ini

OCF="\/www\/.php\/ssl\/cacert.pem"
read -r -p "openssl.cafile [$OCF]: " I_OCF
I_OCF=${I_OCF:-$OCF}
sed -i "/openssl.cafile=/c\\openssl.cafile=$I_OCF" /QOpenSys/etc/php/php.ini

OCP="\/www\/.php\/ssl\/"
read -r -p "openssl.capath [$OCP]: " I_OCP
I_OCP=${I_OCP:-$OCP}
sed -i "/openssl.capath=/c\\openssl.capath=$I_OCP" /QOpenSys/etc/php/php.ini

printf "\n\n"
printf "#########################\n"
printf "# PHP-FPM UPSTREAM PORT #\n"
printf "#########################\n"

# change PHP-FPM upstream port to :9090 (default :9000 conflicts with ZendServer's PHP)
PORT="9090"
read -r -p "PHP-FPM Upstream Port [$PORT]: " I_PORT
I_PORT=${I_PORT:-$PORT}
sed -i "/listen = 127.0.0.1:/c\\listen = 127.0.0.1:$I_PORT" /QOpenSys/etc/php/php-fpm.d/www.conf
sed -i "/server 127.0.0.1:/c\\        server 127.0.0.1:$I_PORT;" /www/.nginx/nginx.conf

# put fastcgi script into place
rsync -zavh /www/.nginx/snippets /QOpenSys/etc/nginx/ > /dev/null 2>&1

###################################################
# ODBC: Configuration & Settings
###################################################

printf "\n\n"
printf "#########################\n"
printf "#     ODBC SETTINGS     #\n"
printf "#########################\n"

# copy ODBC config file into place
cp /www/.php/odbc.ini /QOpenSys/etc/

SRLNBR=$(system 'wrksysval qsrlnbr' | grep QSRLNBR | awk '{print $2}')
DATABASE="S${SRLNBR}"
HOSTNAME=$(hostname)

read -r -p "System Hostname [$HOSTNAME]: " I_HOSTNAME
I_HOSTNAME=${I_HOSTNAME:-$HOSTNAME}
sed -i "s/HOSTNAME_HERE/$I_HOSTNAME/g" /QOpenSys/etc/odbc.ini

read -r -p "ODBC Default Database [$DATABASE]: " I_DATABASE
I_DATABASE=${I_DATABASE:-$DATABASE}
sed -i "s/QSRLNBR_HERE/$I_DATABASE/g" /QOpenSys/etc/odbc.ini

read -r -p "ODBC Username: " I_ODBC_USERNAME
sed -i "s/USERNAME_HERE/$I_ODBC_USERNAME/g" /QOpenSys/etc/odbc.ini

read -r -p "ODBC password: " I_ODBC_PASSWORD
sed -i "s/PASSWORD_HERE/$I_ODBC_PASSWORD/g" /QOpenSys/etc/odbc.ini

printf "\n\n"
printf "############################################################################\n"
printf "#                               SCRIPT DONE!                               #\n"
printf "#                                                                          #\n"
printf "#  * type 'WWW' on 5250 session to control Nginx & PHP-FPM                 #\n"
printf "#  * create Nginx server blocks in /www/.nginx/sites-available and         #\n"
printf "#       symlink to /www/.nginx/sites-enabled to turn them on               #\n"
printf "#  * PHP log stored at /www/.php/logs                                      #\n"
printf "#  * Nginx conf at /www/.nginx/nginx.conf (symlinked to QOpenSys)          #\n"
printf "#  * php.ini, odbc.ini, extensions, etc found in /QOpenSys/etc/            #\n"
printf "############################################################################\n"
