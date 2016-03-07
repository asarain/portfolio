ROOTDIR=./
include defs.mk

APPDIR:=$(PWD)
SUBDIRS := drivers midi9d midi9cgi midi9midi midi9player ppu midi9_apps gsteq gstsync testhw

all: release

#*-----------------------------------------------------------------------------*
#* Build code
#*-----------------------------------------------------------------------------*
createtarget:
	mkdir -p $(TARGETDIR)/
	tar xvzf $(ROOTDIR)/bsp/image_system.tar.gz -C $(TARGETDIR)
	rsync -ar $(PROJECTDIR)/common/target/* $(TARGETDIR)
	$(MAKE) webapp-update
	mkdir -p $(TARGETDIR)/$(KERNELLIBDIR)/sound/soc/
	mkdir -p $(TARGETDIR)/$(KERNELLIBDIR)/drivers/midi9/
	mkdir -p $(TARGETDIR)/usr/lib/gstreamer-0.10/
	mkdir -p $(TARGETDIR)/usr/local/lib/gstreamer-0.10/
	rsync -a ../common/target/usr/local/bin/* $(TARGETDIR)/usr/local/bin/
	sudo chown -R $(USER):$(USER) $(TARGETDIR)/*

$(TARGETDIR):
	$(MAKE) createtarget

debug release: $(TARGETDIR)
	@$(MAKE) midi9lib
	@echo "================="
	@echo "==> Make Code <=="
	@echo "================="
	for dir in $(SUBDIRS); do (cd $$dir && $(MAKE) --no-print-directory) || exit 1; done

#	@for dir in $(SUBDIRS); do (cd $$dir && $(MAKE) --no-print-directory $@) || exit 1; done

sync:
	$(MAKE) release
	@sudo chown -R root:root $(TARGETDIR)/*
	sudo rsync --archive --recursive --itemize-changes $(TARGETDIR)/* /tftpboot/root/ 
	@sudo chown -R $(USER):$(USER) $(TARGETDIR)/*

#*-----------------------------------------------------------------------------*
#* library build code
#*-----------------------------------------------------------------------------*
LIBTOOLSDIR:=$(APPDIR)/buildroot/output/host/usr
LIBSTAGINGDIR:=$(APPDIR)/buildroot/output/staging
LIBTOOLPREFIX:=$(LIBTOOLSDIR)/bin/arm-linux
MAKETOOLS_OPTIONS:=LD="$(LIBTOOLPREFIX)-ld --sysroot=$(LIBSTAGINGDIR)" \
    CC="$(LIBTOOLPREFIX)-gcc --sysroot=$(LIBSTAGINGDIR)" \
    RANLIB="$(LIBTOOLPREFIX)-ranlib" \
    STRIP="$(LIBTOOLPREFIX)-strip" \
    OBJCOPY="$(LIBTOOLPREFIX)-objcopy" \
    OBJDUMP="$(LIBTOOLPREFIX)-objdump" \
    DEFAULT_LINKER="$(LIBTOOLPREFIX)-ld --sysroot=$(LIBSTAGINGDIR)" \
    CFLAGS="-Os -pipe -O2  -D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64" \
    LDFLAGS="-L$(LIBSTAGINGDIR)/lib -L$(LIBSTAGINGDIR)/usr/lib" \
    PKG_CONFIG_SYSROOT_DIR="$(LIBSTAGINGDIR)" \
    PKG_CONFIG="$(LIBTOOLSDIR)/bin/pkg-config" \
    PKG_CONFIG_PATH="$(LIBSTAGINGDIR)/lib/pkgconfig:" \
    PERLLIB="$(LIBSTAGINGDIR)/lib/perl" \
    LIBSTAGINGDIR="$(LIBSTAGINGDIR)" ac_cv_lbl_unaligned_fail=yes ac_cv_func_mmap_fixed_mapped=yes ac_cv_func_memcmp_working=yes ac_cv_have_decl_malloc=yes gl_cv_func_malloc_0_nonnull=yes ac_cv_func_malloc_0_nonnull=yes ac_cv_func_calloc_0_nonnull=yes ac_cv_func_realloc_0_nonnull=yes ac_cv_c_bigendian=no  ./configure --target=arm-linux --host=arm-linux --build=i686-pc-linux-gnu --prefix=/usr --exec-prefix=/usr --sysconfdir=/etc

lib/Makefile:
	mkdir -p lib/m4
	cd lib/; autoreconf -iv;
	(cd lib/ && rm -rf config.cache && $(MAKETOOLS_OPTIONS) )

midi9lib: lib/Makefile
	@echo "==> Make library <=="
	@cd lib;$(MAKE)
	@cp lib/src/.libs/libmidi9.so  $(STAGING_DIR)/usr/lib/
	@cp lib/src/.libs/libmidi9.a   $(STAGING_DIR)/usr/lib/
	@cp lib/src/.libs/libmidi9.la  $(STAGING_DIR)/usr/lib/
	@cp lib/src/.libs/libmidi9.lai $(STAGING_DIR)/usr/lib/
	@cp lib/src/.libs/libmidi9.so.0.0.1 $(TARGETDIR)/usr/lib/
	@cp lib/src/.libs/libmidi9.so.0.0.1 $(TARGETDIR)/usr/local/lib/

lib-clean:
	cd lib && $(MAKE) clean

#*-----------------------------------------------------------------------------*
#* utilities
#*-----------------------------------------------------------------------------*
webapp-update:
	unzip -o $(ROOTDIR)/bsp/webapp.zip -d $(TARGETDIR)/var/www/

nfs-update:
	@find ./ -name \*~ | xargs sudo rm -f
	@find ./ -name \*.bak | xargs sudo rm -f
	@cp $(KERNEL_IMAGE) /tftpboot/
	@sudo chown -R root:root $(TARGETDIR)/*
	sudo rsync --archive --recursive --itemize-changes $(TARGETDIR)/* /tftpboot/root/ 
	@sudo chown -R $(USER):$(USER) $(TARGETDIR)/*

clean:
	@for dir in $(SUBDIRS); do (cd $$dir && $(MAKE) clean) || exit 1; done
	@find . -type f -name "*.bak" -exec rm -f {} \;
	@find . -type f -name "*.lo" -exec rm -f {} \;
	@find . -type f -name "*.o.cmd" -exec rm -f {} \;
	@find . -type f -name "*.ko.cmd" -exec rm -f {} \;
	@find . -type f -name "*~" -exec rm -f {} \;
	@sudo rm -rf $(TARGETDIR)/


#*-----------------------------------------------------------------------------*
#* pianomation
#*-----------------------------------------------------------------------------*
#*-----------------------------------------------------------------------------*
#* Firmware
#*-----------------------------------------------------------------------------*
firmware:
	@$(MAKE) -f firmware.mk firmware

firmware-script:
	@$(MAKE) -f firmware.mk firmware-script-publish

firmware-current:
	@$(MAKE) -f firmware.mk firmware-current

firmware-all:
	@$(MAKE) -f firmware.mk firmware-all

firmware-publish:
	@$(MAKE) -f firmware.mk firmware-publish

firmware-rebuild:
	@$(MAKE) pm-clean
	@$(MAKE) pm
	@$(MAKE) jffs2
	@$(MAKE) firmware-all
	@$(MAKE) firmware-publish
	@$(MAKE) firmware-script

patch:
	@$(MAKE) -f firmware.mk patch

patch-publish:
	@$(MAKE) -f firmware.mk patch-publish

#*-----------------------------------------------------------------------------*
#* Root File System
#*-----------------------------------------------------------------------------*
$(BUILDROOT_SOURCE_FILE):
	wget -P ./ http://buildroot.uclibc.org/downloads/$(BUILDROOT_SOURCE_FILE)

$(BRDIR)/.pmii_unpacked_stamp: $(BUILDROOT_SOURCE_FILE)
	mkdir -p $(BRDIR)
	tar -xvjf $(BUILDROOT_SOURCE_FILE)
	mv $(BUILDROOT_DIR)/* $(BRDIR)/
	rm -r $(BUILDROOT_DIR)
	patch -p0 < configs/package.patch
#	cp configs/gst-plugins-base-audiotstsrc.patch $(BRDIR)/package/multimedia/gst-plugins-base/
	[ -d ~$(USER)/dev/downloads ] || mkdir -p ~$(USER)/dev/downloads
	touch $@

$(BRDIR)/.pmii_configured_stamp: $(BRDIR)/.pmii_unpacked_stamp
	cp configs/pmii_defconfig $(BRDIR)/configs
	cp configs/pmii_kernel_defconfig $(BRDIR)/configs
	touch $@

$(BRDIR)/.pmii_build_stamp: $(BRDIR)/.pmii_configured_stamp
	$(MAKE) createtarget
	cd $(BRDIR); $(MAKE) pmii_defconfig
	touch $@

$(BRDIR)/.pmii_driverpatch_stamp: $(BRDIR)/.pmii_build_stamp
	make -C $(BRDIR)/
	cp configs/midi9_wm8580.c $(BRDIR)/$(LINUX_DIR)/sound/soc/atmel/
	touch $@

rfs:	$(BRDIR)/.pmii_driverpatch_stamp
	make -C $(BRDIR)/
	@echo "DONE"

audio:
	rm -f $(BRDIR)/output/target/lib/modules/$(LINUX_VERSION)/kernel/sound/soc/atmel/snd-soc-atmel_ssc_dai.ko
	rm -f $(BRDIR)/output/target/lib/modules/$(LINUX_VERSION)/kernel/sound/soc/snd-soc-midi9-wm8580.ko
	rm -f $(BRDIR)/output/target/lib/modules/$(LINUX_VERSION)/kernel/sound/soc/codecs/snd-soc-wm8580.ko
	make -C $(BRDIR)/
	make pm
	sudo rsync --archive --recursive --itemize-changes $(BRDIR)/output/target/lib/modules/$(LINUX_VERSION)/kernel/* /tftpboot/root/lib/modules/$(LINUX_VERSION)/kernel/ 

#*-----------------------------------------------------------------------------*
#* kernel
#*-----------------------------------------------------------------------------*
kernel:
	rm -f $(BRDIR)/$(LINUX_DIR)/arch/arm/boot/uImage
	rm -f $(BRDIR)/output/images/uImage
	rm -f $(BRDIR)/$(LINUX_DIR)/.stamp_built
	$(MAKE) -C $(BRDIR)/
	cp $(BRDIR)/$(LINUX_DIR)/arch/arm/boot/uImage $(BRDIR)/output/images/
	sudo cp $(BRDIR)/output/images/uImage /tftpboot


testsrc:
	rm -f buildroot/output/build/gst-plugins-base-0.10.36/.stamp_built
	rm -f buildroot/output/build/gst-plugins-base-0.10.36/.stamp_images_installed
	rm -f buildroot/output/build/gst-plugins-base-0.10.36/.stamp_target_installed
	$(MAKE) -C $(BRDIR)/
#	cp buildroot/output/build/at91bootstrap-1.16/nandflash_at91sam9g20ek.bin buildroot/output/images/
#	cp buildroot/output/images/nandflash_at91sam9g20ek.bin loader/
#	sudo cp buildroot/output/images/nandflash_at91sam9g20ek.bin /tftpboot/root/root/


#*-----------------------------------------------------------------------------*
#* jffs2
#*-----------------------------------------------------------------------------*
jffs2:
	@rm -f buildroot/output/images/uImage
	@rm -f buildroot/output/images/rootfs.jffs2
	@$(MAKE) kernel

#*-----------------------------------------------------------------------------*
#* uboot
#*-----------------------------------------------------------------------------*
bootstrap:
	rm -f buildroot/output/build/at91bootstrap-1.16/.stamp_built
	rm -f buildroot/output/build/at91bootstrap-1.16/.stamp_images_installed
	rm -f buildroot/output/build/at91bootstrap-1.16/.stamp_target_installed
	$(MAKE) -C $(BRDIR)/
	cp buildroot/output/build/at91bootstrap-1.16/nandflash_at91sam9g20ek.bin buildroot/output/images/
	cp buildroot/output/images/nandflash_at91sam9g20ek.bin loader/
	sudo cp buildroot/output/images/nandflash_at91sam9g20ek.bin /tftpboot/root/root/

uboot:
	rm -f buildroot/output/build/uboot-2013.04/.stamp_built
	rm -f buildroot/output/build/uboot-2013.04/.stamp_images_installed
	rm -f buildroot/output/build/uboot-2013.04/.stamp_target_installed
	$(MAKE) -C $(BRDIR)/
	cp buildroot/output/build/uboot-2013.04/u-boot.bin buildroot/output/images/
	cp buildroot/output/images/u-boot.bin loader/
	sudo cp buildroot/output/images/u-boot.bin /tftpboot/root/root/

uboot-environment:
	dos2unix configs/u-boot-env.txt
	buildroot/output/build/host-uboot-tools-2013.04/tools/mkenvimage -s 0x20000 -o buildroot/output/images/uboot-env.bin configs/u-boot-env.txt 
	cp buildroot/output/images/uboot-env.bin loader/

#*-----------------------------------------------------------------------------*
#* xmplib
#*-----------------------------------------------------------------------------*
xmplib:
	cd xmplib/build/cross_compile/arm9g20;make
	cp xmplib/bin/linux-armv5tej1_debug/hdmidi output/target/usr/local/bin/
#	sudo cp xmplib/bin/linux-armv5tej1_debug/* /tftpboot/root/usr/local/bin/

xmplib-clean:
	cd xmplib/build/cross_compile/arm9g20;make distclean

#*-----------------------------------------------------------------------------*
#* backup
#*-----------------------------------------------------------------------------*
configurekerneldrivers:
	@echo '****** Backup board config files'
	cd $(BRDIR)/$(LINUX_DIR)/arch/arm/mach-at91/; [ -f at91sam9260_devices.c.orig ] || cp at91sam9260_devices.c at91sam9260_devices.c.orig
	cd $(BRDIR)/$(LINUX_DIR)/arch/arm/mach-at91/; [ -f board-sam9g20ek.c.orig ]     || cp board-sam9g20ek.c     board-sam9g20ek.c.orig
	@echo '****** Backup driver files'
	cd $(BRDIR)/$(LINUX_DIR)/drivers/usb/host/;   [ -f ohci.h.orig ]          || cp ohci.h          ohci.h.orig
	cd $(BRDIR)/$(LINUX_DIR)/drivers/usb/host/;   [ -f ohci-hcd.c.orig ]      || cp ohci-hcd.c      ohci-hcd.c.orig
	cd $(BRDIR)/$(LINUX_DIR)/drivers/usb/gadget/;	[ -f gmidi.c.orig ]         || cp gmidi.c         gmidi.c.orig
	cd $(BRDIR)/$(LINUX_DIR)/drivers/tty/serial/; [ -f atmel_serial.c.orig ]  || cp atmel_serial.c  atmel_serial.c.orig
	@echo '****** Backup audio driver files'
	cd $(BRDIR)/$(LINUX_DIR)/sound/soc/atmel/;    [ -f atmel_ssc_dai.c.orig ] || cp atmel_ssc_dai.c atmel_ssc_dai.c.orig
	cd $(BRDIR)/$(LINUX_DIR)/sound/soc/codecs/;   [ -f wm8580.c.orig ]        || cp wm8580.c        wm8580.c.orig
	cd $(BRDIR)/$(LINUX_DIR)/sound/soc/codecs/;   [ -f wm8580.h.orig ]        || cp wm8580.h        wm8580.h.orig
	@echo '****** Apply driver patches'
#	patch -p0 < configs/midi9_kernel.patch
	@echo '****** Copy files'

createkernelpatch:
	-diff -Naur $(BRDIR)/$(LINUX_DIR)/arch/arm/mach-at91/at91sam9260_devices.c.orig $(BRDIR)/$(LINUX_DIR)/arch/arm/mach-at91/at91sam9260_devices.c  > configs/midi9_kernel.patch
	-diff -Naur $(BRDIR)/$(LINUX_DIR)/arch/arm/mach-at91/board-sam9g20ek.c.orig     $(BRDIR)/$(LINUX_DIR)/arch/arm/mach-at91/board-sam9g20ek.c     >> configs/midi9_kernel.patch
	-diff -Naur $(BRDIR)/$(LINUX_DIR)/drivers/usb/host/ohci.h.orig                  $(BRDIR)/$(LINUX_DIR)/drivers/usb/host/ohci.h                  >> configs/midi9_kernel.patch
	-diff -Naur $(BRDIR)/$(LINUX_DIR)/drivers/usb/host/ohci-hcd.c.orig              $(BRDIR)/$(LINUX_DIR)/drivers/usb/host/ohci-hcd.c              >> configs/midi9_kernel.patch
	-diff -Naur $(BRDIR)/$(LINUX_DIR)/drivers/usb/gadget/gmidi.c.orig               $(BRDIR)/$(LINUX_DIR)/drivers/usb/gadget/gmidi.c               >> configs/midi9_kernel.patch
	-diff -Naur $(BRDIR)/$(LINUX_DIR)/drivers/tty/serial/atmel_serial.c.orig        $(BRDIR)/$(LINUX_DIR)/drivers/tty/serial/atmel_serial.c        >> configs/midi9_kernel.patch
	-diff -Naur $(BRDIR)/$(LINUX_DIR)/sound/soc/atmel/atmel_ssc_dai.c.orig          $(BRDIR)/$(LINUX_DIR)/sound/soc/atmel/atmel_ssc_dai.c          >> configs/midi9_kernel.patch
	-diff -Naur $(BRDIR)/$(LINUX_DIR)/sound/soc/codecs/wm8580.c.orig                $(BRDIR)/$(LINUX_DIR)/sound/soc/codecs/wm8580.c                >> configs/midi9_kernel.patch
	-diff -Naur $(BRDIR)/$(LINUX_DIR)/sound/soc/codecs/wm8580.h.orig                $(BRDIR)/$(LINUX_DIR)/sound/soc/codecs/wm8580.h                >> configs/midi9_kernel.patch
	@echo '****** Documentation only, not used'
	-diff -Naur $(BRDIR)/$(LINUX_DIR)/drivers/spi/spi-atmel.c drivers/atmel_spi.c  > configs/documentation.patch
	-diff -Naur $(BRDIR)/$(LINUX_DIR)/drivers/spi/spi-atmel.c drivers/atmel_spi.h >> configs/documentation.patch

uboot-patch:
	cd buildroot/output/build/uboot-2013.04/;diff -Naur ./board/atmel/at91sam9260ek/auto_update.c.orig ./board/atmel/at91sam9260ek/auto_update.c > ../../../../auto_update.patch

backup:
	@echo "--- MIDI9 makefiles ---";
	cp -p $(BRDIR)/.config configs/pmii_defconfig
	cp -p $(BRDIR)/$(LINUX_DIR)/.config configs/pmii_kernel_defconfig
	cp -p $(BRDIR)/output/build/busybox-1.21.0/.config configs/pmii_busybox_defconfig
	cp $(BRDIR)/$(LINUX_DIR)/sound/soc/atmel/midi9_wm8580.c configs/

#*-----------------------------------------------------------------------------*
#* utilities
#*-----------------------------------------------------------------------------*
nfs:
	mkdir -p /tftpboot/root
	sudo rm -rf /tftpboot/root/*
	sudo tar -xpf $(BRDIR)/output/images/rootfs.tar -C /tftpboot/root/
	cp $(BRDIR)/output/images/uImage /tftpboot/
	cd midi9;$(MAKE) nfs-update

loader-sync:
	cp buildroot/output/images/nandflash_at91sam9g20ek.bin loader/
	cp buildroot/output/images/u-boot.bin loader/
	$(MAKE) uboot-environment

nfs-rollback:
	@sudo cp buildroot/output/images/uboot-env.bin /tftpboot/root/root/uboot-env_backup.bin
	@sudo cp buildroot/output/images/uImage /tftpboot/root/root/uImage_backup.bin
	@sudo cp buildroot/output/images/rootfs.jffs2 /tftpboot/root/root/rootfs_backup.jffs2

lib-cleanall:
	rm -rf lib/autom4te.cache lib/m4 lib/Makefile lib/aclocal.m4 lib/config.log lib/configure lib/Makefile.in lib/ltmain.sh lib/include/Makefile.in lib/src/config.h.in lib/src/Makefile.in lib/src/*.lo lib/src/*.o lib/src/*.la lib/src/config.h lib/src/Makefile lib/src/stamp-h1 lib/include/Makefile lib/include/version.h lib/src/.deps ../common/src/.deps ../common/src/.libs

dist-clean:
	sudo rm -rf $(BRDIR)/
#	[ -f midi9/Makefile ] && (cd midi9;$(MAKE) clean)


#*-----------------------------------------------------------------------------*
#*   Help Display
#*-----------------------------------------------------------------------------*
help:
	@echo 'To make a build/release:'
	@echo '  make dist-clean        - remove everything except for driver source and bsp source'
	@echo '  make                   - build everything, takes a long time'
	@echo '  make nfs               - copies root file system to tftp drive, zip bsp package'
	@echo
	@echo 'Cleaning:'
	@echo '  dist-clean             - everything except this file and the bsp source'
	@echo
	@echo 'Patch:'
	@echo '  upgrade                - Complete upgrade package'
	@echo
	@echo 'Build:'
	@echo '  pm                     - build application'
	@echo '  rfs                    - build buildroot'
	@echo '  kernel                 - re-build kernel'
	@echo '  uboot                  - re-build uboot'
	@echo '  uboot-environment      - build uboot environment'
	@echo '  xmplib                 - build hd-midi library'
	@echo
	@echo 'Miscellaneous:'
	@echo '  backup                 - backup setup'
	@echo
