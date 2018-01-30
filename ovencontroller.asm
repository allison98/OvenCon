$MODLP51
org 0000H
   ljmp MainProgram

CLK  EQU 22118400
BAUD equ 115200
BRG_VAL equ (0x100-(CLK/(16*BAUD)))
REF equ 4.096

; These �EQU� must match the wiring between the microcontroller and ADC
CE_ADC EQU P2.0
MY_MOSI EQU P2.1
MY_MISO EQU P2.2
MY_SCLK EQU P2.3
BEEPER EQU P2.4 ; placeholder pin for beeper

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
DSEG at 30H
x:   ds 4
y:   ds 4
bcd: ds 5
Result: ds 2
coldtemp: ds 4
reflowstate: ds 1 ; Used for changing states/displaying states. Not used anywhere else (as of Jan 30). Assign a number to each state
soaktemp: ds 1
soaktime: ds 1
reflowtemp: ds 1
reflowtime: ds 1
countererror: ds 1

BSEG
startflag: dbit 1
errorflag: dbit 1

CSEG
; These 'equ' must match the wiring between the microcontroller and the LCD!
LCD_RS equ P1.1
LCD_RW equ P1.2
LCD_E  equ P1.3
LCD_D4 equ P3.2
LCD_D5 equ P3.3
LCD_D6 equ P3.4
LCD_D7 equ P3.5
HIGH_TEMP EQU P3.6
; make sure that this is same with the rest of the ckt 
OvenPin equ Px.x
StartButton equ Px.x 


$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

$NOLIST
$include(math32.inc) ; A library of Lmath functions
$LIST



; constant strings  
Test_msg:  db 'Temp:xx.xx*C', 0
MenuMessage1: db '1.Soak Temp', 0
MenuMessage2: db '2.Soak Time', 0
MenuMessage3: db '3.Reflow Temp', 0
MenuMessage4: db '4.Reflow Time', 0


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
	cpl SOUND_OUT; Connect speaker to P3.7!
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
  
	mov a, second 	; Increment the BCD counter
	cjne a, #0x59, incc
	mov a, #0x0
	ljmp da1
  
incc:
	add a, #0x01 ;THIS IS ADDING SECONDS
da1:
	da a ; Decimal adjust instruction.  Check datasheet for more details!
	mov second, a

increaseerror:  
  mov a, countererror
  inc a
  mov countererror, a

  
;CHECK TO SEE IF SECOND HAS RESET, THEN INCREMENT MINUTES
  mov a, second	
	cjne a, #0x0,Timer2_ISR_done 
	mov a, minute
	add a, #0x01 ;increase min
	da a ; Decimal adjust instruction.  Check datasheet for more details!
	mov minute, a	
	
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
    lcall LCD_4BIT
    mov reflowstate, #0   ; do nothing state
    mov reflowparam, #0   ; menu
    mov countererror, #0	; to check if the thermocouple is in the oven
		
    ;initial message 
    Set_Cursor(1, 1)
    Send_Constant_String(#Test_msg)
    Set_Cursor(1,11)
    WriteData(#223) ; print the degree sign   
    
    lcall InitSerialPort
		lcall INIT_SPI
    
    
    ljmp Menu_select1
    
FOREVER: ;this will be how the oven is being controlled ; jump here once start button is pressed!!!
	
  lcall checkstop
  lcall checkerror
  
	lcall readingcoldjunction ;answer in 'bcd' is saved in variable called 'coldtemp'
  
  
  
	ljmp FOREVER
  
;---------------------------------;
; END 											      ;
;---------------------------------; 

  
;---------------------------------;
; functions						 				    ;
;---------------------------------;      




checkstop:
 	jnb STARTBUTTON, stop         ; start the reflow process
  Wait_Milli_Seconds(#50)
  jnb STARTBUTTON, stop 
  Wait_Milli_Seconds(#50)
  ret
stop:
	lcall TurnOvenOff
  ljmp Menu_select1
  

;---------------------------------- ;
; SSR Box communicating with the 	  ;
; Microcontroller 									;
;(1) uses OvenButton to communicate ; 
  ;with the transistor to turn the 	;
  ;oven or off											;
;(2) 															
;
;
;-----------------------------------;
	

TurnOvenOff:
	clear OvenButton
  ret
TurnOvenOn:
	setb OvenButton
  ret



;beeper function to indicate reflow process has started
; needs to be called in order to use.
; 
Reflow_start:
 setb BEEPER
 cpl BEEPER
 Wait_Milli_Seconds(#500)
 clr BEEPER
 ret
 
State_change:
 setb BEEPER
 cpl BEEPER
 Wait_Milli_Seconds(#500)
 clr BEEPER
 ret
 
Open_toaster_oven:
 setb BEEPER
 cpl BEEPER
 Wait_Milli_Seconds(#5000)
 clr BEEPER
 ret
 
;As a safety measure, the reflow process must be aborted if the oven doesn�t reach at least 50oC in the first 60 seconds of operation
checkerror: 
	push acc
  push psw
  
  mov a, counterror
  cjne a, #0x60, noerror
  
  ; check if oven temp is still less than 50 in the first 60 secondsload_x(oventemp) ; what is this variable 
  Load_y(50)
	;x<y
	lcall x_lt_y
	jnb mf, noerror
  lcall TurnOvenOff
  
noerror:
  pop acc
  pop psw 
	ret

readingcoldjunction: ;read the cold junction from the adc
;reading the adc
	push acc
  push psw
  
	clr CE_ADC 
	mov R0, #00000001B ; Start bit:1 
	lcall DO_SPI_G
	mov R0, #10000000B ; Single ended, read channel 0 
	lcall DO_SPI_G 
	mov a, R1          ; R1 contains bits 8 and 9 
	anl a, #00000011B  ; We need only the two least significant bits 
	mov Result+1, a    ; Save result high.
	mov R0, #55H ; It doesn't matter what we transmit... 
	lcall DO_SPI_G 
	mov Result, R1     ; R1 contains bits 0 to 7.  Save result low. 
	setb CE_ADC 
	;wait for 1 second 
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
  
	lcall Calculate_Temp_in_Celcius 
  mov a, bcd
  mov coldtemp, a
  
  pop acc
  pop psw
  ret   
   
;------------------------------;
; Temperature Reader From Sam	 ;
;------------------------------;
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

	
;Trying to trasfer the binary value in ADC into BCD and then into 
;ASCII to show in putty
Calculate_Temp_in_Celcius: 	
	clr a 
	Load_x(0)	; 
	Load_y(0)
	; load the result into X 
	mov a, Result+0
	mov X, a
	mov a, Result+1
	mov X+1, a
	Load_Y (4096)
	lcall mul32;
	Load_Y(1023)
	lcall div32;  
	;calculte temperature 
	Load_Y(273)
	mov temp, X
	lcall sub32
	lcall hex2bcd ; converts binary in x to BCD in BCD
	lcall Display_Temp_LCD 
;	lcall Display_Temp_Putty
	ret
	
Show_Celcius: 
	lcall Display_Temp_LCD
	lcall Display_Temp_Putty
	ret
	
	
; Display Temperature in Putty!
Display_Temp_Putty:
	Send_BCD(bcd+1)
	Send_BCD(bcd)
	mov a, #'\r'
	lcall putchar
	mov a, #'\n'
	lcall putchar
	ret	

; Display Temperature in LCD
Display_Temp_LCD:
; show temp in Celcius 
	Set_Cursor(1, 6);
	Display_BCD(bcd+1)
	Set_Cursor(1, 9); 
	ret


;--------------------------------------;
; Menu - Set soak parameters         	 ;
;--------------------------------------;
Menu_select1:  
  WriteCommand(#0x01)
  Wait_Milli_Seconds(#50)
Menu_select2:
	Set_Cursor(1, 1)
  Send_Constant_String(#MenuMessage1)
	Set_Cursor(2, 1)
  Send_Constant_String(#MenuMessage2)
	Wait_Milli_Seconds(#50)
  
  jnb BUTTON_1, Jump_to_Set_SoakTemp1     ;go to set Soak Temperature
	Wait_Milli_Seconds(#50)
  jnb BUTTON_1, Jump_to_Set_SoakTemp1
  Wait_Milli_Seconds(#50)
  
  jnb BUTTON_2, Jump_to_Set_SoakTime1    ;go to set Soak Time
  Wait_Milli_Seconds(#50)
  jnb BUTTON_2, Jump_to_Set_SoakTime1
  Wait_Milli_Seconds(#50)
  
	jnb BUTTON_3, Jump_to_Menu_select3   ;go to second set of menus
	Wait_Milli_Seconds(#50)
  jnb BUTTON_3, Jump_to_Menu_select3
  Wait_Milli_Seconds(#50)
  
  jnb STARTBUTTON, FOREVER         ; start the reflow process
  Wait_Milli_Seconds(#50)
  jnb STARTBUTTON, FOREVER
  Wait_Milli_Seconds(#50)
  
	ljmp Menu_select2
  

Jump_to_Set_SoakTemp1:
	ljmp Set_SoakTemp1
  
Jump_to_Set_SoakTime1:
	ljmp Set_SoakTime1
  
Jump_to_Menu_select3:
	ljmp Menu_select3

; Settings - Soak Temperature
Set_SoakTemp1:
  WriteCommand(#0x01)          ;clear display
  Wait_Milli_Seconds(#50)
  Set_Cursor(1, 1)
	Display_BCD(soaktemp)
Set_SoakTemp2:
	jnb BUTTON_1, SoakTemp_inc   ;might need a 'Jump_to'
  Wait_Milli_Seconds(#50)
	jnb BUTTON_1, SoakTemp_inc  
	Wait_Milli_Seconds(#50)
  jnb BUTTON_2, SoakTemp_dec  
	Wait_Milli_Seconds(#50)
  jnb BUTTON_2, SoakTemp_dec 
	Wait_Milli_Seconds(#50)
  jnb BUTTON_3, gobacktomenu1@@@@@@@@ ;set this later, might need more 'Jump_to' functions
	Wait_Milli_Seconds(#50)
  jnb BOOT_BUTTON, gobacktomenu1@@@@@@@@ ;set this later
  ljmp Set_SoakTemp2
  
SoakTemp_inc:   ;Can include some display message to indicate which setting we're on
	mov a, soaktemp
  add a, #0x01
  da a
  mov soaktemp, a
  Set_Cursor(1, 1)
  Display_BCD(soaktemp)
  ljmp Set_SoakTemp2
  
SoakTemp_dec:
  mov a, soaktemp
	add a, #0x99
	da a
	mov soaktemp, a
	Set_Cursor(1, 1)
	Display_BCD(soaktemp)
	ljmp Set_SoakTemp2

; Settings - Soak Time
Set_SoakTime1:
  WriteCommand(#0x01)          ;clear display
  Wait_Milli_Seconds(#50)
  Set_Cursor(1, 1)
	Display_BCD(soaktime)
Set_SoakTime2:
	jnb BUTTON_1, SoakTime_inc
  Wait_Milli_Seconds(#50)
	jnb BUTTON_1, SoakTime_inc  
	Wait_Milli_Seconds(#50)
  jnb BUTTON_2, SoakTime_dec  
	Wait_Milli_Seconds(#50)
  jnb BUTTON_2, SoakTime_dec 
	Wait_Milli_Seconds(#50)
  jnb BOOT_BUTTON, gobacktomenu1@@@@@@@@ ;set this later
	Wait_Milli_Seconds(#50)
  jnb BOOT_BUTTON, gobacktomenu1@@@@@@@@ ;set this later
  ljmp Set_SoakTime2

SoakTime_inc:   ;Can include some display message to indicate which setting we're on
	mov a, soaktime
  add a, #0x01
  da a
  mov soaktime, a
  Set_Cursor(1, 1)
  Display_BCD(soaktime)
  ljmp Set_SoakTime2
  
SoakTime_dec:
  mov a, soaktime
	add a, #0x99
	da a
	mov soaktime, a
	Set_Cursor(1, 1)
	Display_BCD(soaktime)
	ljmp Set_SoakTime2

; Second set of Menu - Set eflow parameters
Menu_select3:
  WriteCommand(#0x01)
  Wait_Milli_Seconds(#50)
Menu_select4:
	Set_Cursor(1, 1)
  Send_Constant_String(#MenuMessage3)
	Set_Cursor(2, 1)
  Send_Constant_String(#MenuMessage4)
	Wait_Milli_Seconds(#50)
  
  jnb BUTTON_1, Jump_to_Set_ReflowTemp1     ;go to set Soak Temperature
	Wait_Milli_Seconds(#50)
  jnb BUTTON_1, Jump_to_Set_ReflowTemp1
  Wait_Milli_Seconds(#50)
  
  jnb BUTTON_2, Jump_to_Set_ReflowTime1    ;go to set Soak Time
  Wait_Milli_Seconds(#50)
  jnb BUTTON_2, Jump_to_Set_ReflowTime1
  Wait_Milli_Seconds(#50)
  
	jnb BUTTON_3, Jump_to_Menu_select2   ;go to second set of menus
	Wait_Milli_Seconds(#50)
  jnb BUTTON_3, Jump_to_Menu_select2
  
  jnb STARTBUTTON, starttimer         ; start the reflow process
  Wait_Milli_Seconds(#50)
  jnb STARTBUTTON, starttimer
  Wait_Milli_Seconds(#50)
  sjmp jumped
 
starttimer:
  lcall Timer2_Init
  ljmp FOREVER
 
jumpmed:  
	ljmp Menu_select4

Jump_to_Set_ReflowTemp1:
	ljmp Set_ReflowTemp1
  
Jump_to_Set_ReflowTime1:
	ljmp Set_ReflowTime1
  
Jump_to_Menu_select2:
	ljmp Menu_select2
  
; Settings - Reflow Temperature
Set_ReflowTemp1:
  WriteCommand(#0x01)          ;clear display
  Wait_Milli_Seconds(#50)
  Set_Cursor(1, 1)
	Display_BCD(reflowtemp)
Set_ReflowTemp2:
	jnb BUTTON_1, ReflowTemp_inc
  Wait_Milli_Seconds(#50)
	jnb BUTTON_1, ReflowTemp_inc  
	Wait_Milli_Seconds(#50)
  jnb BUTTON_2, ReflowTemp_dec  
	Wait_Milli_Seconds(#50)
  jnb BUTTON_2, ReflowTemp_dec 
	Wait_Milli_Seconds(#50)
  jnb BOOT_BUTTON, gobacktomenu3@@@@@@@@ ;set this later
	Wait_Milli_Seconds(#50)
  jnb BOOT_BUTTON, gobacktomenu3@@@@@@@@ ;set this later
  ljmp Set_ReflowTemp2

ReflowTemp_inc:   ;Can include some display message to indicate which setting we're on
	mov a, reflowtemp
  add a, #0x01
  da a
  mov reflowtemp, a
  Set_Cursor(1, 1)
  Display_BCD(reflowtemp)
  ljmp Set_ReflowTemp2
  
ReflowTemp_dec:
  mov a, reflowtemp
	add a, #0x99
	da a
	mov reflowtemp, a
	Set_Cursor(1, 1)
	Display_BCD(reflowtemp)
	ljmp Set_ReflowTemp2

; Settings - Reflow Time
Set_ReflowTime1:
  WriteCommand(#0x01)          ;clear display
  Wait_Milli_Seconds(#50)
  Set_Cursor(1, 1)
	Display_BCD(reflowtime)
Set_ReflowTime2:
	jnb BUTTON_1, ReflowTime_inc
  Wait_Milli_Seconds(#50)
	jnb BUTTON_1, ReflowTime_inc  
	Wait_Milli_Seconds(#50)
  jnb BUTTON_2, ReflowTime_dec  
	Wait_Milli_Seconds(#50)
  jnb BUTTON_2, ReflowTime_dec 
	Wait_Milli_Seconds(#50)
  jnb BOOT_BUTTON, gobacktomenu3@@@@@@@@ ;set this later
	Wait_Milli_Seconds(#50)
  jnb BOOT_BUTTON, gobacktomenu3@@@@@@@@ ;set this later
  ljmp Set_ReflowTime2

ReflowTime_inc:   ;Can include some display message to indicate which setting we're on
	mov a, reflowtime
  add a, #0x01
  da a
  mov reflowtime, a
  Set_Cursor(1, 1)
  Display_BCD(reflowtime)
  ljmp Set_ReflowTime2
  
ReflowTime_dec:
  mov a, reflowtime
	add a, #0x99
	da a
	mov reflowtime, a
	Set_Cursor(1, 1)
	Display_BCD(reflowtime)
	ljmp Set_ReflowTime2

END




