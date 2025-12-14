# ====================================================================
# MAKEFILE for 32-bit Protected Mode Kernel with ASM and C Sources
# ====================================================================

# --- Directories ---
BUILD = build
OBJDIR = $(BUILD)/obj
KERNEL = kernel
BOOT = boot

# --- Files ---
OS_IMG = $(BUILD)/os.img
BOOTBIN = $(BUILD)/boot.bin
KERNELBIN = $(BUILD)/kernel.bin
BOOTASM = $(BOOT)/boot.asm

# --- Cross-Compiler Definitions ---
# Change the CC variable to use your actual user path
CC = /home/andr-moreira-lopes/osdev/toolchain/bin/i686-elf-gcc
# Flags: -m32 for 32-bit, -ffreestanding/-nostdlib to skip standard OS libraries
# -I$(KERNEL) ensures header files like fat12.h are found.
CFLAGS = -m32 -ffreestanding -nostdlib -I$(KERNEL) 

# --- KERNEL SOURCE AND OBJECT LISTS (FIXED) ---

# 1. Source lists
KERNEL_ASM_SRCS := $(wildcard $(KERNEL)/*.asm) 
KERNEL_C_SRCS := $(wildcard $(KERNEL)/*.c)

# 2. Object lists (defines what object files must be built)
KERNEL_ASM_OBJS := $(patsubst $(KERNEL)/%.asm, $(OBJDIR)/%.o, $(KERNEL_ASM_SRCS))
KERNEL_C_OBJS := $(patsubst $(KERNEL)/%.c, $(OBJDIR)/%.o, $(KERNEL_C_SRCS))

# 3. Final dependency list for the linker (FIXED: Includes both C and ASM objects)
KERNEL_OBJS := $(KERNEL_ASM_OBJS) $(KERNEL_C_OBJS)


# --- TARGETS ---

# Default target
all: $(OS_IMG)

# 1. Final Disk Image Creation
$(OS_IMG): $(BOOTBIN) $(KERNELBIN)
	dd if=/dev/zero of=$(OS_IMG) bs=512 count=2880
	mkfs.fat -F 12 $(OS_IMG)
	mcopy -i $(OS_IMG) $(KERNELBIN) ::/KERNEL.BIN
	dd if=$(BOOTBIN) of=$(OS_IMG) bs=512 count=1 conv=notrunc

# 2. Assemble Bootloader
$(BOOTBIN): $(BOOTASM)
	mkdir -p $(BUILD)
	nasm -f bin $< -o $@

# 3. Link Kernel from all .o files
# $^ is the automatic variable for all prerequisites (i.e., $(KERNEL_OBJS))
$(KERNELBIN): $(KERNEL_OBJS)
	ld -m elf_i386 -T linker.ld -o $@ --oformat binary $^

# --- PATTERN RULES ---

# 4. Pattern Rule: Assemble ASM files to object files
$(OBJDIR)/%.o: $(KERNEL)/%.asm
	mkdir -p $(OBJDIR)
	nasm -f elf32 $< -o $@

# 5. Pattern Rule: Compile C files to object files (Integrated)
$(OBJDIR)/%.o: $(KERNEL)/%.c
	mkdir -p $(OBJDIR)
	$(CC) $(CFLAGS) -c $< -o $@

# --- UTILITIES ---

# Clean
clean:
	rm -rf $(BUILD)
