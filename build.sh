#!/bin/bash

trap "echo ERROR;   exit" ERR

TOP=`pwd`

prepare()
{
    sudo apt-get install gcc-aarch64-linux-gnu > /dev/null
    sudo apt-get install device-tree-compiler > /dev/null
    sudo apt-get install bison > /dev/null
    sudo apt-get install genext2fs > /dev/null
    sudo apt-get install bc > /dev/null
}

download-uboot()
{
    mkdir -p $TOP/download
    cd $TOP/download

    if [ ! -e u-boot-2017.09.tar.bz2 ]; then
        wget ftp://ftp.denx.de/pub/u-boot/u-boot-2017.09.tar.bz2
    fi

    cd $TOP
}

extract-uboot()
{
    mkdir -p $TOP/build-uboot
    cd $TOP/build-uboot

    if [ ! -e u-boot-2017.09 ]; then
        tar xjvf $TOP/download/u-boot-2017.09.tar.bz2
    fi

    cd $TOP
}

build-uboot()
{
    cd $TOP/build-uboot/u-boot-2017.09

    export ARCH=arm64
    export CROSS_COMPILE=aarch64-linux-gnu-
    make rpi_3_defconfig
    make all

    mkdir -p $TOP/dist
    cp -pf u-boot.bin $TOP/dist

    cd $TOP
}

clone-xvisor()
{
    mkdir -p $TOP/source-xvisor
    cd $TOP/source-xvisor
    if [ ! -e xvisor ]; then
        git clone https://github.com/xvisor/xvisor.git
        cd xvisor
        git submodule init
        git submodule update
    else
        :
    fi

    cd $TOP
}

build-xvisor()
{
    cd $TOP/source-xvisor/xvisor/

    export CROSS_COMPILE=aarch64-linux-gnu-
    if [ ! -e build/openconf/.config ]; then
        make ARCH=arm generic-v8-defconfig
        make
        mkimage -A arm64 -O linux -T kernel -C none -a 0x00080000 -e 0x00080000 -n Xvisor \
                -d build/vmm.bin build/uvmm.bin
        mkdir -p $TOP/dist
        cp -pf build/uvmm.bin $TOP/dist

        make -C tests/arm64/virt-v8/basic
        ls -l ./build/tests/arm64/virt-v8/basic/firmware.bin 
    fi

    mkdir -p $TOP/dist
    cp -pf $TOP/source-xvisor/xvisor/build/arch/arm/board/generic/dts/broadcom/bcm2837-rpi-3-b.dtb $TOP/dist

    cd $TOP
}

download-linux()
{
    mkdir -p $TOP/download
    cd $TOP/download

    if [ ! -e linux-v4.15.tar.gz ]; then
        wget https://github.com/torvalds/linux/archive/v4.15.tar.gz
        mv v4.15.tar.gz linux-v4.15.tar.gz
    fi

    cd $TOP
}

extract-linux()
{
    mkdir -p $TOP/source-linux
    cd $TOP/source-linux

    if [ ! -e linux-4.15 ]; then
        tar xzvf $TOP/download/linux-v4.15.tar.gz
    fi

    cd $TOP
}

build-linux()
{
    mkdir -p build-linux
    cp $TOP/source-xvisor/xvisor/tests/arm64/virt-v8/linux/linux-4.15_defconfig build-linux/.config
    
    cd $TOP/source-linux/linux-4.15

    export ARCH=arm64
    export CROSS_COMPILE=aarch64-linux-gnu-
    make O=$TOP/build-linux ARCH=arm64 oldconfig
    make O=$TOP/build-linux ARCH=arm64 Image dtbs

    ls -l $TOP/build-linux/arch/arm64/boot/Image

    cd $TOP
}

download-busybox()
{
    mkdir -p $TOP/download
    cd $TOP/download

    if [ ! -e busybox-1_27_2.tar.gz ]; then
        wget https://github.com/mirror/busybox/archive/1_27_2.tar.gz
        mv 1_27_2.tar.gz busybox-1_27_2.tar.gz
    fi

    cd $TOP
}

extract-busybox()
{
    mkdir -p $TOP/build-busybox
    cd $TOP/build-busybox

    if [ ! -e busybox-1_27_2 ]; then
        tar xzvf $TOP/download/busybox-1_27_2.tar.gz
    fi

    cd $TOP
}

build-busybox()
{
    cd $TOP/build-busybox/busybox-1_27_2

    export CROSS_COMPILE=aarch64-linux-gnu-
    if [ ! -e .config ]; then
        cp $TOP/source-xvisor/xvisor/tests/common/busybox/busybox-1.27.2_defconfig .config
        make oldconfig
    fi
    make install

    mkdir -p ./_install/etc/init.d
    mkdir -p ./_install/dev
    mkdir -p ./_install/proc
    mkdir -p ./_install/sys
    ln -sf /sbin/init ./_install/init
    cp -f $TOP/source-xvisor/xvisor/tests/common/busybox/fstab ./_install/etc/fstab
    cp -f $TOP/source-xvisor/xvisor/tests/common/busybox/rcS ./_install/etc/init.d/rcS
    cp -f $TOP/source-xvisor/xvisor/tests/common/busybox/motd ./_install/etc/motd
    cp -f $TOP/source-xvisor/xvisor/tests/common/busybox/logo_linux_clut224.ppm ./_install/etc/logo_linux_clut224.ppm
    cp -f $TOP/source-xvisor/xvisor/tests/common/busybox/logo_linux_vga16.ppm ./_install/etc/logo_linux_vga16.ppm

    cd ./_install; find ./ | cpio -o -H newc | gzip -9 > $TOP/build-busybox/busybox-1_27_2/rootfs.img
    ls -l $TOP/build-busybox/busybox-1_27_2/rootfs.img

    cd $TOP
}

build-disk()
{
    mkdir -p $TOP/build-disk/disk/tmp
    mkdir -p $TOP/build-disk/disk/system

    cd $TOP/source-xvisor/xvisor
    cp -f ./docs/banner/roman.txt $TOP/build-disk/disk/system/banner.txt
    cp -f ./docs/logo/xvisor_logo_name.ppm $TOP/build-disk/disk/system/logo.ppm
    mkdir -p $TOP/build-disk/disk/images/arm64/virt-v8
    ./build/tools/dtc/bin/dtc -I dts -O dtb -o $TOP/build-disk/disk/images/arm64/virt-v8x2.dtb ./tests/arm64/virt-v8/virt-v8x2.dts
    cp -f ./build/tests/arm64/virt-v8/basic/firmware.bin $TOP/build-disk/disk/images/arm64/virt-v8/firmware.bin
    cp -f ./tests/arm64/virt-v8/linux/nor_flash.list $TOP/build-disk/disk/images/arm64/virt-v8/nor_flash.list
    cp -f ./tests/arm64/virt-v8/linux/cmdlist $TOP/build-disk/disk/images/arm64/virt-v8/cmdlist
    cp -f ./tests/arm64/virt-v8/xscript/one_novgic_guest_virt-v8.xscript $TOP/build-disk/disk/boot.xscript
    cp -f $TOP/build-linux/arch/arm64/boot/Image $TOP/build-disk/disk/images/arm64/virt-v8/Image
    ./build/tools/dtc/bin/dtc -I dts -O dtb -o $TOP/build-disk/disk/images/arm64/virt-v8/virt-v8.dtb ./tests/arm64/virt-v8/linux/virt-v8.dts
    cp -f $TOP/build-busybox/busybox-1_27_2/rootfs.img $TOP/build-disk/disk/images/arm64/rootfs.img

    # genext2fs -B 1024 -b 32768 -d $TOP/build-disk/disk $TOP/build-disk//disk.img
    genext2fs -B 1024 -b 16384 -d $TOP/build-disk/disk $TOP/build-disk/disk.img
    mkimage -A arm64 -O linux -T ramdisk -a 0x00000000 -n "Xvisor Ramdisk" -d $TOP/build-disk/disk.img $TOP/build-disk/udisk.img

    mkdir -p $TOP/dist
    cp -pf $TOP/build-disk/udisk.img $TOP/dist/

    cd $TOP
}


#
# main
#
if [ .$1 == .clean ]; then
    rm -rf build-busybox
    rm -rf build-disk
    rm -rf build-linux
    rm -rf build-uboot
    rm -rf build-xvisor
    rm -rf dist
    rm -rf source-linux
    rm -rf source-xvisor
    exit
fi

prepare
download-uboot
extract-uboot
build-uboot

clone-xvisor
build-xvisor

download-linux
extract-linux
build-linux

download-busybox
extract-busybox

download-busybox
extract-busybox
build-busybox

build-disk

ls -l dist/
