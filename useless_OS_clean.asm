; useless_OS - clean assembly source (equivalent to useless_OS.hex)

; --- Print banner ---
start:
    mov out2, 0x1
    mov out1, 'W'
    mov out1, 'e'
    mov out1, 'l'
    mov out1, 'c'
    mov out1, 'o'
    mov out1, 'm'
    mov out1, 'e'
    mov out1, ' '
    mov out1, 't'
    mov out1, 'o'
    mov out1, ' '
    mov out1, 't'
    mov out1, 'h'
    mov out1, 'e'
    mov out1, ' '
    mov out1, 'U'
    mov out1, 's'
    mov out1, 'e'
    mov out1, 'l'
    mov out1, 'e'
    mov out1, 's'
    mov out1, 's'
    mov out1, 0x0
    mov out1, 'O'
    mov out1, 'S'
    mov out1, ' '
    mov out1, 'v'
    mov out1, '7'
    mov out1, '.'
    mov out1, '5'
    mov out1, '\n'
    mov out1, 'B'
    mov out1, 'y'
    mov out1, ' '
    mov out1, 'D'
    mov out1, 'a'
    mov out1, 'n'
    mov out1, 'i'
    mov out1, 'j'
    mov out1, 'e'
    mov out1, 'l'
    mov out1, ' '
    mov out1, 'K'
    mov out1, 'o'
    mov out1, 'r'
    mov out1, 'e'
    mov out1, 'n'
    mov out1, 't'
    mov out1, '\n'

; --- Init: disable output, then enter shell loop ---
    mov out2, 0x0

; --- Shell loop: reset first-char buffer and print prompt ---
shell_loop:
    mov a, 0x0
    mov [0x0], a

    mov out1, 0x0
    mov out2, 0x1
    mov out1, '\n'
    mov out1, '\n'
    mov out1, 'S'
    mov out1, 'h'
    mov out1, 'e'
    mov out1, 'l'
    mov out1, 'l'
    mov out1, ':'
    mov out1, '>'
    mov out1, ' '
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
    mov out1, '\n'
    mov out1, 'I'
    mov out1, 0x27
    mov out1, 'm'
    mov out1, ' '
    mov out1, 'a'
    mov out1, 'f'
    mov out1, 'r'
    mov out1, 'a'
    mov out1, 'i'
    mov out1, 'd'
    mov out1, ' '
    mov out1, 'I'
    mov out1, ' '
    mov out1, 'c'
    mov out1, 'a'
    mov out1, 'n'
    mov out1, 0x27
    mov out1, 't'
    mov out1, ' '
    mov out1, 'd'
    mov out1, 'o'
    mov out1, ' '
    mov out1, 't'
    mov out1, 'h'
    mov out1, 'a'
    mov out1, 't'
    mov out1, ','
    mov out1, ' '
    mov out1, 'D'
    mov out1, 'a'
    mov out1, 'v'
    mov out1, 'e'
    mov out2, 0x0
    jmp shell_loop

; --- Help command response ---
cmd_help:
    mov out1, 0x0
    mov out2, 0x1
    mov out1, '\n'
    mov out1, 'A'
    mov out1, 'v'
    mov out1, 'a'
    mov out1, 'i'
    mov out1, 'l'
    mov out1, 'a'
    mov out1, 'b'
    mov out1, 'l'
    mov out1, 'e'
    mov out1, ' '
    mov out1, 'c'
    mov out1, 'o'
    mov out1, 'm'
    mov out1, 'm'
    mov out1, 'a'
    mov out1, 'n'
    mov out1, 'd'
    mov out1, 's'
    mov out1, ':'
    mov out1, '\n'
    mov out1, '\n'
    mov out1, ' '
    mov out1, ' '
    mov out1, ' '
    mov out1, 'h'
    mov out1, 'e'
    mov out1, 'l'
    mov out1, 'p'
    mov out1, ' '
    mov out1, '-'
    mov out1, ' '
    mov out1, 'p'
    mov out1, 'r'
    mov out1, 'i'
    mov out1, 'n'
    mov out1, 't'
    mov out1, 's'
    mov out1, ' '
    mov out1, 't'
    mov out1, 'h'
    mov out1, 'i'
    mov out1, 's'
    mov out1, ' '
    mov out1, 'm'
    mov out1, 'e'
    mov out1, 's'
    mov out1, 's'
    mov out1, 'a'
    mov out1, 'g'
    mov out1, 'e'
    mov out2, 0x0
    jmp shell_loop
