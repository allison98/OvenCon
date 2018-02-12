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
BEEPER EQU P3.7 ; placeholder pin for beeper


SEGA equ P2.4
SEGB equ P2.5
SEGC equ P2.6
SEGD equ P2.7
SEGE equ P4.5
SEGF equ P4.4
SEGG equ P0.7
CA1  equ P0.1
CA2  equ P0.2
CA3  equ P0.0

TIMER0_RELOAD_L DATA 0xf2
TIMER1_RELOAD_L DATA 0xf3
TIMER0_RELOAD_H DATA 0xf4
TIMER1_RELOAD_H DATA 0xf5

TIMER0_RATE   EQU 4096             ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

C4			 EQU 262
D4      	 EQU 294
E4			 EQU 330
F4		 	 EQU 349
G4			 EQU 392
A4			 EQU 440
B4     	  	 EQU 494

C5			 EQU 523
D5      	 EQU 587
E5			 EQU 659
F5		 	 EQU 698
G5			 EQU 784
A5			 EQU 880
B5     	  	 EQU 988

G4F			 EQU 370
A4F			 EQU 415
B4F			 EQU 466
C5S			 EQU 554
D5F			 EQU 554
E5F			 EQU 622

C4_reload	EQU ((65536-(CLK/(2*C4))))
D4_reload   EQU ((65536-(CLK/(2*D4))))
E4_reload	EQU ((65536-(CLK/(2*E4))))
F4_reload	EQU ((65536-(CLK/(2*F4))))
G4_reload	EQU ((65536-(CLK/(2*G4))))
A4_reload	EQU ((65536-(CLK/(2*A4))))
B4_reload	EQU ((65536-(CLK/(2*B4))))

C5_reload	EQU ((65536-(CLK/(2*C5))))
D5_reload   EQU ((65536-(CLK/(2*D5))))
E5_reload	EQU ((65536-(CLK/(2*E5))))
F5_reload	EQU ((65536-(CLK/(2*F5))))
G5_reload	EQU ((65536-(CLK/(2*G5))))
A5_reload	EQU ((65536-(CLK/(2*A5))))
B5_reload	EQU ((65536-(CLK/(2*B5))))

G4F_reload	EQU ((65536-(CLK/(2*G4F))))
A4F_reload	EQU ((65536-(CLK/(2*A4F))))
B4F_reload	EQU ((65536-(CLK/(2*B4F))))
C5S_reload	EQU ((65536-(CLK/(2*C5S))))
D5F_reload	EQU ((65536-(CLK/(2*D5F))))
E5F_reload	EQU ((65536-(CLK/(2*E5F))))


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
Disp1:  ds 1 
Disp2:  ds 1
Disp3:  ds 1
state:  ds 1

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

StartButton equ P0.3
BUTTON_1 equ P0.4
BUTTON_2 equ P0.5
BUTTON_3 equ P0.6
OvenButton equ P1.0


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
ReflowStateMess: db 'Reflow State    ', 0
SoakState: db 'Soak State      ', 0
TemperatureRise: db 'Temp. Increase  ',0
CoolingTemp: db 'Oven is cooling.',0

Tone_Message1:     db '1Surprise 2Mario', 0
Tone_Message2:     db '   3Star Wars   ', 0


Blank: db '              ',0

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
; Used for the state change beeps ;
;---------------------------------;

Timer0_ISR:
	cpl BEEPER
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
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

  Inc_Done:
	; Check if half second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), Timer2_ISR_done ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(1000), Timer2_ISR_done
	
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
	;mov SEGP, c
	ret  
	
	MainProgram:
	mov sp, #07FH ; Initialize the stack pointer
	; Configure P0 in bidirectional mode
    mov P0M0, #0
    mov P0M1, #0
    mov auxr, #00010001B
    setb EA 
    lcall LCD_4BIT
    mov soaktemp, #0x0
    
    mov soaktime, #0x0

    mov reflowtemp, #0x0
   
    mov reflowtime, #0x0

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
  ;  lcall Timer2_Init
   lcall TurnOvenOff
  ; lcall TurnOvenOn
   ljmp Menu_select1 ;; selecting and setting profiles
   Menu_select1:  
  WriteCommand(#0x01)
  Wait_Milli_Seconds(#50)
Menu_select2:
  Set_Cursor(1, 1)
  Send_Constant_String(#MenuMessage1)
  Set_Cursor(2, 1)
  Send_Constant_String(#MenuMessage2)
  Wait_Milli_Seconds(#50) ;go to set Soak Temperature
  jb BUTTON_1, Menu_select2_2
  jnb BUTTON_1, $
  

  
END
