; fake_linux.asm - Fake Linux boot and POSIX-like shell

; --- Boot sequence ---
start:
    mov out2, 0x1
    mov out1, "\nHomemade Linux 8-bit\n[OK] Boot\nlogin: root\n"
    mov out2, 0x0

; --- Shell loop: reset first-char buffer and print prompt ---
shell_loop:
    mov a, 0x0
    mov [0x0], a

    mov out1, 0x0
    mov out2, 0x1
    mov out1, "\nroot@cpu:~# "
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

; --- Dispatch on first character ---
    mov a, [0x0]
    cmp a, '\n'
    je shell_loop
    cmp a, 'h'
    je cmd_help
    cmp a, 'l'
    je cmd_ls
    cmp a, 'u'
    je cmd_uname
    cmp a, 'w'
    je cmd_whoami
    cmp a, 'p'
    je cmd_pwd
    cmp a, 'e'
    je cmd_exit

; --- Unknown command ---
    mov out1, 0x0
    mov out2, 0x1
    mov out1, "\nbash: command not found"
    mov out2, 0x0
    jmp shell_loop

; --- help ---
cmd_help:
    mov out1, 0x0
    mov out2, 0x1
    mov out1, "\nCommands: ls pwd uname whoami exit"
    mov out2, 0x0
    jmp shell_loop

; --- ls ---
cmd_ls:
    mov out1, 0x0
    mov out2, 0x1
    mov out1, "\nbin  etc  home  usr  var"
    mov out2, 0x0
    jmp shell_loop

; --- uname -a ---
cmd_uname:
    mov out1, 0x0
    mov out2, 0x1
    mov out1, "\nLinux cpu 6.1.0 #1 SMP 8-bit"
    mov out2, 0x0
    jmp shell_loop

; --- whoami ---
cmd_whoami:
    mov out1, 0x0
    mov out2, 0x1
    mov out1, "\nroot"
    mov out2, 0x0
    jmp shell_loop

; --- pwd ---
cmd_pwd:
    mov out1, 0x0
    mov out2, 0x1
    mov out1, "\n/root"
    mov out2, 0x0
    jmp shell_loop

; --- exit: print logout and halt (out2=0xFF signals simulator to stop) ---
cmd_exit:
    mov out1, 0x0
    mov out2, 0x1
    mov out1, "\nlogout"
    mov out2, 0xFF
