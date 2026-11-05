# Code guide: Smart Traffic Junction Controller

Scaled four-way traffic junction controlled by an Arduino Uno (ATmega328P).
All firmware is written **entirely in AVR Assembly** (GNU `avr-as` syntax). No C, C++ or Arduino library functions are used.

## Features

- **Normal mode:** table-driven four-way cycle (North-South / East-West) with transitional yellow and all-red clearance. Timings are stored in a program memory table and read with `lpm`.
- **Pedestrian crossing (South approach):** the button (INT0) only sets a request flag. The crossing phase is inserted after the current vehicle phase and its all-red interval. All directions stay red while 5 LEDs count down from 5 to 0 (1 s per step). Presses during the crossing are ignored, so one press gives one crossing.
- **Night mode:** when the LDR reading drops below the dark threshold, all yellow LEDs flash at 1 Hz and all other LEDs are off. Normal mode resumes only after the light stays above the bright threshold for 5 consecutive seconds. Any dark sample resets the counter.
- **Pedestrian button in Night mode:** ignored (request flag cleared, INT0 disabled). Normal mode resumes through a 1 s all-red interval.

## Files

| File | Description |
|---|---|
| `traffic.S` | Complete firmware: vector table, initialisation (stack, ports, INT0, ADC, Timer1), table-driven normal mode, pedestrian handling and countdown, night mode with hysteresis, INT0 ISR, phase table in flash |
| `README.md` | This file |

### Structure of `traffic.S`

| Section / label | Purpose |
|---|---|
| `.section .vectors` | Reset vector (0x0000) and INT0 vector (0x0004) |
| `RESET` | Stack pointer, DDR/PORT setup, INT0 (falling edge), ADC (AVcc, left adjust, prescaler 128), Timer1 CTC (0.5 s), `sei` |
| `NORMAL_MODE`, `PHASE_LOOP` | Reads the phase table with `lpm`, drives PORTB, waits the phase duration |
| `NORMAL_DELAY`, `WAIT_ONE_SECOND`, `HALF_SECOND` | Timing routines based on the Timer1 compare flag; `HALF_SECOND` also samples the LDR |
| `READ_ADC` | Single ADC0 conversion, 8-bit result in `r17` |
| `PEDESTRIAN_MODE` | All-red crossing phase and 5 to 0 LED countdown |
| `ENTER_NIGHT`, `NIGHT_LOOP`, `NIGHT_HALF`, `NH_EXIT` | 1 Hz yellow flashing and 5 s exit hysteresis |
| `BUTTON_ISR` | Saves SREG, sets pedestrian request flag `r20`, `reti` |
| `PHASE_TABLE` | Program memory table: PORTB pattern and duration in seconds per phase |

## Pin mapping

| Arduino pin | AVR pin | Function |
|---|---|---|
| D8 | PB0 | North + South RED |
| D9 | PB1 | North + South YELLOW |
| D10 | PB2 | North + South GREEN |
| D11 | PB3 | East + West RED |
| D12 | PB4 | East + West YELLOW |
| D13 | PB5 | East + West GREEN |
| D2 | PD2 (INT0) | Pedestrian push-button (internal pull-up, to GND) |
| D3 to D7 | PD3 to PD7 | Countdown LEDs 1 to 5 |
| A0 | PC0 (ADC0) | LDR voltage divider |

## Phase table

| Phase | North-South | East-West | Duration |
|---|---|---|---|
| 0 | Green | Red | 5 s |
| 1 | Yellow | Red | 2 s |
| 2 | Red | Red (all-red) | 1 s |
| 3 | Red | Green | 5 s |
| 4 | Red | Yellow | 2 s |
| 5 | Red | Red (all-red) | 1 s |

Pedestrian requests are served after phase 2 or phase 5.

## Tunable constants (top of `traffic.S`)

| Constant | Default | Meaning |
|---|---|---|
| `DARK_TH` | 15 | ADC (8-bit) below this value means dark |
| `BRIGHT_TH` | 25 | ADC at or above this value counts as bright |
| `EXIT_COUNT` | 10 | Number of 0.5 s bright samples needed to leave Night mode (10 x 0.5 s = 5 s) |

Tune `DARK_TH` and `BRIGHT_TH` for the LDR and fixed resistor used on the real board.

## Toolchain setup (Ubuntu / Debian)

```
sudo apt update
sudo apt install gcc-avr binutils-avr avr-libc avrdude
avr-gcc --version
```

Windows: use WSL (Ubuntu) and the commands above, or a Windows AVR-GCC toolchain added to PATH.
macOS: `brew install avr-gcc avrdude`.

Note: the source file extension must be capital `.S`, so that the C preprocessor handles `#include <avr/io.h>`. This header is used only for register and bit name definitions. No C code is compiled.

## Build

```
avr-gcc -mmcu=atmega328p -nostdlib -nostartfiles -o traffic.elf traffic.S
avr-objcopy -O ihex traffic.elf traffic.hex
```

The build must finish with no errors or warnings.

## Upload to Arduino Uno

Find the serial port first (usually `/dev/ttyACM0` on Linux, `COMx` on Windows):

```
avrdude -c arduino -p m328p -P /dev/ttyACM0 -b 115200 -U flash:w:traffic.hex:i
```

## Quick test checklist

1. Normal cycle runs: NS green, yellow, all-red, EW green, yellow, all-red.
2. Press the button during green or yellow: lights do not change at once; after the all-red interval all directions show red and the LEDs count 5 to 0.
3. Press repeatedly: only one crossing phase is given.
4. Cover the LDR: yellow LEDs flash at 1 Hz.
5. Uncover the LDR: Normal mode returns only after 5 s of continuous light; re-covering within 5 s keeps Night mode.
