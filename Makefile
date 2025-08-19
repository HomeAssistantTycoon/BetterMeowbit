##
## Main BetterMeowbit Makefile
##

-include Makefile.user

BL_BASE   ?= $(wildcard .)
LIBOPENCM3 ?= $(wildcard libopencm3)

CC        = arm-none-eabi-gcc
OBJCOPY   = arm-none-eabi-objcopy
OPENOCD   ?= openocd
JTAGCONFIG ?= interface/stlink-v2.cfg

export BOARD ?= f401
-include boards/$(BOARD)/board.mk

FN ?= f4
CPUTYPE ?= STM32F401
CPUTYPE_SHORT ?= STM32F4
CPUFLAGS ?= -mcpu=cortex-m4 -mfloat-abi=hard -mfpu=fpv4-sp-d16

LINKER_FILE ?= linker/stm32$(FN).ld
ifeq ($(origin EXTRAFLAGS), undefined)
	EXTRAFLAGS ?= -D$(CPUTYPE)
else
	EXTRAFLAGS += -D$(CPUTYPE)
endif

export FLAGS = -std=gnu99 \
	-Os -g -Wundef -Wall -fno-builtin \
	-I$(LIBOPENCM3)/include \
	-Iboards/$(BOARD) \
	-ffunction-sections \
	-nostartfiles \
	-lnosys \
	-Wl,-gc-sections \
	-Wl,-g \
	-Wno-unused \
	-Werror \
	-mthumb $(CPUFLAGS) \
	-D$(CPUTYPE_SHORT) \
	-T$(LINKER_FILE) \
	-L$(LIBOPENCM3)/lib \
	-lopencm3_stm32$(FN) \
	$(EXTRAFLAGS)

COMMON_SRCS = bl.c usb.c usb_msc.c ghostfat.c dmesg.c screen.c images.c \
              settings.c hf2.c support.c webusb.c winusb.c util.c flashwarning.c

SRCS = $(COMMON_SRCS) main_$(FN).c
OBJS := $(patsubst %.c,%.o,$(SRCS))
DEPS := $(OBJS:.o=.d)

OPENOCDALL = $(OPENOCD) -f $(JTAGCONFIG) -f target/stm32$(FN)x.cfg

all: build-bl sizes

clean:
	cd $(LIBOPENCM3) && make --no-print-directory clean && cd ..
	rm -f *.elf *.bin
	rm -rf build

OCM3FILE = $(LIBOPENCM3)/include/libopencm3/stm32/$(FN)/nvic.h

build-bl: $(MAKEFILE_LIST) $(OCM3FILE) do-build

$(OCM3FILE):
	$(MAKE) checksubmodules
	@bash -lc '$(MAKE) -C $(LIBOPENCM3) lib'

.PHONY: checksubmodules
checksubmodules: updatesubmodules
	$(Q) ($(BL_BASE)/Tools/check_submodules.sh)

.PHONY: updatesubmodules
updatesubmodules:
	$(Q) (git submodule init)
	$(Q) (git submodule update)

flash: upload
burn: upload
b: burn
f: flash

upload: build-bl flash-bootloader

BMP = $(shell ls -1 /dev/cu.usbmodem*1 | head -1)
BMP_ARGS = -ex "target extended-remote $(BMP)" -ex "mon tpwr enable" -ex "mon swdp_scan" -ex "attach 1"
GDB = arm-none-eabi-gdb

flash-ocd: all
	$(OPENOCDALL) -c "program build/$(BOARD)/bootloader.elf verify reset exit "

flash-bootloader:
	$(GDB) $(BMP_ARGS) -ex "load" -ex "quit" build/$(BOARD)/bootloader.elf

gdb:
	$(GDB) $(BMP_ARGS) build/$(BOARD)/bootloader.elf

.PHONY: sizes
sizes:
	@-find build/*/ -name '*.elf' -type f | xargs size 2> /dev/null || :

