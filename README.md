# RP2350

Environment setup for Raspberry Pi RP2350 development on both **Arm Cortex-M33** and **RISC-V Hazard3** cores.

## Environment Preparation Script

This repository includes a script that configures a fresh Ubuntu system for RP2350 development — including support for the **Raspberry Pi Debug Probe**.

### What the script does
- Installs **Arm** and **RISC-V** bare-metal toolchains.
- Clones and updates the **pico-sdk**.
- Builds **picotool** with USB support for flashing firmware.
- Builds **Raspberry Pi’s OpenOCD fork** with RP2350 target support.
- Installs **udev rules** for the Debug Probe and sets user group permissions.
- Adds required paths to your `~/.bashrc` for future shells.
- Provides ready-to-use **OpenOCD config files** for both Arm and RISC-V debugging.

### Usage
```bash
git clone https://github.com/arashmok/RP2350.git
cd RP2350
bash prep_pico2_full_env.sh
