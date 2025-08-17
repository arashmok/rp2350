# RP2350 Environment Setup

This repository contains a setup script to prepare a fresh Ubuntu system for development with the Raspberry Pi Pico 2 (RP2350).  
It installs the required toolchains, Pico SDK, picotool, and Raspberry Pi’s OpenOCD fork, and sets up udev rules for USB and Debug Probe access.

---

## Usage

Run the script on a fresh Ubuntu VM:

```bash
bash prep_pico2_full_env.sh
```

After completion:

- Arm (`arm-none-eabi`) and RISC-V (`riscv-none-elf`) toolchains will be installed.
- `picotool` will be available globally (both normal and sudo).
- `openocd` will be installed with configs for RP2350 Arm and RISC-V targets.
- udev rules will allow non-root access to boards and Debug Probe.
- `pico-sdk` will be cloned under `~/pico-work`.

---

## Building a Project

From inside your project folder:

```bash
mkdir -p build
cd build

cmake .. -G Ninja   -DPICO_SDK_PATH=$PICO_SDK_PATH   -DPICO_PLATFORM=<rp2350-arm or rp2350-riscv>   -DPICO_BOARD=pico2

ninja
```

This will generate UF2 and ELF files in the `build/` folder.

---

## Uploading to Pico 2

### Option A: Using BOOTSEL (drag-and-drop)
1. Hold the **BOOTSEL** button on the Pico 2 and plug it into USB.  
   It will appear as a USB mass storage device.
2. Copy the generated `.uf2` file (e.g. `<project>.uf2`) to the mounted drive.
3. The board will reboot automatically and start running the program.

### Option B: Using `picotool` (recommended for development)
With the board connected in BOOTSEL mode:

```bash
picotool load -f build/<project>.uf2
picotool reboot
```

- `load -f` flashes the UF2 directly.  
- `reboot` restarts the Pico 2 to run the program.

> If you see permission errors, unplug/replug and make sure you’ve logged out/in after group changes (`dialout`, `plugdev`).

---

## Next Steps

- Use the provided OpenOCD config files for debugging:
  - `rp2350-arm.cfg`
  - `rp2350-riscv.cfg`
- Start adding projects (both Arm and RISC-V based) into this repo.
