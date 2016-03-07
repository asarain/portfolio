#!/bin/sh
# .----------------------------------------------------------------------------,
# | Description: verify firmware update files and setup installer              |
# `----------------------------------------------------------------------------'
# partitions
VARDIR=/usr/local/share/midi9

write_to_log() 
{
  echo "$@"  
  echo "$(date +%Y%m%d-%T): $@" >> $LOGFILE
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
  elif [ -f /usr/sbin/midi9/midi9d ]; then
    KERNEL=2.6
    VARDIR=/root
    if ( grep -q system_patch_2011-07-18.zip $VARDIR/version.log ) then
      APP_VERSION=1.60
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
}

# .----------------------------------------------------------------------------,
# | Section: API                                                               |
# `----------------------------------------------------------------------------'
get_application_version
write_to_log "[$0] install firmware"
if [ -f manifest.md5 ];then
  # verify files
  if (md5sum -cs manifest.md5); then
    if [ -d /tmp ];then
      [ -d /tmp/installer ] || mkdir /tmp/installer
      rm -f /tmp/installer/*
      cp installer.tar.gz /tmp/installer
      cd /tmp/installer
      gunzip installer.tar.gz
      tar xf installer.tar
      if (./install.sh);then
        write_to_log "[$0] SUCCESS: Ready to reboot for firmware update"
        exit 0
      else
        write_to_log "[$0] FAIL: patch failed"
      fi
    else
      write_to_log "[$0] FAIL: no /tmp directory"
    fi
  else
    write_to_log "[$0] FAIL: invalid payload"
  fi
else
  write_to_log "[$0] FAIL: no manifest"
fi
exit 1
