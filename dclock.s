# -----------------------------------------------------------------------------
# dclock.s - Decimal clock that maps each day to 1000 decimal minutes.
#
# Build: run make
#   or
# as --64 -o dclock.o dclock.s
# ld -o dclock dclock.o
#
# First it looks in /usr/local/etc/dclock.conf for a UTC offset value the
# default in the file is -6 and hardcoded is -6.
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
.set __NR_read, 0
.set __NR_open, 2
.set __NR_write, 1
.set __NR_close, 3
.set __NR_exit, 60

.set DEFAULT_TIMEZONE_OFFSET, -6 * 3600

.set NANO_PER_DAY, 86400000000000

.set MIDNIGHT, 999
.set NOON, 500
.set TEATIME, 333
 
# ---------- DATA ----------
     .data

.align 64
cumulative_days_normal:
     .long 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365
.align 64
cumulative_days_leap:
     .long 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366

str_midnight:
     .asciz "NEW"
str_noon:
     .asciz " (NOON)"
str_teatime:
     .asciz " (TEATIME)"

str_version:
     .ascii "dclock (Decimal clock that maps each day to 1000 decimal minutes)\n\n"
     .asciz "Written by Travis Montoya."
str_arg_version:
     .asciz "-v"
str_arg_expanded:
     .asciz "-e"
str_arg_error:
     .ascii "dclock: invalid option.\n"
     .ascii "usage; dclock <option>\n"
     .ascii "   -v    show program version information\n"
     .asciz "   -e    show expanded information with decimal time"

str_expanded:
     .asciz "Date: "
str_output:
     .asciz "Decimal time: "
newline:
     .asciz "\n"
dash:
     .asciz "/"

config_file:
     .asciz "/usr/local/etc/dclock.conf"

show_expanded:
     # 0 = normal, 1 = expanded
     .byte 0 

     .bss

# Our timespec struct for simplicity
# tv_sec  - 8 bytes
# tv_nsec - 8 bytes
#
# This way we can access tv_nsec by doing timespec+8
.align 8
timespec:
    .space 16

.align 8
decimal_time_str:
    .space 21

.align 8
tz_buffer:
    .space 4

.align 8
date_buffer:
    .space 16

# ---------- CODE ----------
     .text
     .globl _start

_start:
    mov       (%rsp), %r8
    cmp       $2, %r8
    jl        .L_get_time
    jg        .L_print_arg_error

    # We check for either of the command line arguments below whether it is
    # -v to show the version or -e for expanded date format printing
    lea       16(%rsp), %r9 
    mov       (%r9), %rdi
    pushq     %rdi

    mov       $2, %rcx
    lea       str_arg_version, %rsi
    call      strn_cmp
    test      %eax, %eax
    jz        .L_print_version

    popq      %rdi
    mov       $2, %rcx
    lea       str_arg_expanded, %rsi
    call      strn_cmp
    test      %eax, %eax
    jnz       .L_print_arg_error
    incb      show_expanded
.L_get_time:
    movq      $__NR_clock_gettime, %rax
    movq      $CLOCK_REALTIME, %rdi
    leaq      timespec, %rsi
    syscall

    # We check for our config file and attempt to open it and read the offset for the local
    # timezone. If there is not one specified we default to -6 (MDT)
    mov     $__NR_open, %rax   
    lea     config_file, %rdi
    xor     %rsi, %rsi         
    mov     $0644, %rdx
    syscall

    cmp     $0, %rax
    jl      .L_use_default_timezone

    pushq   %rax

    mov     %rax, %rdi       
    xor     %rax, %rax
    mov     $tz_buffer, %rsi
    mov     $4, %rdx                            # Read at max 4 bytes (-12 to + 14) + null terminator
    syscall

    popq    %rdi
    mov     $__NR_close, %rax
    syscall
     
    lea     tz_buffer, %rsi
    call    parse_config_value
    mov     $3600, %rcx
    imulq   %rcx
    addq    %rax, timespec
    jmp     .L_calculate_decimal_time

.L_use_default_timezone:
    # Throughout the calls we would be calculating everything with the number of seconds/nano
    # seconds since epoch. We need to apply a timezone offset to adjust the UTC time to our
    # local timezone.
    addq      $DEFAULT_TIMEZONE_OFFSET, timespec

.L_calculate_decimal_time:
    # Get year and day of year
    movq      timespec, %rdi
    call      get_year_from_epoch_sec
    # %rax = year, %rdx = day of year
    
    movq      %rax, %r8                         # We could technically do a couple pops to get this value again
                                                # but we are potentially reusing it again pretty quick so I save
                                                # it to a register that won't be used.
    pushq     %rax
    pushq     %rdx
    
    movq      %rdx, %rdi                        # day of year
    movq      %rax, %rsi                        # year
    call      get_day_of_month
    # %rax = month, %rdx = day of month
    
    pushq     %rax
    pushq     %rdx

    # dclocks "expanded" form shows the month/day/year before we show the
    # decimal time. So we check if it was passed as an argument and then
    # print out the date information below. If not we just jump to print
    # the decimal time.
    cmpb      $1, show_expanded
    jne       .L_not_expanded
    call      .L_print_expanded
.L_not_expanded:
    # Get hours, minutes, seconds
    movq      timespec, %rax
    movq      $86400, %rcx
    xorq      %rdx, %rdx
    divq      %rcx                              # %rdx = seconds of the day
    movq      %rdx, %rdi
    call      get_hms
    # %rax = hours, %rdx = minutes, %rcx = seconds

    # We decided on nanoseconds instead of ms for precision (as much as we could) and we break
    # down the hour, minutes to seconds and add them to the remaining seconds in %rcx so we can
    # finally get the total nanoseconds for the day.
    imulq     $3600, %rax                       # Seconds in an hour
    imulq     $60, %rdx                         # Seconds in a minute
    addq      %rdx, %rax
    addq      %rcx, %rax
    imulq     $1000000000, %rax
    addq      timespec+8, %rax  # Add tv_nsec
    # %rax contains nanos_today
  
    # Here is where we calculate the decimal time for the day and scale it to 0-999. Because we
    # use nanoseconds we can try to be a bit more precise on the time.
    #
    # decimal_time = ((NANO_PER_DAY - nanos_today) * 1000) / NANO_PER_DAY
    #
    # We substract the elapsed nanoseconds from NANO_PER_DAY so we get the remaining nanoseconds
    # then scale it to 0-999 by multiplying by 1000. Then dividing it normalizes this to a fraction
    # of the day.
    movq      $NANO_PER_DAY, %rcx               # Nanoseconds per day
    subq      %rax, %rcx                        # Subtract elapsed nanoseconds from total nanoseconds in day
    movq      %rcx, %rax 
    movq      $1000, %rcx
    mulq      %rcx                              # Multiply by 1000 for total decimal minutes for the day
    movq      $NANO_PER_DAY, %rcx               # Nanoseconds per day
    xorq      %rdx, %rdx
    divq      %rcx
    # %rax contains decimal minutes

    pushq     %rax

    leaq      decimal_time_str, %rsi
    call      uint64_to_ascii

    leaq      str_output, %rdi
    call      print_str

    # For midnight we replace printing a number and print "NEW" to show we are in a new day.
    popq      %rax
    cmp       $MIDNIGHT, %rax
    je        .L_print_midnight

    leaq      decimal_time_str, %rdi
    call      print_str

    # To help reference parts of the after we print the decimal time we will print a string
    # referencing which part of the day it is. 500 = "NOON" and 333 = "TEATIME"
    cmp       $NOON, %rax
    je        .L_print_noon
    cmp       $TEATIME, %rax
    je        .L_print_teatime

    jmp       .L_exit

# This needs to be called and not jumped to
.L_print_expanded:
    lea       str_expanded, %rdi
    call      print_str

    # rax = month
    # rdx = day of the month
    # r8  = year
    lea       date_buffer, %rsi
    call      uint64_to_ascii
    lea       date_buffer, %rdi
    call      print_str

    lea       dash, %rdi
    call      print_str

    mov       %rdx, %rax
    lea       date_buffer, %rsi
    call      uint64_to_ascii
    lea       date_buffer, %rdi
    call      print_str

    lea       dash, %rdi
    call      print_str

    mov       %r8, %rax
    lea       date_buffer, %rsi
    call      uint64_to_ascii
    lea       date_buffer, %rdi
    call      print_str

    lea       newline, %rdi
    call      print_str

    ret

.L_print_midnight:
    leaq      str_midnight, %rdi
    call      print_str
    jmp       .L_exit

.L_print_noon:
    leaq      str_noon, %rdi
    call      print_str
    jmp       .L_exit

.L_print_teatime:
    leaq      str_teatime, %rdi
    call      print_str
    jmp       .L_exit

.L_print_version:
    leaq      str_version, %rdi
    call      print_str
    jmp       .L_exit

.L_print_arg_error:
    leaq      str_arg_error, %rdi
    call      print_str

.L_exit:    

    leaq      newline, %rdi
    call      print_str

    mov       $__NR_exit, %rax
    xor       %rdi, %rdi
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

    mov       $86400, %rbx
    mov       %rdi, %rax
    xor       %rdx, %rdx
    div       %rbx                            # %rax = days since epoch

    # 1970 is the start of the UNIX epoch. We will start subtracting from this date.
    mov       $1970, %r12                     # %r12 = year
    mov       %rax, %r13                      # %r13 = remaining days

.L_year_loop:
    # We will continually increment %r12 (year) and subtract days from %r13 until we
    # cannot subtract anymore (366 or 365 depending on leap year) this will leave us
    # with the current year in %rax and reamining days in %rdx
    test      %r13, %r13
    jz        .L_year_found

    mov       %r12, %rdi
    call      is_leap_year
    mov       %rax, %r14                      # Store is_leap_year result

    # Assume it's not a leep year
    mov       $365, %rbx
    test      %r14, %r14
    jz        .L_check_days
    mov       $366, %rbx

.L_check_days:
    # If remaining days are less than 366 or 365 we found our current year and we
    # return the remaining days.
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

    # Calculate hour for %rax as there is 3600 seconds in an hour (60 min * 60 sec)
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
    inc       %r12                              # Adjust day of year to 1-indexed
    mov       %rsi, %r13                        # r13 = year

    # Check if it's a leap year so we know which array to load for our calculations
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

# The arrays specified have the amount of days of the year up until the current month
# think of the cumulative arrays indexed 1-12 for the month. So we search the array
# comparing it to the days in %rdi. The month will be the index into the array. To
# find the days we subtract the previous months cumulative days.
#
# so if %rbx is our index:
# month = first index (%rbx) where %rdi <= array[%rbx]
# if month = 1 then day = %rdi else day = array[%rbx-1]
.align 64
.L_month_loop:
    prefetchnta 64(%r14)

    mov       (%r14, %rbx, 4), %eax             # Load cumulative days
    cmp       %r12d, %eax
    jg        .L_month_found
    inc       %rbx
    cmp       $11, %rbx
    jle       .L_month_loop

# Remember we need to load previous months days and subtract it from $r12 to get the
# current day of th emonth since it's 0 indexed array if its january (0) we will inc
# by 1 to get January to be (1) 
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
    push      %rbx
    push      %r12
    push      %rcx
    push      %rdx

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
    pop       %rdx
    pop       %rcx
    pop       %r12
    pop       %rbx
    ret

# String comparison utility function with variable length checking
# Input:
#   %rcx is length to check
#   %rdi string1
#   %rsi string2
#   %rax is return
strn_cmp:
    cld
    repe      cmpsb
    jne       .L_strn_cmp_ne
    xor       %rax, %rax
    ret
.L_strn_cmp_ne:
    mov       $-1, %rax
    ret

# Parse timezone offset from config file
# Input:
#   %rsi buffer
# Returns:
#   %rax offset -12 to +14 
parse_config_value:
    push      %rcx
    push      %r8

    xor       %rax, %rax         # Initialize result to 0
    xor       %rcx, %rcx         # Clear rcx for digit values
    mov       $1, %r8            # Sign multiplier (1 for positive, -1 for negative)

    # Skip leading whitespace and newlines
.L_skip_space:
    movzbl    (%rsi), %ecx
    cmp       $' ', %cl
    je        .L_next_char
    cmp       $'\n', %cl
    je        .L_next_char

    # Check for minus sign
    cmp       $'-', %cl
    jne       .L_parse_loop
    mov       $-1, %r8
    inc       %rsi

    # Pretty simple ascii parsing to integer. We get the next digit in the string
    # subtract '0' to convert to an integer and multiply by 10 to shift to next
    # place in the integer.
.L_parse_loop:
    movzbl    (%rsi), %ecx
    sub       $'0', %cl
    cmp       $9, %cl
    ja        .L_done
    imul      $10, %rax
    add       %rcx, %rax
    inc       %rsi
    jmp       .L_parse_loop

.L_next_char:
    inc       %rsi
    jmp       .L_skip_space

.L_done:
    imul      %r8, %rax      # Apply sign
    pop       %r8
    pop       %rcx
    ret

