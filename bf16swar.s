.data
case0: .word 0x3F99999A # 1.200000
case1: .word 0x3F9A0000 # 1.203125
case2: .word 0x4013D70A # 2.310000
case3: .word 0x40140000 # 2.312500
case4: .word 0x3DCCCCCD # 0.1
case5: .word 0xBDCD0000 # -0.1
case6: .word 0x80000000 # -0.0
case7: .word 0x00000000 # 0.0
comma: .string ","
eol: .string "\n"

.text
.globl main
main:
    # la a0, case6
    # lw a0, 0(a0)
    # jal ra, fp32_to_bf16
    # jal print_float
    # j end

    la t0, case0
    lw a0, 0(t0)
    lw a1, 4(t0)
    jal ra, pbf16_encode
    mv s0, a0

    jal print_hex
    la a0, eol
    jal print_string

    mv a0, s0
    jal ra, pbf16_decode
    mv s0, a0
    mv s1, a1

    jal print_hex
    la a0, eol
    jal print_string
    mv a0, s1
    jal print_hex

    j end

#######################

fp32_to_bf16:
    addi sp, sp, -4
    sw s0, 0(sp)

    mv s0, a0
    srli t0, s0, 23     # t0: exponent
    andi t0, t0, 0xFF
    slli t1, s0, 9      # t1: mantissa

fp32_to_bf16_CHECK_ZERO:
    bnez t0, fp32_to_bf16_CHECK_INF_NAN
    beqz t1, fp32_to_bf16_EXIT
fp32_to_bf16_CHECK_INF_NAN:
    li t2, 0xFF         # t2: mask 0xFF
    beq t0, t2, fp32_to_bf16_EXIT

fp32_to_bf16_ROUNDING:
    li t2, 0x8000
    add a0, s0, t2      # round to nearest bf16
    li t2, 0xFFFF0000
    and a0, a0, t2

fp32_to_bf16_EXIT:
    lw s0, 0(sp)
    addi sp, sp, 4
    ret

#######################

# a0 = (a0 & 0xFFFF0000) | (a1 >> 16)
pbf16_encode:
    srli a1, a1, 16
    li t0, 0xFFFF0000
    and a0, a0, t0
    or a0, a0, a1
    ret

#######################

# a0 = a0 & 0xFFFF0000
# a1 = a0 << 16
pbf16_decode:
    slli a1, a0, 16
    li t0, 0xFFFF0000
    and a0, a0, t0
    ret

#######################

pbf16_mul:
    addi sp, sp, -44
    sw s0, 0(sp)    # sign
    sw s1, 4(sp)    # mantissa
    sw s2, 8(sp)    # exponent
    sw s3, 12(sp)   # input a
    sw s4, 16(sp)   # input b
    sw s5, 20(sp)   # mask 0x80008000
    sw s6, 24(sp)   # mask 0x00800080
    sw s7, 28(sp)   # mask 0x007F007F
    sw s8, 32(sp)   # mask 0x00FF00FF
    sw s9, 36(sp)   # shift
    sw ra, 40(sp)

    mv s3, a0
    mv s4, a1
    li s5, 0x80008000
    li s6, 0x00800080
    li s7, 0x007F007F
    li s8, 0x00FF00FF

    # sign s0
    xor s0, s3, s4
    and s0, s0, s5

    # mantissa s1
    and a0, s3, s7
    and a1, s4, s7
    or a0, a0, s6
    or a1, a1, s6
    jal ra, imul16
    srli s1, a0, 7
    and s1, s1, s7

    # shift s9
    srli s9, s1, 8
    andi s9, s9, 1
    srl s1, s1, s9

    # exponent s2
    srli a0, s3, 7
    srli a1, s4, 7
    and a0, a0, s8
    and a1, a1, s8
    add s2, a0, a1
    sub s2, s2, s7
    beqz s9, pbf16_mul_IF_END
    mv a0, s2
    jal ra, inc
    mv s2, a0
pbf16_mul_IF_END:

    # result a0
    mv a0, s0   # sign
    and s1, s1, s7
    or a0, a0, s1   # mantissa
    and s2, s2, s8
    slli s2, s2, 7
    or a0, a0, s2   # exponent

    lw s0, 0(sp)    # sign
    lw s1, 4(sp)    # mantissa
    lw s2, 8(sp)    # exponent
    lw s3, 12(sp)   # input a
    lw s4, 16(sp)   # input b
    lw s5, 20(sp)   # mask 0x80008000
    lw s6, 24(sp)   # mask 0x00800080
    lw s7, 28(sp)   # mask 0x007F007F
    lw s8, 32(sp)   # mask 0x00FF00FF
    lw s9, 36(sp)   # shift
    lw ra, 40(sp)
    addi sp, sp, 44
    ret

#######################

mask_lowest_zero:
    addi sp, sp, -4
    sw s0, 0(sp)

    mv s0, a0
    slli s0, a0, 1
    ori s0, s0, 0x1
    and a0, a0, s0

    slli s0, a0, 2
    ori s0, s0, 0x3
    and a0, a0, s0

    slli s0, a0, 4
    ori s0, s0, 0xF
    and a0, a0, s0

    slli s0, a0, 8
    ori s0, s0, 0xFF
    and a0, a0, s0

    slli s0, a0, 16
    ori s0, s0, 0xFFFF
    and a0, a0, s0

    lw s0, 0(sp)
    addi sp, sp, 4
    ret

#######################

inc:
    addi sp, sp, -12
    sw s0, 0(sp)
    sw s1, 0(sp)

    not s0, a0
    beqz s0, inc_EXIT_FAIL

    mv s0, a0   # s0: x
    jal ra, mask_lowest_zero
    mv s1, a0   # s1: mask
    slli a0, a0, 1
    ori a0, a0, 1
    xor a0, a0, a0

    mv s0, a0   # s0: x
    jal ra, mask_lowest_zero  # a0: mask
    slli s1, a0, 1  # s1: z1
    ori s1, s1, 1
    xor s1, s1, a0

    not a0, a0
    and a0, a0, s0
    or a0, a0, s1

inc_EXIT_OK:
    lw s0, 0(sp)
    lw s1, 4(sp)
    lw ra, 8(sp)
    addi sp, sp, 12
    ret

inc_EXIT_FAIL:
    li a0, 0
    lw s0, 0(sp)
    lw s1, 4(sp)
    lw ra, 8(sp)
    addi sp, sp, 12
    ret

#######################

# a0 = a0 * a1
imul16:
    addi sp, sp, -12
    sw s0, 0(sp)
    sw s1, 4(sp)
    sw s2, 8(sp)

    li s0, 0    # s0: current result
    li t0, 0    # t0: loop index
    li t1, 8    # t1: loop bound
imul16_LOOP1_BEGIN:
    bge t0, t1, imul16_LOOP1_END

    srl s1, a1, t0
    andi s1, s1, 1
    beqz s1, imul16_IF1_END

    sll s2, a0, t0
    add s0, s0, s2
imul16_IF1_END:

    addi t0, t0, 1
    j imul16_LOOP1_BEGIN
imul16_LOOP1_END:

    slli s0, s0, 16
    srli s0, s0, 16
    srli a1, a1, 16
    srli a0, a0, 16
    slli a0, a0, 16

    li t0, 0    # t0: loop index
    li t1, 8    # t1: loop bound
imul16_LOOP2_BEGIN:
    bge t0, t1, imul16_LOOP2_END

    srl s1, a1, t0
    andi s1, s1, 1
    beqz s1, imul16_IF2_END

    sll s2, a0, t0
    add s0, s0, s2
imul16_IF2_END:

    addi t0, t0, 1
    j imul16_LOOP2_BEGIN
imul16_LOOP2_END:

    lw s0, 0(sp)
    lw s1, 4(sp)
    lw s2, 8(sp)
    addi sp, sp, 12
    ret

#######################

print_float:
    li a7, 2
    ecall
    ret

print_hex:
    li a7, 34
    ecall
    ret

print_string:
    li a7, 4
    ecall
    ret

end:
    nop
