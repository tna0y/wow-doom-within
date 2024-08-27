<img src="media/menu.png" alt="Menu Screenshot" width="480">&nbsp;
<img src="media/gameplay.png" alt="Gameplay Screenshot" width="480"/>

# The Doom Within
**A World of Warcraft Addon that runs Doom.**

## How to Play

The addon is available on CurseForge: [Doom Within Addon](https://legacy.curseforge.com/wow/addons/doom-within).

Refer to the addon description for detailed usage instructions.

## Building

Refer to the [**Makefile**](Makefile) for the general compilation procedure.

To install the engine as an addon on a Windows PC, use `deploy.bat`. The samples selected in **tests/testsuite.lua** will run as soon as the addon is loaded.

If you want to try running other programs using the emulator, check out [vladvis/risc-v-wow-emu](https://github.com/vladvis/risc-v-wow-emu) for instructions.

### Compiling the Addon

The addon emulates Linux while the game runs on Windows and macOS, so using Windows + WSL is the optimal development environment for this project.

Build steps:

1. **Build the project:**

   ```sh
   # On Linux
   make
   ```

   After building, `build/DoomWithin` should contain all the files you need for the addon to work.

2. **Install the addon into your game:**

   ```sh
   # On Windows
   .\deploy.bat
   ```

   Run the script to install it in your game. Ensure the paths in the **deploy.conf** file are correctly set up.

### Requirements

To build the tests, you'll need the [risc-v-gnu-toolchain](https://github.com/riscv-collab/riscv-gnu-toolchain):

```sh
git clone git@github.com:riscv-collab/riscv-gnu-toolchain.git
cd riscv-gnu-toolchain
./configure --prefix=/opt/toolchains/riscv32 --with-arch=rv32g --with-abi=ilp32d
make
```

You'll also need Python with `jinja2` and `pyelftools` to convert ELF binaries to Lua code that can be loaded in-game:

```sh
python3 -m pip install jinja2 pyelftools
```

## Porting and Architecture Considerations

RISC-V was chosen as the target architecture because it's well-documented and extendable. We opted for the RV32IM extension, along with F, D, Zicsr, and Zifencei (NOP), though the project can compile and run without these extensions.

Our goal was to turn Doom into a time-distributed pure function that converts inputs into framebuffers. We chose [doomgeneric](https://github.com/ozkl/doomgeneric) as the source port base because it adheres to this ideology, limiting side effects and external interactions to a single code file—ideal for emulator development, as it makes peripherals predictable and localized.

Doomgeneric only requires the implementation of the following functions (see [doomgeneric/doomgeneric_riscv32.c](doomgeneric/doomgeneric_riscv32.c) for their implementation):

- `DG_Init`
- `DG_DrawFrame`
- `DG_SleepMs`
- `DG_GetTicksMs`
- `DG_GetKey`

We extended the interface with two additional functions, identified through profiling and instrumentation as performance hotspots. These functions were implemented as separate system calls, providing a significant performance boost:

- `DG_DrawColumn`
- `DG_DrawSpan`
- `DG_memcpy`

### Syscall Table

Below is the current syscall table. Note that it bears little resemblance to Linux syscalls:

| Syscall Name              | Number | Details                                                                              |
|---------------------------|--------|--------------------------------------------------------------------------------------|
| `SYS_WOW_toggle_window`    | 101    | Shows a black screen. Some programs can operate headlessly without this syscall.     |
| `SYS_WOW_send_framebuffer` | 102    | Sends the framebuffer to the emulator. The color palette is taken from PLAYPAL 0th lump. |
| `SYS_WOW_check_key_pressed`| 103    | Queries for user inputs.                                                             |
| `SYS_WOW_sleep`            | 104    | Sleep implementation. Can be used to switch the execution context back to WoW.       |
| `SYS_WOW_draw_column`      | 105    | Optimization. Column draw loop implemented directly in Lua.                          |
| `SYS_WOW_draw_span`        | 106    | Optimization. Span draw loop implemented directly in Lua.                            |
| `SYS_WOW_memcpy   `        | 107    | Optimization. memcpy implemented directly in Lua.                                    |
| `exit`                     | 93     | Allows for proper termination.                                                       |
| `write`                    | 64     | Useful for debugging, only `1` and `2` file descriptors are supported.               |
| `newfstat`                 | 80     | No-op, called by `printf`.                                                           |
| `fclose`                   | 57     | No-op, newlib likes to close stdout/stderr.                                          |
| `brk`                      | 214    | Dynamic memory support, fully implemented.                                           |
| `clock_gettime`            | 403    | Used by the newlib `gettimeofday` implementation.                                    |

## Performance and Optimizations

Performance varies greatly depending on the device, largely influenced by single-thread CPU performance and memory speed. Currently, we observe 0.5-2 seconds per frame when rendering game levels, depending on the device.

After the initial and naive implementation of both the port and emulator, we initially observed a performance of 15 seconds per frame while drawing the splash screen.

Doom runs live demos during the initial frames without any user input, so our benchmark was total the frame number that could be achieved in 180 real seconds from the program start.

The following optimizations were implemented:

- **Code cleanup:** Asserts and debug outputs were removed from performance-critical branches. This provided a major performance improvement.
- **Instruction decoding caching:** We implemented a simple address-to-decoded-instruction-object table, as we do not support polymorphic binaries. This provided a major performance improvement.
- **Sound-related code removal:** All sound-related code was removed from the game, resulting in a marginal binary size reduction.
- **RANGECHECK undefined:** The `RANGECHECK` was undefined in the game source code, resulting in a marginal performance improvement.
- **Syscall optimization:** `R_DrawColumn` and `R_DrawSpan` function loops were moved to separate syscalls, providing a major performance improvement.
- **Aligned memory access:** Frame rendering uses aligned memory access, resulting in a minor performance improvement.
- **Adress-level instruction cache:** In repeating code only a single table lookup is now required per instruction.
- **Precalculating parts of instruction code:** When first loading instructions anything that can be calculated in advance is stored.
- **Memcpy:** implemented in Lua reducing overall executed instruction count by ~10%.

## Development

Development is split into two repositories for convenience and licensing reasons:

- [wow-doom-within](https://github.com/tna0y/wow-doom-within): Contains the WoW addon wrapper and the Doom port source code.
- [risc-v-wow-emu](https://github.com/vladvis/risc-v-wow-emu): Contains the emulator code and tests.

### How to Contribute

Contributions are highly welcome! We are currently seeking performance gains to get Doom to a playable state.

Feel free to reach out via issues, Discord (tna0y), or Battle.net (tna0y#2138) if you have any ideas or suggestions.

### Contributors

- [vladvis](https://github.com/vladvis) - Emulator development.
- [tna0y](https://github.com/tna0y) - Emulator tests, Doom port.

### Acknowledgments

- [RISC-666](https://github.com/lcq2/risc-666) For providing a reference on instruction implementation.
- [doomgeneric](https://github.com/ozkl/doomgeneric) Source port used as a base for this project.
