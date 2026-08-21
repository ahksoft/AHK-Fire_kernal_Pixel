#!/usr/bin/env bash

# Constants
WORKDIR="$(pwd)"
RELEASE_DIR="$WORKDIR/artifacts"

KERNEL_NAME="AHK-Fire"
USER="ahksoft"
HOST="AHK-Fire Kernel Pixel"
TIMEZONE="Asia/Damascus"
ANYKERNEL_REPO="https://github.com/ahksoft/AK3-Fire"

KERNEL_DEFCONFIG="gki_defconfig"

KERNEL_BRANCH="${KERNEL_BRANCH:-blu_spark-17}"


# Set timezone
sudo timedatectl set-timezone "$TIMEZONE" || export TZ="$TIMEZONE"

RELEASE="$(date +v%y.%m.%d)${RUN_NUM}"

mkdir -p $RELEASE_DIR

RELEASE_REPO="ahksoft/AHK-Fire_kernal_Pixel"
AK3_ZIP_NAME="$KERNEL_NAME-VARIANT-REL-KVER.zip"
OUTDIR="$WORKDIR/out"
KSRC="$WORKDIR/ksrc"
KERNEL_PATCHES="$WORKDIR/kernel-patches"
PATCHES_DIR="$WORKDIR/patches"

# Import functions
source $WORKDIR/functions.sh

echo "RELEASE_REPO=$RELEASE_REPO" >> $GITHUB_ENV
echo "KERNEL_NAME=${KERNEL_NAME}${RUN_NUM}" >> $GITHUB_ENV
echo "RELEASE_NAME=$KERNEL_NAME $RELEASE" >> $GITHUB_ENV
echo "RELEASE=$RELEASE" >> $GITHUB_ENV

# Logging
BUILD_LOGS="$RELEASE_DIR/build.log"
MAKE_LOGS="$RELEASE_DIR/make.log"
exec > >(tee -a "$BUILD_LOGS") 2>&1

trap 'echo "=== SCRIPT EXIT at $(date) ===" >> "$BUILD_LOGS"' EXIT
trap 'echo "!!! ERROR at line $LINENO: [[$BASH_COMMAND]]" >> "$BUILD_LOGS"' ERR
trap 'echo "!!! Received SIGTERM at $(date) - possible GitHub kill" >> "$BUILD_LOGS"' TERM
trap 'echo "!!! Received SIGINT at $(date)" >> "$BUILD_LOGS"' INT

# Clone kernel source
log "Cloning kernel source from $(simplify_gh_url "$KERNEL_REPO")"
git clone -q --depth=1 --recurse-submodules "$KERNEL_REPO" -b "$KERNEL_BRANCH" "$KSRC"

cd $KSRC
LINUX_VERSION=$(make --no-print-directory kernelversion 2>/dev/null | tail -1 | tr -d '[:space:]')
LINUX_VERSION_CODE=${LINUX_VERSION//./}
DEFCONFIG_FILE=$(find ./arch/arm64/configs -name "$KERNEL_DEFCONFIG")
echo "LINUX_VERSION=$LINUX_VERSION" >> $GITHUB_ENV
cd $WORKDIR

# Set Kernel variant
log "Setting Kernel variant..."
case "$KSU" in
  "SKSU") VARIANT="SukiSU" ;;
  "KSU") VARIANT="KernelSU" ;;
  "KSUN") VARIANT="KernelSU-Next" ;;
  *) VARIANT="KernelSU-Next" ;;
esac
susfs_included && VARIANT+="+SUSFS"
SUSFS_URL="https://gitlab.com/simonpunk/susfs4ksu"
SUSFS_DIR="$WORKDIR/susfs"
SUSFS_PATCHES="${SUSFS_DIR}/kernel_patches"
SUSFS_BRANCH="gki-android14-6.1"
SUSFS_PATCH="gki-android14-6.1"

log "Changelog of repos"
gh api "repos/$KERNEL_REPO/commits?sha=${KERNEL_BRANCH}&per_page=10" --jq '.[] | "- [" + .sha[0:7] + "](" + .html_url + ") " + (.commit.message | split("\n")[0])'\
> "$RELEASE_DIR/kernel_changelog.txt" 2>/dev/null || true
gh api 'repos/KernelSU-Next/KernelSU-Next/commits?sha=dev&per_page=10' --jq '.[] | "- [" + .sha[0:7] + "](" + .html_url + ") " + (.commit.message | split("\n")[0])'\
> "$RELEASE_DIR/ksun_changelog.txt" 2>/dev/null || true

# Download Clang
echo "::group::Downloading Clang..."
CLANG_BIN="$WORKDIR/neutron-clang/bin"
mkdir -p "$WORKDIR/neutron-clang"
cd "$WORKDIR/neutron-clang"
bash <(curl -s "https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman") -S
cd $OLDPWD
if [ ! -d "$CLANG_BIN" ]; then
    error "Clang not found in ${CLANG_BIN}."
    exit 1
fi

export PATH="${CLANG_BIN}:$PATH"
echo "::endgroup::"

# ccache configuration
export CCACHE_DIR="$HOME/.ccache"
export CCACHE_BASEDIR="$WORKDIR"
export CCACHE_NOHARDLINK=true
export CCACHE_COMPILERCHECK=content
export CC="ccache clang"
export CXX="ccache clang++"

ccache --zero-stats
ccache --max-size=5G
ccache --set-config=sloppiness="pch_defines,time_macros,file_macro,include_file_mtime,include_file_ctime"
ccache --set-config=hash_dir=false
ccache --set-config=base_dir="$WORKDIR"
ccache --set-config=compiler_check=content

# Extract clang version
COMPILER_STRING=$(clang -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')
echo "COMPILER_STRING=$COMPILER_STRING" >> $GITHUB_ENV

cd $KSRC

echo "::group::Applied patches"
log "Applying BBRv3 patch"
patch -p1 --fuzz=3 < $KERNEL_PATCHES/bbrv3/bbrv3.patch

log "Applying NTSync patches..."
curl -LSs "https://github.com/WildKernels/kernel_patches/raw/main/common/ntsync/ntsync_base.patch" | patch -p1 --fuzz=3
curl -LSs "https://github.com/WildKernels/kernel_patches/raw/main/common/ntsync/ntsync_compat_android14-6.1.patch" | patch -p1 --fuzz=3
log "NTSync patches applied"

log "BBG included"
wget -qO- "https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh" | bash
sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/selinux/selinux,baseband_guard/ } }' "security/Kconfig"

if [ "$DROIDSPACES" = "true" ] || [ "$NH" = "true" ]; then
  log "Applying DroidSpaces/NetHunter sysvipc patch"
  patch -p1 --fuzz=3 < "$KERNEL_PATCHES/droidspaces/001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch"
fi

if [ "$KSU" = "SKSU" ]; then
  log "SukiSU included"
  if susfs_included; then
    install_ksu "SukiSU-Ultra/SukiSU-Ultra" "builtin"
  else
    install_ksu "SukiSU-Ultra/SukiSU-Ultra" "main"
  fi

  if susfs_included; then
    clone_susfs
    apply_susfs_patches
  fi

fi

if [ "$KSU" = "KSU" ]; then
  log "KernelSU included"
  if susfs_included; then
    VARIANT+="+Multiple-Managers"
    git clone "https://github.com/tiann/KernelSU" && echo "[+] Repository cloned."
    clone_susfs

    cd KernelSU
    git reset --soft HEAD~1
    patch -p1 --fuzz=3 < "$PATCHES_DIR/0001-feat-avc-log-spoofing.patch"
    patch -p1 --fuzz=3 < "$PATCHES_DIR/0001-feat-add-multiple-managers.patch"
    patch -p1 --fuzz=3 < "$PATCHES_DIR/0001-feat-throne_tracker-offload-to-kthread.patch"
    patch -p1 --fuzz=3 < "$SUSFS_PATCHES/KernelSU/10_enable_susfs_for_ksu.patch"
    patch -p1 --fuzz=3 < "$PATCHES_DIR/0001-feat-escape-persistent_allow_list-to-kthread.patch"
    patch -p1 --fuzz=3 < "$PATCHES_DIR/0001-feat-supercalls-allow-userspace-to-pull-list-entries.patch"
    sed -i "/    git pull && echo \"\[+\] Repository updated.\"/d" "kernel/setup.sh"
    git config --global user.email "ahks9f533@gmail.com"
    git config --global user.name "Abir Hasan AHK"
    git add .
    git commit -m "susfs patch"
    cd ..
    bash "KernelSU/kernel/setup.sh" "main"

    apply_susfs_patches
  else
    install_ksu "tiann/KernelSU" "main"
  fi

fi

if [ "$KSU" = "KSUN" ]; then
  log "KernelSU-Next included"
  if susfs_included; then
    install_ksu "pershoot/KernelSU-Next" "dev-susfs"
  else
    install_ksu "KernelSU-Next/KernelSU-Next" "dev"
  fi

  if susfs_included; then
    clone_susfs
    apply_susfs_patches
  fi

fi

echo "VARIANT=$VARIANT" >> $GITHUB_ENV

if [ "$NM" = "true" ]; then
  log "Applying NoMount"
  curl "https://raw.githubusercontent.com/maxsteeel/nomount/refs/heads/dev/kernel/setup.sh" | bash -s dev
fi
echo "::endgroup::"

# Replace Placeholder in zip name
AK3_ZIP_NAME=${AK3_ZIP_NAME//KVER/$LINUX_VERSION}
AK3_ZIP_NAME=${AK3_ZIP_NAME//VARIANT/$VARIANT}

log "Patching custom configs..."
source "$WORKDIR/configs/gki_defconfig.sh"

# set localversion
if [ "${TODO:-kernel}" = "kernel" ]; then
  LATEST_COMMIT_HASH=$(git rev-parse --short HEAD)
  SUFFIX="${RELEASE}/${LATEST_COMMIT_HASH}"
  config --set-str CONFIG_LOCALVERSION "-$KERNEL_NAME/$SUFFIX"
  config --disable CONFIG_LOCALVERSION_AUTO
  sed -i 's/echo "+"/# echo "+"/g' scripts/setlocalversion
fi

# Declare needed variables
export KBUILD_BUILD_USER="$USER"
export KBUILD_BUILD_HOST="$HOST"
export KBUILD_BUILD_TIMESTAMP=$(git -C $KSRC log -1 --format=%cd --date=format-local:'%a %b %d %T %z %Y')
export KCFLAGS="-w"

LINK_CACHE_PATH="/dev/shm/thinlto-cache"
LINKER_SHIM="/tmp/clang-lto-linker"
MAKE_ARGS=(
  LLVM=1
  LLVM_IAS=1
  ARCH=arm64
  CROSS_COMPILE=aarch64-linux-gnu-
  CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
  -j$(nproc --all)
  O="$OUTDIR"
)

if [ "$CLEAN_LTO_CACHE" = "true" ]; then
  rm -rf "$LINK_CACHE_PATH"
  log "ThinLTO cache removed"
fi

if [ "${LTO:-}" = "thinLTO" ]; then
    log "ThinLTO cache enabled"
    mkdir -p "$LINK_CACHE_PATH"
    cat > "$LINKER_SHIM" << SHIM
#!/usr/bin/env bash
JOBCOUNT=\$(( \$(nproc --all) / 2 ))
exec ld.lld "\$@" --thinlto-cache-dir="$LINK_CACHE_PATH" --thinlto-jobs=\$JOBCOUNT
SHIM
    chmod +x "$LINKER_SHIM"
    MAKE_ARGS+=(LD="$LINKER_SHIM" HOSTLD="$LINKER_SHIM")
fi

KERNEL_IMAGE="$OUTDIR/arch/arm64/boot/Image"
MODULE_SYMVERS="$OUTDIR/Module.symvers"
KMI_CHECK="$WORKDIR/py/kmi-check-6.x.py"

echo "::group::Generating config..."
make ${MAKE_ARGS[@]} "$KERNEL_DEFCONFIG"
echo "::endgroup::"

# SUSFS debugging
if susfs_included; then

  log "=== DEBUG: Checking defconfig for SUSFS ==="
  grep -i susfs ./arch/arm64/configs/gki_defconfig || echo "[-] SUSFS NOT FOUND in defconfig!"
  echo ""

  # DEBUG: Check if SUSFS made it to .config
  log "=== DEBUG: Checking .config for SUSFS ==="
  grep CONFIG_KSU_SUSFS $OUTDIR/.config || echo "[-] SUSFS NOT ENABLED in .config!"
  grep CONFIG_KSU_SUSFS_SUS_MAP $OUTDIR/.config || echo "[-] SUSFS_SUS_MAP not enabled!"
  echo ""

  # If SUSFS is in defconfig but not in .config, check dependencies
  if grep -q "CONFIG_KSU_SUSFS" ./arch/arm64/configs/gki_defconfig && ! grep -q "CONFIG_KSU_SUSFS=y" $OUTDIR/.config; then
    log "[!] SUSFS in defconfig but not in .config - checking dependencies..."
    grep "depends on" $(find . -name "Kconfig" -exec grep -l "KSU_SUSFS" {} \;) 2>/dev/null || echo "No dependency info found"
  fi

fi

# Test
if [ "$TEST" = "yes" ]; then
  log "Pipeline test done"
  mkdir -p "$RELEASE_DIR"
  echo "test-${VARIANT}" > "$RELEASE_DIR/test-${VARIANT}.zip"
  exit 0
fi

if [[ $TODO == "defconfig" ]]; then
  log "Copying defconfig..."
  mkdir -p "$RELEASE_DIR"
  cp "$OUTDIR/.config" "$RELEASE_DIR/config-${VARIANT}.txt"
  exit 0
fi

echo "::group::Building kernel..."
make ${MAKE_ARGS[@]} CC="ccache clang" CXX="ccache clang++" > "$MAKE_LOGS" 2>&1
echo "::endgroup::"

# Return to the initial working directory
cd $WORKDIR

# Clone AnyKernel
log "Cloning anykernel from $(simplify_gh_url "$ANYKERNEL_REPO")"
git clone -q --depth=1 $ANYKERNEL_REPO anykernel

# Set kernel string in anykernel
AK3_ZIP_NAME=${AK3_ZIP_NAME//REL/$RELEASE}
sed -i \
  "s/kernel.string=.*/kernel.string=${KERNEL_NAME} ${RELEASE} ${LINUX_VERSION} ${VARIANT} for Google Pixel 6 Pro by Abir Hasan AHK (ahksoft)/g" \
  $WORKDIR/anykernel/anykernel.sh

# Zip the anykernel
cd anykernel
log "Zipping anykernel..."
if [ ! -f "$KERNEL_IMAGE" ];then
  error "$KERNEL_IMAGE not found."
  exit 1
fi
cp "$KERNEL_IMAGE" .
zip -r9 "$WORKDIR/$AK3_ZIP_NAME" ./*
cd $OLDPWD

echo "BASE_NAME=$KERNEL_NAME-$VARIANT" >> $GITHUB_ENV
mkdir -p $RELEASE_DIR
mv $WORKDIR/*.zip $RELEASE_DIR
