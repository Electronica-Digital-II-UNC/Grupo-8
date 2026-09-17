; TRABAJO DE LABORATORIO 3: DISPLAYS MULTIPLEXADOS
; PIC16F887 - Frecuencia: 4 MHz
;
; ASIGNACIÓN DE PINES:
; - RD0 a RD7: Banco de 8 LEDs 
; - RB0 a RB6: Segmentos de los Displays 
; - RA0: Habilitación Display 1 (Decenas) 
; - RA1: Habilitación Display 2 (Unidades) 
; - RA4: Pulsador de Incremento (Activo en bajo '0')
    
    LIST        p=16F887
    #INCLUDE    <p16f887.inc>


; VARIABLES EN MEMORIA RAM (Banco 0)
    CBLOCK  0x20
        CONTADOR        ; Registro con la cuenta binaria (0 a 99)
        DECENAS         ; Dígito de decenas (0 a 9)
        UNIDADES        ; Dígito de unidades (0 a 9)
        TEMP_BIN        ; Variable temporal para conversión BCD
        ESTADO_ANT_PUL  ; Bandera de estado del pulsador para lectura no bloqueante
        DELAY_VAR1      ; Variables para retardo de multiplexación (~5 ms)
        DELAY_VAR2
    ENDC


; VECTORES DE INICIO (Compatibilidad con Bootloader AN1310)

    ORG     0x0000
    GOTO    INICIO

    ORG     0x0008

; TABLA DE DECODIFICACIÓN 7 SEGMENTOS (anodo Común)
; Segmentos: RB6:g, RB5:f, RB4:e, RB3:d, RB2:c, RB1:b, RB0:a

TABLA_7SEG:
    ADDWF   PCL, F
    RETLW   B'11000000'     ; 0
    RETLW   B'11111001'     ; 1
    RETLW   B'10100100'     ; 2
    RETLW   B'10110000'     ; 3
    RETLW   B'10011001'     ; 4
    RETLW   B'10010010'     ; 5
    RETLW   B'10000010'     ; 6
    RETLW   B'11111000'     ; 7
    RETLW   B'10000000'     ; 8
    RETLW   B'10010000'     ; 9


; INICIALIZACIÓN Y CONFIGURACIÓN DE PUERTOS

INICIO:
    ; Desactivar funciones analógicas
    BANKSEL ANSEL
    CLRF    ANSEL
    CLRF    ANSELH

    ; Configuración de dirección de puertos
    BANKSEL TRISD
    CLRF    TRISD           ; PORTD completo como salida 
    CLRF    TRISB           ; PORTB completo como salida 
    BCF     TRISA, 0        ; RA0 como salida 
    BCF     TRISA, 1        ; RA1 como salida 
    BSF     TRISA, 4        ; RA4 como entrada 

    ; Inicialización de registros y puertos
    BANKSEL PORTD
    CLRF    PORTD
    CLRF    PORTB
    BCF     PORTA, 0        ; Apaga ambos displays al inicio
    BCF     PORTA, 1
    CLRF    CONTADOR
    CLRF    DECENAS
    CLRF    UNIDADES
    CLRF    ESTADO_ANT_PUL

BUCLE_PRINCIPAL:
    ; Actualizar el banco de 8 LEDs con el valor binario
    MOVF    CONTADOR, W
    MOVWF   PORTD

    ; Descomponer el número binario en Decenas y Unidades
    CALL    CONVERSION_BCD

    ; Refrescar Display 1 (Decenas)
    BCF     PORTA, 1        ; Apagar Unidades
    MOVF    DECENAS, W
    CALL    TABLA_7SEG
    MOVWF   PORTB           ; Cargar segmentos de decenas
    BSF     PORTA, 0        ; Encender Decenas
    CALL    RETARDO_5MS

    ; Refrescar Display 2 (Unidades)
    BCF     PORTA, 0        ; Apagar Decenas
    MOVF    UNIDADES, W
    CALL    TABLA_7SEG
    MOVWF   PORTB           ; Cargar segmentos de unidades
    BSF     PORTA, 1        ; Encender Unidades
    CALL    RETARDO_5MS

    ; Sondeo no bloqueante del pulsador de incremento en RA4
    BTFSS   PORTA, 4
    GOTO    PULSADOR_PRESIONADO

    ; Si RA4 está en '1' (suelto), se reinicia la bandera de detección
    CLRF    ESTADO_ANT_PUL
    GOTO    BUCLE_PRINCIPAL

PULSADOR_PRESIONADO:
    ; Verificar si ya se había registrado la pulsación actual
    MOVF    ESTADO_ANT_PUL, F
    BTFSS   STATUS, Z
    GOTO    BUCLE_PRINCIPAL 

    ; Registrar el flanco descendente 
    MOVLW   0x01
    MOVWF   ESTADO_ANT_PUL

    ; Incrementar contador con límite en 99
    INCF    CONTADOR, F
    MOVLW   D'100'
    SUBWF   CONTADOR, W
    BTFSC   STATUS, Z
    CLRF    CONTADOR        ; Si llegó a 100, vuelve a 00

    GOTO    BUCLE_PRINCIPAL


; CONVERSIÓN BINARIO A DECIMAL 
CONVERSION_BCD:
    CLRF    DECENAS
    MOVF    CONTADOR, W
    MOVWF   TEMP_BIN

RESTA_10:
    MOVLW   D'10'
    SUBWF   TEMP_BIN, W
    BTFSS   STATUS, C       ; Si C = 0, el resultado es negativo 
    GOTO    FIN_BCD
    MOVWF   TEMP_BIN        ; Guarda el resultado restado
    INCF    DECENAS, F      ; Incrementa contador de decenas
    GOTO    RESTA_10

FIN_BCD:
    MOVF    TEMP_BIN, W
    MOVWF   UNIDADES        
    RETURN


; RETARDO DE MULTIPLEXACIÓN (~5 ms a 4 MHz)
RETARDO_5MS:
    MOVLW   D'7'
    MOVWF   DELAY_VAR1
L_5_1:
    MOVLW   D'236'
    MOVWF   DELAY_VAR2
L_5_2:
    DECFSZ  DELAY_VAR2, F
    GOTO    L_5_2
    DECFSZ  DELAY_VAR1, F
    GOTO    L_5_1
    RETURN

    END