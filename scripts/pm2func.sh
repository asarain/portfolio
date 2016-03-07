#  ____  __  __ ____    _               _        __                      
# |  _ \|  \/  |___ \  | |__   __ _ ___| |__    / _|_   _ _ __   ___ ___ 
# | |_) | |\/| | __) | | '_ \ / _` / __| '_ \  | |_| | | | '_ \ / __/ __|
# |  __/| |  | |/ __/  | |_) | (_| \__ \ | | | |  _| |_| | | | | (__\__ \
# |_|   |_|  |_|_____| |_.__/ \__,_|___/_| |_| |_|  \__,_|_| |_|\___|___/

# .****************************************************************************,
# | Section: Defines - default to 3.1 kernel                                   |
# `****************************************************************************'
# variables
KERNEL=3.1
APP_VERSION=0.00

# directories
VARDIR=/usr/local/share/midi9
SERIALNUMBER_FILE=$VARDIR/.serialnumber
USBDRIVE=/media/usbdrive
AUDIOCUEDIR=/usr/local/share/sounds/USA

# files
CGIRESULTFILE="/tmp/result.cgi"
AUDIOCUEDIR=/usr/local/share/audio_cues/USA
UPDATER_JSON=/tmp/json_data/updater.json

# .****************************************************************************,
# | Section: Misc                                                              |
# `****************************************************************************'
pm2func_get_application_version()
{
  if [ -f /usr/local/bin/midi9d ]; then
    KERNEL=3.1
    APP_VERSION=$(/usr/local/bin/midi9d --appversion 2>&1)
    VARDIR=/usr/local/share/midi9
  elif [ -f /usr/bin/midi9d ]; then
    KERNEL=2.6
    APP_VERSION=$(/usr/bin/midi9d --appversion 2>&1)
    VARDIR=/root
    AUDIOCUEDIR=/media/sounds/USA
  elif [ -f /usr/sbin/midi9/midi9d ]; then
    KERNEL=2.6
    VARDIR=/root
    AUDIOCUEDIR=/media/sounds/USA
    if ( grep -q system_patch_2011-07-18.zip $VARDIR/version.log ) then
      APP_VERSION=1.60
      USBDRIVE=/media/thumb
    elif ( grep -q system_patch_2011-11-09.zip $VARDIR/version.log ); then
      APP_VERSION=2.26
    elif ( grep -q system_patch_2012-01-18.zip $VARDIR/version.log ); then
      APP_VERSION=2.51
    else
      # < 3.79
      APP_VERSION=3.78
    fi
  fi
  SERIALNUMBER_FILE=$VARDIR/.serialnumber
}

pm2func_kernel_version()
{
  echo ${KERNEL##*|}
}

pm2func_app_version()
{
  echo ${APP_VERSION##*|}
}

pm2func_serial_number()
{
  tmp=$(cat $SERIALNUMBER_FILE)
  echo ${tmp##*|}
}

pm2func_usb_drive()
{
  echo ${USBDRIVE##*|}
}

pm2func_vardir()
{
  echo ${VARDIR##*|}
}

# .---------------------------------------------------------,
# | Description: Play audio cue through player app          | 
# | Parameters:  <file>                                     |
# '---------------------------------------------------------'
pm2func_play_audio_cue() 
{
  if [ "$(pidof midi9player)" ];then
    FILE_NAME_LEN=$(printf "%02x" "`expr length $1`")
    echo -ne '\xf0\x09\x00\x00\x05\x02' > /tmp/midi9playerfifo
    echo -ne "\x$FILE_NAME_LEN" >> /tmp/midi9playerfifo
    echo -n $1 >> /tmp/midi9playerfifo
    echo -ne '\xf7' >> /tmp/midi9playerfifo
  else
    if [ -f /usr/bin/madplay ]; then
      if [ -f $AUDIOCUEDIR/$1 ]; then
        amixer -q set DAC1 220
        madplay -Q -owave:- $AUDIOCUEDIR/$@ | aplay -q 1> /dev/null
      fi
    fi
  fi
}

# .---------------------------------------------------------,
# | Description: Wait for file to be created                |
# | Parameters:  <file>                                     |
# `---------------------------------------------------------'
pm2func_wait_for_file()
{
  TIMEOUT=10
  while [ ! -f $1 ]; do
    TIMEOUT=$(( $TIMEOUT - 1 ))
    [ $TIMEOUT -lt 0 ] && return 1
    sleep 1
  done
  return 0
}

pm2func_is_usbdrive_mounted() 
{
  if (mountpoint -q $USBDRIVE/); then
    return 0
  fi
  return 1
}

pm2func_file_size_bytes()
{
  # NOTE: do not use debugging echo statements
  SIZE_BYTES=0
  if [ -f $1 ];then
    SIZE_BYTES=$(ls -l $1 | awk '{print $5}')
  fi
  echo ${SIZE_BYTES##*|}
}

pm2func_root_is_nfs() 
{
  if [ "$(uname -r)" == "3.1.6" ]; then
    grep -qe ':/tftpboot/root.*\(nfs\|smbfs\|ncp\|coda\) .*' /proc/mounts
    [ $? -eq 0 ] && return 0 || return 1
  else
    grep -qe ':/dev/root.*\(nfs\|smbfs\|ncp\|coda\) .*' /proc/mounts
    [ $? -eq 0 ] && return 0 || return 1
  fi
}

# .---------------------------------------------------------,
# | Description: Set partition read-only/read-write         |
# | Parameters:  [ro|rw]                                    |
# `---------------------------------------------------------'
pm2func_partition_set_mode()
{
  if [ "$(uname -r)" == "3.1.6" ]; then
    if [ "$1" == "ro" ] || [ "$1" == "rw" ];then
      if (pm2func_root_is_nfs); then
        PARTITION_RFS=`mount | grep tftpboot | cut -d' ' -f1`
      else
        PARTITION_RFS=/dev/mtd4
      fi
      mount -o remount,$1 $PARTITION_RFS /
      return $?
    fi
  fi
  return 1
}

# .---------------------------------------------------------,
# | Description: check if QRS FTP site is available         |
# | Parameters:  [none]                                     |
# `---------------------------------------------------------'
pm2func_is_qrs_server_available()
{
  ping -q -c 1 -W 3 qrspno.comcity.com > /dev/null
  return $?
}

# .****************************************************************************,
# | Section: File type detection                                               |
# `****************************************************************************'
# .---------------------------------------------------------,
# | Description: Test if catalog is solo tracks             |
# | Usage:       is_solo_track <catalog>                    |
# `---------------------------------------------------------'
pm2func_is_solo_track()
{
  if [ "$1" -eq "$1" ] 2>/dev/null; then
    ALBUM_PREFIX=$(($1/10000))
    [ $ALBUM_PREFIX -eq 40 ] && return 0
    [ $ALBUM_PREFIX -eq 80 ] && return 0
    [ $ALBUM_PREFIX -eq 84 ] && return 0
  fi
  return 1
}

# .---------------------------------------------------------,
# | Description: Test if file is QRS library content        |
# | Usage:       is_qrs_content <file>                      |
# |              <file> format is XXXXXX/XX.XXX             |
# | FIXIT: Make more robust                                 |
# `---------------------------------------------------------'
pm2func_is_qrs_content()
{
  CATALOG=$(echo $1 | cut -d'/' -f1)
  if [ "$CATALOG" -eq "$CATALOG" ] 2>/dev/null; then
    TRACK=$(echo $1 | cut -d'/' -f2 |cut -d'.' -f1)
    if [ "$TRACK" -eq "$TRACK" ] 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

# .****************************************************************************,
# | Section: JSON functions                                                    |
# `****************************************************************************'
# .---------------------------------------------------------,
# | Description: Extract JSON value from key                |
# | Parameters: [file] [key]                                |
# `---------------------------------------------------------'
pm2func_json_get_value()
{
  # DO NOT USE ECHO FOR DEBUG
  if [ -f $1 ];then
    temp=`cat $1 | sed 's/\\\\\//\//g' | sed 's/[{}]//g' | awk -v k="text" '{n=split($0,a,","); for (i=1; i<=n; i++) print a[i]}' | sed 's/\"\:\"/\|/g' | sed 's/[\,]/ /g' | sed 's/\"//g' | grep -w $2 | cut -d":" -f2 | sed -e 's/^ *//g' -e 's/ *$//g'` 
  else
    temp=
  fi
  echo ${temp##*|}
}

# .---------------------------------------------------------,
# | Description: replace specified valued                   | 
# | Parameters: [file] [key] [value]                        |
# '---------------------------------------------------------'
pm2func_json_update_param()
{
#  echo "[pm2func_json_update_param]: <$1> <$2> <$3>"
  if [ -f $1 ];then  
    CURR=$(pm2func_json_get_value $1 $2)
    OLD="\"$2\": \"$CURR"
    NEW="\"$2\": \"$3"
    sed -i "s/$OLD/$NEW/" $1
    return $?
  fi
  return 1
}

# .---------------------------------------------------------,
# | Description: replace specified valued                   | 
# | Parameters: [file] [key] [value]                        |
# '---------------------------------------------------------'
pm2func_json_update_string()
{
  if [ -f $1 ];then  
    sed -i 's/\("'$2'":\s\)\"[^"]*/\1\"'$3'/' $1
    return $?
  fi
  return 1
}

# .---------------------------------------------------------,
# | Description: replace specified valued                   | 
# | Parameters: [file] [key] [value]                        |
# '---------------------------------------------------------'
pm2func_json_update_integer()
{
  if [ -f $QC_JSON ];then  
    sed -i 's/\("'$2'":\s\)[0-9]\+/\1'$3'/' $1 
    return $?
  fi
  return 1
}

# .****************************************************************************,
# | Section: CGI                                                               |
# `****************************************************************************'
# .---------------------------------------------------------,
# | Description: send command to CGI                        |
# | Parameters: [args]                                      |
# `---------------------------------------------------------'
pm2func_cgi_cmd()
{
  /var/www/cgi-bin/midi9cgi $1
  return $?
}

# .---------------------------------------------------------,
# | Description: Get value from CGI                         |
# | Parameters: [cmd] [key]                                 |
# `---------------------------------------------------------'
pm2func_cgi_get()
{
  # DO NOT USE ECHO FOR DEBUG
  /var/www/cgi-bin/midi9cgi "get=$1" > $CGIRESULTFILE
  pm2func_json_get_value $CGIRESULTFILE $2
}

# .---------------------------------------------------------,
# | Description: Get value from CGI                         |
# | Parameters: [cmd] [key]                                 |
# `---------------------------------------------------------'
pm2func_cgi_json_get()
{
  # DO NOT USE ECHO FOR DEBUG
  /var/www/cgi-bin/midi9cgi "getjsondata=$1" > $CGIRESULTFILE
  pm2func_json_get_value $CGIRESULTFILE $2
}

# .---------------------------------------------------------,
# | Description: Wait for CGI command response. Commands    |
# |              should return value in less time than the  |
# |              timeout.                                   |
# | Parameters: [cmd] [key] [state]                         |
# `---------------------------------------------------------'
pm2func_cgi_wait_for_cmd()
{
#  echo "[pm2func_cgi_wait_for_state]: <$1> <$2> <$3>"
  TIMEOUT=3
  while [ "$(pm2func_cgi_json_get $1 $2)" != "$3" ]; do
    TIMEOUT=$(( $TIMEOUT - 1 ))
    [ $TIMEOUT -lt 0 ] && return 1
    sleep 1 
  done
  return 0
}


# .---------------------------------------------------------,
# | Description: Wait for state to change to desired value  |
# | Parameters: [cmd] [key] [state]                         |
# `---------------------------------------------------------'
pm2func_cgi_wait_for_state()
{
#  echo "[pm2func_cgi_wait_for_state]: <$1> <$2> <$3>"
  TIMEOUT=20
  while [ "$(pm2func_cgi_json_get $1 $2)" != "$3" ]; do
    TIMEOUT=$(( $TIMEOUT - 1 ))
    [ $TIMEOUT -lt 0 ] && return 1
    sleep 1 
  done
  return 0
}

# .---------------------------------------------------------,
# | Description: Wait for param to change from specified v  |
# | Parameters: [cmd] [key] [state]                         |
# `---------------------------------------------------------'
pm2func_cgi_wait_for_change()
{
#  echo "[pm2func_cgi_wait_for_change]: <$1> <$2> <$3>"
  TIMEOUT=20
  while [ "$(pm2func_cgi_json_get $1 $2)" == "$3" ]; do
    TIMEOUT=$(( $TIMEOUT - 1 ))
    [ $TIMEOUT -lt 0 ] && return 1
    sleep 1 
  done
  return 0
}

