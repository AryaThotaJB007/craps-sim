# Craps Game Simulator — x86 Assembly (NASM)

CS 66 project: a 32-bit NASM assembly program that simulates 10,000 games
of craps (Pass Line bet) and reports the win/loss totals, using a
hand-rolled linear congruential generator (LCG) seeded from the system
clock for the dice rolls.

## What it does

- Seeds a linear congruential generator (`seed = seed * 1103515245 +
  12345`) from the current Unix time.
- Rolls two dice per turn (`roll_two_dice`) and plays out a full Pass
  Line game (`play_one_game`): natural win on a come-out 7 or 11,
  instant loss on 2/3/12, otherwise the come-out roll becomes the
  "point" and play continues until the point repeats (win) or a 7
  appears (seven-out, loss).
- Repeats for 10,000 games and prints the total wins and losses via
  `printf`.

## Implementation notes

- Callee-saved registers (`ebx`, `edx`) are pushed/popped around
  `roll_two_dice`, and the loop counter is saved/restored around each
  `play_one_game` call since it isn't guaranteed to preserve `ecx`.
- Division uses `xor edx, edx` / `div` (unsigned) rather than
  `cdq` / `idiv` (signed) — an earlier signed-division version produced
  a skewed win count, since the RNG's positive-but-large values were
  occasionally being interpreted as negative.
- `roll_two_dice` grabs each die from bits 16 and up of the LCG output
  rather than the raw low bits. The low bits of this LCG flip parity on
  every single call (a known LCG pitfall, not actually random), which
  was silently forcing the two dice to always sum to an odd number —
  making a natural 2 or 12 impossible to roll and skewing the win rate
  to ~62%. Shifting up to the higher bits before the mod-6 fixes it;
  the program now lands consistently in the ~49%/51% range, matching
  the real Pass Line house edge (~1.4%).
- Exits via `fflush(NULL)` followed by a raw `int 0x80` sys_exit rather
  than libc's `exit()`. The `fflush` call is required — without it, the
  `printf` output sits in a stdio buffer that never gets flushed before
  the process terminates, so nothing prints at all when stdout isn't an
  interactive terminal (e.g. piped or redirected).

## Build & run

A fresh Codespace/container likely won't have `nasm` or 32-bit `libc`
installed. Install both first:

```bash
sudo apt-get update && sudo apt-get install -y nasm gcc-multilib
```

Then assemble, link, and run:

```bash
nasm -f elf32 craps_nasm.asm -o craps_nasm.o
ld -m elf_i386 --dynamic-linker /lib/ld-linux.so.2 -o craps_nasm craps_nasm.o -lc -L/usr/lib32
./craps_nasm
```

(`ld` comes from `binutils`, preinstalled on standard Ubuntu Codespace
images. `gcc-multilib` is what actually provides the 32-bit `libc` this
program links against — a 64-bit-only system has no 32-bit `-lc` to find
without it.)

## License

See `LICENSE` (MIT, course-provided template).
