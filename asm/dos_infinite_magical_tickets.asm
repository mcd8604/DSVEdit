.nds
.relativeinclude on
.erroronwarning on

@Overlay41Start equ 0x023E0100
@FreeSpace equ 0x023E0100

.open "ftc/overlay9_0", 0219E3E0h

; This patch should be applied after "dos_magical_ticket.asm".

; When starting a new game, give the player a Magical Ticket.
; There's not enough space so we overwrite the code where it checks if you already have a potion and skips giving you another three (for new game+).
.org 0x021F61D4
  ; Potions
  mov r2, 3h
  bl 021E78F0h ; SetOwnedItemNum
  ; Magical Ticket
  mov r0, 2h
  mov r1, 2Bh
  bl 021E7870h ; GiveItem
  b 021F61F0h

.close

.open "ftc/overlay9_41", @Overlay41Start

; Don't consume magical tickets on use.
.org @FreeSpace+0x6C
  mov r0, 42h ; This is the SFX that will be played on use.
  b 0x021EF264 ; Return to the consumable code after the part where it would remove the item from your inventory.

; Change the global flags checked to not care that the game hasn't been saved once yet.
.org @FreeSpace+0x78
  .word 0x80040007

.close
