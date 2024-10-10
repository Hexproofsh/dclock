# -----------------------------------------------------------------------------
# decclock.s - Decimal clock that maps each day to 1000 decimal minutes.
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

# ---------- DATA ----------
     .data

str_midnight:
     .asciz "NEW"

.align 8
NANOS_PER_DAY:
     .quad 86400000000000

# ---------- CODE ----------
     .text
     .globl _start

_start:
     
.L_exit:
     mov    $2025, %rdi
     call   is_leap_year

     mov    $60, %rax
     mov    $0, %rdi
     syscall

# ---------- FUNCTIONS ----------

# Function: get_year_from_epoch_sec
# Purpose: Returns the current year from epoch seconds
# Input; %rdi - specifies the year
# Returns: current year in %rax
get_year_from_epoch_sec:
    # %rax = days
    # %r10 = year
    mov     $1970, %r10

    mov     %rdi, %rax
    mov     $86400, %rbx
    xor     %rdx, %rdx
    div     %rbx

.L_get_year:
    cmp     $0, %rax
    je      .L_return_year


.L_return_year:
    ret

# Function: is_leap_year
# Purpose: Determines if the specified year is a leap year
# Input: %rdi - specifies the year
# Returns: 1 in %rax if a leap year
#          0 in %rax if not a leap year
is_leap_year:
    push   %rbx
    
    # Check if divisible by 4
    mov    %rdi, %rax
    xor    %rdx, %rdx                  # In all these calls we clear %rdx because remainder is in %rdx
    mov    $4, %rbx
    div    %rbx
    test   %rdx, %rdx
    jnz    .L_not_leap_year
    
    # Check if divisible by 100
    mov    %rdi, %rax
    xor    %rdx, %rdx
    mov    $100, %rbx
    div    %rbx
    test   %rdx, %rdx
    jnz    .L_is_leap_year
    
    # Check if divisible by 400
    mov    %rdi, %rax
    xor    %rdx, %rdx
    mov    $400, %rbx
    div    %rbx
    test   %rdx, %rdx
    jz     .L_is_leap_year
    
.L_not_leap_year:
    xor    %rax, %rax
    jmp    .L_exit_is_leap_year

.L_is_leap_year:
    mov    $1, %rax

.L_exit_is_leap_year:
    pop    %rbx
    ret
