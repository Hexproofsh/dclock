# -----------------------------------------------------------------------------
# decclock.s - Decimal clock that maps each day to 1000 decimal minutes.
#
# Build: run make
#   or
# as --64 -o decclock.o decclock.s
# ld -o decclock decclock.o
#
# Implementation details from: https://jochen.link/experiments/calculateur.html
#
# "
# Using the number 1000 as a reference is precise enough for everyday use and 
# relatable when referring to specific parts of the day. Midnight is 1000 
# (displayed as “NEW”), noon 500, and teatime 333. Even though it is technically 
# a countdown it is not perceived like that, since checking the time usually 
# happens at a glance, not continuously. The displayed number represents all the 
# time we can still use, before we get another 1000 decimal minutes.
# "
# 
# Here it is in GNU x64 assembly form.
# Code is 100% free and public domain.
# Travis Montoya <trav@hexproof.sh>
# -----------------------------------------------------------------------------
.set CLOCK_REALTIME, 0
.set STDOUT, 1

.set __NR_clock_gettime, 228
.set __NR_write, 1

# We will eventually change this, but for time to be accurate we need to give
# the localtime offset. For now its set for MST with DST being set. This will
# be set in a config file soon.
.set TIMEZONE_OFFSET, -6 * 3600

# ---------- DATA ----------
     .data

cumulative_days_normal:
    .long 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365

cumulative_days_leap:
    .long 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366

str_midnight:
     .asciz "NEW"

str_output:
     .asciz "Decimal time: "

newline:
     .asciz "\n"

     .bss

.align 8
timespec:
    .space 16

.align 8
decimal_time_str:
    .space 21 

# ---------- CODE ----------
     .text
     .globl _start

_start:
    movq      $__NR_clock_gettime, %rax
    movq      $CLOCK_REALTIME, %rdi
    leaq      timespec, %rsi
    syscall

    movq      timespec, %rax
    addq      $TIMEZONE_OFFSET, %rax 
    movq      %rax, timespec
    
    # Get year and day of year
    movq      timespec, %rdi
    call      get_year_from_epoch_sec
    # %rax = year, %rdx = day of year
    
    pushq     %rax
    pushq     %rdx
    
    movq      %rdx, %rdi                        # day of year
    movq      %rax, %rsi                        # year
    call      get_day_of_month
    # %rax = month, %rdx = day of month
    
    pushq     %rax
    pushq     %rdx
    
    # Get hours, minutes, seconds
    movq      timespec, %rax
    movq      $86400, %rcx
    xorq      %rdx, %rdx
    divq      %rcx                              # %rdx = seconds of the day
    movq      %rdx, %rdi
    call      get_hms
    # %rax = hours, %rdx = minutes, %rcx = seconds

    # Calculate nanos_today
    imulq     $3600, %rax
    imulq     $60, %rdx
    addq      %rdx, %rax
    addq      %rcx, %rax
    imulq     $1000000000, %rax
    addq      timespec+8, %rax  # Add tv_nsec
    # %rax contains nanos_today
  
    # Calculate decimal time
    movq      $86400000000000, %rcx             # Nanoseconds per day
    subq      %rax, %rcx                        # Subtract elapsed nanoseconds from total nanoseconds in day
    movq      %rcx, %rax 
    movq      $1000, %rcx
    mulq      %rcx                              # Multiply by 1000 for total decimal minutes for the day
    movq      $86400000000000, %rcx             # Nanoseconds per day
    xorq      %rdx, %rdx
    divq      %rcx
    # %rax contains decimal minutes

    pushq     %rax

    leaq      decimal_time_str, %rsi
    call      uint64_to_ascii

    leaq      str_output, %rdi
    call      print_str

    popq      %rax
    cmp       $1000, %rax
    je        .L_print_midnight

    leaq      decimal_time_str, %rdi
    call      print_str
    jmp       .L_exit

.L_print_midnight:

    leaq      str_midnight, %rdi
    call      print_str

.L_exit:    

    leaq      newline, %rdi
    call      print_str

    mov       $60, %rax
    mov       $0, %rdi
    syscall

# ---------- FUNCTIONS ----------

# Function: get_year_from_epoch_sec
# Purpose: Returns the current year from epoch seconds
# Input: 
#   %rdi - epoch seconds
# Output: 
#   %rax - current year, %rdx - remaining days in year
get_year_from_epoch_sec:
    push      %rbx
    push      %r12
    push      %r13
    push      %r14

    # Calculate days since epoch
    mov       $86400, %rbx
    mov       %rdi, %rax
    xor       %rdx, %rdx
    div       %rbx                            # %rax = days since epoch

    mov       $1970, %r12                     # %r12 = year
    mov       %rax, %r13                      # %r13 = remaining days

.L_year_loop:
    test      %r13, %r13
    jz        .L_year_found

    mov       %r12, %rdi
    call      is_leap_year
    mov       %rax, %r14                      # Store is_leap_year result

    mov       $365, %rbx
    test      %r14, %r14
    jz        .L_check_days
    mov       $366, %rbx

.L_check_days:
    cmp       %rbx, %r13
    jl        .L_year_found
    sub       %rbx, %r13
    inc       %r12
    jmp       .L_year_loop

.L_year_found:
    mov       %r12, %rax                      # Return year in %rax
    mov       %r13, %rdx                      # Return remaining days in %rdx

    pop       %r14
    pop       %r13
    pop       %r12
    pop       %rbx
    ret

# Function: get_hms (Get Hours, Minutes, Seconds)
# Input:
#   %rdi - remaining seconds
# Output:
#   %rax - hours
#   %rdx - minutes
#   %rcx - seconds
get_hms:
    pushq     %rbp
    movq      %rsp, %rbp

    # Calculate hours
    movq      %rdi, %rax
    movq      $3600, %rcx
    xorq      %rdx, %rdx
    divq      %rcx
    # %rax contains hours
    
    pushq     %rax

    # Calculate remaining minutes and seconds
    movq      %rdx, %rax                        # Remainder (seconds) from hours division
    movq      $60, %rcx
    xorq      %rdx, %rdx
    divq      %rcx
    # %rax contains minutes, %rdx contains seconds

    movq      %rdx, %rcx                        # Move seconds to %rcx
    movq      %rax, %rdx                        # Move minutes to %rdx
    popq      %rax                              # Restore hours to %rax

    leave
    ret

# Function: get_day_of_month
# Input:
#   %rdi - day of year (0-365)
#   %rsi - year (to check if it's a leap year)
# Output:
#   %rax - month (1-12)
#   %rdx - day of month (1-31)
get_day_of_month:
    push      %rbx
    push      %r12
    push      %r13
    push      %r14

    mov       %rdi, %r12                        # r12 = day of year
    mov       %rsi, %r13                        # r13 = year

    # Check if it's a leap year
    mov       %r13, %rdi
    call      is_leap_year
    test      %rax, %rax
    jz        .L_use_normal_array

    # Leap year
    lea       cumulative_days_leap, %r14
    jmp       .L_find_month

.L_use_normal_array:
    lea       cumulative_days_normal, %r14

.L_find_month:
    xor       %rbx, %rbx                        # rbx = month index (0-11)

.L_month_loop:
    mov       (%r14, %rbx, 4), %eax             # Load cumulative days
    cmp       %r12d, %eax
    jg        .L_month_found
    inc       %rbx
    cmp       $11, %rbx
    jle       .L_month_loop

.L_month_found:
    # Calculate day of month
    test      %rbx, %rbx
    jz        .L_first_month
    mov       -4(%r14, %rbx, 4), %eax           # Load previous month's cumulative days
    sub       %eax, %r12d                       # Subtract from day of year
    jmp       .L_calc_day

.L_first_month:
    inc       %r12d                             # For January, just add 1 to day of year

.L_calc_day:
    lea       1(%rbx), %rax                     # Return month (1-12) in rax
    mov       %r12d, %edx                       # Return day of month in rdx

    pop       %r14
    pop       %r13
    pop       %r12
    pop       %rbx
    ret

# Function: is_leap_year
# Purpose: Determines if the specified year is a leap year
# Input: 
#   %rdi - specifies the year
# Returns: 
#   1 in %rax if a leap year
#   0 in %rax if not a leap year
is_leap_year:
    push      %rbx
    
    # Check if divisible by 4
    mov       %rdi, %rax
    xor       %rdx, %rdx                        # In all these calls we clear %rdx because remainder is in %rdx
    mov       $4, %rbx
    div       %rbx
    test      %rdx, %rdx
    jnz       .L_not_leap_year
    
    # Check if divisible by 100
    mov       %rdi, %rax
    xor       %rdx, %rdx
    mov       $100, %rbx
    div       %rbx
    test      %rdx, %rdx
    jnz       .L_is_leap_year
    
    # Check if divisible by 400
    mov       %rdi, %rax
    xor       %rdx, %rdx
    mov       $400, %rbx
    div       %rbx
    test      %rdx, %rdx
    jz        .L_is_leap_year
    
.L_not_leap_year:
    xor      %rax, %rax
    jmp      .L_exit_is_leap_year

.L_is_leap_year:
    mov      $1, %rax

.L_exit_is_leap_year:
    pop      %rbx
    ret

# ---------- HELPER FUNCTIONS ----------

# Print a string to STDOUT = 1
# Input:
#   %rdi holds the address of the string
#
# We need to find the length of the string first and then print using
# syscall __NR_write (sys_write) 
print_str:
    push      %rcx
    push      %rax
    push      %rdx

    xor       %rcx, %rcx
.L_strlen:
    movb      (%rdi, %rcx), %al
    test      %al, %al
    jz        .L_write
    inc       %rcx
    jmp       .L_strlen
.L_write:
    # At this point %rcx holds the length of the null terminated string
    mov       %rcx, %rdx
    mov       %rdi, %rsi
    mov       $STDOUT, %rdi
    mov       $__NR_write, %rax
    syscall

    pop       %rdx
    pop       %rax
    pop       %rcx
    ret

# Convert unsigned 64-bit integer to ASCII
# Input:
#   %rax - integer
#   %rsi - buffer pointer
uint64_to_ascii:
    push      %rbp
    mov       %rsp, %rbp
    push      %rbx
    push      %r12

    mov       %rsi, %rbx                        # Save original buffer pointer
    mov       $10, %rcx
    add       $20, %rsi                         # Move to end of buffer
    mov       %rsi, %r12                        # Save end of buffer pointer

    # Null-terminate the string
    movb      $0, (%rsi)

.L_convert_digit:
    xor       %rdx, %rdx
    div       %rcx                              # Divide rax by 10
    add       $'0', %dl                         # Convert remainder to ASCII
    dec       %rsi
    mov       %dl, (%rsi)                       # Store ASCII char
    test      %rax, %rax
    jnz       .L_convert_digit

    # Move the string to the beginning of the buffer if necessary
    cmp       %rbx, %rsi
    je        .L_done_to_ascii

    # Inline string move
    mov       %rsi, %rcx                        # Source
    mov       %rbx, %rdx                        # Destination
.L_strcpy:
    movb      (%rcx), %al
    movb      %al, (%rdx)
    inc       %rcx
    inc       %rdx
    cmp       %r12, %rcx
    jle       .L_strcpy

.L_done_to_ascii:
    pop       %r12
    pop       %rbx
    pop       %rbp
    ret

