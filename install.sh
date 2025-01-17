#!/usr/bin/env bash

set -Eeuo pipefail

agentPath=
appName=
license=
agentConfigPath=
appRoot=
phpPath=$(command -v php)
swatAgentDirName="swat-agent"

error_exit() {
  echo "$1" 1>&2
  exit 255
}

checkDependencies() {
  for dep in "$@"
  do
    command -v $dep >/dev/null 2>&1 || error_exit "$dep is required"
  done
}

askWriteableDirectory() {
  local promptMessage="$1"
  local defaultValue="$2"
  local path=
  read -e -r -p "$1 (default: $2): " path
  path=${path:-$defaultValue}
  path="$path/$swatAgentDirName"
  path="$(echo $path | sed 's/\/\//\//g')"
  [ -d "$path" ] && error_exit "The directory $path is already exists."
  mkdir -p "$path"
  echo $(cd $path; pwd)
}

askRequiredField() {
  local promptMessage="$1"
  local result=
  while [ -z "$result" ]
  do
    read -r -p "$1: " result
    [ -z "$result" ] && echo "This is required field. Please try again."
  done
  echo $result
}

printSuccess() {
  local msg="$@"
  red=`tput setaf 1`
  green=`tput setaf 2`
  reset=`tput sgr0`
  echo "${green}${msg}${reset}"
}

verifySignature() {
  echo -n "LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQ0lqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FnOEFNSUlDQ2dLQ0FnRUE0M2FBTk1WRXR3eEZBdTd4TE91dQpacG5FTk9pV3Y2aXpLS29HendGRitMTzZXNEpOR3lRS1Jha0MxTXRsU283VnFPWnhUbHZSSFhQZWt6TG5vSHVHCmdmNEZKa3RPUEE2S3d6cjF4WFZ3RVg4MEFYU1JNYTFadzdyOThhenh0ZHdURVh3bU9GUXdDcjYramFOM3ErbUoKbkRlUWYzMThsclk0NVJxWHV1R294QzBhbWVoakRnTGxJUSs1d1kxR1NtRGRiaDFJOWZqMENVNkNzaFpsOXFtdgorelhjWGh4dlhmTUU4MUZsVUN1elRydHJFb1Bsc3dtVHN3ODNVY1lGNTFUak8zWWVlRno3RFRhRUhMUVVhUlBKClJtVzdxWE9kTGdRdGxIV0t3V2ppMFlrM0d0Ylc3NVBMQ2pGdEQzNytkVDFpTEtzYjFyR0VUYm42V3I0Nno4Z24KY1Q4cVFhS3pYRThoWjJPSDhSWjN1aFVpRHhZQUszdmdsYXJSdUFacmVYMVE2ZHdwYW9ZcERKa29XOXNjNXlkWApBTkJsYnBjVXhiYkpaWThLS0lRSURnTFdOckw3SVNxK2FnYlRXektFZEl0Ni9EZm1YUnJlUmlMbDlQMldvOFRyCnFxaHNHRlZoRHZlMFN6MjYyOU55amgwelloSmRUWXRpdldxbGl6VTdWbXBob1NrVnNqTGtwQXBiUUNtVm9vNkgKakJmdU1sY1JPeWI4TXJCMXZTNDJRU1MrNktkMytwR3JyVnh0akNWaWwyekhSSTRMRGwrVzUwR1B6LzFkeEw2TgprZktZWjVhNUdCZm00aUNlaWVNa3lBT2lKTkxNa1cvcTdwM200ejdUQjJnbWtldm1aU3Z5MnVMNGJLYlRoYXRlCm9sdlpFd253WWRxaktkcVkrOVM1UlNVQ0F3RUFBUT09Ci0tLS0tRU5EIFBVQkxJQyBLRVktLS0tLQ==" | base64 -d > $agentPath/release.pub

  cd $agentPath;
  openssl dgst -sha256 -verify release.pub -signature launcher.sha256 launcher.checksum || error_exit "Signature verification is failed"
  cd -
}

checkDependencies "php" "wget" "awk" "nice" "grep" "openssl"
# /usr/local/swat-agent see: https://refspecs.linuxfoundation.org/FHS_2.3/fhs-2.3.html
agentPath=$(askWriteableDirectory "Where to download Site Wide Analysis Agent" "/usr/local/")
echo "Site Wide Analysis Agent will be installed into $agentPath"
appName=$(askRequiredField "Enter agent credentials App Name (Provided by Adobe Commerce)")
license=$(askRequiredField "Enter agent credentials License Key (Provided by Adobe Commerce)")

# Get Adobe Commerce Application Root
while [[ -z "$appRoot" ]] || [[ -z "$(ls -A $appRoot)" ]] || [[ -z "$(ls -A $appRoot/app/etc)" ]] || [[ ! -f "$appRoot/app/etc/env.php" ]]
do
  read -e -r -p "Enter Adobe Commerce Application Root (default:/var/www/html): " appRoot
  appRoot=${appRoot:-/var/www/html}
  if [[ ! -f "$appRoot/app/etc/env.php" ]]; then
    echo "The directory $appRoot is not the Adobe Commerce Application Root"
    continue
  fi
  appRoot="$(cd $appRoot; pwd)"
done

appConfigVarDBName=$($phpPath -r "\$config = require '$appRoot/app/etc/env.php'; echo(\$config['db']['connection']['default']['dbname']);")
appConfigVarDBUser=$($phpPath -r "\$config = require '$appRoot/app/etc/env.php'; echo(\$config['db']['connection']['default']['username']);")
appConfigVarDBPass=$($phpPath -r "\$config = require '$appRoot/app/etc/env.php'; echo(\$config['db']['connection']['default']['password']);")
appConfigVarDBHost=$($phpPath -r "\$config = require '$appRoot/app/etc/env.php'; \$host = \$config['db']['connection']['default']['host']; echo(strpos(\$host,':')!==false?reset(explode(':', \$host)):\$host);")
appConfigVarDBPort=$($phpPath -r "\$config = require '$appRoot/app/etc/env.php'; \$host = \$config['db']['connection']['default']['host']; echo(strpos(\$host,':')!==false?end(explode(':', \$host)):'3306');")

[ -d "$agentPath" ] && [ ! -z "$(ls -A "$agentPath")" ] && error_exit "Site Wide Analysis Tool Agent Directory $agentPath is not empty. Review and remove it <rm -r $agentPath>"

set -x
wget -qP "$agentPath" https://updater.swat.magento.com/launcher/launcher.linux-amd64.tar.gz
tar -xf "$agentPath/launcher.linux-amd64.tar.gz" -C "$agentPath"
verifySignature

echo "SWAT_AGENT_APP_NAME=$appName" > "$agentPath/swat-agent.env"
echo "SWAT_AGENT_LICENSE_KEY=$license" >> "$agentPath/swat-agent.env"
echo "SWAT_AGENT_APPLICATION_PHP_PATH=$phpPath" >> "$agentPath/swat-agent.env"
echo "SWAT_AGENT_APPLICATION_MAGENTO_PATH=$appRoot" >> "$agentPath/swat-agent.env"
echo "SWAT_AGENT_APPLICATION_DB_USER=$appConfigVarDBUser" >> "$agentPath/swat-agent.env"
echo "SWAT_AGENT_APPLICATION_DB_PASSWORD=$appConfigVarDBPass" >> "$agentPath/swat-agent.env"
echo "SWAT_AGENT_APPLICATION_DB_HOST=$appConfigVarDBHost" >> "$agentPath/swat-agent.env"
echo "SWAT_AGENT_APPLICATION_DB_PORT=$appConfigVarDBPort" >> "$agentPath/swat-agent.env"
echo "SWAT_AGENT_APPLICATION_DB_NAME=$appConfigVarDBName" >> "$agentPath/swat-agent.env"
echo "SWAT_AGENT_APPLICATION_CHECK_REGISTRY_PATH=$agentPath/tmp" >> "$agentPath/swat-agent.env"
echo "SWAT_AGENT_BACKEND_HOST=check.swat.magento.com:443" >> "$agentPath/swat-agent.env"
echo "SWAT_AGENT_LOGIN_BACKEND_HOST=login.swat.magento.com:443" >> "$agentPath/swat-agent.env"
echo "SWAT_AGENT_RUN_CHECKS_ON_START=1" >> "$agentPath/swat-agent.env"
echo "SWAT_AGENT_LOG_LEVEL=error" >> "$agentPath/swat-agent.env"
set +x

printSuccess "Site Wide Analysis Tool Agent is successfully installed $agentPath"
echo "SWAT agent configuration file created $agentPath/swat-agent.env"
echo "SWAT agent is copied $agentPath/scheduler"
echo "Optional: you can add symlink ln -s $agentPath/scheduler /usr/local/bin/scheduler"
echo "Next step: Configure daemon or crontab. If you have a root access please follow the installation guide and configure a daemon. If you do not have a root access you can configure cronjob as below: "
echo "* * * * * flock -n /tmp/swat-agent.lockfile -c 'set +o allexport; source $agentPath/swat-agent.env; set -o allexport; $agentPath/scheduler' >> /path/to/swat-agent/errors.log 2>&1"
