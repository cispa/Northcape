#include <zephyr/toolchain.h>
#include <zephyr/skadi/skadi_asm.h>
#include <zephyr/arch/riscv/csr.h>

GTEXT(sim_capability_test_code_seg)
GTEXT(sim_capability_test_code_seg_end)

// underflow sled
.p2align 4
c.ebreak
c.ebreak
c.ebreak
c.ebreak
.p2align 3
sim_capability_test_code_seg:
    li t0, 16
    mv t1, a1

_loop_start:
    sd t0, 0(t1)
    ld t2, 0(t1)

    bne t0, t2, _load_fail
    addi t0, t0, -1
    bgtz t0, _loop_start

    addi a0, a0, 42
    ret
_load_fail:
    li a0, 0
    ret
// need 4 byte alignment...
.p2align 2
sim_capability_test_code_seg_end:
    nop


GTEXT(sim_capability_test_large_code_seg)
GTEXT(sim_capability_test_large_code_seg_end)

// underflow sled
.p2align 4
c.ebreak
c.ebreak
c.ebreak
c.ebreak
.p2align 3
sim_capability_test_large_code_seg:
    .rept 200
    addi a0, a0, 1
    .endr
    mv t0, a0
    mv t1, ra
    // force a cache miss for the return transactions by flushing icache
    csrwi 0x7C0, 0x00														
	csrwi 0x7C0, 0x01
    mv a0, t0
    mv ra, t1
    ret
// need 4 byte alignment...
.p2align 2
sim_capability_test_large_code_seg_end:
    nop
GTEXT(sim_capability_test_xlarge_code_seg)
GTEXT(sim_capability_test_xlarge_code_seg_end)

// underflow sled
.p2align 4
c.ebreak
c.ebreak
c.ebreak
c.ebreak
.p2align 3
sim_capability_test_xlarge_code_seg:
    .rept 20000
    addi a0, a0, 1
    .endr
    mv t0, a0
    mv t1, ra
    mv a0, t0
    mv ra, t1
    ret
// need 4 byte alignment...
.p2align 2
sim_capability_test_xlarge_code_seg_end:
    nop

/* a dummy computation that does some branches - will try to "poison" the branch table and get cva6 to crash */
GTEXT(sim_capability_test_dummy_subsystem_callee)
.p2align 3
sim_capability_test_dummy_subsystem_callee:
andi a1, a0, 0x1
srli a0, a0, 0x1
/* dummy read to involve the LSU as well */
auipc t0, 0x0
lb t0, 0(t0)
beqz a1, .last_even
addi a0, a0, 1

.last_even:
andi a1, a0, 0x1
beqz a1, .is_done
srli a0, a0, 0x1
j .last_even

.is_done:
// some compressed instructions to quickly fill the pipeline
.rept 100
c.addi t0, 0x1
.endr
// pipeline flush --> edge case in the frontend
fence
ret

GTEXT(sim_capability_test_dummy_subsystem_callee_end)
.p2align 2
sim_capability_test_dummy_subsystem_callee_end:
nop

GDATA(sim_capability_test_dummy_subsystem_callee_token)
GDATA(sim_capability_test_dummy_subsystem_ret_token)

GTEXT(sim_capability_test_dummy_subsystem_caller)
sim_capability_test_dummy_subsystem_caller:
addi sp, sp, -8
sd ra, 0(sp)
ld ra, sim_capability_test_dummy_subsystem_ret_token
ld t0, sim_capability_test_dummy_subsystem_callee_token
jr t0

GTEXT(sim_capability_test_dummy_subsystem_caller_return_trampoline)
.p2align 3
sim_capability_test_dummy_subsystem_caller_return_trampoline:

ld ra, 0(sp)
addi sp, sp, 8
ret

GTEXT(sim_capability_test_dummy_subsystem_caller_return_trampoline_end)
.p2align 2
sim_capability_test_dummy_subsystem_caller_return_trampoline_end:
nop

GTEXT(_invalid_subsystem_call_target)
_invalid_subsystem_call_target:
# make sure a0 is written even if we skip over parts of the trampoline
.rept 4
    li a0, 0
.endr
    ret
GTEXT(_invalid_subsystem_call_target_end)
_invalid_subsystem_call_target_end:
    nop

GTEXT(_expect_exception)
_expect_exception:
    li a0, 1
    ret


/* checks whether incorrect subsystem call causes an exception */
/* extern bool sim_capability_test_test_failing_subsystem_call(void *target); */
GTEXT(sim_capability_test_test_failing_subsystem_call)
sim_capability_test_test_failing_subsystem_call:

    # our dummy handler CANNOT handle interrupts
    csrr t2, mstatus
    csrci mstatus, MSTATUS_MIE

    csrr t0, mtvec

    # this should trigger an exception, as TID 0 has no set-task ID
    SKADI_SCALL(a0, 0)

    # should we ever just step over
    li a0, 0
    ret

/* bare-bones subsystem callee that uses the Skadi primitive for returning */
GTEXT(sim_capability_test_dummy_subsystem_callee_scall)
.p2align 3
sim_capability_test_dummy_subsystem_callee_scall:
li a0, 1
SKADI_SRET

GTEXT(sim_capability_test_dummy_subsystem_callee_end_scall)
.p2align 2
sim_capability_test_dummy_subsystem_callee_end_scall:
nop

GDATA(sim_capability_test_dummy_subsystem_callee_token_scall)
GDATA(sim_capability_test_dummy_subsystem_ret_token_scall)

GTEXT(sim_capability_test_dummy_subsystem_caller_scall)
sim_capability_test_dummy_subsystem_caller_scall:
addi sp, sp, -8
sd ra, 0(sp)
ld ra, sim_capability_test_dummy_subsystem_ret_token_scall
ld t0, sim_capability_test_dummy_subsystem_callee_token_scall
/* expect task ID 2 */
li t1, 2
SKADI_SCALL_ID(t0, t1)

GTEXT(sim_capability_test_dummy_subsystem_caller_return_trampoline_scall)
.p2align 3
sim_capability_test_dummy_subsystem_caller_return_trampoline_scall:

ld ra, 0(sp)
addi sp, sp, 8
ret

GTEXT(sim_capability_test_dummy_subsystem_caller_return_trampoline_end_scall)
.p2align 2
sim_capability_test_dummy_subsystem_caller_return_trampoline_end_scall:
nop



/* bare-bones subsystem callee that uses the Skadi scalls primitive for returning */
GTEXT(sim_capability_test_dummy_subsystem_callee_scalls)
.p2align 3
sim_capability_test_dummy_subsystem_callee_scalls:
li a0, 1
SKADI_SRETS

GTEXT(sim_capability_test_dummy_subsystem_callee_end_scalls)
.p2align 2
sim_capability_test_dummy_subsystem_callee_end_scalls:
nop

GDATA(sim_capability_test_dummy_subsystem_callee_token_scalls)
GDATA(sim_capability_test_dummy_subsystem_ret_token_scalls)

GTEXT(sim_capability_test_dummy_subsystem_caller_scalls)
sim_capability_test_dummy_subsystem_caller_scalls:
addi sp, sp, -8
sd ra, 0(sp)
ld ra, sim_capability_test_dummy_subsystem_ret_token_scalls
ld t0, sim_capability_test_dummy_subsystem_callee_token_scalls
SKADI_SCALLS(t0, 0)

GTEXT(sim_capability_test_dummy_subsystem_caller_return_trampoline_scalls)
.p2align 3
sim_capability_test_dummy_subsystem_caller_return_trampoline_scalls:

ld ra, 0(sp)
addi sp, sp, 8
ret

GTEXT(sim_capability_test_dummy_subsystem_caller_return_trampoline_end_scalls)
.p2align 2
sim_capability_test_dummy_subsystem_caller_return_trampoline_end_scalls:
nop


#define REG_TEST_CASE(REG)  \
    bnez REG, _test_fail

GTEXT(sim_capability_test_test_callee_zero)
.p2align 2
sim_capability_test_test_callee_zero:
    // space for all regs
    addi sp, sp, -(8*32)

    // sp is on the kill list
    mv a0, sp

    sd s0, 0(sp)
    sd s1, 8(sp)
    sd s2, 16(sp)
    sd s3, 24(sp)
    sd s4, 32(sp)
    sd s5, 40(sp)
    sd s6, 48(sp)
    sd s7, 56(sp)
    sd s8, 64(sp)
    sd s9, 72(sp)
    sd s10, 80(sp)
    sd s11, 88(sp)

    ld t0, _skadi_callee_clear_mask
    SKADI_REGCALL(t0)

    // only a0, ra should have survived
    
    REG_TEST_CASE(sp)
    REG_TEST_CASE(gp)
    REG_TEST_CASE(tp)
    
    REG_TEST_CASE(t0)
    REG_TEST_CASE(t1)
    REG_TEST_CASE(t2)
    REG_TEST_CASE(t3)
    REG_TEST_CASE(t4)
    REG_TEST_CASE(t5)
    REG_TEST_CASE(t6)

    REG_TEST_CASE(s0)
    REG_TEST_CASE(s1)
    REG_TEST_CASE(s2)
    REG_TEST_CASE(s3)
    REG_TEST_CASE(s4)
    REG_TEST_CASE(s5)
    REG_TEST_CASE(s6)
    REG_TEST_CASE(s7)
    REG_TEST_CASE(s8)
    REG_TEST_CASE(s9)
    REG_TEST_CASE(s10)
    REG_TEST_CASE(s11)
    
    REG_TEST_CASE(a1)
    REG_TEST_CASE(a2)
    REG_TEST_CASE(a3)
    REG_TEST_CASE(a4)
    REG_TEST_CASE(a5)
    REG_TEST_CASE(a6)
    REG_TEST_CASE(a7)

    // if the writing of registers fails, we will not complete the rest of the test
    // so no need to check here explicitly :-)

    mv sp, a0
    li a0, 1
    j _out

_test_fail:
    mv sp, a0
    li a0, 0

_out:
    ld s0, 0(sp)
    ld s1, 8(sp)
    ld s2, 16(sp)
    ld s3, 24(sp)
    ld s4, 32(sp)
    ld s5, 40(sp)
    ld s6, 48(sp)
    ld s7, 56(sp)
    ld s8, 64(sp)
    ld s9, 72(sp)
    ld s10, 80(sp)
    ld s11, 88(sp)

    addi sp, sp, (8*32)
    ret

.p2align 3
_skadi_callee_clear_mask:
.dword SKADI_CLEAR_REG_CALLEE
