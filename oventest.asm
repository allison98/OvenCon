
$MODLP51
org 0000H
   ljmp MainProgram

CLK  EQU 22118400
BAUD equ 115200
BRG_VAL equ (0x100-(CLK/(16*BAUD)))
REF equ 4.096

; These ’EQU’ must match the wiring between the microcontroller and ADC
CE_ADC EQU P2.0
MY_MOSI EQU P2.1
MY_MISO EQU P2.2
MY_SCLK EQU P2.3


TIMER0_RELOAD_L DATA 0xf2
TIMER1_RELOAD_L DATA 0xf3
TIMER0_RELOAD_H DATA 0xf4
TIMER1_RELOAD_H DATA 0xf5

TIMER0_RATE   EQU 4096             ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

; buttons
BOOT_BUTTON   equ P4.5

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

;future variables
DSEG at 0x30
x:   ds 4
y:   ds 4
bcd: ds 5
Result: ds 2
coldtemp: ds 1
hottemp:ds 1
reflowstate: ds 1 ; Used for changing states/displaying states. Not used anywhere else (as of Jan 30). Assign a number to each state
soaktemp: ds 1
soaktime: ds 1
reflowtemp: ds 1
reflowtime: ds 1
countererror: ds 1
temperature:ds 1
Count1ms:     ds 2 ; Used to determine when half second has passed 
counterror: ds 1
reflowparam: ds 1
seconds: ds 1
minute: ds 1
temp: ds 1

BSEG
startflag: dbit 1
errorflag: dbit 1
mf: dbit 1

CSEG
; These 'equ' must match the wiring between the microcontroller and the LCD!
LCD_RS equ P1.1
LCD_RW equ P1.2
LCD_E  equ P1.3
LCD_D4 equ P3.2
LCD_D5 equ P3.3
LCD_D6 equ P3.4
LCD_D7 equ P3.5

OvenButton equ P3.7
BEEPER equ P2.5




$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

$NOLIST
$include(math32.inc) ; A library of Lmath functions
$LIST



; constant strings  
Test_msg:  db 'TIME:', 0
MenuMessage1: db '1.Soak Temp', 0   ;used when selecting parameter
MenuMessage2: db '2.Soak Time', 0
MenuMessage3: db '3.Reflow Temp', 0
MenuMessage4: db '4.Reflow Time', 0
MenuSoakTemp: db 'Soak Temp:', 0  ;used when changing parameter
MenuSoakTime: db 'Soak Time:', 0
MenuReflowTemp: db 'Reflow Temp:', 0
MenuReflowTime: db 'Reflow Time:', 0


;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;

Timer0_Init:
	mov a, TMOD
	anl a, #0xf0 ; Clear the bits for timer 0
	orl a, #0x01 ; Configure timer 0 as 16-timer
	mov TMOD, a
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	; Set autoreload value
	mov TIMER0_RELOAD_H, #high(TIMER0_RELOAD)
	mov TIMER0_RELOAD_L, #low(TIMER0_RELOAD)
	; Enable the timer and interrupts
    setb ET0  ; Enable timer 0 interrupt
    ;setb TR0  ; Start timer 0
	ret

;---------------------------------;
; ISR for timer 0.  Set to execute;
; every 1/4096Hz to generate a    ;
; 2048 Hz square wave at pin P3.7 ;
;---------------------------------;

Timer0_ISR:
	
	reti
  
;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
Timer2_Init:
	mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
	mov TH2, #high(TIMER2_RELOAD)
	mov TL2, #low(TIMER2_RELOAD)
	; Set the reload value
	mov RCAP2H, #high(TIMER2_RELOAD)
	mov RCAP2L, #low(TIMER2_RELOAD)
	; Init One millisecond interrupt counter.  It is a 16-bit variable made with two 8-bit parts
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Enable the timer and interrupts
    setb ET2  ; Enable timer 2 interrupt
    setb TR2  ; Enable timer 2
	ret

;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR
	cpl P3.6 ; To check the interrupt rate with oscilloscope. It must be precisely a 1 ms pulse.
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

  Inc_Done:
	; Check if half second has passed
	mov a, Count1ms+0
	cjne a, #low(800), Timer2_ISR_done ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(800), Timer2_ISR_done
	
	cpl TR0 ; Enable/disable timer/counter 0. This line creates a beep-silence-beep-silence sound.
					; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
  
	mov a, seconds 	; Increment the BCD counter

	add a, #0x01 ;THIS IS ADDING SECONDS

	da a ; Decimal adjust instruction.  Check datasheet for more details!
	mov seconds, a
	
Timer2_ISR_done:
	pop psw
	pop acc
	reti
   
;---------------------------------;
; initialize the slave		      ;
;---------------------------------;

INIT_SPI:
 setb MY_MISO ; Make MISO an input pin
 clr MY_SCLK ; For mode (0,0) SCLK is zero
 ret

;---------------------------------;
; receive and send data	       		;
;---------------------------------;

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

Display_10_digit_BCD:
	Set_Cursor(1, 6)
	Display_BCD(bcd+4)
	Display_BCD(bcd+3)
	Display_BCD(bcd+2)
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	ret
	
;---------------------------------;
; initialize the serial ports     ;
;---------------------------------;
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
 
 ;---------------------------------;
; MAIN PROGRAM							      ;
;---------------------------------;  
;---------------------------------;
; MAIN PROGRAM							      ;
;---------------------------------;  

MainProgram:
	mov sp, #07FH ; Initialize the stack pointer
	; Configure P0 in bidirectional mode
   mov P0M0, #0
    mov P0M1, #0
    setb EA   ; Enable Global interrupts
    lcall LCD_4BIT
    
    mov seconds, #0
    mov soaktemp, #0
    mov soaktime, #0x60
    mov reflowtemp, #0
    mov reflowtime, #0x60
    mov countererror, #0	; to check if the thermocouple is in the oven
		
    ;initial message 
    Set_Cursor(1, 1)
    Send_Constant_String(#Test_msg)
    Set_Cursor(1,11)
    Display_BCD(seconds)
  
    lcall InitSerialPort
		lcall INIT_SPI
		lcall Timer0_Init
    lcall Timer2_Init
    setb OvenButton
    setb BEEPER
FOREVER: ;this will be how the oven is being controlled ; jump here once start button is pressed!!!
;------state 1 -------- ;	
   	mov a, seconds
   	Set_Cursor(1,11)
    Display_BCD(seconds)
    cjne a, soaktime, FOREVER
    
    lcall TurnOvenOff
   
 
   lcall State_change ; going to soak time state 
  
   clr tr2   			; restarting timer 2 to keep track of the time lasped since we reached soaktemp
   mov a, #0
   mov seconds, a
   setb tr2
   
 loop: 
   mov a, seconds
   Set_Cursor(1,11)
    Display_BCD(seconds)
    cjne a, reflowtime, loop
    lcall TurnOvenOn
   
   lcall State_change ; going to soak time state 
  
   clr tr2   			; restarting timer 2 to keep track of the time lasped since we reached soaktemp
   mov a, #0
   mov seconds, a
   setb tr2
   ljmp FOREVER
   

  

  

	
TurnOvenOff:
	clr OvenButton	
  ret
TurnOvenOn:
	setb OvenButton
  ret



;beeper function to indicate reflow process has started
; needs to be called in order to use.
; 
Reflow_start:
 setb BEEPER
 
 Wait_Milli_Seconds(#255)
 clr BEEPER
 ret
 
State_change:
 setb BEEPER
 Wait_Milli_Seconds(#255)
 clr BEEPER
 ret
 
Open_toaster_oven:
 setb BEEPER
 cpl BEEPER
 Wait_Milli_Seconds(#255)
 clr BEEPER
 ret
 

END 

