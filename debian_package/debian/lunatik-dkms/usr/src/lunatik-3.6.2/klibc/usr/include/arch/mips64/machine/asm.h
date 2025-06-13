/*
 * arch/mips64/include/machine/asm.h
 */

#ifndef _MACHINE_ASM_H
#define _MACHINE_ASM_H

/*
 * Symbolic register names for 64 bit ABI
 */


#define zero    $0      /* wired zero */
#define AT      $at     /* assembler temp - uppercase because of ".set at" */
#define v0      $2      /* return value - caller saved */
#define v1      $3
#define a0      $4      /* argument registers */
#define a1      $5
#define a2      $6
#define a3      $7
#define a4      $8      /* arg reg 64 bit; caller saved in 32 bit */
#define ta0     $8
#define a5      $9
#define ta1     $9
#define a6      $10
#define ta2     $10
#define a7      $11
#define ta3     $11
#define t4      $12     /* caller saved */
#define t5      $13
#define t6      $14
#define t7      $15
#define s0      $16     /* callee saved */
#define s1      $17
#define s2      $18
#define s3      $19
#define s4      $20
#define s5      $21
#define s6      $22
#define s7      $23
#define t8      $24     /* caller saved */
#define t9      $25     /* callee address for PIC/temp */
#define jp      $25     /* PIC jump register */
#define k0      $26     /* kernel temporary */
#define k1      $27
#define gp      $28     /* global pointer - caller saved for PIC */
#define sp      $29     /* stack pointer */
#define fp      $30     /* frame pointer */
#define s8      $30     /* callee saved */
#define ra      $31     /* return address */


/*
 * LEAF - declare leaf routine
 */
#define LEAF(symbol)                                    \
		.globl  symbol;                         \
		.align  2;                              \
		.type   symbol,@function;               \
		.ent    symbol,0;                       \
symbol:		.frame  sp,0,ra


/*
 * NESTED - declare nested routine entry point
 */
#define NESTED(symbol, framesize, rpc)                  \
		.globl  symbol;                         \
		.align  2;                              \
		.type   symbol,@function;               \
		.ent    symbol,0;                       \
symbol:		.frame  sp, framesize, rpc

/*
 * END - mark end of function
 */
#define END(function)                                   \
		.end    function;                       \
		.size   function,.-function


#endif				/* _MACHINE_ASM_H */
