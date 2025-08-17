#!/usr/bin/env bash
# Full environment prep for Raspberry Pi Pico 2 (RP2350)
# - Arm (arm-none-eabi) + RISC-V (riscv-none-elf) toolchains
# - pico-sdk clone/update + PICO_SDK_PATH
# - picotool (USB-enabled) + add to PATH (+ sudo-safe symlink)
# - Raspberry Pi OpenOCD fork (RP2350 targets) with internal jimTCL
# - udev rules for Debug Probe + broad RP USB rule (2e8a:*)
# - dialout/plugdev groups
# - Ninja default (Make also available)
# Tested on Ubuntu 22.04/24.04 (x86_64)

set -euo pipefail

# ---------- Versions & paths ----------
XPACK_VER="13.2.0-1"
XPACK_DIR="/opt/xpack-riscv-none-elf-gcc-${XPACK_VER}"
XPACK_TARBALL="xpack-riscv-none-elf-gcc-${XPACK_VER}-linux-x64.tar.gz"
XPACK_URL="https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v${XPACK_VER}/${XPACK_TARBALL}"

WORKDIR="${HOME}/pico-work"
PICO_SDK_DIR="${WORKDIR}/pico-sdk"
PICOTOOL_DIR="${WORKDIR}/picotool"
PICOTOOL_BIN="${PICOTOOL_DIR}/build/picotool"

OPENOCD_DIR="${WORKDIR}/openocd-rpi"
OPENOCD_PREFIX="${OPENOCD_DIR}/install"
OPENOCD_BIN="${OPENOCD_PREFIX}/bin/openocd"

CFG_DIR="${WORKDIR}/openocd-cfg"

# ---------- Helpers ----------
have_cmd(){ command -v "$1" >/dev/null 2>&1; }
append_once_bashrc(){
  local line="$1" file="${HOME}/.bashrc"
  grep -Fxq "$line" "$file" || echo "$line" >> "$file"
}
banner(){ echo; echo "==== $* ===="; }

# ---------- 0) Base packages ----------
banner "Installing base packages (build tools, cmake, ninja, libusb, python, serial utils)"
sudo apt-get update -y
sudo apt-get install -y \
  build-essential git cmake ninja-build pkg-config \
  libusb-1.0-0 libusb-1.0-0-dev wget curl \
  python3 python3-pip minicom usbutils

banner "Installing Arm bare-metal toolchain + GDB"
sudo apt-get install -y \
  gcc-arm-none-eabi binutils-arm-none-eabi libnewlib-arm-none-eabi gdb-multiarch

banner "Installing autotools and dev libs for OpenOCD"
sudo apt-get install -y autoconf automake libtool texinfo libhidapi-dev

# ---------- 1) RISC-V toolchain (xPack) ----------
banner "Installing RISC-V toolchain (xPack riscv-none-elf ${XPACK_VER})"
if [[ ! -d "${XPACK_DIR}" ]]; then
  wget -q "${XPACK_URL}" -O "/tmp/${XPACK_TARBALL}"
  sudo tar -xzf "/tmp/${XPACK_TARBALL}" -C /opt/
fi
export PATH="${XPACK_DIR}/bin:${PATH}"
append_once_bashrc "export PATH=${XPACK_DIR}/bin:\$PATH"

# Persist Pico SDK RISC-V hints (robust CMake detection)
append_once_bashrc "export PICO_GCC_TRIPLE=riscv-none-elf"
append_once_bashrc "export PICO_TOOLCHAIN_PATH=${XPACK_DIR}/bin"
export PICO_GCC_TRIPLE="riscv-none-elf"
export PICO_TOOLCHAIN_PATH="${XPACK_DIR}/bin"

# Quick checks
have_cmd arm-none-eabi-gcc  || { echo "ERROR: arm-none-eabi-gcc not found";  exit 1; }
have_cmd riscv-none-elf-gcc || { echo "ERROR: riscv-none-elf-gcc not found"; exit 1; }

# ---------- 2) pico-sdk ----------
banner "Cloning/updating pico-sdk"
mkdir -p "${WORKDIR}"
if [[ ! -d "${PICO_SDK_DIR}" ]]; then
  git clone https://github.com/raspberrypi/pico-sdk.git "${PICO_SDK_DIR}"
fi
pushd "${PICO_SDK_DIR}" >/dev/null
git fetch --tags
git pull --ff-only
git submodule update --init --recursive
popd >/dev/null
export PICO_SDK_PATH="${PICO_SDK_DIR}"
append_once_bashrc "export PICO_SDK_PATH=${PICO_SDK_DIR}"

# ---------- 3) picotool (USB-enabled) ----------
banner "Building picotool (USB-enabled)"
if [[ ! -d "${PICOTOOL_DIR}" ]]; then
  git clone https://github.com/raspberrypi/picotool.git "${PICOTOOL_DIR}"
fi
# force fresh configure so libusb is detected
rm -rf "${PICOTOOL_DIR}/build"
mkdir -p "${PICOTOOL_DIR}/build"
pushd "${PICOTOOL_DIR}/build" >/dev/null
cmake .. -DPICO_SDK_PATH="${PICO_SDK_DIR}" -DCMAKE_BUILD_TYPE=Release -G Ninja
cmake --build . -j
popd >/dev/null

# Add picotool to PATH for current and future shells
banner "Adding picotool to PATH"
append_once_bashrc "export PATH=${PICOTOOL_DIR}/build:\$PATH"
export PATH="${PICOTOOL_DIR}/build:$PATH"

# Also expose to sudo via a symlink (idempotent)
if [[ -x "${PICOTOOL_BIN}" ]]; then
  sudo ln -sf "${PICOTOOL_BIN}" /usr/local/bin/picotool
fi

# Verify USB subcommands exist (needs libusb)
if ! "${PICOTOOL_BIN}" --help | grep -q "load"; then
  echo "WARNING: picotool appears to be built WITHOUT USB support."
  echo "Rebuild after confirming libusb-1.0-0-dev is installed:"
  echo "  rm -rf ${PICOTOOL_DIR}/build && mkdir ${PICOTOOL_DIR}/build && cd ${PICOTOOL_DIR}/build"
  echo "  cmake .. -DPICO_SDK_PATH=${PICO_SDK_DIR} -DCMAKE_BUILD_TYPE=Release -G Ninja && cmake --build . -j"
fi

# ---------- 4) Raspberry Pi OpenOCD fork (with internal jimTCL) ----------
banner "Building Raspberry Pi OpenOCD fork (RP2350 targets, internal jimTCL)"
if [[ ! -d "${OPENOCD_DIR}" ]]; then
  git clone https://github.com/raspberrypi/openocd.git "${OPENOCD_DIR}"
fi
pushd "${OPENOCD_DIR}" >/dev/null
git pull --ff-only || true
git submodule update --init --recursive
./bootstrap
./configure --prefix="${OPENOCD_PREFIX}" --enable-cmsis-dap --enable-internal-jimtcl
make -j"$(nproc)"
make install
popd >/dev/null
export PATH="${OPENOCD_PREFIX}/bin:${PATH}"
append_once_bashrc "export PATH=${OPENOCD_PREFIX}/bin:\$PATH"

# ---------- 5) udev rules + groups ----------
banner "Installing udev rules (Debug Probe & RP USB) and adding user to groups"
# OpenOCD generic rules
if [[ -f "${OPENOCD_DIR}/contrib/60-openocd.rules" ]]; then
  sudo cp "${OPENOCD_DIR}/contrib/60-openocd.rules" /etc/udev/rules.d/
fi

# Raspberry Pi Debug Probe CMSIS-DAP (common VID:PID 2e8a:000c)
sudo bash -c 'cat >/etc/udev/rules.d/99-rpi-debug-probe.rules' <<'RULES'
SUBSYSTEM=="usb", ATTR{idVendor}=="2e8a", ATTR{idProduct}=="000c", MODE="0666", GROUP="plugdev", SYMLINK+="rpi-debug-probe"
RULES

# Broad permission for all Raspberry Pi USB (covers RP2040/RP2350 BOOTSEL like 2e8a:000f)
sudo bash -c 'cat >/etc/udev/rules.d/99-pico-usb.rules' <<'RULES'
SUBSYSTEM=="usb", ATTR{idVendor}=="2e8a", MODE="0666", GROUP="plugdev"
RULES

sudo udevadm control --reload-rules
sudo udevadm trigger

# Serial/USB groups for access without sudo
sudo usermod -aG dialout "$USER" || true
getent group plugdev >/dev/null 2>&1 || sudo groupadd plugdev
sudo usermod -aG plugdev "$USER" || true
echo "If this is your first run, log out/in (or reboot) so new group memberships take effect."

# ---------- 6) Handy OpenOCD configs ----------
banner "Writing OpenOCD config snippets (CMSIS-DAP + RP2350)"
mkdir -p "${CFG_DIR}"

cat > "${CFG_DIR}/rp2350-arm.cfg" <<'EOF'
# Debug Probe (CMSIS-DAP) + RP2350 (Arm/M33)
interface cmsis-dap
transport select swd
adapter speed 4000

# RP2350 Arm target (from Raspberry Pi OpenOCD fork)
source [find target/rp2350.cfg]

# If unstable, try: adapter speed 1000
EOF

cat > "${CFG_DIR}/rp2350-riscv.cfg" <<'EOF'
# Debug Probe (CMSIS-DAP) + RP2350 (RISC-V/Hazard3)
interface cmsis-dap
transport select swd
adapter speed 4000

# RP2350 RISC-V target (from Raspberry Pi OpenOCD fork)
source [find target/rp2350-riscv.cfg]

# If unstable, try: adapter speed 1000
EOF

# ---------- 7) Summary ----------
banner "Environment ready!"
echo "Arm GCC : $(arm-none-eabi-gcc --version | head -n1)"
echo "RISC-V  : $(riscv-none-elf-gcc --version | head -n1)"
echo "pico-sdk: ${PICO_SDK_PATH}"
echo "picotool: $(command -v picotool)"
echo "openocd : ${OPENOCD_BIN}"
echo
echo "OpenOCD configs:"
echo "  Arm   : ${CFG_DIR}/rp2350-arm.cfg"
echo "  RISC-V: ${CFG_DIR}/rp2350-riscv.cfg"
echo
echo "Next steps:"
echo "  - Unplug/replug the Debug Probe after udev/group changes."
echo "  - Open a new shell or run:  source ~/.bashrc"
echo "  - Example build using Ninja (recommended):"
echo "      mkdir -p build && cd build"
echo "      cmake .. -G Ninja \\"
echo "        -DPICO_SDK_PATH=\$PICO_SDK_PATH \\"
echo "        -DPICO_PLATFORM=rp2350-riscv \\"
echo "        -DPICO_BOARD=pico2"
echo "      ninja"