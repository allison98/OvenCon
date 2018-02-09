calculations:
	push acc
	push psw
	; Vout calculations
	mov x, Result
	mov x+1, Result+1
	mov x+2, #0
	mov x+3, #0
	Load_y(410)
	lcall mul32
	Load_y(1023)
	lcall div32
	; we now have Vout in x
	Load_y(273)
	lcall sub32
;	; calculation for the temperature

	lcall hex2bcd
	mov a, x
		pop psw 
	pop acc
	ret