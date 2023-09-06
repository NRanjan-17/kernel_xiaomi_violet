#!/bin/bash

# Telegram Config
TOKEN="$API_BOT"  # Bot Token
CHATID="$CHATID" # Chat id of telegram channel/group
BOT_MSG_URL="https://api.telegram.org/bot${TOKEN}/sendMessage"
BOT_BUILD_URL="https://api.telegram.org/bot${TOKEN}/sendDocument"
BOT_STICKER_URL="https://api.telegram.org/bot${TOKEN}/sendSticker"

kernel_dir="${PWD}"
CCACHE=$(command -v ccache)
objdir="${kernel_dir}/out"
anykernel=$HOME/anykernel
builddir="${kernel_dir}/build"
ZIMAGE=$kernel_dir/out/arch/arm64/boot/Image.gz-dtb
kernel_name="HYPER_KERNEL-v1.4_VIOLET"
zip_name="$kernel_name-$(date +"%d%m%Y-%H%M").zip"

# Build Machine details
cores=$(nproc --all)
os=$(cat /etc/issue)
time=$(TZ="Asia/Kolkata" date "+%a %b %d %r")

# send saxx msgs to tg
tg_post_msg() {
  curl -s -X POST "$BOT_MSG_URL" -d chat_id="$CHATID" \
    -d "disable_web_page_preview=true" \
    -d "parse_mode=html" \
    -d text="$1"

}

# send build to tg
tg_post_build()
{
	#Post MD5Checksum alongwith for easeness
	MD5CHECK=$(md5sum "$1" | cut -d' ' -f1)

	#Show the Checksum alongwith caption
	curl --progress-bar -F document=@"$1" "$BOT_BUILD_URL" \
	-F chat_id="$CHATID"  \
	-F "disable_web_page_preview=true" \
	-F "parse_mode=Markdown" \
	-F caption="$2 | *MD5 Checksum : *\`$MD5CHECK\`"
}

# send a nice sticker ro act as a sperator between builds
tg_post_sticker() {
  curl -s -X POST "$BOT_STICKER_URL" -d chat_id="$CHATID" \
    -d sticker="CAACAgIAAxkBAAEluXNk-J9cz-fa-UWMdw6gOG0Dyv7tMAAChwYAAtJaiAE3y9LflkkmbzAE"
}

#start off by sending a trigger msg
tg_post_sticker
tg_post_msg "<b>Kernel Build Triggered ⌛</b>%0A<b>===============</b>%0A<b>Kernel : </b><code>$kernel_name</code>%0A<b>Machine : </b><code>$os</code>%0A<b>Cores : </b><code>$cores</code>%0A<b>Time : </b><code>$time</code>"

TC_DIR=$HOME/tc/
CLANG_DIR=$TC_DIR/clang-r487747c
export CONFIG_FILE="vendor/violet-perf_defconfig"
export ARCH="arm64"
export KBUILD_BUILD_HOST=17
export KBUILD_BUILD_USER=HyperPower

export PATH="$CLANG_DIR/bin:$PATH"

if ! [ -d "$TC_DIR" ]; then
    echo "Toolchain not found! Cloning to $TC_DIR..."
    tg_post_msg "<code>Toolchain not found! Cloning toolchain</code>"
    if ! git clone -q --depth=1 --single-branch https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 -b master $TC_DIR; then
        echo "Cloning failed! Aborting..."
        exit 1
    fi
fi

# Colors
NC='\033[0m'
RED='\033[0;31m'
LRD='\033[1;31m'
LGR='\033[1;32m'

make_defconfig()
{
    START=$(date +"%s")
    echo -e ${LGR} "########### Generating Defconfig ############${NC}"
    make -s ARCH=${ARCH} O=${objdir} ${CONFIG_FILE} -j$(nproc --all)
}
compile()
{
    cd ${kernel_dir}
    echo -e ${LGR} "######### Compiling kernel #########${NC}"
    make -j$(nproc --all) \
    O=out \
    ARCH=${ARCH}\
    CC="ccache clang" \
    CLANG_TRIPLE="aarch64-linux-gnu-" \
    CROSS_COMPILE="aarch64-linux-gnu-" \
    CROSS_COMPILE_ARM32="arm-linux-gnueabi-" \
    LLVM=1 \
    LLVM_IAS=1 \
    2>&1 | tee error.log

}

completion() {
  cd ${objdir}
  COMPILED_IMAGE=arch/arm64/boot/Image.gz-dtb
  COMPILED_DTBO=arch/arm64/boot/dtbo.img
  if [[ -f ${COMPILED_IMAGE} && ${COMPILED_DTBO} ]]; then

    git clone -q https://github.com/NRanjan-17/AnyKernel3 $anykernel

    mv -f $ZIMAGE ${COMPILED_DTBO} $anykernel

    cd $anykernel
    find . -name "*.zip" -type f
    find . -name "*.zip" -type f -delete
    zip -r AnyKernel.zip *
    mv AnyKernel.zip $zip_name
    mv $anykernel/$zip_name $HOME/$zip_name
    rm -rf $anykernel
    END=$(date +"%s")
    DIFF=$(($END - $START))
    BUILDTIME=$(echo $((${END} - ${START})) | awk '{print int ($1/3600)" Hours:"int(($1/60)%60)"Minutes:"int($1%60)" Seconds"}')
    tg_post_build "$HOME/$zip_name" "Build took : $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)"
    tg_post_msg "<code>Compiled successfully</code>"
    curl --upload-file $HOME/$zip_name https://free.keep.sh
    echo
    echo -e ${LGR} "############################################"
    echo -e ${LGR} "############# OkThisIsEpic!  ##############"
    echo -e ${LGR} "############################################${NC}"
  else
    tg_post_build "$kernel_dir/error.log" "$CHATID" "Debug Mode Logs"
    tg_post_msg "<code>Compilation failed</code>"
    echo -e ${RED} "############################################"
    echo -e ${RED} "##         This Is Not Epic :'(           ##"
    echo -e ${RED} "############################################${NC}"
  fi
}
make_defconfig
if [ $? -eq 0 ]; then
  tg_post_msg "<code>Defconfig generated successfully</code>"
fi
compile
completion
cd ${kernel_dir}
