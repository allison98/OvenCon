
$MODLP51
org 0000H
   ljmp MainProgram

CLK  EQU 22118400
BAUD equ 115200
BRG_VAL equ (0x100-(CLK/(16*BAUD)))
REF equ 4.096       ;reference at LM4040

; These ’EQU’ must match the wiring between the microcontroller and ADC
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
	
dseg at 0x30
;future variables
x:   ds 4
y:   ds 4
bcd: ds 5
Result: ds 2
coldtemp: ds 1
hottemp:ds 4
soaktemp: ds 1
soaktime: ds 1
reflowtemp: ds 1
reflowtime: ds 1
countererror: ds 1
temperature:ds 4
Count1ms:     ds 2 ; Used to determine when half second has passed 
reflowparam: ds 1
second: ds 1
minute: ds 1
temp: ds 1
count: ds 1

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
STARTBUTTON equ P0.5


$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

$NOLIST
$include(math32.inc) ; A library of Lmath functions
$LIST


; constant strings  
Test_msg:  db 'Temp:xx.xx*C', 0
MenuMessage1: db '1.Soak Temp', 0   ;used when selecting parameter
MenuMessage2: db '2.Soak Time', 0
MenuMessage3: db '3.Reflow Temp', 0
MenuMessage4: db '4.Reflow Time', 0
MenuSoakTemp: db 'Soak Temp:', 0  ;used when changing parameter
MenuSoakTime: db 'Soak Time:', 0
MenuReflowTemp: db 'Reflow Temp:', 0
MenuReflowTime: db 'Reflow Time:', 0
ReflowStateMess: db 'Reflow State', 0
SoakState: db 'Soak State', 0
TemperatureRise: db 'Temp. Increase',0
CoolingTemp: db 'Oven is cooling.',0


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
;	cpl SOUND_OUT; Connect speaker to P3.7!
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
	cjne a, #low(500), Timer2_ISR_done ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(500), Timer2_ISR_done
	
    ; cpl TR0 ; Enable/disable timer/counter 0. This line creates a beep-silence-beep-silence sound.
    ; where is halfsecondflag?					
					; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
  
	mov a, second 	; Increment the BCD counter

	add a, #0x01 ;THIS IS ADDING SECONDS

	da a ; Decimal adjust instruction.  Check datasheet for more details!
	mov second, a
	
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






MainProgram:
	mov sp, #07FH ; Initialize the stack pointer
	; Configure P0 in bidirectional mode
    mov P0M0, #0
    mov P0M1, #0
    setb EA 
    lcall LCD_4BIT
    mov soaktemp, #50
    mov soaktime, #0x65
    mov reflowtemp, #70
    mov reflowtime, #0x60
    mov second, #0
   ; mov countererror, #0	; to check if the thermocouple is in the oven
		
    ;initial message 
   ; Set_Cursor(1, 1)
   ; Send_Constant_String(#Test_msg)
   ; Set_Cursor(1,11)
   ; WriteData(#223) ; print the degree sign   
    mov count, #0
    
    lcall InitSerialPort
		lcall INIT_SPI
		lcall Timer0_Init
    lcall Timer2_Init
   ; ljmp Menu_select1 ;; selecting and setting profiles
    
FOREVER: ;this will be how the oven is being controlled ; jump here once start button is pressed!!!
;------state 1 -------- ;	
   Set_Cursor(1,1)
   Send_Constant_String(#TemperatureRise)
 ;  lcall checkstop       ;checks if stop button is pressed. If so, turns off oven and goes back to menu
   ;lcall checkerror      ;if error, terminate program and return
   lcall Readingtemperatures  ;calculates temperature of oven using thermocouple junctions
   lcall DisplayingLCD

   lcall cst ; checking if we have reached Soak Temp yet
  ; lcall State_change_BEEPER ; temp = soak temp, so going to soak time state 
   clr tr2   			; restarting timer 2 to keep track of the time lasped since we reached soaktemp
   mov a, #0x0
   mov second, a
   setb tr2
   sjmp skiped
 
 cst: 
  mov a, coldtemp
  mov b, soaktemp
  div AB
  mov a,b 
  cjne a, #0, FOREVER
  lcall TurnOvenOn
  ret
  


	
 
 skiped:
  ; after we reached the soak temp stay there for __ seconds
  ;-----state 2 ------;
soaktempchecked:
	Set_Cursor(1,1)
   Send_Constant_String(#SoakState)  
;	lcall checkstop	
   lcall Readingtemperatures
   lcall DisplayingLCD
  lcall keepingsoaktempsame ; boundary temp
  lcall keepingsoaktempsame1
  lcall checksoaktime ; if soak time is up go to next state
  sjmp soaktempchecked
  
; ---- state 3 ---- ; increaseing to reflow temp
increasereflowtemp: 
 ; lcall checkstop
  	Set_Cursor(1,1)
   Send_Constant_String(#TemperatureRise) 
  lcall Readingtemperatures
   lcall DisplayingLCD
  lcall checkingreflowtemp
 ; lcall State_change_BEEPER
  clr tr2
  mov a, #0
  mov second, a
  setb tr2

  ;----state 4 ---;
 reflowstate:
  ;lcall checkstop
  lcall Readingtemperatures
   lcall DisplayingLCD
   	Set_Cursor(1,1)
   Send_Constant_String(#ReflowStateMess) 
  lcall keepingreflowtempsame
  lcall keepingreflowtempsame1
  lcall checkreflowtime
  sjmp reflowstate
  
 ;------- state5-----;
 cooling:
 	Set_Cursor(1,1)
   Send_Constant_String(#CoolingTemp) 
 lcall Readingtemperatures
  lcall DisplayingLCD
 lcall waitforcooling
; lcall Open_oven_toaster_BEEPER
 
 ljmp $
  
;---------------------------------;
; functions						 				    ;
;---------------------------------; 

waitforcooling:


  clr c
  mov a, #60
  subb a, coldtemp
  jnc cooled
  ljmp cooling
  
  
;	load_X(coldtemp)
;  load_Y(60)
;  lcall x_gteq_y   ; compare if temp >= 60 
;  jnb mf, cooled
;  ljmp cooling
  
 
cooled:
	ret

; *********** STATE 2 **********
; After reaching the soak temperature we stay at that temp 
; for 60 to 120 seconds

keepingsoaktempsame:
  mov a, soaktemp
  add a, #5
  mov x, a
   
  clr c
  mov a, x
  subb a, coldtemp
  jnc soaktempisokay
  ljmp soaktemptoohigh

  ;load_Y(coldtemp)
  ;lcall x_gteq_y   ; compare if temp <= soaktemp + 10
 ; jnb mf, soaktemptoohigh; if mf!=1 then keep checking
 
 keepingsoaktempsame1:
  ; temp>= soaktemp-10
 ; load_Y(5)
 ; load_X(soaktemp)
 ; lcall sub32	
  mov a, soaktemp
  clr c
  subb a, #5
  mov x, a
  
  clr c
  mov a, coldtemp
  subb a, x
  jnc soaktempisokay
  ljmp soaktemptoolow
  
   
  
soaktempisokay:
	ret
  
soaktemptoohigh: 
  lcall TurnOvenOff
  ret
  
soaktemptoolow:
	lcall TurnOvenOn
  ret
  
 keepingreflowtempsame:
	; temp <=reflowtemp+10
	
 ; load_X(5)
 ; load_Y(reflowtemp)
 ; lcall add32		; upper bound for the straight line for the soak temp: soaktemp+10
   
    mov a, reflowtemp
  add a, #5
  mov x, a
    
  clr c
  mov a, x
  add a, coldtemp
  jnc soaktempisokay
  ljmp soaktemptoohigh
  
  ;load_Y(coldtemp)
  ;lcall x_gteq_y   ; compare if temp <= soaktemp + 10
 ; jnb mf, soaktemptoohigh; if mf!=1 then keep checking
 keepingreflowtempsame1:
  ; temp>= soaktemp-10
  ;load_Y(5)
  ;load_X(reflowtemp)
  ;lcall sub32	
  clr c
  mov a, reflowtemp
  subb a, #5
  mov x, a
  
  clr c
  mov a, coldtemp
  subb a, x
  jnc soaktempisokay
  ljmp soaktemptoolow
  
 ; lower bound for the straight line for the soak temp: soaktemp-10
;  load_Y(coldtemp)
 ; lcall x_gteq_y   ; compare if temp <= soaktemp - 10 
 ; jb mf, soaktemptoolow; if mf!=1 then keep checking
 ; ljmp soaktempisokay
  

checksoaktime:
	mov a, second
  cjne a, soaktime, soaknotdone
  lcall TurnOvenOn
  clr tr2
  mov a, #0
  mov second, a
  setb tr2
  ljmp increasereflowtemp
soaknotdone:
	ret 
  
checkreflowtime:
	mov a, second
  cjne a, reflowtime,reflownotdone
  lcall TurnOvenOff
  clr tr2
  mov a, #0
  mov second, a
  setb tr2
  ljmp cooling
reflownotdone:
	ret

; reading the thermocouple junction values 
Readingtemperatures:
  lcall readingcoldjunction ;answer in x is saved in variable called 'coldtemp'

  mov a, x
  mov coldtemp, a ;final temperature is in the temperature variable
  ret

; checking if the temperture at the hot end is equal to soak temp yet


;checkingsoaktemperature: 
;  clr c
 ; mov a, soaktemp
 ; subb a, coldtemp
 ; jnc Jump_to_FOREVER  
 ; lcall TurnOvenOff
 ; ret
Jump_to_FOREVER:
	ljmp FOREVER

; checking if the temperture at the hot end is equal to reflow temp yet
checkingreflowtemp: 
  clr c
  mov a, reflowtemp
  subb a, coldtemp
  jnc increasereflowtemp1
   

  ;load_X(coldtemp)
  ;load_Y(reflowtemp)
  
 ; lcall x_gteq_y   ; compare if temp >= reflowtemp 
 ; jnb mf, Jump_to_FOREVER ; if mf!=1 then keep checking
  ;this is what it should do if reflowtemperature = actual tempreature     
  lcall TurnOvenOff
  ret
increasereflowtemp1:
ljmp increasereflowtemp

 ;stop the process at any time  
checkstop:                     ; stop the reflow process
	jb STARTBUTTON, return
	jnb STARTBUTTON, $
	sjmp stop
return:
  ret
stop:
	lcall TurnOvenOff
    ljmp $

  
;---------------------------------- ;
; SSR Box communicating with the 	  ;
; Microcontroller 									;
;(1) uses OvenButton to communicate ; 
  ;with the transistor to turn the 	;
  ;oven or off											;
;(2) 																;
;																		;
;																		;
;-----------------------------------;
	
TurnOvenOff:
	clr OvenButton	
  ret
TurnOvenOn:
	setb OvenButton
  ret

DisplayingLCD:
	Set_Cursor(2,1)
	Display_BCD(second)
	
	Set_Cursor(2, 12)
	mov x, coldtemp
	lcall hex2bcd
	
	Display_BCD(bcd)
	Set_Cursor(2,15)
    WriteData(#0xDF)
    Set_Cursor(2,16)
    WriteData(#'C')
    
    ret
    
    



;As a safety measure, the reflow process must be aborted if the oven doesn’t reach at least 50oC in the first 60 seconds of operation
checkerror: 
	push acc
  push psw
  
;  mov x, second
;  Load_y(60)
;  lcall x_gteq_y
;  jnb mf, noerror; if mf = 0, then x<y, time<60secs, don't need to check time yet
  ;check temp because time>60sec
  
  clr c
  mov a, #0x60
  subb a, second
  jnc noerror
  
  mov a, #50
  subb a, coldtemp
  jnc noerror
  lcall TurnOvenOff
  
  ;mov x, coldtemp
  ;Load_y(50)
  ;lcall x_gteq_y
  ;jb mf, noerror  ;if mf = 1, then x>=y which is what we want, no error
  ;there is error, so turn off oven
  ;lcall TurnOvenOff
  
noerror:
  pop psw
  pop acc 
  ret
	
;------------------------------;
; Temperature Reader From Sam	 ;
;------------------------------;
	
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
  
	lcall Calculate_Temp_in_C 
    mov a, x
    mov coldtemp, a
  
	  pop psw
	  pop acc
	  ret   
	   

;Trying to transfer the binary value in ADC into BCD and then into 
;ASCII to show in putty
Calculate_Temp_in_C: 	
	clr a 
	Load_x(0)	; 
	Load_y(0)
	; load the result into X 
	mov a, Result+0
	mov X, a
	mov a, Result+1
	mov X+1, a
	Load_Y (410)
	lcall mul32;
	Load_Y(1023)
	lcall div32;  
	;calculte temperature 
	Load_Y(273)
	mov temp, X
	lcall sub32
	lcall hex2bcd ; converts binary in x to BCD in BCD
	;Set_Cursor(2, 13)
	;Display_BCD(bcd)
;	lcall Display_Temp_Putty
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

