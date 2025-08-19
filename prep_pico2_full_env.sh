#!/usr/bin/env bash
# Full environment prep for Raspberry Pi Pico 2 (RP2350)
# - Arm (arm-none-eabi) + RISC-V (riscv-none-elf) toolchains
# - pico-sdk clone/update + PICO_SDK_PATH
# - picotool (USB-enabled) built AND INSTALLED as a CMake package
# - Raspberry Pi OpenOCD fork (RP2350 targets) with internal jimTCL
# - udev rules for Debug Probe + broad RP USB rule (2e8a:*)
# - dialout/plugdev groups
# - Ninja default (Make also available)
# - PATH + CMAKE_PREFIX_PATH persisted so CMake can find picotool
# Tested on Ubuntu 22.04/24.04 (x86_64)

set -euo pipefail

XPACK_VER="13.2.0-1"
XPACK_DIR="/opt/xpack-riscv-none-elf-gcc-${XPACK_VER}"
XPACK_TARBALL="xpack-riscv-none-elf-gcc-${XPACK_VER}-linux-x64.tar.gz"
XPACK_URL="https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v${XPACK_VER}/${XPACK_TARBALL}"

WORKDIR="${HOME}/pico-work"
PICO_SDK_DIR="${WORKDIR}/pico-sdk"

PICOTOOL_DIR="${WORKDIR}/picotool"
PICOTOOL_BUILD="${PICOTOOL_DIR}/build"
PICOTOOL_INSTALL="${PICOTOOL_DIR}/install"
PICOTOOL_BIN="${PICOTOOL_BUILD}/picotool"

OPENOCD_DIR="${WORKDIR}/openocd-rpi"
OPENOCD_PREFIX="${OPENOCD_DIR}/install"
OPENOCD_BIN="${OPENOCD_PREFIX}/bin/openocd"

CFG_DIR="${WORKDIR}/openocd-cfg"

have_cmd(){ command -v "$1" >/dev/null 2>&1; }
append_once_bashrc(){ local l="$1" f="${HOME}/.bashrc"; grep -Fxq "$l" "$f" || echo "$l" >> "$f"; }
banner(){ echo; echo "==== $* ===="; }

banner "Installing base packages"
sudo apt-get update -y
sudo apt-get install -y build-essential git cmake ninja-build pkg-config \
  libusb-1.0-0 libusb-1.0-0-dev wget curl python3 python3-pip minicom usbutils \
  gcc-arm-none-eabi binutils-arm-none-eabi libnewlib-arm-none-eabi gdb-multiarch \
  autoconf automake libtool texinfo libhidapi-dev

banner "Installing RISC-V toolchain (xPack ${XPACK_VER})"
if [[ ! -d "${XPACK_DIR}" ]]; then
  wget -q "${XPACK_URL}" -O "/tmp/${XPACK_TARBALL}"
  sudo tar -xzf "/tmp/${XPACK_TARBALL}" -C /opt/
fi
export PATH="${XPACK_DIR}/bin:${PATH}"
append_once_bashrc "export PATH=${XPACK_DIR}/bin:\$PATH"
append_once_bashrc "export PICO_GCC_TRIPLE=riscv-none-elf"
append_once_bashrc "export PICO_TOOLCHAIN_PATH=${XPACK_DIR}/bin"
export PICO_GCC_TRIPLE="riscv-none-elf"
export PICO_TOOLCHAIN_PATH="${XPACK_DIR}/bin"

have_cmd arm-none-eabi-gcc  || { echo "arm-none-eabi-gcc not found";  exit 1; }
have_cmd riscv-none-elf-gcc || { echo "riscv-none-elf-gcc not found"; exit 1; }

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

banner "Building + INSTALLING picotool (USB-enabled, CMake package)"
if [[ ! -d "${PICOTOOL_DIR}" ]]; then
  git clone https://github.com/raspberrypi/picotool.git "${PICOTOOL_DIR}"
fi
rm -rf "${PICOTOOL_BUILD}" "${PICOTOOL_INSTALL}"
mkdir -p "${PICOTOOL_BUILD}"
pushd "${PICOTOOL_BUILD}" >/dev/null
cmake .. -G Ninja \
  -DPICO_SDK_PATH="${PICO_SDK_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PICOTOOL_INSTALL}"
cmake --build . -j
cmake --install .
popd >/dev/null

# Add picotool binary to PATH (user shells) and symlink for sudo shells
append_once_bashrc "export PATH=${PICOTOOL_BUILD}:\$PATH"
export PATH="${PICOTOOL_BUILD}:$PATH"
sudo ln -sf "${PICOTOOL_BIN}" /usr/local/bin/picotool

# Make CMake auto-find picotool package (this fixes your error)
append_once_bashrc "export CMAKE_PREFIX_PATH=${PICOTOOL_INSTALL}:\$CMAKE_PREFIX_PATH"
export CMAKE_PREFIX_PATH="${PICOTOOL_INSTALL}:${CMAKE_PREFIX_PATH:-}"

# Sanity: ensure USB subcommands exist
if ! "${PICOTOOL_BIN}" --help | grep -q "load"; then
  echo "WARNING: picotool built WITHOUT USB support; ensure libusb-1.0-0-dev installed."
fi

banner "Building Raspberry Pi OpenOCD fork (internal jimTCL)"
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
append_once_bashrc "export PATH=${OPENOCD_PREFIX}/bin:\$PATH"
export PATH="${OPENOCD_PREFIX}/bin:${PATH}"

banner "Installing udev rules + groups"
# OpenOCD generic rules
if [[ -f "${OPENOCD_DIR}/contrib/60-openocd.rules" ]]; then
  sudo cp "${OPENOCD_DIR}/contrib/60-openocd.rules" /etc/udev/rules.d/
fi
# Debug Probe rule (2e8a:000c)
sudo bash -c 'cat >/etc/udev/rules.d/99-rpi-debug-probe.rules' <<'RULES'
SUBSYSTEM=="usb", ATTR{idVendor}=="2e8a", ATTR{idProduct}=="000c", MODE="0666", GROUP="plugdev", SYMLINK+="rpi-debug-probe"
RULES
# Broad RP USB vendor rule (covers BOOTSEL IDs)
sudo bash -c 'cat >/etc/udev/rules.d/99-pico-usb.rules' <<'RULES'
SUBSYSTEM=="usb", ATTR{idVendor}=="2e8a", MODE="0666", GROUP="plugdev"
RULES
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo usermod -aG dialout "$USER" || true
getent group plugdev >/dev/null 2>&1 || sudo groupadd plugdev
sudo usermod -aG plugdev "$USER" || true

banner "Writing OpenOCD config snippets"
mkdir -p "${CFG_DIR}"
cat > "${CFG_DIR}/rp2350-arm.cfg" <<'EOF'
interface cmsis-dap
transport select swd
adapter speed 4000
source [find target/rp2350.cfg]
# adapter speed 1000
EOF
cat > "${CFG_DIR}/rp2350-riscv.cfg" <<'EOF'
interface cmsis-dap
transport select swd
adapter speed 4000
source [find target/rp2350-riscv.cfg]
# adapter speed 1000
EOF

banner "Environment ready!"
echo "Arm GCC : $(arm-none-eabi-gcc --version | head -n1)"
echo "RISC-V  : $(riscv-none-elf-gcc --version | head -n1)"
echo "pico-sdk: ${PICO_SDK_PATH}"
echo "picotool: $(command -v picotool)"
echo "openocd : ${OPENOCD_BIN}"
echo "CMAKE_PREFIX_PATH includes: ${PICOTOOL_INSTALL}"
echo
echo "Open a new shell or run:  source ~/.bashrc"
echo
echo "Build example (RISC-V, Pico 2):"
echo "  mkdir -p build && cd build"
echo "  cmake .. -G Ninja -DPICO_SDK_PATH=\$PICO_SDK_PATH -DPICO_PLATFORM=rp2350-riscv -DPICO_BOARD=pico2"
echo "  ninja"