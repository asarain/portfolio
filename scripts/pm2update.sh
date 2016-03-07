#!/bin/sh
TRACE=0
#                  ____                  _       _       
#  _ __  _ __ ___ |___ \ _   _ _ __   __| | __ _| |_ ___ 
# | '_ \| '_ ` _ \  __) | | | | '_ \ / _` |/ _` | __/ _ \
# | |_) | | | | | |/ __/| |_| | |_) | (_| | (_| | ||  __/
# | .__/|_| |_| |_|_____|\__,_| .__/ \__,_|\__,_|\__\___|
# |_|                         |_|                        

# .****************************************************************************,
# | Section: Defines - default to 3.1 kernel                                   |
# `****************************************************************************'
# constants
QRS_SERVER=ftp://qrspno.comcity.com
TESTING_SERVER=http://www.sarain.net/midi9
QRS_SERVER_LOGIN=pmiisync:32MAVMpz

# 3.1 partitions
PARTITION_BOOTSTRAP=/dev/mtd0
PARTITION_UBOOTBIN=/dev/mtd1
PARTITION_UBOOTENV=/dev/mtd2
PARTITION_KERNEL=/dev/mtd3
PARTITION_RFS=/dev/mtd4
PARTITION_UBOOTENV_BACKUP=/dev/mtd5
PARTITION_KERNEL_BACKUP=/dev/mtd6
PARTITION_RFS_BACKUP=/dev/mtd7
PARTITION_DATA=/dev/mtd8

# variables
KERNEL=3.1
APP_VERSION=0.00

# directories
VARDIR=/usr/local/share/midi9
SERIALNUMBER_FILE=$VARDIR/.serialnumber
USBDRIVE=/media/usbdrive
AUDIOCUEDIR=/usr/local/share/sounds/USA

# files
LOGFILE=$VARDIR/update.log
PM2_VERSIONS_MANIFEST=pm2_versions
UPDATER_JSON=/tmp/json_data/updater.json
MUTE_FLAG=/tmp/muteupdate

# .****************************************************************************,
# | Section: Utilities                                                         |
# `****************************************************************************'
write_to_log() 
{
  [ $TRACE -eq 1 ] && echo "$@"
  echo "$(date +%Y%m%d-%T): $@" >> $LOGFILE
}

log_rotate() 
{
  if [ -f $LOGFILE ];then
    tail -n 1000 $LOGFILE > /tmp/tmp.log
    rm $LOGFILE
    mv /tmp/tmp.log $LOGFILE
  fi
}

get_application_version()
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
  LOGFILE=$VARDIR/update.log
  SERIALNUMBER_FILE=$VARDIR/.serialnumber
}

cgi_cmd()
{
  /var/www/cgi-bin/midi9cgi $1
  return $?
}

is_usbdrive_mounted() 
{
  if (mountpoint -q $USBDRIVE/); then
    return 0
  fi
  return 1
}

root_is_nfs() 
{
  if [ $KERNEL == 2.6 ]; then
    grep -qe ':/dev/root.*\(nfs\|smbfs\|ncp\|coda\) .*' /proc/mounts
    [ $? -eq 0 ] && return 0 || return 1
  else
    grep -qe ':/tftpboot/root.*\(nfs\|smbfs\|ncp\|coda\) .*' /proc/mounts
    [ $? -eq 0 ] && return 0 || return 1
  fi
}

# .---------------------------------------------------------,
# | Description: Play audio cue through player app          | 
# | Parameters:  <file>                                     |
# '---------------------------------------------------------'
play_audio_cue() 
{
  if [ ! -f $MUTE_FLAG ];then 
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
  fi
}

# .---------------------------------------------------------,
# | Description: Set partition read-only/read-write         |
# | Parameters:  [ro|rw]                                    |
# `---------------------------------------------------------'
partition_set_mode()
{
  if [ $KERNEL == 3.1 ]; then
    if [ "$1" == "ro" ] || [ "$1" == "rw" ];then
      if (root_is_nfs); then
        PARTITION_RFS=`mount | grep tftpboot | cut -d' ' -f1`
      else
        PARTITION_RFS=$PARTITION_RFS
      fi
      mount -o remount,$1 $PARTITION_RFS /
      return $?
    fi
  else
    return 0
  fi
  return 1
}

folder_free_space()
{
  # NOTE: do not use debugging echo statements
  KB_FREE=0
  DISKFREE=$(df -h $1 | tail -1 | awk '{print $4}')
  INTEGER=$(echo $DISKFREE | cut -d'.' -f1)
  FRACTION=$(echo $DISKFREE | cut -d'.' -f2)
  if (echo $FRACTION | grep -q G); then
   KB_FREE=$(($INTEGER * 1024 * 1024 + ($(echo "$FRACTION" | sed 's/G//')*1024*102)))
  fi
  if (echo $FRACTION | grep -q M); then
    KB_FREE=$(($INTEGER * 1024 + ($(echo "$FRACTION" | sed 's/M//')*102)))
  fi
  echo ${KB_FREE##*|}
}

file_size_bytes()
{
  # NOTE: do not use debugging echo statements
  SIZE_BYTES=0
  if [ -f $1 ];then
    SIZE_BYTES=$(ls -l $1 | awk '{print $5}')
  fi
  echo ${SIZE_BYTES##*|}
}

file_size_kb()
{
  # NOTE: do not use debugging echo statements
  SIZE_KB=$(($(file_size_bytes $1) / 1024))
  echo ${SIZE_KB##*|}
}

# .---------------------------------------------------------,
# | Description: program NAND partition                     |
# | Parameters:  [partition] [binary file]                  |
# `---------------------------------------------------------'
nand_program()
{
  write_to_log "[nand_program]: <$1> <$2>"

  if [ $KERNEL == 2.6 ]; then
    if (flash_eraseall $1);then
      nandwrite --markbad --pad --quiet $1 $2
    fi
  else
    if (flash_erase --jffs2 --quiet $1 0 0);then
      nandwrite --markbad --pad --quiet $1 $2
    fi
  fi
  return $?
}

# .---------------------------------------------------------,
# | Description: Show progress                              |
# | Parameters:  [file] [pid] [approx final size]           |
# `---------------------------------------------------------'
display_progress()
{
  write_to_log "[display_progress]: <$1> <$2> <3>"

  FILE_SIZE_SRC_KB=$3
  FILE_SIZE_KB=0
  COUNT=0
  while [ $COUNT -lt 3600 ]; do
    sleep 1
    if (ps -o pid | grep -q $2);then
      COUNT=$((COUNT + 1))
      if [ -f $1 ];then
        FILE_SIZE_KB=$(file_size_kb $1)   
      fi
      if [ $FILE_SIZE_SRC_KB -gt 0 ];then
        PERCENT=$((FILE_SIZE_KB * 100 / FILE_SIZE_SRC_KB))
        json_write_status_file percent_completed $PERCENT
        echo -ne "\r[$1]: $FILE_SIZE_KB kb of $FILE_SIZE_SRC_KB kb ($PERCENT%) $COUNT seconds"
     fi
      [ $((COUNT % 30)) -eq 0 ] && play_audio_cue update_progress.mp3
    else
      if [ $FILE_SIZE_SRC_KB -gt 0 ];then
        echo -ne '\n'
      fi
      break;
    fi
  done
  return 0
}

# .---------------------------------------------------------,
# | Description: Show progress                              |
# | Parameters:  [file] [pid] [approx final size]           |
# `---------------------------------------------------------'
settings_save_to_usb()
{
  write_to_log "[settings_save_to_usb]: <$1> <$2> <3>"

  rm -f $VARDIR/settings.tar.gz
  mkdir -p /tmp/settings/media
  # make image of settings
  [ -f $VARDIR/.drm ] && cp $VARDIR/.drm /tmp/settings/
  [ -d $VARDIR/.keys ] && cp -r $VARDIR/.keys/ /tmp/settings/
  [ -d $VARDIR/.settings ] && cp -r $VARDIR/.settings/ /tmp/settings/
  [ -d $VARDIR/.velocitymaps ] && cp -r $VARDIR/.velocitymaps/ /tmp/settings/
  [ -d $VARDIR/alarm ] && cp -r $VARDIR/alarm/ /tmp/settings/
  [ -d $VARDIR/config ] && cp -r $VARDIR/config/ /tmp/settings/
  [ -d $MEDIADIR/playlist ] && cp -r $MEDIADIR/playlist/ /tmp/settings/media/
  [ -d $MEDIADIR/recordings ] && cp -r $MEDIADIR/recordings/ /tmp/settings/media/
  [ -f $VARDIR/songs.log ] && cp $VARDIR/songs.log /tmp/settings/
  [ -f $VARDIR/update.log ] && cp $VARDIR/update.log /tmp/settings/
  [ -d $VARDIR/userdata ] && cp -r $VARDIR/userdata/ /tmp/settings/
  [ -f $VARDIR/version.log ] && cp $VARDIR/version.log /tmp/settings/
  [ -f $VARDIR/qc.log ] && cp $VARDIR/version.log /tmp/settings/
  # old settings
  [ -f $VARDIR/midi9.conf ] && cp $VARDIR/midi9.conf /tmp/settings/
  [ -f $VARDIR/solenoid.conf ] && cp $VARDIR/solenoid.conf /tmp/settings/
  [ -f $VARDIR/security.txt ] && cp $VARDIR/security.txt /tmp/settings/
  # create bundle of settings
  cd /tmp/settings/
  tar cf $VARDIR/settings.tar -C /tmp/settings/ .
  gzip $VARDIR/settings.tar
  cp $VARDIR/settings.tar.gz $VARDIR/settings_`(date +"%Y-%m-%d")`.tar.gz
  cd /root/
  rm -r /tmp/settings/
  if (is_usbdrive_mounted);then
    cp $VARDIR/settings.tar.gz $USBDRIVE
  fi
  return 0
}


# .****************************************************************************,
# | Section: server functions                                                  |
# `****************************************************************************'
server_ping()
{
  if ( $(curl -sm 5 -I qrspno.net > /dev/null) > 0 ); then
    return 0
  fi
  return 1
}

# .---------------------------------------------------------,
# | Description: File download from server to current dir   |
# | Parameters:  [local directory] [remote directory]       | 
# |              [filename]                                 | 
# `---------------------------------------------------------'
server_download_file()
{
  write_to_log "[server_download_file]: <$1> <$2> <$3>"
  if (echo $1 | grep -qe $USBDRIVE); then
    if (! is_usbdrive_mounted);then
      write_to_log "[server_download_file]: Destination USB drive not present"
      play_audio_cue fault.mp3
      play_audio_cue usb.mp3
      return 1
    fi
  fi
  [ -d $1 ] || mkdir $1
  cd $1
  curl -u $QRS_SERVER_LOGIN -O $2/$3 2>> /dev/null
  if [ -f $1/$3 ];then
    json_write_status_file qrsftp 1
    if ( grep -qe "404 Not Found" $1/$3 ); then
      write_to_log "[server_download_file]: $1/$3 404 Not Found"
      rm $1/$3
    else 
      return 0
    fi 
  else 
    write_to_log "[server_download_file]: FAIL $1/$3"
    json_write_status_file qrsftp 0
  fi 
  return 1
}

# .---------------------------------------------------------,
# | Description: download contents of directory from QRS    |
# | Parameters:  [source directory] [destination directory] | 
# `---------------------------------------------------------'
server_download_directory()
{
  write_to_log "[server_download_directory]: <$1> <$2>"
  ncftpget -V -R -u pmiisync -p 32MAVMpz qrspno.comcity.com $2 $1
  [ $? -eq 0 ] && return 0 || return 1
}

# .---------------------------------------------------------,
# | Description: upload file to QRS server                  |
# | Parameters:  [file] [remote directory]                  | 
# `---------------------------------------------------------'
server_upload_file()
{
  write_to_log "[server_upload_file]: <$1> <$2>"
  curl --ftp-create-dirs -u $QRS_SERVER_LOGIN -T $1 $2 2> /dev/null
  [ $? -eq 0 ] && return 0 || return 1
}

# .---------------------------------------------------------,
# | Description: upload file to QRS server                  |
# | Parameters:  [local directory] [remote directory]       | 
# `---------------------------------------------------------'
server_upload_directory()
{
  write_to_log "[server_upload_directory]: <$1> <$2>"
  [ -d $1 ] || mkdir $1
  cd $1
  find ./ -type f -exec curl -s -u $QRS_SERVER_LOGIN --ftp-create-dirs -T {} $2{} \; > /dev/null
  [ $? -eq 0 ] && return 0 || return 1
}

# .****************************************************************************,
# | Section: JSON functions                                                    |
# `****************************************************************************'
# .---------------------------------------------------------,
# | Description: Extract JSON value from key                |
# | Usage:       json_get_value <file> <key>                |
# `---------------------------------------------------------'
json_get_value()
{
  # NOTE: do not use debugging echo statements
  if [ -f $1 ]; then
    temp=`cat $1 | sed 's/\\\\\//\//g' | sed 's/[{}]//g' | awk -v k="text" '{n=split($0,a,","); for (i=1; i<=n; i++) print a[i]}' | sed 's/\"\:\"/\|/g' | sed 's/[\,]/ /g' | sed 's/\"//g' | grep -w $2 | cut -d":" -f2 | sed -e 's/^ *//g' -e 's/ *$//g'` 
  else
    temp=
  fi
  echo ${temp##*|}
}

json_update_string()
{
  sed -i 's/\("'$1'":\s\)\"[^"]*/\1\"'$2'/' $UPDATER_JSON
}

json_update_integer()
{
  sed -i 's/\("'$1'":\s\)[0-9]\+/\1'$2'/' $UPDATER_JSON 
}

# .---------------------------------------------------------,
# | Description: Write /tmp/json_data/id.json               | 
# | Parameters:  [serial number] [MAC address]              | 
# '---------------------------------------------------------'
json_write_id_file()
{
  write_to_log "[json_write_id_file]: <$1>:<$2>"
  echo -n "{\"version\": \"000\"," > /tmp/json_data/id.json
  echo -n "\"serial_number\": \"$1\"," >> /tmp/json_data/id.json
  echo -n "\"mac_address\": \"$2\"" >> /tmp/json_data/id.json
  echo "}" >> /tmp/json_data/id.json
}

# .---------------------------------------------------------,
# | Description: Write /tmp/json_data/updater.json          | 
# '---------------------------------------------------------'
json_write_status_file()
{
#  write_to_log "[json_write_status_file]: <$1>:<$2>"

  if [ -f $UPDATER_JSON ];then  
    [ $(file_size_bytes $UPDATER_JSON) -le 0 ] && rm $UPDATER_JSON
  fi
  if [ ! -f $UPDATER_JSON ];then
    write_to_log "[json_write_status_file]: reset"
    echo -n "{\"version\": \"000\"," > $UPDATER_JSON 
    echo -n "\"timestamp\": \"0\"," >> $UPDATER_JSON 
    echo -n "\"qrsftp\": 0," >> $UPDATER_JSON 
    echo -n "\"firmware_patch_file\": \"none\"," >> $UPDATER_JSON 
    echo -n "\"app_patch_file\": \"none\"," >> $UPDATER_JSON 
    echo -n "\"content_patch_file\": \"none\"," >> $UPDATER_JSON 
    echo -n "\"media_patch_file\": \"none\"," >> $UPDATER_JSON 
    echo -n "\"database_patch_file\": \"none\"," >> $UPDATER_JSON 
    echo -n "\"in_progress\": 0," >> $UPDATER_JSON 
    echo -n "\"percent_completed\": 0," >> $UPDATER_JSON 
    echo -n "\"content_download_bytes\": 0," >> $UPDATER_JSON 
    echo -n "\"content_scan_progress\": 0," >> $UPDATER_JSON 
    echo -n "\"content_download_progress\": 0" >> $UPDATER_JSON 
    echo "}" >> $UPDATER_JSON 
  fi
  json_update_string timestamp $(date +%Y-%m-%d_%T)
  # ip address
  # strings
  [ "$1" == "firmware_patch_file" ] && json_update_string $1 $2
  [ "$1" == "app_patch_file" ] && json_update_string $1 $2
  [ "$1" == "content_patch_file" ] && json_update_string $1 $2
  [ "$1" == "database_patch_file" ] && json_update_string $1 $2
  [ "$1" == "media_patch_file" ] && json_update_string $1 $2
  # numbers
  [ "$1" == "qrsftp" ] && json_update_integer $1 $2
  [ "$1" == "content_scan_progress" ] && json_update_integer $1 $2
  [ "$1" == "content_download_bytes" ] && json_update_integer $1 $2
  [ "$1" == "content_download_progress" ] && json_update_integer $1 $2
  [ "$1" == "in_progress" ] && json_update_integer $1 $2
  [ "$1" == "percent_completed" ] && json_update_integer $1 $2
}

# .****************************************************************************,
# | Section: u-boot functions                                                  |
# `****************************************************************************'
uboot_set_variable()
{
  sed -i '/'$1'=/ d' u-boot-env.txt
  echo "$1=$2" >> u-boot-env.txt
}

# .---------------------------------------------------------,
# | Description: set u-boot flags to update from USB drive  |
# | Parameters:                                             |
# `---------------------------------------------------------'
uboot_set_update_flags()
{
  write_to_log "[uboot_set_update_flags]:"
  cd /tmp
  uboot_set_variable pm2_update_firmware 1
  uboot_set_variable pm2_update_recovery 1
  uboot_set_variable pm2_kernel 3
}

# .---------------------------------------------------------,
# | Description: set u-boot ID variables                    |
# | Parameters:  [serial number] [MAC address]              |
# `---------------------------------------------------------'
uboot_set_id()
{
  write_to_log "[uboot_set_id]: <$1> <$2>"
  cd /tmp
  uboot_set_variable serial# $1
  uboot_set_variable ethaddr $2
}

# .---------------------------------------------------------,
# | Description: make u-boot variable file binary in /tmp   |
# | Parameters:  [serial number] [MAC address]              |
# `---------------------------------------------------------'
uboot_make_vars_image()
{
  write_to_log "[uboot_make_vars_image]: <$1> <$2>"
  uboot_set_id $1 $2
  uboot_set_update_flags
  /usr/local/sbin/mkenvimage -s 0x20000 -o uboot-env.bin u-boot-env.txt
}

# .****************************************************************************,
# | Section: update (patch) functions                                          |
# `****************************************************************************'
patch_get_type()
{
  # NOTE: do not use debugging echo statements
  PREFIX=$(echo $1 | cut -d'_' -f1)'_'$(echo $1 | cut -d'_' -f2)
  echo ${PREFIX##*|}
}

# .---------------------------------------------------------,
# | Description: return date string                         |
# | Parameters:  [patch_file]                               |
# | Examples:    pm2_app_2014-01-01.zip                     |
# |              system_patch_2014-01-01.zip                |
# |              pm2_firmware_10.00.zip                     |
# `---------------------------------------------------------'
patch_get_date_string()
{
  # NOTE: do not use debugging echo statements
  tmp=$(echo $1 | cut -d'_' -f3)
  DATESTRING=${tmp%%.zip}
  echo ${DATESTRING##*|}
}

# .---------------------------------------------------------,
# | Description: parse the patch string and get the date    |
# |              version                                    | 
# | Parameters:  [patch_file]                               |
# | Examples:    pm2_app_2014-01-01.zip                     |
# |              system_patch_2014-01-01.zip                |
# |              pm2_firmware_10.00.zip                     |
# `---------------------------------------------------------'
calculate_patch_date()
{
  # NOTE: do not use debugging echo statements
  EPOCHTIME=0
  DATESTRING=$(patch_get_date_string $1)
  if (echo $DATESTRING | grep -qF "."); then
    EPOCHTIME=$(echo "$1" | cut -d'_' -f3)
    EPOCHTIME=$(($(echo "$EPOCHTIME" | cut -d'.' -f1) * 100 + $(echo "$EPOCHTIME" | cut -d'.' -f2)))
  else
    if (echo $1 | grep -q "initial_"); then
      EPOCHTIME=0
    else
      EPOCHTIME=$(date --utc --date "$DATESTRING-00:00" +%s)
    fi
  fi
  echo ${EPOCHTIME##*|}
}

# .---------------------------------------------------------,
# | Description: Check patch list against version.log.      | 
# |              Patch must be newer than version.log entry.|
# | Parameters:  [file]                                     |
# `---------------------------------------------------------'
is_patch_new()
{
#  write_to_log "[is_patch_new]: <$1>"
  IS_NEW_PATCH=0
  NUMBER_OF_ENTRIES=0 

  PATCHTIMESTAMP=$(calculate_patch_date $1)
  PREFIX=$(patch_get_type $1)

  while read entry
  do
    if ( echo $entry | grep -q $PREFIX ) then
      # found patch type entry in version.log
      NUMBER_OF_ENTRIES=$((NUMBER_OF_ENTRIES+1))
      tmp=${entry%%.zip}
      a=$(echo $tmp | cut -d' ' -f2)
      VERSIONTIMESTAMP=$(calculate_patch_date $a)
      # compare date of patch to date of log entry
      if [ $PATCHTIMESTAMP -gt $VERSIONTIMESTAMP ]; then
        IS_NEW_PATCH=1
      else
        IS_NEW_PATCH=0
      fi
    fi
  done < $VARDIR/version.log

  if [ $NUMBER_OF_ENTRIES -eq 0 ]; then
    # there was no entry in the log, so do patch
    IS_NEW_PATCH=1
  fi
  [ $IS_NEW_PATCH -eq 1 ] && return 0 || return 1;
}

# .---------------------------------------------------------,
# | Description: scan directory, create manifest            |
# `---------------------------------------------------------'
patch_scan()
{
   touch /tmp/$PM2_VERSIONS_MANIFEST
   [ -f pm2_firmware_?.??.zip ] && ls -1c pm2_firmware_?.??.zip | tail -n 1 >> /tmp/$PM2_VERSIONS_MANIFEST
   [ -f pm2_firmware_??.??.zip ] && ls -1c pm2_firmware_??.??.zip | tail -n 1 >> /tmp/$PM2_VERSIONS_MANIFEST
   [ -f pm2_app_????-??-??.zip ] && ls -1c pm2_app_????-??-??.zip | tail -n 1 >> /tmp/$PM2_VERSIONS_MANIFEST
   [ -f system_patch_????-??-??.zip ] && ls -1c system_patch_????-??-??.zip | tail -n 1 >> /tmp/$PM2_VERSIONS_MANIFEST
   [ -f media_patch_????-??-??.zip ] && ls -1c media_patch_????-??-??.zip | tail -n 1 >> /tmp/$PM2_VERSIONS_MANIFEST
   [ -f database_patch_????-??-??.zip ] && ls -1c database_patch_????-??-??.zip | tail -n 1 >> /tmp/$PM2_VERSIONS_MANIFEST
  return 0
}

# .---------------------------------------------------------,
# | Description: download patch file manifest               |
# | Parameters:  [serverqrs|servertest|serverusb]           |
# |              [serialnumber]                             |
# `---------------------------------------------------------'
patch_manifest_download()
{
  write_to_log "[patch_manifest_download]: <$1> <$2>"

  [ -f /tmp/$PM2_VERSIONS_MANIFEST ] && rm /tmp/$PM2_VERSIONS_MANIFEST
  [ -f /tmp/pm2_rw_versions ] && rm /tmp/pm2_rw_versions

  case "$1" in
    serverqrs)
      if [ -n "$2" ];then
        server_download_file /tmp $QRS_SERVER/PMIISync/Serial/$2/Patches $PM2_VERSIONS_MANIFEST
      else
        if [ "$(uname -r)" == "2.6.36.1" ];then
          server_download_file /tmp $QRS_SERVER/PMIISync/patches pm2_rw_versions
          cp /tmp/pm2_rw_versions /tmp/$PM2_VERSIONS_MANIFEST
        else
          server_download_file /tmp $QRS_SERVER/PMIISync/patches $PM2_VERSIONS_MANIFEST
        fi
      fi
    ;;
    servertest)
      server_download_file /tmp $TESTING_SERVER/patch $PM2_VERSIONS_MANIFEST
    ;;
    serverusb)
      if (is_usbdrive_mounted);then
        cd /media/usbdrive
        patch_scan
      else
        write_to_log "[patch_manifest_download]: FAIL: USB drive not mounted"
      fi
    ;;
    servertmp)
      cd /tmp
      patch_scan
    ;;
    *)
      echo "[patch_manifest_download]: bad parameter $1"
    ;;
  esac
  [ -f /tmp/$PM2_VERSIONS_MANIFEST ] && return 0 || return 1;
}


# .---------------------------------------------------------,
# | Description: Unzip patch file                           |
# | Parameters:  [filename]                                 |
# `---------------------------------------------------------'
patch_unzip()
{
  write_to_log "[patch_unzip]: <$1>"
  FILE_SIZE_KB=$(file_size_kb /tmp/$1)   
  if [ $(folder_free_space /tmp) -gt $FILE_SIZE_KB ]; then
    [ -d /tmp/update ] && rm -r /tmp/update
    x=$1
    PATCH_PREFIX=${x%%.*}
    # decompress patch
    if [ -f /tmp/$PATCH_PREFIX.zip ]; then
      mkdir /tmp/update
      if (unzip -n /tmp/$PATCH_PREFIX.zip -d /tmp/update/);then
        rm /tmp/$PATCH_PREFIX.zip
        return 0
      fi
    fi
  fi
  return 1
}  

# .---------------------------------------------------------,
# | Description: Execute embedded patch.sh file             |
# | Parameters:  <path to patch.sh>                         |
# `---------------------------------------------------------'
patch_execute_embedded_file()
{
  write_to_log "[patch_execute_embedded_file]: <$1>"
  ERR=1 
  if [ -f $1/patch.sh ];then
    settings_save_to_usb
    cd $1
    chmod 755 patch.sh
    if (partition_set_mode rw);then
      if (./patch.sh);then
        cat patch_id >> $VARDIR/version.log
        write_to_log "[patch_execute_embedded_file] SUCCESS" 
        play_audio_cue update_successful.mp3
        ERR=0 
      else
        play_audio_cue fault.mp3
        write_to_log "[patch_execute_embedded_file] FAIL: $1/patch.sh " 
      fi
      partition_set_mode ro
      json_write_status_file in_progress 0
    fi
  fi
  return $ERR
}

# .---------------------------------------------------------,
# | Description: Create update image in /tmp/image from     |
# |              update in /tmp                             | 
# | Parameters:  [file] [app|content|firmware]              |
# `---------------------------------------------------------'
patch_unpack()
{
  write_to_log "[patch_unpack]: <$1> <$2>"

  if [ $KERNEL == 2.6 ]; then
    play_audio_cue preparing_files.mp3
  else
    play_audio_cue unpacking.mp3
  fi
  [ -d /tmp/update ] && rm -rf /tmp/update
  [ -d /tmp/image ] && rm -rf /tmp/image
  case "$2" in
    app)
      if (patch_unzip $1);then
        if [ $KERNEL == 2.6 ]; then
          return 0
        else 
          # verify patch file integrity
          cd /tmp/update/
          if (md5sum -sc manifest.md5);then
            # decompress payload
            if (gunzip payload.tar.gz);then
              # untar payload
              mkdir /tmp/image
              if (tar -xf payload.tar -C /tmp/image/);then
                rm /tmp/update/payload.tar
                # verify image file integrity
                cd /tmp/image/
                if (md5sum -sc manifest.md5);then
                  # log file difference
                  cd /
                  md5sum -c /tmp/image/manifest.md5 > /tmp/changes.txt
                  grep FAILED /tmp/changes.txt | sed -e 's/: FAILED//' >> $LOGFILE
                  cd /tmp
                  rm /tmp/image/manifest.md5
                  write_to_log "[patch_unpack]: completed"
                  return 0
                fi
              else
                write_to_log "[patch_unpack]: FAIL: manifest check"
              fi
            fi
          fi
        fi
      fi
    ;;
    database)
      if [ $KERNEL == 2.6 ]; then
        if (patch_unzip $1);then
          return 0
        fi
      fi
    ;;
    media)
      if [ $KERNEL == 2.6 ]; then
        if (patch_unzip $1);then
          return 0
        fi
      fi
    ;;
    firmware)
      ERR=1 
      if (is_usbdrive_mounted);then
        FILE_SIZE_KB=$(file_size_kb /media/usbdrive/$1)   
        if [ $(folder_free_space /media/usbdrive) -gt $FILE_SIZE_KB ]; then
          x=$1
          if ($(echo $1 | grep -q ".tar.gz"));then
            PATCH_PREFIX=${x%%.tar.gz}
          else
            PATCH_PREFIX=${x%%.zip}
          fi 

          # decompress patch
          if [ -f /media/usbdrive/$PATCH_PREFIX.zip ] || [ -f /media/usbdrive/$PATCH_PREFIX.tar.gz ]; then
            cd /media/usbdrive
            rm -f installer.tar.gz manifest.md5 patch_id pm2_kernel.img pm2_rfs.img kernel_*
            # unzip pm2_firmware_xxxx-xx-xx.zip file
            if [ -f /media/usbdrive/$PATCH_PREFIX.tar.gz ];then
              # used only for testing 
              rm -f $PATCH_PREFIX.tar
              gunzip $PATCH_PREFIX.tar.gz
              tar -xf $PATCH_PREFIX.tar -C /media/usbdrive
            fi
            if [ -f /media/usbdrive/$PATCH_PREFIX.zip ];then
              unzip -qo /media/usbdrive/$1 -d /media/usbdrive/ &
              pid=$!
              display_progress /media/usbdrive/pm2_rfs.img $pid 44000

            fi
          else
            write_to_log "[patch_unpack]: FAIL: No $PATCH_PREFIX file"
          fi
          cd /media/usbdrive/
          if (md5sum -sc manifest.md5);then
            ERR=0 
          else 
             write_to_log "[patch_unpack]: FAIL: unzip error"
             play_audio_cue fault.mp3
             play_audio_cue one.mp3
          fi
        else
          write_to_log "[patch_unpack]: FAIL: Not enough space on USB drive"
          play_audio_cue fault.mp3
          play_audio_cue two.mp3
        fi
      else
        write_to_log "[patch_unpack]: FAIL: USB drive not mounted"
        echo "[patch_unpack]: FAIL: USB drive not mounted"
        play_audio_cue fault.mp3
        play_audio_cue usb.mp3
      fi
      write_to_log "[patch_unpack]: completed, err=$ERR"
      return $ERR
    ;;
    content)
      # Download library content file
      DOWNLOAD_START=$(date +%s)
      unzip -n /tmp/$1 -d /tmp/ > /dev/null
      if [ -f /tmp/library.lst ];then
        SONGS_IN_LIBRARY=$(cat /tmp/library.lst | wc -l)

        # remove any stray .mp3 solo files
        if ( [ -e /media/sdcard/400101/01.qrs ] && [ -e /media/sdcard/400101/01.mp3 ] || [ -e /media/sdcard/401106/13.qrs ] && [ -e /media/sdcard/401106/13.mp3 ] || [ -e /media/sdcard/801288/15.qrs ] && [ -e /media/sdcard/801288/15.mp3 ]); then
          "$0" prune-solo-files
        fi

        # list songs on SD-card
        cd /media/sdcard
        find ./ -name \*.mp3  > /tmp/songs
        find ./ -name \*.qrs >> /tmp/songs
        find ./ -name \*.mid >> /tmp/songs
        SONGS_ON_SDCARD=$(cat /tmp/songs | wc -l)
        cat /tmp/songs | tr -d '\n' > /tmp/songlist
        SONG_COUNT_DIFFERENCE=$((SONGS_IN_LIBRARY-SONGS_ON_SDCARD))

        # compare the two, make download list
        SONG_COUNT=0
        LAST_PRINT=0
        CONTENT_DOWNLOAD_BYTES=0
        CONTENT_SCAN_PROGRESS=0
        rm -f /tmp/downloadlist
        # library.lst format: 400101/03.qrs	16260
        while read line
        do
          SONG=$(echo $line | awk '{print $1}')
          SONG_COUNT=$((SONG_COUNT+1))
          if !( grep -q $SONG /tmp/songlist ) then
            # song is not on SD card
            SIZE=$(echo $line | awk '{print $2}')
            if [ $SIZE -gt 0 ]; then
              CONTENT_DOWNLOAD_BYTES=$((CONTENT_DOWNLOAD_BYTES+SIZE))
              echo "$SONG $SIZE" >> /tmp/downloadlist
              IS_CONTENT_AVAILABLE=1
            fi
            # check if directory needs to be deleted
            if ((echo $SONG | grep -q "delete")); then
              echo "$SONG 0" >> /tmp/downloadlist
            fi
          fi
    
          # progress
          if [ $SONGS_IN_LIBRARY -gt 0 ]; then
            CONTENT_SCAN_PROGRESS=$((SONG_COUNT*100/SONGS_IN_LIBRARY))
            if [ $CONTENT_SCAN_PROGRESS -gt $LAST_PRINT ]; then
              LAST_PRINT=$((LAST_PRINT+5))
              json_write_status_file content_scan_progress $CONTENT_SCAN_PROGRESS
            fi
          fi
        done < /tmp/library.lst
        END=$(date +%s)
        DIFF=$(($END - $DOWNLOAD_START))
        json_write_status_file content_scan_progress 100
        json_write_status_file content_download_bytes $CONTENT_DOWNLOAD_BYTES
        write_to_log "[patch_available]: $CONTENT_DOWNLOAD_BYTES bytes of content available"
        return 0
      fi
    ;;
    *)
      write_to_log "[patch_unpack]: invald app $2"
    ;;
  esac
  play_audio_cue fault.mp3
  return 1
}

# .****************************************************************************,
# | Section: Content                                                           |
# `****************************************************************************'
# .---------------------------------------------------------,
# | Description: Test if catalog is solo tracks             |
# | Usage:       content_is_solo_track <catalog>            |
# `---------------------------------------------------------'
content_is_solo_track()
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
# | Usage:       content_is_qrs_track <file>                |
# |              <file> format is XXXXXX/XX.XXX             |
# | FIXIT: Make more robust                                 |
# `---------------------------------------------------------'
content_is_qrs_track()
{
  CATALOG=$(echo $1 | cut -d'/' -f1)
  if [ $(echo $CATALOG | egrep '^[0-9]+$') ]; then
    TRACK=$(echo $1 | cut -d'/' -f2 |cut -d'.' -f1)
    if [ $(echo $TRACK | egrep '^[0-9]+$') ]; then
      return 0
    fi
  fi
  return 1
}

# .---------------------------------------------------------,
# | Description:    If a .qrs file is a solo track and      |
# |                 there is a .mp3 file with the same name,| 
# |                 delete it.                              |
# | Parameters:     <song>                                  |
# | Example <song>: 400101/03.qrs                           |
# `---------------------------------------------------------'
content_delete_qrs_mp3_conjugate()
{
  if ( echo $1 | grep -q '.qrs' ) then
    CATALOG=$(echo $1 | cut -d'/' -f1)
    if (content_is_solo_track $CATALOG); then
      # delete AMI file if .qrs replaced it
      SONG=$(basename "$1")
      SONG="${SONG%.*}"
      MP3_CONJUGATE=/media/sdcard/$CATALOG/$SONG.mp3
      if [ -f $MP3_CONJUGATE ]; then
        QRS_FILE="/media/sdcard/$SONG.qrs"
        write_to_log "[content_delete_qrs_mp3_conjugate]: Delete $MP3_CONJUGATE"
        rm -f $MP3_CONJUGATE
        # replace .mp3 entry in playlists with .qrs 
        IFS=$'\n'
        PLAYLIST_MP3_SOLO_FILES=$(grep -irl $MP3_CONJUGATE /media/playlist/)
        for x in $PLAYLIST_MP3_SOLO_FILES ; do
          sed -i 's#'$MP3_CONJUGATE'#'$QRS_FILE'#g' "$x"
        done
      fi
    fi
  fi
}

content_download()
{
  write_to_log "[content_download]: <$1>"
  if [ -f /tmp/downloadlist ]; then
    CONTENT_DOWNLOAD_BYTES=$(json_get_value $UPDATER_JSON content_download_bytes)
    if [ $CONTENT_DOWNLOAD_BYTES -gt 0 ]; then
      BYTES_DOWNLOADED=0
      CONTENT_DOWNLOAD_PROGRESS=0
      if [ "$1" == "servertest" ]; then
        CONTENT_SRC_DIR=$TESTING_SERVER/PMIISync/SDCard
      else
        CONTENT_SRC_DIR=$QRS_SERVER/PMIISync/SDCard
      fi
      # /tmp/downloadlist format: 400101/03.qrs 16260
      while read line
      do
        # download file to proper directory
        DIRECTORY=$(echo $line | cut -d'/' -f1)
        EXPECTED_SIZE=$(echo $line | cut -d' ' -f2)
        FILE=$(echo $line | cut -d'/' -f2)
        FILE=$(echo $FILE | cut -d' ' -f1)
        if ((echo $FILE | grep -q "delete")); then
          echo "**Delete directory /media/sdcard/$DIRECTORY"
          if [ -d /media/sdcard/$DIRECTORY ]; then
            echo "Delete directory /media/sdcard/$DIRECTORY"
          fi
        else
          KB_FREE=$(folder_free_space /media/sdcard)
          if [ $KB_FREE -gt $(($EXPECTED_SIZE/1000)) ]; then
            if (server_download_file /media/sdcard/$DIRECTORY $CONTENT_SRC_DIR/$DIRECTORY $FILE);then
              BYTES_DOWNLOADED=$((BYTES_DOWNLOADED+EXPECTED_SIZE))
              CONTENT_DOWNLOAD_PROGRESS=$((BYTES_DOWNLOADED*100/CONTENT_DOWNLOAD_BYTES))
              write_to_log "$CONTENT_DOWNLOAD_PROGRESS%: $BYTES_DOWNLOADED of $CONTENT_DOWNLOAD_BYTES bytes"
              json_write_status_file content_download_progress $CONTENT_DOWNLOAD_PROGRESS
              content_delete_qrs_mp3_conjugate $DIRECTORY/$FILE
            else
              write_to_log "[content_download]: FAIL: download of $CONTENT_SRC_DIR/$DIRECTORY $FILE to /media/sdcard/$DIRECTORY"
            fi
          else
            write_to_log "[content_download]: FAIL: Not enough disk space.  Folder free space is $KB_FREE kb, file size is $(($EXPECTED_SIZE/1000))"
          fi
        fi
      done < /tmp/downloadlist
      json_write_status_file content_download_progress 100
    fi
  fi
  write_to_log "[content_download]: Completed"
}

content_verify()
{
  write_to_log "[content_verify]:"
  CONTENT_IS_VALID=1
  if [ -f /tmp/downloadlist ]; then
    while read line
    do
      FILE=$(echo $line | cut -d' ' -f1)
      if (content_is_qrs_track $FILE) then
        CATALOG=$(echo $FILE | cut -d'/' -f1)
        LOCATION=/media/sdcard/$(echo $line | cut -d' ' -f1)
        if [ -f $LOCATION ];then
          EXPECTED_SIZE=$(echo $line | cut -d' ' -f2)
          READ_SIZE=$(file_size_bytes $LOCATION)    
          if [ $EXPECTED_SIZE != $READ_SIZE ]; then
            write_to_log "File $LOCATION size is incorrect. Is $READ_SIZE bytes, should be $EXPECTED_SIZE bytes.  Deleting"
            rm -f $LOCATION
            CONTENT_IS_VALID=0
          fi
        else 
          write_to_log "File $LOCATION does not exist"
          CONTENT_IS_VALID=0
        fi
      fi
    done < /tmp/downloadlist
  fi
  write_to_log "[content_verify]: Done"
  [ $CONTENT_IS_VALID -eq 1 ] && return 0 || return 1;
}


# .-----------------------------------------------------,
# | Description: Execute patch if available             |
# | Parameters:  [firmware|app|content|media|database]  |
# |              [serverqrs|servertest|serverusb]       |
# `-----------------------------------------------------'
patch_execute()
{
  write_to_log "[patch_execute]: <$1> <$2>"
  if [ "$(json_get_value $UPDATER_JSON $1_patch_file)" != "none" ];then
    PATCH_FILE=$(json_get_value $UPDATER_JSON $1_patch_file)
    echo "Updating $1 to $PATCH_FILE from $2"
    if [ "$2" == "firmware" ];then
      DST=dstusb
    else
      DST=dsttmp
    fi
    if ("$0" download $PATCH_FILE $2 $DST); then
      if (patch_unpack $PATCH_FILE $1);then
        case "$1" in
          app)
            if (patch_execute_embedded_file /tmp/update);then
              json_write_status_file in_progress 0
              if [ $KERNEL == 2.6 ]; then
                play_audio_cue system.mp3
              else
                play_audio_cue application.mp3
              fi
              play_audio_cue update_successful.mp3
              play_audio_cue powerdown.mp3
              write_to_log "[patch_execute]: ** Reboot to $PATCH_FILE"
              sleep 4
              reboot 
              return 0
            else
              write_to_log "[$0]: FAIL: /media/usbdrive/patch.sh"
            fi
          ;;
          firmware)
            if (patch_execute_embedded_file /media/usbdrive);then
              json_write_status_file in_progress 0
              play_audio_cue firmware.mp3
              play_audio_cue update_successful.mp3
              play_audio_cue powerdown.mp3
              write_to_log "[patch_execute]: ** Reboot to $PATCH_FILE"
              sleep 4
              reboot 
              exit 0
            else
              write_to_log "[$0]: FAIL: /media/usbdrive/patch.sh"
            fi
          ;;
          content)
            if (mountpoint -q /media/sdcard/); then
              content_download $3
              if (content_verify); then
                if [ $KERNEL == 2.6 ]; then
                  cgi_cmd 'playlist=reindex&media=sdcard'
                  cgi_cmd 'playlist=select&type=unlocked'
                else
                  cgi_cmd 'playlist=scan&media=sdcard'
                  cgi_cmd 'playlist=select&file=/media/playlist/unlocked.json'
                fi
                echo $PATCH_FILE >> $VARDIR/version.log
                json_write_status_file in_progress 0
                if [ $KERNEL == 2.6 ]; then
                  play_audio_cue library.mp3
                else
                  play_audio_cue content.mp3
                fi
                play_audio_cue update_successful.mp3
                exit 0
              fi
            else
              write_to_log "[$0]: FAIL: /media/sdcard not mounted"
            fi
          ;;
          database)
            if (patch_execute_embedded_file /tmp/update);then
              json_write_status_file $2_patch_file none
              json_write_status_file in_progress 0
              play_audio_cue database.mp3
              play_audio_cue update_successful.mp3
              exit 0
            fi
          ;;
          media)
            if (patch_execute_embedded_file /tmp/update);then
              json_write_status_file in_progress 0
              play_audio_cue media.mp3
              play_audio_cue update_successful.mp3
              exit 0
            fi
          ;;
          *)
            echo "[$0:$1] unknown target $2"
          ;;
        esac
        json_write_status_file in_progress 0
        play_audio_cue fault.mp3
      else
        write_to_log "[patch_execute]: FAIL - unpack $PATCH_FILE"
      fi 
    else
      write_to_log "[patch_execute]: FAIL - download $PATCH_FILE"
    fi
  else
    write_to_log "[patch_execute]: no update needed"
  fi
  return 1
}

# .****************************************************************************,
# | Section: API                                                               |
# `****************************************************************************'
get_application_version
log_rotate
[ -f $UPDATER_JSON ] || json_write_status_file
case "$1" in
    # .-----------------------------------------------------,
    # | Description: check if updates are available         |
    # | Parameters:  [serverqrs|servertest|serverusb]       |
    # |              [(serialnumber)]                       |
    # `-----------------------------------------------------'
  check-all)
    write_to_log "[$0]: <$1> <$2> <$3>"
    if (patch_manifest_download $2 $3);then
      while read line; do
        if [ ! -z $line ];then
          IS_NEW_PATCH=0
          MANIFEST_PATCH_FILE=$(echo -n $line | tr -d '\r')
          if (is_patch_new $MANIFEST_PATCH_FILE);then
            write_to_log "[check-all]: $MANIFEST_PATCH_FILE is new"
            MANIFEST_PATCH_FILE_PREFIX=$(patch_get_type $MANIFEST_PATCH_FILE)
            case "$MANIFEST_PATCH_FILE_PREFIX" in
              system_patch)
                if [ $KERNEL == 2.6 ]; then
                  json_write_status_file app_patch_file $MANIFEST_PATCH_FILE
                  play_audio_cue system.mp3
                  play_audio_cue update.mp3
                  play_audio_cue available.mp3
                fi
              ;;
              media_patch)
                if [ $KERNEL == 2.6 ]; then
                  json_write_status_file media_patch_file $MANIFEST_PATCH_FILE
                  play_audio_cue media.mp3
                  play_audio_cue update.mp3
                  play_audio_cue available.mp3
                fi  
              ;;
              database_patch)
                if [ $KERNEL == 2.6 ]; then
                  json_write_status_file database_patch_file $MANIFEST_PATCH_FILE
                  play_audio_cue database.mp3
                  play_audio_cue update.mp3
                  play_audio_cue available.mp3
                fi  
              ;;
              pm2_app)
                if [ $KERNEL == 3.1 ]; then
                  json_write_status_file app_patch_file $MANIFEST_PATCH_FILE
                  play_audio_cue application.mp3
                  play_audio_cue update.mp3
                  play_audio_cue available.mp3
                fi
              ;;
              pm2_content)
                json_write_status_file content_patch_file $MANIFEST_PATCH_FILE
                if [ $KERNEL == 2.6 ]; then
                  play_audio_cue libarary.mp3
                else
                  play_audio_cue content.mp3
                fi
                play_audio_cue update.mp3
                play_audio_cue available.mp3
              ;;
              pm2_firmware)
                json_write_status_file firmware_patch_file $MANIFEST_PATCH_FILE
                play_audio_cue firmware.mp3
                play_audio_cue update.mp3
                play_audio_cue available.mp3
              ;;
              *)
                echo "[$0][$1]: Unknown patch prefix $MANIFEST_PATCH_FILE_PREFIX from $MANIFEST_PATCH_FILE"
              ;;
            esac
          else
            write_to_log "[check-all]: $MANIFEST_PATCH_FILE is already installed"
          fi 
        fi 
      done < /tmp/$PM2_VERSIONS_MANIFEST
    fi
  ;;
  check)
    # .-----------------------------------------------------,
    # | Description: check if update is available on server |
    # | Parameters:  [firmware|app|content|media|database]  |
    # |              [serverqrs|servertest|serverusb]       |
    # `-----------------------------------------------------'
    write_to_log "[$0]: <$1> <$2> <$3>"
    IS_PATCH_AVAILABLE=0
    json_write_status_file $2_patch_file none
    "$0" check-all $3
    if [ "$(json_get_value $UPDATER_JSON $2_patch_file)" != "none" ];then
      IS_PATCH_AVAILABLE=1
    fi
    [ $IS_PATCH_AVAILABLE -eq 1 ] && exit 0 || exit 1
  ;;
  download)
    # .-----------------------------------------------------,
    # | Description: download file to local drive           |
    # | Parameters:  [file]                                 |
    # |              [serverqrs|servertest|serverusb]       |
    # |              [dsttmp|dstusb]                        |
    # `-----------------------------------------------------'
    write_to_log "[$0]: <$1> <$2> <$3> <$4>"
    if [ "$2" != "" ];then
      if [ $KERNEL == 2.6 ]; then
        play_audio_cue update_progress.mp3
      else
        play_audio_cue downloading.mp3
      fi
      [ -f /tmp/$2 ] && rm -f /tmp/$2

      PATCH_TYPE=$(patch_get_type $2)
      PATCH_DATE=$(patch_get_date_string $2)

      case "$4" in
        dstusb)
          DST_DIR=/media/usbdrive
        ;;
        dsttmp)
          DST_DIR=/tmp
        ;;
        *)
          write_to_log "[download]: FAIL: invalid destination $4"
          exit 1
        ;;
      esac

      case "$3" in
        serverqrs)
          if [ "$PATCH_TYPE" == "pm2_firmware" ];then
            SRC=$QRS_SERVER/PMIISync/firmware
          else
            SRC=$QRS_SERVER/PMIISync/patches
          fi
          server_download_file $DST_DIR $SRC $2
        ;;
        servertest)
          if [ "$PATCH_TYPE" == "pm2_firmware" ];then
            server_download_file $DST_DIR $TESTING_SERVER/firmware $2 &
            pid=$!
            display_progress $DST_DIR/$2 $pid 44000
          else
            server_download_file $DST_DIR $TESTING_SERVER/patch $2
          fi
        ;;
        serverusb)
          if (is_usbdrive_mounted);then
            cp $USBDRIVE/$2 $DST_DIR
          fi
        ;;
        *)
          write_to_log "[download]: bad server $3"
        ;;
      esac
    else
      write_to_log "[patch_download]: FAIL: no file specified"
    fi
    if [ -f $DST_DIR/$2 ];then
      exit 0
    else
      write_to_log "[download]: FAIL: <$2> <$3> <$4>"
      exit 1
    fi
  ;;
  update)
    # .-----------------------------------------------------,
    # | Description: update code/content patch              |
    # | Parameters:  [firmware|app|content|media|databases] |
    # |              [serverqrs|servertest|serverusb]       |
    # |              [reboot]                               |
    # `-----------------------------------------------------'
    write_to_log "[$0]: <$1> <$2> <$3> <$4>"
    ERR=1 

    if [ "$(json_get_value $UPDATER_JSON in_progress)" == "0" ];then
      if ("$0" check $2 $3); then
        json_write_status_file in_progress 1
        PATCH_FILE=$(json_get_value $UPDATER_JSON $2_patch_file)
        write_to_log "***********************************************************"
        write_to_log "** [$0]: Updating $2 to $PATCH_FILE from $3 **"
        write_to_log "***********************************************************"
        echo "[$0]: Updating $2 to $PATCH_FILE from $3"
        if [ "$2" == "firmware" ];then
          DST=dstusb
        else
          DST=dsttmp
        fi
        if ("$0" download $PATCH_FILE $3 $DST); then
          if (patch_unpack $PATCH_FILE $2);then
            case "$2" in
              app)
                if (patch_execute_embedded_file /tmp/update);then
                  json_write_status_file in_progress 0
                  if [ $KERNEL == 2.6 ]; then
                    play_audio_cue system.mp3
                  else
                    play_audio_cue application.mp3
                  fi
                  play_audio_cue update_successful.mp3
                  play_audio_cue powerdown.mp3
                  write_to_log "[$1]: ** Reboot to $PATCH_FILE"
                  sleep 4
                  reboot 
                  exit 0
                else
                  write_to_log "[$0]: FAIL: /media/usbdrive/patch.sh"
                fi
              ;;
              firmware)
                if (patch_execute_embedded_file /media/usbdrive);then
                  json_write_status_file in_progress 0
                  play_audio_cue firmware.mp3
                  play_audio_cue update_successful.mp3
                  play_audio_cue powerdown.mp3
                  write_to_log "[$1]: ** Reboot to $PATCH_FILE"
                  sleep 4
                  reboot 
                  exit 0
                else
                  write_to_log "[$0]: FAIL: /media/usbdrive/patch.sh"
                fi
              ;;
              content)
                content_download $3
                if (content_verify); then
                  if [ $KERNEL == 2.6 ]; then
                    cgi_cmd 'playlist=reindex&media=sdcard'
                    cgi_cmd 'playlist=select&type=unlocked'
                  else
                    cgi_cmd 'playlist=scan&media=sdcard'
                    cgi_cmd 'playlist=select&file=/media/playlist/unlocked.json'
                  fi
                  echo $PATCH_FILE >> $VARDIR/version.log
                  json_write_status_file in_progress 0
                  if [ $KERNEL == 2.6 ]; then
                    play_audio_cue libarary.mp3
                  else
                    play_audio_cue content.mp3
                  fi
                  play_audio_cue update_successful.mp3
                  exit 0
                fi
              ;;
              database)
                if (patch_execute_embedded_file /tmp/update);then
                  json_write_status_file $2_patch_file none
                  json_write_status_file in_progress 0
                  play_audio_cue database.mp3
                  play_audio_cue update_successful.mp3
                  exit 0
                fi
              ;;
              media)
                if (patch_execute_embedded_file /tmp/update);then
                  json_write_status_file in_progress 0
                  play_audio_cue media.mp3
                  play_audio_cue update_successful.mp3
                  exit 0
                fi
              ;;
              *)
                echo "[$0:$1] unknown target $2"
              ;;
            esac
          fi 
        fi 
        json_write_status_file in_progress 0
        play_audio_cue fault.mp3
      else
        write_to_log "[$0]: $2 is up to date from $3"
        exit 0
      fi 
    else
      write_to_log "[$0] FAIL: update in progress"
    fi 
    exit 1
  ;;
  update-by-serialnumber)
    if [ -f $SERIALNUMBER_FILE ];then
      "$0" check-all serverqrs $(cat $SERIALNUMBER_FILE)
      if [ $KERNEL == 2.6 ]; then
        patch_execute database serverqrs
        patch_execute media serverqrs
        [ $? -eq 0 ] && exit 0
      fi
      patch_execute app serverqrs
      [ $? -eq 0 ] && exit 0
      patch_execute content serverqrs
      [ $? -eq 0 ] && exit 0
#      patch_execute firmware serverqrs
#      [ $? -eq 0 ] && exit 0
    fi
  ;;
  download-remote-dir)
    write_to_log "[$0]: <$1> <$2> <$3>"
    if [ -f $SERIALNUMBER_FILE ];then
      if (server_download_directory PMIISync/Serial/$(cat $SERIALNUMBER_FILE)/$2 $3);then
        write_to_log "[$1]: SUCCESS"
      else
        write_to_log "[$1]: FAIL"
      fi
    fi
  ;;
  upload-remote-dir)
    write_to_log "[$0]: <$1> <$2> <$3>"
    if [ -f $SERIALNUMBER_FILE ];then
      if (server_upload_directory $2 $QRS_SERVER/PMIISync/Serial/$(cat $SERIALNUMBER_FILE)/$3);then
        write_to_log "[$1]: SUCCESS"
      else
        write_to_log "[$1]: FAIL"
      fi
    fi
  ;;

  update-drm-keys)
    [ -d /tmp/Keys ] && rm -r /tmp/Keys
    "$0" download-remote-dir Keys /tmp
     FILES=/tmp/Keys/*
     for i in $FILES
     do
       cgi_cmd "drm=unlock&file=$i"
     done
  ;;
  download-drm)
    write_to_log "[$0]: $1"
    if [ -f $SERIALNUMBER_FILE ];then
      "$0" download-remote-dir keys /tmp
       cp /tmp/keys/* /tmp/
      if (mountpoint -q /media/sdcard/); then
        "$0" download-remote-dir Released /media/sdcard
        "$0" download-remote-dir Unreleased /media/sdcard
        "$0" download-remote-dir sdcard /media
       fi
    fi
  ;;
  upload-state)
    write_to_log "[$0]: $1"
    if [ -f $SERIALNUMBER_FILE ];then
      [ -d /tmp/upload_image ] && rm -r /tmp/upload_image
      mkdir /tmp/upload_image

      mkdir /tmp/upload_image/Logs
      TIMESTAMP=$(date +'%d-%m-%y_%H-%M')
      mkdir /tmp/upload_image/Logs/$TIMESTAMP
      cp $VARDIR/update.log /tmp/upload_image/Logs/$TIMESTAMP/
      cp $VARDIR/version.log /tmp/upload_image/Logs/$TIMESTAMP/
      cp /var/log/messages /tmp/upload_image/Logs/$TIMESTAMP/

      cp -rf /var/www/alarm/ /tmp/upload_image/
      mv /tmp/upload_image/alarm /tmp/upload_image/Alarm
      cp -rfL /var/www/playlist/ /tmp/upload_image/
      mv /tmp/upload_image/playlist /tmp/upload_image/Playlist

      mkdir /tmp/upload_image/Settings
      [ -f $VARDIR/songs.log ] && cp $VARDIR/songs.log /tmp/upload_image/Settings/
      cp $VARDIR/.drm /tmp/upload_image/Settings/
      cp -rf /var/www/userdata/* /tmp/upload_image/Settings/
      cp /tmp/json_data/keyadjust.json /tmp/upload_image/Settings/
      cp /tmp/json_data/pedaladjust.json /tmp/upload_image/Settings/
      cp /tmp/json_data/network.json /tmp/upload_image/Settings/
      cp /tmp/json_data/networkstate.json /tmp/upload_image/Settings/
      cp /tmp/json_data/pnoscan.json /tmp/upload_image/Settings/
      cp /tmp/json_data/general.json /tmp/upload_image/Settings/
      cp /tmp/json_data/midi_velocity.json /tmp/upload_image/Settings/

      if [ $KERNEL == 2.6 ]; then
        /var/www/cgi-bin/midi9cgi "get=version&get=volume&get=solenoids&get=keyboard&get=power_supply&get=midi_settings&get=network_data&get=drm&get=pedal&get=pnoscan&param=basic&get=record&get=usbdrive&get=velocitymap" > /tmp/upload_image/Settings/settings.json
      else
        /var/www/cgi-bin/midi9cgi "getjsondata=system&get=pedal&get=pnoscan&param=basic&get=record&get=usbdrive&get=velocitymap" > /tmp/upload_image/Settings/settings.json
      fi
      ps > /tmp/upload_image/Settings/ps.log
      uptime > /tmp/upload_image/Settings/uptime.log
      free > /tmp/upload_image/Settings/free.log
      top -n 1 > /tmp/upload_image/Settings/top.log
      df > /tmp/upload_image/Settings/df.log
      "$0" upload-remote-dir /tmp/upload_image
      rm -r /tmp/upload_image
    fi
  ;;
  prune-solo-files)
    find /media/sdcard/ -name \*.qrs > /tmp/qrssongs
    sed -i 's/\/media\/sdcard\///' /tmp/qrssongs
    while read line; do
      content_delete_qrs_mp3_conjugate $line
    done < /tmp/qrssongs
  ;;
  on-boot)
#   .-----------------------------------------------------,
#   | Description: Do very little to speed boot time.     |
#   `-----------------------------------------------------'
    write_to_log "-------------------------------------------------------------"
    write_to_log "[$0/$1]: app version $(midi9d -a)"
    if (server_ping);then
      json_write_status_file qrsftp 1
    else
      json_write_status_file qrsftp 0
      write_to_log "[$0/$1]: no FTP connection"
    fi
  ;;
  all)
#   .-----------------------------------------------------,
#   | Description: 3:00 A.M. call.  Do everything. Mute   |
#   |              sound.                                 |
#   `-----------------------------------------------------'
    write_to_log "[$0/$1]:"
    if (server_ping);then
      json_write_status_file qrsftp 1
      touch $MUTE_FLAG
      "$0" update database serverqrs
      "$0" update media serverqrs
      "$0" update app serverqrs
      "$0" update content serverqrs
      "$0" download-drm
      "$0" upload-state
      "$0" update-drm-keys
      "$0" update-by-serialnumber
      rm  $MUTE_FLAG
    else
      json_write_status_file qrsftp 0
      write_to_log "[$0/$1]: no FTP connection"
    fi    
  ;;
  code)
    write_to_log "[$0/$1]:"
    "$0" update database serverqrs
    "$0" update media serverqrs
    "$0" update app serverqrs
    "$0" download-drm
    "$0" upload-state
  ;;
  program-firmware)
    PATCH_FILE=pm2_firmware_$2.zip
    if ("$0" download $PATCH_FILE servertest dstusb);then
      if (patch_unpack $PATCH_FILE firmware);then
        if (patch_execute_embedded_file /media/usbdrive);then
          play_audio_cue powerdown.mp3
          write_to_log "[$1]: ** Reboot to $PATCH_FILE"
          sleep 4
          reboot 
          exit 0
        fi
      fi
    fi
    exit 1
  ;;
  set-id)
    if [ "$2" == "" ];then
      SERIALNUMBER=$(fw_printenv serial# | sed -n 's/^.*=\([^&]*\).*$/\1/p')
      MACID=$(ip link show eth0 | awk '/ether/ {print $2}')
      json_write_id_file $SERIALNUMBER $MACID
      exit 0
    else
      SERIALNUMBER=$2
      MACID=$3
      if [ $KERNEL == 2.6 ]; then
        DEFAULTS_DIR=/root/.defaults/
      else
        DEFAULTS_DIR=/root/defaults/
      fi
      if [ "$SERIALNUMBER" != "" ] && [ "$MACID" != "" ];then
        if [ -f $DEFAULTS_DIR/u-boot-env.txt ];then
          cp $DEFAULTS_DIR/u-boot-env.txt /tmp
          if (uboot_set_id $SERIALNUMBER $MACID);then
            cd /tmp
            if [ $KERNEL == 2.6 ]; then
              uboot_set_variable pm2_kernel 2
              uboot_set_variable kernel_nandaddress "0x200000"
              uboot_set_variable bootcmd "run kernel2boot"
            fi 
            if [ $KERNEL == 3.1 ]; then
              uboot_set_variable pm2_kernel 3
            fi 
            [ -f /tmp/uboot-env.bin ] && rm /tmp/uboot-env.bin
            /usr/local/sbin/mkenvimage -s 0x20000 -o uboot-env.bin u-boot-env.txt
            if [ -f /tmp/uboot-env.bin ];then
              if (nand_program $PARTITION_UBOOTENV /tmp/uboot-env.bin);then
                json_write_id_file $SERIALNUMBER $MACID
                exit 0
              else 
                write_to_log "[$0/$1]: FAIL - NAND write failed"
              fi
            else
              write_to_log "[$0/$1]: FAIL - uboot image"
            fi
          else 
            write_to_log "[$0/$1]: FAIL - set ID failed"
          fi
        else 
          write_to_log "[$0/$1]: FAIL - $DEFAULTS_DIR/u-boot-env.txt does not exist"
        fi
      else
        write_to_log "[$0/$1]: FAIL - invalid input: <$2> <$3>"
      fi
    fi
    exit 1
  ;;
  qc-firmware-upgrade)
    "$0" download-remote-dir Patches /tmp
    if [ -f /tmp/Patches/qc_firmware_update_to_10.00.sh ];then
      echo "WARNING!! Upgrading to firmware 10.00" 
      chmod 755 /tmp/Patches/qc_firmware_update_to_10.00.sh
      /tmp/Patches/qc_firmware_update_to_10.00.sh
    fi
  ;;
  *)
    echo "[$0]: Unknown parameter $1"
    echo "Usage: $0 [update|check] [firmware|app|content|media|database] [servertest|serverqrs|serverusb] [[reboot]]"
    echo "       $0 [download] [file] [servertest|serverqrs] [dsttmp|dstusb]"
    echo "       $0 [program-firmware] [10.00|5.00|3.98|2.51|2.26|1.60]"
    echo "       $0 [all|code|download-drm|upload-state|upload-remote-dir|download-remote-dir]"
    echo "       $0 [set-id] [[serial number] [MAC address]]"
    exit 1
  ;;
esac

exit $?
