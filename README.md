# z486 MiSTer core

z486_MiSTer is an experimental PC core for MiSTer. It runs the z386 CPU from
[Marty_MiSTer](https://github.com/MiSTer-devel/Marty_MiSTer) (`src/z386`) as a
386DX at a fixed 16 MHz, with no cache and no FPU. The CPU advances on a 16 MHz
clock enable; memory, video, sound and timers keep running on `clk_sys`.

The core uses MiSTer SDRAM for system memory and supports 16, 32, 64, or 128 MB
configurations. Video hardware provides VGA and ET4000-compatible SVGA modes.

## Trying It

z486_MiSTer requires an SDRAM module. The SDRAM XS-D v2.5 module has been
verified to work. It also requires MiSTer main `MiSTer_20260823` or newer;
run `Scripts` → `update` before installing the core.

Download the latest build from the
[releases page](https://github.com/nand2mario/z486_MiSTer/releases), then place
the files as follows:

- `z486_*.rbf` in `/media/fat/_Computer`
- [boot0.rom](verilator/boot0.rom), [boot1.rom](verilator/boot1.rom), and disk
  images (`.vhd`) in `/media/fat/games/Z486`

Development and compatibility discussion is available in the
[MiSTer FPGA forum thread](https://misterfpga.org/viewtopic.php?t=10667).
