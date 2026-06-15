# Reverse-engineering the Meson8b secure monitor (secondary-CPU boot)

The 4-core fix required understanding how this box's **proprietary secure monitor** starts
secondary CPUs. The monitor is AES-encrypted on disk (in the signed bootloader), so it can't
be read statically. The trick: it is **resident in DRAM at `0x05000000`** every boot
(loaded by the signed bootloader, independent of the OS), and it exposes a
**secure-register-read SMC**, so we can make it read out *its own code* for us.

## Dumping the monitor

The monitor's SMC ABI (ARMv7 `smc #0`):

| r0 | meaning | args |
|----|---------|------|
| 2  | read a secure register/address | r1 = phys addr → returns value in r0 |
| 3  | write a secure register/address | r1 = phys addr, r2 = value |
| 4  | monitor command | r1 = cmd id, r2/r3 = args |

`r0=4, r1=0x701/0x702` returns the secure-memory base/size. `r0=2` reads arbitrary secure
DRAM — so a kernel loop over `0x04f00000..0x05200000` calling `smc(2, addr)` dumps the whole
monitor (the patch keeps a `/proc/meson_secmon` helper that does this). Disassemble with:

```
arm-linux-gnueabihf-objdump -D -b binary -m arm -EL --adjust-vma=0x05000000 secmon-code.bin
```

## SMC dispatch (found at ~`0x05135164`)

The `r0=4` handler dispatches on `(cmd & 0xf00)`:

```
0x100 -> handler 0x5134dc8
0x200 -> handler 0x5134e84   (CORE ops)
0x300 -> handler 0x5134f4c
0x500 -> handler 0x5134fd8
0x700 -> handler ...         (MEM info: 0x701 base, 0x702 size, 0x703 flash)
```

The **core handler `0x5134e84`** is a jump table for cmd `0x201..0x20a`:

```
0x201 read core-ctrl     0x202 write core-ctrl
0x207 set secondary boot-addr (-> 0x513aef4)
```

## `0x207` set-boot-addr handler (`0x513aef4`)

```c
// r0 = cpu (1..3), r1 = entry addr
sram_addr_reg = 0xd901ff84 + (cpu-1)*4;
mailbox[cpu]  = 0x05104da4 + cpu*4;      // per-cpu mailbox in secure DRAM
clear mailbox[cpu];
boot_routine(cpu);                       // 0x513627c — full power-on, see below
mailbox[cpu] = entry;                    // store the real (non-secure) kernel entry
```

## The boot routine `0x513627c` (what actually powers + starts a core)

Registers it touches (all resolved from its literal pool):

| reg | what |
|-----|------|
| `0xc4300008` | SCU CPU power-status |
| `0xc81000e0` / `0xc81000e4` / `0xc81000f4` | AO `PWR_A9_CNTL0` / `CNTL1` / `MEM_PD0` |
| `0xc110419c` | HHI `SYS_CPU_CLK_CNTL` (CPU reset bit) |
| `0xd901ff84(+)` | SMP SRAM per-cpu boot-addr |
| `0xd901ff80` | SMP SRAM CPU-ctrl (enable bits) |
| `0x05100128` | the monitor's own secure secondary entry |

Sequence (per cpu):
1. SCU power-on: `scu[8] &= ~(3 << (8*cpu))`
2. (chip-rev `0xc1107d4c == 0x1b` gate) AO `CNTL0 &= ~(3 << (16 + 2*cpu))`
3. HHI reset assert: `hhi[0x19c] |= 1 << (cpu+24)`
4. AO `MEM_PD0 &= ~(0xf << (32 - 4*cpu))`
5. AO `CNTL1 &= ~(3 << (2*(cpu+1)))`
6. **poll AO `CNTL1` bit `(cpu+16)` for power-good — UNBOUNDED loop**
7. AO `CNTL0 &= ~(1 << cpu)` (isolation off)
8. SRAM boot-addr = `0x05100128`; HHI reset deassert
9. SRAM ctrl `|= (1<<cpu) | 1`; `sev`

## Why upstream `meson8b-smp` fails, and why `0x207` hung

- Upstream pokes the SRAM/SCU directly. The **SRAM is secure** → read = external abort
  (the original crash), write = silently dropped.
- Calling `0x207` directly hung because step 6's **power-good poll never completed in our
  boot context** — the secure monitor spins forever, so the `smc` never returns.
- It is **not** corruption-of-mailbox (we verified with the region reserved): it is the
  monitor's own unbounded poll.

## The fix (see the kernel patch)

Reimplement `0x513627c` in the non-secure kernel:
- Do steps 1–9's **AO/SCU/HHI** writes **directly via `ioremap`** (these registers are
  non-secure accessible — verified: the stock kernel's `meson_set_cpu_power_ctrl` does the
  same via `0xfe00xxxx` ioremaps).
- Replace the **unbounded** power-good poll with a **bounded** one (it succeeds quickly when
  we drive it ourselves).
- Do the **secure** bits — mailbox `0x05104da4+cpu*4`, SRAM `0xd901ff84`/`0xd901ff80` — via
  the monitor's `smc` r0=3 write (they fault from non-secure).
- `sev`. The core resets into `0x05100128`, reads the mailbox, drops to non-secure at our
  `secondary_startup`.

## Confirming against the stock kernel

The stock Android 3.10 kernel (dumped from `/dev/mem` at phys `0x208000`, `kptr_restrict=0`
for symbols) has exactly `meson_auxcoreboot_addr` (→ `0x207`), `meson_smc1/2/3`,
`meson_set_cpu_power_ctrl`. So the stock uses the same SMC; it works there because the full
vendor boot establishes the AO power state. We sidestep that by doing the power ourselves.

Key constant: `meson_smc1` uses **`mov r0,#4`** then `smc #0`, and the monitor **clobbers
r2–r12** across the call (the vendor wrapper saves `{r2-ip,lr}`). A non-secure caller MUST
do the same — our inline asm clobbers `r4–r12/lr`, else the caller crashes right after a
register-heavy SMC like the core path.
