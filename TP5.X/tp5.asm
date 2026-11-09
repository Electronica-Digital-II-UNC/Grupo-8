LIST        p=16F887
    #INCLUDE    <p16f887.inc>
 
; ---------------- Parametros ----------------
PRECARGA    EQU .12         ; valor inicial de TMR0 (igual que el TdL4)
DEB_MS      EQU .20         ; antirrebote del teclado en ms
 
EST_VIS     EQU .0          ; estado: visualizacion
EST_EDIC    EQU .1          ; estado: edicion
 
NO_TECLA    EQU 0xFF        ; codigo "ninguna tecla"
 
TEC_A       EQU .10         ; codigos logicos de las teclas que no son numeros
TEC_B       EQU .11
TEC_C       EQU .12
TEC_D       EQU .13
TEC_AST     EQU .14         ; '*'
TEC_NUM     EQU .15         ; '#'
 
F_NUEVA     EQU .0          ; FLAGS: 1 = hay una tecla nueva sin procesar
 
; ---------------- Variables ----------------
    CBLOCK  0x20
        CONF0           ; valor CONFIRMADO: unidades      -> display RA0
        CONF1           ;                   decenas       -> display RA1
        CONF2           ;                   centenas      -> display RA2
        CONF3           ;                   unidades de mil -> display RA3
        EDIT0           ; valor EN EDICION (mismo orden)
        EDIT1
        EDIT2
        EDIT3
 
        BASE_DISP       ; direccion del arreglo que se muestra (CONF0 o EDIT0)
        CURSOR          ; cifra seleccionada: 0..3 (3 = izquierda, 0 = derecha)
        ESTADO          ; EST_VIS / EST_EDIC
        FLAGS
 
        DIGITO          ; indice del selector que se enciende (0..3 = RA0..RA3)
        SELMASK         ; selector one-hot (01,02,04,08) antes de invertir
        TICKS_PEND      ; ticks de 1 ms pendientes de atender
 
        TECLA_CRUDA     ; lectura de este ms (0..15 o NO_TECLA)
        TECLA_ANT       ; lectura del ms anterior
        TECLA_ESTABLE   ; ultimo estado validado por el antirrebote
        TECLA_EVENTO    ; tecla nueva ya traducida a su codigo logico
        DEB_CNT         ; contador de antirrebote
        FILA_IDX        ; fila que se explora (0..3)
        FILA_MASK       ; patron de filas para PORTD
        COL_IDX         ; columna detectada (0..3)
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
    FILL    (NOP), .2       ; compensacion: completa 1000 us (igual que TdL4)
    MOVLW   PRECARGA        ; recargar TMR0
    MOVWF   TMR0
    BCF     INTCON, T0IF    ; limpiar la bandera
 
    MOVLW   0x0F            ; 1) apagar el digito anterior (RA0..RA3 = 1)
    MOVWF   PORTA
    FILL    (NOP), .10      ;    tiempo muerto: deja apagar los transistores
 
    MOVF    BASE_DISP, W    ; 2) buscar el numero que va en este display
    ADDWF   DIGITO, W       ;    FSR = BASE_DISP + DIGITO
    MOVWF   FSR             ;    (BASE_DISP = CONF0 o EDIT0 segun el estado)
    MOVF    INDF, W         ;    W = numero (0..9)
    CALL    TABLA_7SEG      ;    convertirlo a segmentos
    MOVWF   PORTB           ;    ponerlo en el bus
 
    MOVF    ESTADO, W       ;    en edicion: punto en la cifra del cursor
    XORLW   EST_EDIC
    BTFSS   STATUS, Z
    GOTO    ISR_SELECTOR
    MOVF    CURSOR, W
    XORWF   DIGITO, W
    BTFSC   STATUS, Z
    BSF     PORTB, 7
 
ISR_SELECTOR:
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

TABLA_7SEG:                 ; numero (0..9) -> segmentos, catodo comun
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
 

TABLA_TECLAS:
    ADDWF   PCL, F
    RETLW   .1              ; fila 0, col 0
    RETLW   .2              ; fila 0, col 1
    RETLW   .3              ; fila 0, col 2
    RETLW   TEC_A           ; fila 0, col 3
    RETLW   .4              ; fila 1, col 0
    RETLW   .5              ; fila 1, col 1
    RETLW   .6              ; fila 1, col 2
    RETLW   TEC_B           ; fila 1, col 3
    RETLW   .7              ; fila 2, col 0
    RETLW   .8              ; fila 2, col 1
    RETLW   .9              ; fila 2, col 2
    RETLW   TEC_C           ; fila 2, col 3
    RETLW   TEC_AST         ; fila 3, col 0
    RETLW   .0              ; fila 3, col 1
    RETLW   TEC_NUM         ; fila 3, col 2
    RETLW   TEC_D           ; fila 3, col 3
 

INICIO:
    BANKSEL ANSEL
    CLRF    ANSEL           ; todo digital
    CLRF    ANSELH
 
    BANKSEL TRISD
    MOVLW   b'11110000'     ; RD0..RD3 salidas (filas), RD4..RD7 entradas (columnas)
    MOVWF   TRISD
    CLRF    TRISB           ; segmentos salida
    BCF     TRISA, 0        ; selectores RA0..RA3 salida
    BCF     TRISA, 1
    BCF     TRISA, 2
    BCF     TRISA, 3
    BSF     TRISA, 4        ; RA4 (pulsador del TdL4) queda como entrada, sin uso
    MOVLW   b'11000001'     ; RBPU=1, T0CS=0 (Fosc/4), PSA=0, prescaler 1:4
    MOVWF   OPTION_REG
 
    BANKSEL PORTA           ; de aqui en adelante, siempre banco 0
    MOVLW   0x0F            ; todos los displays apagados (activos en bajo)
    MOVWF   PORTA
    CLRF    PORTB
    MOVLW   0xFF            ; filas en reposo (todas en '1')
    MOVWF   PORTD
 
    CLRF    CONF0           ; valor inicial 0000
    CLRF    CONF1
    CLRF    CONF2
    CLRF    CONF3
    CLRF    EDIT0
    CLRF    EDIT1
    CLRF    EDIT2
    CLRF    EDIT3
    MOVLW   CONF0           ; se muestra el valor confirmado
    MOVWF   BASE_DISP
    MOVLW   .3
    MOVWF   CURSOR
    CLRF    ESTADO          ; arranca en visualizacion
    CLRF    FLAGS
 
    MOVLW   NO_TECLA
    MOVWF   TECLA_CRUDA
    MOVWF   TECLA_ANT
    MOVWF   TECLA_ESTABLE
    CLRF    DEB_CNT
 
    CLRF    TICKS_PEND
    CLRF    DIGITO
    MOVLW   0x01
    MOVWF   SELMASK
 
    MOVLW   PRECARGA
    MOVWF   TMR0
    BCF     INTCON, T0IF
    MOVLW   b'10100000'     ; GIE=1, T0IE=1
    MOVWF   INTCON
 
; =========================================================================
; PROGRAMA PRINCIPAL
; =========================================================================
PRINCIPAL:
    MOVF    TICKS_PEND, F
    BTFSC   STATUS, Z
    GOTO    PRINCIPAL       ; nada pendiente
    MOVLW   .1              ; consumir un tick (no se pierde ninguno)
    SUBWF   TICKS_PEND, F
 
    CALL    TECLADO_1MS     ; DETECCION: explora el teclado y aplica antirrebote
 
    BTFSS   FLAGS, F_NUEVA  ; hubo una tecla nueva?
    GOTO    PRINCIPAL
    BCF     FLAGS, F_NUEVA
    MOVF    TECLA_EVENTO, W
    CALL    PROCESAR_TECLA  ; INTERPRETACION: que hace esa tecla
    GOTO    PRINCIPAL
 

LEER_TECLADO:
    CLRF    FILA_IDX
    MOVLW   b'11111110'     ; primera fila en '0' (RD0)
    MOVWF   FILA_MASK
LT_FILA:
    MOVF    FILA_MASK, W    ; activar una fila (las otras en '1')
    MOVWF   PORTD
    FILL    (NOP), .4       ; dejar que se estabilicen las columnas
    SWAPF   PORTD, W        ; columnas RD4..RD7 -> bits 0..3
    ANDLW   0x0F
    XORLW   0x0F            ; ahora: bit en '1' = columna apretada
    BTFSS   STATUS, Z
    GOTO    LT_HAY_TECLA
 
    BSF     STATUS, C       ; pasar a la fila siguiente:
    RLF     FILA_MASK, F    ;   11111110 -> 11111101 -> 11111011 -> 11110111
    INCF    FILA_IDX, F
    MOVLW   .4
    XORWF   FILA_IDX, W
    BTFSS   STATUS, Z
    GOTO    LT_FILA
 
    MOVLW   0xFF            ; ninguna tecla: filas en reposo
    MOVWF   PORTD
    RETLW   NO_TECLA
 
LT_HAY_TECLA:
    MOVWF   TEMP            ; TEMP = columnas apretadas
    MOVLW   0xFF            ; filas en reposo
    MOVWF   PORTD
    CLRF    COL_IDX
LT_COLUMNA:                 ; buscar el primer bit en '1' = columna
    RRF     TEMP, F
    BTFSC   STATUS, C
    GOTO    LT_CODIGO
    INCF    COL_IDX, F
    GOTO    LT_COLUMNA
LT_CODIGO:                  ; codigo = fila*4 + columna
    BCF     STATUS, C
    RLF     FILA_IDX, W     ; W = fila*2
    MOVWF   TEMP
    BCF     STATUS, C
    RLF     TEMP, W         ; W = fila*4
    ADDWF   COL_IDX, W      ; W = fila*4 + columna
    RETURN
 
; ---- Antirrebote y deteccion de tecla nueva (se llama cada 1 ms) ----
TECLADO_1MS:
    CALL    LEER_TECLADO
    MOVWF   TECLA_CRUDA
 
    XORWF   TECLA_ESTABLE, W    ; igual al estado estable?
    BTFSC   STATUS, Z
    GOTO    TEC_SIN_CAMBIO      ; si: ninguna o mantenida
 
    MOVF    TECLA_CRUDA, W      ; distinta: igual a la lectura anterior?
    XORWF   TECLA_ANT, W
    BTFSS   STATUS, Z
    GOTO    TEC_REINICIAR       ; no: todavia rebota, se empieza a contar de nuevo
 
    INCF    DEB_CNT, F          ; misma lectura otro ms: contar
    MOVLW   DEB_MS
    XORWF   DEB_CNT, W
    BTFSS   STATUS, Z
    RETURN                      ; todavia no paso el tiempo de antirrebote
 
    CLRF    DEB_CNT             ; cambio validado
    MOVF    TECLA_ESTABLE, W    ; TEMP = estado anterior
    MOVWF   TEMP
    MOVF    TECLA_CRUDA, W      ; nuevo estado estable
    MOVWF   TECLA_ESTABLE
 
    INCF    TEMP, W             ; el anterior era NO_TECLA (0xFF + 1 = 0)?
    BTFSS   STATUS, Z
    RETURN                      ; no: fue una LIBERACION (no hace nada)
    INCF    TECLA_ESTABLE, W    ; el nuevo es NO_TECLA?
    BTFSC   STATUS, Z
    RETURN
 
    MOVF    TECLA_ESTABLE, W    ; TECLA NUEVA: traducir y avisar al principal
    CALL    TABLA_TECLAS
    MOVWF   TECLA_EVENTO
    BSF     FLAGS, F_NUEVA
    RETURN
 
TEC_SIN_CAMBIO:
    MOVF    TECLA_CRUDA, W
    MOVWF   TECLA_ANT
    CLRF    DEB_CNT
    RETURN
 
TEC_REINICIAR:
    MOVF    TECLA_CRUDA, W
    MOVWF   TECLA_ANT
    CLRF    DEB_CNT
    RETURN
 

PROCESAR_TECLA:
    MOVWF   TEMP                ; TEMP = tecla
    MOVF    ESTADO, W
    XORLW   EST_EDIC
    BTFSC   STATUS, Z
    GOTO    PT_EDICION
 
    ; ---- VISUALIZACION: solo '#' hace algo ----
    MOVF    TEMP, W
    XORLW   TEC_NUM
    BTFSS   STATUS, Z
    RETURN
    MOVF    CONF0, W            ; copiar el valor confirmado a la edicion
    MOVWF   EDIT0
    MOVF    CONF1, W
    MOVWF   EDIT1
    MOVF    CONF2, W
    MOVWF   EDIT2
    MOVF    CONF3, W
    MOVWF   EDIT3
    MOVLW   .3                  ; cursor en la cifra de la izquierda
    MOVWF   CURSOR
    MOVLW   EDIT0               ; mostrar la copia en edicion
    MOVWF   BASE_DISP
    MOVLW   EST_EDIC
    MOVWF   ESTADO
    RETURN
 
    ; ---- EDICION ----
PT_EDICION:
    MOVLW   .10                 ; es un numero (tecla < 10)?
    SUBWF   TEMP, W             ; W = tecla - 10  (C = 0 si tecla < 10)
    BTFSS   STATUS, C
    GOTO    PT_NUMERO
 
    MOVF    TEMP, W
    XORLW   TEC_A
    BTFSC   STATUS, Z
    GOTO    PT_IZQUIERDA
    MOVF    TEMP, W
    XORLW   TEC_B
    BTFSC   STATUS, Z
    GOTO    PT_DERECHA
    MOVF    TEMP, W
    XORLW   TEC_C
    BTFSC   STATUS, Z
    GOTO    PT_BORRAR
    MOVF    TEMP, W
    XORLW   TEC_D
    BTFSC   STATUS, Z
    GOTO    PT_CONFIRMAR
    MOVF    TEMP, W
    XORLW   TEC_AST
    BTFSC   STATUS, Z
    GOTO    PT_CANCELAR
    RETURN                      ; '#' en edicion: no hace nada
 
PT_NUMERO:                      ; EDIT[CURSOR] = numero y avanzar
    MOVLW   EDIT0
    ADDWF   CURSOR, W
    MOVWF   FSR
    MOVF    TEMP, W
    MOVWF   INDF
    GOTO    PT_DERECHA
 
PT_IZQUIERDA:                   ; cursor + 1, hasta 3 como maximo
    MOVF    CURSOR, W
    XORLW   .3
    BTFSC   STATUS, Z
    RETURN                      ; ya esta en la cifra de la izquierda
    INCF    CURSOR, F
    RETURN
 
PT_DERECHA:                     ; cursor - 1, hasta 0 como minimo
    MOVF    CURSOR, F
    BTFSC   STATUS, Z
    RETURN                      ; ya esta en la cifra de la derecha
    MOVLW   .1
    SUBWF   CURSOR, F
    RETURN
 
PT_BORRAR:                      ; valor en edicion = 0000
    CLRF    EDIT0
    CLRF    EDIT1
    CLRF    EDIT2
    CLRF    EDIT3
    MOVLW   .3
    MOVWF   CURSOR
    RETURN
 
PT_CONFIRMAR:                   ; guardar la edicion como valor confirmado
    MOVF    EDIT0, W
    MOVWF   CONF0
    MOVF    EDIT1, W
    MOVWF   CONF1
    MOVF    EDIT2, W
    MOVWF   CONF2
    MOVF    EDIT3, W
    MOVWF   CONF3
    GOTO    PT_A_VISUALIZACION
 
PT_CANCELAR:                    ; descartar la edicion
PT_A_VISUALIZACION:
    MOVLW   CONF0               ; mostrar el valor confirmado
    MOVWF   BASE_DISP
    MOVLW   EST_VIS
    MOVWF   ESTADO
    RETURN
 
    END


