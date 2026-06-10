.arm
.global _start

.equ IRQ_VECTOR,    0x027E3FFC
.equ ORIG_IRQ,      0x01FF8000

.equ REG_DISPCNT,   0x04000000
.equ REG_VCOUNT,    0x04000006
.equ REG_BG2CNT,    0x0400000C
.equ REG_BG2SCROLL, 0x04000018
.equ REG_KEYINPUT,  0x04000130

.equ BG_PALETTE,    0x05000000
.equ BG_TILE_ADDR,  0x06007FA0      @ Exact VRAM offset for Tile 0x3FD (Base + 1021 * 32)
.equ BG_MAP_BASE,   0x0600F000

_start:
    @ ====================================================
    @ IRQ INSTALLER (Hooked at 0x021898d4 in Overlay 14)
    @ ====================================================
    stmdb sp!, {r0-r12, lr}

    ldr r0, =IRQ_VECTOR
    ldr r1, [r0]
    ldr r2, =irq_handler
    cmp r1, r2
    beq exit_installer

    str r2, [r0]

exit_installer:
    ldmia sp!, {r0-r12, lr}
    mov r7, r0
    bx lr

irq_handler:
    @ ====================================================
    @ PAYLOAD (Per-frame Display)
    @ ====================================================
    sub sp, sp, #0x4          
    stmdb sp!, {r0-r12, lr}   

    ldr r0, =REG_VCOUNT     
    ldrh r1, [r0]           
    cmp r1, #192            
    blt exit_irq            

    @ ====================================================
    @ Toggle Logic & Edge Detection
    @ ====================================================
    ldr r0, =REG_KEYINPUT
    ldrh r1, [r0]
    mvn r1, r1              
    and r1, r1, #0x08       @ Mask Start Button

    ldr r3, =0x020F93F0     @ RAM: Previous Start State
    ldr r4, [r3]
    and r4, r4, #0x08       @ Clean uninitialized RAM garbage
    str r1, [r3]            @ Save new state

    cmp r1, #0x08           
    bne active_loop         @ Start not pressed -> bypass to active check
    cmp r4, #0x08
    beq active_loop         @ Start WAS pressed last frame (holding) -> bypass

    @ --- START JUST PRESSED (EDGE DETECTED) ---
    ldr r3, =0x020F93F4     @ RAM: Toggle State
    ldr r4, [r3]
    and r4, r4, #1
    eor r4, r4, #1          @ Flip Toggle
    str r4, [r3]

    cmp r4, #1
    beq do_save             @ If just turned ON, save game's display state

do_restore:
    @ --- JUST TURNED OFF: RESTORE GAME STATE ---
    ldr r3, =0x020F93F8     @ RAM: Saved DISPCNT
    ldrh r1, [r3]
    ldr r0, =REG_DISPCNT
    strh r1, [r0]

    ldr r3, =0x020F93FC     @ RAM: Saved BG2CNT
    ldrh r1, [r3]
    ldr r0, =REG_BG2CNT
    strh r1, [r0]

    b active_loop

do_save:
    @ --- JUST TURNED ON: CAPTURE GAME STATE ---
    ldr r0, =REG_DISPCNT
    ldrh r1, [r0]
    ldr r3, =0x020F93F8
    strh r1, [r3]

    ldr r0, =REG_BG2CNT
    ldrh r1, [r0]
    ldr r3, =0x020F93FC
    strh r1, [r3]

active_loop:
    @ ====================================================
    @ Active State Gate
    @ ====================================================
    ldr r3, =0x020F93F4
    ldr r4, [r3]
    and r4, r4, #1
    cmp r4, #1
    bne exit_irq            @ If Toggle is OFF, exit

    @ ====================================================
    @ Setup Display Hardware (Forced Mode)
    @ ====================================================
    @ 1. Enable BG2
    ldr r0, =REG_DISPCNT
    ldrh r1, [r0]
    orr r1, r1, #0x0400
    strh r1, [r0]

    @ 2. Setup BG2CNT (Clear Priority, Char Base, Color Mode, Screen Base. Set to 16-color, priority 0, screen 30)
    ldr r0, =REG_BG2CNT     
    ldrh r1, [r0]           
    ldr r2, =0xDF8F         @ Mask out bits 0,1,2,3,7,8-12
    bic r1, r1, r2          
    ldr r2, =0x1E00         @ Set Screen Base Block 30 (0x0600F000), Priority 0, Char 0
    orr r1, r1, r2
    strh r1, [r0]

    @ 3. Anchor BG2 Scroll to 0,0 (Fixes offscreen rendering)
    ldr r0, =REG_BG2SCROLL
    mov r1, #0
    str r1, [r0]            @ 32-bit write zeroes out both HOFS and VOFS simultaneously

    @ 4. Setup BG Palette 0 (Colors 13, 14, 15)
    ldr r0, =BG_PALETTE
    ldr r1, =0x7C1F         @ Magenta (R:31, G:0, B:31)
    strh r1, [r0, #0x1A]    
    ldr r1, =0x7FFF         @ White
    strh r1, [r0, #0x1C]    
    mov r1, #0              @ Black
    strh r1, [r0, #0x1E]    

    @ ====================================================
    @ Generate Solid Tiles in VRAM
    @ ====================================================
    ldr r0, =BG_TILE_ADDR

    @ Tile 0x3FD: Magenta
    ldr r1, =0xDDDDDDDD     
    mov r2, #8
tile_mag:
    str r1, [r0], #4
    subs r2, r2, #1
    bne tile_mag

    @ Tile 0x3FE: White
    ldr r1, =0xEEEEEEEE     
    mov r2, #8
tile_wht:
    str r1, [r0], #4
    subs r2, r2, #1
    bne tile_wht

    @ Tile 0x3FF: Black
    ldr r1, =0xFFFFFFFF     
    mov r2, #8
tile_blk:
    str r1, [r0], #4
    subs r2, r2, #1
    bne tile_blk

    @ ====================================================
    @ Fill Background Map with Magenta
    @ ====================================================
    ldr r0, =BG_MAP_BASE
    ldr r1, =0x03FD         @ Tile 0x3FD
    orr r1, r1, r1, lsl #16 @ Pack two tiles
    ldr r2, =0x200          @ 512 words = 2048 bytes
fill_map:
    str r1, [r0], #4
    subs r2, r2, #1
    bne fill_map

    @ ====================================================
    @ Draw 32-bit Data Grid
    @ ====================================================
    ldr r0, =0x020F9400

    ldrb r5, [r0]          @ rank
    mov  r5, r5, lsl #24

    ldrh r1, [r0,#2]       @ seed
    orr  r5, r5, r1, lsl #8

    ldrb r1, [r0,#1]       @ location
    orr  r5, r5, r1
    
    ldr r0, =BG_MAP_BASE
    mov r6, #0              

draw_grid:
    @ Shift bit out of map data
    movs r5, r5, lsl #1
    ldrcc r7, =0x03FE       @ Bit 0: Black Tile
    ldrcs r7, =0x03FF       @ Bit 1: White Tile

    @ Calculate Row: 5 + (Index / 8) * 4
    mov r1, r6, lsr #3      
    mov r1, r1, lsl #2      
    add r1, r1, #5          

    @ Calculate Column: 1 + (Index % 8) * 4
    and r2, r6, #7          
    mov r2, r2, lsl #2      
    add r2, r2, #1          

    @ Calculate Map RAM Offset
    mov r3, r1, lsl #5      @ Row * 32
    add r3, r3, r2          @ + Column
    mov r3, r3, lsl #1      @ * 2 bytes
    add r4, r0, r3          
    
    @ Draw 2x2 Square
    strh r7, [r4]           
    strh r7, [r4, #2]       
    strh r7, [r4, #64]      
    strh r7, [r4, #66]      

    add r6, r6, #1
    cmp r6, #32
    blt draw_grid

exit_irq:
    ldr r12, =ORIG_IRQ
    str r12, [sp, #56]          
    ldmia sp!, {r0-r12, lr, pc} 

@ ====================================================
@ MAP GENERATION TRAMPOLINE
@ Branch from 0x020a7c94 (b capture_map_data)
@ ====================================================
capture_map_data:
    strb r0,[r6,#0x15]      

    ldrb r1,[r6,#0x17]
    ldrh r2,[r6,#0x1A]

    ldr r12,=0x020F9400
    strb r1,[r12]
    strb r0,[r12,#1]
    strh r2,[r12,#2]

    b 0x020A7C98
    
