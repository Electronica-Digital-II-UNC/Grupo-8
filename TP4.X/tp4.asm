LIST        p=16F887
    #INCLUDE    <p16f887.inc>

; ---------------- Parametros ----------------
PRECARGA    EQU .12         ; valor inicial de TMR0 (ver calculo arriba)
DEB_MS      EQU .20         ; antirrebote en ms


INI_S_T     EQU .0          ; decenas de segundo
INI_S_U     EQU .0          ; unidades de segundo
INI_CS_T    EQU .0          ; decenas de centesima

EST_DET     EQU .0          ; estados del cronometro
EST_CONT    EQU .1
EST_PAUSA   EQU .2

F_PRES      EQU .0          ; BTN_FLAGS: 1 = pulsador estable presionado
F_LARGA     EQU .1          ; BTN_FLAGS: 1 = la pulsacion larga ya actuo

; ---------------- Variables ----------------
    CBLOCK  0x20
        CS_U            ; centesimas unidades  -> display RA0
        CS_T            ; centesimas decenas   -> display RA1
        S_U             ; segundos unidades    -> display RA2
        S_T             ; segundos decenas     -> display RA3
                        
        DIGITO          ; indice del selector que se enciende (0..3 = RA0..RA3)
        SELMASK         ; selector one-hot (01,02,04,08) antes de invertir
        TICKS_PEND      ; ticks de 1 ms pendientes de atender
        CNT_MS          ; ms acumulados hacia una centesima (0..9)
        ESTADO          ; EST_DET / EST_CONT / EST_PAUSA
        BTN_FLAGS
        DEB_CNT         ; contador de antirrebote
        PRESS_L         ; duracion de la presion (16 bits, ms)
        PRESS_H
        TEMP
    ENDC

    CBLOCK  0x70        ; RAM comun a todos los bancos (contexto de la ISR)
        W_TEMP
        STATUS_TEMP
        PCLATH_TEMP
        FSR_TEMP
    ENDC

; ---------------- Vectores ----------------
    ORG     0x0000
    GOTO    INICIO

    ORG     0x0004
    GOTO    ISR             ; vector de interrupcion del 16F887

    ORG     0x0008          ; destino que usa el bootloader AN1310 (como en el TP3)

ISR:
    MOVWF   W_TEMP          ; guardar contexto
    SWAPF   STATUS, W
    MOVWF   STATUS_TEMP
    MOVF    PCLATH, W
    MOVWF   PCLATH_TEMP
    CLRF    PCLATH          ; llamadas y tabla en pagina 0
    BANKSEL PORTB           ; banco 0
    MOVF    FSR, W          ; la ISR usa FSR: tambien se guarda
    MOVWF   FSR_TEMP

    BTFSC   INTCON, T0IF    ; consultar la bandera de Timer0
    CALL    ISR_TMR0
    GOTO    SALIR_ISR

SALIR_ISR:
    MOVF    FSR_TEMP, W     ; restaurar contexto
    MOVWF   FSR
    MOVF    PCLATH_TEMP, W
    MOVWF   PCLATH
    SWAPF   STATUS_TEMP, W
    MOVWF   STATUS
    SWAPF   W_TEMP, F
    SWAPF   W_TEMP, W
    RETFIE


ISR_TMR0:
    FILL    (NOP), .2       ; compensacion: completa 1000 us (ver calculo)
    MOVLW   PRECARGA        ; recargar TMR0
    MOVWF   TMR0
    BCF     INTCON, T0IF    ; limpiar la bandera

    MOVLW   0x0F            ; 1) apagar el digito anterior (RA0..RA3 = 1)
    MOVWF   PORTA
    FILL    (NOP), .10      ;    tiempo muerto: deja apagar los transistores

    MOVLW   CS_U            ; 2) buscar el numero que va en este display
    ADDWF   DIGITO, W       ;    FSR = CS_U + DIGITO
    MOVWF   FSR
    MOVF    INDF, W         ;    W = numero (0..9)
    CALL    TABLA_7SEG      ;    convertirlo a segmentos
    MOVWF   PORTB           ;    ponerlo en el bus
    MOVLW   .2              ;    es el display de unidades de segundo (RA2)?
    XORWF   DIGITO, W
    BTFSC   STATUS, Z
    BSF     PORTB, 7        ;    si: prender el punto (separador SS.CC)

    MOVF    SELMASK, W      ; 3) habilitar solo ese selector (en '0')
    XORLW   0x0F
    MOVWF   PORTA

    INCF    DIGITO, F       ; avanzar al proximo digito
    BCF     STATUS, C
    RLF     SELMASK, F
    BTFSS   SELMASK, 4      ; paso del cuarto?
    GOTO    TMR0_TICK
    CLRF    DIGITO
    MOVLW   0x01
    MOVWF   SELMASK
TMR0_TICK:
    INCF    TICKS_PEND, F   ; avisar al principal: paso 1 ms
    RETURN


TABLA_7SEG:
    ADDWF   PCL, F
    RETLW   b'00111111'     ; 0
    RETLW   b'00000110'     ; 1
    RETLW   b'01011011'     ; 2
    RETLW   b'01001111'     ; 3
    RETLW   b'01100110'     ; 4
    RETLW   b'01101101'     ; 5
    RETLW   b'01111101'     ; 6
    RETLW   b'00000111'     ; 7
    RETLW   b'01111111'     ; 8
    RETLW   b'01101111'     ; 9


INICIO:
    BANKSEL ANSEL
    CLRF    ANSEL           ; todo digital
    CLRF    ANSELH

    BANKSEL TRISD
    CLRF    TRISD           ; PORTD salida
    CLRF    TRISB           ; segmentos salida
    BCF     TRISA, 0        ; selectores RA0..RA3 salida
    BCF     TRISA, 1
    BCF     TRISA, 2
    BCF     TRISA, 3
    BSF     TRISA, 4        ; pulsador entrada
    MOVLW   b'11000001'     ; RBPU=1, T0CS=0 (Fosc/4), PSA=0, prescaler 1:4
    MOVWF   OPTION_REG

    BANKSEL PORTA           ; de aqui en adelante, siempre banco 0
    MOVLW   0x0F            ; todos los displays apagados (activos en bajo)
    MOVWF   PORTA
    CLRF    PORTB
    CLRF    PORTD

    CLRF    TICKS_PEND
    CLRF    CNT_MS
    CLRF    CS_U            ; arranca mostrando 00.00
    CLRF    CS_T
    CLRF    S_U
    CLRF    S_T
    CLRF    ESTADO          ; arranca detenido
    CLRF    BTN_FLAGS
    CLRF    DEB_CNT
    CLRF    PRESS_L
    CLRF    PRESS_H
    CLRF    DIGITO
    MOVLW   0x01
    MOVWF   SELMASK

    MOVLW   PRECARGA
    MOVWF   TMR0
    BCF     INTCON, T0IF
    MOVLW   b'10100000'     ; GIE=1, T0IE=1
    MOVWF   INTCON

;PROGRAMA PRINCIPAL
PRINCIPAL:
    MOVF    TICKS_PEND, F
    BTFSC   STATUS, Z
    GOTO    PRINCIPAL       ; nada pendiente
    MOVLW   .1              ; consumir un tick (no se pierde ninguno)
    SUBWF   TICKS_PEND, F
    CALL    TICK_1MS
    GOTO    PRINCIPAL

; ---------------- Tarea de cada milisegundo ----------------
TICK_1MS:
    CALL    BOTON_1MS       ; antirrebote + duracion + acciones
    MOVF    ESTADO, W
    XORLW   EST_CONT
    BTFSS   STATUS, Z
    RETURN                  ; detenido o pausado: no acumula tiempo
    INCF    CNT_MS, F
    MOVLW   .10
    XORWF   CNT_MS, W
    BTFSS   STATUS, Z
    RETURN
    CLRF    CNT_MS          ; 10 ms = 1 centesima
    CALL    INC_CENT
    RETURN

; ---------------- Incremento de tiempo (digitos decimales) ----------------

INC_CENT:
    INCF    CS_U, W         ; W = CS_U + 1
    XORLW   .10
    BTFSC   STATUS, Z
    GOTO    INC_CS_T        ; llego a 10: pasa a la siguiente cifra
    INCF    CS_U, F
    RETURN
INC_CS_T:
    CLRF    CS_U
    INCF    CS_T, W
    XORLW   .10
    BTFSC   STATUS, Z
    GOTO    INC_S_U
    INCF    CS_T, F
    RETURN
INC_S_U:
    CLRF    CS_T
    INCF    S_U, W
    XORLW   .10
    BTFSC   STATUS, Z
    GOTO    INC_S_T
    INCF    S_U, F
    RETURN
INC_S_T:
    CLRF    S_U
    INCF    S_T, W
    XORLW   .6
    BTFSC   STATUS, Z
    GOTO    INC_VUELTA
    INCF    S_T, F
    RETURN
INC_VUELTA:
    CLRF    S_T             ; 59:99 -> 00:00
    RETURN

; ---------------- Poner a cero / cargar inicio ----------------
PONER_A_CERO:               ; tambien limpia el acumulador de ms
    CLRF    CNT_MS
    CLRF    CS_U
    CLRF    CS_T
    CLRF    S_U
    CLRF    S_T
    RETURN

CARGAR_INICIO:              ; inicio desde cero (o valor de prueba)
    CLRF    CNT_MS          ; (no llama a PONER_A_CERO para no usar
    CLRF    CS_U            ;  un nivel mas de pila)
    MOVLW   INI_CS_T
    MOVWF   CS_T
    MOVLW   INI_S_U
    MOVWF   S_U
    MOVLW   INI_S_T
    MOVWF   S_T
    RETURN

;PULSADOR
BOTON_1MS:
    MOVLW   .0
    BTFSS   PORTA, 4
    MOVLW   .1              ; W = 1 si el pin esta presionado (RA4 = 0)
    MOVWF   TEMP
    MOVLW   .0
    BTFSC   BTN_FLAGS, F_PRES
    MOVLW   .1              ; W = 1 si el estado estable es "presionado"
    XORWF   TEMP, W         ; W = 0 si coinciden
    BTFSC   STATUS, Z
    GOTO    BTN_IGUAL

    INCF    DEB_CNT, F      ; el pin difiere del estado estable: contar
    MOVLW   DEB_MS
    XORWF   DEB_CNT, W
    BTFSS   STATUS, Z
    GOTO    BTN_DURACION    ; todavia no se valida el cambio
    CLRF    DEB_CNT         ; cambio validado
    MOVLW   b'00000001'     ; invertir el bit F_PRES (bit 0)
    XORWF   BTN_FLAGS, F
    BTFSS   BTN_FLAGS, F_PRES
    GOTO    BTN_LIBERACION
    CLRF    PRESS_L         ; presion validada: arranca la medicion de duracion
    CLRF    PRESS_H
    BCF     BTN_FLAGS, F_LARGA
    RETURN
BTN_LIBERACION:             ; liberacion validada
    BTFSS   BTN_FLAGS, F_LARGA
    CALL    ACCION_CORTA    ; solo si la larga no actuo
    BCF     BTN_FLAGS, F_LARGA
    RETURN

BTN_IGUAL:
    CLRF    DEB_CNT
BTN_DURACION:               ; medir mientras el estado estable sea "presionado"
    BTFSS   BTN_FLAGS, F_PRES
    RETURN
    BTFSC   BTN_FLAGS, F_LARGA
    RETURN
    INCF    PRESS_L, F
    BTFSC   STATUS, Z
    INCF    PRESS_H, F
    MOVLW   0xE8            ; 1000 = 0x03E8
    XORWF   PRESS_L, W
    BTFSS   STATUS, Z
    RETURN
    MOVLW   0x03
    XORWF   PRESS_H, W
    BTFSS   STATUS, Z
    RETURN
    BSF     BTN_FLAGS, F_LARGA      ; la larga actua una sola vez
    CALL    ACCION_LARGA
    RETURN

; ---------------- Acciones ----------------
ACCION_CORTA:
    MOVF    ESTADO, W
    BTFSC   STATUS, Z
    GOTO    AC_INICIAR      ; detenido -> inicia desde cero
    XORLW   EST_CONT
    BTFSC   STATUS, Z
    GOTO    AC_PAUSAR       ; contando -> pausa
    MOVLW   EST_CONT        ; pausado -> reanuda
    MOVWF   ESTADO
    RETURN
AC_PAUSAR:
    MOVLW   EST_PAUSA
    MOVWF   ESTADO
    RETURN
AC_INICIAR:
    CALL    CARGAR_INICIO
    MOVLW   EST_CONT
    MOVWF   ESTADO
    RETURN

ACCION_LARGA:
    MOVF    ESTADO, W
    BTFSC   STATUS, Z
    RETURN                  ; detenido: permanece en cero
    CALL    PONER_A_CERO    ; contando/pausado -> detiene y pone a cero
    CLRF    ESTADO
    RETURN

    END


