#!/bin/sh
#### BACKUP IMAGE ####

VERSION="HD51 - 30/04/2017\ncreator of the script Dimitrij (http://forums.openpli.org)\n"
DIRECTORY="$1"
START=$(date +%s)
DATE=`date +%Y%m%d_%H%M`
IMAGEVERSION=`date +%Y%m%d`
MKFS=/bin/tar
BZIP2=/usr/bin/bzip2
PARTED=/usr/sbin/parted
MSDOSNEW=/usr/sbin/mkfs.fat
USEMCOPY="yes"
MCOPY=/usr/bin/mcopy
ROOTFSTYPE="rootfs.tar.bz2"
IMAGETYPE="disk.img"
WORKDIR="$DIRECTORY/bi"
RESIZE2FS=/sbin/resize2fs

if [ -f /etc/issue ] ; then
	ISSUE=`cat /etc/issue | grep . | tail -n 1 ` 
	IMVER=${ISSUE%?????}
elif [ -f /etc/bhversion ] ; then
	ISSUE=`cat /etc/bhversion | grep . | tail -n 1 ` 
	IMVER=${ISSUE%?????}
elif [ -f /etc/vtiversion.info ] ; then
	ISSUE=`cat /etc/vtiversion.info | grep . | tail -n 1 ` 
	IMVER=${ISSUE%?????}
elif [ -f /etc/vtiversion.info ] ; then
	ISSUE=`cat /etc/vtiversion.info | grep . | tail -n 1 ` 
	IMVER=${ISSUE%?????}
elif [ -f /proc/stb/info/vumodel ] && [ -f /etc/version ] ; then
	ISSUE=`cat /etc/version | grep . | tail -n 1 ` 
	IMVER=${ISSUE%?????}
else
	IMVER="unknown"
fi

echo "Script date = $VERSION\n"
echo "Back-up media = $DIRECTORY\n"
df -h "$DIRECTORY"
echo "Back-up date_time = $DATE\n"
echo "Working directory = $WORKDIR\n"
echo -n "Drivers = "
opkg list-installed | grep dvb-modules

CREATE_ZIP="$2"
RECOVERY="$4"
if [ -n "$CREATE_ZIP" ] && [ $CREATE_ZIP = "recovery" ] ; then
	CREATE_ZIP=""
	RECOVERY="$2"
fi
IMAGENAME="$3"
TYPE=UNKNOWN

if [ -f /proc/stb/info/boxtype ] ; then
	MODEL=$( cat /proc/stb/info/boxtype )
	if [ $MODEL = "hd51" ] ; then
		TYPE=MUTANT
		echo "Found Mutant HD51 4K\n"
		#MTD_KERNEL="mmcblk0p2"
		MTD_KERNEL="kernel"
		MTDBOOT="mmcblk0p1"
		python /usr/lib/enigma2/python/Plugins/Extensions/FullBackup/findkerneldevice.py
		KERNEL=`cat /sys/firmware/devicetree/base/chosen/kerneldev` 
		KERNELNAME=${KERNEL:11:7}.bin
		echo "$KERNELNAME = STARTUP_${KERNEL:17:1}"
	elif [ $MODEL = "sf4008" ] ; then
		TYPE=OCTAGON
		echo "Found Octagon SF4008 4K\n"
		MTD_KERNEL="mmcblk0p3"
		KERNELNAME="kernel.bin"
	elif [ $MODEL = "vs1500" ] ; then
		TYPE=VIMASTEC
		echo "Found VIMASTEC VS1500 4K\n"
		#MTD_KERNEL="mmcblk0p2"
		MTD_KERNEL="kernel"
		MTDBOOT="mmcblk0p1"
		python /usr/lib/enigma2/python/Plugins/Extensions/FullBackup/findkerneldevice.py
		KERNEL=`cat /sys/firmware/devicetree/base/chosen/kerneldev` 
		KERNELNAME=${KERNEL:11:7}.bin
	elif [ $MODEL = "et11000" ] ; then
		TYPE=GI
		MODEL="et1x000"
		echo "Found Galaxy Innovations et11000 4K\n"
		MTD_KERNEL="mmcblk0p3"
		KERNELNAME="kernel.bin"
	else
		echo "No supported receiver found!\n"
		exit 0
	fi
	MAINDEST="$DIRECTORY/$MODEL"
	EXTRA="$DIRECTORY/automatic_fullbackup/$DATE"
	echo "Destination        = $MAINDEST\n"
else
	echo "No supported receiver found!\n"
	exit 0
fi

if [ ! -f $MKFS ] ; then
	echo "NO TAR FOUND, ABORTING\n"
	exit 0
fi
if [ ! -f "$BZIP2" ] ; then 
	echo "$BZIP2 not installed yet, now installing\n"
	opkg update > /dev/null 2>&1
	opkg install bzip2 > /dev/null 2>&1
	echo "Exit, try again\n"
	sleep 10
	exit 0
fi

echo "Starting Full Backup!\nOptions control panel will not be available 2-15 minutes.\nPlease wait ..."
echo "--------------------------"

control_c(){
   echo "Control C was pressed, quiting..."
   umount /tmp/bi/root 2>/dev/null
   rmdir /tmp/bi/root 2>/dev/null
   rmdir /tmp/bi 2>/dev/null
   rm -rf "$WORKDIR" 2>/dev/null
   exit 255
}
trap control_c SIGINT

echo "\nWARNING!\n"
echo "To stop creating a backup, press the Menu button.\n"
sleep 2

## PREPARING THE BUILDING ENVIRONMENT
rm -rf "$WORKDIR"
echo "Remove directory   = $WORKDIR\n"
mkdir -p "$WORKDIR"
echo "Recreate directory = $WORKDIR\n"

if [ -n "$RECOVERY" ] && [ $RECOVERY = "recovery" ] ; then
	RUN="yes"
	if [ ! -f "$PARTED" ] ; then 
		echo "$PARTED not installed yet, now installing\n"
		opkg update > /dev/null 2>&1
		opkg install parted
		echo "Stop, try again\n"
		RUN="no"
	fi
	if [ ! -f "$MSDOSNEW" ] ; then
		echo "$MSDOSNEW not installed yet, now installing\n"
		opkg update > /dev/null 2>&1
		opkg install dosfstools
		if [ ! -f "$MSDOSNEW" ] ; then
			SRC="https://raw.githubusercontent.com/Dima73/automatic-full-backup/master/dosfstools/armv71/mkfs.fat"
			DEST=/tmp/mkfs.fat
			if which curl >/dev/null 2>&1 ; then
				curl -o $DEST $SRC
			else
				echo >&2 "install-dosfstools: cannot find curl"
				opkg update && opkg install curl
				if which curl >/dev/null 2>&1 ; then
					curl -o $DEST $SRC
				fi
			fi
			if ! [ -f $DEST ] ; then
				echo >&2 "install-dosfstools: download failed"
			else
				mv /tmp/mkfs.fat /usr/sbin/mkfs.fat
				chmod 755 /usr/sbin/mkfs.fat
				ln -s /usr/sbin/mkfs.fat /usr/sbin/mkfs.msdos
			fi
		fi
		echo "Stop, try again\n"
		RUN="no"
	fi
	if [ ! -f "$MCOPY" ] && [ $USEMCOPY = "yes" ] ; then 
		echo "$MCOPY not installed yet, now installing\n"
		opkg update  > /dev/null 2>&1
		opkg install mtools glibc-gconv-ibm850 libc6  > /dev/null 2>&1
		if [ ! -f "$MCOPY" ] ; then 
			SRC="https://raw.githubusercontent.com/Dima73/automatic-full-backup/master/mtools/armv71/mtools"
			DEST=/tmp/mtools
			if which curl >/dev/null 2>&1 ; then
				curl -o $DEST $SRC
			else
				echo >&2 "install-mtools: cannot find curl"
				opkg update && opkg install curl
				if which curl >/dev/null 2>&1 ; then
					curl -o $DEST $SRC
				fi
			fi
			if ! [ -f $DEST ] ; then
				echo >&2 "install-mtools: download failed"
			else
				mv /tmp/mtools /usr/bin/mtools
				chmod 755 /usr/bin/mtools
				ln -s /usr/bin/mtools /usr/bin/mcopy
			fi
		fi
	echo "Stop, try again\n"
		RUN="no"
	fi
	#if [ ! -f "$RESIZE2FS" ] ; then 
	#	echo "$RESIZE2FS not installed yet, now installing\n"
	#	opkg update > /dev/null 2>&1
	#	opkg install e2fsprogs
	#	echo "Stop, try again\n"
	#	RUN="no"
	#fi
	if [ $RUN = "yes" ] ; then
		echo "Please be patient, a recovery will now be made,\n"
		echo "because of the used filesystem the back-up\n"
		echo "will take about 30 minutes for this system\n"
		GPT_OFFSET="0"
		GPT_SIZE="1024"
		BOOT_PARTITION_OFFSET="$(expr ${GPT_OFFSET} \+ ${GPT_SIZE})"
		BOOT_PARTITION_SIZE="3072"
		KERNEL_PARTITION_OFFSET="$(expr ${BOOT_PARTITION_OFFSET} \+ ${BOOT_PARTITION_SIZE})"
		KERNEL_PARTITION_SIZE="8192"
		ROOTFS_PARTITION_OFFSET="$(expr ${KERNEL_PARTITION_OFFSET} \+ ${KERNEL_PARTITION_SIZE})"
		ROOTFS_PARTITION_SIZE="819200"
		SECOND_KERNEL_PARTITION_OFFSET="$(expr ${ROOTFS_PARTITION_OFFSET} \+ ${ROOTFS_PARTITION_SIZE})"
		SECOND_ROOTFS_PARTITION_OFFSET="$(expr ${SECOND_KERNEL_PARTITION_OFFSET} \+ ${KERNEL_PARTITION_SIZE})"
		THRID_KERNEL_PARTITION_OFFSET="$(expr ${SECOND_ROOTFS_PARTITION_OFFSET} \+ ${ROOTFS_PARTITION_SIZE})"
		THRID_ROOTFS_PARTITION_OFFSET="$(expr ${THRID_KERNEL_PARTITION_OFFSET} \+ ${KERNEL_PARTITION_SIZE})"
		FOURTH_KERNEL_PARTITION_OFFSET="$(expr ${THRID_ROOTFS_PARTITION_OFFSET} \+ ${ROOTFS_PARTITION_SIZE})"
		FOURTH_ROOTFS_PARTITION_OFFSET="$(expr ${FOURTH_KERNEL_PARTITION_OFFSET} \+ ${KERNEL_PARTITION_SIZE})"
		SWAP_PARTITION_OFFSET="$(expr ${FOURTH_ROOTFS_PARTITION_OFFSET} \+ ${ROOTFS_PARTITION_SIZE})"
		EMMC_IMAGE_SIZE="3817472"
		IMAGE_ROOTFS_SIZE="196608"
		EMMC_IMAGE="$WORKDIR/$IMAGETYPE"
		echo " "
		echo "Create: Recovery Fullbackup disk.img"
		echo " "
		dd if=/dev/zero of=${EMMC_IMAGE} bs=1024 count=0 seek=${EMMC_IMAGE_SIZE}
		parted -s ${EMMC_IMAGE} mklabel gpt
		parted -s ${EMMC_IMAGE} unit KiB mkpart boot fat16 ${BOOT_PARTITION_OFFSET} $(expr ${BOOT_PARTITION_OFFSET} \+ ${BOOT_PARTITION_SIZE})
		parted -s ${EMMC_IMAGE} unit KiB mkpart kernel1 ${KERNEL_PARTITION_OFFSET} $(expr ${KERNEL_PARTITION_OFFSET} \+ ${KERNEL_PARTITION_SIZE})
		parted -s ${EMMC_IMAGE} unit KiB mkpart rootfs1 ext2 ${ROOTFS_PARTITION_OFFSET} $(expr ${ROOTFS_PARTITION_OFFSET} \+ ${ROOTFS_PARTITION_SIZE})
		parted -s ${EMMC_IMAGE} unit KiB mkpart kernel2 ${SECOND_KERNEL_PARTITION_OFFSET} $(expr ${SECOND_KERNEL_PARTITION_OFFSET} \+ ${KERNEL_PARTITION_SIZE})
		parted -s ${EMMC_IMAGE} unit KiB mkpart rootfs2 ext2 ${SECOND_ROOTFS_PARTITION_OFFSET} $(expr ${SECOND_ROOTFS_PARTITION_OFFSET} \+ ${ROOTFS_PARTITION_SIZE})
		parted -s ${EMMC_IMAGE} unit KiB mkpart kernel3 ${THRID_KERNEL_PARTITION_OFFSET} $(expr ${THRID_KERNEL_PARTITION_OFFSET} \+ ${KERNEL_PARTITION_SIZE})
		parted -s ${EMMC_IMAGE} unit KiB mkpart rootfs3 ext2 ${THRID_ROOTFS_PARTITION_OFFSET} $(expr ${THRID_ROOTFS_PARTITION_OFFSET} \+ ${ROOTFS_PARTITION_SIZE})
		parted -s ${EMMC_IMAGE} unit KiB mkpart kernel4 ${FOURTH_KERNEL_PARTITION_OFFSET} $(expr ${FOURTH_KERNEL_PARTITION_OFFSET} \+ ${KERNEL_PARTITION_SIZE})
		parted -s ${EMMC_IMAGE} unit KiB mkpart rootfs4 ext2 ${FOURTH_ROOTFS_PARTITION_OFFSET} $(expr ${FOURTH_ROOTFS_PARTITION_OFFSET} \+ ${ROOTFS_PARTITION_SIZE})
		parted -s ${EMMC_IMAGE} unit KiB mkpart swap linux-swap ${SWAP_PARTITION_OFFSET} $(expr ${EMMC_IMAGE_SIZE} \- 1024)
		dd if=/dev/zero of=${WORKDIR}/boot.img bs=1024 count=${BOOT_PARTITION_SIZE}
		/usr/sbin/mkfs.msdos -S 512 ${WORKDIR}/boot.img
		if [ $USEMCOPY = "yes" ] ; then 
			echo "boot emmcflash0.kernel1 'brcm_cma=440M@328M brcm_cma=192M@768M root=/dev/mmcblk0p3 rw rootwait ${MODEL}_4.boxmode=1'" > ${WORKDIR}/STARTUP
			echo "boot emmcflash0.kernel1 'brcm_cma=440M@328M brcm_cma=192M@768M root=/dev/mmcblk0p3 rw rootwait ${MODEL}_4.boxmode=1'" > ${WORKDIR}/STARTUP_1
			echo "boot emmcflash0.kernel2 'brcm_cma=440M@328M brcm_cma=192M@768M root=/dev/mmcblk0p5 rw rootwait ${MODEL}_4.boxmode=1'" > ${WORKDIR}/STARTUP_2
			echo "boot emmcflash0.kernel3 'brcm_cma=440M@328M brcm_cma=192M@768M root=/dev/mmcblk0p7 rw rootwait ${MODEL}_4.boxmode=1'" > ${WORKDIR}/STARTUP_3
			echo "boot emmcflash0.kernel4 'brcm_cma=440M@328M brcm_cma=192M@768M root=/dev/mmcblk0p9 rw rootwait ${MODEL}_4.boxmode=1'" > ${WORKDIR}/STARTUP_4
			/usr/bin/mcopy -i ${WORKDIR}/boot.img -v ${WORKDIR}/STARTUP ::
			/usr/bin/mcopy -i ${WORKDIR}/boot.img -v ${WORKDIR}/STARTUP_1 ::
			/usr/bin/mcopy -i ${WORKDIR}/boot.img -v ${WORKDIR}/STARTUP_2 ::
			/usr/bin/mcopy -i ${WORKDIR}/boot.img -v ${WORKDIR}/STARTUP_3 ::
			/usr/bin/mcopy -i ${WORKDIR}/boot.img -v ${WORKDIR}/STARTUP_4 ::
			dd conv=notrunc if=${WORKDIR}/boot.img of=${EMMC_IMAGE} bs=1024 seek=${BOOT_PARTITION_OFFSET}
		else
			dd conv=notrunc if=/dev/${MTDBOOT} of=${EMMC_IMAGE} bs=1024 seek=${BOOT_PARTITION_OFFSET}
		fi
		MTDROOTFS=$(readlink /dev/root)
		if [ $MTDROOTFS = "mmcblk0p3" ]; then
			MTD_KERNEL="mmcblk0p2"
		fi
		if [ $MTDROOTFS = "mmcblk0p5" ]; then
			MTD_KERNEL="mmcblk0p4"
		fi
		if [ $MTDROOTFS = "mmcblk0p7" ]; then
			MTD_KERNEL="mmcblk0p6"
		fi
		if [ $MTDROOTFS = "mmcblk0p9" ]; then
			MTD_KERNEL="mmcblk0p8"
		fi
		dd conv=notrunc if=/dev/${MTD_KERNEL} of=${EMMC_IMAGE} bs=1024 seek=${KERNEL_PARTITION_OFFSET}
		dd if=/dev/${MTDROOTFS} of=${EMMC_IMAGE} bs=1024 seek=${ROOTFS_PARTITION_OFFSET}
		#echo "Start e2fsck\n"
		#e2fsck -f $WORKDIR/$IMAGETYPE
		#echo "Start resize2fs\n"
		#resize2fs -M $WORKDIR/$IMAGETYPE
	else
		echo "Abort... not installed needs utils\n"
	fi
fi

mkdir -p /tmp/bi/root
echo "Create directory   = /tmp/bi/root\n"
sync
if [ $MODEL = "hd51" ] || [ $MODEL = "vs1500" ] ; then
	MTDROOTFS=$(readlink /dev/root)
	if [ $MTDROOTFS = "mmcblk0p3" ]; then
		MTD_KERNEL="mmcblk0p2"
	fi
	if [ $MTDROOTFS = "mmcblk0p5" ]; then
		MTD_KERNEL="mmcblk0p4"
	fi
	if [ $MTDROOTFS = "mmcblk0p7" ]; then
		MTD_KERNEL="mmcblk0p6"
	fi
	if [ $MTDROOTFS = "mmcblk0p9" ]; then
		MTD_KERNEL="mmcblk0p8"
	fi
	mount /dev/${MTDROOTFS} /tmp/bi/root
else
	mount --bind / /tmp/bi/root
fi


dd if=/dev/$MTD_KERNEL of=$WORKDIR/$KERNELNAME > /dev/null 2>&1
echo "Kernel resides on /dev/$MTD_KERNEL\n" 

echo "Start creating rootfs.tar\n"
$MKFS -cf $WORKDIR/rootfs.tar -C /tmp/bi/root --exclude=/var/nmbd/* .
$BZIP2 $WORKDIR/rootfs.tar

TSTAMP="$(date "+%Y-%m-%d-%Hh%Mm")"

if [ $TYPE = "MUTANT" -o $TYPE = "VIMASTEC" -o $TYPE = "OCTAGON" -o $TYPE = "GI" ] ; then
	rm -rf "$MAINDEST"
	echo "Removed directory  = $MAINDEST\n"
	mkdir -p "$MAINDEST" 
	echo "Created directory  = $MAINDEST\n"
	mv "$WORKDIR/$KERNELNAME" "$MAINDEST/$KERNELNAME"
	mv "$WORKDIR/$ROOTFSTYPE" "$MAINDEST/$ROOTFSTYPE"
	if [ $TYPE = "GI" ] ; then
		echo "rename this file to 'force' to be able to flash this backup" > "$MAINDEST/noforce"
		if [ -f /boot/update.bin ] ; then
			cp /boot/update.bin "$MAINDEST/update.bin"
			echo "this file enable kernel update" > "$MAINDEST/partition.update"
		fi
	fi
	if [ -n "$RECOVERY" ] && [ $RECOVERY = "recovery" ] && [ -f $WORKDIR/$IMAGETYPE ] ; then
		mv "$WORKDIR/$IMAGETYPE" "$MAINDEST/$IMAGETYPE"
	fi
	echo "$MODEL-$IMAGEVERSION" > "$MAINDEST/imageversion"
	if [ -z "$CREATE_ZIP" ] ; then
		mkdir -p "$EXTRA/$MODEL"
		echo "Created directory  = $EXTRA/$MODEL\n"
		touch "$MAINDEST/$IMVER"
		cp -r "$MAINDEST" "$EXTRA"
		touch "$DIRECTORY/automatic_fullbackup/.timestamp"
	else
		if [ $CREATE_ZIP != "none" ] ; then
			echo "Create zip archive..."
			cd $DIRECTORY && $CREATE_ZIP -r $DIRECTORY/backup-$IMAGENAME-$MODEL-$TSTAMP.zip . -i /$MODEL/*
			cd
		fi
	fi
	if [ -f "$MAINDEST/rootfs.tar.bz2" -a -f "$MAINDEST/$KERNELNAME" ] ; then
		echo " "
		echo "BACK-UP MADE SUCCESSFULLY IN: $MAINDEST\n"
	else
		echo " "
		echo "Image creation FAILED!\n"
	fi
fi

umount /tmp/bi/root
rmdir /tmp/bi/root
rmdir /tmp/bi
rm -rf "$WORKDIR"
sleep 5
END=$(date +%s)
DIFF=$(( $END - $START ))
MINUTES=$(( $DIFF/60 ))
SECONDS=$(( $DIFF-(( 60*$MINUTES ))))
if [ $SECONDS -le  9 ] ; then 
	SECONDS="0$SECONDS"
fi
echo "BACKUP FINISHED IN $MINUTES.$SECONDS MINUTES\n"
exit 
