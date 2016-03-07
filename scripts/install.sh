#!/bin/sh
# .----------------------------------------------------------------------------,
# | Description: Update bootstrap and u-boot to program a kernel and RFS image.|
# |              Assumption: firmare update file has unpacked the images to    |
# |              the USB drive.                                                |
# |              Assumption: the installer has been unpacked to a directory    |
# |              and this script is run in that directory                      |
# `----------------------------------------------------------------------------'
# partitions
PARTITION_BOOTSTRAP=/dev/mtd0
PARTITION_UBOOTBIN=/dev/mtd1
PARTITION_UBOOTENV=/dev/mtd2

VARDIR=/usr/local/share/midi9
SERIALNUMBER_FILE=$VARDIR/.serialnumber
LOGFILE=$VARDIR/update.log
MKENVBIN=mkenvimage

BOOTSTRAP_BIN=nandflash_at91sam9g20ek.bin
UBOOT_BIN=u-boot.bin

write_to_log() 
{
#  echo "$@"  
  echo "$(date +%Y%m%d-%T): $@" >> $LOGFILE
}

get_application_version()
{
  if [ -f /usr/local/bin/midi9d ]; then
    KERNEL=3.1
    APP_VERSION=$(/usr/local/bin/midi9d --appversion 2>&1)
    VARDIR=/usr/local/share/midi9
    MKENVBIN=mkenvimage
  elif [ -f /usr/bin/midi9d ]; then
    KERNEL=2.6
    APP_VERSION=$(/usr/bin/midi9d --appversion 2>&1)
    VARDIR=/root
    MKENVBIN=mkenvimage2.6
  elif [ -f /usr/sbin/midi9/midi9d ]; then
    KERNEL=2.6
    VARDIR=/root
    MKENVBIN=mkenvimage2.6
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
  SERIALNUMBER_FILE=$VARDIR/.serialnumber
  LOGFILE=$VARDIR/update.log
}


uboot_set_variable()
{
  sed -i '/'$1'=/ d' u-boot-env.txt
  echo "$1=$2" >> u-boot-env.txt
}

partition_erase()
{
  if [ $KERNEL == 2.6 ]; then
    flash_eraseall $1
  else
    flash_erase --jffs2 --quiet $1 0 0
  fi
}

# .---------------------------------------------------------,
# | Description: write binary file to partition             |
# | Parameters:  [partition] [binary file]                  |
# `---------------------------------------------------------'
partition_program()
{
  if [ -e $2 ];then
    if (partition_erase $1);then
      if (nandwrite --markbad --pad --quiet $1 $2);then
        return 0
      fi
    fi
  fi
 return 1
}

# .----------------------------------------------------------------------------,
# | Section: API                                                               |
# `----------------------------------------------------------------------------'
get_application_version
if [ -f manifest.md5 ];then
  # verify u-boot installer
  if (md5sum -cs manifest.md5); then
    if [ -f /media/usbdrive/pm2_rfs.img ] && [ -f /media/usbdrive/pm2_rfs.img ];then
      cp /media/usbdrive/kernel_* ./

      if [ -f kernel_2.6.36.1 ]; then
        uboot_set_variable pm2_update_firmware 1
        uboot_set_variable pm2_kernel 2
        uboot_set_variable kernel_nandaddress "0x200000"
        uboot_set_variable bootcmd "run kernel2boot"
      elif [ -f kernel_3.1.6 ]; then
        uboot_set_variable pm2_update_firmware 1
        uboot_set_variable pm2_update_recovery 1
        uboot_set_variable pm2_kernel 3
      else
        write_to_log "[$0] FAIL: unknown kernel version"
        exit 1
      fi

      # Get current ID
      MAC_ADDRESS=$(ip link show eth0 | awk '/ether/ {print $2}')
      SERIAL_NUMBER=$(cat $SERIALNUMBER_FILE) 
      uboot_set_variable serial# $SERIAL_NUMBER
      uboot_set_variable ethaddr $MAC_ADDRESS

      chmod 755 $MKENVBIN 
      if (./$MKENVBIN -s 0x20000 -o uboot-env.bin u-boot-env.txt);then
        # Fix length so that u-boot works - kinda magic
        echo -ne \\x00 | dd bs=1 count=1 seek=22 conv=notrunc of=$BOOTSTRAP_BIN
        if (partition_program $PARTITION_BOOTSTRAP $BOOTSTRAP_BIN);then
          if (partition_program $PARTITION_UBOOTBIN $UBOOT_BIN);then
            if (partition_program $PARTITION_UBOOTENV uboot-env.bin);then
              write_to_log "[$0] SUCCESS"
              exit 0
            else
              write_to_log "[$0] FAIL: u-boot environment programming"
            fi
          else
            write_to_log "[$0] FAIL: u-boot binary programming"
          fi
        else
          write_to_log "[$0] FAIL: bootstrap programming"
        fi
      else
        write_to_log "[$0] FAIL: create environment file"
      fi
    else
      write_to_log "[$0] FAIL: no images on USB drive"
    fi
  else
    write_to_log "[$0] FAIL: invalid payload"
  fi
else
  write_to_log "[$0] FAIL: no manifest"
fi
exit 1
