; craps_nasm.asm
; Simulate 10,000 games of Craps (Pass Line bet) and print wins/losses.
; NASM + 32-bit Linux, linked with libc.

%define GAMES_TO_PLAY 10000

global _start
global main

extern printf
extern time        ; we only use time() now
extern fflush       ; need this so our printf output doesn't get lost (see _start below)

section .data
    fmtWins   db  "Total wins: %d", 10, 0
    fmtLosses db  "Total losses: %d", 10, 0

section .bss
    wins      resd 1
    losses    resd 1
    point     resd 1
    seed      resd 1        ; RNG seed

section .text

; ----------------------------------------------------
; Program entry for ld: _start
; Calls main(), then exits with its return value.
; ----------------------------------------------------
_start:
    call main          ; EAX = return code from main
    push eax           ; save main's return code, fflush is gonna clobber eax
    push dword 0       ; fflush(NULL) flushes every open stream
    call fflush        ; without this, printf's buffered output gets lost since we
    add  esp, 4         ; exit straight through the kernel below instead of libc's exit()
    pop  eax
    mov  ebx, eax      ; status
    mov  eax, 1        ; sys_exit
    int  0x80

; ----------------------------------------------------
; next_random:
; Simple linear congruential generator.
; Uses the formula: seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
; This is a pretty standard LCG that gives decent random numbers
; EAX = pseudo-random 31-bit integer (0..2^31-1)
; ----------------------------------------------------
next_random:
    mov  eax, [seed]           ; grab the current seed value
    imul eax, 1103515245       ; multiply by constant (result stays in EAX for 32-bit)
    add  eax, 12345            ; add the increment constant
    and  eax, 0x7fffffff       ; mask to keep it positive (31 bits)
    mov  [seed], eax           ; save new seed for next time
    ret

; -------------------------------------
; roll_two_dice:
; Simulates rolling two six-sided dice
; Returns the sum in EAX (will be 2-12)
; -------------------------------------
roll_two_dice:
    push ebx               ; save registers we're gonna use
    push edx

    ; === Roll the first die ===
    call next_random           ; get a random number in EAX
    shr  eax, 16                ; turns out the low bits of this LCG flip parity every single
                                 ; call (not actually random), so taking mod 6 straight off them
                                 ; made the two dice always add up to an odd number - grabbing
                                 ; the higher bits instead fixes that
    xor  edx, edx              ; clear EDX before division
    mov  ebx, 6                ; we want modulo 6
    div  ebx                   ; divide by 6: quotient in EAX, remainder in EDX
    mov  eax, edx              ; grab the remainder (0-5)
    inc  eax                   ; add 1 to get 1-6
    mov  ecx, eax              ; save first die in ECX

    ; === Roll the second die ===
    call next_random           ; get another random number
    shr  eax, 16                ; same fix as above
    xor  edx, edx              ; clear EDX before division
    mov  ebx, 6                ; modulo 6 again
    div  ebx                   ; divide by 6
    mov  eax, edx              ; remainder (0-5)
    inc  eax                   ; add 1 to get 1-6

    ; === Add them together ===
    add  eax, ecx              ; sum = die1 + die2 (result in EAX)

    pop  edx                   ; restore registers
    pop  ebx
    ret

; ----------------------------------------------------
; play_one_game:
; Plays a single game of craps following the rules
; Returns EAX = 1 if player wins, 0 if player loses
; ----------------------------------------------------
play_one_game:
    push ebx               ; gotta save ebx (callee-saved register)

    ; === COME OUT ROLL ===
    call roll_two_dice         ; roll the dice
    mov  ebx, eax              ; save the come out roll in EBX

    ; Check for natural (instant win on 7 or 11)
    cmp  ebx, 7
    je   .win                  ; rolled a 7, we win!
    cmp  ebx, 11
    je   .win                  ; rolled an 11, we win!

    ; Check for craps (instant loss on 2, 3, or 12)
    cmp  ebx, 2
    je   .lose                 ; snake eyes, we lose
    cmp  ebx, 3
    je   .lose                 ; ace-deuce, we lose
    cmp  ebx, 12
    je   .lose                 ; boxcars, we lose

    ; === POINT PHASE ===
    ; If we got here, we rolled 4, 5, 6, 8, 9, or 10
    ; That becomes our "point" - we need to roll it again before rolling 7
    mov  [point], ebx          ; save the point

.point_loop:
    ; Keep rolling until we hit the point or seven out
    call roll_two_dice         ; roll again, result in EAX
    mov  ecx, [point]          ; load our point value
    
    cmp  eax, ecx              ; did we roll the point?
    je   .win                  ; yes! we made the point, we win!

    cmp  eax, 7                ; did we roll a 7?
    je   .lose                 ; yes, sevened out, we lose

    jmp  .point_loop           ; nope, keep rolling

.win:
    mov  eax, 1                ; return 1 for WIN
    jmp  .done

.lose:
    mov  eax, 0                ; return 0 for LOSS

.done:
    pop  ebx                   ; restore ebx
    ret

; ----------------------------------------------------
; main:
; The main function - runs 10,000 games and prints results
; ----------------------------------------------------
main:
    push ebp                   ; set up stack frame
    mov  ebp, esp

    ; === Seed the random number generator ===
    ; We use the current time as the seed so we get different results each run
    push dword 0               ; pass NULL to time()
    call time                  ; EAX = current time_t (seconds since 1970)
    add  esp, 4                ; clean up the argument
    mov  [seed], eax           ; use time as our initial seed

    ; === Initialize counters ===
    mov  dword [wins],   0     ; start with 0 wins
    mov  dword [losses], 0     ; start with 0 losses

    ; === Main game loop - play 10,000 games ===
    mov  ecx, GAMES_TO_PLAY    ; ECX is our loop counter (10,000)

.game_loop:
    push ecx                   ; save loop counter (play_one_game might modify ECX)
    
    call play_one_game         ; play one game, EAX = 1 if win, 0 if loss
    
    cmp  eax, 1                ; did we win?
    jne  .count_loss           ; nope, go count a loss
    
    ; Player won this game
    inc  dword [wins]          ; increment win counter
    jmp  .after_count

.count_loss:
    ; Player lost this game
    inc  dword [losses]        ; increment loss counter

.after_count:
    pop  ecx                   ; restore loop counter
    loop .game_loop            ; decrement ECX and loop if not zero

    ; === Print results ===
    
    ; Print total wins
    push dword [wins]          ; argument: number of wins
    push dword fmtWins         ; argument: format string
    call printf                ; call printf
    add  esp, 8                ; clean up 2 arguments (4 bytes each)

    ; Print total losses
    push dword [losses]        ; argument: number of losses
    push dword fmtLosses       ; argument: format string
    call printf                ; call printf
    add  esp, 8                ; clean up 2 arguments

    mov  eax, 0                ; return 0 from main (success)

    mov  esp, ebp              ; clean up stack frame
    pop  ebp
    ret
