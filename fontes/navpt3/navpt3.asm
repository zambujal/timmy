; NAVPT3.BIN: o leitor de PT3 (Universal PT2/PT3/TS player, S.V.Bulba) para a musica de fundo
; do navegador. Fica na pagina 41 do DivMMC, mapeada em 2000h:
;   2000h  jp Inicia   (HL = modulo)
;   2003h  jp Toca     (uma vez por frame)
;   2006h  jp Cala
; 2009h: endereco do modulo (logo a seguir as variaveis); o modulo vai ate' 3FF7h
; (3FF8h-3FFFh: estado do navegador). Toca e Cala tem de ser chamados com DI (o leitor
; usa o SP para ler o modulo).
                    org 2000h
                    jp Inicia
                    jp PLAY
                    jp MUTE
                    dw Modulo           ; 2009h: onde vai o modulo
                    db "NP3"            ; 200Bh: assinatura
Inicia              xor a               ; um so' modulo (num TurboSound toca o 1.o), ABC, em ciclo
                    ld (SETUP),a
                    ld de,0
                    jp INIT
TonA	EQU 0
TonB	EQU 2
TonC	EQU 4
Noise	EQU 6
Mixer	EQU 7
AmplA	EQU 8
AmplB	EQU 9
AmplC	EQU 10
Env	EQU 11
EnvTp	EQU 13

;ChannelsVars
;	STRUCT	CHP
;reset group
PsInOr EQU 0
PsInSm EQU 1
CrAmSl EQU 2
CrNsSl EQU 3
CrEnSl EQU 4
TSlCnt EQU 5
CrTnSl EQU 6
TnAcc EQU 8
COnOff EQU 10
;reset group

OnOffD EQU 11

;IX for PTDECOD here (+12)
OffOnD EQU 12
OrnPtr EQU 13
SamPtr EQU 15
NNtSkp EQU 17
Note EQU 18
SlToNt EQU 19
Env_En EQU 20
Flags EQU 21
 ;Enabled - 0, SimpleGliss - 2
TnSlDl EQU 22
TSlStp EQU 23
TnDelt EQU 25
NtSkCn EQU 27
Volume EQU 28
;	ENDS
CHP EQU 29

;	STRUCT	VRS

CurPos EQU 0
PosSub EQU 1

ModNum EQU 2 ;bit0: ChipNum
	     ;bit1: 1-reversed patterns order (AlCo TS)
ChanA EQU 3
ChanB EQU ChanA+CHP
ChanC EQU ChanB+CHP

;GlobalVars
MODADDR EQU ChanC+CHP
OrnPtrs EQU MODADDR+2
SamPtrs EQU MODADDR+4
PatsPtr EQU MODADDR+6
AdInPtA EQU MODADDR+8
AdInPtB EQU MODADDR+10
AdInPtC EQU MODADDR+12
CrPsPtr EQU MODADDR+14
LPosPtr EQU MODADDR+16
Delay EQU MODADDR+18
DelyCnt EQU MODADDR+19
ESldAdd EQU MODADDR+20
CurESld EQU MODADDR+22
Env_Del EQU MODADDR+24
CurEDel EQU MODADDR+25
Ns_Base EQU MODADDR+26
AddToNs EQU MODADDR+27
AddToEn EQU MODADDR+28
EnvBase EQU MODADDR+29
AYREGS EQU MODADDR+31
;	ENDS
VRS EQU AYREGS+14

;Entry and other points
;START initialize playing of modules at MDLADDR (single module)
;START+3 initialization with module address in HL and DE (TS)
;START+5 play one quark
;START+8 mute
;START+10 setup and status flags

start:
	LD HL,0 ;(o LD HL,MDLADDR original: o SETUP tem de ficar em start+10)
	JR INIT
	JP PLAY
	JR MUTE
SETUP:
	defb 0 ;set bit0, if you want to play without looping
	     ;(optional);
	     ;set bit1 for PT2 and reset for PT3 before
	     ;calling INIT;
	     ;bits2-3: %00-ABC, %01-ACB, %10-BAC (optional);
	     ;bits4-5: %00-no TS, %01-2 modules TS, %10-
	     ;autodetect PT3 TS-format by AlCo (PT 3.7+);
	     ;Remark: old PT3 TS-format by AlCo (PT 3.6) is not
	     ;documented and must be converted to new standard.
	     ;bit6 is set each time, when loop point of 2nd TS
	     ;module is passed (optional).
	     ;bit7 is set each time, when loop point of 1st TS
	     ;or of single module is passed (optional).

;Identifier
	IFDEF IDENT
	defb "=UniPT2/PT3/TS-Player r.",Release,"="
	ENDIF



MUTE:
	XOR A
	LD H,A
	LD L,A
	LD (VARS1+AYREGS+AmplA),A
	LD (VARS1+AYREGS+AmplB),HL
	LD (VARS2+AYREGS+AmplA),A
	LD (VARS2+AYREGS+AmplB),HL
	JP ROUT

INIT:
;HL - AddressOfModule
;DE - AddresOf2ndModule
	PUSH DE
	PUSH HL
	LD HL,VARS
	LD (HL),0
	LD DE,VARS+1
	LD BC,VAR0END-VARS-1
	LDIR
	INC HL
	LD (VARS1+AdInPtA),HL ;ptr to zero
	LD (VARS2+AdInPtA),HL

	POP HL
	LD IY,VARS1+100
	LD A,(start+10)
	AND 2
	JP NZ,I_PT2

	CALL INITPT3
	LD HL,$1F18 ;(e_-SamCnv-2)*256+#18 ;ZXASM :(
	LD (SamCnv),HL
	LD A,$BA
	LD (OrnCP),A
	LD (SamCP),A
	LD A,$7B
	LD (OrnLD),A
	LD (SamLD),A
	LD A,$87
	LD (SamClc2),A
	POP HL
	;Use version and ton table of 1st module
	LD A,(IX+13-100) ;EXTRACT VERSION NUMBER
	SUB $30
	JR C,L20
	CP 10
	JR C,L21
L20:
	LD A,6
L21:
	LD (Version),A
	PUSH AF ;VolTable version
	CP 4
	LD A,(IX+99-100) ;TONE TABLE NUMBER
	RLA
	AND 7
	PUSH AF ;NoteTable number

	LD IY,VARS2+100
	LD A,(start+10)
	AND 48
	JR Z,NOTS
	CP 16
	JR Z,TwoPT3s
	LD A,(Version)
	CP 7
	JR C,NOTS
	LD A,(IX+98-100) ;ALCO TS MARKER
	CP $20
	JR Z,NOTS
	LD HL,VARS1
	LD DE,VARS2
	LD BC,VRS
	LDIR
	SET 1,(IY-100+ModNum)
	LD C,A
	ADD A,A
	ADD A,C
	SUB 2
	LD (TSSub),A
	JR AlCoTS_
TwoPT3s:
	CALL INITPT3
AlCoTS_:
	LD A,1
	LD (is_ts),A
	SET 0,(IY-100+ModNum)

NOTS:
	LD BC,PT3PD
	LD HL,0
	LD DE,PT3EMPTYORN
	JR INITCOMMON

I_PT2:
	CALL INITPT2
	LD HL,$51CB
	LD (SamCnv),HL
	LD A,$BB
	LD (OrnCP),A
	LD (SamCP),A
	LD A,$7A
	LD (OrnLD),A
	LD (SamLD),A
	LD A,$80
	LD (SamClc2),A
	POP HL
	LD A,5
	LD (Version),A
	PUSH AF
	LD A,2
	PUSH AF

	LD A,(start+10)
	AND 48
	JR Z,NOTS2

	LD IY,VARS2+100
	LD A,1
	LD (is_ts),A
	SET 0,(IY-100+ModNum)
	CALL INITPT2

NOTS2:
	LD BC,PT2PD
	LD HL,$8687
	LD DE,PT2EMPTYORN

INITCOMMON:

	IFDEF BASIC
	LD IY,$5C3A
	ENDIF

	LD (PTDEC),BC
	LD (PsCalc),HL
	PUSH DE

;note table data depacker
;(c) Ivan Roshin
	LD DE,T_PACK
	LD BC,T1_+(2*49)-1
TP_0:
	LD A,(DE)
	INC DE
	CP 15*2
	JR NC,TP_1
	LD H,A
	LD A,(DE)
	LD L,A
	INC DE
	JR TP_2
TP_1:
	PUSH DE
	LD D,0
	LD E,A
	ADD HL,DE
	ADD HL,DE
	POP DE
TP_2:
	LD A,H
	LD (BC),A
	DEC BC
	LD A,L
	LD (BC),A
	DEC BC
	SUB $F8*2 & $FF
	JR NZ,TP_0

	INC A
	LD (VARS1+DelyCnt),A
	LD (VARS2+DelyCnt),A
	LD HL,$F001 ;H - Volume, L - NtSkCn
	LD (VARS1+ChanA+NtSkCn),HL
	LD (VARS1+ChanB+NtSkCn),HL
	LD (VARS1+ChanC+NtSkCn),HL
	LD (VARS2+ChanA+NtSkCn),HL
	LD (VARS2+ChanB+NtSkCn),HL
	LD (VARS2+ChanC+NtSkCn),HL
	POP HL
	LD (VARS1+ChanA+OrnPtr),HL
	LD (VARS1+ChanB+OrnPtr),HL
	LD (VARS1+ChanC+OrnPtr),HL
	LD (VARS2+ChanA+OrnPtr),HL
	LD (VARS2+ChanB+OrnPtr),HL
	LD (VARS2+ChanC+OrnPtr),HL

	POP AF

;NoteTableCreator (c) Ivan Roshin
;A - NoteTableNumber*2+VersionForNoteTable
;(xx1b - 3.xx..3.4r, xx0b - 3.4x..3.6x..VTII1.0)

	LD HL,NT_DATA
	LD D,0
	ADD A,A
	LD E,A
	ADD HL,DE
	LD E,(HL)
	INC HL
	SRL E
	SBC A,A
	AND $A7 ;#00 (NOP) or #A7 (AND A)
	LD (L3),A
	EX DE,HL
	LD BC,T1_
	ADD HL,BC

	LD A,(DE)
	ADD A,T_ & $ff
	LD C,A
	ADC A,T_/256
	SUB C
	LD B,A
	PUSH BC
	LD DE,NT_
	PUSH DE

	LD B,12
L1:
	PUSH BC
	LD C,(HL)
	INC HL
	PUSH HL
	LD B,(HL)

	PUSH DE
	EX DE,HL
	LD DE,23
	LD IXH,8

L2:
	SRL B
	RR C
L3:
	defb $19	;AND A or NOP
	LD A,C
	ADC A,D	;=ADC 0
	LD (HL),A
	INC HL
	LD A,B
	ADC A,D
	LD (HL),A
	ADD HL,DE
	DEC IXH
	JR NZ,L2

	POP DE
	INC DE
	INC DE
	POP HL
	INC HL
	POP BC
	DJNZ L1

	POP HL
	POP DE

	LD A,E
	CP TCOLD_1 & $ff
	JR NZ,CORR_1
	LD A,$FD
	LD (NT_+$2E),A

CORR_1:
	LD A,(DE)
	AND A
	JR Z,TC_EXIT
	RRA
	PUSH AF
	ADD A,A
	LD C,A
	ADD HL,BC
	POP AF
	JR NC,CORR_2
	DEC (HL)
	DEC (HL)
CORR_2:
	INC (HL)
	AND A
	SBC HL,BC
	INC DE
	JR CORR_1

TC_EXIT:

	POP AF

;VolTableCreator (c) Ivan Roshin
;A - VersionForVolumeTable (0..4 - 3.xx..3.4x;
			   ;5.. - 2.x,3.5x..3.6x..VTII1.0)

	CP 5
	LD HL,$11
	LD D,H
	LD E,H
	LD A,$17
	JR NC,M1
	DEC L
	LD E,L
	XOR A
M1:
	LD (M2),A

	LD IX,VT_+16

	LD C,$F
INITV2:
	PUSH HL

	ADD HL,DE
	EX DE,HL
	SBC HL,HL

	LD B,$10
INITV1:
	LD A,L
M2:
	defb $7D
	LD A,H
	ADC A,0
	LD (IX),A
	INC IX
	ADD HL,DE
	DJNZ INITV1

	POP HL
	LD A,E
	CP $77
	JR NZ,M3
	INC E
M3:
	DEC C
	JR NZ,INITV2

	JP ROUT

INITPT3:
	CALL SETMDAD
	PUSH HL
	LD DE,100
	ADD HL,DE
	LD A,(HL)
	LD (IY-100+Delay),A
	PUSH HL
	POP IX
	ADD HL,DE
	CALL SETCPPT
	LD E,(IX+102-100)
	INC HL




	IFDEF CURPOSCOUNTER
	LD (IY-100+PosSub),L
	ENDIF
	ADD HL,DE
	CALL SETLPPT
	POP DE
	LD L,(IX+103-100)
	LD H,(IX+104-100)
	ADD HL,DE
	CALL SETPTPT
	LD HL,169
	ADD HL,DE
	CALL SETORPT
	LD HL,105
	ADD HL,DE

SETSMPT:
	LD (IY-100+SamPtrs),L
	LD (IY-100+SamPtrs+1),H
	RET

INITPT2:
	LD A,(HL)
	LD (IY-100+Delay),A
	PUSH HL
	PUSH HL
	PUSH HL
	INC HL
	INC HL
	LD A,(HL)
	INC HL
	CALL SETSMPT
	LD E,(HL)
	INC HL
	LD D,(HL)
	POP HL
	AND A
	SBC HL,DE
	CALL SETMDAD
	POP HL
	LD DE,67
	ADD HL,DE
	CALL SETORPT
	LD E,32
	ADD HL,DE
	LD C,(HL)
	INC HL
	LD B,(HL)
	LD E,30
	ADD HL,DE
	CALL SETCPPT
	LD E,A
	INC HL

	IFDEF CURPOSCOUNTER
	LD (IY-100+PosSub),L
	ENDIF

	ADD HL,DE
	CALL SETLPPT
	POP HL
	ADD HL,BC




SETPTPT:
	LD (IY-100+PatsPtr),L
	LD (IY-100+PatsPtr+1),H
	RET

SETMDAD:
	LD (IY-100+MODADDR),L
	LD (IY-100+MODADDR+1),H
	RET

SETORPT:
	LD (IY-100+OrnPtrs),L
	LD (IY-100+OrnPtrs+1),H
	RET

SETCPPT:
	LD (IY-100+CrPsPtr),L
	LD (IY-100+CrPsPtr+1),H
	RET

SETLPPT:
	LD (IY-100+LPosPtr),L
	LD (IY-100+LPosPtr+1),H
	RET

SETENBS:
	LD (IY-100+EnvBase),L
	LD (IY-100+EnvBase+1),H
	RET

SETESLD:
	LD (IY-100+CurESld),L
	LD (IY-100+CurESld+1),H
	RET

GETIX:
	PUSH IY
	POP IX
	ADD IX,DE
	RET

PTDECOD:
	CALL GETIX
PTDEC:	EQU $+1
	JP $C3C3

;PT2 pattern decoder
PD2_SAM:
	CALL SETSAM
	JR PD2_LOOP

PD2_EOff:
	LD (IX-12+Env_En),A
	JR PD2_LOOP

PD2_ENV:
	LD (IX-12+Env_En),16
	LD (IY-100+AYREGS+EnvTp),A
	LD A,(BC)
	INC BC
	LD L,A
	LD A,(BC)
	INC BC
	LD H,A
	CALL SETENBS
	JR PD2_LOOP

PD2_ORN:
	CALL SETORN
	JR PD2_LOOP

PD2_SKIP:
	INC A
	LD (IX-12+NNtSkp),A
	JR PD2_LOOP

PD2_VOL:
	RRCA
	RRCA
	RRCA
	RRCA
	LD (IX-12+Volume),A
	JR PD2_LOOP

PD2_GLIS:
	SET 2,(IX-12+Flags)
	INC A
	LD (IX-12+TnSlDl),A
	LD (IX-12+TSlCnt),A
	LD A,(BC)
	INC BC
        LD (IX-12+TSlStp),A
	ADD A,A
	SBC A,A
        LD (IX-12+TSlStp+1),A
	SCF
	JR PD2_LP2

PT2PD:
	AND A

PD2_LP2:
	EX AF,AF'
	
PD2_LOOP:
	LD A,(BC)
	INC BC
	ADD A,$20
	JR Z,PD2_REL
	JR C,PD2_SAM
	ADD A,96
	JR C,PD2_NOTE
	INC A
	JR Z,PD2_EOff
	ADD A,15
	JP Z,PD_FIN
	JR C,PD2_ENV
	ADD A,$10
	JR C,PD2_ORN
	ADD A,$40
	JR C,PD2_SKIP
	ADD A,$10
	JR C,PD2_VOL
	INC A
	JR Z,PD2_DEL
	INC A
	JR Z,PD2_GLIS
	INC A
	JR Z,PD2_PORT
	INC A
	JR Z,PD2_STOP
	LD A,(BC)
	INC BC
	LD (IX-12+CrNsSl),A
	JR PD2_LOOP

PD2_PORT:
	RES 2,(IX-12+Flags)
	LD A,(BC)
	INC BC
	INC BC ;ignoring precalc delta to right sound
	INC BC
	SCF
	JR PD2_LP2

PD2_STOP:
	LD (IX-12+TSlCnt),A
	JR PD2_LOOP

PD2_REL:
	LD (IX-12+Flags),A
	JR PD2_EXIT


PD2_DEL:
	CALL C_DELAY
	JR PD2_LOOP




PD2_NOTE:
	LD L,A
	LD A,(IX-12+Note)
	LD (PrNote+1),A
	LD (IX-12+Note),L
	XOR A
	LD (IX-12+TSlCnt),A
	SET 0,(IX-12+Flags)
	EX AF,AF'
	JR NC,NOGLIS2
	BIT 2,(IX-12+Flags)
	JR NZ,NOPORT2
	LD (LoStep),A
	ADD A,A
	SBC A,A
	EX AF,AF'
	LD H,A
	LD L,A
	INC A
	CALL SETPORT
NOPORT2:
	LD (IX-12+TSlCnt),1
NOGLIS2:
	XOR A


PD2_EXIT:
	LD (IX-12+PsInSm),A
	LD (IX-12+PsInOr),A
	LD (IX-12+CrTnSl),A
	LD (IX-12+CrTnSl+1),A
	JP PD_FIN

;PT3 pattern decoder
PD_OrSm:
	LD (IX-12+Env_En),0
	CALL SETORN
PD_SAM_:
	LD A,(BC)
	INC BC
	RRCA

PD_SAM:
	CALL SETSAM
	JR PD_LOOP

PD_VOL:
	RRCA
	RRCA
	RRCA
	RRCA
	LD (IX-12+Volume),A
	JR PD_LP2
	
PD_EOff:
	LD (IX-12+Env_En),A
	LD (IX-12+PsInOr),A
	JR PD_LP2

PD_SorE:
	DEC A
	JR NZ,PD_ENV
	LD A,(BC)
	INC BC
	LD (IX-12+NNtSkp),A
	JR PD_LP2

PD_ENV:
	CALL SETENV
	JR PD_LP2

PD_ORN:
	CALL SETORN
	JR PD_LOOP

PD_ESAM:
	LD (IX-12+Env_En),A
	LD (IX-12+PsInOr),A
	CALL NZ,SETENV
	JR PD_SAM_

PT3PD:
	LD A,(IX-12+Note)
	LD (PrNote+1),A
	LD L,(IX-12+CrTnSl)
	LD H,(IX-12+CrTnSl+1)
	LD (PrSlide+1),HL

PD_LOOP:
	LD DE,$2010
PD_LP2:
	LD A,(BC)
	INC BC
	ADD A,E
	JR C,PD_OrSm
	ADD A,D
	JR Z,PD_FIN
	JR C,PD_SAM
	ADD A,E
	JR Z,PD_REL
	JR C,PD_VOL
	ADD A,E
	JR Z,PD_EOff
	JR C,PD_SorE
	ADD A,96
	JR C,PD_NOTE
	ADD A,E
	JR C,PD_ORN
	ADD A,D
	JR C,PD_NOIS
	ADD A,E
	JR C,PD_ESAM
	ADD A,A
	LD E,A
	LD HL,SPCCOMS+$FF20-$2000
	ADD HL,DE
	LD E,(HL)
	INC HL
	LD D,(HL)
	PUSH DE
	JR PD_LOOP
	
PD_NOIS:
	LD (IY-100+Ns_Base),A
	JR PD_LP2

PD_REL:
	RES 0,(IX-12+Flags)
	JR PD_RES

PD_NOTE:
	LD (IX-12+Note),A
	SET 0,(IX-12+Flags)
	XOR A

PD_RES:
	LD (PDSP_+1),SP
	LD SP,IX
	LD H,A
	LD L,A
	PUSH HL
	PUSH HL
	PUSH HL
	PUSH HL
	PUSH HL
	PUSH HL
PDSP_:
	LD SP,$3131

PD_FIN:
	LD A,(IX-12+NNtSkp)
	LD (IX-12+NtSkCn),A
	RET

C_PORTM:
	LD A,(BC)
	INC BC
;SKIP PRECALCULATED TONE DELTA (BECAUSE
;CANNOT BE RIGHT AFTER PT3 COMPILATION)
	INC BC
	INC BC
	EX AF,AF'
	LD A,(BC) ;SIGNED TONE STEP
	INC BC
	LD (LoStep),A
	LD A,(BC)
	INC BC
	AND A
	EX AF,AF'
	LD L,(IX-12+CrTnSl)
	LD H,(IX-12+CrTnSl+1)

;Set portamento variables
;A - Delay; A' - Hi(Step); ZF' - (A'=0); HL - CrTnSl

SETPORT:
	RES 2,(IX-12+Flags)
	LD (IX-12+TnSlDl),A
	LD (IX-12+TSlCnt),A
	PUSH HL
	LD DE,NT_
	LD A,(IX-12+Note)
	LD (IX-12+SlToNt),A
	ADD A,A
	LD L,A
	LD H,0
	ADD HL,DE
	LD A,(HL)
	INC HL
	LD H,(HL)
	LD L,A
	PUSH HL
PrNote:
	LD A,$3E
	LD (IX-12+Note),A
	ADD A,A
	LD L,A
	LD H,0
	ADD HL,DE
	LD E,(HL)
	INC HL
	LD D,(HL)
	POP HL
	SBC HL,DE
	LD (IX-12+TnDelt),L
	LD (IX-12+TnDelt+1),H
	POP DE
Version: EQU $+1
	LD A,$3E
	CP 6
	JR C,OLDPRTM ;Old 3xxx for PT v3.5-
PrSlide:
	LD DE,$1111
	LD (IX-12+CrTnSl),E
	LD (IX-12+CrTnSl+1),D
LoStep:	EQU $+1
OLDPRTM:
	LD A,$3E
	EX AF,AF'
	JR Z,NOSIG
	EX DE,HL
NOSIG:
	SBC HL,DE
	JP P,SET_STP
	CPL
	EX AF,AF'
	NEG
	EX AF,AF'
SET_STP:
	LD (IX-12+TSlStp+1),A
	EX AF,AF'
	LD (IX-12+TSlStp),A
	LD (IX-12+COnOff),0
	RET

C_GLISS:
	SET 2,(IX-12+Flags)
	LD A,(BC)
	INC BC
	LD (IX-12+TnSlDl),A
	AND A
	JR NZ,GL36
	LD A,(Version) ;AlCo PT3.7+
	CP 7
	SBC A,A
	INC A
GL36:
	LD (IX-12+TSlCnt),A
	LD A,(BC)
	INC BC
	EX AF,AF'
	LD A,(BC)
	INC BC
	JR SET_STP

C_SMPOS:
	LD A,(BC)
	INC BC
	LD (IX-12+PsInSm),A
	RET

C_ORPOS:
	LD A,(BC)
	INC BC
	LD (IX-12+PsInOr),A
	RET

C_VIBRT:
	LD A,(BC)
	INC BC
	LD (IX-12+OnOffD),A
	LD (IX-12+COnOff),A
	LD A,(BC)
	INC BC
	LD (IX-12+OffOnD),A
	XOR A
	LD (IX-12+TSlCnt),A
	LD (IX-12+CrTnSl),A
	LD (IX-12+CrTnSl+1),A
	RET

C_ENGLS:
	LD A,(BC)
	INC BC
	LD (IY-100+Env_Del),A
	LD (IY-100+CurEDel),A
	LD A,(BC)
	INC BC
	LD L,A
	LD A,(BC)
	INC BC
	LD H,A
	LD (IY-100+ESldAdd),L
	LD (IY-100+ESldAdd+1),H
	RET

C_DELAY:
	LD A,(BC)
	INC BC
	LD (IY-100+Delay),A
	LD HL,VARS2+ModNum ;if AlCo_TS
	BIT 1,(HL)
	RET Z
	LD (VARS1+Delay),A
	LD (VARS1+DelyCnt),A
	LD (VARS2+Delay),A
	RET
	
SETENV:
	LD (IX-12+Env_En),E
	LD (IY-100+AYREGS+EnvTp),A
	LD A,(BC)
	INC BC
	LD H,A
	LD A,(BC)
	INC BC
	LD L,A
	CALL SETENBS
	XOR A
	LD (IX-12+PsInOr),A
	LD (IY-100+CurEDel),A
	LD H,A
	LD L,A
	JP SETESLD

SETORN:
	ADD A,A
	LD E,A
	LD D,0
	LD (IX-12+PsInOr),D
	LD L,(IY-100+OrnPtrs)
	LD H,(IY-100+OrnPtrs+1)
	ADD HL,DE
	LD E,(HL)
	INC HL
	LD D,(HL)
	LD L,(IY-100+MODADDR)
	LD H,(IY-100+MODADDR+1)
	ADD HL,DE
	LD (IX-12+OrnPtr),L
	LD (IX-12+OrnPtr+1),H
C_NOP:
	RET


SETSAM:
	ADD A,A
	LD E,A
	LD D,0
	LD L,(IY-100+SamPtrs);
	LD H,(IY-100+SamPtrs+1);
	ADD HL,DE
	LD E,(HL)
	INC HL
	LD D,(HL)
	LD L,(IY-100+MODADDR)
	LD H,(IY-100+MODADDR+1)
	ADD HL,DE
	LD (IX-12+SamPtr),L
	LD (IX-12+SamPtr+1),H
	RET

;ALL 16 ADDRESSES TO PROTECT FROM BROKEN PT3 MODULES
SPCCOMS:
	defw C_NOP
	defw C_GLISS
	defw C_PORTM
	defw C_SMPOS
	defw C_ORPOS
	defw C_VIBRT
	defw C_NOP
	defw C_NOP
	defw C_ENGLS
	defw C_DELAY
	defw C_NOP
	defw C_NOP
	defw C_NOP
	defw C_NOP
	defw C_NOP
	defw C_NOP

CHREGS:
	CALL GETIX
	XOR A
	LD (Ampl),A
	BIT 0,(IX+Flags)
	PUSH HL
	JP Z,CH_EXIT
	LD (CSP_+1),SP
	LD L,(IX+OrnPtr)
	LD H,(IX+OrnPtr+1)
	LD SP,HL
	POP DE
	LD H,A
	LD A,(IX+PsInOr)
	LD L,A
	ADD HL,SP
	INC A
		;PT2	PT3
OrnCP:
	INC A	;CP E	CP D
	JR C,CH_ORPS
OrnLD:
	defb 1	;LD A,D	LD A,E
CH_ORPS:
	LD (IX+PsInOr),A
	LD A,(IX+Note)
	ADD A,(HL)
	JP P,CH_NTP
	XOR A
CH_NTP:
	CP 96
	JR C,CH_NOK
	LD A,95
CH_NOK:
	ADD A,A
	EX AF,AF'
	LD L,(IX+SamPtr)
	LD H,(IX+SamPtr+1)
	LD SP,HL
	POP DE
	LD H,0
	LD A,(IX+PsInSm)
	LD B,A
	ADD A,A
SamClc2:
	ADD A,A ;or ADD A,B for PT2
	LD L,A
	ADD HL,SP
	LD SP,HL
	LD A,B
	INC A
		;PT2	PT3
SamCP:
	INC A	;CP E	CP D
	JR C,CH_SMPS
SamLD:	defb 1	;LD A,D	LD A,E
CH_SMPS:
	LD (IX+PsInSm),A
	POP BC
	POP HL

;Convert PT2 sample to PT3
		;PT2		PT3
SamCnv:
	POP HL  ;BIT 2,C	JR e_
	POP HL	
	LD H,B
	JR NZ,$+8
	EX DE,HL
	AND A
	SBC HL,HL
	SBC HL,DE
	LD D,C
	RR C
	SBC A,A
	CPL
	AND $3E
	RR C
	RR B
	AND C
	LD C,A
	LD A,B
	RRA
	RRA
	RR D
	RRA
	AND $9F
	LD B,A

e_:
	LD E,(IX+TnAcc)
	LD D,(IX+TnAcc+1)
	ADD HL,DE
	BIT 6,B
	JR Z,CH_NOAC
	LD (IX+TnAcc),L
	LD (IX+TnAcc+1),H
CH_NOAC:
	EX DE,HL
	EX AF,AF'
	ADD A,NT_ & $ff
	LD L,A
	ADC A,NT_/256
	SUB L
	LD H,A
	LD SP,HL
	POP HL
	ADD HL,DE
	LD E,(IX+CrTnSl)
	LD D,(IX+CrTnSl+1)
	ADD HL,DE
CSP_:
	LD SP,$3131
	EX (SP),HL
	XOR A
	OR (IX+TSlCnt)
	JR Z,CH_AMP
	DEC (IX+TSlCnt)
	JR NZ,CH_AMP
	LD A,(IX+TnSlDl)
	LD (IX+TSlCnt),A
	LD L,(IX+TSlStp)
	LD H,(IX+TSlStp+1)
	LD A,H
	ADD HL,DE
	LD (IX+CrTnSl),L
	LD (IX+CrTnSl+1),H
	BIT 2,(IX+Flags)
	JR NZ,CH_AMP
	LD E,(IX+TnDelt)
	LD D,(IX+TnDelt+1)
	AND A
	JR Z,CH_STPP
	EX DE,HL
CH_STPP:
	SBC HL,DE
	JP M,CH_AMP
	LD A,(IX+SlToNt)
	LD (IX+Note),A
	XOR A
	LD (IX+TSlCnt),A
	LD (IX+CrTnSl),A
	LD (IX+CrTnSl+1),A
CH_AMP:
	LD A,(IX+CrAmSl)
	BIT 7,C
	JR Z,CH_NOAM
	BIT 6,C
	JR Z,CH_AMIN
	CP 15
	JR Z,CH_NOAM
	INC A
	JR CH_SVAM
CH_AMIN:
	CP -15
	JR Z,CH_NOAM
	DEC A
CH_SVAM:
	LD (IX+CrAmSl),A
CH_NOAM:
	LD L,A
	LD A,B
	AND 15
	ADD A,L
	JP P,CH_APOS
	XOR A
CH_APOS:
	CP 16
	JR C,CH_VOL
	LD A,15
CH_VOL:
	OR (IX+Volume)
	ADD A,VT_ & $ff
	LD L,A
	ADC A,VT_/256
	SUB L
	LD H,A
	LD A,(HL)
CH_ENV:
	BIT 0,C
	JR NZ,CH_NOEN
	OR (IX+Env_En)
CH_NOEN:
	LD (Ampl),A
	BIT 7,B
	LD A,C
	JR Z,NO_ENSL
	RLA
	RLA
	SRA A
	SRA A
	SRA A
	ADD A,(IX+CrEnSl) ;SEE COMMENT BELOW
	BIT 5,B
	JR Z,NO_ENAC
	LD (IX+CrEnSl),A
NO_ENAC:
	ADD A,(IY-100+AddToEn) ;BUG IN PT3 - NEED WORD HERE
	LD (IY-100+AddToEn),A
	JR CH_MIX
NO_ENSL:
	RRA
	ADD A,(IX+CrNsSl)
	LD (IY-100+AddToNs),A
	BIT 5,B
	JR Z,CH_MIX
	LD (IX+CrNsSl),A
CH_MIX:
	LD A,B
	RRA
	AND $48
CH_EXIT:
	OR (IY-100+AYREGS+Mixer)
	RRCA
	LD (IY-100+AYREGS+Mixer),A
	POP HL
	XOR A
	OR (IX+COnOff)
	RET Z
	DEC (IX+COnOff)
	RET NZ
	XOR (IX+Flags)
	LD (IX+Flags),A
	RRA
	LD A,(IX+OnOffD)
	JR C,CH_ONDL
	LD A,(IX+OffOnD)
CH_ONDL:
	LD (IX+COnOff),A
	RET

PLAY_:
	XOR A
	LD (IY-100+AddToEn),A
	LD (IY-100+AYREGS+Mixer),A
	DEC A
	LD (IY-100+AYREGS+EnvTp),A
	DEC (IY-100+DelyCnt)
	JP NZ,PL2
	DEC (IY-100+ChanA+NtSkCn)
	JR NZ,PL1B
	LD C,(IY-100+AdInPtA)
	LD B,(IY-100+AdInPtA+1)
	LD A,(BC)
	AND A
	JR NZ,PL1A
	LD D,A
	LD (IY-100+Ns_Base),A
	LD L,(IY-100+CrPsPtr)
	LD H,(IY-100+CrPsPtr+1)
	INC HL
	LD A,(HL)
	INC A
	JR NZ,PLNLP


	LD L,(IY-100+LPosPtr)
	LD H,(IY-100+LPosPtr+1)
	LD A,(HL)
	INC A
PLNLP:
	CALL SETCPPT
	DEC A
	BIT 1,(IY-100+ModNum)
	JR Z,NoAlCo
TSSub:	EQU $+1
	SUB $D6
	CPL
NoAlCo:
		;PT2		PT3
PsCalc:
	DEC A	;ADD A,A	NOP
	DEC A	;ADD A,(HL)	NOP
	ADD A,A
	LD E,A
	RL D

	IFDEF CURPOSCOUNTER
	LD A,L
	SUB (IY-100+PosSub)
	LD (IY-100+CurPos),A
	ENDIF

	LD L,(IY-100+PatsPtr)
	LD H,(IY-100+PatsPtr+1)
	ADD HL,DE
	LD E,(IY-100+MODADDR)
	LD D,(IY-100+MODADDR+1)
	LD (PSP_+1),SP
	LD SP,HL
	POP HL
	ADD HL,DE
	LD B,H
	LD C,L
	POP HL
	ADD HL,DE
	LD (IY-100+AdInPtB),L
	LD (IY-100+AdInPtB+1),H
	POP HL
	ADD HL,DE
	LD (IY-100+AdInPtC),L
	LD (IY-100+AdInPtC+1),H
PSP_:
	LD SP,$3131
PL1A:
	LD DE,ChanA+12-100
	CALL PTDECOD
	LD (IY-100+AdInPtA),C
	LD (IY-100+AdInPtA+1),B

PL1B:
	DEC (IY-100+ChanB+NtSkCn)
	JR NZ,PL1C
	LD DE,ChanB+12-100
	LD C,(IY-100+AdInPtB)
	LD B,(IY-100+AdInPtB+1)
	CALL PTDECOD
	LD (IY-100+AdInPtB),C
	LD (IY-100+AdInPtB+1),B

PL1C:
	DEC (IY-100+ChanC+NtSkCn)
	JR NZ,PL1D
	LD DE,ChanC+12-100
	LD C,(IY-100+AdInPtC)
	LD B,(IY-100+AdInPtC+1)
	CALL PTDECOD
	LD (IY-100+AdInPtC),C
	LD (IY-100+AdInPtC+1),B

PL1D:
	LD A,(IY-100+Delay)
	LD (IY-100+DelyCnt),A

PL2:
	LD DE,ChanA-100
	LD L,(IY-100+AYREGS+TonA)
	LD H,(IY-100+AYREGS+TonA+1)
	CALL CHREGS
	LD (IY-100+AYREGS+TonA),L
	LD (IY-100+AYREGS+TonA+1),H
Ampl:	EQU $+1
	LD A,$3E
	LD (IY-100+AYREGS+AmplA),A
	LD DE,ChanB-100
	LD L,(IY-100+AYREGS+TonB)
	LD H,(IY-100+AYREGS+TonB+1)
	CALL CHREGS
	LD (IY-100+AYREGS+TonB),L
	LD (IY-100+AYREGS+TonB+1),H
	LD A,(Ampl)
	LD (IY-100+AYREGS+AmplB),A
	LD DE,ChanC-100
	LD L,(IY-100+AYREGS+TonC)
	LD H,(IY-100+AYREGS+TonC+1)
	CALL CHREGS
	LD (IY-100+AYREGS+TonC),L
	LD (IY-100+AYREGS+TonC+1),H
	LD A,(Ampl)
	LD (IY-100+AYREGS+AmplC),A

	LD A,(IY-100+Ns_Base)
	ADD A,(IY-100+AddToNs)
	LD (IY-100+AYREGS+Noise),A

	LD A,(IY-100+AddToEn)
	LD E,A
	ADD A,A
	SBC A,A
	LD D,A
	LD L,(IY-100+EnvBase)
	LD H,(IY-100+EnvBase+1)
	ADD HL,DE
	LD E,(IY-100+CurESld)
	LD D,(IY-100+CurESld+1)
	ADD HL,DE
	LD (IY-100+AYREGS+Env),L
	LD (IY-100+AYREGS+Env+1),H

	XOR A
	OR (IY-100+CurEDel)
	RET Z
	DEC (IY-100+CurEDel)
	RET NZ
	LD A,(IY-100+Env_Del)
	LD (IY-100+CurEDel),A
	LD L,(IY-100+ESldAdd)
	LD H,(IY-100+ESldAdd+1)
	ADD HL,DE
	JP SETESLD

PLAY:
	LD IY,VARS1+100
	CALL PLAY_
	LD A,(is_ts)
	AND A
	JR Z,PL_nts
	LD IY,VARS2+100
	CALL PLAY_
PL_nts:
	IFDEF BASIC
	LD IY,$5C3A
	ENDIF

ROUT:
	LD BC,$FFFD
	LD A,(is_ts)
	AND A
	JR Z,r_nts ;keep old standard
	OUT (C),B
r_nts:
	EX AF,AF'

	IFDEF ACBBAC
	LD IX,VARS1+AYREGS
	ELSE
	LD HL,VARS1+AYREGS
	ENDIF

	CALL ROUT_
	EX AF,AF'
	RET Z
	LD B,D
	CPL
	OUT (C),A

	IFDEF ACBBAC
	LD IX,VARS2+AYREGS
	ELSE
	LD HL,VARS2+AYREGS
	ENDIF

ROUT_:

	IFDEF ACBBAC
	LD A,(SETUP)
	AND 12
	JR Z,ABC
	ADD A,CHTABLE
	LD E,A
	ADC A,CHTABLE/256
	SUB E
	LD D,A
	LD B,0
	PUSH IX
	POP HL
	LD A,(DE)
	INC DE
	LD C,A
	ADD HL,BC
	LD A,(IX+TonB)
	LD C,(HL)
	LD (IX+TonB),C
	LD (HL),A
	INC HL
	LD A,(IX+TonB+1)
	LD C,(HL)
	LD (IX+TonB+1),C
	LD (HL),A
	LD A,(DE)
	INC DE
	LD C,A
	ADD HL,BC
	LD A,(IX+AmplB)
	LD C,(HL)
	LD (IX+AmplB),C
	LD (HL),A
	LD A,(DE)
	INC DE
	LD (RxCA1),A
	XOR 8
	LD (RxCA2),A
	LD A,(DE)
	AND (IX+Mixer)
	LD E,A
	LD A,(IX+Mixer)
RxCA1:
	defb $E6
	AND %010010
	OR E
	LD E,A
	LD A,(IX+Mixer)
	AND %010010
RxCA2:
	OR E
	OR E
	LD (IX+Mixer),A
ABC:
	ENDIF

	XOR A
	LD DE,$FFBF

	IFDEF ACBBAC
	LD BC,$FFFD
	PUSH IX
	POP HL
	ENDIF

LOUT:
	OUT (C),A
	LD B,E
	OUTI 
	LD B,D
	INC A
	CP 13
	JR NZ,LOUT
	OUT (C),A
	LD A,(HL)
	AND A
	RET M
	LD B,E
	OUT (C),A
	RET

	IFDEF ACBBAC

CHTABLE: EQU $-4
	defb 4,5,15,%001001,0,7,7,%100100
	ENDIF

NT_DATA:
	defb (T_NEW_0-T1_)*2
	defb TCNEW_0-T_
	defb (T_OLD_0-T1_)*2+1
	defb TCOLD_0-T_
	defb (T_NEW_1-T1_)*2+1
	defb TCNEW_1-T_
	defb (T_OLD_1-T1_)*2+1
	defb TCOLD_1-T_
	defb (T_NEW_2-T1_)*2
	defb TCNEW_2-T_
	defb (T_OLD_2-T1_)*2
	defb TCOLD_2-T_
	defb (T_NEW_3-T1_)*2
	defb TCNEW_3-T_
	defb (T_OLD_3-T1_)*2
	defb TCOLD_3-T_

T_:

TCOLD_0:defb $00+1,$04+1,$08+1,$0A+1,$0C+1,$0E+1,$12+1,$14+1
	defb $18+1,$24+1,$3C+1,0
TCOLD_1:defb $5C+1,0
TCOLD_2:defb $30+1,$36+1,$4C+1,$52+1,$5E+1,$70+1,$82,$8C,$9C
	defb $9E,$A0,$A6,$A8,$AA,$AC,$AE,$AE,0
TCNEW_3:defb $56+1
TCOLD_3:defb $1E+1,$22+1,$24+1,$28+1,$2C+1,$2E+1,$32+1,$BE+1,0
TCNEW_0:defb $1C+1,$20+1,$22+1,$26+1,$2A+1,$2C+1,$30+1,$54+1
	defb $BC+1,$BE+1,0
TCNEW_1:EQU TCOLD_1
TCNEW_2:defb $1A+1,$20+1,$24+1,$28+1,$2A+1,$3A+1,$4C+1,$5E+1
	defb $BA+1,$BC+1,$BE+1,0

PT3EMPTYORN: EQU $-1
	defb 1,0

;first 12 values of tone tables (packed)

T_PACK:
	defb $06EC*2/256,$06EC*2 & $FF
	defb $0755-$06EC
	defb $07C5-$0755
	defb $083B-$07C5
	defb $08B8-$083B
	defb $093D-$08B8
	defb $09CA-$093D
	defb $0A5F-$09CA
	defb $0AFC-$0A5F
	defb $0BA4-$0AFC
	defb $0C55-$0BA4
	defb $0D10-$0C55
	defb $066D*2/256,$066D*2 & $FF
	defb $06CF-$066D
	defb $0737-$06CF
	defb $07A4-$0737
	defb $0819-$07A4
	defb $0894-$0819
	defb $0917-$0894
	defb $09A1-$0917
	defb $0A33-$09A1
	defb $0ACF-$0A33
	defb $0B73-$0ACF
	defb $0C22-$0B73
	defb $0CDA-$0C22
	defb $0704*2/256,$0704*2 & $FF
	defb $076E-$0704
	defb $07E0-$076E
	defb $0858-$07E0
	defb $08D6-$0858
	defb $095C-$08D6
	defb $09EC-$095C
	defb $0A82-$09EC
	defb $0B22-$0A82
	defb $0BCC-$0B22
	defb $0C80-$0BCC
	defb $0D3E-$0C80
	defb $07E0*2/256,$07E0*2 & $FF
	defb $0858-$07E0
	defb $08E0-$0858
	defb $0960-$08E0
	defb $09F0-$0960
	defb $0A88-$09F0
	defb $0B28-$0A88
	defb $0BD8-$0B28
	defb $0C80-$0BD8
	defb $0D60-$0C80
	defb $0E10-$0D60
	defb $0EF8-$0E10

;vars from here can be stripped
;you can move VARS to any other address

VARS:

is_ts:	defb 0

VARS1:	ds VRS
VARS2:	ds VRS

VT_:	EQU $-16
	ds 256-16 ;CreatedVolumeTableAddress

T1_:	EQU VT_+16 ;Tone tables data depacked here

T_OLD_1: EQU T1_
T_OLD_2: EQU T_OLD_1+24
T_OLD_3: EQU T_OLD_2+24
T_OLD_0: EQU T_OLD_3+2
T_NEW_0: EQU T_OLD_0
T_NEW_1: EQU T_OLD_1
T_NEW_2: EQU T_NEW_0+24
T_NEW_3: EQU T_OLD_3

PT2EMPTYORN: EQU VT_+31 ;1,0,0 sequence

NT_:	ds 192 ;CreatedNoteTableAddress

VAR0END: EQU VT_+16 ;INIT zeroes from VARS to VAR0END-1

VARSEND: EQU $
Modulo
                    assert Modulo < 3000h
