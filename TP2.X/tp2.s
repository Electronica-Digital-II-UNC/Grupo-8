
; TRABAJO DE LABORATORIO 2: ENTRADAS Y SALIDAS DIGITALES
; PIC16F887 - Frecuencia: 4 MHz

; ASIGNACIÓN DE PINES:
; - RD0 (LSB) a RD7 (MSB): Banco de 8 LEDs
; - RA4 (Pin 6): Pulsador de Contador / Incremento (Activo en bajo '0')
; - RA5 (Pin 7): Pulsador de Secuencia / Cambio de Modo (Activo en bajo '0')

    LIST        p=16F887
    #INCLUDE    <p16f887.inc>
    
; VARIABLES EN MEMORIA RAM (Banco 0)
    CBLOCK  0x20
        CONTADOR        ; Registro para almacenar la cuenta (0 a 255)
        PATRON_SEC      ; Registro para almacenar el patrón de rotación
        MODO_ACTUAL     ; 0 = Modo Contador, 1 = Modo Secuencia Luminosa
        DELAY_VAR1      ; Variables para retardos de tiempo
        DELAY_VAR2
        DELAY_VAR3
    ENDC


; VECTORES DE INICIO 
    ORG     0x0000
    GOTO    INICIO

    ORG     0x0008

; INICIALIZACIÓN Y CONFIGURACIÓN DE PUERTOS
INICIO:
    ; Configurar pines como digitales 
    BANKSEL ANSEL
    CLRF    ANSEL           ; Desactiva entradas analógicas AN0 a AN7 
    CLRF    ANSELH          ; Desactiva entradas analógicas AN8 a AN13

    ; Configurar dirección de los puertos
    BANKSEL TRISD
    CLRF    TRISD           ; Todo el Puerto D como SALIDA 
    BSF     TRISA, 4        ; RA4 como ENTRADA (Pulsador Contador)
    BSF     TRISA, 5        ; RA5 como ENTRADA (Pulsador Secuencia)

    ; Inicializar valores por defecto 
    BANKSEL PORTD
    CLRF    PORTD           ; Apagar todos los LEDs al inicio (00h)
    CLRF    CONTADOR        ; Inicializar la cuenta en 0
    CLRF    MODO_ACTUAL     ; Arranca en Modo Contador (0)
    
    MOVLW   B'00000001'     ; Inicializar patrón con el LED menos significativo encendido
    MOVWF   PATRON_SEC

; BUCLE PRINCIPAL
BUCLE_PRINCIPAL:
    ; Verificar si se presionó RA5 (Cambio de Modo / Secuencia)
    BTFSS   PORTA, 5
    CALL    CAMBIAR_MODO

    ; Evaluar qué modo está activo actualmente
    MOVF    MODO_ACTUAL, F
    BTFSS   STATUS, Z
    GOTO    RUTINA_SECUENCIA ; Si MODO_ACTUAL = 1 -> Va a la secuencia luminosa

; MODO 1: CONTADOR BINARIO (0 a 255)
RUTINA_CONTADOR:
    MOVF    CONTADOR, W
    MOVWF   PORTD           ; Muestra el valor actual de la cuenta en los 8 LEDs

    ; Verificar si se presiona RA4 (Incrementar cuenta)
    BTFSC   PORTA, 4
    GOTO    BUCLE_PRINCIPAL ; Si está en '1' (suelto), continúa el bucle

    ; Antirrebote al presionar RA4 (~20 ms)
    CALL    RETARDO_20MS
    BTFSC   PORTA, 4
    GOTO    BUCLE_PRINCIPAL ; Si volvió a '1', fue ruido o falso contacto

    ; Acción: Incrementar cuenta
    INCF    CONTADOR, F     ; Incrementa el registro CONTADOR (de 0 a 255 y regresa a 0)
    MOVF    CONTADOR, W
    MOVWF   PORTD           ; Actualiza el valor visual en los LEDs

ESPERAR_SOLTAR_RA4:
    ; Esperar hasta que el usuario libere el pulsador RA4
    BTFSS   PORTA, 4
    GOTO    ESPERAR_SOLTAR_RA4

    ; Antirrebote al soltar (~20 ms)
    CALL    RETARDO_20MS
    GOTO    BUCLE_PRINCIPAL

; MODO 2: SECUENCIA LUMINOSA (Desplazamiento por rotación de bits)
RUTINA_SECUENCIA:
    MOVF    PATRON_SEC, W
    MOVWF   PORTD           ; Muestra el bit activo en el banco de LEDs

    ; Operación de desplazamiento / rotación
    BCF     STATUS, C       ; Limpia el flag de Carry
    RLF     PATRON_SEC, F   ; Desplaza a la izquierda a través del Carry
    BTFSC   STATUS, C       ; Si el bit se desplazó fuera del byte (Carry = 1)
    BSF     PATRON_SEC, 0   ; Reingresa el bit encendido en la posición LSB (RD0)

    ; Retardo visible (~250 ms) que monitorea si se presiona RA5 para salir
    CALL    RETARDO_SECUENCIA
    GOTO    BUCLE_PRINCIPAL
    
; SUBRUTINA: CAMBIO DE MODO CON ANTIRREBOTE

CAMBIAR_MODO:
    CALL    RETARDO_20MS
    BTFSC   PORTA, 5
    RETURN                  ; Falso contacto

    ; Alternar el valor de MODO_ACTUAL (0 <-> 1)
    MOVLW   0x01
    XORWF   MODO_ACTUAL, F

ESPERAR_SOLTAR_RA5:
    BTFSS   PORTA, 5
    GOTO    ESPERAR_SOLTAR_RA5
    CALL    RETARDO_20MS
    RETURN
    
; RUTINAS DE RETARDO (Temporización a 4 MHz)

RETARDO_20MS:
    MOVLW   D'26'
    MOVWF   DELAY_VAR1
L_20_1:
    MOVLW   D'255'
    MOVWF   DELAY_VAR2
L_20_2:
    DECFSZ  DELAY_VAR2, F
    GOTO    L_20_2
    DECFSZ  DELAY_VAR1, F
    GOTO    L_20_1
    RETURN

RETARDO_SECUENCIA:
    MOVLW   D'5'
    MOVWF   DELAY_VAR3
L_SEC_1:
    CALL    RETARDO_20MS
    ; Permite cambiar de modo de forma inmediata sin esperar los 250ms completos
    BTFSS   PORTA, 5
    RETURN
    DECFSZ  DELAY_VAR3, F
    GOTO    L_SEC_1
    RETURN

    END


