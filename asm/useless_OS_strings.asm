; useless_OS - assembly source using string literals

; --- Print banner ---
start:
    mov out2, 0x1
    mov out1, "Welcome to the Useless\0OS v7.6\nBy Elwimen\n"
    mov out2, 0x0

; --- Shell loop: reset first-char buffer and print prompt ---
shell_loop:
    mov a, 0x0
    mov [0x0], a

    mov out1, 0x0
    mov out2, 0x1
    mov out1, "\n > "
    mov out1, 0x0
    mov out2, 0x0

; --- Read characters until Enter ---
read_loop:
    mov a, in1
    cmp a, 0x1
    jne read_loop
    mov a, in2
    mov out2, 0x2
    mov out2, 0x0
    mov out1, a
    mov out2, 0x1
    mov out2, 0x0
    mov [0x1], a
    mov a, [0x0]
    cmp a, 0x0
    jne skip_first
    mov a, [0x1]
    mov [0x0], a
skip_first:
    mov a, [0x1]
    cmp a, '\n'
    jne read_loop

; --- Process command ---
    mov a, [0x0]
    cmp a, '\n'
    je shell_loop
    cmp a, 'h'
    je cmd_help

; --- Unknown command response ---
    mov out1, 0x0
    mov out2, 0x1
    mov out1, "\nI'm afraid I can't do that, Dave"
    mov out2, 0x0
    jmp shell_loop

; --- Help command response ---
cmd_help:
    mov out1, 0x0
    mov out2, 0x1
    mov out1, "\nAvailable commands:\n\thelp - prints this message"
    mov out2, 0x0
    jmp shell_loop
