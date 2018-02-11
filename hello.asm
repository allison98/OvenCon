$MODLP51
org 0000H

CLK  EQU 22118400
BAUD equ 115200
BRG_VAL equ (0x100-(CLK/(16*BAUD)))


; These �EQU� must match the wiring between the microcontroller and ADC
CE_ADC EQU P2.0
MY_MOSI EQU P2.1
MY_MISO EQU P2.2
MY_SCLK EQU P2.3

; For the 7-segment display
SEGA equ P0.3
SEGB equ P0.5
SEGC equ P0.7
SEGD equ P4.4
SEGE equ P4.5
SEGF equ P0.4
SEGG equ P0.6
SEGP equ P2.7
CA1  equ P0.2
CA2  equ P0.0
CA3  equ P0.1


DSEG at 30H
x:   ds 4
y:   ds 4
Result: ds 4
bcd: ds 5
;Count1ms:     ds 2 ; Used to determine when half second has passed
;BCD_counter:  ds 1 ; The BCD counter incrememted in the ISR and displayed in the main loop
Disp1:  ds 1 
Disp2:  ds 1
Disp3:  ds 1
state:  ds 1

BSEG
mf: dbit 1

$NOLIST
$include(math32.inc)
$LIST




cseg
; These 'equ' must match the wiring between the microcontroller and the LCD!
LCD_RS equ P1.1
LCD_RW equ P1.2
LCD_E  equ P1.3
LCD_D4 equ P3.2
LCD_D5 equ P3.3
LCD_D6 equ P3.4
LCD_D7 equ P3.5
$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST




Left_blank mac
	mov a, %0
	anl a, #0xf0
	swap a
	jz Left_blank_%M_a
	ljmp %1
Left_blank_%M_a:
	Display_char(#' ')
	mov a, %0
	anl a, #0x0f
	jz Left_blank_%M_b
	ljmp %1
Left_blank_%M_b:
	Display_char(#' ')
endmac

; Sends 10-digit BCD number in bcd to the LCD
Display_10_digit_BCD:
	Set_Cursor(2, 7)
	Display_BCD(bcd+4)
	Display_BCD(bcd+3)
	Display_BCD(bcd+2)
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	; Replace all the zeros to the left with blanks
	Set_Cursor(2, 7)
	Left_blank(bcd+4, skip_blank)
	Left_blank(bcd+3, skip_blank)
	Left_blank(bcd+2, skip_blank)
	Left_blank(bcd+1, skip_blank)
	mov a, bcd+0
	anl a, #0f0h
	swap a
	jnz skip_blank
	Display_char(#' ')
skip_blank:
	ret

; We can display a number any way we want.  In this case with
; four decimal places.
Display_formated_BCD:
	Set_Cursor(2, 7)
	Display_char(#' ')
	Display_BCD(bcd+3)
	Display_BCD(bcd+2)
	Display_char(#'.')
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	ret

Test_msg:  db 'Temp:xx', 0


; Configure the serial port and baud rate
InitSerialPort:
    ; Since the reset button bounces, we need to wait a bit before
    ; sending messages, otherwise we risk displaying gibberish!
    mov R1, #222
    mov R0, #166
    djnz R0, $   ; 3 cycles->3*45.21123ns*166=22.51519us
    djnz R1, $-4 ; 22.51519us*222=4.998ms
    ; Now we can proceed with the configuration
	orl	PCON,#0x80
	mov	SCON,#0x52
	mov	BDRCON,#0x00
	mov	BRL,#BRG_VAL
	mov	BDRCON,#0x1E ; BDRCON=BRR|TBCK|RBCK|SPD;
    ret

; Send a character using the serial port
putchar1:
    jnb TI, putchar1
    clr TI
    mov SBUF, a
    ret

; Send a constant-zero-terminated string using the serial port
SendString:
    clr A
    movc A, @A+DPTR
    jz SendStringDone
    lcall putchar
    inc DPTR
    sjmp SendString
SendStringDone:
    ret
 

    
INIT_SPI:
 setb MY_MISO ; Make MISO an input pin
 clr MY_SCLK ; For mode (0,0) SCLK is zero
 ret

DO_SPI_G:
 push acc
 mov R1, #0 ; Received byte stored in R1
 mov R2, #8 ; Loop counter (8-bits)
DO_SPI_G_LOOP:
 mov a, R0 ; Byte to write is in R0
 rlc a ; Carry flag has bit to write
 mov R0, a
 mov MY_MOSI, c
 setb MY_SCLK ; Transmit
 mov c, MY_MISO ; Read received bit
 mov a, R1 ; Save received bit in R1
 rlc a
 mov R1, a
 clr MY_SCLK
 djnz R2, DO_SPI_G_LOOP
 pop acc
 ret

Display_voltage:
	DB ' ','\r','\n',0	


;---------------------------------;
; Send a BCD number to PuTTY      ;
;---------------------------------;


;---------------;
;multiplication
;---------------;
Voltage_calculation:

;Set_Cursor(1, 6)
   ; Display_BCD(#0x02)
    ; There are macros defined in math32.asm that can be used to load constants
    ; to variables x and y. The same code above may be written as:
    ;initialize
    Set_Cursor(1, 6);
	Display_BCD(#0x02)
    Load_x(0)
    Load_y(0)
    
    mov x, result
    mov x+1,result+1
    Load_y(4096)
    lcall mul32
    Load_y(10230)
    lcall div32 ; This subroutine is in math32.asm
    
    load_y(273)
    lcall sub32
    
    
    lcall hex2bcd
   Send_BCD(bcd+1)
   Send_BCD(bcd) 
   
   ;;;  State machine for 7-segment displays starts here
	; Turn all displays off
	setb CA1
	setb CA2
	setb CA3

	mov a, state
state0:
	cjne a, #0, state1
	mov a, disp1
	lcall load_segments
	clr CA1
	inc state
	sjmp state_done
state1:
	cjne a, #1, state2
	mov a, disp2
	lcall load_segments
	clr CA2
	inc state
	sjmp state_done
state2:
	cjne a, #2, state_reset
	mov a, disp3
	lcall load_segments
	clr CA3
	mov state, #0
	sjmp state_done
state_reset:
	mov state, #0
state_done:
;;;  State machine for 7-segment displays ends here

   ret
   
wait_a_second:
			Wait_Milli_Seconds(#100)
			Wait_Milli_Seconds(#100)
			Wait_Milli_Seconds(#100)
			Wait_Milli_Seconds(#100)
			Wait_Milli_Seconds(#100)
			Wait_Milli_Seconds(#100)
			Wait_Milli_Seconds(#100)
			Wait_Milli_Seconds(#100)
			Wait_Milli_Seconds(#100)
			Wait_Milli_Seconds(#100)
			ret						


; Pattern to load passed in accumulator
load_segments:
	mov c, acc.0
	mov SEGA, c
	mov c, acc.1
	mov SEGB, c
	mov c, acc.2
	mov SEGC, c
	mov c, acc.3
	mov SEGD, c
	mov c, acc.4
	mov SEGE, c
	mov c, acc.5
	mov SEGF, c
	mov c, acc.6
	mov SEGG, c
	mov c, acc.7
	mov SEGP, c
	ret
	


HEX_7SEG: DB 0xC0, 0xF9, 0xA4, 0xB0, 0x99, 0x92, 0x82, 0xF8, 0x80, 0x90



MainProgram:
    mov SP, #7FH ; Set the stack pointer to the begining of idata
 
    lcall InitSerialPort
    lcall INIT_SPI
     ; In case you decide to use the pins of P0, configure the port in bidirectional mode:
    mov P0M0, #0
    mov P0M1, #0
    mov AUXR, #00010001B ; Max memory.  P4.4 is a general purpose IO pin
     lcall LCD_4BIT
    

 
Forever:
clr CE_ADC
mov R0, #00000001B ; Start bit:1
lcall DO_SPI_G
mov R0, #10000000B ; Single ended, read channel 0
lcall DO_SPI_G
mov a, R1 ; R1 contains bits 8 and 9
anl a, #00000011B ; We need only the two least significant bits
mov Result+1, a ; Save result high.
mov R0, #55H ; It doesn't matter what we transmit...
lcall DO_SPI_G
mov Result, R1 ; R1 contains bits 0 to 7. Save result low.
setb CE_ADC

;lcall wait_a_second
;lcall Voltage_calculation

Seg_display:
	mov dptr, #HEX_7SEG
	
	;mov a, bcd
	;mov a, #1011011b	;changed
	;anl a, #0x0f
	;movc a, @a+dptr
;	mov disp2, a


		setb CA1
	;mov a, bcd
	mov a, #8	;changed
	swap a
	anl a, #0x0f
	movc a, @a+dptr
	mov disp1, a
	lcall load_segments


		clr CA1
	
	;mov a, bcd
;	mov a, #0x8	;changed
;	swap a
;	anl a, #0x0f
;	movc a, @a+dptr
;	mov disp3, a
	;lcall wait_a_second
	
 	Set_Cursor(1, 1)
 	Send_Constant_String(#Test_msg)	
 	
; lcall Voltage_calculation
 
 lcall SendString
 sjmp Forever
    
END



