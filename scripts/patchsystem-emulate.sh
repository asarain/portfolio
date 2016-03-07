#!/bin/sh

# directories
TARGET=target
UPDATE=systempatch

# files
MIDI9_DRIVER_DIR=$TARGET/lib/modules/2.6.36.1/kernel/sound/midi9
MIDI9_APP_DIR=$TARGET/usr/sbin/midi9

write_to_log() 
{
  echo "$(date +%Y%m%d-%T): $@"
}

remove_directories() {
  rm -rf $TARGET/var/www/json_data
  rm -rf $TARGET/var/www/playlist
  rm -rf $TARGET/media/playlist/playlist
  echo "Clean old install"
  rm -rf $TARGET/usr/lib/midi9/
  rm -rf $TARGET/root/config/
  rm -rf $TARGET/media/thumbB/
  rm -rf $TARGET/mnt/thumbB/
}

remove_files() {
  [ -f $TARGET/usr/lib/gstreamer-0.10/libgstequalizer.so ] && rm $TARGET/usr/lib/gstreamer-0.10/libgstequalizer.so
  [ -f $TARGET/root/timestamp ] && rm $TARGET/root/timestamp
  [ -f $TARGET/root/cdsyncalong.txt ] && rm $TARGET/root/cdsyncalong.txt
  [ -f $TARGET/root/login.cfg ] && rm $TARGET/root/login.cfg
}

move_files() {
  [ -f $TARGET/root/solenoid.conf ] && ( [ -f $TARGET/root/.keysolenoidparams ] || mv $TARGET/root/solenoid.conf $TARGET/root/.keysolenoidparams )
  [ -f $TARGET/root/midi9.conf ] && ( [ -f $TARGET/root/.appdata ] || mv $TARGET/root/midi9.conf $TARGET/root/.appdata )
  [ -f $TARGET/root/security.txt ] && ( [ -f $TARGET/root/.purchased ] || mv $TARGET/root/security.txt $TARGET/root/.purchased )
}

make_directories() {
  echo "Make directories"
  [ -d $TARGET/var/www/cgi-bin/ ] || mkdir -p $TARGET/var/www/cgi-bin/
  [ -d $TARGET/var/www/albumart/ ] || mkdir -p $TARGET/var/www/albumart/
  [ -d $TARGET/media/cdrom/ ] || mkdir -p $TARGET/media/cdrom/
  [ -d $TARGET/media/demo/ ] || mkdir -p $TARGET/media/demo/
  [ -d $TARGET/media/net/ ] || mkdir -p $TARGET/media/net/
  [ -d $TARGET/media/nfs/ ] || mkdir -p $TARGET/media/nfs/
  [ -d $TARGET/media/playlist/ ] || mkdir -p $TARGET/media/playlist/
  [ -d $TARGET/media/recordings/ ] || mkdir -p $TARGET/media/recordings/
  [ -d $TARGET/media/sdcard/ ] || mkdir -p $TARGET/media/sdcard/
  [ -d $TARGET/media/sounds/ ] || mkdir -p $TARGET/media/sounds/
  [ -d $TARGET/media/test/ ] || mkdir -p $TARGET/media/test/
  [ -d $TARGET/media/usbdrive/ ] || mkdir -p $TARGET/media/usbdrive/
  [ -d $TARGET/media/thumb/ ] || mkdir -p $TARGET/media/thumb/
  [ -d $TARGET/media/thumbB/ ] || mkdir -p $TARGET/media/thumbB/
  [ -d $TARGET/media/u_sdcard/ ] || mkdir -p $TARGET/media/u_sdcard/
  [ -d $TARGET/media/user/ ] || mkdir -p $TARGET/media/user/
  [ -d $TARGET/var/spool/cron/crontabs/ ] || mkdir -p $TARGET/var/spool/cron/crontabs/
  [ -d $TARGET/root/.velocitymaps/ ] || mkdir -p $TARGET/root/.velocitymaps/
  [ -d $TARGET/root/.keys/ ] || mkdir -p $TARGET/root/.keys/
  echo "Make links"
  [ -d /mnt/sdcard/ ] || (cd $TARGET/mnt; ln -s ../media/sdcard/ sdcard;cd ../..;)
  [ -d /mnt/u_sdcard/ ] || (cd $TARGET/mnt; ln -s ../media/u_sdcard/ u_sdcard;cd ../..;)
  [ -d /mnt/usbdrive/ ] || (cd $TARGET/mnt; ln -s ../media/usbdrive/ usbdrive;cd ../..;)
  [ -d /mnt/thumb/ ] || (cd $TARGET/mnt; ln -s ../media/thumb/ thumb;cd ../..;)
  [ -d /mnt/cdrom/ ] || (cd $TARGET/mnt; ln -s ../media/cdrom/ cdrom;cd ../..;)
  [ -d /mnt/nfs/ ] || (cd $TARGET/mnt; ln -s ../media/nfs/ nfs;cd ../..;)
  [ -d /var/www/media/ ] || (cd $TARGET/var/www/; ln -s ../../media/ media;cd ../../..;)
  [ -d /var/www/playlist/ ] || (cd $TARGET/var/www/; ln -s ../../playlist/ playlist;cd ../../..;)
}

copy_driver_files() {
  [ -d $MIDI9_DRIVER_DIR/ ] || mkdir -p $MIDI9_DRIVER_DIR/
  if [ -f $UPDATE/midi9-pwm.ko ]
  then
    echo "Copy drivers"
    chmod a+w $MIDI9_DRIVER_DIR/
    cp $UPDATE/*.ko $MIDI9_DRIVER_DIR/; chmod 755 $MIDI9_DRIVER_DIR/*.ko
  fi
}

copy_app_files() {
  [ -d $MIDI9_APP_DIR/ ] || mkdir -p $MIDI9_APP_DIR/
  [ -d $TARGET/usr/lib/alsa-lib/ ] || mkdir -p $TARGET/usr/lib/alsa-lib/
  [ -d $TARGET/usr/lib/gstreamer-0.10/ ] || mkdir -p $TARGET/usr/lib/gstreamer-0.10/
  if [ -f $UPDATE/ancho ]
  then
    echo "Copy applications"
    chmod a+w $MIDI9_APP_DIR/
    cp $UPDATE/ancho $MIDI9_APP_DIR/; chmod 755 $MIDI9_APP_DIR/ancho
    cp $UPDATE/buttons $MIDI9_APP_DIR/; chmod 755 $MIDI9_APP_DIR/buttons
    cp $UPDATE/gstplay $MIDI9_APP_DIR/; chmod 755 $MIDI9_APP_DIR/gstplay
    cp $UPDATE/midi9d $MIDI9_APP_DIR/; chmod 755 $MIDI9_APP_DIR/midi9d
    cp $UPDATE/midi9_updater $MIDI9_APP_DIR/; chmod 755 $MIDI9_APP_DIR/midi9_updater
    cp $UPDATE/midiconn $MIDI9_APP_DIR/; chmod 755 $MIDI9_APP_DIR/midiconn
    cp $UPDATE/pmidi $MIDI9_APP_DIR/; chmod 755 $MIDI9_APP_DIR/pmidi
    cp $UPDATE/rmidi $MIDI9_APP_DIR/; chmod 755 $MIDI9_APP_DIR/rmidi
    cp $UPDATE/ppu $MIDI9_APP_DIR/; chmod 755 $MIDI9_APP_DIR/ppu
    cp $UPDATE/solenoidadjust $MIDI9_APP_DIR/; chmod 755 $MIDI9_APP_DIR/solenoidadjust
    cp $UPDATE/testusb $MIDI9_APP_DIR/; chmod 755 $MIDI9_APP_DIR/testusb
    [ -f $UPDATE/selftest ] && (cp $UPDATE/selftest $MIDI9_APP_DIR/; chmod 755 $MIDI9_APP_DIR/selftest;)
    cp $UPDATE/midi9cgi $TARGET/var/www/cgi-bin/; chmod 755 $TARGET/var/www/cgi-bin/midi9cgi
    cp $UPDATE/libgstami.so $TARGET/usr/lib/gstreamer-0.10/; chmod 755 $TARGET/usr/lib/gstreamer-0.10/libgstami.so
    [ -f $UPDATE/libgsteq.so ] && (cp $UPDATE/libgsteq.so $TARGET/usr/lib/gstreamer-0.10/; chmod 755 $TARGET/usr/lib/gstreamer-0.10/libgsteq.so;)
    if [ -f $UPDATE/libmidi9.so.0.0.1 ]; then
      cp $UPDATE/libmidi9.so.0.0.1 $TARGET/usr/lib/; chmod 755 $TARGET/usr/lib//libmidi9.so.0.0.1
    	rm -f $TARGET/usr/lib/libmidi9.so.0 $TARGET/usr/lib/libmidi9.so.1
  	  (cd $TARGET/usr/lib; ln -s libmidi9.so.0.0.1 libmidi9.so;cd ../../..;)
  	  (cd $TARGET/usr/lib; ln -s libmidi9.so.0.0.1 libmidi9.so.0;cd ../../..;)
  	  (cd $TARGET/usr/lib; ln -s libmidi9.so.0.0.1 libmidi9.so.1;cd ../../..;)
    fi
  else
    echo "FAILURE! app files not found"
  fi
}

copy_system_files() {
  if [ -f $UPDATE/S90midi9 ]
  then
    echo "Copy system files"
    cp $UPDATE/S90midi9 $TARGET/etc/init.d/; chmod 755 $TARGET/etc/init.d/S90midi9
    cp $UPDATE/getpatch $TARGET/root/; chmod 755 $TARGET/root/getpatch
    cp $UPDATE/hotplug $TARGET/sbin/; chmod 755 $TARGET/sbin/hotplug
    cp $UPDATE/hostapd.conf $TARGET/root/
    cp $UPDATE/HOWTO.txt $TARGET/root/
    cp $UPDATE/cdsyncalong.txt $TARGET/root/.syncalong
    [ -f $UPDATE/login.cfg ] && (cp $UPDATE/login.cfg $TARGET/root/.ftplogin;)
    [ -f $UPDATE/cron.txt ] && (cp $UPDATE/cron.txt $TARGET/root/;)
    [ -f $TARGET/root/.purchased ] || cp $UPDATE/security.txt $TARGET/root/.purchased
    cp $UPDATE/fstab $TARGET/etc/
    cp $UPDATE/udhcpd.conf $TARGET/etc/
    cp $UPDATE/asound.conf $TARGET/etc/
    cp $UPDATE/resolv.conf $TARGET/etc/
    cp $UPDATE/httpd.conf $TARGET/etc/
    cp $UPDATE/avahi-daemon.conf $TARGET/etc/avahi/
    cp $UPDATE/PMII_start.html $TARGET/media/
    cp $UPDATE/modules.dep $TARGET/lib/modules/2.6.36.1/
    cp $UPDATE/modules.usbmap $TARGET/lib/modules/2.6.36.1/
    [ -d $TARGET/etc/samba/ ] && cp $UPDATE/smb.conf $TARGET/etc/samba/ || echo 'No samba dir'
  fi
}

setup_nodes() {
  if [ -f $UPDATE/snddevices ]
  then
    echo "Setup nodes"
    chmod 755 $UPDATE/snddevices
#    $UPDATE/snddevices
  fi
  [ -d $TARGET/dev/input/ ] || mkdir -p $TARGET/dev/input/
  [ -r $TARGET/dev/input/event0 ] || sudo mknod $TARGET/dev/input/event0 c 13 64
  [ -d $TARGET/dev/misc/ ] || mkdir -p $TARGET/dev/misc/
  [ -r $TARGET/dev/misc/rtc ] || sudo mknod $TARGET/dev/misc/rtc c 254 0
}

update_script_files() {
  [ -d $TARGET/root/scripts/ ] || mkdir -p $TARGET/root/scripts
  if [ -f $UPDATE/scripts.zip ]
  then
    echo "Setup script files"
    unzip -q -o $UPDATE/scripts.zip -d $TARGET/root/scripts/
    chmod 755 $TARGET/root/scripts/*
  fi
}

update_website() {
  [ -d $TARGET/var/www/ ] || mkdir -p $TARGET/var/www/
  if [ -f $UPDATE/webapp.zip ]
  then
    echo "Setup web app"
    unzip -q -o $UPDATE/webapp.zip -d $TARGET/var/www/
  fi
  [ -d $TARGET/var/www/midi9/ ] || mkdir -p $TARGET/var/www/midi9/
  if [ -f $UPDATE/www.zip ]
  then
    echo "Setup midi9 web diagnostics"
    unzip -q -o $UPDATE/www.zip -d $TARGET/var/www/
  fi
  if [ -f $UPDATE/albumart.zip ]
  then
    echo "Setup album art"
    unzip -q -o $UPDATE/albumart.zip -d $TARGET/var/www/
  fi
  chmod 755 $TARGET/var/www/cgi-bin/*
}

update_demosongs() {
  [ -d $TARGET/media/demo/ ] || mkdir -p $TARGET/media/demo/
  if [ -f $UPDATE/demosongs.zip ]
  then
    echo "Setup demosongs"
    rm -f $TARGET/media/demo/*
    unzip -q -o $UPDATE/demosongs.zip -d $TARGET/media/demo/
  fi
  [ -d $TARGET/media/test/ ] || mkdir -p $TARGET/media/test/
  if [ -f $UPDATE/test_tracks.zip ]
  then
    echo "Setup test tracks"
    rm -rf $TARGET/media/test/*
    unzip -q -o $UPDATE/test_tracks.zip -d $TARGET/media/test/
  fi
  [ -d $TARGET/media/sounds/ ] || mkdir -p $TARGET/media/sounds/
  if [ -f $UPDATE/sounds.zip ]
  then
    echo "Setup sounds"
    rm -f $TARGET/media/sounds/*
    unzip -q -o $UPDATE/sounds.zip -d $TARGET/media/sounds/
  fi
}

update_firmware() {
  if [ -f $UPDATE/firmware.zip ]
  then
    echo "Setup firmware"
    unzip -q -o $UPDATE/firmware.zip -d $TARGET/lib/
  fi
}

update_velocitymaps() {
  if [ -f $UPDATE/velocitymaps.zip ]
  then
    echo "Setup firmware"
    unzip -q -o $UPDATE/velocitymaps.zip -d $TARGET/root/.velocitymaps/
  fi
}

make_soft_links() {
  [ -f /var/www/json_data ] || (cd $TARGET/var/www; ln -s ../../tmp/json_data/ json_data;cd ../../..;)
  [ -f /var/www/media ] || (cd $TARGET/var/www; ln -s ../../media/ media;cd ../../..;)
  [ -f /var/www/playlist ] || (cd $TARGET/var/www; ln -s ../../media/playlist playlist;cd ../../..;)
  rm -rf $TARGET/var/log
  cd $TARGET/var; ln -s ../tmp/ log;cd ../..;
}


case "$1" in
  5.00)
    TARGET=$2
    UPDATE=$3
    echo "Update Pianomation II Script BEGIN"
    echo "Pianomation II Web-Enabled Player Piano Controller" > $TARGET/etc/issue
    write_to_log "--> update script START <--"
    setup_nodes
    chmod 777 $TARGET/root/cloud/
    [ -f $TARGET/root/.drm ] ||  (mv $TARGET/root/.defaults/.purchased $TARGET/root/;)
    touch $TARGET/root/.updated
    make_soft_links
    write_to_log "Pianomation update script SUCCESS"
	;;
  3.98)
    TARGET=$2
    UPDATE=$3
    echo "Update Pianomation II Script BEGIN"
    echo "Pianomation II Web-Enabled Player Piano Controller" > $TARGET/etc/issue
    write_to_log "--> update script START <--"
    setup_nodes
    chmod 777 $TARGET/root/cloud/
    [ -f $TARGET/root/.drm ] ||  (mv $TARGET/root/.defaults/.purchased $TARGET/root/;)
    touch $TARGET/root/.updated
    make_soft_links

    write_to_log "Pianomation update script SUCCESS"
	;;
  2.51)
    TARGET=$2
    UPDATE=$3
    echo "Update midi9 applications/drivers"
    echo "Pianomation II Web-Enabled Player Piano Controller" > $TARGET/etc/issue
    move_files
    make_directories
    copy_driver_files
    copy_app_files
    copy_system_files
    update_script_files
    update_website
    update_demosongs
    update_firmware
    update_velocitymaps
    setup_nodes
	;;
  2.26)
    TARGET=$2
    UPDATE=$3
    echo "Update midi9 applications/drivers"
    echo "Pianomation II Web-Enabled Player Piano Controller" > $TARGET/etc/issue
    move_files
    make_directories
    copy_driver_files
    copy_app_files
    copy_system_files
    update_script_files
    update_website
    update_demosongs
    update_firmware
    update_velocitymaps
    setup_nodes
	;;
  1.60)
    TARGET=$2
    UPDATE=$3
    echo "Update midi9 applications/drivers to version $1"
    echo "Pianomation II Web-Enabled Player Piano Controller" > $TARGET/etc/issue
    move_files
    make_directories
    copy_driver_files
    copy_app_files
    copy_system_files
    update_script_files
    update_website
    update_demosongs
    update_firmware
    update_velocitymaps
    setup_nodes
	;;
  *)
    echo "[$0]: Unknown version $1"
esac

exit $?
