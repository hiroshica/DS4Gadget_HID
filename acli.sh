#!/bin/bash

build_all() {
    for board in "${BOARDS[@]}" ; do
        export ARDUINO_BOARD_FQBN=${board}
        ARDUINO_BOARD_FQBN2=${ARDUINO_BOARD_FQBN//:/.}
        arduino-cli cache clean
        rm -rf ${ACLI_TMP}/arduino-core-cache
        find ${ACLI_TMP} -type d -name 'arduino-sketch-*' -print0 |xargs -0 rm -rf
        find ${MYPROJECT_EXAMPLES} -type d -name build -print0 |xargs -0 rm -rf
        find ${MYPROJECT_EXAMPLES} -name '*.ino' -print0 | xargs -0 -n 1 arduino-cli compile --verbose --fqbn ${board} ${2}
        # Convert all BIN to UF2 for drag-and-drop burning on boards with UF2 boot loader
        for MYSKETCH in ${MYPROJECT_EXAMPLES}/* ; do
            pushd ${MYSKETCH}/build/${ARDUINO_BOARD_FQBN2}
            for i in *.bin ; do
                if [[ -f $i ]] ; then
                    if [[ ${board} == *"m4"* ]] ; then
                        ${MYPROJECT_TOOLS}/uf2conv.py -c -b 0x4000 $i -o $i.uf2
                    else
                        ${MYPROJECT_TOOLS}/uf2conv.py -c $i -o $i.uf2
                    fi
                fi
            done
            FIRMWARE=${MYSKETCH}/firmware/${1}/${ARDUINO_BOARD_FQBN2}
            if [[ ! -d ${FIRMWARE} ]] ; then
                mkdir -p ${FIRMWARE}
            fi
            mv *.ino.bin.uf2 ${FIRMWARE}
            popd
        done
    done
}

ACLI_TMP="$HOME/tmp"
export TMP=${ACLI_TMP}
#echo ${ACLI_TMP}
mkdir ${ACLI_TMP}

ARDDIR=${ACLI_TMP}/acli_ds4gadget_hid_$$
export ARDUINO_BOARD_MANAGER_ADDITIONAL_URLS="https://adafruit.github.io/arduino-board-index/package_adafruit_index.json"
export ARDUINO_DIRECTORIES_DATA="${ARDDIR}/data"
export ARDUINO_DIRECTORIES_DOWNLOADS="${ARDDIR}/downloads"
export ARDUINO_DIRECTORIES_USER="${ARDDIR}/user"
export MYPROJECT_EXAMPLES="${PWD}/examples"
export MYPROJECT_SRC="${PWD}/src"
export MYPROJECT_TOOLS="${PWD}/tools"
export HID_PROJECT=$ARDUINO_DIRECTORIES_USER/libraries/HID-Project/src
arduino-cli core update-index
# The latest version does not work. Use this version
arduino-cli core install adafruit:samd@1.5.14
#arduino-cli core install arduino:mbed:pico
arduino-cli core list
arduino-cli lib install Bounce2
arduino-cli lib install "Adafruit DotStar"
# Use the latest version from github to make SAMD work.
git clone https://github.com/NicoHood/HID ${ARDUINO_DIRECTORIES_USER}/libraries/HID-Project
# Merge this project's files into HID-Project
ln -sf $MYPROJECT_SRC/SingleReport/* $HID_PROJECT/SingleReport
ln -sf $MYPROJECT_SRC/HID-APIs/* $HID_PROJECT/HID-APIs
sed -i '/^#include "SingleReport\/SingleGamepad.h"/a #include "SingleReport/SingleDS4Gamepad.h"' $HID_PROJECT/HID-Project.h
# Disable CDC ACM (USB Serial)
find ${ARDUINO_DIRECTORIES_DATA} -name USBDesc.h -print0 | xargs -0 sed -i 's/^#define.*CDC_ENABLED.*$/\/\/#define CDC_ENABLED/'
# Fix USB class/subclass/protocol
find ${ARDUINO_DIRECTORIES_DATA} -name USBCore.cpp -print0 | xargs -0 sed -i -e 's/bool _cdcComposite.*;/bool _cdcComposite = false;/;/if (setup.wLength == 8)/i #ifdef CDC_ENABLED' -e '/_cdcComposite = 1/a #endif'
# Compile all examples for all boards
BOARDS=('adafruit:samd:adafruit_trinket_m0' 'adafruit:samd:adafruit_itsybitsy_m0' 'adafruit:samd:adafruit_itsybitsy_m4' 'arduino:mbed:pico' 'arduino:mbed_rp2040:pico')
build_all viddefault >error_viddefault 2>&1
# Use Dual Shock 4 VID/PID
build_all vidds4 "--build-properties build.vid=0x054c,build.pid=0x09cc"  >error_vidds4 2>&1

rm -rf ${ACLI_TMP}
