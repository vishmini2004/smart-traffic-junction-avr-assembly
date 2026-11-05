#include <avr/io.h>

; ============================================================
; SMART TRAFFIC JUNCTION CONTROLLER  (avr-as / GNU syntax)
; Arduino Uno / ATmega328P
;
; PB0 NS Red   PB1 NS Yellow   PB2 NS Green
; PB3 EW Red   PB4 EW Yellow   PB5 EW Green
; PD2 Pedestrian button (INT0)
; PD3..PD7 Countdown LEDs
; PC0 (ADC0) LDR
;
; Registers
;   r19 = current phase index (0..5)
;   r18 = seconds remaining in phase
;   r20 = pedestrian request flag
;   r22 = dark flag (set by HALF_SECOND when ADC < DARK_TH)
;   r24 = consecutive bright half-seconds (night mode)
; ============================================================

.equ DARK_TH,   15          ; ADC < 15  -> dark
.equ BRIGHT_TH, 25          ; ADC >= 25 -> bright
.equ EXIT_COUNT, 10         ; 10 x 0.5 s = 5 s

.section .vectors
    rjmp RESET                  ; 0x0000 Reset
    .org 0x0004
    rjmp BUTTON_ISR             ; 0x0004 INT0

.section .text

; ============================================================
; INITIALIZATION
; ============================================================
RESET:
    ldi r16, hi8(RAMEND)
    out _SFR_IO_ADDR(SPH), r16
    ldi r16, lo8(RAMEND)
    out _SFR_IO_ADDR(SPL), r16

    ldi r16, 0b00111111
    out _SFR_IO_ADDR(DDRB), r16
    clr r16
    out _SFR_IO_ADDR(PORTB), r16

    ldi r16, 0b11111000
    out _SFR_IO_ADDR(DDRD), r16
    ldi r16, 0b00000100
    out _SFR_IO_ADDR(PORTD), r16

    clr r20
    clr r22

    ldi r16, (1<<ISC01)
    sts EICRA, r16
    ldi r16, (1<<INTF0)
    out _SFR_IO_ADDR(EIFR), r16
    ldi r16, (1<<INT0)
    out _SFR_IO_ADDR(EIMSK), r16

    ldi r16, (1<<REFS0) | (1<<ADLAR)
    sts ADMUX, r16
    ldi r16, (1<<ADEN) | (1<<ADPS2) | (1<<ADPS1) | (1<<ADPS0)
    sts ADCSRA, r16

    clr r16
    sts TCCR1A, r16
    ldi r16, hi8(31249)
    sts OCR1AH, r16
    ldi r16, lo8(31249)
    sts OCR1AL, r16
    ldi r16, (1<<WGM12) | (1<<CS12)
    sts TCCR1B, r16

    sei

; ============================================================
; NORMAL MODE (table driven)
; ============================================================
NORMAL_MODE:
    clr r19
    clr r22

PHASE_LOOP:
    ldi ZH, hi8(PHASE_TABLE)
    ldi ZL, lo8(PHASE_TABLE)
    mov r16, r19
    lsl r16
    add ZL, r16
    clr r16
    adc ZH, r16

    lpm r16, Z+
    lpm r18, Z
    out _SFR_IO_ADDR(PORTB), r16

    rcall NORMAL_DELAY
    tst r22
    brne GO_NIGHT

    cpi r19, 2
    breq CHECK_PED
    cpi r19, 5
    brne NO_PED
CHECK_PED:
    tst r20
    breq NO_PED
    rcall PEDESTRIAN_MODE
    tst r22
    brne GO_NIGHT
NO_PED:

    inc r19
    cpi r19, 6
    brlo PHASE_LOOP
    clr r19
    rjmp PHASE_LOOP

GO_NIGHT:
    rjmp ENTER_NIGHT

; ---- Wait r18 seconds (aborts early if dark) ----
NORMAL_DELAY:
    rcall WAIT_ONE_SECOND
    tst r22
    brne ND_DONE
    dec r18
    brne NORMAL_DELAY
ND_DONE:
    ret

WAIT_ONE_SECOND:
    rcall HALF_SECOND
    tst r22
    brne W1_DONE
    rcall HALF_SECOND
W1_DONE:
    ret

; ---- 0.5 s via Timer1 flag, also samples LDR ----
HALF_SECOND:
    clr r23
    sts TCNT1H, r23
    sts TCNT1L, r23
    ldi r23, (1<<OCF1A)
    out _SFR_IO_ADDR(TIFR1), r23
HS_WAIT:
    in r23, _SFR_IO_ADDR(TIFR1)
    sbrs r23, OCF1A
    rjmp HS_WAIT
    ldi r23, (1<<OCF1A)
    out _SFR_IO_ADDR(TIFR1), r23

    rcall READ_ADC              ; r17 = LDR value
    cpi r17, DARK_TH
    brsh HS_NOT_DARK
    ldi r22, 1                  ; dark detected
HS_NOT_DARK:
    ret

; ---- ADC0 read, r17 = 8-bit result ----
READ_ADC:
    lds r16, ADCSRA
    ori r16, (1<<ADSC)
    sts ADCSRA, r16
ADC_WAIT:
    lds r16, ADCSRA
    sbrc r16, ADSC
    rjmp ADC_WAIT
    lds r17, ADCH
    ret

; ============================================================
; PEDESTRIAN MODE
; ============================================================
PEDESTRIAN_MODE:
    clr r20

    clr r16
    out _SFR_IO_ADDR(EIMSK), r16

    ldi r16, 0b00001001
    out _SFR_IO_ADDR(PORTB), r16

    ldi r16, 0b11111100         ; 5
    out _SFR_IO_ADDR(PORTD), r16
    rcall WAIT_ONE_SECOND
    tst r22
    brne PED_ABORT
    ldi r16, 0b01111100         ; 4
    out _SFR_IO_ADDR(PORTD), r16
    rcall WAIT_ONE_SECOND
    tst r22
    brne PED_ABORT
    ldi r16, 0b00111100         ; 3
    out _SFR_IO_ADDR(PORTD), r16
    rcall WAIT_ONE_SECOND
    tst r22
    brne PED_ABORT
    ldi r16, 0b00011100         ; 2
    out _SFR_IO_ADDR(PORTD), r16
    rcall WAIT_ONE_SECOND
    tst r22
    brne PED_ABORT
    ldi r16, 0b00001100         ; 1
    out _SFR_IO_ADDR(PORTD), r16
    rcall WAIT_ONE_SECOND

PED_ABORT:
    ldi r16, 0b00000100         ; LEDs off, pull-up on
    out _SFR_IO_ADDR(PORTD), r16

    ldi r16, (1<<INTF0)
    out _SFR_IO_ADDR(EIFR), r16
    ldi r16, (1<<INT0)
    out _SFR_IO_ADDR(EIMSK), r16
    ret

; ============================================================
; NIGHT MODE
; ============================================================
ENTER_NIGHT:
    ; reset stack (we jumped out of nested calls)
    ldi r16, hi8(RAMEND)
    out _SFR_IO_ADDR(SPH), r16
    ldi r16, lo8(RAMEND)
    out _SFR_IO_ADDR(SPL), r16

    clr r20                     ; ignore pedestrian requests
    clr r16
    out _SFR_IO_ADDR(EIMSK), r16
    ldi r16, 0b00000100         ; countdown LEDs off
    out _SFR_IO_ADDR(PORTD), r16
    clr r24                     ; bright counter = 0

NIGHT_LOOP:
    ; ---- yellow ON for 0.5 s ----
    ldi r16, 0b00010010
    out _SFR_IO_ADDR(PORTB), r16
    rcall NIGHT_HALF

    ; ---- all OFF for 0.5 s ----
    clr r16
    out _SFR_IO_ADDR(PORTB), r16
    rcall NIGHT_HALF

    rjmp NIGHT_LOOP

; 0.5 s wait + hysteresis update; exits night when r24 reaches EXIT_COUNT
NIGHT_HALF:
    clr r23
    sts TCNT1H, r23
    sts TCNT1L, r23
    ldi r23, (1<<OCF1A)
    out _SFR_IO_ADDR(TIFR1), r23
NH_WAIT:
    in r23, _SFR_IO_ADDR(TIFR1)
    sbrs r23, OCF1A
    rjmp NH_WAIT
    ldi r23, (1<<OCF1A)
    out _SFR_IO_ADDR(TIFR1), r23

    rcall READ_ADC
    cpi r17, BRIGHT_TH
    brsh NH_BRIGHT
    clr r24                     ; not bright -> restart 5 s count
    ret
NH_BRIGHT:
    inc r24
    cpi r24, EXIT_COUNT
    brsh NH_EXIT
    ret

NH_EXIT:
    ; leave night mode through an all-red second
    pop r16                     ; discard return address (NIGHT_HALF)
    pop r16
    ldi r16, 0b00001001
    out _SFR_IO_ADDR(PORTB), r16
    rcall WAIT_ONE_SECOND_PLAIN

    clr r20
    clr r22
    ldi r16, (1<<INTF0)
    out _SFR_IO_ADDR(EIFR), r16
    ldi r16, (1<<INT0)
    out _SFR_IO_ADDR(EIMSK), r16
    rjmp NORMAL_MODE

; plain 1 s delay without LDR sampling
WAIT_ONE_SECOND_PLAIN:
    ldi r25, 2
WP_LOOP:
    clr r23
    sts TCNT1H, r23
    sts TCNT1L, r23
    ldi r23, (1<<OCF1A)
    out _SFR_IO_ADDR(TIFR1), r23
WP_WAIT:
    in r23, _SFR_IO_ADDR(TIFR1)
    sbrs r23, OCF1A
    rjmp WP_WAIT
    ldi r23, (1<<OCF1A)
    out _SFR_IO_ADDR(TIFR1), r23
    dec r25
    brne WP_LOOP
    ret

; ============================================================
; BUTTON INTERRUPT (only sets request flag)
; ============================================================
BUTTON_ISR:
    push r16
    in r16, _SFR_IO_ADDR(SREG)
    push r16
    ldi r20, 1
    pop r16
    out _SFR_IO_ADDR(SREG), r16
    pop r16
    reti

; ============================================================
; PHASE TABLE (Program Memory): PORTB pattern, seconds
; ============================================================
.balign 2
PHASE_TABLE:
    .byte 0b00001100, 5         ; 0: NS green,  EW red
    .byte 0b00001010, 2         ; 1: NS yellow, EW red
    .byte 0b00001001, 1         ; 2: all red
    .byte 0b00100001, 5         ; 3: NS red,    EW green
    .byte 0b00010001, 2         ; 4: NS red,    EW yellow
    .byte 0b00001001, 1         ; 5: all red
