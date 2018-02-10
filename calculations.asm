calculations:
	push acc
	push psw
	; Vout calculations
	mov x, Result
	mov x+1, Result+1
	mov x+2, #0
	mov x+3, #0
	Load_y(29)
	lcall mul32
	Load_y(2150)
	lcall add32

	; we now have Vout in x

;	; calculation for the temperature

	lcall hex2bcd
	mov a, x
	pop acc
	ret