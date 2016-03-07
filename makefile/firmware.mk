include defs.mk

# directories
UBOOTTOOLSDIR:=buildroot/output/build/host-uboot-tools-2014.01/tools
FIRMWAREDIR:=firmwareimage


WEBSERVERDIR:=../../public_html/htdocs/midi9
PUBLISHDIR:=$(WEBSERVERDIR)/firmware
PNOMATION_2.6.36.1_DIR:=../../pm2

# files
PAYLOAD:=payload.tar.gz
INSTALLER:=installer.tar.gz

# constants
DATE=`date +%F`

# variables
FIRMWARE_VERSION_TEST:=10.00
FIRMWARE_VERSION_CURRENT:=5.00

#*-----------------------------------------------------------------------------*
#* Firmware
#*-----------------------------------------------------------------------------*
$(FIRMWAREDIR): 
	@mkdir $(FIRMWAREDIR)/

$(FIRMWAREDIR)/pm2_kernel.img: $(FIRMWAREDIR)/uImage
	@echo "==>  make kernel u-boot image"
	@$(UBOOTTOOLSDIR)/mkimage -A arm -O linux -T firmware -C none -a $(KERNEL_IMG_ADDRESS) -e 0 -n "midi9Kernel" -d $< $@

$(FIRMWAREDIR)/pm2_rfs.img: $(FIRMWAREDIR)/rootfs.jffs2
	@echo "==>  make RFS u-boot image"
	$(UBOOTTOOLSDIR)/mkimage -A arm -O linux -T firmware -C none -a $(RFS_IMG_ADDRESS) -e 0 -n "midi9RFS" -d $< $@

$(FIRMWAREDIR)/$(INSTALLER):
	@echo "==>  Installer"
	@rm -rf $(FIRMWAREDIR)/installer;mkdir $(FIRMWAREDIR)/installer
	@cp bsp/mkenvimage2.6 $(FIRMWAREDIR)/installer
	@cp output/target/usr/local/sbin/mkenvimage $(FIRMWAREDIR)/installer/
	@cp loader/nandflash_at91sam9g20ek.bin $(FIRMWAREDIR)/installer/
	@cp loader/u-boot.bin $(FIRMWAREDIR)/installer/
	@cp configs/u-boot-env.txt $(FIRMWAREDIR)/installer/
	@cp bsp/install.sh $(FIRMWAREDIR)/installer
	@chmod 755 $(FIRMWAREDIR)/installer/install.sh
	@find $(FIRMWAREDIR)/installer -empty -type d -delete
	@cd $(FIRMWAREDIR)/installer;find ./ -type f -print0 | xargs -0 md5sum > ../manifest.md5;
	@cp $(FIRMWAREDIR)/manifest.md5 $(FIRMWAREDIR)/installer/ 
	@cd $(FIRMWAREDIR)/installer;tar czpf ../../$(FIRMWAREDIR)/$(INSTALLER) *
	@rm -r $(FIRMWAREDIR)/installer $(FIRMWAREDIR)/manifest.md5 # cleanup

firmware-image: $(FIRMWAREDIR)/pm2_kernel.img $(FIRMWAREDIR)/pm2_rfs.img $(FIRMWAREDIR)/$(INSTALLER)
	@echo "==>make pm2_firmware_$(FIRMWARE_VERSION).zip"
	@rm -f pm2_firmware_$(FIRMWARE_VERSION).zip
	@rm -rf $(FIRMWAREDIR)/image;mkdir $(FIRMWAREDIR)/image
	@cp $(FIRMWAREDIR)/$(INSTALLER) $(FIRMWAREDIR)/image
	@cp $(FIRMWAREDIR)/pm2_kernel.img $(FIRMWAREDIR)/image/
	@cp $(FIRMWAREDIR)/pm2_rfs.img $(FIRMWAREDIR)/image/
	@touch $(FIRMWAREDIR)/image/kernel_$(KERNEL_VERSION)
	@echo -n "$(DATE) " > $(FIRMWAREDIR)/image/patch_id;echo 'pm2_firmware_$(FIRMWARE_VERSION).zip' >> $(FIRMWAREDIR)/image/patch_id;
	@cp bsp/firmware-patch.sh $(FIRMWAREDIR)/image/patch.sh
	@chmod 755 $(FIRMWAREDIR)/image/patch.sh
	@find $(FIRMWAREDIR)/image -empty -type d -delete
	@cd $(FIRMWAREDIR)/image;find ./ -type f -print0 | xargs -0 md5sum > ../manifest.md5;
	@cp $(FIRMWAREDIR)/manifest.md5 $(FIRMWAREDIR)/image/ 
	@zip -j pm2_firmware_$(FIRMWARE_VERSION).zip $(FIRMWAREDIR)/image/*
	@rm -r $(FIRMWAREDIR)/image $(FIRMWAREDIR)/manifest.md5

create-jffs2-2.6-a: $(PNOMATION_2.6.36.1_DIR)/rfs/output/images/rootfs.tar $(WEBSERVERDIR)/patch/$(SYSTEMPATCHFILE) $(WEBSERVERDIR)/patch/$(MEDIAPATCHFILE)
	@echo "==>  make 2.6 JFFS2 image"
	@sudo rm -rf $(FIRMWAREDIR)/target;mkdir $(FIRMWAREDIR)/target
	@rm -rf $(FIRMWAREDIR)/systempatch;mkdir $(FIRMWAREDIR)/systempatch
	@rm -rf $(FIRMWAREDIR)/mediapatch;mkdir $(FIRMWAREDIR)/mediapatch
	@echo "  extract base system files to target"
	@sudo tar -xf $(PNOMATION_2.6.36.1_DIR)/rfs/output/images/rootfs.tar -C $(FIRMWAREDIR)/target/
	@echo "  extract media patch $(MEDIAPATCHFILE) to target"
	@unzip -q $(WEBSERVERDIR)/patch/$(MEDIAPATCHFILE) -d $(FIRMWAREDIR)/mediapatch
	@sudo tar -xzf $(FIRMWAREDIR)/mediapatch/payload.tar.gz -C $(FIRMWAREDIR)/target/
	@echo "  extract system patch $(SYSTEMPATCHFILE) to target"
	@unzip -q $(WEBSERVERDIR)/patch/$(SYSTEMPATCHFILE) -d $(FIRMWAREDIR)/systempatch
	@sudo tar -xzf  $(FIRMWAREDIR)/systempatch/payload.tar.gz -C $(FIRMWAREDIR)/target/
	@echo "  emulate patch script"
	@cp bsp/patchsystem-emulate.sh $(FIRMWAREDIR)/
	@cd $(FIRMWAREDIR)/;sudo ./patchsystem-emulate.sh $(FIRMWARE_VERSION) target systempatch
	@sudo chmod a+w $(FIRMWAREDIR)/target/root/version.log $(FIRMWAREDIR)/target/etc/hostname
	@cat $(FIRMWAREDIR)/systempatch/patch_id >> $(FIRMWAREDIR)/target/root/version.log
	@cat $(FIRMWAREDIR)/mediapatch/patch_id >> $(FIRMWAREDIR)/target/root/version.log
	@sudo echo "qrspno" > $(FIRMWAREDIR)/target/etc/hostname
	@echo "  make JFFS2 image"
	@sudo buildroot/output/host/usr/sbin/mkfs.jffs2 -e 0x20000 -l -s 0x800 -n -d $(FIRMWAREDIR)/target/ -o $(FIRMWAREDIR)/rootfs.jffs2

create-jffs2-2.6-b:$(PNOMATION_2.6.36.1_DIR)/rfs/output/images/rootfs.tar $(WEBSERVERDIR)/patch/$(SYSTEMPATCHFILE)
	@echo "==>  make 2.6 JFFS2 image"
	@sudo rm -rf $(FIRMWAREDIR)/target;mkdir $(FIRMWAREDIR)/target
	@rm -rf $(FIRMWAREDIR)/systempatch;mkdir $(FIRMWAREDIR)/systempatch
	@echo "  extract base system files to target"
	@sudo tar -xf $(PNOMATION_2.6.36.1_DIR)/rfs/output/images/rootfs.tar -C $(FIRMWAREDIR)/target/
	@echo "  extract system patch $(SYSTEMPATCHFILE) to target"
	@unzip -q $(WEBSERVERDIR)/patch/$(SYSTEMPATCHFILE) -d $(FIRMWAREDIR)/systempatch
	@echo "  emulate patch script"
	@cp bsp/patchsystem-emulate.sh $(FIRMWAREDIR)/
	@cd $(FIRMWAREDIR)/;sudo ./patchsystem-emulate.sh $(FIRMWARE_VERSION) target systempatch
	@sudo chmod a+w $(FIRMWAREDIR)/target/root/version.log $(FIRMWAREDIR)/target/etc/hostname
	@cat $(FIRMWAREDIR)/systempatch/patch_id >> $(FIRMWAREDIR)/target/root/version.log
	@sudo echo "qrspno" > $(FIRMWAREDIR)/target/etc/hostname
	@echo "  make JFFS2 image"
	@sudo buildroot/output/host/usr/sbin/mkfs.jffs2 -e 0x20000 -l -s 0x800 -n -d $(FIRMWAREDIR)/target/ -o $(FIRMWAREDIR)/rootfs.jffs2


firmware-update-patch: $(FIRMWAREDIR)
	@echo "#!/bin/sh" > $(FIRMWAREDIR)/patch.sh
	@echo " " >> $(FIRMWAREDIR)/patch.sh
	@echo "echo 'Starting patch.sh'" >> $(FIRMWAREDIR)/patch.sh
	@echo "chmod 755 /tmp/update/pm2update.sh" >> $(FIRMWAREDIR)/patch.sh
	@echo "/tmp/update/pm2update.sh update firmware serverusb" >> $(FIRMWAREDIR)/patch.sh
	@chmod 755 $(FIRMWAREDIR)/patch.sh
	@zip -j system_patch_2035-01-01.zip $(FIRMWAREDIR)/patch.sh output/target/usr/local/bin/pm2update.sh
	@echo "==>system_patch_2035-01-01.zip created<=="

#*-----------------------------------------------------------------------------*
setup-test: $(FIRMWAREDIR)
	@$(eval FIRMWARE_VERSION := $(FIRMWARE_VERSION_TEST))
	@$(eval KERNEL_IMG_ADDRESS := 0x80000)
	@$(eval RFS_IMG_ADDRESS := 0x380000)
	@$(eval KERNEL_VERSION := 3.1.6)
	@cp buildroot/output/images/uImage $(FIRMWAREDIR)/
	@cp buildroot/output/images/rootfs.jffs2 $(FIRMWAREDIR)/

firmware: setup-test firmware-image firmware-update-patch
	@echo "==>Firmware image $(FIRMWARE_VERSION) Completed<=="
	@sudo rm -r $(FIRMWAREDIR)/

#*-----------------------------------------------------------------------------*
setup-current: $(FIRMWAREDIR)
	@$(eval FIRMWARE_VERSION := $(FIRMWARE_VERSION_CURRENT))
	@$(eval SYSTEMPATCHFILE := stable_patch.zip)
	@$(eval MEDIAPATCHFILE := media_patch_2014-05-08.zip)
	@$(eval KERNEL_IMG_ADDRESS := 0x200000)
	@$(eval RFS_IMG_ADDRESS := 0xF00000)
	@$(eval KERNEL_VERSION := 2.6.36.1)
	@cp $(PNOMATION_2.6.36.1_DIR)/loader/uImage $(FIRMWAREDIR)/

firmware-current: setup-current create-jffs2-2.6-a firmware-image
	@echo "==>Firmware image $(FIRMWARE_VERSION) Completed<=="
	@sudo rm -r $(FIRMWAREDIR)/

#*-----------------------------------------------------------------------------*
setup-398: $(FIRMWAREDIR)
	@$(eval FIRMWARE_VERSION := 3.98)
	@$(eval SYSTEMPATCHFILE := system_patch_2013-04-16.zip)
	@$(eval MEDIAPATCHFILE := media_patch_2013-04-11.zip)
	@$(eval KERNEL_IMG_ADDRESS := 0x200000)
	@$(eval RFS_IMG_ADDRESS := 0xF00000)
	@$(eval KERNEL_VERSION := 2.6.36.1)
	@cp $(PNOMATION_2.6.36.1_DIR)/loader/uImage $(FIRMWAREDIR)/

firmware-398: setup-398 create-jffs2-2.6-a firmware-image
	@echo "==>Firmware image $(FIRMWARE_VERSION) Completed<=="
	@sudo rm -r $(FIRMWAREDIR)/

#*-----------------------------------------------------------------------------*
setup-251: $(FIRMWAREDIR)
	@$(eval FIRMWARE_VERSION := 2.51)
	@$(eval SYSTEMPATCHFILE := system_patch_2012-01-18.zip)
	@$(eval KERNEL_IMG_ADDRESS := 0x200000)
	@$(eval RFS_IMG_ADDRESS := 0xF00000)
	@$(eval KERNEL_VERSION := 2.6.36.1)
	@cp $(PNOMATION_2.6.36.1_DIR)/loader/uImage $(FIRMWAREDIR)/

firmware-251: setup-251 create-jffs2-2.6-b firmware-image
	@echo "==>Firmware image $(FIRMWARE_VERSION) Completed<=="
	@sudo rm -r $(FIRMWAREDIR)/

#*-----------------------------------------------------------------------------*
setup-226: $(FIRMWAREDIR)
	@$(eval FIRMWARE_VERSION := 2.26)
	@$(eval SYSTEMPATCHFILE := system_patch_2011-11-09.zip)
	@$(eval KERNEL_IMG_ADDRESS := 0x200000)
	@$(eval RFS_IMG_ADDRESS := 0xF00000)
	@$(eval KERNEL_VERSION := 2.6.36.1)
	@cp $(PNOMATION_2.6.36.1_DIR)/loader/uImage $(FIRMWAREDIR)/

firmware-226: setup-226 create-jffs2-2.6-b firmware-image 
	@echo "==>Firmware image $(FIRMWARE_VERSION) Completed<=="
	@sudo rm -r $(FIRMWAREDIR)/

#*-----------------------------------------------------------------------------*
setup-160: $(FIRMWAREDIR)
	@$(eval FIRMWARE_VERSION := 1.60)
	@$(eval SYSTEMPATCHFILE := system_patch_2011-07-18.zip)
	@$(eval KERNEL_IMG_ADDRESS := 0x200000)
	@$(eval RFS_IMG_ADDRESS := 0xF00000)
	@$(eval KERNEL_VERSION := 2.6.36.1)
	@cp $(PNOMATION_2.6.36.1_DIR)/loader/uImage $(FIRMWAREDIR)/

firmware-160: setup-160 create-jffs2-2.6-b firmware-image
	@echo "==>Firmware image $(FIRMWARE_VERSION) Completed<=="
	@sudo rm -r $(FIRMWAREDIR)/

#*-----------------------------------------------------------------------------*
firmware-all:
	@make -f firmware.mk firmware-160
	@make -f firmware.mk firmware-226
	@make -f firmware.mk firmware-251
	@make -f firmware.mk firmware-398
	@make -f firmware.mk firmware-current
	@make -f firmware.mk firmware

firmware-script-publish: output/target/usr/local/bin/pm2util.sh
	@cp output/target/usr/local/bin/pm2util.sh $(PUBLISHDIR)/
	@cp output/target/usr/local/bin/pm2update.sh $(PUBLISHDIR)/

firmware-publish: firmware-script-publish
	@-cp system_patch_2035-01-01.zip $(WEBSERVERDIR)/patch/
	@-cp system_patch_2035-01-01.zip $(PUBLISHDIR)/
	@-cp pm2_firmware_*.??.zip $(PUBLISHDIR)/
	@rm -f pm2_firmware_*.??.zip
	@rm -f system_patch_2035-01-01.zip
	@echo "==>Firmware published to $(PUBLISHDIR)<=="


#*-----------------------------------------------------------------------------*
patch: $(FIRMWAREDIR)
	@rm -f pm2_app_$(DATE).zip
	@sudo rm -rf $(FIRMWAREDIR)/target;mkdir $(FIRMWAREDIR)/target
	@rm -rf $(FIRMWAREDIR)/image;mkdir $(FIRMWAREDIR)/image
	@rsync --archive --checksum --compare-dest=../../output/release output/target/* $(FIRMWAREDIR)/target
	@find $(FIRMWAREDIR)/target -empty -type d -delete
	@cd $(FIRMWAREDIR)/target;find ./ -type f -print0 | xargs -0 md5sum > ../manifest.md5;
	@cp $(FIRMWAREDIR)/manifest.md5 $(FIRMWAREDIR)/target
	@cd $(FIRMWAREDIR)/target;tar czpf ../image/$(PAYLOAD) *
	@rm -r $(FIRMWAREDIR)/target
	@
	@echo "#!/bin/sh" > $(FIRMWAREDIR)/image/patch.sh
	@echo "if (rsync -arc /tmp/image/ /);then" >> $(FIRMWAREDIR)/image/patch.sh
	@echo "  if (cat /tmp/update/patch_id >> /usr/local/share/midi9/version.log);then" >> $(FIRMWAREDIR)/image/patch.sh
	@echo '    echo "Successful patch"' >> $(FIRMWAREDIR)/image/patch.sh
	@echo "    exit 0" >> $(FIRMWAREDIR)/image/patch.sh
	@echo "  fi" >> $(FIRMWAREDIR)/image/patch.sh
	@echo "fi" >> $(FIRMWAREDIR)/image/patch.sh
	@echo "exit 1" >> $(FIRMWAREDIR)/image/patch.sh
	@chmod 755 $(FIRMWAREDIR)/image/patch.sh
	@
	@echo -n "$(DATE) " > $(FIRMWAREDIR)/image/patch_id;echo "pm2_app_$(DATE).zip" >> $(FIRMWAREDIR)/image/patch_id;
	@find $(FIRMWAREDIR)/image -empty -type d -delete
	@cd $(FIRMWAREDIR)/image;find ./ -type f -print0 | xargs -0 md5sum > ../manifest.md5;
	@cp $(FIRMWAREDIR)/manifest.md5 $(FIRMWAREDIR)/image
	@zip -j pm2_app_$(DATE).zip $(FIRMWAREDIR)/image/*
	@echo pm2_app_$(DATE).zip > pm2_versions
	@echo "==>Firmware patch pm2_app_$(DATE).zip Completed<=="
	@sudo rm -r $(FIRMWAREDIR)/

patch-publish: firmware-script-publish
	@-cp pm2_app_????-??-??.zip $(WEBSERVERDIR)/patch/
	@ rm -f pm2_app_????-??-??.zip

#*-----------------------------------------------------------------------------*
#*   Help Display
#*-----------------------------------------------------------------------------*
help:
	@echo 'firmware commands:'
	@echo '  firmware'
	@echo '  firmware-[160|226|251|398|current]'
	@echo '  firmware-all'
	@echo '  firmware-publish'
	@echo
