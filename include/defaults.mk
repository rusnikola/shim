ARCH		?= $(shell $(CC) -dumpmachine | cut -f1 -d- | sed \
			-e s,aarch64,aa64, \
			-e 's,arm.*,arm,' \
			-e s,i[3456789]86,ia32, \
			-e s,x86_64,x64, \
			)
include $(TOPDIR)/include/arch-$(ARCH).mk

COMPILER	?= gcc
CC		= $(CROSS_COMPILE)$(COMPILER)
BUILDDIR	?= $(TOPDIR)
DESTDIR		?=
LD		= $(CROSS_COMPILE)ld
OBJCOPY		= $(CROSS_COMPILE)objcopy
OPENSSL		?= openssl
HEXDUMP		?= hexdump
INSTALL		?= install
PK12UTIL	?= pk12util
CERTUTIL	?= certutil
PESIGN		?= pesign
SBSIGN		?= sbsign
prefix		?= /usr
prefix		:= $(abspath $(prefix))
datadir		?= $(prefix)/share/
PKGNAME		?= shim
ESPROOTDIR	?= boot/efi/
EFIBOOTDIR	?= $(ESPROOTDIR)EFI/BOOT/
TARGETDIR	?= $(ESPROOTDIR)EFI/$(EFIDIR)/
DATATARGETDIR	?= $(datadir)/$(PKGNAME)/$(VERSION)$(DASHRELEASE)/$(ARCH)/
DEBUGINFO	?= $(prefix)/lib/debug/
DEBUGSOURCE	?= $(prefix)/src/debug/
OSLABEL		?= $(EFIDIR)
DEFAULT_LOADER	?= \\\\grub$(ARCH).efi
DASHJ		?= -j$(shell echo $$(($$(grep -c "^model name" /proc/cpuinfo) + 1)))
OBJCOPY_GTE224	= $(shell expr `$(OBJCOPY) --version |grep ^"GNU objcopy" | sed 's/^.*\((.*)\|version\) //g' | cut -f1-2 -d.` \>= 2.24)

OPENSSLDIR	= $(TOPDIR)/Cryptlib/OpenSSL

EFI_INCLUDE	?= /usr/include/efi
EFI_INCLUDES	= -nostdinc \
		  -I$(TOPDIR)/Cryptlib \
		  -I$(TOPDIR)/Cryptlib/Include \
		  -I$(TOPDIR)/Cryptlib/Include/openssl \
		  -I$(EFI_INCLUDE) \
		  -I$(EFI_INCLUDE)/$(ARCH) \
		  -I$(EFI_INCLUDE)/protocol \
		  -I$(TOPDIR)/include \
		  -I$(OPENSSLDIR) \
		  -I$(OPENSSLDIR)/crypto/asn1 \
		  -I$(OPENSSLDIR)/crypto/evp \
		  -I$(OPENSSLDIR)/crypto/modes \
		  -I$(OPENSSLDIR)/crypto/include \
		  -iquote $(TOPDIR) \
		  -iquote $(TOPDIR)/src \
		  -iquote $(OPENSSLDIR) \
		  -iquote $(OPENSSLDIR)/crypto/include \
		  -iquote $(BUILDDIR)/src

EFI_CRT_OBJS 	= $(EFI_PATH)/crt0-efi-$(ARCH).o
EFI_LDS		= $(TOPDIR)/include/elf_$(ARCH)_efi.lds

COMMIT_ID ?= $(shell if [ -e .git ] ; then git log -1 --pretty=format:%H ; elif [ -f commit ]; then cat commit ; else echo master; fi)

OPENSSL_CFLAGS = -D_CRT_SECURE_NO_DEPRECATE \
		 -D_CRT_NONSTDC_NO_DEPRECATE \
		 -DL_ENDIAN \
		 -DOPENSSL_SMALL_FOOTPRINT \
		 -DOPENSSL_FIPS \
		 -DPEDANTIC

CFLAGS		= -ggdb -O0 -fno-stack-protector -fno-strict-aliasing -fpic \
		  -fshort-wchar -Wall -Wsign-compare -Werror -fno-builtin \
		  -Werror=sign-compare -ffreestanding -std=gnu89 \
		  -I$(shell $(CC) $(ARCH_CFLAGS) -print-file-name=include) \
		  "-DDEFAULT_LOADER=L\"$(DEFAULT_LOADER)\"" \
		  "-DDEFAULT_LOADER_CHAR=\"$(DEFAULT_LOADER)\"" \
		  $(EFI_INCLUDES) $(ARCH_CFLAGS) $(OPENSSL_CFLAGS)

ifneq ($(origin OVERRIDE_SECURITY_POLICY), undefined)
	CFLAGS	+= -DOVERRIDE_SECURITY_POLICY
endif

ifneq ($(origin ENABLE_HTTPBOOT), undefined)
	CFLAGS	+= -DENABLE_HTTPBOOT
endif

ifneq ($(origin REQUIRE_TPM), undefined)
	CFLAGS  += -DREQUIRE_TPM
endif

ifneq ($(origin ENABLE_SHIM_CERT),undefined)
	CFLAGS += -DENABLE_SHIM_CERT
endif

LIB_GCC		= $(shell $(CC) $(ARCH_CFLAGS) -print-libgcc-file-name)
EFI_LIBS	= -lefi -lgnuefi --start-group Cryptlib/libcryptlib.a Cryptlib/OpenSSL/libopenssl.a --end-group $(LIB_GCC)
FORMAT		?= --target efi-app-$(LDARCH)
EFI_PATH	?= $(LIBDIR)/gnuefi

MMSTEM		?= mm$(ARCH)
MMNAME		= $(MMSTEM).efi
MMSONAME	= $(MMSTEM).so
FBSTEM		?= fb$(ARCH)
FBNAME		= $(FBSTEM).efi
FBSONAME	= $(FBSTEM).so
SHIMSTEM	?= shim$(ARCH)
SHIMNAME	= $(SHIMSTEM).efi
SHIMSONAME	= $(SHIMSTEM).so
SHIMHASHNAME	= $(SHIMSTEM).hash
BOOTEFINAME	?= BOOT$(ARCH_UPPER).EFI
BOOTCSVNAME	?= BOOT$(ARCH_UPPER).CSV

CFLAGS += "-DEFI_ARCH=L\"$(ARCH)\"" "-DDEBUGDIR=L\"/usr/lib/debug/usr/share/shim/$(ARCH)-$(VERSION)$(DASHRELEASE)/\""

ifneq ($(origin VENDOR_CERT_FILE), undefined)
	CFLAGS += -DVENDOR_CERT_FILE=\"$(VENDOR_CERT_FILE)\"
endif
ifneq ($(origin VENDOR_DBX_FILE), undefined)
	CFLAGS += -DVENDOR_DBX_FILE=\"$(VENDOR_DBX_FILE)\"
endif

LDFLAGS		= --hash-style=sysv -nostdlib -znocombreloc -T $(EFI_LDS) -shared -Bsymbolic -L$(EFI_PATH) -L$(LIBDIR) -LCryptlib -LCryptlib/OpenSSL $(EFI_CRT_OBJS) --build-id=sha1 $(ARCH_LDFLAGS) --no-undefined

define get-config
$(shell git config --local --get "shim.$(1)")
endef

define object-template
$(subst $(TOPDIR),$(BUILDDIR),$(patsubst %.c,%.o,$(2))): $(2)
	$$(CC) $$(CFLAGS) $(3) -c -o $$@ $$<
endef

%.efi : $(BUILDDIR)/%.efi

src/%.o : $(BUILDDIR)/src/%.o

%.crt : $(BUILDDIR)/certdb/%.crt
%.cer : $(BUILDDIR)/certdb/%.cer

%.efi : %.so
ifneq ($(OBJCOPY_GTE224),1)
	$(error objcopy >= 2.24 is required)
endif
	$(OBJCOPY) --file-alignment 512 -D \
		-j .text -j .sdata -j .data -j .data.ident \
		-j .dynamic -j .dynsym -j .rel* \
		-j .rela* -j .reloc -j .eh_frame \
		-j .vendor_cert \
		-j .note.gnu.build-id \
		$(FORMAT) $^ $@
	# I am tired of wasting my time fighting binutils timestamp code.
	dd conv=notrunc bs=1 count=4 seek=$(TIMESTAMP_LOCATION) if=/dev/zero of=$@

%.efi.debug: %.so
ifneq ($(OBJCOPY_GTE224),1)
	$(error objcopy >= 2.24 is required)
endif
	$(OBJCOPY) --file-alignment 512 -D \
		-j .text -j .sdata -j .data -j .data.ident \
		-j .dynamic -j .dynsym -j .rel* \
		-j .rela* -j .reloc -j .eh_frame \
		-j .debug_info -j .debug_abbrev -j .debug_aranges \
		-j .debug_line -j .debug_str -j .debug_ranges \
		-j .note.gnu.build-id \
		$< $@

ifneq ($(origin ENABLE_SBSIGN),undefined)
%.efi.signed: %.efi shim.key shim.crt
	@$(SBSIGN) \
		--key $(BUILDDIR)/certdb/shim.key \
		--cert $(BUILDDIR)/certdb/shim.crt \
		--output $(BUILDDIR)/$@ $(BUILDDIR)/$^
else
.ONESHELL: $(MMNAME).signed $(FBNAME).signed
%.efi.signed: %.efi certdb/secmod.db
	@cd $(BUILDDIR)
	$(PESIGN) -n certdb -i $< -c "shim" -s -o $@ -f
endif

.ONESHELL: %.hash
%.hash : | $(BUILDDIR)
%.hash : %.efi
	@cd $(BUILDDIR)
	$(PESIGN) -i $< -P -h > $@

%.efi %.efi.signed %.efi.debug %.so : | $(BUILDDIR)

.EXPORT_ALL_VARIABLES:
unexport KEYS
unexport FALLBACK_OBJS FALLBACK_SRCS
unexport MOK_OBJS MOK_SOURCES
unexport OBJS ORIG_FALLBACK_SRCS ORIG_SOURCES ORIG_MOK_SOURCES
unexport SOURCES SUBDIRS
unexport TARGET TARGETS
unexport VPATH
