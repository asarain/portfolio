BUILDROOT_VERSION:=2014.02
LINUX_VERSION:=3.1.6

BRDIR:=buildroot
NFS_DIR:=/tftpboot/root
TMPDIR:=tmpdir

BUILDROOT_DIR:=buildroot-$(BUILDROOT_VERSION)
BUILDROOT_SOURCE_FILE:=$(BUILDROOT_DIR).tar.bz2

LINUX_DIR:=output/build/linux-$(LINUX_VERSION)
# pre-requisites:
# - ROOTDIR is set
#
# Vars that can be set beforehand:
# - CC, CFLAGS, LD, LDFLAGS
# - CONFIG ("release" or "debug")
# - DEBUG (debug Makefile)
# - ARCH  (usually auto detected, e.g. i386,i686,x86_64,armv6l)
# - OS    (usually auto detected, e.g. iOS,Linux,Darwin)
# - LIBS  (lib commands to the linker)

# these vars will set:
# - SRCDIR
# - OBJDIR
# - BINDIR (executables)
# - LIBDIR (libraries)
# - CONFIG (release or debug)
# - CFLAGS
# - LDFLAGS
# - CC
# - LD
# - AR

ARCH=armv5tej1
OS=Linux

FLAGS = -Wall \
        -Wextra
#        -Wstrict-prototypes \
#        -Wundef
#        -fsigned-char \
#        -fno-builtin \
#        -fno-unroll-loops \
#        -fpeephole \
#        -fno-keep-inline-functions \
#        -pedantic \
#        -Wcast-qual \
#        -Wwrite-strings \
#        -Winline

.POSIX:

CFLAGS_release = -O2
CFLAGS_debug   = -g -DDEBUG

# build specific flags
STAGING_DIR:=$(ROOTDIR)/buildroot/output/staging
KERNEL_IMAGE = $(ROOTDIR)/buildroot/output/images/uImage
GST_EQ_DIR   = $(ROOTDIR)/buildroot/output/build/gst-plugins-good-0.10.31/gst/equalizer
TOOLSDIR:=$(ROOTDIR)/buildroot/output/host/usr/bin
KERNELLIBDIR:=lib/modules/$(LINUX_VERSION)/kernel
LIBSDIR:=$(ROOTDIR)/buildroot/output/host/usr/arm-buildroot-linux-uclibcgnueabi/sysroot/usr/lib

# arch-specific compiler options
DEFINES_armv5tej1 =-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -DHAVE_ASM_IOCTLS_H=1 -DHAVE_LINUX_HAYESESP_H=1  

CFLAGS_armv6l = -Wno-psabi # do not warn about modified va_args implementation
CFLAGS_armv5tej1 = --sysroot=$(STAGING_DIR)/ -isysroot $(STAGING_DIR) $(DEFINES_$(ARCH)) -Wl,-rpath=/usr/local/lib

LDFLAGS_armv5tej1 = --sysroot=$(STAGING_DIR)/ -isysroot $(STAGING_DIR) -L$(STAGING_DIR)/lib/ -L$(STAGING_DIR)/usr/lib/ 

# processor architecture: i386, x86_64, armv6l, ...
NATIVE_ARCH := $(shell uname -m)
ifndef ARCH
 ARCH := $(NATIVE_ARCH)
 export ARCH
endif

# OS: Linux, Darwin, iOS
ifndef OS
 OS := $(shell uname)
 export OS  
endif

# default config (debug or release)
ifndef CONFIG
 CONFIG := debug
endif

# basic directories
OBJDIR       = 
SRCDIR       = $(ROOTDIR)
PROJECTDIR   = $(ROOTDIR)/..
BINDIR       = $(SRCDIR)/output/target
TARGETDIR    = $(SRCDIR)/output/target
COMMONSRCDIR = $(SRCDIR)/common
NFSDIR       = /tftpboot/root

# libraries and c-flags
ALSA_CFLAGS = -I$(STAGING_DIR)/usr/include/alsa
ALSA_LIBS = -L$(LIBSDIR) -lasound

GLIB_CFLAGS = -I$(STAGING_DIR)/usr/include/glib-2.0 -I$(STAGING_DIR)/usr/lib/glib-2.0/include/
GLIB_LIBS = -pthread -lgobject-2.0 -lgthread-2.0 -lgmodule-2.0 -lglib-2.0 -lintl  

GST_CFLAGS = -I$(STAGING_DIR)/usr/include/gstreamer-0.10 -I$(STAGING_DIR)/usr/include/libxml2
GST_LIBS = -L$(LIBSDIR) -lgstreamer-0.10 -lgobject-2.0 -lgmodule-2.0 -lgthread-2.0 -pthread -lglib-2.0 -lintl

MIDI9_LIBS = -L$(LIBSDIR) -lmidi9 -ljson-c

ID3TAGS_LIBS = -lid3tag

INCLUDES := -I. -I$(STAGING_DIR)/usr/include -I$(STAGING_DIR)/include  -I$(PROJECTDIR) -I../lib/include -I$(SRCDIR) -I$(COMMONSRCDIR) 

override CFLAGS += $(FLAGS) $(CFLAGS_$(CONFIG)) $(CFLAGS_$(ARCH)) 
override LDFLAGS += $(FLAGS) $(LDFLAGS_$(ARCH)) 

ifdef DEBUG
 LOG =
 DGLOG =
else
 LOG = @echo $(notdir $@) ;
 DGLOG = @
endif

# Compiler
CC = $(TOOLSDIR)/arm-linux-gcc
LD = $(TOOLSDIR)/arm-linux-gcc
AR=ar
RANLIB=ranlib

COMPILE = $(CC) $(CFLAGS) $(INCLUDES)
LINK = $(LD) $(LDFLAGS)

