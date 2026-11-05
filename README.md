# Smart Traffic Junction Controller (AVR Assembly)

A scaled four-way traffic junction controlled by an Arduino Uno (ATmega328P), with all firmware written entirely in **AVR assembly** (no C and no Arduino libraries).

*Group project for IE3064 Embedded Systems Design, SLIIT (Group 4).*

## Features
- Table-driven four-way signal cycle with yellow and all-red clearance, timings read from flash with `lpm`
- Pedestrian crossing: button interrupt (INT0) sets a request, crossing phase runs after the current phase, with a 5-to-0 LED countdown
- Night mode: LDR read with the ADC; yellow LEDs flash at 1 Hz, and normal mode returns only after 5 s of stable daylight (hysteresis)
- Timer1 in CTC mode for timing

## Tech
AVR assembly (avr-as), ATmega328P, ADC, external interrupt, Timer1, Proteus schematics

## Folder guide
`code/` firmware (`traffic.S`, hex) · `design/` schematics and state machine

See `code/README.md` for pin mapping and a detailed code walkthrough.

## Authors
Vishmini Michel and group members.
