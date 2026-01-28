;#start=Traffic_Lights_Fixed.exe#

.model small
.stack 100h

.data
; ---------------------------------------
; Messages for each pedestrian state
pedestrian_all_go_msg     db ' >>> Pedestrians can CROSS now from ALL sides', 0
pedestrian_ns_go_msg      db ' >>> ONLY North-South pedestrians can CROSS now', 0
pedestrian_ew_go_msg      db ' >>> ONLY East-West pedestrians can CROSS now', 0
pedestrian_stop_msg       db ' [X] Pedestrians on RED side MUST STOP and wait', 0
pedestrian_ready_msg      db ' ... Pedestrians, GET READY to walk', 0
pedestrian_readystop_msg  db ' ... Prepare to STOP crossing', 0

; Emergency mode messages
emergency_active_msg      db ' !!! EMERGENCY MODE ACTIVE - ALL TRAFFIC STOP !!!', 0
emergency_exit_msg        db ' >>> Emergency cleared - Returning to previous mode', 0

; Pedestrian button messages
ped_request_msg           db ' [P] Pedestrian crossing REQUESTED - Extending green time', 0
ped_granted_msg           db ' [+3s] Extra time granted for pedestrians', 0
ped_denied_msg            db ' [!] Pedestrian request denied (wrong phase)', 0

; Rush hour messages
rush_hour_active_msg      db ' [RUSH HOUR MODE] Heavy traffic - Extended main road timing', 0
rush_hour_exit_msg        db ' >>> Rush hour ended - Normal timing restored', 0

; Night mode messages
night_mode_active_msg     db ' [NIGHT MODE] All lights BLINKING YELLOW - Drive carefully', 0
night_mode_exit_msg       db ' >>> Day mode activated - Normal operation', 0
night_caution_msg         db ' >>> Late night hours - Reduced traffic - Stay alert', 0

; Statistics messages
stats_label               db 'Cycles: ', 0
stats_ns_label            db '| NS Cars: ', 0
stats_ew_label            db '| EW Cars: ', 0

; Control keys help
help_msg                  db ' [E=Emerg|N=Normal|P=Ped|R=Rush|M=Night|D=Day|ESC=Exit]', 0
exit_msg                  db 'Traffic Light System Terminated. Goodbye!', 0Dh, 0Ah, '$'

; ---------------------------------------
; TRANSITION PATTERNS
transition1     equ     0000_0011_0000_1100b ; North/South Green, East/West Red
transition2     equ     0000_0100_1001_0010b ; All Yellow
transition3     equ     0000_1000_0110_0001b ; East/West Green, North/South Red
transition4     equ     0000_0100_1001_0010b ; All Yellow
all_red         equ     0000_0010_0100_1001b ; All directions Red
emergency_pattern equ   0000_0100_1001_0010b ; Emergency: All Yellow flashing
night_pattern   equ     0000_0100_1001_0010b ; Night: Yellow blinking

; Screen management
screen_offset   dw 0
base_row        equ 3    ; Start messages from row 3
max_row         equ 20   ; Maximum row before reset

; Mode flags
emergency_mode     db 0     ; 0 = normal, 1 = emergency active
night_mode         db 0     ; 0 = day, 1 = night
rush_hour_mode     db 0     ; 0 = normal, 1 = rush hour
ped_request        db 0     ; 0 = no request, 1 = pedestrian requested
program_exit       db 0     ; 0 = running, 1 = exit requested
previous_mode      db 0     ; 0 = normal, 1 = night (for emergency return)
current_phase      db 0     ; 0 = all_red, 1 = NS_green, 2 = yellow, 3 = EW_green

; Current timer values
ns_timer        db 0
ew_timer        db 0

; Statistics counters
cycle_counter   dw 0         ; Total cycles completed
ns_cars         dw 0         ; North-South cars passed
ew_cars         dw 0         ; East-West cars passed

; Timing values (can be modified by modes)
ns_green_time   db 5         ; Default 5 seconds
ew_green_time   db 5         ; Default 5 seconds
yellow_time     db 2         ; Default 2 seconds

; Temporary storage for timer countdown
current_timer_value db 0

.code
start:
    mov ax, @data
    mov ds, ax

    ; Clear screen
    call ClearScreen

    ; Show control keys help at top
    mov si, offset help_msg
    mov bl, 0Fh ; White
    call PrintTextColor

    ; Show initial statistics
    call UpdateStatistics

    ; -------------------------------
    ; INITIAL STATE: ALL RED
    mov current_phase, 0
    mov ax, all_red       
    out 4, ax             ; Send to port 4

    ; Show ALL pedestrians can GO
    mov si, offset pedestrian_all_go_msg
    mov bl, 0Ah ; Light Green
    call PrintTextColor

    ; Initialize timers
    mov ns_timer, 5
    mov ew_timer, 5
    call UpdateTimerDisplay

    ; Countdown + Beep (5 sec)
    mov cx, 5
    call DelayWithCountdown

; ----------------;
; BEGIN MAIN LOOP ;
; ----------------;
main_loop:
    ; Check for exit
    cmp program_exit, 1
    je exit_program

    ; Reset screen offset for new cycle (with safety check)
    mov ax, screen_offset
    cmp ax, max_row
    jl screen_ok
    mov screen_offset, base_row
screen_ok:

    ; Check for mode keys
    call CheckModeKeys
    
    ; If emergency mode, jump to emergency loop
    cmp emergency_mode, 1
    je emergency_loop

    ; If night mode, jump to night loop
    cmp night_mode, 1
    je night_loop

    ; Increment cycle counter at start of new cycle
    inc cycle_counter
    call UpdateStatistics

    ; -------- Transition 1: North-South Green, East-West Red --------
    mov current_phase, 1
    mov ax, transition1
    out 4, ax

    ; NS pedestrians go, EW must stop
    mov si, offset pedestrian_ns_go_msg
    mov bl, 0Ah ; Green for NS pedestrians
    call PrintTextColor

    mov si, offset pedestrian_stop_msg
    mov bl, 0Ch ; Red for EW pedestrians
    call PrintTextColor

    ; Check for pedestrian request
    cmp ped_request, 1
    jne no_ped_ns
    
    ; Pedestrian requested - add 3 seconds
    mov si, offset ped_granted_msg
    mov bl, 0Eh ; Yellow
    call PrintTextColor
    mov al, ns_green_time
    add al, 3
    mov current_timer_value, al
    mov ped_request, 0   ; Reset request
    jmp ped_done_ns

no_ped_ns:
    mov al, ns_green_time
    mov current_timer_value, al

ped_done_ns:
    ; Set timers for display
    mov al, current_timer_value
    mov ns_timer, al
    mov ew_timer, 0
    call UpdateTimerDisplay

    ; Delay with timer countdown
    mov al, current_timer_value
    xor ah, ah
    mov cx, ax
    call DelayWithLiveTimer
    
    cmp program_exit, 1
    je exit_program
    cmp emergency_mode, 1
    je emergency_loop
    cmp night_mode, 1
    je night_loop

    ; Update NS car count based on actual green time (FIXED: 16-bit multiplication)
    mov al, current_timer_value
    xor ah, ah
    mov bx, 2
    mul bx              ; 16-bit: DX:AX = AX * BX
    add ns_cars, ax
    call UpdateStatistics

    ; -------- Transition 2: All Yellow --------
    mov current_phase, 2
    mov ax, transition2
    out 4, ax

    ; Pedestrians prepare to STOP
    mov si, offset pedestrian_readystop_msg
    mov bl, 0Eh ; Yellow
    call PrintTextColor

    mov al, yellow_time
    mov ns_timer, al
    mov ew_timer, al
    call UpdateTimerDisplay

    mov al, yellow_time
    xor ah, ah
    mov cx, ax
    call DelayWithBothTimers
    
    cmp program_exit, 1
    je exit_program
    cmp emergency_mode, 1
    je emergency_loop
    cmp night_mode, 1
    je night_loop

    ; -------- Transition 3: East-West Green, North-South Red --------
    mov current_phase, 3
    mov ax, transition3
    out 4, ax

    ; EW pedestrians go, NS must stop
    mov si, offset pedestrian_ew_go_msg
    mov bl, 0Ah ; Green for EW pedestrians
    call PrintTextColor

    mov si, offset pedestrian_stop_msg
    mov bl, 0Ch ; Red for NS pedestrians
    call PrintTextColor

    ; Check for pedestrian request
    cmp ped_request, 1
    jne no_ped_ew
    
    ; Pedestrian requested - add 3 seconds
    mov si, offset ped_granted_msg
    mov bl, 0Eh ; Yellow
    call PrintTextColor
    mov al, ew_green_time
    add al, 3
    mov current_timer_value, al
    mov ped_request, 0   ; Reset request
    jmp ped_done_ew

no_ped_ew:
    mov al, ew_green_time
    mov current_timer_value, al

ped_done_ew:
    ; Set timers for display
    mov al, current_timer_value
    mov ns_timer, 0
    mov ew_timer, al
    call UpdateTimerDisplay

    ; Delay with timer countdown
    mov al, current_timer_value
    xor ah, ah
    mov cx, ax
    call DelayWithLiveTimer
    
    cmp program_exit, 1
    je exit_program
    cmp emergency_mode, 1
    je emergency_loop
    cmp night_mode, 1
    je night_loop

    ; Update EW car count based on actual green time (FIXED: 16-bit multiplication)
    mov al, current_timer_value
    xor ah, ah
    mov bx, 2
    mul bx              ; 16-bit: DX:AX = AX * BX
    add ew_cars, ax
    call UpdateStatistics

    ; -------- Transition 4: All Yellow --------
    mov current_phase, 2
    mov ax, transition4
    out 4, ax

    ; Pedestrians prepare to GO
    mov si, offset pedestrian_ready_msg
    mov bl, 0Eh ; Yellow
    call PrintTextColor

    mov al, yellow_time
    mov ns_timer, al
    mov ew_timer, al
    call UpdateTimerDisplay

    mov al, yellow_time
    xor ah, ah
    mov cx, ax
    call DelayWithBothTimers
    
    cmp program_exit, 1
    je exit_program
    cmp emergency_mode, 1
    je emergency_loop
    cmp night_mode, 1
    je night_loop

    ; -------- All Red Before Repeating --------
    mov current_phase, 0
    mov ax, all_red
    out 4, ax

    ; Show ALL pedestrians can GO again
    mov si, offset pedestrian_all_go_msg
    mov bl, 0Ah ; Light Green
    call PrintTextColor

    mov ns_timer, 5
    mov ew_timer, 5
    call UpdateTimerDisplay

    ; Countdown + Beep (5 sec)
    mov cx, 5
    call DelayWithCountdown

    ; Loop again
    jmp main_loop   

; ----------------------------------------------------------------;
; EMERGENCY MODE LOOP                                             ;
; ----------------------------------------------------------------;
emergency_loop:
    ; Clear message area
    call ClearMessageArea
    
    ; Show emergency message
    mov si, offset emergency_active_msg
    mov bl, 0CEh ; Bright Red on Yellow background
    call PrintTextColor

    ; Update timers to 0
    mov ns_timer, 0
    mov ew_timer, 0
    call UpdateTimerDisplay

emergency_flash_loop:
    ; Check for exit key
    call CheckModeKeys
    cmp program_exit, 1
    je exit_program
    cmp emergency_mode, 0
    je exit_emergency

    ; Flash pattern: All Yellow ON
    mov ax, emergency_pattern
    out 4, ax

    ; Beep
    mov al, 07h
    mov ah, 0Eh
    mov bh, 0
    int 10h

    ; Short delay (FIXED: Added AL=0 for INT 15h compatibility)
    mov al, 0           ; CRITICAL FIX for DOSBox
    mov cx, 0007h
    mov dx, 0A120h
    mov ah, 86h
    int 15h

    ; Flash pattern: All RED (darker)
    mov ax, all_red
    out 4, ax

    ; Short delay (FIXED: Added AL=0)
    mov al, 0           ; CRITICAL FIX for DOSBox
    mov cx, 0007h
    mov dx, 0A120h
    mov ah, 86h
    int 15h

    jmp emergency_flash_loop

exit_emergency:
    ; Clear message area
    call ClearMessageArea
    
    ; Show exit message
    mov si, offset emergency_exit_msg
    mov bl, 0Ah ; Green
    call PrintTextColor

    ; Reset to all red
    mov ax, all_red
    out 4, ax

    ; Brief pause before resuming (FIXED: Added AL=0)
    mov al, 0           ; CRITICAL FIX for DOSBox
    mov cx, 000Fh
    mov dx, 4240h
    mov ah, 86h
    int 15h

    ; Return to previous mode
    cmp previous_mode, 1
    je return_to_night
    jmp main_loop

return_to_night:
    mov previous_mode, 0
    jmp night_loop

; ----------------------------------------------------------------;
; NIGHT MODE LOOP                                                 ;
; ----------------------------------------------------------------;
night_loop:
    ; Clear message area
    call ClearMessageArea
    
    ; Show night mode message
    mov si, offset night_mode_active_msg
    mov bl, 0Eh ; Yellow
    call PrintTextColor

    mov si, offset night_caution_msg
    mov bl, 0Eh ; Yellow
    call PrintTextColor

    ; Update timers to 0
    mov ns_timer, 0
    mov ew_timer, 0
    call UpdateTimerDisplay

night_blink_loop:
    ; Check for exit key
    call CheckModeKeys
    cmp program_exit, 1
    je exit_program
    cmp night_mode, 0
    je exit_night
    cmp emergency_mode, 1
    je emergency_loop

    ; Blink pattern: All Yellow ON
    mov ax, night_pattern
    out 4, ax

    ; Medium delay (FIXED: Added AL=0)
    mov al, 0           ; CRITICAL FIX for DOSBox
    mov cx, 000Fh
    mov dx, 4240h
    mov ah, 86h
    int 15h

    ; All OFF (actually all red, but looks off)
    mov ax, all_red
    out 4, ax

    ; Medium delay (FIXED: Added AL=0)
    mov al, 0           ; CRITICAL FIX for DOSBox
    mov cx, 000Fh
    mov dx, 4240h
    mov ah, 86h
    int 15h

    jmp night_blink_loop

exit_night:
    ; Clear message area
    call ClearMessageArea
    
    ; Show exit message
    mov si, offset night_mode_exit_msg
    mov bl, 0Ah ; Green
    call PrintTextColor

    ; Reset to all red
    mov ax, all_red
    out 4, ax

    ; Brief pause (FIXED: Added AL=0)
    mov al, 0           ; CRITICAL FIX for DOSBox
    mov cx, 000Fh
    mov dx, 4240h
    mov ah, 86h
    int 15h

    ; Return to main loop
    jmp main_loop

; ----------------------------------------------------------------;
; CheckModeKeys: Check for E, N, P, R, M, D, ESC keys             ;
; ----------------------------------------------------------------;
CheckModeKeys:
    push ax
    push bx
    
    mov ah, 01h          ; Check keyboard status
    int 16h
    jz no_mode_key       ; Jump if no key available
    
    mov ah, 00h          ; Get keystroke
    int 16h
    
    ; Check ESC key (scan code)
    cmp ah, 01h
    je request_exit
    
    ; Check Emergency (E/e)
    cmp al, 'E'
    je activate_emergency
    cmp al, 'e'
    je activate_emergency
    
    ; Check Normal from Emergency (N/n)
    cmp al, 'N'
    je deactivate_emergency
    cmp al, 'n'
    je deactivate_emergency
    
    ; Check Pedestrian (P/p)
    cmp al, 'P'
    je activate_pedestrian
    cmp al, 'p'
    je activate_pedestrian
    
    ; Check Rush Hour (R/r)
    cmp al, 'R'
    je toggle_rush_hour
    cmp al, 'r'
    je toggle_rush_hour
    
    ; Check Night Mode (M/m)
    cmp al, 'M'
    je activate_night
    cmp al, 'm'
    je activate_night
    
    ; Check Day Mode (D/d)
    cmp al, 'D'
    je deactivate_night
    cmp al, 'd'
    je deactivate_night
    
    jmp no_mode_key

request_exit:
    mov program_exit, 1
    jmp no_mode_key

activate_emergency:
    ; Save current mode
    cmp night_mode, 1
    jne save_normal_mode
    mov previous_mode, 1
    jmp set_emergency
save_normal_mode:
    mov previous_mode, 0
set_emergency:
    mov emergency_mode, 1
    jmp no_mode_key

deactivate_emergency:
    mov emergency_mode, 0
    jmp no_mode_key

activate_pedestrian:
    cmp emergency_mode, 1
    je deny_ped_request       ; Don't allow during emergency
    cmp night_mode, 1
    je deny_ped_request       ; Don't allow during night
    
    ; Only allow during green phases
    cmp current_phase, 1
    je allow_ped_request
    cmp current_phase, 3
    je allow_ped_request
    
deny_ped_request:
    push si
    mov si, offset ped_denied_msg
    mov bl, 0Ch ; Red
    call PrintTextColor
    pop si
    jmp no_mode_key

allow_ped_request:
    mov ped_request, 1
    push si
    mov si, offset ped_request_msg
    mov bl, 0Bh ; Cyan
    call PrintTextColor
    pop si
    jmp no_mode_key

toggle_rush_hour:
    cmp rush_hour_mode, 0
    je enable_rush
    
    ; Disable rush hour
    mov rush_hour_mode, 0
    mov ns_green_time, 5
    mov ew_green_time, 5
    mov yellow_time, 2
    push si
    mov si, offset rush_hour_exit_msg
    mov bl, 0Ah ; Green
    call PrintTextColor
    pop si
    jmp no_mode_key

enable_rush:
    mov rush_hour_mode, 1
    mov ns_green_time, 8  ; Main road: 8 seconds
    mov ew_green_time, 3  ; Side road: 3 seconds
    mov yellow_time, 3    ; Longer yellow
    push si
    mov si, offset rush_hour_active_msg
    mov bl, 0Eh ; Yellow
    call PrintTextColor
    pop si
    jmp no_mode_key

activate_night:
    mov night_mode, 1
    jmp no_mode_key

deactivate_night:
    mov night_mode, 0
    jmp no_mode_key

no_mode_key:
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------;
; UpdateTimerDisplay: Show NS and EW timer at top of screen      ;
; ----------------------------------------------------------------;
UpdateTimerDisplay:
    push ax
    push bx
    push cx
    push dx
    push di
    push es

    mov ax, 0B800h
    mov es, ax

    ; Position: Row 1, Col 60
    mov di, (1 * 160) + (60 * 2)

    ; Print "NS: "
    mov al, 'N'
    mov ah, 0Fh
    stosw
    mov al, 'S'
    stosw
    mov al, ':'
    stosw
    mov al, ' '
    stosw

    ; Print NS timer value
    mov al, ns_timer
    call PrintDigitToScreen

    mov al, 's'
    mov ah, 0Fh
    stosw
    mov al, ' '
    stosw
    mov al, ' '
    stosw

    ; Print "EW: "
    mov al, 'E'
    stosw
    mov al, 'W'
    stosw
    mov al, ':'
    stosw
    mov al, ' '
    stosw

    ; Print EW timer value
    mov al, ew_timer
    call PrintDigitToScreen

    mov al, 's'
    mov ah, 0Fh
    stosw

    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Helper function to print digit(s) at DI
PrintDigitToScreen:
    push ax
    push bx
    push dx
    
    cmp al, 9
    jbe single_digit_print
    
    ; Two digits
    xor ah, ah
    mov bl, 10
    div bl              ; AL = tens, AH = ones
    
    push ax
    add al, '0'
    mov ah, 0Ah         ; Green
    stosw
    pop ax
    
    mov al, ah
    add al, '0'
    mov ah, 0Ah
    stosw
    jmp done_print_digit

single_digit_print:
    add al, '0'
    mov ah, 0Ah         ; Green
    stosw

done_print_digit:
    pop dx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------;
; UpdateStatistics: Display cycle count and car counts            ;
; ----------------------------------------------------------------;
UpdateStatistics:
    push ax
    push bx
    push cx
    push dx
    push di
    push si
    push es

    mov ax, 0B800h
    mov es, ax

    ; Position: Row 2, Col 2
    mov di, (2 * 160) + (2 * 2)

    ; Print "Cycles: "
    mov si, offset stats_label
stat_cycles_loop:
    lodsb
    cmp al, 0
    je stat_cycles_done
    mov ah, 0Bh         ; Cyan
    stosw
    jmp stat_cycles_loop

stat_cycles_done:
    ; Print cycle number
    mov ax, cycle_counter
    call PrintNumberToScreen
    
    ; Print "| NS Cars: "
    mov si, offset stats_ns_label
stat_ns_loop:
    lodsb
    cmp al, 0
    je stat_ns_done
    mov ah, 0Bh
    stosw
    jmp stat_ns_loop

stat_ns_done:
    ; Print NS cars
    mov ax, ns_cars
    call PrintNumberToScreen

    ; Print "| EW Cars: "
    mov si, offset stats_ew_label
stat_ew_loop:
    lodsb
    cmp al, 0
    je stat_ew_done
    mov ah, 0Bh
    stosw
    jmp stat_ew_loop

stat_ew_done:
    ; Print EW cars
    mov ax, ew_cars
    call PrintNumberToScreen

    ; Clear rest of line
    mov cx, 10
    mov ax, 0F20h       ; Space with white attribute
clear_stat_line:
    stosw
    loop clear_stat_line

    pop es
    pop si
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------;
; PrintNumberToScreen: Print number in AX to screen at DI         ;
; Uses ES:DI for output                                            ;
; ----------------------------------------------------------------;
PrintNumberToScreen:
    push ax
    push bx
    push cx
    push dx

    ; Handle zero case
    test ax, ax
    jnz convert_number
    mov al, '0'
    mov ah, 0Eh         ; Yellow
    stosw
    mov al, ' '
    mov ah, 0Fh
    stosw
    jmp done_print_number

convert_number:
    xor cx, cx
    mov bx, 10

divide_loop_num:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz divide_loop_num

print_digits_num:
    pop ax
    add al, '0'
    mov ah, 0Eh         ; Yellow
    stosw
    loop print_digits_num

    ; Add space after number
    mov al, ' '
    mov ah, 0Fh
    stosw

done_print_number:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------;
; DelayWithBothTimers: Countdown both NS and EW timers            ;
; Used during yellow phases when both directions count down       ;
; ----------------------------------------------------------------;
DelayWithBothTimers:
    push ax
    push bx
    push cx
    push dx

    mov bx, cx          ; BX = seconds remaining

delay_both_loop:
    cmp bx, 0
    je delay_both_done
    
    ; Update BOTH timers
    mov ns_timer, bl
    mov ew_timer, bl
    call UpdateTimerDisplay

    ; Delay 1 second (FIXED: Added AL=0)
    mov al, 0           ; CRITICAL FIX for DOSBox
    mov cx, 000Fh
    mov dx, 4240h
    mov ah, 86h
    int 15h

    ; Check for mode keys
    call CheckModeKeys
    cmp program_exit, 1
    je delay_both_done
    cmp emergency_mode, 1
    je delay_both_done
    cmp night_mode, 1
    je delay_both_done

    dec bx
    jmp delay_both_loop

delay_both_done:
    ; Set both timers to 0
    mov ns_timer, 0
    mov ew_timer, 0
    call UpdateTimerDisplay

    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------;
; DelayWithLiveTimer: Delay CX seconds with live timer countdown  ;
; Updates either NS or EW timer based on current phase            ;
; ----------------------------------------------------------------;
DelayWithLiveTimer:
    push ax
    push bx
    push cx
    push dx

    mov bx, cx          ; BX = seconds remaining

delay_live_loop:
    cmp bx, 0
    je delay_live_done
    
    ; Update appropriate timer based on current phase
    cmp current_phase, 1
    je update_ns_live
    cmp current_phase, 3
    je update_ew_live
    jmp update_display_live

update_ns_live:
    mov ns_timer, bl
    mov ew_timer, 0
    jmp update_display_live

update_ew_live:
    mov ns_timer, 0
    mov ew_timer, bl

update_display_live:
    call UpdateTimerDisplay

    ; Delay 1 second (FIXED: Added AL=0)
    mov al, 0           ; CRITICAL FIX for DOSBox
    mov cx, 000Fh
    mov dx, 4240h
    mov ah, 86h
    int 15h

    ; Check for mode keys
    call CheckModeKeys
    cmp program_exit, 1
    je delay_live_done
    cmp emergency_mode, 1
    je delay_live_done
    cmp night_mode, 1
    je delay_live_done

    dec bx
    jmp delay_live_loop

delay_live_done:
    ; Set appropriate timer to 0
    cmp current_phase, 1
    je zero_ns_live
    cmp current_phase, 3
    je zero_ew_live
    jmp final_update_live

zero_ns_live:
    mov ns_timer, 0
    jmp final_update_live

zero_ew_live:
    mov ew_timer, 0

final_update_live:
    call UpdateTimerDisplay

    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------;
; PrintTextColor: print string at (row++) directly to video memory;
; SI = offset of string, BL = color                               ;
; ----------------------------------------------------------------;
PrintTextColor:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    mov ax, 0B800h
    mov es, ax

    ; Check if we need to reset screen offset
    mov cx, screen_offset
    cmp cx, max_row
    jl no_reset_needed
    mov screen_offset, base_row
    mov cx, base_row

no_reset_needed:
    mov ax, cx
    mov dx, 160
    mul dx
    mov di, ax

print_text_loop:
    lodsb
    cmp al, 0
    je print_text_done
    mov es:[di], al
    inc di
    mov es:[di], bl
    inc di
    jmp print_text_loop

print_text_done:
    inc screen_offset
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; -----------------------------------------------------;
; DelayWithCountdown: Delay N seconds + beep each sec  ;
; -----------------------------------------------------;
DelayWithCountdown:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    mov bx, cx
    mov ax, 0B800h
    mov es, ax

countdown_loop:
    cmp bx, 0
    je countdown_done
    
    ; Update both timers for display
    mov ns_timer, bl
    mov ew_timer, bl
    call UpdateTimerDisplay

    ; Show countdown at bottom
    mov di, (24 * 160) + (70 * 2)
    mov al, bl
    add al, '0'
    mov ah, 0Fh
    stosw
    mov al, ' '
    stosw

    ; Beep
    mov al, 07h
    mov ah, 0Eh
    mov bh, 0
    int 10h

    ; Delay 1 second (FIXED: Added AL=0)
    mov al, 0           ; CRITICAL FIX for DOSBox
    mov cx, 000Fh
    mov dx, 4240h
    mov ah, 86h
    int 15h

    ; Check for keys
    call CheckModeKeys
    cmp program_exit, 1
    je countdown_done
    cmp emergency_mode, 1
    je countdown_done
    cmp night_mode, 1
    je countdown_done

    dec bx
    jmp countdown_loop

countdown_done:
    ; Clear countdown display
    mov di, (24 * 160) + (70 * 2)
    mov ax, 0F20h
    stosw
    stosw

    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------;
; ClearScreen: Clear entire screen                                ;
; ----------------------------------------------------------------;
ClearScreen:
    push ax
    push bx
    push cx
    push dx

    mov ah, 06h
    mov al, 0
    mov bh, 07h
    mov cx, 0
    mov dx, 184Fh
    int 10h

    mov ah, 02h
    mov bh, 0
    mov dx, 0
    int 10h

    mov screen_offset, 0

    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------;
; ClearMessageArea: Clear message display area (rows 3-20)        ;
; ----------------------------------------------------------------;
ClearMessageArea:
    push ax
    push bx
    push cx
    push dx

    mov ah, 06h
    mov al, 0
    mov bh, 07h
    mov cx, 0300h
    mov dx, 144Fh
    int 10h

    mov screen_offset, base_row

    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------;
; Exit Program                                                     ;
; ----------------------------------------------------------------;
exit_program:
    call ClearScreen
    
    ; Display exit message (FIXED: Using direct video memory instead of INT 21h)
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    
    mov ax, 0B800h
    mov es, ax
    mov di, (12 * 160) + (20 * 2)  ; Center of screen
    
    mov si, offset exit_msg
exit_msg_loop:
    lodsb
    cmp al, '$'         ; FIX: Check for '$' terminator
    je exit_msg_done
    cmp al, 0Dh         ; Skip CR
    je exit_msg_loop
    cmp al, 0Ah         ; Skip LF
    je exit_msg_loop
    mov ah, 0Eh         ; Yellow text
    stosw
    jmp exit_msg_loop
    
exit_msg_done:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    
    ; Brief pause to show message (FIXED: Added AL=0)
    mov al, 0
    mov cx, 001Eh
    mov dx, 8480h
    mov ah, 86h
    int 15h
    
    ; Terminate program
    mov ah, 4Ch
    int 21h

end start