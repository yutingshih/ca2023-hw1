#include <stdio.h>
#include <stdint.h>

typedef float bf16_t;       // bfloat16
typedef uint32_t pbf16_t;   // packed bfloat16

bf16_t fp32_to_bf16(float x)
{
    float y = x;
    int *p = (int *) &y;
    unsigned int exp = *p & 0x7F800000;
    unsigned int man = *p & 0x007FFFFF;
    if (exp == 0 && man == 0) /* zero */
        return x;
    if (exp == 0x7F800000) /* infinity or NaN */
        return x;

    /* Normalized number */
    /* round to nearest */
    float r = x;
    int *pr = (int *) &r;
    *pr &= 0xFF800000;  /* r has the same exp as x */
    r /= 0x100;
    y = x + r;

    *p &= 0xFFFF0000;

    return y;
}

pbf16_t pbf16_encode(bf16_t a, bf16_t b)
{
    return (*(pbf16_t *)&a & 0xFFFF0000) | (*(pbf16_t *)&b >> 16);
}

void pbf16_decode(pbf16_t ab, bf16_t* a, bf16_t* b)
{
    *(pbf16_t*)a = ab & 0xFFFF0000;
    *(pbf16_t*)b = ab << 16;
}

uint32_t mask_lowest_zero(uint32_t x)
{
    uint32_t mask = x;
    mask &= (mask << 1) | 0x1;
    mask &= (mask << 2) | 0x3;
    mask &= (mask << 4) | 0xF;
    mask &= (mask << 8) | 0xFF;
    mask &= (mask << 16) | 0xFFFF;
    return mask;
}

int64_t inc(int64_t x)
{
    if (~x == 0)
        return 0;
    /* TODO: Carry flag */
    int64_t mask = mask_lowest_zero(x);
    int64_t z1 = mask ^ ((mask << 1) | 1);
    return (x & ~mask) | z1;
}

// int64_t imul32(int32_t a, int32_t b)
// {
//     int64_t r = 0, a64 = (int64_t) a, b64 = (int64_t) b;
//     for (int i = 0; i < 8; i++) {
//         if ((b64 >> i) & 1)
//             r += a64 << i;
//     }
//     return r;
// }

uint32_t imul16(uint32_t a, uint32_t b) {
    uint32_t r = 0;
    for (int i = 0; i < 8; i++)
        if ((b >> i) & 1) r += a << i;
    r &= 0xFFFF;
    b >>= 16;
    a &= 0xFFFF0000;
    for (int i = 0; i < 8; i++)
        if ((b >> i) & 1) r += a << i;
    return r;
}

pbf16_t pbf16_mul(pbf16_t a, pbf16_t b)
{
    uint32_t sr = (a ^ b) & 0x80008000;

    uint32_t ma = (a & 0x007F007F) | 0x00800080;
    uint32_t mb = (b & 0x007F007F) | 0x00800080;

    uint32_t mr = (imul16(ma, mb) >> 7) & 0x007F007F;
    uint32_t msh = (mr >> 8) & 1;
    mr >>= msh;

    uint32_t ea = (a >> 7) & 0x00FF00FF;
    uint32_t eb = (b >> 7) & 0x00FF00FF;
    uint32_t er = ea + eb - 0x007F007F; // 127 = 0b1111111 = 0x7F
    er = msh ? inc(er) : er;

    pbf16_t r = sr | ((er & 0x00FF00FF) << 7) | (mr & 0x007F007F);
    return r;
}

/* float32 multiply */
// float fmul32(float a, float b)
// {
//     /* TODO: Special values like NaN and INF */
//     int32_t ia = *(int32_t *) &a, ib = *(int32_t *) &b;

//     /* sign */
//     int sa = ia >> 31;
//     int sb = ib >> 31;

//     /* mantissa */
//     int32_t ma = (ia & 0x7FFFFF) | 0x800000;
//     int32_t mb = (ib & 0x7FFFFF) | 0x800000;

//     /* exponent */
//     int32_t ea = ((ia >> 23) & 0xFF);
//     int32_t eb = ((ib >> 23) & 0xFF);

//     /* 'r' = result */
//     int64_t mrtmp = imul32(ma, mb) >> 23;
//     int mshift = getbit(mrtmp, 24);

//     int64_t mr = mrtmp >> mshift;
//     int32_t ertmp = ea + eb - 127;
//     int32_t er = mshift ? inc(ertmp) : ertmp;
//     /* TODO: Overflow ^ */
//     int sr = sa ^ sb;
//     int32_t r = (sr << 31) | ((er & 0xFF) << 23) | (mr & 0x7FFFFF);
//     return *(float *) &r;
// }

void print(float x) {
    printf("%f (0x%08X)\n", x, *(uint32_t*)&x);
}

int main(void)
{
    // float x[] = {
    //     1.2,
    //     1.203125,
    //     2.310000,
    //     2.312500,
    //     0.1,
    //     -0.1,
    //     -0.0,
    // };

    // unsigned num = sizeof(x) / sizeof(float);

    // // test 1: fp32_to_bf16
    // for (unsigned i = 0; i + 1 < num; i += 2) {
    //     print(x[i]);
    //     bf16_t y = fp32_to_bf16(x[i]);
    //     print(y);
    //     puts("");
    // }

    // // test 2: pbf16 encode/decode
    // for (unsigned i = 0; i + 1 < num; i += 2) {
    //     print(x[i]);
    //     print(x[i+1]);
    //     pbf16_t ab = pbf16_encode(x[i], x[i+1]);
    //     print(*(float *)&ab);

    //     bf16_t a = 0.0f, b = 0.0f;
    //     pbf16_decode(ab, &a, &b);
    //     print(a);
    //     print(b);
    //     puts("");
    // }

    // test 3: pbf16_mul
    float fa = -1.203125;
    float fb = -2.310000;
    float fc = -3.14;
    float fd = 0.1;

    puts("input:");
    bf16_t a = fp32_to_bf16(fa);
    bf16_t b = fp32_to_bf16(fb);
    bf16_t c = fp32_to_bf16(fc);
    bf16_t d = fp32_to_bf16(fd);
    printf("a = ");
    print(a);
    printf("b = ");
    print(b);
    printf("c = ");
    print(c);
    printf("d = ");
    print(d);
    puts("");

    puts("output:");
    pbf16_t pq = pbf16_mul(pbf16_encode(a, b), pbf16_encode(c, d));
    bf16_t p, q;
    pbf16_decode(pq, &p, &q);
    printf("p = ac = ");
    print(p);
    printf("q = bd = ");
    print(q);
    puts("");

    puts("answer:");
    printf("p = ac = ");
    print(fp32_to_bf16(fa * fc));
    printf("q = bd = ");
    print(fp32_to_bf16(fb * fd));

    return 0;
}