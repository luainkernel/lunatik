
lua/ldo.o:     file format elf64-littleaarch64


Disassembly of section .text:

0000000000000000 <correctstack-0x8>:
       0:	d503201f 	nop
       4:	d503201f 	nop

0000000000000008 <correctstack>:
correctstack():
/home/ubuntu/lunatik/lua/ldo.c:182


/*
** Change back all offsets into pointers.
*/
static void correctstack (lua_State *L) {
       8:	d503201f 	nop
       c:	d503201f 	nop
/home/ubuntu/lunatik/lua/ldo.c:187
  CallInfo *ci;
  UpVal *up;
  L->top.p = restorestack(L, L->top.offset);
  L->tbclist.p = restorestack(L, L->tbclist.offset);
  for (up = L->openupval; up != NULL; up = up->u.open.next)
      10:	a9430c02 	ldp	x2, x3, [x0, #48]
/home/ubuntu/lunatik/lua/ldo.c:185
  L->top.p = restorestack(L, L->top.offset);
      14:	f9400804 	ldr	x4, [x0, #16]
/home/ubuntu/lunatik/lua/ldo.c:186
  L->tbclist.p = restorestack(L, L->tbclist.offset);
      18:	f9402001 	ldr	x1, [x0, #64]
/home/ubuntu/lunatik/lua/ldo.c:185
  L->top.p = restorestack(L, L->top.offset);
      1c:	8b040044 	add	x4, x2, x4
      20:	f9000804 	str	x4, [x0, #16]
/home/ubuntu/lunatik/lua/ldo.c:186
  L->tbclist.p = restorestack(L, L->tbclist.offset);
      24:	8b010041 	add	x1, x2, x1
      28:	f9002001 	str	x1, [x0, #64]
/home/ubuntu/lunatik/lua/ldo.c:187
  for (up = L->openupval; up != NULL; up = up->u.open.next)
      2c:	b4000163 	cbz	x3, 58 <correctstack+0x50>
      30:	a9410464 	ldp	x4, x1, [x3, #16]
/home/ubuntu/lunatik/lua/ldo.c:188
    up->v.p = s2v(restorestack(L, up->v.offset));
      34:	8b040042 	add	x2, x2, x4
      38:	f9000862 	str	x2, [x3, #16]
/home/ubuntu/lunatik/lua/ldo.c:187
  for (up = L->openupval; up != NULL; up = up->u.open.next)
      3c:	b40000e1 	cbz	x1, 58 <correctstack+0x50>
/home/ubuntu/lunatik/lua/ldo.c:188
    up->v.p = s2v(restorestack(L, up->v.offset));
      40:	f9400823 	ldr	x3, [x1, #16]
      44:	f9401802 	ldr	x2, [x0, #48]
      48:	8b030042 	add	x2, x2, x3
      4c:	f9000822 	str	x2, [x1, #16]
/home/ubuntu/lunatik/lua/ldo.c:187
  for (up = L->openupval; up != NULL; up = up->u.open.next)
      50:	f9400c21 	ldr	x1, [x1, #24]
      54:	b5ffff61 	cbnz	x1, 40 <correctstack+0x38>
/home/ubuntu/lunatik/lua/ldo.c:189
  for (ci = L->ci; ci != NULL; ci = ci->previous) {
      58:	f9401001 	ldr	x1, [x0, #32]
/home/ubuntu/lunatik/lua/ldo.c:193
    ci->top.p = restorestack(L, ci->top.offset);
    ci->func.p = restorestack(L, ci->func.offset);
    if (isLua(ci))
      ci->u.l.trap = 1;  /* signal to update 'trap' in 'luaV_execute' */
      5c:	52800025 	mov	w5, #0x1                   	// #1
/home/ubuntu/lunatik/lua/ldo.c:189
  for (ci = L->ci; ci != NULL; ci = ci->previous) {
      60:	b40001c1 	cbz	x1, 98 <correctstack+0x90>
      64:	d503201f 	nop
/home/ubuntu/lunatik/lua/ldo.c:190
    ci->top.p = restorestack(L, ci->top.offset);
      68:	a9400c24 	ldp	x4, x3, [x1]
      6c:	f9401802 	ldr	x2, [x0, #48]
      70:	8b030042 	add	x2, x2, x3
      74:	f9000422 	str	x2, [x1, #8]
/home/ubuntu/lunatik/lua/ldo.c:192
    if (isLua(ci))
      78:	79407c23 	ldrh	w3, [x1, #62]
/home/ubuntu/lunatik/lua/ldo.c:191
    ci->func.p = restorestack(L, ci->func.offset);
      7c:	f9401802 	ldr	x2, [x0, #48]
      80:	8b040042 	add	x2, x2, x4
      84:	f9000022 	str	x2, [x1]
/home/ubuntu/lunatik/lua/ldo.c:192
    if (isLua(ci))
      88:	37080043 	tbnz	w3, #1, 90 <correctstack+0x88>
/home/ubuntu/lunatik/lua/ldo.c:193
      ci->u.l.trap = 1;  /* signal to update 'trap' in 'luaV_execute' */
      8c:	b9002825 	str	w5, [x1, #40]
/home/ubuntu/lunatik/lua/ldo.c:189 (discriminator 2)
  for (ci = L->ci; ci != NULL; ci = ci->previous) {
      90:	f9400821 	ldr	x1, [x1, #16]
      94:	b5fffea1 	cbnz	x1, 68 <correctstack+0x60>
/home/ubuntu/lunatik/lua/ldo.c:195
  }
}
      98:	d2800000 	mov	x0, #0x0                   	// #0
      9c:	d2800001 	mov	x1, #0x0                   	// #0
      a0:	d2800002 	mov	x2, #0x0                   	// #0
      a4:	d2800003 	mov	x3, #0x0                   	// #0
      a8:	d2800004 	mov	x4, #0x0                   	// #0
      ac:	d2800005 	mov	x5, #0x0                   	// #0
      b0:	d65f03c0 	ret
      b4:	d503201f 	nop
      b8:	d503201f 	nop
      bc:	d503201f 	nop

00000000000000c0 <closepaux>:
closepaux():
/home/ubuntu/lunatik/lua/ldo.c:914


/*
** Auxiliary function to call 'luaF_close' in protected mode.
*/
static void closepaux (lua_State *L, void *ud) {
      c0:	d503201f 	nop
      c4:	d503201f 	nop
      c8:	d503233f 	paciasp
      cc:	aa0103e2 	mov	x2, x1
      d0:	f800865e 	str	x30, [x18], #8
/home/ubuntu/lunatik/lua/ldo.c:916
  struct CloseP *pcl = cast(struct CloseP *, ud);
  luaF_close(L, pcl->level, pcl->status, 0);
      d4:	52800003 	mov	w3, #0x0                   	// #0
/home/ubuntu/lunatik/lua/ldo.c:914
static void closepaux (lua_State *L, void *ud) {
      d8:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
      dc:	910003fd 	mov	x29, sp
/home/ubuntu/lunatik/lua/ldo.c:916
  luaF_close(L, pcl->level, pcl->status, 0);
      e0:	f9400021 	ldr	x1, [x1]
      e4:	b9400842 	ldr	w2, [x2, #8]
      e8:	94000000 	bl	0 <luaF_close>
			e8: R_AARCH64_CALL26	luaF_close
/home/ubuntu/lunatik/lua/ldo.c:917
}
      ec:	f85f8e5e 	ldr	x30, [x18, #-8]!
      f0:	f84107fd 	ldr	x29, [sp], #16
      f4:	d50323bf 	autiasp
      f8:	d2800000 	mov	x0, #0x0                   	// #0
      fc:	d2800001 	mov	x1, #0x0                   	// #0
     100:	d2800002 	mov	x2, #0x0                   	// #0
     104:	d2800003 	mov	x3, #0x0                   	// #0
     108:	d2800010 	mov	x16, #0x0                   	// #0
     10c:	d2800011 	mov	x17, #0x0                   	// #0
     110:	d65f03c0 	ret
     114:	d503201f 	nop
     118:	d503201f 	nop
     11c:	d503201f 	nop

0000000000000120 <luaD_seterrorobj>:
luaD_seterrorobj():
/home/ubuntu/lunatik/lua/ldo.c:91
void luaD_seterrorobj (lua_State *L, int errcode, StkId oldtop) {
     120:	d503201f 	nop
     124:	d503201f 	nop
     128:	d503233f 	paciasp
     12c:	f800865e 	str	x30, [x18], #8
     130:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
     134:	910003fd 	mov	x29, sp
     138:	a90153f3 	stp	x19, x20, [sp, #16]
     13c:	aa0203f3 	mov	x19, x2
     140:	aa0003f4 	mov	x20, x0
/home/ubuntu/lunatik/lua/ldo.c:92
  switch (errcode) {
     144:	7100103f 	cmp	w1, #0x4
     148:	540002a0 	b.eq	19c <luaD_seterrorobj+0x7c>  // b.none
     14c:	7100143f 	cmp	w1, #0x5
     150:	54000640 	b.eq	218 <luaD_seterrorobj+0xf8>  // b.none
     154:	34000481 	cbz	w1, 1e4 <luaD_seterrorobj+0xc4>
/home/ubuntu/lunatik/lua/ldo.c:107
      setobjs2s(L, oldtop, L->top.p - 1);  /* error message on current top */
     158:	f9400800 	ldr	x0, [x0, #16]
/home/ubuntu/lunatik/lua/ldo.c:111
  L->top.p = oldtop + 1;
     15c:	91004273 	add	x19, x19, #0x10
/home/ubuntu/lunatik/lua/ldo.c:107
      setobjs2s(L, oldtop, L->top.p - 1);  /* error message on current top */
     160:	f85f0001 	ldur	x1, [x0, #-16]
     164:	f9000041 	str	x1, [x2]
     168:	385f8000 	ldurb	w0, [x0, #-8]
     16c:	39002040 	strb	w0, [x2, #8]
/home/ubuntu/lunatik/lua/ldo.c:111
  L->top.p = oldtop + 1;
     170:	f9000a93 	str	x19, [x20, #16]
/home/ubuntu/lunatik/lua/ldo.c:112
}
     174:	f85f8e5e 	ldr	x30, [x18, #-8]!
     178:	a94153f3 	ldp	x19, x20, [sp, #16]
     17c:	f84207fd 	ldr	x29, [sp], #32
     180:	d50323bf 	autiasp
     184:	d2800000 	mov	x0, #0x0                   	// #0
     188:	d2800001 	mov	x1, #0x0                   	// #0
     18c:	d2800002 	mov	x2, #0x0                   	// #0
     190:	d2800010 	mov	x16, #0x0                   	// #0
     194:	d2800011 	mov	x17, #0x0                   	// #0
     198:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:94
      setsvalue2s(L, oldtop, G(L)->memerrmsg); /* reuse preregistered msg. */
     19c:	f9400c00 	ldr	x0, [x0, #24]
/home/ubuntu/lunatik/lua/ldo.c:111
  L->top.p = oldtop + 1;
     1a0:	91004273 	add	x19, x19, #0x10
/home/ubuntu/lunatik/lua/ldo.c:94
      setsvalue2s(L, oldtop, G(L)->memerrmsg); /* reuse preregistered msg. */
     1a4:	f9408800 	ldr	x0, [x0, #272]
     1a8:	f9000040 	str	x0, [x2]
     1ac:	39402000 	ldrb	w0, [x0, #8]
     1b0:	321a0000 	orr	w0, w0, #0x40
     1b4:	39002040 	strb	w0, [x2, #8]
/home/ubuntu/lunatik/lua/ldo.c:111
  L->top.p = oldtop + 1;
     1b8:	f9000a93 	str	x19, [x20, #16]
/home/ubuntu/lunatik/lua/ldo.c:112
}
     1bc:	f85f8e5e 	ldr	x30, [x18, #-8]!
     1c0:	a94153f3 	ldp	x19, x20, [sp, #16]
     1c4:	f84207fd 	ldr	x29, [sp], #32
     1c8:	d50323bf 	autiasp
     1cc:	d2800000 	mov	x0, #0x0                   	// #0
     1d0:	d2800001 	mov	x1, #0x0                   	// #0
     1d4:	d2800002 	mov	x2, #0x0                   	// #0
     1d8:	d2800010 	mov	x16, #0x0                   	// #0
     1dc:	d2800011 	mov	x17, #0x0                   	// #0
     1e0:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:102
      setnilvalue(s2v(oldtop));  /* no error message */
     1e4:	3900205f 	strb	wzr, [x2, #8]
/home/ubuntu/lunatik/lua/ldo.c:111
  L->top.p = oldtop + 1;
     1e8:	91004273 	add	x19, x19, #0x10
     1ec:	f9000a93 	str	x19, [x20, #16]
/home/ubuntu/lunatik/lua/ldo.c:112
}
     1f0:	f85f8e5e 	ldr	x30, [x18, #-8]!
     1f4:	a94153f3 	ldp	x19, x20, [sp, #16]
     1f8:	f84207fd 	ldr	x29, [sp], #32
     1fc:	d50323bf 	autiasp
     200:	d2800000 	mov	x0, #0x0                   	// #0
     204:	d2800001 	mov	x1, #0x0                   	// #0
     208:	d2800002 	mov	x2, #0x0                   	// #0
     20c:	d2800010 	mov	x16, #0x0                   	// #0
     210:	d2800011 	mov	x17, #0x0                   	// #0
     214:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:98
      setsvalue2s(L, oldtop, luaS_newliteral(L, "error in error handling"));
     218:	d28002e2 	mov	x2, #0x17                  	// #23
     21c:	90000001 	adrp	x1, 0 <correctstack-0x8>
			21c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.8
     220:	91000021 	add	x1, x1, #0x0
			220: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.8
     224:	94000000 	bl	0 <luaS_newlstr>
			224: R_AARCH64_CALL26	luaS_newlstr
     228:	f9000260 	str	x0, [x19]
/home/ubuntu/lunatik/lua/ldo.c:111
  L->top.p = oldtop + 1;
     22c:	91004273 	add	x19, x19, #0x10
/home/ubuntu/lunatik/lua/ldo.c:98
      setsvalue2s(L, oldtop, luaS_newliteral(L, "error in error handling"));
     230:	39402000 	ldrb	w0, [x0, #8]
     234:	321a0000 	orr	w0, w0, #0x40
     238:	381f8260 	sturb	w0, [x19, #-8]
/home/ubuntu/lunatik/lua/ldo.c:111
  L->top.p = oldtop + 1;
     23c:	f9000a93 	str	x19, [x20, #16]
/home/ubuntu/lunatik/lua/ldo.c:112
}
     240:	f85f8e5e 	ldr	x30, [x18, #-8]!
     244:	a94153f3 	ldp	x19, x20, [sp, #16]
     248:	f84207fd 	ldr	x29, [sp], #32
     24c:	d50323bf 	autiasp
     250:	d2800000 	mov	x0, #0x0                   	// #0
     254:	d2800001 	mov	x1, #0x0                   	// #0
     258:	d2800002 	mov	x2, #0x0                   	// #0
     25c:	d2800010 	mov	x16, #0x0                   	// #0
     260:	d2800011 	mov	x17, #0x0                   	// #0
     264:	d65f03c0 	ret
     268:	d503201f 	nop
     26c:	d503201f 	nop

0000000000000270 <luaD_throw>:
luaD_throw():
/home/ubuntu/lunatik/lua/ldo.c:115
l_noret luaD_throw (lua_State *L, int errcode) {
     270:	d503201f 	nop
     274:	d503201f 	nop
     278:	d503233f 	paciasp
     27c:	f800865e 	str	x30, [x18], #8
     280:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
     284:	910003fd 	mov	x29, sp
     288:	a90153f3 	stp	x19, x20, [sp, #16]
     28c:	aa0003f3 	mov	x19, x0
/home/ubuntu/lunatik/lua/ldo.c:116
  if (L->errorJmp) {  /* thread has an error handler? */
     290:	f9402c03 	ldr	x3, [x0, #88]
     294:	b40000e3 	cbz	x3, 2b0 <luaD_throw+0x40>
/home/ubuntu/lunatik/lua/ldo.c:117
    L->errorJmp->status = errcode;  /* set status */
     298:	2a0103e2 	mov	w2, w1
     29c:	b9007062 	str	w2, [x3, #112]
/home/ubuntu/lunatik/lua/ldo.c:118
    LUAI_THROW(L, L->errorJmp);  /* jump to it */
     2a0:	52800021 	mov	w1, #0x1                   	// #1
     2a4:	f9402c00 	ldr	x0, [x0, #88]
     2a8:	91002000 	add	x0, x0, #0x8
     2ac:	94000000 	bl	0 <longjmp>
			2ac: R_AARCH64_CALL26	longjmp
/home/ubuntu/lunatik/lua/ldo.c:121
    global_State *g = G(L);
     2b0:	f9400c14 	ldr	x20, [x0, #24]
/home/ubuntu/lunatik/lua/ldo.c:122
    errcode = luaE_resetthread(L, errcode);  /* close all upvalues */
     2b4:	94000000 	bl	0 <luaE_resetthread>
			2b4: R_AARCH64_CALL26	luaE_resetthread
     2b8:	2a0003e1 	mov	w1, w0
/home/ubuntu/lunatik/lua/ldo.c:123
    if (g->mainthread->errorJmp) {  /* main thread has a handler? */
     2bc:	f9408680 	ldr	x0, [x20, #264]
     2c0:	f9402c02 	ldr	x2, [x0, #88]
     2c4:	b4000162 	cbz	x2, 2f0 <luaD_throw+0x80>
/home/ubuntu/lunatik/lua/ldo.c:124
      setobjs2s(L, g->mainthread->top.p++, L->top.p - 1);  /* copy error obj. */
     2c8:	f9400802 	ldr	x2, [x0, #16]
     2cc:	91004043 	add	x3, x2, #0x10
     2d0:	f9000803 	str	x3, [x0, #16]
     2d4:	f9400a60 	ldr	x0, [x19, #16]
     2d8:	f85f0003 	ldur	x3, [x0, #-16]
     2dc:	f9000043 	str	x3, [x2]
     2e0:	385f8000 	ldurb	w0, [x0, #-8]
     2e4:	39002040 	strb	w0, [x2, #8]
/home/ubuntu/lunatik/lua/ldo.c:125
      luaD_throw(g->mainthread, errcode);  /* re-throw in main thread */
     2e8:	f9408680 	ldr	x0, [x20, #264]
     2ec:	94000000 	bl	270 <luaD_throw>
			2ec: R_AARCH64_CALL26	luaD_throw
/home/ubuntu/lunatik/lua/ldo.c:128
      if (g->panic) {  /* panic function? */
     2f0:	f9408281 	ldr	x1, [x20, #256]
     2f4:	b4000061 	cbz	x1, 300 <luaD_throw+0x90>
/home/ubuntu/lunatik/lua/ldo.c:130
        g->panic(L);  /* call panic function (last chance to jump out) */
     2f8:	aa1303e0 	mov	x0, x19
     2fc:	d63f0020 	blr	x1
/home/ubuntu/lunatik/lua/ldo.c:132
      abort();
     300:	d4210000 	brk	#0x800
     304:	d503201f 	nop
     308:	d503201f 	nop
     30c:	d503201f 	nop

0000000000000310 <f_parser>:
f_parser():
/home/ubuntu/lunatik/lua/ldo.c:988
    luaD_throw(L, LUA_ERRSYNTAX);
  }
}


static void f_parser (lua_State *L, void *ud) {
     310:	d503201f 	nop
     314:	d503201f 	nop
     318:	d503233f 	paciasp
     31c:	f800865e 	str	x30, [x18], #8
     320:	a9bd7bfd 	stp	x29, x30, [sp, #-48]!
     324:	910003fd 	mov	x29, sp
     328:	a90153f3 	stp	x19, x20, [sp, #16]
     32c:	aa0103f3 	mov	x19, x1
     330:	aa0003f4 	mov	x20, x0
     334:	a9025bf5 	stp	x21, x22, [sp, #32]
/home/ubuntu/lunatik/lua/ldo.c:991
  LClosure *cl;
  struct SParser *p = cast(struct SParser *, ud);
  int c = zgetc(p->z);  /* read first character */
     338:	f9400021 	ldr	x1, [x1]
     33c:	f9400020 	ldr	x0, [x1]
     340:	d1000402 	sub	x2, x0, #0x1
     344:	f9000022 	str	x2, [x1]
     348:	b4000800 	cbz	x0, 448 <f_parser+0x138>
/home/ubuntu/lunatik/lua/ldo.c:991 (discriminator 1)
     34c:	f9400261 	ldr	x1, [x19]
     350:	f9400420 	ldr	x0, [x1, #8]
     354:	91000402 	add	x2, x0, #0x1
     358:	f9000422 	str	x2, [x1, #8]
     35c:	39400015 	ldrb	w21, [x0]
/home/ubuntu/lunatik/lua/ldo.c:993 (discriminator 4)
  if (c == LUA_SIGNATURE[0]) {
    checkmode(L, p->mode, "binary");
     360:	f9402a76 	ldr	x22, [x19, #80]
/home/ubuntu/lunatik/lua/ldo.c:992 (discriminator 4)
  if (c == LUA_SIGNATURE[0]) {
     364:	71006ebf 	cmp	w21, #0x1b
     368:	540003c0 	b.eq	3e0 <f_parser+0xd0>  // b.none
checkmode():
/home/ubuntu/lunatik/lua/ldo.c:980
  if (mode && strchr(mode, x[0]) == NULL) {
     36c:	b40000b6 	cbz	x22, 380 <f_parser+0x70>
     370:	aa1603e0 	mov	x0, x22
     374:	52800e81 	mov	w1, #0x74                  	// #116
     378:	94000000 	bl	0 <strchr>
			378: R_AARCH64_CALL26	strchr
     37c:	b40006e0 	cbz	x0, 458 <f_parser+0x148>
f_parser():
/home/ubuntu/lunatik/lua/ldo.c:998
    cl = luaU_undump(L, p->z, p->name);
  }
  else {
    checkmode(L, p->mode, "text");
    cl = luaY_parser(L, p->z, &p->buff, &p->dyd, p->name, c);
     380:	aa1303e2 	mov	x2, x19
     384:	2a1503e5 	mov	w5, w21
     388:	f9402e64 	ldr	x4, [x19, #88]
     38c:	91008263 	add	x3, x19, #0x20
     390:	f8408441 	ldr	x1, [x2], #8
     394:	aa1403e0 	mov	x0, x20
     398:	94000000 	bl	0 <luaY_parser>
			398: R_AARCH64_CALL26	luaY_parser
     39c:	aa0003e1 	mov	x1, x0
/home/ubuntu/lunatik/lua/ldo.c:1001
  }
  lua_assert(cl->nupvalues == cl->p->sizeupvalues);
  luaF_initupvals(L, cl);
     3a0:	aa1403e0 	mov	x0, x20
     3a4:	94000000 	bl	0 <luaF_initupvals>
			3a4: R_AARCH64_CALL26	luaF_initupvals
/home/ubuntu/lunatik/lua/ldo.c:1002
}
     3a8:	f85f8e5e 	ldr	x30, [x18, #-8]!
     3ac:	a94153f3 	ldp	x19, x20, [sp, #16]
     3b0:	a9425bf5 	ldp	x21, x22, [sp, #32]
     3b4:	f84307fd 	ldr	x29, [sp], #48
     3b8:	d50323bf 	autiasp
     3bc:	d2800000 	mov	x0, #0x0                   	// #0
     3c0:	d2800001 	mov	x1, #0x0                   	// #0
     3c4:	d2800002 	mov	x2, #0x0                   	// #0
     3c8:	d2800003 	mov	x3, #0x0                   	// #0
     3cc:	d2800004 	mov	x4, #0x0                   	// #0
     3d0:	d2800005 	mov	x5, #0x0                   	// #0
     3d4:	d2800010 	mov	x16, #0x0                   	// #0
     3d8:	d2800011 	mov	x17, #0x0                   	// #0
     3dc:	d65f03c0 	ret
checkmode():
/home/ubuntu/lunatik/lua/ldo.c:980
  if (mode && strchr(mode, x[0]) == NULL) {
     3e0:	b40000b6 	cbz	x22, 3f4 <f_parser+0xe4>
     3e4:	aa1603e0 	mov	x0, x22
     3e8:	52800c41 	mov	w1, #0x62                  	// #98
     3ec:	94000000 	bl	0 <strchr>
			3ec: R_AARCH64_CALL26	strchr
     3f0:	b4000480 	cbz	x0, 480 <f_parser+0x170>
f_parser():
/home/ubuntu/lunatik/lua/ldo.c:994
    cl = luaU_undump(L, p->z, p->name);
     3f4:	f9400261 	ldr	x1, [x19]
     3f8:	aa1403e0 	mov	x0, x20
     3fc:	f9402e62 	ldr	x2, [x19, #88]
     400:	94000000 	bl	0 <luaU_undump>
			400: R_AARCH64_CALL26	luaU_undump
     404:	aa0003e1 	mov	x1, x0
/home/ubuntu/lunatik/lua/ldo.c:1001
  luaF_initupvals(L, cl);
     408:	aa1403e0 	mov	x0, x20
     40c:	94000000 	bl	0 <luaF_initupvals>
			40c: R_AARCH64_CALL26	luaF_initupvals
/home/ubuntu/lunatik/lua/ldo.c:1002
}
     410:	f85f8e5e 	ldr	x30, [x18, #-8]!
     414:	a94153f3 	ldp	x19, x20, [sp, #16]
     418:	a9425bf5 	ldp	x21, x22, [sp, #32]
     41c:	f84307fd 	ldr	x29, [sp], #48
     420:	d50323bf 	autiasp
     424:	d2800000 	mov	x0, #0x0                   	// #0
     428:	d2800001 	mov	x1, #0x0                   	// #0
     42c:	d2800002 	mov	x2, #0x0                   	// #0
     430:	d2800003 	mov	x3, #0x0                   	// #0
     434:	d2800004 	mov	x4, #0x0                   	// #0
     438:	d2800005 	mov	x5, #0x0                   	// #0
     43c:	d2800010 	mov	x16, #0x0                   	// #0
     440:	d2800011 	mov	x17, #0x0                   	// #0
     444:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:991 (discriminator 2)
  int c = zgetc(p->z);  /* read first character */
     448:	f9400260 	ldr	x0, [x19]
     44c:	94000000 	bl	0 <luaZ_fill>
			44c: R_AARCH64_CALL26	luaZ_fill
     450:	2a0003f5 	mov	w21, w0
     454:	17ffffc3 	b	360 <f_parser+0x50>
checkmode():
/home/ubuntu/lunatik/lua/ldo.c:981
    luaO_pushfstring(L,
     458:	90000002 	adrp	x2, 0 <correctstack-0x8>
			458: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.8+0x50
     45c:	aa1603e3 	mov	x3, x22
     460:	91000042 	add	x2, x2, #0x0
			460: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.8+0x50
     464:	aa1403e0 	mov	x0, x20
     468:	90000001 	adrp	x1, 0 <correctstack-0x8>
			468: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.8+0x20
     46c:	91000021 	add	x1, x1, #0x0
			46c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.8+0x20
     470:	94000000 	bl	0 <luaO_pushfstring>
			470: R_AARCH64_CALL26	luaO_pushfstring
/home/ubuntu/lunatik/lua/ldo.c:983
    luaD_throw(L, LUA_ERRSYNTAX);
     474:	aa1403e0 	mov	x0, x20
     478:	52800061 	mov	w1, #0x3                   	// #3
     47c:	94000000 	bl	270 <luaD_throw>
			47c: R_AARCH64_CALL26	luaD_throw
/home/ubuntu/lunatik/lua/ldo.c:981
    luaO_pushfstring(L,
     480:	90000002 	adrp	x2, 0 <correctstack-0x8>
			480: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.8+0x18
     484:	aa1603e3 	mov	x3, x22
     488:	91000042 	add	x2, x2, #0x0
			488: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.8+0x18
     48c:	17fffff6 	b	464 <f_parser+0x154>
f_parser():
/home/ubuntu/lunatik/lua/ldo.c:981
     490:	d503201f 	nop
     494:	d503201f 	nop

0000000000000498 <luaD_rawrunprotected>:
luaD_rawrunprotected():
/home/ubuntu/lunatik/lua/ldo.c:138
int luaD_rawrunprotected (lua_State *L, Pfunc f, void *ud) {
     498:	d503201f 	nop
     49c:	d503201f 	nop
     4a0:	d503233f 	paciasp
     4a4:	f800865e 	str	x30, [x18], #8
     4a8:	a9b47bfd 	stp	x29, x30, [sp, #-192]!
     4ac:	d5384103 	mrs	x3, sp_el0
     4b0:	910003fd 	mov	x29, sp
     4b4:	f9000bf3 	str	x19, [sp, #16]
     4b8:	aa0003f3 	mov	x19, x0
     4bc:	f90013e0 	str	x0, [sp, #32]
/home/ubuntu/lunatik/lua/ldo.c:140
  struct lua_longjmp lj;
     4c0:	910103e4 	add	x4, sp, #0x40
/home/ubuntu/lunatik/lua/ldo.c:139
  l_uint32 oldnCcalls = L->nCcalls;
     4c4:	b940b000 	ldr	w0, [x0, #176]
     4c8:	b9002fe0 	str	w0, [sp, #44]
/home/ubuntu/lunatik/lua/ldo.c:138
int luaD_rawrunprotected (lua_State *L, Pfunc f, void *ud) {
     4cc:	a9030be1 	stp	x1, x2, [sp, #48]
/home/ubuntu/lunatik/lua/ldo.c:140
  struct lua_longjmp lj;
     4d0:	52800001 	mov	w1, #0x0                   	// #0
     4d4:	d2800f02 	mov	x2, #0x78                  	// #120
/home/ubuntu/lunatik/lua/ldo.c:138
int luaD_rawrunprotected (lua_State *L, Pfunc f, void *ud) {
     4d8:	f9430060 	ldr	x0, [x3, #1536]
     4dc:	f9005fe0 	str	x0, [sp, #184]
     4e0:	d2800000 	mov	x0, #0x0                   	// #0
/home/ubuntu/lunatik/lua/ldo.c:140
  struct lua_longjmp lj;
     4e4:	aa0403e0 	mov	x0, x4
     4e8:	94000000 	bl	0 <memset>
			4e8: R_AARCH64_CALL26	memset
/home/ubuntu/lunatik/lua/ldo.c:142
  lj.previous = L->errorJmp;  /* chain new error handler */
     4ec:	f9402e61 	ldr	x1, [x19, #88]
/home/ubuntu/lunatik/lua/ldo.c:143
  L->errorJmp = &lj;
     4f0:	f9002e60 	str	x0, [x19, #88]
/home/ubuntu/lunatik/lua/ldo.c:144
  LUAI_TRY(L, &lj,
     4f4:	910123e0 	add	x0, sp, #0x48
/home/ubuntu/lunatik/lua/ldo.c:142
  lj.previous = L->errorJmp;  /* chain new error handler */
     4f8:	f90023e1 	str	x1, [sp, #64]
/home/ubuntu/lunatik/lua/ldo.c:141
  lj.status = LUA_OK;
     4fc:	b900b3ff 	str	wzr, [sp, #176]
/home/ubuntu/lunatik/lua/ldo.c:144
  LUAI_TRY(L, &lj,
     500:	94000000 	bl	0 <setjmp>
			500: R_AARCH64_CALL26	setjmp
     504:	35000080 	cbnz	w0, 514 <luaD_rawrunprotected+0x7c>
/home/ubuntu/lunatik/lua/ldo.c:144 (discriminator 2)
     508:	a94307e2 	ldp	x2, x1, [sp, #48]
     50c:	f94013e0 	ldr	x0, [sp, #32]
     510:	d63f0040 	blr	x2
/home/ubuntu/lunatik/lua/ldo.c:147
  L->errorJmp = lj.previous;  /* restore old error handler */
     514:	f94013e3 	ldr	x3, [sp, #32]
/home/ubuntu/lunatik/lua/ldo.c:150
}
     518:	d5384101 	mrs	x1, sp_el0
/home/ubuntu/lunatik/lua/ldo.c:147
  L->errorJmp = lj.previous;  /* restore old error handler */
     51c:	f94023e2 	ldr	x2, [sp, #64]
     520:	f9002c62 	str	x2, [x3, #88]
/home/ubuntu/lunatik/lua/ldo.c:148
  L->nCcalls = oldnCcalls;
     524:	aa0303e2 	mov	x2, x3
/home/ubuntu/lunatik/lua/ldo.c:149
  return lj.status;
     528:	b940b3e0 	ldr	w0, [sp, #176]
/home/ubuntu/lunatik/lua/ldo.c:148
  L->nCcalls = oldnCcalls;
     52c:	b9402fe3 	ldr	w3, [sp, #44]
     530:	b900b043 	str	w3, [x2, #176]
/home/ubuntu/lunatik/lua/ldo.c:150
}
     534:	f9405fe3 	ldr	x3, [sp, #184]
     538:	f9430022 	ldr	x2, [x1, #1536]
     53c:	eb020063 	subs	x3, x3, x2
     540:	d2800002 	mov	x2, #0x0                   	// #0
     544:	54000181 	b.ne	574 <luaD_rawrunprotected+0xdc>  // b.any
     548:	f9400bf3 	ldr	x19, [sp, #16]
     54c:	f85f8e5e 	ldr	x30, [x18, #-8]!
     550:	f84c07fd 	ldr	x29, [sp], #192
     554:	d50323bf 	autiasp
     558:	d2800001 	mov	x1, #0x0                   	// #0
     55c:	d2800002 	mov	x2, #0x0                   	// #0
     560:	d2800003 	mov	x3, #0x0                   	// #0
     564:	d2800004 	mov	x4, #0x0                   	// #0
     568:	d2800010 	mov	x16, #0x0                   	// #0
     56c:	d2800011 	mov	x17, #0x0                   	// #0
     570:	d65f03c0 	ret
     574:	94000000 	bl	0 <__stack_chk_fail>
			574: R_AARCH64_CALL26	__stack_chk_fail
     578:	d503201f 	nop
     57c:	d503201f 	nop

0000000000000580 <luaD_reallocstack>:
luaD_reallocstack():
/home/ubuntu/lunatik/lua/ldo.c:212
int luaD_reallocstack (lua_State *L, int newsize, int raiseerror) {
     580:	d503201f 	nop
     584:	d503201f 	nop
     588:	d503233f 	paciasp
     58c:	f800865e 	str	x30, [x18], #8
     590:	a9ba7bfd 	stp	x29, x30, [sp, #-96]!
     594:	910003fd 	mov	x29, sp
     598:	a90153f3 	stp	x19, x20, [sp, #16]
     59c:	aa0003f3 	mov	x19, x0
     5a0:	a9025bf5 	stp	x21, x22, [sp, #32]
     5a4:	2a0103f5 	mov	w21, w1
     5a8:	a90363f7 	stp	x23, x24, [sp, #48]
     5ac:	2a0203f7 	mov	w23, w2
     5b0:	a9046bf9 	stp	x25, x26, [sp, #64]
     5b4:	a90573fb 	stp	x27, x28, [sp, #80]
/home/ubuntu/lunatik/lua/ldo.c:216
  int oldgcstop = G(L)->gcstopem;
     5b8:	a9411003 	ldp	x3, x4, [x0, #16]
/home/ubuntu/lunatik/lua/ldo.c:213
  int oldsize = stacksize(L);
     5bc:	a9428416 	ldp	x22, x1, [x0, #40]
relstack():
/home/ubuntu/lunatik/lua/ldo.c:169
  L->tbclist.offset = savestack(L, L->tbclist.p);
     5c0:	f9402000 	ldr	x0, [x0, #64]
/home/ubuntu/lunatik/lua/ldo.c:170
  for (up = L->openupval; up != NULL; up = up->u.open.next)
     5c4:	f9401e62 	ldr	x2, [x19, #56]
luaD_reallocstack():
/home/ubuntu/lunatik/lua/ldo.c:216
  int oldgcstop = G(L)->gcstopem;
     5c8:	39419c9a 	ldrb	w26, [x4, #103]
relstack():
/home/ubuntu/lunatik/lua/ldo.c:168
  L->top.offset = savestack(L, L->top.p);
     5cc:	cb010063 	sub	x3, x3, x1
/home/ubuntu/lunatik/lua/ldo.c:169
  L->tbclist.offset = savestack(L, L->tbclist.p);
     5d0:	cb010000 	sub	x0, x0, x1
luaD_reallocstack():
/home/ubuntu/lunatik/lua/ldo.c:213
  int oldsize = stacksize(L);
     5d4:	cb0102d6 	sub	x22, x22, x1
relstack():
/home/ubuntu/lunatik/lua/ldo.c:168
  L->top.offset = savestack(L, L->top.p);
     5d8:	f9000a63 	str	x3, [x19, #16]
/home/ubuntu/lunatik/lua/ldo.c:169
  L->tbclist.offset = savestack(L, L->tbclist.p);
     5dc:	f9002260 	str	x0, [x19, #64]
luaD_reallocstack():
/home/ubuntu/lunatik/lua/ldo.c:213
  int oldsize = stacksize(L);
     5e0:	9344fed6 	asr	x22, x22, #4
relstack():
/home/ubuntu/lunatik/lua/ldo.c:170
  for (up = L->openupval; up != NULL; up = up->u.open.next)
     5e4:	b4000162 	cbz	x2, 610 <luaD_reallocstack+0x90>
     5e8:	a9410043 	ldp	x3, x0, [x2, #16]
/home/ubuntu/lunatik/lua/ldo.c:171
    up->v.offset = savestack(L, uplevel(up));
     5ec:	cb010061 	sub	x1, x3, x1
     5f0:	f9000841 	str	x1, [x2, #16]
/home/ubuntu/lunatik/lua/ldo.c:170
  for (up = L->openupval; up != NULL; up = up->u.open.next)
     5f4:	b40000e0 	cbz	x0, 610 <luaD_reallocstack+0x90>
/home/ubuntu/lunatik/lua/ldo.c:171
    up->v.offset = savestack(L, uplevel(up));
     5f8:	f9400801 	ldr	x1, [x0, #16]
     5fc:	f9401a62 	ldr	x2, [x19, #48]
     600:	cb020021 	sub	x1, x1, x2
     604:	f9000801 	str	x1, [x0, #16]
/home/ubuntu/lunatik/lua/ldo.c:170
  for (up = L->openupval; up != NULL; up = up->u.open.next)
     608:	f9400c00 	ldr	x0, [x0, #24]
     60c:	b5ffff60 	cbnz	x0, 5f8 <luaD_reallocstack+0x78>
/home/ubuntu/lunatik/lua/ldo.c:172
  for (ci = L->ci; ci != NULL; ci = ci->previous) {
     610:	f9401263 	ldr	x3, [x19, #32]
     614:	b4000143 	cbz	x3, 63c <luaD_reallocstack+0xbc>
/home/ubuntu/lunatik/lua/ldo.c:173
    ci->top.offset = savestack(L, ci->top.p);
     618:	a9401060 	ldp	x0, x4, [x3]
     61c:	f9401a61 	ldr	x1, [x19, #48]
     620:	cb010084 	sub	x4, x4, x1
     624:	f9000464 	str	x4, [x3, #8]
/home/ubuntu/lunatik/lua/ldo.c:174
    ci->func.offset = savestack(L, ci->func.p);
     628:	f9401a61 	ldr	x1, [x19, #48]
     62c:	cb010000 	sub	x0, x0, x1
     630:	f9000060 	str	x0, [x3]
/home/ubuntu/lunatik/lua/ldo.c:172
  for (ci = L->ci; ci != NULL; ci = ci->previous) {
     634:	f9400863 	ldr	x3, [x3, #16]
     638:	b5ffff03 	cbnz	x3, 618 <luaD_reallocstack+0x98>
luaD_reallocstack():
/home/ubuntu/lunatik/lua/ldo.c:219
  G(L)->gcstopem = 1;  /* stop emergency collection */
     63c:	f9400e61 	ldr	x1, [x19, #24]
     640:	52800022 	mov	w2, #0x1                   	// #1
/home/ubuntu/lunatik/lua/ldo.c:220
  newstack = luaM_reallocvector(L, L->stack.p, oldsize + EXTRA_STACK,
     644:	110016dc 	add	w28, w22, #0x5
     648:	110016bb 	add	w27, w21, #0x5
     64c:	aa1303e0 	mov	x0, x19
/home/ubuntu/lunatik/lua/ldo.c:219
  G(L)->gcstopem = 1;  /* stop emergency collection */
     650:	39019c22 	strb	w2, [x1, #103]
/home/ubuntu/lunatik/lua/ldo.c:220
  newstack = luaM_reallocvector(L, L->stack.p, oldsize + EXTRA_STACK,
     654:	937c7f94 	sbfiz	x20, x28, #4, #32
     658:	937c7f63 	sbfiz	x3, x27, #4, #32
     65c:	aa1403e2 	mov	x2, x20
     660:	f9401a61 	ldr	x1, [x19, #48]
     664:	93407f99 	sxtw	x25, w28
     668:	94000000 	bl	0 <luaM_realloc_>
			668: R_AARCH64_CALL26	luaM_realloc_
     66c:	aa0003f8 	mov	x24, x0
/home/ubuntu/lunatik/lua/ldo.c:222
  G(L)->gcstopem = oldgcstop;  /* restore emergency collection */
     670:	f9400e61 	ldr	x1, [x19, #24]
     674:	39019c3a 	strb	w26, [x1, #103]
/home/ubuntu/lunatik/lua/ldo.c:223
  if (l_unlikely(newstack == NULL)) {  /* reallocation failed? */
     678:	b4000480 	cbz	x0, 708 <luaD_reallocstack+0x188>
/home/ubuntu/lunatik/lua/ldo.c:229
  L->stack.p = newstack;
     67c:	f9001a78 	str	x24, [x19, #48]
/home/ubuntu/lunatik/lua/ldo.c:230
  correctstack(L);  /* change offsets back to pointers */
     680:	aa1303e0 	mov	x0, x19
     684:	97fffe61 	bl	8 <correctstack>
/home/ubuntu/lunatik/lua/ldo.c:231
  L->stack_last.p = L->stack.p + newsize;
     688:	f9401a60 	ldr	x0, [x19, #48]
     68c:	8b35d000 	add	x0, x0, w21, sxtw #4
     690:	f9001660 	str	x0, [x19, #40]
/home/ubuntu/lunatik/lua/ldo.c:232
  for (i = oldsize + EXTRA_STACK; i < newsize + EXTRA_STACK; i++)
     694:	6b1b039f 	cmp	w28, w27
     698:	5400018a 	b.ge	6c8 <luaD_reallocstack+0x148>  // b.tcont
     69c:	510006a1 	sub	w1, w21, #0x1
     6a0:	8b140302 	add	x2, x24, x20
     6a4:	4b160021 	sub	w1, w1, w22
     6a8:	8b190021 	add	x1, x1, x25
     6ac:	91000421 	add	x1, x1, #0x1
     6b0:	8b011300 	add	x0, x24, x1, lsl #4
     6b4:	d503201f 	nop
/home/ubuntu/lunatik/lua/ldo.c:232 (discriminator 3)
     6b8:	91004042 	add	x2, x2, #0x10
/home/ubuntu/lunatik/lua/ldo.c:233 (discriminator 3)
    setnilvalue(s2v(newstack + i)); /* erase new segment */
     6bc:	381f805f 	sturb	wzr, [x2, #-8]
/home/ubuntu/lunatik/lua/ldo.c:232 (discriminator 3)
  for (i = oldsize + EXTRA_STACK; i < newsize + EXTRA_STACK; i++)
     6c0:	eb00005f 	cmp	x2, x0
     6c4:	54ffffa1 	b.ne	6b8 <luaD_reallocstack+0x138>  // b.any
/home/ubuntu/lunatik/lua/ldo.c:234
  return 1;
     6c8:	52800020 	mov	w0, #0x1                   	// #1
/home/ubuntu/lunatik/lua/ldo.c:235
}
     6cc:	f85f8e5e 	ldr	x30, [x18, #-8]!
     6d0:	a94153f3 	ldp	x19, x20, [sp, #16]
     6d4:	a9425bf5 	ldp	x21, x22, [sp, #32]
     6d8:	a94363f7 	ldp	x23, x24, [sp, #48]
     6dc:	a9446bf9 	ldp	x25, x26, [sp, #64]
     6e0:	a94573fb 	ldp	x27, x28, [sp, #80]
     6e4:	f84607fd 	ldr	x29, [sp], #96
     6e8:	d50323bf 	autiasp
     6ec:	d2800001 	mov	x1, #0x0                   	// #0
     6f0:	d2800002 	mov	x2, #0x0                   	// #0
     6f4:	d2800003 	mov	x3, #0x0                   	// #0
     6f8:	d2800004 	mov	x4, #0x0                   	// #0
     6fc:	d2800010 	mov	x16, #0x0                   	// #0
     700:	d2800011 	mov	x17, #0x0                   	// #0
     704:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:224
    correctstack(L);  /* change offsets back to pointers */
     708:	aa1303e0 	mov	x0, x19
     70c:	97fffe3f 	bl	8 <correctstack>
/home/ubuntu/lunatik/lua/ldo.c:227
    else return 0;  /* do not raise an error */
     710:	52800000 	mov	w0, #0x0                   	// #0
/home/ubuntu/lunatik/lua/ldo.c:225
    if (raiseerror)
     714:	34fffdd7 	cbz	w23, 6cc <luaD_reallocstack+0x14c>
/home/ubuntu/lunatik/lua/ldo.c:226
      luaM_error(L);
     718:	aa1303e0 	mov	x0, x19
     71c:	52800081 	mov	w1, #0x4                   	// #4
     720:	94000000 	bl	270 <luaD_throw>
			720: R_AARCH64_CALL26	luaD_throw
     724:	d503201f 	nop
     728:	d503201f 	nop
     72c:	d503201f 	nop

0000000000000730 <luaD_growstack>:
luaD_growstack():
/home/ubuntu/lunatik/lua/ldo.c:242
int luaD_growstack (lua_State *L, int n, int raiseerror) {
     730:	d503201f 	nop
     734:	d503201f 	nop
     738:	d503233f 	paciasp
     73c:	f800865e 	str	x30, [x18], #8
     740:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
/home/ubuntu/lunatik/lua/ldo.c:244
  if (l_unlikely(size > LUAI_MAXSTACK)) {
     744:	52884804 	mov	w4, #0x4240                	// #16960
     748:	72a001e4 	movk	w4, #0xf, lsl #16
/home/ubuntu/lunatik/lua/ldo.c:242
int luaD_growstack (lua_State *L, int n, int raiseerror) {
     74c:	910003fd 	mov	x29, sp
     750:	a90153f3 	stp	x19, x20, [sp, #16]
     754:	2a0203f4 	mov	w20, w2
/home/ubuntu/lunatik/lua/ldo.c:243
  int size = stacksize(L);
     758:	a9429803 	ldp	x3, x6, [x0, #40]
     75c:	cb060063 	sub	x3, x3, x6
     760:	9344fc63 	asr	x3, x3, #4
/home/ubuntu/lunatik/lua/ldo.c:244
  if (l_unlikely(size > LUAI_MAXSTACK)) {
     764:	6b04007f 	cmp	w3, w4
     768:	5400066c 	b.gt	834 <luaD_growstack+0x104>
/home/ubuntu/lunatik/lua/ldo.c:253
  else if (n < LUAI_MAXSTACK) {  /* avoids arithmetic overflows */
     76c:	528847e5 	mov	w5, #0x423f                	// #16959
     770:	aa0003f3 	mov	x19, x0
     774:	72a001e5 	movk	w5, #0xf, lsl #16
     778:	6b05003f 	cmp	w1, w5
     77c:	5400034c 	b.gt	7e4 <luaD_growstack+0xb4>
/home/ubuntu/lunatik/lua/ldo.c:255
    int needed = cast_int(L->top.p - L->stack.p) + n;
     780:	f9400805 	ldr	x5, [x0, #16]
/home/ubuntu/lunatik/lua/ldo.c:254
    int newsize = 2 * size;  /* tentative new size */
     784:	531f7863 	lsl	w3, w3, #1
/home/ubuntu/lunatik/lua/ldo.c:256
    if (newsize > LUAI_MAXSTACK)  /* cannot cross the limit */
     788:	6b04007f 	cmp	w3, w4
/home/ubuntu/lunatik/lua/ldo.c:255
    int needed = cast_int(L->top.p - L->stack.p) + n;
     78c:	cb0600a5 	sub	x5, x5, x6
/home/ubuntu/lunatik/lua/ldo.c:256
    if (newsize > LUAI_MAXSTACK)  /* cannot cross the limit */
     790:	1a84d063 	csel	w3, w3, w4, le
/home/ubuntu/lunatik/lua/ldo.c:255
    int needed = cast_int(L->top.p - L->stack.p) + n;
     794:	9344fca5 	asr	x5, x5, #4
     798:	0b050021 	add	w1, w1, w5
     79c:	6b03003f 	cmp	w1, w3
     7a0:	1a83a021 	csel	w1, w1, w3, ge  // ge = tcont
/home/ubuntu/lunatik/lua/ldo.c:260
    if (l_likely(newsize <= LUAI_MAXSTACK))
     7a4:	6b04003f 	cmp	w1, w4
     7a8:	540001ec 	b.gt	7e4 <luaD_growstack+0xb4>
/home/ubuntu/lunatik/lua/ldo.c:261
      return luaD_reallocstack(L, newsize, raiseerror);
     7ac:	94000000 	bl	580 <luaD_reallocstack>
			7ac: R_AARCH64_CALL26	luaD_reallocstack
/home/ubuntu/lunatik/lua/ldo.c:269
}
     7b0:	f85f8e5e 	ldr	x30, [x18, #-8]!
     7b4:	a94153f3 	ldp	x19, x20, [sp, #16]
     7b8:	f84207fd 	ldr	x29, [sp], #32
     7bc:	d50323bf 	autiasp
     7c0:	d2800001 	mov	x1, #0x0                   	// #0
     7c4:	d2800002 	mov	x2, #0x0                   	// #0
     7c8:	d2800003 	mov	x3, #0x0                   	// #0
     7cc:	d2800004 	mov	x4, #0x0                   	// #0
     7d0:	d2800005 	mov	x5, #0x0                   	// #0
     7d4:	d2800006 	mov	x6, #0x0                   	// #0
     7d8:	d2800010 	mov	x16, #0x0                   	// #0
     7dc:	d2800011 	mov	x17, #0x0                   	// #0
     7e0:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:265
  luaD_reallocstack(L, ERRORSTACKSIZE, raiseerror);
     7e4:	52886101 	mov	w1, #0x4308                	// #17160
     7e8:	2a1403e2 	mov	w2, w20
     7ec:	aa1303e0 	mov	x0, x19
     7f0:	72a001e1 	movk	w1, #0xf, lsl #16
     7f4:	94000000 	bl	580 <luaD_reallocstack>
			7f4: R_AARCH64_CALL26	luaD_reallocstack
/home/ubuntu/lunatik/lua/ldo.c:266
  if (raiseerror)
     7f8:	35000254 	cbnz	w20, 840 <luaD_growstack+0x110>
/home/ubuntu/lunatik/lua/ldo.c:269
}
     7fc:	f85f8e5e 	ldr	x30, [x18, #-8]!
/home/ubuntu/lunatik/lua/ldo.c:251
    return 0;  /* if not 'raiseerror', just signal it */
     800:	52800000 	mov	w0, #0x0                   	// #0
/home/ubuntu/lunatik/lua/ldo.c:269
}
     804:	a94153f3 	ldp	x19, x20, [sp, #16]
     808:	f84207fd 	ldr	x29, [sp], #32
     80c:	d50323bf 	autiasp
     810:	d2800001 	mov	x1, #0x0                   	// #0
     814:	d2800002 	mov	x2, #0x0                   	// #0
     818:	d2800003 	mov	x3, #0x0                   	// #0
     81c:	d2800004 	mov	x4, #0x0                   	// #0
     820:	d2800005 	mov	x5, #0x0                   	// #0
     824:	d2800006 	mov	x6, #0x0                   	// #0
     828:	d2800010 	mov	x16, #0x0                   	// #0
     82c:	d2800011 	mov	x17, #0x0                   	// #0
     830:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:249
    if (raiseerror)
     834:	34fffe42 	cbz	w2, 7fc <luaD_growstack+0xcc>
/home/ubuntu/lunatik/lua/ldo.c:250
      luaD_throw(L, LUA_ERRERR);  /* error inside message handler */
     838:	528000a1 	mov	w1, #0x5                   	// #5
     83c:	94000000 	bl	270 <luaD_throw>
			83c: R_AARCH64_CALL26	luaD_throw
/home/ubuntu/lunatik/lua/ldo.c:267
    luaG_runerror(L, "stack overflow");
     840:	90000001 	adrp	x1, 0 <correctstack-0x8>
			840: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.8+0x58
     844:	aa1303e0 	mov	x0, x19
     848:	91000021 	add	x1, x1, #0x0
			848: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.8+0x58
     84c:	94000000 	bl	0 <luaG_runerror>
			84c: R_AARCH64_CALL26	luaG_runerror
     850:	d503201f 	nop
     854:	d503201f 	nop

0000000000000858 <luaD_shrinkstack>:
luaD_shrinkstack():
/home/ubuntu/lunatik/lua/ldo.c:300
void luaD_shrinkstack (lua_State *L) {
     858:	d503201f 	nop
     85c:	d503201f 	nop
     860:	d503233f 	paciasp
     864:	f800865e 	str	x30, [x18], #8
     868:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
     86c:	910003fd 	mov	x29, sp
     870:	f9000bf3 	str	x19, [sp, #16]
     874:	aa0003f3 	mov	x19, x0
stackinuse():
/home/ubuntu/lunatik/lua/ldo.c:280
  for (ci = L->ci; ci != NULL; ci = ci->previous) {
     878:	f9401002 	ldr	x2, [x0, #32]
/home/ubuntu/lunatik/lua/ldo.c:279
  StkId lim = L->top.p;
     87c:	f9400801 	ldr	x1, [x0, #16]
/home/ubuntu/lunatik/lua/ldo.c:280
  for (ci = L->ci; ci != NULL; ci = ci->previous) {
     880:	b40000c2 	cbz	x2, 898 <luaD_shrinkstack+0x40>
     884:	d503201f 	nop
     888:	a9408843 	ldp	x3, x2, [x2, #8]
     88c:	eb03003f 	cmp	x1, x3
     890:	9a832021 	csel	x1, x1, x3, cs  // cs = hs, nlast
     894:	b5ffffa2 	cbnz	x2, 888 <luaD_shrinkstack+0x30>
/home/ubuntu/lunatik/lua/ldo.c:284
  res = cast_int(lim - L->stack.p) + 1;  /* part of stack in use */
     898:	f9401a63 	ldr	x3, [x19, #48]
/home/ubuntu/lunatik/lua/ldo.c:285
  if (res < LUA_MINSTACK)
     89c:	52800280 	mov	w0, #0x14                  	// #20
luaD_shrinkstack():
/home/ubuntu/lunatik/lua/ldo.c:302
  int max = (inuse > LUAI_MAXSTACK / 3) ? LUAI_MAXSTACK : inuse * 3;
     8a0:	5282c2a2 	mov	w2, #0x1615                	// #5653
stackinuse():
/home/ubuntu/lunatik/lua/ldo.c:284
  res = cast_int(lim - L->stack.p) + 1;  /* part of stack in use */
     8a4:	cb030021 	sub	x1, x1, x3
luaD_shrinkstack():
/home/ubuntu/lunatik/lua/ldo.c:302
  int max = (inuse > LUAI_MAXSTACK / 3) ? LUAI_MAXSTACK : inuse * 3;
     8a8:	72a000a2 	movk	w2, #0x5, lsl #16
stackinuse():
/home/ubuntu/lunatik/lua/ldo.c:284
  res = cast_int(lim - L->stack.p) + 1;  /* part of stack in use */
     8ac:	9344fc21 	asr	x1, x1, #4
     8b0:	11000421 	add	w1, w1, #0x1
/home/ubuntu/lunatik/lua/ldo.c:285
  if (res < LUA_MINSTACK)
     8b4:	6b00003f 	cmp	w1, w0
     8b8:	1a80a020 	csel	w0, w1, w0, ge  // ge = tcont
luaD_shrinkstack():
/home/ubuntu/lunatik/lua/ldo.c:302
  int max = (inuse > LUAI_MAXSTACK / 3) ? LUAI_MAXSTACK : inuse * 3;
     8bc:	6b02003f 	cmp	w1, w2
     8c0:	5400032c 	b.gt	924 <luaD_shrinkstack+0xcc>
/home/ubuntu/lunatik/lua/ldo.c:305
  if (inuse <= LUAI_MAXSTACK && stacksize(L) > max) {
     8c4:	f9401662 	ldr	x2, [x19, #40]
/home/ubuntu/lunatik/lua/ldo.c:302
  int max = (inuse > LUAI_MAXSTACK / 3) ? LUAI_MAXSTACK : inuse * 3;
     8c8:	531f7801 	lsl	w1, w0, #1
     8cc:	0b000020 	add	w0, w1, w0
/home/ubuntu/lunatik/lua/ldo.c:305
  if (inuse <= LUAI_MAXSTACK && stacksize(L) > max) {
     8d0:	cb030042 	sub	x2, x2, x3
     8d4:	9344fc42 	asr	x2, x2, #4
     8d8:	6b02001f 	cmp	w0, w2
     8dc:	5400008a 	b.ge	8ec <luaD_shrinkstack+0x94>  // b.tcont
/home/ubuntu/lunatik/lua/ldo.c:307 (discriminator 4)
    luaD_reallocstack(L, nsize, 0);  /* ok if that fails */
     8e0:	aa1303e0 	mov	x0, x19
     8e4:	52800002 	mov	w2, #0x0                   	// #0
     8e8:	94000000 	bl	580 <luaD_reallocstack>
			8e8: R_AARCH64_CALL26	luaD_reallocstack
/home/ubuntu/lunatik/lua/ldo.c:311
  luaE_shrinkCI(L);  /* shrink CI list */
     8ec:	aa1303e0 	mov	x0, x19
     8f0:	94000000 	bl	0 <luaE_shrinkCI>
			8f0: R_AARCH64_CALL26	luaE_shrinkCI
/home/ubuntu/lunatik/lua/ldo.c:312
}
     8f4:	f85f8e5e 	ldr	x30, [x18, #-8]!
     8f8:	f9400bf3 	ldr	x19, [sp, #16]
     8fc:	f84207fd 	ldr	x29, [sp], #32
     900:	d50323bf 	autiasp
     904:	d2800000 	mov	x0, #0x0                   	// #0
     908:	d2800001 	mov	x1, #0x0                   	// #0
     90c:	d2800002 	mov	x2, #0x0                   	// #0
     910:	d2800003 	mov	x3, #0x0                   	// #0
     914:	d2800004 	mov	x4, #0x0                   	// #0
     918:	d2800010 	mov	x16, #0x0                   	// #0
     91c:	d2800011 	mov	x17, #0x0                   	// #0
     920:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:305 (discriminator 4)
  if (inuse <= LUAI_MAXSTACK && stacksize(L) > max) {
     924:	52884802 	mov	w2, #0x4240                	// #16960
     928:	72a001e2 	movk	w2, #0xf, lsl #16
     92c:	6b02003f 	cmp	w1, w2
     930:	54fffdec 	b.gt	8ec <luaD_shrinkstack+0x94>
/home/ubuntu/lunatik/lua/ldo.c:305 (discriminator 1)
     934:	f9401664 	ldr	x4, [x19, #40]
     938:	cb030083 	sub	x3, x4, x3
     93c:	9344fc63 	asr	x3, x3, #4
     940:	6b02007f 	cmp	w3, w2
     944:	54fffd4d 	b.le	8ec <luaD_shrinkstack+0x94>
/home/ubuntu/lunatik/lua/ldo.c:306
    int nsize = (inuse > LUAI_MAXSTACK / 2) ? LUAI_MAXSTACK : inuse * 2;
     948:	52942403 	mov	w3, #0xa120                	// #41248
     94c:	72a000e3 	movk	w3, #0x7, lsl #16
     950:	6b03003f 	cmp	w1, w3
     954:	5400006c 	b.gt	960 <luaD_shrinkstack+0x108>
     958:	531f7801 	lsl	w1, w0, #1
     95c:	17ffffe1 	b	8e0 <luaD_shrinkstack+0x88>
     960:	2a0203e1 	mov	w1, w2
     964:	17ffffdf 	b	8e0 <luaD_shrinkstack+0x88>
     968:	d503201f 	nop
     96c:	d503201f 	nop

0000000000000970 <luaD_inctop>:
luaD_inctop():
/home/ubuntu/lunatik/lua/ldo.c:315
void luaD_inctop (lua_State *L) {
     970:	d503201f 	nop
     974:	d503201f 	nop
     978:	d503233f 	paciasp
     97c:	f800865e 	str	x30, [x18], #8
     980:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
     984:	910003fd 	mov	x29, sp
     988:	f9000bf3 	str	x19, [sp, #16]
     98c:	aa0003f3 	mov	x19, x0
/home/ubuntu/lunatik/lua/ldo.c:316
  luaD_checkstack(L, 1);
     990:	f9400801 	ldr	x1, [x0, #16]
     994:	f9401402 	ldr	x2, [x0, #40]
     998:	cb010042 	sub	x2, x2, x1
     99c:	f100405f 	cmp	x2, #0x10
     9a0:	540001ad 	b.le	9d4 <luaD_inctop+0x64>
/home/ubuntu/lunatik/lua/ldo.c:317 (discriminator 3)
  L->top.p++;
     9a4:	91004021 	add	x1, x1, #0x10
     9a8:	f9000a61 	str	x1, [x19, #16]
/home/ubuntu/lunatik/lua/ldo.c:318 (discriminator 3)
}
     9ac:	f85f8e5e 	ldr	x30, [x18, #-8]!
     9b0:	f9400bf3 	ldr	x19, [sp, #16]
     9b4:	f84207fd 	ldr	x29, [sp], #32
     9b8:	d50323bf 	autiasp
     9bc:	d2800000 	mov	x0, #0x0                   	// #0
     9c0:	d2800001 	mov	x1, #0x0                   	// #0
     9c4:	d2800002 	mov	x2, #0x0                   	// #0
     9c8:	d2800010 	mov	x16, #0x0                   	// #0
     9cc:	d2800011 	mov	x17, #0x0                   	// #0
     9d0:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:316 (discriminator 1)
  luaD_checkstack(L, 1);
     9d4:	52800022 	mov	w2, #0x1                   	// #1
     9d8:	2a0203e1 	mov	w1, w2
     9dc:	94000000 	bl	730 <luaD_growstack>
			9dc: R_AARCH64_CALL26	luaD_growstack
/home/ubuntu/lunatik/lua/ldo.c:317 (discriminator 1)
  L->top.p++;
     9e0:	f9400a61 	ldr	x1, [x19, #16]
     9e4:	91004021 	add	x1, x1, #0x10
     9e8:	f9000a61 	str	x1, [x19, #16]
/home/ubuntu/lunatik/lua/ldo.c:318 (discriminator 1)
}
     9ec:	f85f8e5e 	ldr	x30, [x18, #-8]!
     9f0:	f9400bf3 	ldr	x19, [sp, #16]
     9f4:	f84207fd 	ldr	x29, [sp], #32
     9f8:	d50323bf 	autiasp
     9fc:	d2800000 	mov	x0, #0x0                   	// #0
     a00:	d2800001 	mov	x1, #0x0                   	// #0
     a04:	d2800002 	mov	x2, #0x0                   	// #0
     a08:	d2800010 	mov	x16, #0x0                   	// #0
     a0c:	d2800011 	mov	x17, #0x0                   	// #0
     a10:	d65f03c0 	ret
     a14:	d503201f 	nop
     a18:	d503201f 	nop
     a1c:	d503201f 	nop

0000000000000a20 <luaD_hook>:
luaD_hook():
/home/ubuntu/lunatik/lua/ldo.c:329
                              int ftransfer, int ntransfer) {
     a20:	d503201f 	nop
     a24:	d503201f 	nop
     a28:	d503233f 	paciasp
     a2c:	f800865e 	str	x30, [x18], #8
     a30:	a9b17bfd 	stp	x29, x30, [sp, #-240]!
     a34:	d5384105 	mrs	x5, sp_el0
     a38:	910003fd 	mov	x29, sp
     a3c:	a90153f3 	stp	x19, x20, [sp, #16]
     a40:	aa0003f3 	mov	x19, x0
     a44:	a90573fb 	stp	x27, x28, [sp, #80]
     a48:	f94300a0 	ldr	x0, [x5, #1536]
     a4c:	f90077e0 	str	x0, [sp, #232]
     a50:	d2800000 	mov	x0, #0x0                   	// #0
/home/ubuntu/lunatik/lua/ldo.c:330
  lua_Hook hook = L->hook;
     a54:	f940527c 	ldr	x28, [x19, #160]
/home/ubuntu/lunatik/lua/ldo.c:331
  if (hook && L->allowhook) {  /* make sure there is a hook */
     a58:	b400007c 	cbz	x28, a64 <luaD_hook+0x44>
/home/ubuntu/lunatik/lua/ldo.c:331 (discriminator 1)
     a5c:	39402e60 	ldrb	w0, [x19, #11]
     a60:	350002a0 	cbnz	w0, ab4 <luaD_hook+0x94>
/home/ubuntu/lunatik/lua/ldo.c:361
}
     a64:	d5384100 	mrs	x0, sp_el0
     a68:	f94077e2 	ldr	x2, [sp, #232]
     a6c:	f9430001 	ldr	x1, [x0, #1536]
     a70:	eb010042 	subs	x2, x2, x1
     a74:	d2800001 	mov	x1, #0x0                   	// #0
     a78:	54000b01 	b.ne	bd8 <luaD_hook+0x1b8>  // b.any
     a7c:	a94153f3 	ldp	x19, x20, [sp, #16]
     a80:	a94573fb 	ldp	x27, x28, [sp, #80]
     a84:	f85f8e5e 	ldr	x30, [x18, #-8]!
     a88:	f84f07fd 	ldr	x29, [sp], #240
     a8c:	d50323bf 	autiasp
     a90:	d2800000 	mov	x0, #0x0                   	// #0
     a94:	d2800001 	mov	x1, #0x0                   	// #0
     a98:	d2800002 	mov	x2, #0x0                   	// #0
     a9c:	d2800003 	mov	x3, #0x0                   	// #0
     aa0:	d2800004 	mov	x4, #0x0                   	// #0
     aa4:	d2800005 	mov	x5, #0x0                   	// #0
     aa8:	d2800010 	mov	x16, #0x0                   	// #0
     aac:	d2800011 	mov	x17, #0x0                   	// #0
     ab0:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:333
    CallInfo *ci = L->ci;
     ab4:	a9025bf5 	stp	x21, x22, [sp, #32]
/home/ubuntu/lunatik/lua/ldo.c:336
    lua_Debug ar;
     ab8:	910183e0 	add	x0, sp, #0x60
     abc:	2a0203f6 	mov	w22, w2
     ac0:	a90363f7 	stp	x23, x24, [sp, #48]
     ac4:	2a0403f5 	mov	w21, w4
     ac8:	2a0103f7 	mov	w23, w1
     acc:	a9046bf9 	stp	x25, x26, [sp, #64]
     ad0:	2a0303f8 	mov	w24, w3
     ad4:	d2801102 	mov	x2, #0x88                  	// #136
/home/ubuntu/lunatik/lua/ldo.c:333
    CallInfo *ci = L->ci;
     ad8:	f9401274 	ldr	x20, [x19, #32]
/home/ubuntu/lunatik/lua/ldo.c:336
    lua_Debug ar;
     adc:	52800001 	mov	w1, #0x0                   	// #0
/home/ubuntu/lunatik/lua/ldo.c:334
    ptrdiff_t top = savestack(L, L->top.p);  /* preserve original 'top' */
     ae0:	f9400a79 	ldr	x25, [x19, #16]
/home/ubuntu/lunatik/lua/ldo.c:335
    ptrdiff_t ci_top = savestack(L, ci->top.p);  /* idem for 'ci->top' */
     ae4:	f940069b 	ldr	x27, [x20, #8]
/home/ubuntu/lunatik/lua/ldo.c:334
    ptrdiff_t top = savestack(L, L->top.p);  /* preserve original 'top' */
     ae8:	f9401a7a 	ldr	x26, [x19, #48]
/home/ubuntu/lunatik/lua/ldo.c:336
    lua_Debug ar;
     aec:	94000000 	bl	0 <memset>
			aec: R_AARCH64_CALL26	memset
/home/ubuntu/lunatik/lua/ldo.c:337
    ar.event = event;
     af0:	b90063f7 	str	w23, [sp, #96]
/home/ubuntu/lunatik/lua/ldo.c:338
    ar.currentline = line;
     af4:	b90093f6 	str	w22, [sp, #144]
/home/ubuntu/lunatik/lua/ldo.c:335
    ptrdiff_t ci_top = savestack(L, ci->top.p);  /* idem for 'ci->top' */
     af8:	cb1a037b 	sub	x27, x27, x26
/home/ubuntu/lunatik/lua/ldo.c:339
    ar.i_ci = ci;
     afc:	f90073f4 	str	x20, [sp, #224]
/home/ubuntu/lunatik/lua/ldo.c:334
    ptrdiff_t top = savestack(L, L->top.p);  /* preserve original 'top' */
     b00:	cb1a033a 	sub	x26, x25, x26
/home/ubuntu/lunatik/lua/ldo.c:340
    if (ntransfer != 0) {
     b04:	35000535 	cbnz	w21, ba8 <luaD_hook+0x188>
     b08:	529ffef6 	mov	w22, #0xfff7                	// #65527
     b0c:	52800115 	mov	w21, #0x8                   	// #8
/home/ubuntu/lunatik/lua/ldo.c:345
    if (isLua(ci) && L->top.p < ci->top.p)
     b10:	79407e80 	ldrh	w0, [x20, #62]
     b14:	370800c0 	tbnz	w0, #1, b2c <luaD_hook+0x10c>
/home/ubuntu/lunatik/lua/ldo.c:345 (discriminator 1)
     b18:	f9400680 	ldr	x0, [x20, #8]
     b1c:	eb19001f 	cmp	x0, x25
     b20:	54000069 	b.ls	b2c <luaD_hook+0x10c>  // b.plast
/home/ubuntu/lunatik/lua/ldo.c:346
      L->top.p = ci->top.p;  /* protect entire activation register */
     b24:	aa0003f9 	mov	x25, x0
     b28:	f9000a60 	str	x0, [x19, #16]
/home/ubuntu/lunatik/lua/ldo.c:347
    luaD_checkstack(L, LUA_MINSTACK);  /* ensure minimum stack size */
     b2c:	f9401660 	ldr	x0, [x19, #40]
     b30:	cb190000 	sub	x0, x0, x25
     b34:	f105001f 	cmp	x0, #0x140
     b38:	5400044d 	b.le	bc0 <luaD_hook+0x1a0>
/home/ubuntu/lunatik/lua/ldo.c:348 (discriminator 3)
    if (ci->top.p < L->top.p + LUA_MINSTACK)
     b3c:	f9400680 	ldr	x0, [x20, #8]
     b40:	91050339 	add	x25, x25, #0x140
     b44:	eb19001f 	cmp	x0, x25
     b48:	54000042 	b.cs	b50 <luaD_hook+0x130>  // b.hs, b.nlast
/home/ubuntu/lunatik/lua/ldo.c:349
      ci->top.p = L->top.p + LUA_MINSTACK;
     b4c:	f9000699 	str	x25, [x20, #8]
/home/ubuntu/lunatik/lua/ldo.c:350
    L->allowhook = 0;  /* cannot call hooks inside a hook */
     b50:	39002e7f 	strb	wzr, [x19, #11]
/home/ubuntu/lunatik/lua/ldo.c:353
    (*hook)(L, &ar);
     b54:	910183e1 	add	x1, sp, #0x60
     b58:	aa1303e0 	mov	x0, x19
/home/ubuntu/lunatik/lua/ldo.c:351
    ci->callstatus |= mask;
     b5c:	79407e82 	ldrh	w2, [x20, #62]
     b60:	2a0202b5 	orr	w21, w21, w2
     b64:	79007e95 	strh	w21, [x20, #62]
/home/ubuntu/lunatik/lua/ldo.c:353
    (*hook)(L, &ar);
     b68:	d63f0380 	blr	x28
/home/ubuntu/lunatik/lua/ldo.c:357
    ci->top.p = restorestack(L, ci_top);
     b6c:	f9401a60 	ldr	x0, [x19, #48]
/home/ubuntu/lunatik/lua/ldo.c:356
    L->allowhook = 1;
     b70:	52800021 	mov	w1, #0x1                   	// #1
     b74:	39002e61 	strb	w1, [x19, #11]
/home/ubuntu/lunatik/lua/ldo.c:357
    ci->top.p = restorestack(L, ci_top);
     b78:	8b1b0000 	add	x0, x0, x27
     b7c:	f9000680 	str	x0, [x20, #8]
/home/ubuntu/lunatik/lua/ldo.c:358
    L->top.p = restorestack(L, top);
     b80:	f9401a60 	ldr	x0, [x19, #48]
     b84:	8b1a0000 	add	x0, x0, x26
     b88:	f9000a60 	str	x0, [x19, #16]
/home/ubuntu/lunatik/lua/ldo.c:359
    ci->callstatus &= ~mask;
     b8c:	79407e80 	ldrh	w0, [x20, #62]
     b90:	0a0002d6 	and	w22, w22, w0
     b94:	79007e96 	strh	w22, [x20, #62]
     b98:	a9425bf5 	ldp	x21, x22, [sp, #32]
     b9c:	a94363f7 	ldp	x23, x24, [sp, #48]
     ba0:	a9446bf9 	ldp	x25, x26, [sp, #64]
/home/ubuntu/lunatik/lua/ldo.c:361
}
     ba4:	17ffffb0 	b	a64 <luaD_hook+0x44>
/home/ubuntu/lunatik/lua/ldo.c:342
      ci->u2.transferinfo.ftransfer = ftransfer;
     ba8:	79007298 	strh	w24, [x20, #56]
/home/ubuntu/lunatik/lua/ldo.c:345
    if (isLua(ci) && L->top.p < ci->top.p)
     bac:	529fdef6 	mov	w22, #0xfef7                	// #65271
/home/ubuntu/lunatik/lua/ldo.c:343
      ci->u2.transferinfo.ntransfer = ntransfer;
     bb0:	79007695 	strh	w21, [x20, #58]
/home/ubuntu/lunatik/lua/ldo.c:345
    if (isLua(ci) && L->top.p < ci->top.p)
     bb4:	52802115 	mov	w21, #0x108                 	// #264
     bb8:	f9400a79 	ldr	x25, [x19, #16]
     bbc:	17ffffd5 	b	b10 <luaD_hook+0xf0>
/home/ubuntu/lunatik/lua/ldo.c:347 (discriminator 1)
    luaD_checkstack(L, LUA_MINSTACK);  /* ensure minimum stack size */
     bc0:	aa1303e0 	mov	x0, x19
     bc4:	52800022 	mov	w2, #0x1                   	// #1
     bc8:	52800281 	mov	w1, #0x14                  	// #20
     bcc:	94000000 	bl	730 <luaD_growstack>
			bcc: R_AARCH64_CALL26	luaD_growstack
/home/ubuntu/lunatik/lua/ldo.c:348 (discriminator 1)
    if (ci->top.p < L->top.p + LUA_MINSTACK)
     bd0:	f9400a79 	ldr	x25, [x19, #16]
     bd4:	17ffffda 	b	b3c <luaD_hook+0x11c>
     bd8:	a9025bf5 	stp	x21, x22, [sp, #32]
     bdc:	a90363f7 	stp	x23, x24, [sp, #48]
     be0:	a9046bf9 	stp	x25, x26, [sp, #64]
/home/ubuntu/lunatik/lua/ldo.c:361
}
     be4:	94000000 	bl	0 <__stack_chk_fail>
			be4: R_AARCH64_CALL26	__stack_chk_fail
     be8:	d503201f 	nop
     bec:	d503201f 	nop

0000000000000bf0 <rethook>:
rethook():
/home/ubuntu/lunatik/lua/ldo.c:387
static void rethook (lua_State *L, CallInfo *ci, int nres) {
     bf0:	d503201f 	nop
     bf4:	d503201f 	nop
     bf8:	d503233f 	paciasp
     bfc:	f800865e 	str	x30, [x18], #8
     c00:	a9bd7bfd 	stp	x29, x30, [sp, #-48]!
     c04:	910003fd 	mov	x29, sp
     c08:	a90153f3 	stp	x19, x20, [sp, #16]
     c0c:	aa0003f4 	mov	x20, x0
     c10:	aa0103f3 	mov	x19, x1
/home/ubuntu/lunatik/lua/ldo.c:388
  if (L->hookmask & LUA_MASKRET) {  /* is return hook on? */
     c14:	b940c000 	ldr	w0, [x0, #192]
     c18:	36080280 	tbz	w0, #1, c68 <rethook+0x78>
/home/ubuntu/lunatik/lua/ldo.c:389
    StkId firstres = L->top.p - nres;  /* index of first result */
     c1c:	f90013f5 	str	x21, [sp, #32]
     c20:	d2800015 	mov	x21, #0x0                   	// #0
     c24:	f9400a83 	ldr	x3, [x20, #16]
/home/ubuntu/lunatik/lua/ldo.c:392
    if (isLua(ci)) {
     c28:	79407c21 	ldrh	w1, [x1, #62]
/home/ubuntu/lunatik/lua/ldo.c:393
      Proto *p = ci_func(ci)->p;
     c2c:	f9400260 	ldr	x0, [x19]
/home/ubuntu/lunatik/lua/ldo.c:389
    StkId firstres = L->top.p - nres;  /* index of first result */
     c30:	cb22d063 	sub	x3, x3, w2, sxtw #4
/home/ubuntu/lunatik/lua/ldo.c:392
    if (isLua(ci)) {
     c34:	360804a1 	tbz	w1, #1, cc8 <rethook+0xd8>
/home/ubuntu/lunatik/lua/ldo.c:398
    ftransfer = cast(unsigned short, firstres - ci->func.p);
     c38:	cb000063 	sub	x3, x3, x0
/home/ubuntu/lunatik/lua/ldo.c:397
    ci->func.p += delta;  /* if vararg, back to virtual 'func' */
     c3c:	f9000260 	str	x0, [x19]
/home/ubuntu/lunatik/lua/ldo.c:399
    luaD_hook(L, LUA_HOOKRET, -1, ftransfer, nres);  /* call it */
     c40:	2a0203e4 	mov	w4, w2
     c44:	aa1403e0 	mov	x0, x20
     c48:	53044c63 	ubfx	w3, w3, #4, #16
     c4c:	12800002 	mov	w2, #0xffffffff            	// #-1
     c50:	52800021 	mov	w1, #0x1                   	// #1
     c54:	94000000 	bl	a20 <luaD_hook>
			c54: R_AARCH64_CALL26	luaD_hook
/home/ubuntu/lunatik/lua/ldo.c:400
    ci->func.p -= delta;
     c58:	f9400260 	ldr	x0, [x19]
     c5c:	8b150000 	add	x0, x0, x21
     c60:	f9000260 	str	x0, [x19]
     c64:	f94013f5 	ldr	x21, [sp, #32]
/home/ubuntu/lunatik/lua/ldo.c:402
  if (isLua(ci = ci->previous))
     c68:	f9400a60 	ldr	x0, [x19, #16]
     c6c:	79407c01 	ldrh	w1, [x0, #62]
     c70:	37080141 	tbnz	w1, #1, c98 <rethook+0xa8>
/home/ubuntu/lunatik/lua/ldo.c:403
    L->oldpc = pcRel(ci->u.l.savedpc, ci_func(ci)->p);  /* set 'oldpc' */
     c74:	f9400001 	ldr	x1, [x0]
     c78:	f9401000 	ldr	x0, [x0, #32]
     c7c:	f9400021 	ldr	x1, [x1]
     c80:	f9400c21 	ldr	x1, [x1, #24]
     c84:	f9402021 	ldr	x1, [x1, #64]
     c88:	cb010000 	sub	x0, x0, x1
     c8c:	9342fc00 	asr	x0, x0, #2
     c90:	51000400 	sub	w0, w0, #0x1
     c94:	b900b680 	str	w0, [x20, #180]
/home/ubuntu/lunatik/lua/ldo.c:404
}
     c98:	f85f8e5e 	ldr	x30, [x18, #-8]!
     c9c:	a94153f3 	ldp	x19, x20, [sp, #16]
     ca0:	f84307fd 	ldr	x29, [sp], #48
     ca4:	d50323bf 	autiasp
     ca8:	d2800000 	mov	x0, #0x0                   	// #0
     cac:	d2800001 	mov	x1, #0x0                   	// #0
     cb0:	d2800002 	mov	x2, #0x0                   	// #0
     cb4:	d2800003 	mov	x3, #0x0                   	// #0
     cb8:	d2800004 	mov	x4, #0x0                   	// #0
     cbc:	d2800010 	mov	x16, #0x0                   	// #0
     cc0:	d2800011 	mov	x17, #0x0                   	// #0
     cc4:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:393
      Proto *p = ci_func(ci)->p;
     cc8:	f9400001 	ldr	x1, [x0]
     ccc:	f9400c21 	ldr	x1, [x1, #24]
/home/ubuntu/lunatik/lua/ldo.c:394
      if (p->is_vararg)
     cd0:	39402c24 	ldrb	w4, [x1, #11]
     cd4:	34fffb24 	cbz	w4, c38 <rethook+0x48>
/home/ubuntu/lunatik/lua/ldo.c:395
        delta = ci->u.l.nextraargs + p->numparams + 1;
     cd8:	b9402e75 	ldr	w21, [x19, #44]
     cdc:	39402821 	ldrb	w1, [x1, #10]
     ce0:	110006b5 	add	w21, w21, #0x1
     ce4:	0b0102b5 	add	w21, w21, w1
/home/ubuntu/lunatik/lua/ldo.c:397
    ci->func.p += delta;  /* if vararg, back to virtual 'func' */
     ce8:	937c7eb5 	sbfiz	x21, x21, #4, #32
     cec:	8b150000 	add	x0, x0, x21
/home/ubuntu/lunatik/lua/ldo.c:400
    ci->func.p -= delta;
     cf0:	cb1503f5 	neg	x21, x21
     cf4:	17ffffd1 	b	c38 <rethook+0x48>
     cf8:	d503201f 	nop
     cfc:	d503201f 	nop

0000000000000d00 <luaD_hookcall>:
luaD_hookcall():
/home/ubuntu/lunatik/lua/ldo.c:369
void luaD_hookcall (lua_State *L, CallInfo *ci) {
     d00:	d503201f 	nop
     d04:	d503201f 	nop
     d08:	d503233f 	paciasp
     d0c:	f800865e 	str	x30, [x18], #8
     d10:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
     d14:	910003fd 	mov	x29, sp
     d18:	f9000bf3 	str	x19, [sp, #16]
     d1c:	aa0103f3 	mov	x19, x1
/home/ubuntu/lunatik/lua/ldo.c:370
  L->oldpc = 0;  /* set 'oldpc' for new function */
     d20:	b900b41f 	str	wzr, [x0, #180]
/home/ubuntu/lunatik/lua/ldo.c:371
  if (L->hookmask & LUA_MASKCALL) {  /* is call hook on? */
     d24:	b940c001 	ldr	w1, [x0, #192]
     d28:	370001c1 	tbnz	w1, #0, d60 <luaD_hookcall+0x60>
/home/ubuntu/lunatik/lua/ldo.c:379
}
     d2c:	f85f8e5e 	ldr	x30, [x18, #-8]!
     d30:	f9400bf3 	ldr	x19, [sp, #16]
     d34:	f84207fd 	ldr	x29, [sp], #32
     d38:	d50323bf 	autiasp
     d3c:	d2800000 	mov	x0, #0x0                   	// #0
     d40:	d2800001 	mov	x1, #0x0                   	// #0
     d44:	d2800002 	mov	x2, #0x0                   	// #0
     d48:	d2800003 	mov	x3, #0x0                   	// #0
     d4c:	d2800004 	mov	x4, #0x0                   	// #0
     d50:	d2800005 	mov	x5, #0x0                   	// #0
     d54:	d2800010 	mov	x16, #0x0                   	// #0
     d58:	d2800011 	mov	x17, #0x0                   	// #0
     d5c:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:374
    Proto *p = ci_func(ci)->p;
     d60:	f9400261 	ldr	x1, [x19]
/home/ubuntu/lunatik/lua/ldo.c:376
    luaD_hook(L, event, -1, 1, p->numparams);
     d64:	52800023 	mov	w3, #0x1                   	// #1
/home/ubuntu/lunatik/lua/ldo.c:375
    ci->u.l.savedpc++;  /* hooks assume 'pc' is already incremented */
     d68:	f9401264 	ldr	x4, [x19, #32]
/home/ubuntu/lunatik/lua/ldo.c:376
    luaD_hook(L, event, -1, 1, p->numparams);
     d6c:	12800002 	mov	w2, #0xffffffff            	// #-1
/home/ubuntu/lunatik/lua/ldo.c:374
    Proto *p = ci_func(ci)->p;
     d70:	f9400025 	ldr	x5, [x1]
/home/ubuntu/lunatik/lua/ldo.c:375
    ci->u.l.savedpc++;  /* hooks assume 'pc' is already incremented */
     d74:	91001084 	add	x4, x4, #0x4
/home/ubuntu/lunatik/lua/ldo.c:373
                                             : LUA_HOOKCALL;
     d78:	79407e61 	ldrh	w1, [x19, #62]
/home/ubuntu/lunatik/lua/ldo.c:374
    Proto *p = ci_func(ci)->p;
     d7c:	f9400ca5 	ldr	x5, [x5, #24]
/home/ubuntu/lunatik/lua/ldo.c:375
    ci->u.l.savedpc++;  /* hooks assume 'pc' is already incremented */
     d80:	f9001264 	str	x4, [x19, #32]
/home/ubuntu/lunatik/lua/ldo.c:373
                                             : LUA_HOOKCALL;
     d84:	13037c21 	asr	w1, w1, #3
/home/ubuntu/lunatik/lua/ldo.c:376
    luaD_hook(L, event, -1, 1, p->numparams);
     d88:	121e0021 	and	w1, w1, #0x4
     d8c:	394028a4 	ldrb	w4, [x5, #10]
     d90:	94000000 	bl	a20 <luaD_hook>
			d90: R_AARCH64_CALL26	luaD_hook
/home/ubuntu/lunatik/lua/ldo.c:377
    ci->u.l.savedpc--;  /* correct 'pc' */
     d94:	f9401260 	ldr	x0, [x19, #32]
     d98:	d1001000 	sub	x0, x0, #0x4
     d9c:	f9001260 	str	x0, [x19, #32]
/home/ubuntu/lunatik/lua/ldo.c:379
}
     da0:	f85f8e5e 	ldr	x30, [x18, #-8]!
     da4:	f9400bf3 	ldr	x19, [sp, #16]
     da8:	f84207fd 	ldr	x29, [sp], #32
     dac:	d50323bf 	autiasp
     db0:	d2800000 	mov	x0, #0x0                   	// #0
     db4:	d2800001 	mov	x1, #0x0                   	// #0
     db8:	d2800002 	mov	x2, #0x0                   	// #0
     dbc:	d2800003 	mov	x3, #0x0                   	// #0
     dc0:	d2800004 	mov	x4, #0x0                   	// #0
     dc4:	d2800005 	mov	x5, #0x0                   	// #0
     dc8:	d2800010 	mov	x16, #0x0                   	// #0
     dcc:	d2800011 	mov	x17, #0x0                   	// #0
     dd0:	d65f03c0 	ret
     dd4:	d503201f 	nop
     dd8:	d503201f 	nop
     ddc:	d503201f 	nop

0000000000000de0 <luaD_tryfuncTM>:
luaD_tryfuncTM():
/home/ubuntu/lunatik/lua/ldo.c:412
StkId luaD_tryfuncTM (lua_State *L, StkId func) {
     de0:	d503201f 	nop
     de4:	d503201f 	nop
     de8:	d503233f 	paciasp
     dec:	f800865e 	str	x30, [x18], #8
     df0:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
     df4:	910003fd 	mov	x29, sp
     df8:	a90153f3 	stp	x19, x20, [sp, #16]
     dfc:	aa0103f3 	mov	x19, x1
     e00:	aa0003f4 	mov	x20, x0
/home/ubuntu/lunatik/lua/ldo.c:415
  checkstackGCp(L, 1, func);  /* space for metamethod */
     e04:	f9400802 	ldr	x2, [x0, #16]
     e08:	f9401401 	ldr	x1, [x0, #40]
     e0c:	cb020021 	sub	x1, x1, x2
     e10:	f100403f 	cmp	x1, #0x10
     e14:	540004cd 	b.le	eac <luaD_tryfuncTM+0xcc>
/home/ubuntu/lunatik/lua/ldo.c:416 (discriminator 6)
  tm = luaT_gettmbyobj(L, s2v(func), TM_CALL);  /* (after previous GC) */
     e18:	aa1303e1 	mov	x1, x19
     e1c:	aa1403e0 	mov	x0, x20
     e20:	528002a2 	mov	w2, #0x15                  	// #21
     e24:	94000000 	bl	0 <luaT_gettmbyobj>
			e24: R_AARCH64_CALL26	luaT_gettmbyobj
     e28:	aa0003e3 	mov	x3, x0
/home/ubuntu/lunatik/lua/ldo.c:417 (discriminator 6)
  if (l_unlikely(ttisnil(tm)))
     e2c:	39402000 	ldrb	w0, [x0, #8]
     e30:	f2400c1f 	tst	x0, #0xf
     e34:	54000660 	b.eq	f00 <luaD_tryfuncTM+0x120>  // b.none
/home/ubuntu/lunatik/lua/ldo.c:419
  for (p = L->top.p; p > func; p--)  /* open space for metamethod */
     e38:	f9400a82 	ldr	x2, [x20, #16]
     e3c:	eb02027f 	cmp	x19, x2
     e40:	54000142 	b.cs	e68 <luaD_tryfuncTM+0x88>  // b.hs, b.nlast
     e44:	d503201f 	nop
/home/ubuntu/lunatik/lua/ldo.c:420 (discriminator 3)
    setobjs2s(L, p, p-1);
     e48:	f85f0041 	ldur	x1, [x2, #-16]
     e4c:	f9000041 	str	x1, [x2]
     e50:	385f8041 	ldurb	w1, [x2, #-8]
/home/ubuntu/lunatik/lua/ldo.c:419 (discriminator 3)
  for (p = L->top.p; p > func; p--)  /* open space for metamethod */
     e54:	d1004042 	sub	x2, x2, #0x10
/home/ubuntu/lunatik/lua/ldo.c:420 (discriminator 3)
    setobjs2s(L, p, p-1);
     e58:	39006041 	strb	w1, [x2, #24]
/home/ubuntu/lunatik/lua/ldo.c:419 (discriminator 3)
  for (p = L->top.p; p > func; p--)  /* open space for metamethod */
     e5c:	eb02027f 	cmp	x19, x2
     e60:	54ffff43 	b.cc	e48 <luaD_tryfuncTM+0x68>  // b.lo, b.ul, b.last
/home/ubuntu/lunatik/lua/ldo.c:421
  L->top.p++;  /* stack space pre-allocated by the caller */
     e64:	f9400a82 	ldr	x2, [x20, #16]
     e68:	91004042 	add	x2, x2, #0x10
     e6c:	f9000a82 	str	x2, [x20, #16]
/home/ubuntu/lunatik/lua/ldo.c:424
}
     e70:	aa1303e0 	mov	x0, x19
/home/ubuntu/lunatik/lua/ldo.c:422
  setobj2s(L, func, tm);  /* metamethod is the new function to be called */
     e74:	f9400061 	ldr	x1, [x3]
     e78:	f9000261 	str	x1, [x19]
     e7c:	39402061 	ldrb	w1, [x3, #8]
     e80:	39002261 	strb	w1, [x19, #8]
/home/ubuntu/lunatik/lua/ldo.c:424
}
     e84:	f85f8e5e 	ldr	x30, [x18, #-8]!
     e88:	a94153f3 	ldp	x19, x20, [sp, #16]
     e8c:	f84207fd 	ldr	x29, [sp], #32
     e90:	d50323bf 	autiasp
     e94:	d2800001 	mov	x1, #0x0                   	// #0
     e98:	d2800002 	mov	x2, #0x0                   	// #0
     e9c:	d2800003 	mov	x3, #0x0                   	// #0
     ea0:	d2800010 	mov	x16, #0x0                   	// #0
     ea4:	d2800011 	mov	x17, #0x0                   	// #0
     ea8:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:415 (discriminator 1)
  checkstackGCp(L, 1, func);  /* space for metamethod */
     eac:	f9400c01 	ldr	x1, [x0, #24]
     eb0:	f9401802 	ldr	x2, [x0, #48]
     eb4:	f9400c21 	ldr	x1, [x1, #24]
     eb8:	cb020273 	sub	x19, x19, x2
     ebc:	f100003f 	cmp	x1, #0x0
     ec0:	5400004d 	b.le	ec8 <luaD_tryfuncTM+0xe8>
/home/ubuntu/lunatik/lua/ldo.c:415 (discriminator 3)
     ec4:	94000000 	bl	0 <luaC_step>
			ec4: R_AARCH64_CALL26	luaC_step
/home/ubuntu/lunatik/lua/ldo.c:415 (discriminator 5)
     ec8:	52800022 	mov	w2, #0x1                   	// #1
     ecc:	aa1403e0 	mov	x0, x20
     ed0:	2a0203e1 	mov	w1, w2
     ed4:	94000000 	bl	730 <luaD_growstack>
			ed4: R_AARCH64_CALL26	luaD_growstack
     ed8:	f9401a80 	ldr	x0, [x20, #48]
/home/ubuntu/lunatik/lua/ldo.c:416 (discriminator 5)
  tm = luaT_gettmbyobj(L, s2v(func), TM_CALL);  /* (after previous GC) */
     edc:	528002a2 	mov	w2, #0x15                  	// #21
/home/ubuntu/lunatik/lua/ldo.c:415 (discriminator 5)
  checkstackGCp(L, 1, func);  /* space for metamethod */
     ee0:	8b130013 	add	x19, x0, x19
/home/ubuntu/lunatik/lua/ldo.c:416 (discriminator 5)
  tm = luaT_gettmbyobj(L, s2v(func), TM_CALL);  /* (after previous GC) */
     ee4:	aa1403e0 	mov	x0, x20
     ee8:	aa1303e1 	mov	x1, x19
     eec:	94000000 	bl	0 <luaT_gettmbyobj>
			eec: R_AARCH64_CALL26	luaT_gettmbyobj
     ef0:	aa0003e3 	mov	x3, x0
/home/ubuntu/lunatik/lua/ldo.c:417 (discriminator 5)
  if (l_unlikely(ttisnil(tm)))
     ef4:	39402000 	ldrb	w0, [x0, #8]
     ef8:	f2400c1f 	tst	x0, #0xf
     efc:	54fff9e1 	b.ne	e38 <luaD_tryfuncTM+0x58>  // b.any
/home/ubuntu/lunatik/lua/ldo.c:418
    luaG_callerror(L, s2v(func));  /* nothing to call */
     f00:	aa1303e1 	mov	x1, x19
     f04:	aa1403e0 	mov	x0, x20
     f08:	94000000 	bl	0 <luaG_callerror>
			f08: R_AARCH64_CALL26	luaG_callerror
     f0c:	d503201f 	nop
     f10:	d503201f 	nop
     f14:	d503201f 	nop

0000000000000f18 <luaD_poscall>:
luaD_poscall():
/home/ubuntu/lunatik/lua/ldo.c:485
void luaD_poscall (lua_State *L, CallInfo *ci, int nres) {
     f18:	d503201f 	nop
     f1c:	d503201f 	nop
     f20:	d503233f 	paciasp
     f24:	f800865e 	str	x30, [x18], #8
     f28:	a9bc7bfd 	stp	x29, x30, [sp, #-64]!
     f2c:	910003fd 	mov	x29, sp
     f30:	a90153f3 	stp	x19, x20, [sp, #16]
     f34:	aa0003f3 	mov	x19, x0
     f38:	a9025bf5 	stp	x21, x22, [sp, #32]
     f3c:	aa0103f5 	mov	x21, x1
     f40:	2a0203f6 	mov	w22, w2
/home/ubuntu/lunatik/lua/ldo.c:487
  if (l_unlikely(L->hookmask && !hastocloseCfunc(wanted)))
     f44:	b940c003 	ldr	w3, [x0, #192]
/home/ubuntu/lunatik/lua/ldo.c:486
  int wanted = ci->nresults;
     f48:	79c07834 	ldrsh	w20, [x1, #60]
/home/ubuntu/lunatik/lua/ldo.c:487
  if (l_unlikely(L->hookmask && !hastocloseCfunc(wanted)))
     f4c:	340007c3 	cbz	w3, 1044 <luaD_poscall+0x12c>
/home/ubuntu/lunatik/lua/ldo.c:487 (discriminator 1)
     f50:	3100069f 	cmn	w20, #0x1
     f54:	540009eb 	b.lt	1090 <luaD_poscall+0x178>  // b.tstop
/home/ubuntu/lunatik/lua/ldo.c:488
    rethook(L, ci, nres);
     f58:	97ffff26 	bl	bf0 <rethook>
/home/ubuntu/lunatik/lua/ldo.c:490
  moveresults(L, ci->func.p, nres, wanted);
     f5c:	f94002a3 	ldr	x3, [x21]
moveresults():
/home/ubuntu/lunatik/lua/ldo.c:436
  switch (wanted) {  /* handle typical cases separately */
     f60:	340004d4 	cbz	w20, ff8 <luaD_poscall+0xe0>
     f64:	7100069f 	cmp	w20, #0x1
     f68:	540008c0 	b.eq	1080 <luaD_poscall+0x168>  // b.none
     f6c:	3100069f 	cmn	w20, #0x1
     f70:	54000781 	b.ne	1060 <luaD_poscall+0x148>  // b.any
     f74:	d503201f 	nop
     f78:	2a1603e4 	mov	w4, w22
     f7c:	2a1603f4 	mov	w20, w22
/home/ubuntu/lunatik/lua/ldo.c:468
  firstresult = L->top.p - nres;  /* index of first result */
     f80:	f9400a61 	ldr	x1, [x19, #16]
     f84:	93407ec0 	sxtw	x0, w22
/home/ubuntu/lunatik/lua/ldo.c:471
  for (i = 0; i < nres; i++)  /* move all results to correct place */
     f88:	7100009f 	cmp	w4, #0x0
     f8c:	54000dcd 	b.le	1144 <luaD_poscall+0x22c>
     f90:	cb001020 	sub	x0, x1, x0, lsl #4
     f94:	937c7c87 	sbfiz	x7, x4, #4, #32
     f98:	91002006 	add	x6, x0, #0x8
     f9c:	91002061 	add	x1, x3, #0x8
     fa0:	d2800002 	mov	x2, #0x0                   	// #0
     fa4:	d503201f 	nop
/home/ubuntu/lunatik/lua/ldo.c:472
    setobjs2s(L, res + i, firstresult + i);
     fa8:	f8626805 	ldr	x5, [x0, x2]
     fac:	f8226865 	str	x5, [x3, x2]
     fb0:	386268c5 	ldrb	w5, [x6, x2]
     fb4:	38226825 	strb	w5, [x1, x2]
/home/ubuntu/lunatik/lua/ldo.c:471
  for (i = 0; i < nres; i++)  /* move all results to correct place */
     fb8:	91004042 	add	x2, x2, #0x10
     fbc:	eb07005f 	cmp	x2, x7
     fc0:	54ffff41 	b.ne	fa8 <luaD_poscall+0x90>  // b.any
/home/ubuntu/lunatik/lua/ldo.c:473
  for (; i < wanted; i++)  /* complete wanted number of results */
     fc4:	6b04029f 	cmp	w20, w4
     fc8:	5400016d 	b.le	ff4 <luaD_poscall+0xdc>
     fcc:	4b040280 	sub	w0, w20, w4
     fd0:	8b24d062 	add	x2, x3, w4, sxtw #4
     fd4:	8b24c004 	add	x4, x0, w4, sxtw
     fd8:	91002060 	add	x0, x3, #0x8
     fdc:	91002042 	add	x2, x2, #0x8
     fe0:	8b041004 	add	x4, x0, x4, lsl #4
     fe4:	d503201f 	nop
/home/ubuntu/lunatik/lua/ldo.c:474
    setnilvalue(s2v(res + i));
     fe8:	3801045f 	strb	wzr, [x2], #16
/home/ubuntu/lunatik/lua/ldo.c:473
  for (; i < wanted; i++)  /* complete wanted number of results */
     fec:	eb02009f 	cmp	x4, x2
     ff0:	54ffffc1 	b.ne	fe8 <luaD_poscall+0xd0>  // b.any
/home/ubuntu/lunatik/lua/ldo.c:475
  L->top.p = res + wanted;  /* top points after the last result */
     ff4:	8b34d063 	add	x3, x3, w20, sxtw #4
/home/ubuntu/lunatik/lua/ldo.c:438
      L->top.p = res;
     ff8:	f9000a63 	str	x3, [x19, #16]
luaD_poscall():
/home/ubuntu/lunatik/lua/ldo.c:494
  L->ci = ci->previous;  /* back to caller (after closing variables) */
     ffc:	f9400aa0 	ldr	x0, [x21, #16]
    1000:	f9001260 	str	x0, [x19, #32]
/home/ubuntu/lunatik/lua/ldo.c:495
}
    1004:	f85f8e5e 	ldr	x30, [x18, #-8]!
    1008:	a94153f3 	ldp	x19, x20, [sp, #16]
    100c:	a9425bf5 	ldp	x21, x22, [sp, #32]
    1010:	f84407fd 	ldr	x29, [sp], #64
    1014:	d50323bf 	autiasp
    1018:	d2800000 	mov	x0, #0x0                   	// #0
    101c:	d2800001 	mov	x1, #0x0                   	// #0
    1020:	d2800002 	mov	x2, #0x0                   	// #0
    1024:	d2800003 	mov	x3, #0x0                   	// #0
    1028:	d2800004 	mov	x4, #0x0                   	// #0
    102c:	d2800005 	mov	x5, #0x0                   	// #0
    1030:	d2800006 	mov	x6, #0x0                   	// #0
    1034:	d2800007 	mov	x7, #0x0                   	// #0
    1038:	d2800010 	mov	x16, #0x0                   	// #0
    103c:	d2800011 	mov	x17, #0x0                   	// #0
    1040:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:490
  moveresults(L, ci->func.p, nres, wanted);
    1044:	f9400023 	ldr	x3, [x1]
moveresults():
/home/ubuntu/lunatik/lua/ldo.c:436
  switch (wanted) {  /* handle typical cases separately */
    1048:	34fffd94 	cbz	w20, ff8 <luaD_poscall+0xe0>
    104c:	7100069f 	cmp	w20, #0x1
    1050:	54000180 	b.eq	1080 <luaD_poscall+0x168>  // b.none
    1054:	3100069f 	cmn	w20, #0x1
    1058:	54fff900 	b.eq	f78 <luaD_poscall+0x60>  // b.none
/home/ubuntu/lunatik/lua/ldo.c:451
      if (hastocloseCfunc(wanted)) {  /* to-be-closed variables? */
    105c:	540001cb 	b.lt	1094 <luaD_poscall+0x17c>  // b.tstop
    1060:	6b16029f 	cmp	w20, w22
/home/ubuntu/lunatik/lua/ldo.c:468
  firstresult = L->top.p - nres;  /* index of first result */
    1064:	93407ec0 	sxtw	x0, w22
    1068:	1a96d284 	csel	w4, w20, w22, le
    106c:	f9400a61 	ldr	x1, [x19, #16]
/home/ubuntu/lunatik/lua/ldo.c:471
  for (i = 0; i < nres; i++)  /* move all results to correct place */
    1070:	7100009f 	cmp	w4, #0x0
    1074:	54fff8ec 	b.gt	f90 <luaD_poscall+0x78>
    1078:	52800004 	mov	w4, #0x0                   	// #0
    107c:	17ffffd4 	b	fcc <luaD_poscall+0xb4>
/home/ubuntu/lunatik/lua/ldo.c:441
      if (nres == 0)   /* no results? */
    1080:	350003d6 	cbnz	w22, 10f8 <luaD_poscall+0x1e0>
/home/ubuntu/lunatik/lua/ldo.c:445
      L->top.p = res + 1;
    1084:	91004063 	add	x3, x3, #0x10
/home/ubuntu/lunatik/lua/ldo.c:442
        setnilvalue(s2v(res));  /* adjust with nil */
    1088:	381f807f 	sturb	wzr, [x3, #-8]
/home/ubuntu/lunatik/lua/ldo.c:446
      return;
    108c:	17ffffdb 	b	ff8 <luaD_poscall+0xe0>
luaD_poscall():
/home/ubuntu/lunatik/lua/ldo.c:490
  moveresults(L, ci->func.p, nres, wanted);
    1090:	f9400023 	ldr	x3, [x1]
moveresults():
/home/ubuntu/lunatik/lua/ldo.c:454
        res = luaF_close(L, res, CLOSEKTOP, 1);
    1094:	aa0303e1 	mov	x1, x3
/home/ubuntu/lunatik/lua/ldo.c:452
        L->ci->callstatus |= CIST_CLSRET;  /* in case of yields */
    1098:	f9401265 	ldr	x5, [x19, #32]
/home/ubuntu/lunatik/lua/ldo.c:454
        res = luaF_close(L, res, CLOSEKTOP, 1);
    109c:	52800023 	mov	w3, #0x1                   	// #1
    10a0:	aa1303e0 	mov	x0, x19
    10a4:	12800002 	mov	w2, #0xffffffff            	// #-1
/home/ubuntu/lunatik/lua/ldo.c:452
        L->ci->callstatus |= CIST_CLSRET;  /* in case of yields */
    10a8:	79407ca4 	ldrh	w4, [x5, #62]
    10ac:	32170084 	orr	w4, w4, #0x200
    10b0:	79007ca4 	strh	w4, [x5, #62]
/home/ubuntu/lunatik/lua/ldo.c:453
        L->ci->u2.nres = nres;
    10b4:	f9401264 	ldr	x4, [x19, #32]
    10b8:	b9003896 	str	w22, [x4, #56]
/home/ubuntu/lunatik/lua/ldo.c:454
        res = luaF_close(L, res, CLOSEKTOP, 1);
    10bc:	94000000 	bl	0 <luaF_close>
			10bc: R_AARCH64_CALL26	luaF_close
    10c0:	aa0003e3 	mov	x3, x0
/home/ubuntu/lunatik/lua/ldo.c:455
        L->ci->callstatus &= ~CIST_CLSRET;
    10c4:	f9401261 	ldr	x1, [x19, #32]
    10c8:	79407c20 	ldrh	w0, [x1, #62]
    10cc:	12167800 	and	w0, w0, #0xfffffdff
    10d0:	79007c20 	strh	w0, [x1, #62]
/home/ubuntu/lunatik/lua/ldo.c:456
        if (L->hookmask) {  /* if needed, call hook after '__close's */
    10d4:	b940c260 	ldr	w0, [x19, #192]
    10d8:	35000200 	cbnz	w0, 1118 <luaD_poscall+0x200>
/home/ubuntu/lunatik/lua/ldo.c:461
        wanted = decodeNresults(wanted);
    10dc:	12800040 	mov	w0, #0xfffffffd            	// #-3
    10e0:	4b140014 	sub	w20, w0, w20
/home/ubuntu/lunatik/lua/ldo.c:462
        if (wanted == LUA_MULTRET)
    10e4:	3100069f 	cmn	w20, #0x1
    10e8:	54fff480 	b.eq	f78 <luaD_poscall+0x60>  // b.none
    10ec:	6b1402df 	cmp	w22, w20
    10f0:	1a94d2c4 	csel	w4, w22, w20, le
    10f4:	17ffffa3 	b	f80 <luaD_poscall+0x68>
/home/ubuntu/lunatik/lua/ldo.c:444
        setobjs2s(L, res, L->top.p - nres);  /* move it to proper place */
    10f8:	f9400a60 	ldr	x0, [x19, #16]
/home/ubuntu/lunatik/lua/ldo.c:445
      L->top.p = res + 1;
    10fc:	91004063 	add	x3, x3, #0x10
/home/ubuntu/lunatik/lua/ldo.c:444
        setobjs2s(L, res, L->top.p - nres);  /* move it to proper place */
    1100:	cb36d000 	sub	x0, x0, w22, sxtw #4
    1104:	f9400001 	ldr	x1, [x0]
    1108:	f81f0061 	stur	x1, [x3, #-16]
    110c:	39402000 	ldrb	w0, [x0, #8]
    1110:	381f8060 	sturb	w0, [x3, #-8]
/home/ubuntu/lunatik/lua/ldo.c:446
      return;
    1114:	17ffffb9 	b	ff8 <luaD_poscall+0xe0>
/home/ubuntu/lunatik/lua/ldo.c:457
          ptrdiff_t savedres = savestack(L, res);
    1118:	f9001bf7 	str	x23, [sp, #48]
/home/ubuntu/lunatik/lua/ldo.c:458
          rethook(L, L->ci, nres);
    111c:	2a1603e2 	mov	w2, w22
    1120:	aa1303e0 	mov	x0, x19
    1124:	f9401261 	ldr	x1, [x19, #32]
/home/ubuntu/lunatik/lua/ldo.c:457
          ptrdiff_t savedres = savestack(L, res);
    1128:	f9401a77 	ldr	x23, [x19, #48]
    112c:	cb170077 	sub	x23, x3, x23
/home/ubuntu/lunatik/lua/ldo.c:458
          rethook(L, L->ci, nres);
    1130:	97fffeb0 	bl	bf0 <rethook>
/home/ubuntu/lunatik/lua/ldo.c:459
          res = restorestack(L, savedres);  /* hook can move stack */
    1134:	f9401a63 	ldr	x3, [x19, #48]
    1138:	8b170063 	add	x3, x3, x23
    113c:	f9401bf7 	ldr	x23, [sp, #48]
    1140:	17ffffe7 	b	10dc <luaD_poscall+0x1c4>
/home/ubuntu/lunatik/lua/ldo.c:471
  for (i = 0; i < nres; i++)  /* move all results to correct place */
    1144:	52800004 	mov	w4, #0x0                   	// #0
    1148:	17ffff9f 	b	fc4 <luaD_poscall+0xac>
luaD_poscall():
/home/ubuntu/lunatik/lua/ldo.c:471
    114c:	d503201f 	nop
    1150:	d503201f 	nop
    1154:	d503201f 	nop

0000000000001158 <unroll>:
unroll():
/home/ubuntu/lunatik/lua/ldo.c:736
static void unroll (lua_State *L, void *ud) {
    1158:	d503201f 	nop
    115c:	d503201f 	nop
    1160:	d503233f 	paciasp
    1164:	f800865e 	str	x30, [x18], #8
    1168:	a9bc7bfd 	stp	x29, x30, [sp, #-64]!
    116c:	910003fd 	mov	x29, sp
    1170:	a90153f3 	stp	x19, x20, [sp, #16]
    1174:	a9025bf5 	stp	x21, x22, [sp, #32]
/home/ubuntu/lunatik/lua/ldo.c:739
  while ((ci = L->ci) != &L->base_ci) {  /* something in the stack */
    1178:	91018016 	add	x22, x0, #0x60
    117c:	f9401013 	ldr	x19, [x0, #32]
    1180:	eb1302df 	cmp	x22, x19
    1184:	54000340 	b.eq	11ec <unroll+0x94>  // b.none
    1188:	aa0003f4 	mov	x20, x0
    118c:	aa1303f5 	mov	x21, x19
    1190:	f9001bf7 	str	x23, [sp, #48]
    1194:	1400000a 	b	11bc <unroll+0x64>
finishCcall():
/home/ubuntu/lunatik/lua/ldo.c:710
  if (ci->callstatus & CIST_CLSRET) {  /* was returning? */
    1198:	36480420 	tbz	w0, #9, 121c <unroll+0xc4>
/home/ubuntu/lunatik/lua/ldo.c:712
    n = ci->u2.nres;  /* just redo 'luaD_poscall' */
    119c:	b9403a62 	ldr	w2, [x19, #56]
/home/ubuntu/lunatik/lua/ldo.c:727
  luaD_poscall(L, ci, n);  /* finish 'luaD_call' */
    11a0:	aa1503e1 	mov	x1, x21
    11a4:	aa1403e0 	mov	x0, x20
    11a8:	94000000 	bl	f18 <luaD_poscall>
			11a8: R_AARCH64_CALL26	luaD_poscall
unroll():
/home/ubuntu/lunatik/lua/ldo.c:739
  while ((ci = L->ci) != &L->base_ci) {  /* something in the stack */
    11ac:	f9401293 	ldr	x19, [x20, #32]
    11b0:	aa1303f5 	mov	x21, x19
    11b4:	eb16027f 	cmp	x19, x22
    11b8:	54000180 	b.eq	11e8 <unroll+0x90>  // b.none
/home/ubuntu/lunatik/lua/ldo.c:740
    if (!isLua(ci))  /* C function? */
    11bc:	79407e60 	ldrh	w0, [x19, #62]
    11c0:	370ffec0 	tbnz	w0, #1, 1198 <unroll+0x40>
/home/ubuntu/lunatik/lua/ldo.c:743
      luaV_finishOp(L);  /* finish interrupted instruction */
    11c4:	aa1403e0 	mov	x0, x20
    11c8:	94000000 	bl	0 <luaV_finishOp>
			11c8: R_AARCH64_CALL26	luaV_finishOp
/home/ubuntu/lunatik/lua/ldo.c:744
      luaV_execute(L, ci);  /* execute down to higher C 'boundary' */
    11cc:	aa1303e1 	mov	x1, x19
    11d0:	aa1403e0 	mov	x0, x20
    11d4:	94000000 	bl	0 <luaV_execute>
			11d4: R_AARCH64_CALL26	luaV_execute
/home/ubuntu/lunatik/lua/ldo.c:739
  while ((ci = L->ci) != &L->base_ci) {  /* something in the stack */
    11d8:	f9401293 	ldr	x19, [x20, #32]
    11dc:	aa1303f5 	mov	x21, x19
    11e0:	eb16027f 	cmp	x19, x22
    11e4:	54fffec1 	b.ne	11bc <unroll+0x64>  // b.any
    11e8:	f9401bf7 	ldr	x23, [sp, #48]
/home/ubuntu/lunatik/lua/ldo.c:747
}
    11ec:	f85f8e5e 	ldr	x30, [x18, #-8]!
    11f0:	a94153f3 	ldp	x19, x20, [sp, #16]
    11f4:	a9425bf5 	ldp	x21, x22, [sp, #32]
    11f8:	f84407fd 	ldr	x29, [sp], #64
    11fc:	d50323bf 	autiasp
    1200:	d2800000 	mov	x0, #0x0                   	// #0
    1204:	d2800001 	mov	x1, #0x0                   	// #0
    1208:	d2800002 	mov	x2, #0x0                   	// #0
    120c:	d2800003 	mov	x3, #0x0                   	// #0
    1210:	d2800010 	mov	x16, #0x0                   	// #0
    1214:	d2800011 	mov	x17, #0x0                   	// #0
    1218:	d65f03c0 	ret
finishCcall():
/home/ubuntu/lunatik/lua/ldo.c:716
    int status = LUA_YIELD;  /* default if there were no errors */
    121c:	52800037 	mov	w23, #0x1                   	// #1
/home/ubuntu/lunatik/lua/ldo.c:719
    if (ci->callstatus & CIST_YPCALL)   /* was inside a 'lua_pcallk'? */
    1220:	372001a0 	tbnz	w0, #4, 1254 <unroll+0xfc>
/home/ubuntu/lunatik/lua/ldo.c:721
    adjustresults(L, LUA_MULTRET);  /* finish 'lua_callk' */
    1224:	f9400661 	ldr	x1, [x19, #8]
    1228:	f9400a80 	ldr	x0, [x20, #16]
    122c:	eb00003f 	cmp	x1, x0
    1230:	54000042 	b.cs	1238 <unroll+0xe0>  // b.hs, b.nlast
    1234:	f9000660 	str	x0, [x19, #8]
/home/ubuntu/lunatik/lua/ldo.c:723
    n = (*ci->u.c.k)(L, status, ci->u.c.ctx);  /* call continuation */
    1238:	f94012a3 	ldr	x3, [x21, #32]
    123c:	2a1703e1 	mov	w1, w23
    1240:	f9401aa2 	ldr	x2, [x21, #48]
    1244:	aa1403e0 	mov	x0, x20
    1248:	d63f0060 	blr	x3
    124c:	2a0003e2 	mov	w2, w0
    1250:	17ffffd4 	b	11a0 <unroll+0x48>
finishpcallk():
/home/ubuntu/lunatik/lua/ldo.c:676
  int status = getcistrecst(ci);  /* get original status */
    1254:	d34a3002 	ubfx	x2, x0, #10, #3
/home/ubuntu/lunatik/lua/ldo.c:677
  if (l_likely(status == LUA_OK))  /* no error? */
    1258:	350000e2 	cbnz	w2, 1274 <unroll+0x11c>
/home/ubuntu/lunatik/lua/ldo.c:687
  ci->callstatus &= ~CIST_YPCALL;
    125c:	121b7800 	and	w0, w0, #0xffffffef
    1260:	79007e60 	strh	w0, [x19, #62]
/home/ubuntu/lunatik/lua/ldo.c:688
  L->errfunc = ci->u.c.old_errfunc;
    1264:	f9401660 	ldr	x0, [x19, #40]
    1268:	f9005680 	str	x0, [x20, #168]
/home/ubuntu/lunatik/lua/ldo.c:691
  return status;
    126c:	f9401293 	ldr	x19, [x20, #32]
    1270:	17ffffed 	b	1224 <unroll+0xcc>
/home/ubuntu/lunatik/lua/ldo.c:680
    StkId func = restorestack(L, ci->u2.funcidx);
    1274:	f9401a83 	ldr	x3, [x20, #48]
/home/ubuntu/lunatik/lua/ldo.c:681
    L->allowhook = getoah(ci->callstatus);  /* restore 'allowhook' */
    1278:	0a170000 	and	w0, w0, w23
/home/ubuntu/lunatik/lua/ldo.c:680
    StkId func = restorestack(L, ci->u2.funcidx);
    127c:	b9803a61 	ldrsw	x1, [x19, #56]
/home/ubuntu/lunatik/lua/ldo.c:676
  int status = getcistrecst(ci);  /* get original status */
    1280:	2a0203f7 	mov	w23, w2
/home/ubuntu/lunatik/lua/ldo.c:681
    L->allowhook = getoah(ci->callstatus);  /* restore 'allowhook' */
    1284:	39002e80 	strb	w0, [x20, #11]
/home/ubuntu/lunatik/lua/ldo.c:682
    func = luaF_close(L, func, status, 1);  /* can yield or raise an error */
    1288:	aa1403e0 	mov	x0, x20
    128c:	8b010061 	add	x1, x3, x1
    1290:	52800023 	mov	w3, #0x1                   	// #1
    1294:	94000000 	bl	0 <luaF_close>
			1294: R_AARCH64_CALL26	luaF_close
/home/ubuntu/lunatik/lua/ldo.c:683
    luaD_seterrorobj(L, status, func);
    1298:	aa0003e2 	mov	x2, x0
    129c:	2a1703e1 	mov	w1, w23
    12a0:	aa1403e0 	mov	x0, x20
    12a4:	94000000 	bl	120 <luaD_seterrorobj>
			12a4: R_AARCH64_CALL26	luaD_seterrorobj
/home/ubuntu/lunatik/lua/ldo.c:684
    luaD_shrinkstack(L);   /* restore stack size in case of overflow */
    12a8:	aa1403e0 	mov	x0, x20
    12ac:	94000000 	bl	858 <luaD_shrinkstack>
			12ac: R_AARCH64_CALL26	luaD_shrinkstack
/home/ubuntu/lunatik/lua/ldo.c:685
    setcistrecst(ci, LUA_OK);  /* clear original status */
    12b0:	79407e60 	ldrh	w0, [x19, #62]
    12b4:	12137000 	and	w0, w0, #0xffffe3ff
    12b8:	12003c00 	and	w0, w0, #0xffff
    12bc:	17ffffe8 	b	125c <unroll+0x104>
unroll():
/home/ubuntu/lunatik/lua/ldo.c:685
    12c0:	d503201f 	nop
    12c4:	d503201f 	nop

00000000000012c8 <luaD_pretailcall>:
luaD_pretailcall():
/home/ubuntu/lunatik/lua/ldo.c:544
                                    int narg1, int delta) {
    12c8:	d503201f 	nop
    12cc:	d503201f 	nop
    12d0:	d503233f 	paciasp
    12d4:	f800865e 	str	x30, [x18], #8
    12d8:	a9ba7bfd 	stp	x29, x30, [sp, #-96]!
    12dc:	910003fd 	mov	x29, sp
    12e0:	a90153f3 	stp	x19, x20, [sp, #16]
    12e4:	aa0203f3 	mov	x19, x2
    12e8:	aa0003f4 	mov	x20, x0
    12ec:	a9025bf5 	stp	x21, x22, [sp, #32]
    12f0:	aa0103f5 	mov	x21, x1
    12f4:	2a0303f6 	mov	w22, w3
    12f8:	a90363f7 	stp	x23, x24, [sp, #48]
    12fc:	2a0403f8 	mov	w24, w4
    1300:	39402262 	ldrb	w2, [x19, #8]
    1304:	12001442 	and	w2, w2, #0x3f
/home/ubuntu/lunatik/lua/ldo.c:546
  switch (ttypetag(s2v(func))) {
    1308:	7100585f 	cmp	w2, #0x16
    130c:	540001c0 	b.eq	1344 <luaD_pretailcall+0x7c>  // b.none
/home/ubuntu/lunatik/lua/ldo.c:571
      func = luaD_tryfuncTM(L, func);  /* try to get '__call' metamethod */
    1310:	aa1303e1 	mov	x1, x19
    1314:	aa1403e0 	mov	x0, x20
/home/ubuntu/lunatik/lua/ldo.c:546
  switch (ttypetag(s2v(func))) {
    1318:	7100985f 	cmp	w2, #0x26
    131c:	54000de0 	b.eq	14d8 <luaD_pretailcall+0x210>  // b.none
    1320:	7100185f 	cmp	w2, #0x6
    1324:	54000380 	b.eq	1394 <luaD_pretailcall+0xcc>  // b.none
/home/ubuntu/lunatik/lua/ldo.c:571
      func = luaD_tryfuncTM(L, func);  /* try to get '__call' metamethod */
    1328:	94000000 	bl	de0 <luaD_tryfuncTM>
			1328: R_AARCH64_CALL26	luaD_tryfuncTM
    132c:	aa0003f3 	mov	x19, x0
/home/ubuntu/lunatik/lua/ldo.c:573
      narg1++;
    1330:	110006d6 	add	w22, w22, #0x1
/home/ubuntu/lunatik/lua/ldo.c:546
  switch (ttypetag(s2v(func))) {
    1334:	39402262 	ldrb	w2, [x19, #8]
    1338:	12001442 	and	w2, w2, #0x3f
    133c:	7100585f 	cmp	w2, #0x16
    1340:	54fffe81 	b.ne	1310 <luaD_pretailcall+0x48>  // b.any
precallC():
/home/ubuntu/lunatik/lua/ldo.c:520
  checkstackGCp(L, LUA_MINSTACK, func);  /* ensure minimum stack size */
    1344:	f9400a80 	ldr	x0, [x20, #16]
    1348:	f9401681 	ldr	x1, [x20, #40]
luaD_pretailcall():
/home/ubuntu/lunatik/lua/ldo.c:550
      return precallC(L, func, LUA_MULTRET, fvalue(s2v(func)));
    134c:	f9400277 	ldr	x23, [x19]
precallC():
/home/ubuntu/lunatik/lua/ldo.c:520
  checkstackGCp(L, LUA_MINSTACK, func);  /* ensure minimum stack size */
    1350:	cb000021 	sub	x1, x1, x0
    1354:	f105003f 	cmp	x1, #0x140
    1358:	54000cec 	b.gt	14f4 <luaD_pretailcall+0x22c>
    135c:	f9400e80 	ldr	x0, [x20, #24]
    1360:	f9401a95 	ldr	x21, [x20, #48]
    1364:	f9400c00 	ldr	x0, [x0, #24]
    1368:	cb150275 	sub	x21, x19, x21
    136c:	f100001f 	cmp	x0, #0x0
    1370:	540011ec 	b.gt	15ac <luaD_pretailcall+0x2e4>
    1374:	aa1403e0 	mov	x0, x20
    1378:	52800022 	mov	w2, #0x1                   	// #1
    137c:	52800281 	mov	w1, #0x14                  	// #20
    1380:	94000000 	bl	730 <luaD_growstack>
			1380: R_AARCH64_CALL26	luaD_growstack
    1384:	f9401a93 	ldr	x19, [x20, #48]
/home/ubuntu/lunatik/lua/ldo.c:522
                               L->top.p + LUA_MINSTACK);
    1388:	f9400a80 	ldr	x0, [x20, #16]
/home/ubuntu/lunatik/lua/ldo.c:520
  checkstackGCp(L, LUA_MINSTACK, func);  /* ensure minimum stack size */
    138c:	8b150273 	add	x19, x19, x21
    1390:	14000059 	b	14f4 <luaD_pretailcall+0x22c>
luaD_pretailcall():
/home/ubuntu/lunatik/lua/ldo.c:552
      Proto *p = clLvalue(s2v(func))->p;
    1394:	a9046bf9 	stp	x25, x26, [sp, #64]
    1398:	f9002bfb 	str	x27, [sp, #80]
    139c:	f9400260 	ldr	x0, [x19]
/home/ubuntu/lunatik/lua/ldo.c:556
      checkstackGCp(L, fsize - delta, func);
    13a0:	f9400a81 	ldr	x1, [x20, #16]
/home/ubuntu/lunatik/lua/ldo.c:552
      Proto *p = clLvalue(s2v(func))->p;
    13a4:	f9400c1a 	ldr	x26, [x0, #24]
/home/ubuntu/lunatik/lua/ldo.c:556
      checkstackGCp(L, fsize - delta, func);
    13a8:	f9401680 	ldr	x0, [x20, #40]
/home/ubuntu/lunatik/lua/ldo.c:553
      int fsize = p->maxstacksize;  /* frame size */
    13ac:	39403359 	ldrb	w25, [x26, #12]
/home/ubuntu/lunatik/lua/ldo.c:556
      checkstackGCp(L, fsize - delta, func);
    13b0:	cb010000 	sub	x0, x0, x1
/home/ubuntu/lunatik/lua/ldo.c:554
      int nfixparams = p->numparams;
    13b4:	39402b57 	ldrb	w23, [x26, #10]
/home/ubuntu/lunatik/lua/ldo.c:556
      checkstackGCp(L, fsize - delta, func);
    13b8:	4b18033b 	sub	w27, w25, w24
    13bc:	93407f61 	sxtw	x1, w27
    13c0:	eb80103f 	cmp	x1, x0, asr #4
    13c4:	54000faa 	b.ge	15b8 <luaD_pretailcall+0x2f0>  // b.tcont
/home/ubuntu/lunatik/lua/ldo.c:557 (discriminator 6)
      ci->func.p -= delta;  /* restore 'func' (if vararg) */
    13c8:	f94002a0 	ldr	x0, [x21]
    13cc:	cb38d000 	sub	x0, x0, w24, sxtw #4
    13d0:	f90002a0 	str	x0, [x21]
/home/ubuntu/lunatik/lua/ldo.c:558 (discriminator 6)
      for (i = 0; i < narg1; i++)  /* move down function and arguments */
    13d4:	710002df 	cmp	w22, #0x0
    13d8:	540002cd 	b.le	1430 <luaD_pretailcall+0x168>
/home/ubuntu/lunatik/lua/ldo.c:559
        setobjs2s(L, ci->func.p + i, func + i);
    13dc:	f9400261 	ldr	x1, [x19]
    13e0:	f9000001 	str	x1, [x0]
    13e4:	39402261 	ldrb	w1, [x19, #8]
    13e8:	39002001 	strb	w1, [x0, #8]
/home/ubuntu/lunatik/lua/ldo.c:558
      for (i = 0; i < narg1; i++)  /* move down function and arguments */
    13ec:	710006df 	cmp	w22, #0x1
    13f0:	540001a0 	b.eq	1424 <luaD_pretailcall+0x15c>  // b.none
    13f4:	d37c7ec5 	ubfiz	x5, x22, #4, #32
    13f8:	91002263 	add	x3, x19, #0x8
    13fc:	d2800204 	mov	x4, #0x10                  	// #16
/home/ubuntu/lunatik/lua/ldo.c:559
        setobjs2s(L, ci->func.p + i, func + i);
    1400:	f94002a0 	ldr	x0, [x21]
    1404:	f8646a62 	ldr	x2, [x19, x4]
    1408:	8b040001 	add	x1, x0, x4
    140c:	f8246802 	str	x2, [x0, x4]
    1410:	38646860 	ldrb	w0, [x3, x4]
/home/ubuntu/lunatik/lua/ldo.c:558
      for (i = 0; i < narg1; i++)  /* move down function and arguments */
    1414:	91004084 	add	x4, x4, #0x10
/home/ubuntu/lunatik/lua/ldo.c:559
        setobjs2s(L, ci->func.p + i, func + i);
    1418:	39002020 	strb	w0, [x1, #8]
/home/ubuntu/lunatik/lua/ldo.c:558
      for (i = 0; i < narg1; i++)  /* move down function and arguments */
    141c:	eb0400bf 	cmp	x5, x4
    1420:	54ffff01 	b.ne	1400 <luaD_pretailcall+0x138>  // b.any
/home/ubuntu/lunatik/lua/ldo.c:560
      func = ci->func.p;  /* moved-down function */
    1424:	f94002a0 	ldr	x0, [x21]
/home/ubuntu/lunatik/lua/ldo.c:561
      for (; narg1 <= nfixparams; narg1++)
    1428:	6b1702df 	cmp	w22, w23
    142c:	540001cc 	b.gt	1464 <luaD_pretailcall+0x19c>
/home/ubuntu/lunatik/lua/ldo.c:558
      for (i = 0; i < narg1; i++)  /* move down function and arguments */
    1430:	2a1603e2 	mov	w2, w22
    1434:	d503201f 	nop
/home/ubuntu/lunatik/lua/ldo.c:562 (discriminator 2)
        setnilvalue(s2v(func + narg1));  /* complete missing arguments */
    1438:	8b22d001 	add	x1, x0, w2, sxtw #4
/home/ubuntu/lunatik/lua/ldo.c:561 (discriminator 2)
      for (; narg1 <= nfixparams; narg1++)
    143c:	11000442 	add	w2, w2, #0x1
/home/ubuntu/lunatik/lua/ldo.c:562 (discriminator 2)
        setnilvalue(s2v(func + narg1));  /* complete missing arguments */
    1440:	3900203f 	strb	wzr, [x1, #8]
/home/ubuntu/lunatik/lua/ldo.c:561 (discriminator 2)
      for (; narg1 <= nfixparams; narg1++)
    1444:	6b0202ff 	cmp	w23, w2
    1448:	54ffff8a 	b.ge	1438 <luaD_pretailcall+0x170>  // b.tcont
    144c:	110006c1 	add	w1, w22, #0x1
    1450:	110006e2 	add	w2, w23, #0x1
    1454:	6b02003f 	cmp	w1, w2
    1458:	4b1602f7 	sub	w23, w23, w22
    145c:	1a9fd2f7 	csel	w23, w23, wzr, le
/home/ubuntu/lunatik/lua/ldo.c:561
    1460:	0b0102f6 	add	w22, w23, w1
/home/ubuntu/lunatik/lua/ldo.c:563
      ci->top.p = func + 1 + fsize;  /* top for new function */
    1464:	d37c1f39 	ubfiz	x25, x25, #4, #8
/home/ubuntu/lunatik/lua/ldo.c:566
      ci->callstatus |= CIST_TAIL;
    1468:	79407ea1 	ldrh	w1, [x21, #62]
/home/ubuntu/lunatik/lua/ldo.c:563
      ci->top.p = func + 1 + fsize;  /* top for new function */
    146c:	91004339 	add	x25, x25, #0x10
/home/ubuntu/lunatik/lua/ldo.c:567
      L->top.p = func + narg1;  /* set top */
    1470:	8b36d016 	add	x22, x0, w22, sxtw #4
/home/ubuntu/lunatik/lua/ldo.c:563
      ci->top.p = func + 1 + fsize;  /* top for new function */
    1474:	8b190000 	add	x0, x0, x25
    1478:	f90006a0 	str	x0, [x21, #8]
/home/ubuntu/lunatik/lua/ldo.c:566
      ci->callstatus |= CIST_TAIL;
    147c:	321b0020 	orr	w0, w1, #0x20
/home/ubuntu/lunatik/lua/ldo.c:568
      return -1;
    1480:	12800013 	mov	w19, #0xffffffff            	// #-1
/home/ubuntu/lunatik/lua/ldo.c:565
      ci->u.l.savedpc = p->code;  /* starting point */
    1484:	f9402341 	ldr	x1, [x26, #64]
    1488:	f90012a1 	str	x1, [x21, #32]
/home/ubuntu/lunatik/lua/ldo.c:566
      ci->callstatus |= CIST_TAIL;
    148c:	79007ea0 	strh	w0, [x21, #62]
/home/ubuntu/lunatik/lua/ldo.c:577
}
    1490:	2a1303e0 	mov	w0, w19
/home/ubuntu/lunatik/lua/ldo.c:567
      L->top.p = func + narg1;  /* set top */
    1494:	f9000a96 	str	x22, [x20, #16]
/home/ubuntu/lunatik/lua/ldo.c:577
}
    1498:	f85f8e5e 	ldr	x30, [x18, #-8]!
    149c:	a94153f3 	ldp	x19, x20, [sp, #16]
    14a0:	a9425bf5 	ldp	x21, x22, [sp, #32]
    14a4:	a94363f7 	ldp	x23, x24, [sp, #48]
/home/ubuntu/lunatik/lua/ldo.c:568
      return -1;
    14a8:	a9446bf9 	ldp	x25, x26, [sp, #64]
    14ac:	f9402bfb 	ldr	x27, [sp, #80]
/home/ubuntu/lunatik/lua/ldo.c:577
}
    14b0:	f84607fd 	ldr	x29, [sp], #96
    14b4:	d50323bf 	autiasp
    14b8:	d2800001 	mov	x1, #0x0                   	// #0
    14bc:	d2800002 	mov	x2, #0x0                   	// #0
    14c0:	d2800003 	mov	x3, #0x0                   	// #0
    14c4:	d2800004 	mov	x4, #0x0                   	// #0
    14c8:	d2800005 	mov	x5, #0x0                   	// #0
    14cc:	d2800010 	mov	x16, #0x0                   	// #0
    14d0:	d2800011 	mov	x17, #0x0                   	// #0
    14d4:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:548
      return precallC(L, func, LUA_MULTRET, clCvalue(s2v(func))->f);
    14d8:	f9400262 	ldr	x2, [x19]
precallC():
/home/ubuntu/lunatik/lua/ldo.c:520
  checkstackGCp(L, LUA_MINSTACK, func);  /* ensure minimum stack size */
    14dc:	f9400a80 	ldr	x0, [x20, #16]
    14e0:	f9401681 	ldr	x1, [x20, #40]
luaD_pretailcall():
/home/ubuntu/lunatik/lua/ldo.c:548
      return precallC(L, func, LUA_MULTRET, clCvalue(s2v(func))->f);
    14e4:	f9400c57 	ldr	x23, [x2, #24]
precallC():
/home/ubuntu/lunatik/lua/ldo.c:520
  checkstackGCp(L, LUA_MINSTACK, func);  /* ensure minimum stack size */
    14e8:	cb000021 	sub	x1, x1, x0
    14ec:	f105003f 	cmp	x1, #0x140
    14f0:	54fff36d 	b.le	135c <luaD_pretailcall+0x94>
prepCallInfo():
/home/ubuntu/lunatik/lua/ldo.c:504
  CallInfo *ci = L->ci = next_ci(L);  /* new frame */
    14f4:	f9401281 	ldr	x1, [x20, #32]
precallC():
/home/ubuntu/lunatik/lua/ldo.c:521
  L->ci = ci = prepCallInfo(L, func, nresults, CIST_C,
    14f8:	91050016 	add	x22, x0, #0x140
prepCallInfo():
/home/ubuntu/lunatik/lua/ldo.c:504
  CallInfo *ci = L->ci = next_ci(L);  /* new frame */
    14fc:	f9400c35 	ldr	x21, [x1, #24]
    1500:	b40003b5 	cbz	x21, 1574 <luaD_pretailcall+0x2ac>
/home/ubuntu/lunatik/lua/ldo.c:506
  ci->nresults = nret;
    1504:	12bfffa0 	mov	w0, #0x2ffff               	// #196607
/home/ubuntu/lunatik/lua/ldo.c:508
  ci->top.p = top;
    1508:	a9005ab3 	stp	x19, x22, [x21]
/home/ubuntu/lunatik/lua/ldo.c:506
  ci->nresults = nret;
    150c:	b9003ea0 	str	w0, [x21, #60]
precallC():
/home/ubuntu/lunatik/lua/ldo.c:521
  L->ci = ci = prepCallInfo(L, func, nresults, CIST_C,
    1510:	f9001295 	str	x21, [x20, #32]
/home/ubuntu/lunatik/lua/ldo.c:524
  if (l_unlikely(L->hookmask & LUA_MASKCALL)) {
    1514:	b940c280 	ldr	w0, [x20, #192]
    1518:	37000360 	tbnz	w0, #0, 1584 <luaD_pretailcall+0x2bc>
/home/ubuntu/lunatik/lua/ldo.c:529
  n = (*f)(L);  /* do the actual call */
    151c:	aa1403e0 	mov	x0, x20
    1520:	d63f02e0 	blr	x23
    1524:	2a0003f3 	mov	w19, w0
/home/ubuntu/lunatik/lua/ldo.c:532
  luaD_poscall(L, ci, n);
    1528:	aa1503e1 	mov	x1, x21
    152c:	aa1403e0 	mov	x0, x20
    1530:	2a1303e2 	mov	w2, w19
    1534:	94000000 	bl	f18 <luaD_poscall>
			1534: R_AARCH64_CALL26	luaD_poscall
luaD_pretailcall():
/home/ubuntu/lunatik/lua/ldo.c:577
}
    1538:	f85f8e5e 	ldr	x30, [x18, #-8]!
    153c:	2a1303e0 	mov	w0, w19
    1540:	a94153f3 	ldp	x19, x20, [sp, #16]
    1544:	a9425bf5 	ldp	x21, x22, [sp, #32]
    1548:	a94363f7 	ldp	x23, x24, [sp, #48]
    154c:	f84607fd 	ldr	x29, [sp], #96
    1550:	d50323bf 	autiasp
    1554:	d2800001 	mov	x1, #0x0                   	// #0
    1558:	d2800002 	mov	x2, #0x0                   	// #0
    155c:	d2800003 	mov	x3, #0x0                   	// #0
    1560:	d2800004 	mov	x4, #0x0                   	// #0
    1564:	d2800005 	mov	x5, #0x0                   	// #0
    1568:	d2800010 	mov	x16, #0x0                   	// #0
    156c:	d2800011 	mov	x17, #0x0                   	// #0
    1570:	d65f03c0 	ret
prepCallInfo():
/home/ubuntu/lunatik/lua/ldo.c:504
  CallInfo *ci = L->ci = next_ci(L);  /* new frame */
    1574:	aa1403e0 	mov	x0, x20
    1578:	94000000 	bl	0 <luaE_extendCI>
			1578: R_AARCH64_CALL26	luaE_extendCI
    157c:	aa0003f5 	mov	x21, x0
    1580:	17ffffe1 	b	1504 <luaD_pretailcall+0x23c>
precallC():
/home/ubuntu/lunatik/lua/ldo.c:525
    int narg = cast_int(L->top.p - func) - 1;
    1584:	f9400a84 	ldr	x4, [x20, #16]
/home/ubuntu/lunatik/lua/ldo.c:526
    luaD_hook(L, LUA_HOOKCALL, -1, 1, narg);
    1588:	12800002 	mov	w2, #0xffffffff            	// #-1
    158c:	aa1403e0 	mov	x0, x20
    1590:	52800023 	mov	w3, #0x1                   	// #1
/home/ubuntu/lunatik/lua/ldo.c:525
    int narg = cast_int(L->top.p - func) - 1;
    1594:	cb130084 	sub	x4, x4, x19
/home/ubuntu/lunatik/lua/ldo.c:526
    luaD_hook(L, LUA_HOOKCALL, -1, 1, narg);
    1598:	52800001 	mov	w1, #0x0                   	// #0
/home/ubuntu/lunatik/lua/ldo.c:525
    int narg = cast_int(L->top.p - func) - 1;
    159c:	9344fc84 	asr	x4, x4, #4
/home/ubuntu/lunatik/lua/ldo.c:526
    luaD_hook(L, LUA_HOOKCALL, -1, 1, narg);
    15a0:	0b020084 	add	w4, w4, w2
    15a4:	94000000 	bl	a20 <luaD_hook>
			15a4: R_AARCH64_CALL26	luaD_hook
    15a8:	17ffffdd 	b	151c <luaD_pretailcall+0x254>
/home/ubuntu/lunatik/lua/ldo.c:520
  checkstackGCp(L, LUA_MINSTACK, func);  /* ensure minimum stack size */
    15ac:	aa1403e0 	mov	x0, x20
    15b0:	94000000 	bl	0 <luaC_step>
			15b0: R_AARCH64_CALL26	luaC_step
    15b4:	17ffff70 	b	1374 <luaD_pretailcall+0xac>
luaD_pretailcall():
/home/ubuntu/lunatik/lua/ldo.c:556 (discriminator 1)
      checkstackGCp(L, fsize - delta, func);
    15b8:	f9400e80 	ldr	x0, [x20, #24]
    15bc:	f9401a81 	ldr	x1, [x20, #48]
    15c0:	f9400c00 	ldr	x0, [x0, #24]
    15c4:	cb010273 	sub	x19, x19, x1
    15c8:	f100001f 	cmp	x0, #0x0
    15cc:	5400006d 	b.le	15d8 <luaD_pretailcall+0x310>
/home/ubuntu/lunatik/lua/ldo.c:556 (discriminator 3)
    15d0:	aa1403e0 	mov	x0, x20
    15d4:	94000000 	bl	0 <luaC_step>
			15d4: R_AARCH64_CALL26	luaC_step
/home/ubuntu/lunatik/lua/ldo.c:556 (discriminator 5)
    15d8:	2a1b03e1 	mov	w1, w27
    15dc:	aa1403e0 	mov	x0, x20
    15e0:	52800022 	mov	w2, #0x1                   	// #1
    15e4:	94000000 	bl	730 <luaD_growstack>
			15e4: R_AARCH64_CALL26	luaD_growstack
    15e8:	f9401a80 	ldr	x0, [x20, #48]
    15ec:	8b130013 	add	x19, x0, x19
    15f0:	17ffff76 	b	13c8 <luaD_pretailcall+0x100>
    15f4:	d503201f 	nop
    15f8:	d503201f 	nop
    15fc:	d503201f 	nop

0000000000001600 <luaD_precall>:
luaD_precall():
/home/ubuntu/lunatik/lua/ldo.c:588
CallInfo *luaD_precall (lua_State *L, StkId func, int nresults) {
    1600:	d503201f 	nop
    1604:	d503201f 	nop
    1608:	d503233f 	paciasp
    160c:	f800865e 	str	x30, [x18], #8
    1610:	a9bb7bfd 	stp	x29, x30, [sp, #-80]!
    1614:	910003fd 	mov	x29, sp
    1618:	a9025bf5 	stp	x21, x22, [sp, #32]
    161c:	aa0103f5 	mov	x21, x1
    1620:	2a0203f6 	mov	w22, w2
    1624:	a90153f3 	stp	x19, x20, [sp, #16]
    1628:	aa0003f3 	mov	x19, x0
    162c:	a90363f7 	stp	x23, x24, [sp, #48]
    1630:	394022a3 	ldrb	w3, [x21, #8]
    1634:	12001463 	and	w3, w3, #0x3f
/home/ubuntu/lunatik/lua/ldo.c:590
  switch (ttypetag(s2v(func))) {
    1638:	7100587f 	cmp	w3, #0x16
    163c:	540001a0 	b.eq	1670 <luaD_precall+0x70>  // b.none
/home/ubuntu/lunatik/lua/ldo.c:612
      func = luaD_tryfuncTM(L, func);  /* try to get '__call' metamethod */
    1640:	aa1503e1 	mov	x1, x21
    1644:	aa1303e0 	mov	x0, x19
/home/ubuntu/lunatik/lua/ldo.c:590
  switch (ttypetag(s2v(func))) {
    1648:	7100987f 	cmp	w3, #0x26
    164c:	540009c0 	b.eq	1784 <luaD_precall+0x184>  // b.none
    1650:	7100187f 	cmp	w3, #0x6
    1654:	54000360 	b.eq	16c0 <luaD_precall+0xc0>  // b.none
/home/ubuntu/lunatik/lua/ldo.c:612
      func = luaD_tryfuncTM(L, func);  /* try to get '__call' metamethod */
    1658:	94000000 	bl	de0 <luaD_tryfuncTM>
			1658: R_AARCH64_CALL26	luaD_tryfuncTM
    165c:	aa0003f5 	mov	x21, x0
/home/ubuntu/lunatik/lua/ldo.c:590
  switch (ttypetag(s2v(func))) {
    1660:	394022a3 	ldrb	w3, [x21, #8]
    1664:	12001463 	and	w3, w3, #0x3f
    1668:	7100587f 	cmp	w3, #0x16
    166c:	54fffea1 	b.ne	1640 <luaD_precall+0x40>  // b.any
precallC():
/home/ubuntu/lunatik/lua/ldo.c:520
  checkstackGCp(L, LUA_MINSTACK, func);  /* ensure minimum stack size */
    1670:	f9400a60 	ldr	x0, [x19, #16]
    1674:	f9401661 	ldr	x1, [x19, #40]
luaD_precall():
/home/ubuntu/lunatik/lua/ldo.c:595
      precallC(L, func, nresults, fvalue(s2v(func)));
    1678:	f94002b8 	ldr	x24, [x21]
precallC():
/home/ubuntu/lunatik/lua/ldo.c:520
  checkstackGCp(L, LUA_MINSTACK, func);  /* ensure minimum stack size */
    167c:	cb000021 	sub	x1, x1, x0
    1680:	f105003f 	cmp	x1, #0x140
    1684:	540008ec 	b.gt	17a0 <luaD_precall+0x1a0>
    1688:	f9400e60 	ldr	x0, [x19, #24]
    168c:	f9401a74 	ldr	x20, [x19, #48]
    1690:	f9400c00 	ldr	x0, [x0, #24]
    1694:	cb1402b4 	sub	x20, x21, x20
    1698:	f100001f 	cmp	x0, #0x0
    169c:	54000e2c 	b.gt	1860 <luaD_precall+0x260>
    16a0:	aa1303e0 	mov	x0, x19
    16a4:	52800022 	mov	w2, #0x1                   	// #1
    16a8:	52800281 	mov	w1, #0x14                  	// #20
    16ac:	94000000 	bl	730 <luaD_growstack>
			16ac: R_AARCH64_CALL26	luaD_growstack
    16b0:	f9401a75 	ldr	x21, [x19, #48]
/home/ubuntu/lunatik/lua/ldo.c:522
                               L->top.p + LUA_MINSTACK);
    16b4:	f9400a60 	ldr	x0, [x19, #16]
/home/ubuntu/lunatik/lua/ldo.c:520
  checkstackGCp(L, LUA_MINSTACK, func);  /* ensure minimum stack size */
    16b8:	8b1402b5 	add	x21, x21, x20
    16bc:	14000039 	b	17a0 <luaD_precall+0x1a0>
luaD_precall():
/home/ubuntu/lunatik/lua/ldo.c:599
      Proto *p = clLvalue(s2v(func))->p;
    16c0:	a9046bf9 	stp	x25, x26, [sp, #64]
    16c4:	f94002a0 	ldr	x0, [x21]
/home/ubuntu/lunatik/lua/ldo.c:600
      int narg = cast_int(L->top.p - func) - 1;  /* number of real arguments */
    16c8:	f9400a62 	ldr	x2, [x19, #16]
/home/ubuntu/lunatik/lua/ldo.c:599
      Proto *p = clLvalue(s2v(func))->p;
    16cc:	f9400c19 	ldr	x25, [x0, #24]
/home/ubuntu/lunatik/lua/ldo.c:600
      int narg = cast_int(L->top.p - func) - 1;  /* number of real arguments */
    16d0:	cb150054 	sub	x20, x2, x21
/home/ubuntu/lunatik/lua/ldo.c:603
      checkstackGCp(L, fsize, func);
    16d4:	f9401660 	ldr	x0, [x19, #40]
/home/ubuntu/lunatik/lua/ldo.c:600
      int narg = cast_int(L->top.p - func) - 1;  /* number of real arguments */
    16d8:	9344fe94 	asr	x20, x20, #4
/home/ubuntu/lunatik/lua/ldo.c:602
      int fsize = p->maxstacksize;  /* frame size */
    16dc:	39403338 	ldrb	w24, [x25, #12]
/home/ubuntu/lunatik/lua/ldo.c:600
      int narg = cast_int(L->top.p - func) - 1;  /* number of real arguments */
    16e0:	51000694 	sub	w20, w20, #0x1
/home/ubuntu/lunatik/lua/ldo.c:603
      checkstackGCp(L, fsize, func);
    16e4:	cb020000 	sub	x0, x0, x2
/home/ubuntu/lunatik/lua/ldo.c:601
      int nfixparams = p->numparams;
    16e8:	39402b37 	ldrb	w23, [x25, #10]
/home/ubuntu/lunatik/lua/ldo.c:602
      int fsize = p->maxstacksize;  /* frame size */
    16ec:	aa1803fa 	mov	x26, x24
/home/ubuntu/lunatik/lua/ldo.c:603
      checkstackGCp(L, fsize, func);
    16f0:	eb80131f 	cmp	x24, x0, asr #4
    16f4:	54000bca 	b.ge	186c <luaD_precall+0x26c>  // b.tcont
prepCallInfo():
/home/ubuntu/lunatik/lua/ldo.c:504 (discriminator 6)
  CallInfo *ci = L->ci = next_ci(L);  /* new frame */
    16f8:	f9401260 	ldr	x0, [x19, #32]
luaD_precall():
/home/ubuntu/lunatik/lua/ldo.c:604 (discriminator 6)
      L->ci = ci = prepCallInfo(L, func, nresults, 0, func + 1 + fsize);
    16fc:	91000718 	add	x24, x24, #0x1
    1700:	8b1812b8 	add	x24, x21, x24, lsl #4
prepCallInfo():
/home/ubuntu/lunatik/lua/ldo.c:504 (discriminator 6)
  CallInfo *ci = L->ci = next_ci(L);  /* new frame */
    1704:	f9400c00 	ldr	x0, [x0, #24]
    1708:	b4000a60 	cbz	x0, 1854 <luaD_precall+0x254>
/home/ubuntu/lunatik/lua/ldo.c:508
  ci->top.p = top;
    170c:	a9006015 	stp	x21, x24, [x0]
/home/ubuntu/lunatik/lua/ldo.c:506
  ci->nresults = nret;
    1710:	79007816 	strh	w22, [x0, #60]
/home/ubuntu/lunatik/lua/ldo.c:507
  ci->callstatus = mask;
    1714:	79007c1f 	strh	wzr, [x0, #62]
luaD_precall():
/home/ubuntu/lunatik/lua/ldo.c:604
      L->ci = ci = prepCallInfo(L, func, nresults, 0, func + 1 + fsize);
    1718:	f9001260 	str	x0, [x19, #32]
/home/ubuntu/lunatik/lua/ldo.c:605
      ci->u.l.savedpc = p->code;  /* starting point */
    171c:	f9402321 	ldr	x1, [x25, #64]
    1720:	f9001001 	str	x1, [x0, #32]
/home/ubuntu/lunatik/lua/ldo.c:606
      for (; narg < nfixparams; narg++)
    1724:	6b17029f 	cmp	w20, w23
    1728:	5400012a 	b.ge	174c <luaD_precall+0x14c>  // b.tcont
    172c:	d503201f 	nop
/home/ubuntu/lunatik/lua/ldo.c:607 (discriminator 2)
        setnilvalue(s2v(L->top.p++));  /* complete missing arguments */
    1730:	f9400a61 	ldr	x1, [x19, #16]
/home/ubuntu/lunatik/lua/ldo.c:606 (discriminator 2)
      for (; narg < nfixparams; narg++)
    1734:	11000694 	add	w20, w20, #0x1
/home/ubuntu/lunatik/lua/ldo.c:607 (discriminator 2)
        setnilvalue(s2v(L->top.p++));  /* complete missing arguments */
    1738:	91004022 	add	x2, x1, #0x10
    173c:	f9000a62 	str	x2, [x19, #16]
    1740:	3900203f 	strb	wzr, [x1, #8]
/home/ubuntu/lunatik/lua/ldo.c:606 (discriminator 2)
      for (; narg < nfixparams; narg++)
    1744:	6b1402ff 	cmp	w23, w20
    1748:	54ffff41 	b.ne	1730 <luaD_precall+0x130>  // b.any
/home/ubuntu/lunatik/lua/ldo.c:617
}
    174c:	f85f8e5e 	ldr	x30, [x18, #-8]!
    1750:	a94153f3 	ldp	x19, x20, [sp, #16]
    1754:	a9425bf5 	ldp	x21, x22, [sp, #32]
    1758:	a94363f7 	ldp	x23, x24, [sp, #48]
    175c:	a9446bf9 	ldp	x25, x26, [sp, #64]
    1760:	f84507fd 	ldr	x29, [sp], #80
    1764:	d50323bf 	autiasp
    1768:	d2800001 	mov	x1, #0x0                   	// #0
    176c:	d2800002 	mov	x2, #0x0                   	// #0
    1770:	d2800003 	mov	x3, #0x0                   	// #0
    1774:	d2800004 	mov	x4, #0x0                   	// #0
    1778:	d2800010 	mov	x16, #0x0                   	// #0
    177c:	d2800011 	mov	x17, #0x0                   	// #0
    1780:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:592
      precallC(L, func, nresults, clCvalue(s2v(func))->f);
    1784:	f94002a2 	ldr	x2, [x21]
precallC():
/home/ubuntu/lunatik/lua/ldo.c:520
  checkstackGCp(L, LUA_MINSTACK, func);  /* ensure minimum stack size */
    1788:	f9400a60 	ldr	x0, [x19, #16]
    178c:	f9401661 	ldr	x1, [x19, #40]
luaD_precall():
/home/ubuntu/lunatik/lua/ldo.c:592
      precallC(L, func, nresults, clCvalue(s2v(func))->f);
    1790:	f9400c58 	ldr	x24, [x2, #24]
precallC():
/home/ubuntu/lunatik/lua/ldo.c:520
  checkstackGCp(L, LUA_MINSTACK, func);  /* ensure minimum stack size */
    1794:	cb000021 	sub	x1, x1, x0
    1798:	f105003f 	cmp	x1, #0x140
    179c:	54fff76d 	b.le	1688 <luaD_precall+0x88>
prepCallInfo():
/home/ubuntu/lunatik/lua/ldo.c:504
  CallInfo *ci = L->ci = next_ci(L);  /* new frame */
    17a0:	f9401261 	ldr	x1, [x19, #32]
precallC():
/home/ubuntu/lunatik/lua/ldo.c:521
  L->ci = ci = prepCallInfo(L, func, nresults, CIST_C,
    17a4:	91050017 	add	x23, x0, #0x140
prepCallInfo():
/home/ubuntu/lunatik/lua/ldo.c:504
  CallInfo *ci = L->ci = next_ci(L);  /* new frame */
    17a8:	f9400c34 	ldr	x20, [x1, #24]
    17ac:	b4000394 	cbz	x20, 181c <luaD_precall+0x21c>
/home/ubuntu/lunatik/lua/ldo.c:507
  ci->callstatus = mask;
    17b0:	52800040 	mov	w0, #0x2                   	// #2
/home/ubuntu/lunatik/lua/ldo.c:508
  ci->top.p = top;
    17b4:	a9005e95 	stp	x21, x23, [x20]
/home/ubuntu/lunatik/lua/ldo.c:506
  ci->nresults = nret;
    17b8:	79007a96 	strh	w22, [x20, #60]
/home/ubuntu/lunatik/lua/ldo.c:507
  ci->callstatus = mask;
    17bc:	79007e80 	strh	w0, [x20, #62]
precallC():
/home/ubuntu/lunatik/lua/ldo.c:521
  L->ci = ci = prepCallInfo(L, func, nresults, CIST_C,
    17c0:	f9001274 	str	x20, [x19, #32]
/home/ubuntu/lunatik/lua/ldo.c:524
  if (l_unlikely(L->hookmask & LUA_MASKCALL)) {
    17c4:	b940c260 	ldr	w0, [x19, #192]
    17c8:	37000320 	tbnz	w0, #0, 182c <luaD_precall+0x22c>
/home/ubuntu/lunatik/lua/ldo.c:529
  n = (*f)(L);  /* do the actual call */
    17cc:	aa1303e0 	mov	x0, x19
    17d0:	d63f0300 	blr	x24
/home/ubuntu/lunatik/lua/ldo.c:532
  luaD_poscall(L, ci, n);
    17d4:	aa1403e1 	mov	x1, x20
    17d8:	2a0003e2 	mov	w2, w0
    17dc:	aa1303e0 	mov	x0, x19
    17e0:	94000000 	bl	f18 <luaD_poscall>
			17e0: R_AARCH64_CALL26	luaD_poscall
luaD_precall():
/home/ubuntu/lunatik/lua/ldo.c:617
}
    17e4:	f85f8e5e 	ldr	x30, [x18, #-8]!
/home/ubuntu/lunatik/lua/ldo.c:593
      return NULL;
    17e8:	d2800000 	mov	x0, #0x0                   	// #0
/home/ubuntu/lunatik/lua/ldo.c:617
}
    17ec:	a94153f3 	ldp	x19, x20, [sp, #16]
    17f0:	a9425bf5 	ldp	x21, x22, [sp, #32]
    17f4:	a94363f7 	ldp	x23, x24, [sp, #48]
    17f8:	f84507fd 	ldr	x29, [sp], #80
    17fc:	d50323bf 	autiasp
    1800:	d2800001 	mov	x1, #0x0                   	// #0
    1804:	d2800002 	mov	x2, #0x0                   	// #0
    1808:	d2800003 	mov	x3, #0x0                   	// #0
    180c:	d2800004 	mov	x4, #0x0                   	// #0
    1810:	d2800010 	mov	x16, #0x0                   	// #0
    1814:	d2800011 	mov	x17, #0x0                   	// #0
    1818:	d65f03c0 	ret
prepCallInfo():
/home/ubuntu/lunatik/lua/ldo.c:504
  CallInfo *ci = L->ci = next_ci(L);  /* new frame */
    181c:	aa1303e0 	mov	x0, x19
    1820:	94000000 	bl	0 <luaE_extendCI>
			1820: R_AARCH64_CALL26	luaE_extendCI
    1824:	aa0003f4 	mov	x20, x0
    1828:	17ffffe2 	b	17b0 <luaD_precall+0x1b0>
precallC():
/home/ubuntu/lunatik/lua/ldo.c:525
    int narg = cast_int(L->top.p - func) - 1;
    182c:	f9400a64 	ldr	x4, [x19, #16]
/home/ubuntu/lunatik/lua/ldo.c:526
    luaD_hook(L, LUA_HOOKCALL, -1, 1, narg);
    1830:	12800002 	mov	w2, #0xffffffff            	// #-1
    1834:	aa1303e0 	mov	x0, x19
    1838:	52800023 	mov	w3, #0x1                   	// #1
/home/ubuntu/lunatik/lua/ldo.c:525
    int narg = cast_int(L->top.p - func) - 1;
    183c:	cb150084 	sub	x4, x4, x21
/home/ubuntu/lunatik/lua/ldo.c:526
    luaD_hook(L, LUA_HOOKCALL, -1, 1, narg);
    1840:	52800001 	mov	w1, #0x0                   	// #0
/home/ubuntu/lunatik/lua/ldo.c:525
    int narg = cast_int(L->top.p - func) - 1;
    1844:	9344fc84 	asr	x4, x4, #4
/home/ubuntu/lunatik/lua/ldo.c:526
    luaD_hook(L, LUA_HOOKCALL, -1, 1, narg);
    1848:	0b020084 	add	w4, w4, w2
    184c:	94000000 	bl	a20 <luaD_hook>
			184c: R_AARCH64_CALL26	luaD_hook
    1850:	17ffffdf 	b	17cc <luaD_precall+0x1cc>
prepCallInfo():
/home/ubuntu/lunatik/lua/ldo.c:504
  CallInfo *ci = L->ci = next_ci(L);  /* new frame */
    1854:	aa1303e0 	mov	x0, x19
    1858:	94000000 	bl	0 <luaE_extendCI>
			1858: R_AARCH64_CALL26	luaE_extendCI
    185c:	17ffffac 	b	170c <luaD_precall+0x10c>
precallC():
/home/ubuntu/lunatik/lua/ldo.c:520
  checkstackGCp(L, LUA_MINSTACK, func);  /* ensure minimum stack size */
    1860:	aa1303e0 	mov	x0, x19
    1864:	94000000 	bl	0 <luaC_step>
			1864: R_AARCH64_CALL26	luaC_step
    1868:	17ffff8e 	b	16a0 <luaD_precall+0xa0>
luaD_precall():
/home/ubuntu/lunatik/lua/ldo.c:603 (discriminator 1)
      checkstackGCp(L, fsize, func);
    186c:	f9400e61 	ldr	x1, [x19, #24]
    1870:	f9401a60 	ldr	x0, [x19, #48]
    1874:	f9400c21 	ldr	x1, [x1, #24]
    1878:	cb0002b5 	sub	x21, x21, x0
    187c:	f100003f 	cmp	x1, #0x0
    1880:	5400006d 	b.le	188c <luaD_precall+0x28c>
/home/ubuntu/lunatik/lua/ldo.c:603 (discriminator 3)
    1884:	aa1303e0 	mov	x0, x19
    1888:	94000000 	bl	0 <luaC_step>
			1888: R_AARCH64_CALL26	luaC_step
/home/ubuntu/lunatik/lua/ldo.c:603 (discriminator 5)
    188c:	2a1a03e1 	mov	w1, w26
    1890:	aa1303e0 	mov	x0, x19
    1894:	52800022 	mov	w2, #0x1                   	// #1
    1898:	94000000 	bl	730 <luaD_growstack>
			1898: R_AARCH64_CALL26	luaD_growstack
    189c:	f9401a60 	ldr	x0, [x19, #48]
    18a0:	8b150015 	add	x21, x0, x21
    18a4:	17ffff95 	b	16f8 <luaD_precall+0xf8>
    18a8:	d503201f 	nop
    18ac:	d503201f 	nop

00000000000018b0 <resume>:
resume():
/home/ubuntu/lunatik/lua/ldo.c:785
static void resume (lua_State *L, void *ud) {
    18b0:	d503201f 	nop
    18b4:	d503201f 	nop
    18b8:	d503233f 	paciasp
    18bc:	f800865e 	str	x30, [x18], #8
    18c0:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
    18c4:	910003fd 	mov	x29, sp
    18c8:	a90153f3 	stp	x19, x20, [sp, #16]
    18cc:	aa0003f3 	mov	x19, x0
/home/ubuntu/lunatik/lua/ldo.c:787
  StkId firstArg = L->top.p - n;  /* first argument */
    18d0:	f9400803 	ldr	x3, [x0, #16]
/home/ubuntu/lunatik/lua/ldo.c:789
  if (L->status == LUA_OK)  /* starting a coroutine? */
    18d4:	39402804 	ldrb	w4, [x0, #10]
/home/ubuntu/lunatik/lua/ldo.c:786
  int n = *(cast(int*, ud));  /* number of arguments */
    18d8:	b9400022 	ldr	w2, [x1]
/home/ubuntu/lunatik/lua/ldo.c:788
  CallInfo *ci = L->ci;
    18dc:	f9401014 	ldr	x20, [x0, #32]
/home/ubuntu/lunatik/lua/ldo.c:787
  StkId firstArg = L->top.p - n;  /* first argument */
    18e0:	cb22d061 	sub	x1, x3, w2, sxtw #4
/home/ubuntu/lunatik/lua/ldo.c:789
  if (L->status == LUA_OK)  /* starting a coroutine? */
    18e4:	34000404 	cbz	w4, 1964 <resume+0xb4>
/home/ubuntu/lunatik/lua/ldo.c:793
    L->status = LUA_OK;  /* mark that it is running (again) */
    18e8:	3900281f 	strb	wzr, [x0, #10]
/home/ubuntu/lunatik/lua/ldo.c:794
    if (isLua(ci)) {  /* yielded inside a hook? */
    18ec:	79407e83 	ldrh	w3, [x20, #62]
    18f0:	36080323 	tbz	w3, #1, 1954 <resume+0xa4>
/home/ubuntu/lunatik/lua/ldo.c:799
      if (ci->u.c.k != NULL) {  /* does it have a continuation function? */
    18f4:	f9401283 	ldr	x3, [x20, #32]
    18f8:	b40000a3 	cbz	x3, 190c <resume+0x5c>
/home/ubuntu/lunatik/lua/ldo.c:801
        n = (*ci->u.c.k)(L, LUA_YIELD, ci->u.c.ctx); /* call continuation */
    18fc:	f9401a82 	ldr	x2, [x20, #48]
    1900:	52800021 	mov	w1, #0x1                   	// #1
    1904:	d63f0060 	blr	x3
    1908:	2a0003e2 	mov	w2, w0
/home/ubuntu/lunatik/lua/ldo.c:805
      luaD_poscall(L, ci, n);  /* finish 'luaD_call' */
    190c:	aa1403e1 	mov	x1, x20
    1910:	aa1303e0 	mov	x0, x19
    1914:	94000000 	bl	f18 <luaD_poscall>
			1914: R_AARCH64_CALL26	luaD_poscall
/home/ubuntu/lunatik/lua/ldo.c:807
    unroll(L, NULL);  /* run continuation */
    1918:	aa1303e0 	mov	x0, x19
    191c:	d2800001 	mov	x1, #0x0                   	// #0
    1920:	97fffe0e 	bl	1158 <unroll>
/home/ubuntu/lunatik/lua/ldo.c:809
}
    1924:	f85f8e5e 	ldr	x30, [x18, #-8]!
    1928:	a94153f3 	ldp	x19, x20, [sp, #16]
    192c:	f84207fd 	ldr	x29, [sp], #32
    1930:	d50323bf 	autiasp
    1934:	d2800000 	mov	x0, #0x0                   	// #0
    1938:	d2800001 	mov	x1, #0x0                   	// #0
    193c:	d2800002 	mov	x2, #0x0                   	// #0
    1940:	d2800003 	mov	x3, #0x0                   	// #0
    1944:	d2800004 	mov	x4, #0x0                   	// #0
    1948:	d2800010 	mov	x16, #0x0                   	// #0
    194c:	d2800011 	mov	x17, #0x0                   	// #0
    1950:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:795
      L->top.p = firstArg;  /* discard arguments */
    1954:	f9000801 	str	x1, [x0, #16]
/home/ubuntu/lunatik/lua/ldo.c:796
      luaV_execute(L, ci);  /* just continue running Lua code */
    1958:	aa1403e1 	mov	x1, x20
    195c:	94000000 	bl	0 <luaV_execute>
			195c: R_AARCH64_CALL26	luaV_execute
    1960:	17ffffee 	b	1918 <resume+0x68>
ccall():
/home/ubuntu/lunatik/lua/ldo.c:631
  if (l_unlikely(getCcalls(L) >= LUAI_MAXCCALLS)) {
    1964:	79416002 	ldrh	w2, [x0, #176]
resume():
/home/ubuntu/lunatik/lua/ldo.c:790
    ccall(L, firstArg - 1, LUA_MULTRET, 0);  /* just call its body */
    1968:	d1004034 	sub	x20, x1, #0x10
ccall():
/home/ubuntu/lunatik/lua/ldo.c:631
  if (l_unlikely(getCcalls(L) >= LUAI_MAXCCALLS)) {
    196c:	71031c5f 	cmp	w2, #0xc7
    1970:	540002e8 	b.hi	19cc <resume+0x11c>  // b.pmore
/home/ubuntu/lunatik/lua/ldo.c:635
  if ((ci = luaD_precall(L, func, nResults)) != NULL) {  /* Lua function? */
    1974:	aa1403e1 	mov	x1, x20
    1978:	aa1303e0 	mov	x0, x19
    197c:	12800002 	mov	w2, #0xffffffff            	// #-1
    1980:	94000000 	bl	1600 <luaD_precall>
			1980: R_AARCH64_CALL26	luaD_precall
    1984:	aa0003e1 	mov	x1, x0
    1988:	b4fffce0 	cbz	x0, 1924 <resume+0x74>
/home/ubuntu/lunatik/lua/ldo.c:636
    ci->callstatus = CIST_FRESH;  /* mark that it is a "fresh" execute */
    198c:	52800080 	mov	w0, #0x4                   	// #4
    1990:	79007c20 	strh	w0, [x1, #62]
/home/ubuntu/lunatik/lua/ldo.c:637
    luaV_execute(L, ci);  /* call it */
    1994:	aa1303e0 	mov	x0, x19
    1998:	94000000 	bl	0 <luaV_execute>
			1998: R_AARCH64_CALL26	luaV_execute
resume():
/home/ubuntu/lunatik/lua/ldo.c:809
}
    199c:	f85f8e5e 	ldr	x30, [x18, #-8]!
    19a0:	a94153f3 	ldp	x19, x20, [sp, #16]
    19a4:	f84207fd 	ldr	x29, [sp], #32
    19a8:	d50323bf 	autiasp
    19ac:	d2800000 	mov	x0, #0x0                   	// #0
    19b0:	d2800001 	mov	x1, #0x0                   	// #0
    19b4:	d2800002 	mov	x2, #0x0                   	// #0
    19b8:	d2800003 	mov	x3, #0x0                   	// #0
    19bc:	d2800004 	mov	x4, #0x0                   	// #0
    19c0:	d2800010 	mov	x16, #0x0                   	// #0
    19c4:	d2800011 	mov	x17, #0x0                   	// #0
    19c8:	d65f03c0 	ret
ccall():
/home/ubuntu/lunatik/lua/ldo.c:632
    checkstackp(L, 0, func);  /* free any use of EXTRA_STACK */
    19cc:	f9401401 	ldr	x1, [x0, #40]
    19d0:	cb030021 	sub	x1, x1, x3
    19d4:	f100003f 	cmp	x1, #0x0
    19d8:	5400008d 	b.le	19e8 <resume+0x138>
/home/ubuntu/lunatik/lua/ldo.c:633
    luaE_checkcstack(L);
    19dc:	aa1303e0 	mov	x0, x19
    19e0:	94000000 	bl	0 <luaE_checkcstack>
			19e0: R_AARCH64_CALL26	luaE_checkcstack
    19e4:	17ffffe4 	b	1974 <resume+0xc4>
/home/ubuntu/lunatik/lua/ldo.c:632
    checkstackp(L, 0, func);  /* free any use of EXTRA_STACK */
    19e8:	f9401803 	ldr	x3, [x0, #48]
    19ec:	52800022 	mov	w2, #0x1                   	// #1
    19f0:	52800001 	mov	w1, #0x0                   	// #0
    19f4:	cb030294 	sub	x20, x20, x3
    19f8:	94000000 	bl	730 <luaD_growstack>
			19f8: R_AARCH64_CALL26	luaD_growstack
    19fc:	f9401a60 	ldr	x0, [x19, #48]
    1a00:	8b140014 	add	x20, x0, x20
    1a04:	17fffff6 	b	19dc <resume+0x12c>
resume():
/home/ubuntu/lunatik/lua/ldo.c:632
    1a08:	d503201f 	nop
    1a0c:	d503201f 	nop

0000000000001a10 <luaD_call>:
luaD_call():
/home/ubuntu/lunatik/lua/ldo.c:646
void luaD_call (lua_State *L, StkId func, int nResults) {
    1a10:	d503201f 	nop
    1a14:	d503201f 	nop
    1a18:	d503233f 	paciasp
    1a1c:	f800865e 	str	x30, [x18], #8
    1a20:	a9bd7bfd 	stp	x29, x30, [sp, #-48]!
    1a24:	910003fd 	mov	x29, sp
    1a28:	a90153f3 	stp	x19, x20, [sp, #16]
    1a2c:	aa0003f3 	mov	x19, x0
    1a30:	aa0103f4 	mov	x20, x1
    1a34:	f90013f5 	str	x21, [sp, #32]
    1a38:	2a0203f5 	mov	w21, w2
ccall():
/home/ubuntu/lunatik/lua/ldo.c:630
  L->nCcalls += inc;
    1a3c:	b940b003 	ldr	w3, [x0, #176]
    1a40:	11000463 	add	w3, w3, #0x1
    1a44:	b900b003 	str	w3, [x0, #176]
/home/ubuntu/lunatik/lua/ldo.c:631
  if (l_unlikely(getCcalls(L) >= LUAI_MAXCCALLS)) {
    1a48:	12003c63 	and	w3, w3, #0xffff
    1a4c:	71031c7f 	cmp	w3, #0xc7
    1a50:	54000348 	b.hi	1ab8 <luaD_call+0xa8>  // b.pmore
/home/ubuntu/lunatik/lua/ldo.c:635
  if ((ci = luaD_precall(L, func, nResults)) != NULL) {  /* Lua function? */
    1a54:	aa1403e1 	mov	x1, x20
    1a58:	2a1503e2 	mov	w2, w21
    1a5c:	aa1303e0 	mov	x0, x19
    1a60:	94000000 	bl	1600 <luaD_precall>
			1a60: R_AARCH64_CALL26	luaD_precall
    1a64:	aa0003e1 	mov	x1, x0
    1a68:	b40000a0 	cbz	x0, 1a7c <luaD_call+0x6c>
/home/ubuntu/lunatik/lua/ldo.c:636
    ci->callstatus = CIST_FRESH;  /* mark that it is a "fresh" execute */
    1a6c:	52800080 	mov	w0, #0x4                   	// #4
    1a70:	79007c20 	strh	w0, [x1, #62]
/home/ubuntu/lunatik/lua/ldo.c:637
    luaV_execute(L, ci);  /* call it */
    1a74:	aa1303e0 	mov	x0, x19
    1a78:	94000000 	bl	0 <luaV_execute>
			1a78: R_AARCH64_CALL26	luaV_execute
/home/ubuntu/lunatik/lua/ldo.c:639
  L->nCcalls -= inc;
    1a7c:	b940b260 	ldr	w0, [x19, #176]
    1a80:	51000400 	sub	w0, w0, #0x1
    1a84:	b900b260 	str	w0, [x19, #176]
luaD_call():
/home/ubuntu/lunatik/lua/ldo.c:648
}
    1a88:	f85f8e5e 	ldr	x30, [x18, #-8]!
    1a8c:	a94153f3 	ldp	x19, x20, [sp, #16]
    1a90:	f94013f5 	ldr	x21, [sp, #32]
    1a94:	f84307fd 	ldr	x29, [sp], #48
    1a98:	d50323bf 	autiasp
    1a9c:	d2800000 	mov	x0, #0x0                   	// #0
    1aa0:	d2800001 	mov	x1, #0x0                   	// #0
    1aa4:	d2800002 	mov	x2, #0x0                   	// #0
    1aa8:	d2800003 	mov	x3, #0x0                   	// #0
    1aac:	d2800010 	mov	x16, #0x0                   	// #0
    1ab0:	d2800011 	mov	x17, #0x0                   	// #0
    1ab4:	d65f03c0 	ret
ccall():
/home/ubuntu/lunatik/lua/ldo.c:632
    checkstackp(L, 0, func);  /* free any use of EXTRA_STACK */
    1ab8:	f9400802 	ldr	x2, [x0, #16]
    1abc:	f9401401 	ldr	x1, [x0, #40]
    1ac0:	cb020021 	sub	x1, x1, x2
    1ac4:	f100003f 	cmp	x1, #0x0
    1ac8:	5400008d 	b.le	1ad8 <luaD_call+0xc8>
/home/ubuntu/lunatik/lua/ldo.c:633
    luaE_checkcstack(L);
    1acc:	aa1303e0 	mov	x0, x19
    1ad0:	94000000 	bl	0 <luaE_checkcstack>
			1ad0: R_AARCH64_CALL26	luaE_checkcstack
    1ad4:	17ffffe0 	b	1a54 <luaD_call+0x44>
/home/ubuntu/lunatik/lua/ldo.c:632
    checkstackp(L, 0, func);  /* free any use of EXTRA_STACK */
    1ad8:	f9401803 	ldr	x3, [x0, #48]
    1adc:	52800022 	mov	w2, #0x1                   	// #1
    1ae0:	52800001 	mov	w1, #0x0                   	// #0
    1ae4:	cb030294 	sub	x20, x20, x3
    1ae8:	94000000 	bl	730 <luaD_growstack>
			1ae8: R_AARCH64_CALL26	luaD_growstack
    1aec:	f9401a60 	ldr	x0, [x19, #48]
    1af0:	8b140014 	add	x20, x0, x20
    1af4:	17fffff6 	b	1acc <luaD_call+0xbc>
luaD_call():
/home/ubuntu/lunatik/lua/ldo.c:632
    1af8:	d503201f 	nop
    1afc:	d503201f 	nop

0000000000001b00 <luaD_callnoyield>:
luaD_callnoyield():
/home/ubuntu/lunatik/lua/ldo.c:654
void luaD_callnoyield (lua_State *L, StkId func, int nResults) {
    1b00:	d503201f 	nop
    1b04:	d503201f 	nop
    1b08:	d503233f 	paciasp
    1b0c:	f800865e 	str	x30, [x18], #8
    1b10:	a9bd7bfd 	stp	x29, x30, [sp, #-48]!
    1b14:	910003fd 	mov	x29, sp
    1b18:	a90153f3 	stp	x19, x20, [sp, #16]
    1b1c:	aa0003f3 	mov	x19, x0
    1b20:	aa0103f4 	mov	x20, x1
    1b24:	f90013f5 	str	x21, [sp, #32]
    1b28:	2a0203f5 	mov	w21, w2
ccall():
/home/ubuntu/lunatik/lua/ldo.c:630
  L->nCcalls += inc;
    1b2c:	320083e2 	mov	w2, #0x10001               	// #65537
    1b30:	b940b003 	ldr	w3, [x0, #176]
    1b34:	0b020063 	add	w3, w3, w2
    1b38:	b900b003 	str	w3, [x0, #176]
/home/ubuntu/lunatik/lua/ldo.c:631
  if (l_unlikely(getCcalls(L) >= LUAI_MAXCCALLS)) {
    1b3c:	12003c63 	and	w3, w3, #0xffff
    1b40:	71031c7f 	cmp	w3, #0xc7
    1b44:	54000368 	b.hi	1bb0 <luaD_callnoyield+0xb0>  // b.pmore
/home/ubuntu/lunatik/lua/ldo.c:635
  if ((ci = luaD_precall(L, func, nResults)) != NULL) {  /* Lua function? */
    1b48:	aa1403e1 	mov	x1, x20
    1b4c:	2a1503e2 	mov	w2, w21
    1b50:	aa1303e0 	mov	x0, x19
    1b54:	94000000 	bl	1600 <luaD_precall>
			1b54: R_AARCH64_CALL26	luaD_precall
    1b58:	aa0003e1 	mov	x1, x0
    1b5c:	b40000a0 	cbz	x0, 1b70 <luaD_callnoyield+0x70>
/home/ubuntu/lunatik/lua/ldo.c:636
    ci->callstatus = CIST_FRESH;  /* mark that it is a "fresh" execute */
    1b60:	52800080 	mov	w0, #0x4                   	// #4
    1b64:	79007c20 	strh	w0, [x1, #62]
/home/ubuntu/lunatik/lua/ldo.c:637
    luaV_execute(L, ci);  /* call it */
    1b68:	aa1303e0 	mov	x0, x19
    1b6c:	94000000 	bl	0 <luaV_execute>
			1b6c: R_AARCH64_CALL26	luaV_execute
/home/ubuntu/lunatik/lua/ldo.c:639
  L->nCcalls -= inc;
    1b70:	b940b260 	ldr	w0, [x19, #176]
    1b74:	12a00021 	mov	w1, #0xfffeffff            	// #-65537
    1b78:	0b010000 	add	w0, w0, w1
    1b7c:	b900b260 	str	w0, [x19, #176]
luaD_callnoyield():
/home/ubuntu/lunatik/lua/ldo.c:656
}
    1b80:	f85f8e5e 	ldr	x30, [x18, #-8]!
    1b84:	a94153f3 	ldp	x19, x20, [sp, #16]
    1b88:	f94013f5 	ldr	x21, [sp, #32]
    1b8c:	f84307fd 	ldr	x29, [sp], #48
    1b90:	d50323bf 	autiasp
    1b94:	d2800000 	mov	x0, #0x0                   	// #0
    1b98:	d2800001 	mov	x1, #0x0                   	// #0
    1b9c:	d2800002 	mov	x2, #0x0                   	// #0
    1ba0:	d2800003 	mov	x3, #0x0                   	// #0
    1ba4:	d2800010 	mov	x16, #0x0                   	// #0
    1ba8:	d2800011 	mov	x17, #0x0                   	// #0
    1bac:	d65f03c0 	ret
ccall():
/home/ubuntu/lunatik/lua/ldo.c:632
    checkstackp(L, 0, func);  /* free any use of EXTRA_STACK */
    1bb0:	f9400802 	ldr	x2, [x0, #16]
    1bb4:	f9401401 	ldr	x1, [x0, #40]
    1bb8:	cb020021 	sub	x1, x1, x2
    1bbc:	f100003f 	cmp	x1, #0x0
    1bc0:	5400008d 	b.le	1bd0 <luaD_callnoyield+0xd0>
/home/ubuntu/lunatik/lua/ldo.c:633
    luaE_checkcstack(L);
    1bc4:	aa1303e0 	mov	x0, x19
    1bc8:	94000000 	bl	0 <luaE_checkcstack>
			1bc8: R_AARCH64_CALL26	luaE_checkcstack
    1bcc:	17ffffdf 	b	1b48 <luaD_callnoyield+0x48>
/home/ubuntu/lunatik/lua/ldo.c:632
    checkstackp(L, 0, func);  /* free any use of EXTRA_STACK */
    1bd0:	f9401803 	ldr	x3, [x0, #48]
    1bd4:	52800022 	mov	w2, #0x1                   	// #1
    1bd8:	52800001 	mov	w1, #0x0                   	// #0
    1bdc:	cb030294 	sub	x20, x20, x3
    1be0:	94000000 	bl	730 <luaD_growstack>
			1be0: R_AARCH64_CALL26	luaD_growstack
    1be4:	f9401a60 	ldr	x0, [x19, #48]
    1be8:	8b140014 	add	x20, x0, x20
    1bec:	17fffff6 	b	1bc4 <luaD_callnoyield+0xc4>
luaD_callnoyield():
/home/ubuntu/lunatik/lua/ldo.c:632
    1bf0:	d503201f 	nop
    1bf4:	d503201f 	nop

0000000000001bf8 <lua_resume>:
lua_resume():
/home/ubuntu/lunatik/lua/ldo.c:832
                                      int *nresults) {
    1bf8:	d503201f 	nop
    1bfc:	d503201f 	nop
    1c00:	d503233f 	paciasp
    1c04:	f800865e 	str	x30, [x18], #8
    1c08:	a9bc7bfd 	stp	x29, x30, [sp, #-64]!
    1c0c:	910003fd 	mov	x29, sp
    1c10:	a90153f3 	stp	x19, x20, [sp, #16]
    1c14:	aa0003f4 	mov	x20, x0
    1c18:	a9025bf5 	stp	x21, x22, [sp, #32]
    1c1c:	aa0303f5 	mov	x21, x3
/home/ubuntu/lunatik/lua/ldo.c:835
  if (L->status == LUA_OK) {  /* may be starting a coroutine */
    1c20:	39402803 	ldrb	w3, [x0, #10]
/home/ubuntu/lunatik/lua/ldo.c:832
                                      int *nresults) {
    1c24:	b9003fe2 	str	w2, [sp, #60]
/home/ubuntu/lunatik/lua/ldo.c:835
  if (L->status == LUA_OK) {  /* may be starting a coroutine */
    1c28:	350005e3 	cbnz	w3, 1ce4 <lua_resume+0xec>
/home/ubuntu/lunatik/lua/ldo.c:836
    if (L->ci != &L->base_ci)  /* not in base level? */
    1c2c:	f9401005 	ldr	x5, [x0, #32]
    1c30:	91018003 	add	x3, x0, #0x60
resume_error():
/home/ubuntu/lunatik/lua/ldo.c:770
  L->top.p -= narg;  /* remove args from the stack */
    1c34:	f9400804 	ldr	x4, [x0, #16]
lua_resume():
/home/ubuntu/lunatik/lua/ldo.c:836
    if (L->ci != &L->base_ci)  /* not in base level? */
    1c38:	eb0300bf 	cmp	x5, x3
    1c3c:	54000661 	b.ne	1d08 <lua_resume+0x110>  // b.any
/home/ubuntu/lunatik/lua/ldo.c:838
    else if (L->top.p - (L->ci->func.p + 1) == nargs)  /* no function? */
    1c40:	f94000a3 	ldr	x3, [x5]
    1c44:	91004063 	add	x3, x3, #0x10
    1c48:	cb030083 	sub	x3, x4, x3
    1c4c:	9344fc63 	asr	x3, x3, #4
    1c50:	eb22c07f 	cmp	x3, w2, sxtw
    1c54:	54000f00 	b.eq	1e34 <lua_resume+0x23c>  // b.none
/home/ubuntu/lunatik/lua/ldo.c:843
  L->nCcalls = (from) ? getCcalls(from) : 0;
    1c58:	b4000621 	cbz	x1, 1d1c <lua_resume+0x124>
/home/ubuntu/lunatik/lua/ldo.c:843 (discriminator 1)
    1c5c:	79416020 	ldrh	w0, [x1, #176]
    1c60:	b900b280 	str	w0, [x20, #176]
/home/ubuntu/lunatik/lua/ldo.c:844 (discriminator 1)
  if (getCcalls(L) >= LUAI_MAXCCALLS)
    1c64:	71031c1f 	cmp	w0, #0xc7
    1c68:	54000dc9 	b.ls	1e20 <lua_resume+0x228>  // b.plast
resume_error():
/home/ubuntu/lunatik/lua/ldo.c:770
  L->top.p -= narg;  /* remove args from the stack */
    1c6c:	f9400a82 	ldr	x2, [x20, #16]
/home/ubuntu/lunatik/lua/ldo.c:771
  setsvalue2s(L, L->top.p, luaS_new(L, msg));  /* push error message */
    1c70:	90000001 	adrp	x1, 0 <correctstack-0x8>
			1c70: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.8+0xb0
/home/ubuntu/lunatik/lua/ldo.c:770
  L->top.p -= narg;  /* remove args from the stack */
    1c74:	b9803ff3 	ldrsw	x19, [sp, #60]
/home/ubuntu/lunatik/lua/ldo.c:771
  setsvalue2s(L, L->top.p, luaS_new(L, msg));  /* push error message */
    1c78:	91000021 	add	x1, x1, #0x0
			1c78: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.8+0xb0
    1c7c:	aa1403e0 	mov	x0, x20
/home/ubuntu/lunatik/lua/ldo.c:770
  L->top.p -= narg;  /* remove args from the stack */
    1c80:	cb131053 	sub	x19, x2, x19, lsl #4
    1c84:	f9000a93 	str	x19, [x20, #16]
/home/ubuntu/lunatik/lua/ldo.c:771
  setsvalue2s(L, L->top.p, luaS_new(L, msg));  /* push error message */
    1c88:	94000000 	bl	0 <luaS_new>
			1c88: R_AARCH64_CALL26	luaS_new
    1c8c:	f9000260 	str	x0, [x19]
    1c90:	39402000 	ldrb	w0, [x0, #8]
    1c94:	321a0000 	orr	w0, w0, #0x40
    1c98:	39002260 	strb	w0, [x19, #8]
lua_resume():
/home/ubuntu/lunatik/lua/ldo.c:837
      return resume_error(L, "cannot resume non-suspended coroutine", nargs);
    1c9c:	52800053 	mov	w19, #0x2                   	// #2
resume_error():
/home/ubuntu/lunatik/lua/ldo.c:772
  api_incr_top(L);
    1ca0:	f9400a80 	ldr	x0, [x20, #16]
    1ca4:	91004000 	add	x0, x0, #0x10
    1ca8:	f9000a80 	str	x0, [x20, #16]
lua_resume():
/home/ubuntu/lunatik/lua/ldo.c:863
}
    1cac:	2a1303e0 	mov	w0, w19
    1cb0:	a94153f3 	ldp	x19, x20, [sp, #16]
    1cb4:	a9425bf5 	ldp	x21, x22, [sp, #32]
    1cb8:	f85f8e5e 	ldr	x30, [x18, #-8]!
    1cbc:	f84407fd 	ldr	x29, [sp], #64
    1cc0:	d50323bf 	autiasp
    1cc4:	d2800001 	mov	x1, #0x0                   	// #0
    1cc8:	d2800002 	mov	x2, #0x0                   	// #0
    1ccc:	d2800003 	mov	x3, #0x0                   	// #0
    1cd0:	d2800004 	mov	x4, #0x0                   	// #0
    1cd4:	d2800005 	mov	x5, #0x0                   	// #0
    1cd8:	d2800010 	mov	x16, #0x0                   	// #0
    1cdc:	d2800011 	mov	x17, #0x0                   	// #0
    1ce0:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:841
  else if (L->status != LUA_YIELD)  /* ended with errors? */
    1ce4:	7100047f 	cmp	w3, #0x1
    1ce8:	54fffb80 	b.eq	1c58 <lua_resume+0x60>  // b.none
resume_error():
/home/ubuntu/lunatik/lua/ldo.c:770
  L->top.p -= narg;  /* remove args from the stack */
    1cec:	f9400802 	ldr	x2, [x0, #16]
/home/ubuntu/lunatik/lua/ldo.c:771
  setsvalue2s(L, L->top.p, luaS_new(L, msg));  /* push error message */
    1cf0:	90000001 	adrp	x1, 0 <correctstack-0x8>
			1cf0: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.8+0x90
/home/ubuntu/lunatik/lua/ldo.c:770
  L->top.p -= narg;  /* remove args from the stack */
    1cf4:	b9803ff3 	ldrsw	x19, [sp, #60]
/home/ubuntu/lunatik/lua/ldo.c:771
  setsvalue2s(L, L->top.p, luaS_new(L, msg));  /* push error message */
    1cf8:	91000021 	add	x1, x1, #0x0
			1cf8: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.8+0x90
/home/ubuntu/lunatik/lua/ldo.c:770
  L->top.p -= narg;  /* remove args from the stack */
    1cfc:	cb131053 	sub	x19, x2, x19, lsl #4
    1d00:	f9000813 	str	x19, [x0, #16]
/home/ubuntu/lunatik/lua/ldo.c:771
  setsvalue2s(L, L->top.p, luaS_new(L, msg));  /* push error message */
    1d04:	17ffffe1 	b	1c88 <lua_resume+0x90>
/home/ubuntu/lunatik/lua/ldo.c:770
  L->top.p -= narg;  /* remove args from the stack */
    1d08:	cb22d093 	sub	x19, x4, w2, sxtw #4
/home/ubuntu/lunatik/lua/ldo.c:771
  setsvalue2s(L, L->top.p, luaS_new(L, msg));  /* push error message */
    1d0c:	90000001 	adrp	x1, 0 <correctstack-0x8>
			1d0c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.8+0x68
    1d10:	91000021 	add	x1, x1, #0x0
			1d10: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.8+0x68
/home/ubuntu/lunatik/lua/ldo.c:770
  L->top.p -= narg;  /* remove args from the stack */
    1d14:	f9000813 	str	x19, [x0, #16]
/home/ubuntu/lunatik/lua/ldo.c:771
  setsvalue2s(L, L->top.p, luaS_new(L, msg));  /* push error message */
    1d18:	17ffffdc 	b	1c88 <lua_resume+0x90>
lua_resume():
/home/ubuntu/lunatik/lua/ldo.c:771
    1d1c:	52800020 	mov	w0, #0x1                   	// #1
/home/ubuntu/lunatik/lua/ldo.c:846
  L->nCcalls++;
    1d20:	b900b280 	str	w0, [x20, #176]
/home/ubuntu/lunatik/lua/ldo.c:849
  status = luaD_rawrunprotected(L, resume, &nargs);
    1d24:	9100f3e2 	add	x2, sp, #0x3c
    1d28:	aa1403e0 	mov	x0, x20
    1d2c:	90000001 	adrp	x1, 0 <correctstack-0x8>
			1d2c: R_AARCH64_ADR_PREL_PG_HI21	.text+0x18b0
precover():
/home/ubuntu/lunatik/lua/ldo.c:825
    status = luaD_rawrunprotected(L, unroll, NULL);
    1d30:	90000016 	adrp	x22, 0 <correctstack-0x8>
			1d30: R_AARCH64_ADR_PREL_PG_HI21	.text+0x1158
lua_resume():
/home/ubuntu/lunatik/lua/ldo.c:849
  status = luaD_rawrunprotected(L, resume, &nargs);
    1d34:	91000021 	add	x1, x1, #0x0
			1d34: R_AARCH64_ADD_ABS_LO12_NC	.text+0x18b0
precover():
/home/ubuntu/lunatik/lua/ldo.c:825
    status = luaD_rawrunprotected(L, unroll, NULL);
    1d38:	910002d6 	add	x22, x22, #0x0
			1d38: R_AARCH64_ADD_ABS_LO12_NC	.text+0x1158
lua_resume():
/home/ubuntu/lunatik/lua/ldo.c:849
  status = luaD_rawrunprotected(L, resume, &nargs);
    1d3c:	94000000 	bl	498 <luaD_rawrunprotected>
			1d3c: R_AARCH64_CALL26	luaD_rawrunprotected
    1d40:	2a0003f3 	mov	w19, w0
precover():
/home/ubuntu/lunatik/lua/ldo.c:822
  while (errorstatus(status) && (ci = findpcall(L)) != NULL) {
    1d44:	7100041f 	cmp	w0, #0x1
    1d48:	540002ad 	b.le	1d9c <lua_resume+0x1a4>
    1d4c:	d503201f 	nop
findpcall():
/home/ubuntu/lunatik/lua/ldo.c:756
  for (ci = L->ci; ci != NULL; ci = ci->previous) {  /* search for a pcall */
    1d50:	f9401284 	ldr	x4, [x20, #32]
    1d54:	b5000084 	cbnz	x4, 1d64 <lua_resume+0x16c>
    1d58:	14000028 	b	1df8 <lua_resume+0x200>
    1d5c:	f9400884 	ldr	x4, [x4, #16]
    1d60:	b40004c4 	cbz	x4, 1df8 <lua_resume+0x200>
/home/ubuntu/lunatik/lua/ldo.c:757
    if (ci->callstatus & CIST_YPCALL)
    1d64:	79407c81 	ldrh	w1, [x4, #62]
    1d68:	3627ffa1 	tbz	w1, #4, 1d5c <lua_resume+0x164>
precover():
/home/ubuntu/lunatik/lua/ldo.c:823
    L->ci = ci;  /* go down to recovery functions */
    1d6c:	f9001284 	str	x4, [x20, #32]
/home/ubuntu/lunatik/lua/ldo.c:825
    status = luaD_rawrunprotected(L, unroll, NULL);
    1d70:	aa1603e1 	mov	x1, x22
    1d74:	aa1403e0 	mov	x0, x20
    1d78:	d2800002 	mov	x2, #0x0                   	// #0
/home/ubuntu/lunatik/lua/ldo.c:824
    setcistrecst(ci, status);  /* status to finish 'pcall' */
    1d7c:	79407c85 	ldrh	w5, [x4, #62]
    1d80:	121370a5 	and	w5, w5, #0xffffe3ff
    1d84:	2a1328b3 	orr	w19, w5, w19, lsl #10
    1d88:	79007c93 	strh	w19, [x4, #62]
/home/ubuntu/lunatik/lua/ldo.c:825
    status = luaD_rawrunprotected(L, unroll, NULL);
    1d8c:	94000000 	bl	498 <luaD_rawrunprotected>
			1d8c: R_AARCH64_CALL26	luaD_rawrunprotected
    1d90:	2a0003f3 	mov	w19, w0
/home/ubuntu/lunatik/lua/ldo.c:822
  while (errorstatus(status) && (ci = findpcall(L)) != NULL) {
    1d94:	7100041f 	cmp	w0, #0x1
    1d98:	54fffdcc 	b.gt	1d50 <lua_resume+0x158>
lua_resume():
/home/ubuntu/lunatik/lua/ldo.c:859
  *nresults = (status == LUA_YIELD) ? L->ci->u2.nyield
    1d9c:	f9401280 	ldr	x0, [x20, #32]
/home/ubuntu/lunatik/lua/ldo.c:860
                                    : cast_int(L->top.p - (L->ci->func.p + 1));
    1da0:	7100067f 	cmp	w19, #0x1
    1da4:	54000420 	b.eq	1e28 <lua_resume+0x230>  // b.none
/home/ubuntu/lunatik/lua/ldo.c:860 (discriminator 2)
    1da8:	f9400001 	ldr	x1, [x0]
    1dac:	f9400a80 	ldr	x0, [x20, #16]
    1db0:	91004021 	add	x1, x1, #0x10
    1db4:	cb010000 	sub	x0, x0, x1
    1db8:	d3448c00 	ubfx	x0, x0, #4, #32
/home/ubuntu/lunatik/lua/ldo.c:859 (discriminator 2)
  *nresults = (status == LUA_YIELD) ? L->ci->u2.nyield
    1dbc:	b90002a0 	str	w0, [x21]
/home/ubuntu/lunatik/lua/ldo.c:863
}
    1dc0:	a9425bf5 	ldp	x21, x22, [sp, #32]
    1dc4:	2a1303e0 	mov	w0, w19
    1dc8:	a94153f3 	ldp	x19, x20, [sp, #16]
    1dcc:	f85f8e5e 	ldr	x30, [x18, #-8]!
    1dd0:	f84407fd 	ldr	x29, [sp], #64
    1dd4:	d50323bf 	autiasp
    1dd8:	d2800001 	mov	x1, #0x0                   	// #0
    1ddc:	d2800002 	mov	x2, #0x0                   	// #0
    1de0:	d2800003 	mov	x3, #0x0                   	// #0
    1de4:	d2800004 	mov	x4, #0x0                   	// #0
    1de8:	d2800005 	mov	x5, #0x0                   	// #0
    1dec:	d2800010 	mov	x16, #0x0                   	// #0
    1df0:	d2800011 	mov	x17, #0x0                   	// #0
    1df4:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:856
    luaD_seterrorobj(L, status, L->top.p);  /* push error message */
    1df8:	f9400a82 	ldr	x2, [x20, #16]
/home/ubuntu/lunatik/lua/ldo.c:855
    L->status = cast_byte(status);  /* mark thread as 'dead' */
    1dfc:	39002a93 	strb	w19, [x20, #10]
/home/ubuntu/lunatik/lua/ldo.c:856
    luaD_seterrorobj(L, status, L->top.p);  /* push error message */
    1e00:	2a1303e1 	mov	w1, w19
    1e04:	aa1403e0 	mov	x0, x20
    1e08:	94000000 	bl	120 <luaD_seterrorobj>
			1e08: R_AARCH64_CALL26	luaD_seterrorobj
/home/ubuntu/lunatik/lua/ldo.c:857
    L->ci->top.p = L->top.p;
    1e0c:	f9401280 	ldr	x0, [x20, #32]
    1e10:	f9400a81 	ldr	x1, [x20, #16]
    1e14:	f9000401 	str	x1, [x0, #8]
/home/ubuntu/lunatik/lua/ldo.c:859
  *nresults = (status == LUA_YIELD) ? L->ci->u2.nyield
    1e18:	f9401280 	ldr	x0, [x20, #32]
    1e1c:	17ffffe3 	b	1da8 <lua_resume+0x1b0>
/home/ubuntu/lunatik/lua/ldo.c:846
  L->nCcalls++;
    1e20:	11000400 	add	w0, w0, #0x1
    1e24:	17ffffbf 	b	1d20 <lua_resume+0x128>
/home/ubuntu/lunatik/lua/ldo.c:860 (discriminator 1)
                                    : cast_int(L->top.p - (L->ci->func.p + 1));
    1e28:	b9403800 	ldr	w0, [x0, #56]
/home/ubuntu/lunatik/lua/ldo.c:859 (discriminator 1)
  *nresults = (status == LUA_YIELD) ? L->ci->u2.nyield
    1e2c:	b90002a0 	str	w0, [x21]
/home/ubuntu/lunatik/lua/ldo.c:862 (discriminator 1)
  return status;
    1e30:	17ffffe4 	b	1dc0 <lua_resume+0x1c8>
resume_error():
/home/ubuntu/lunatik/lua/ldo.c:770
  L->top.p -= narg;  /* remove args from the stack */
    1e34:	cb031093 	sub	x19, x4, x3, lsl #4
/home/ubuntu/lunatik/lua/ldo.c:771
  setsvalue2s(L, L->top.p, luaS_new(L, msg));  /* push error message */
    1e38:	90000001 	adrp	x1, 0 <correctstack-0x8>
			1e38: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.8+0x90
    1e3c:	91000021 	add	x1, x1, #0x0
			1e3c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.8+0x90
/home/ubuntu/lunatik/lua/ldo.c:770
  L->top.p -= narg;  /* remove args from the stack */
    1e40:	f9000813 	str	x19, [x0, #16]
/home/ubuntu/lunatik/lua/ldo.c:771
  setsvalue2s(L, L->top.p, luaS_new(L, msg));  /* push error message */
    1e44:	17ffff91 	b	1c88 <lua_resume+0x90>
lua_resume():
/home/ubuntu/lunatik/lua/ldo.c:771
    1e48:	d503201f 	nop
    1e4c:	d503201f 	nop

0000000000001e50 <lua_isyieldable>:
lua_isyieldable():
/home/ubuntu/lunatik/lua/ldo.c:866
LUA_API int lua_isyieldable (lua_State *L) {
    1e50:	d503201f 	nop
    1e54:	d503201f 	nop
/home/ubuntu/lunatik/lua/ldo.c:867
  return yieldable(L);
    1e58:	b940b000 	ldr	w0, [x0, #176]
    1e5c:	529fffe1 	mov	w1, #0xffff                	// #65535
    1e60:	6b01001f 	cmp	w0, w1
/home/ubuntu/lunatik/lua/ldo.c:868
}
    1e64:	1a9f87e0 	cset	w0, ls  // ls = plast
    1e68:	d2800001 	mov	x1, #0x0                   	// #0
    1e6c:	d65f03c0 	ret
    1e70:	d503201f 	nop
    1e74:	d503201f 	nop

0000000000001e78 <lua_yieldk>:
lua_yieldk():
/home/ubuntu/lunatik/lua/ldo.c:872
                        lua_KFunction k) {
    1e78:	d503201f 	nop
    1e7c:	d503201f 	nop
    1e80:	d503233f 	paciasp
    1e84:	f800865e 	str	x30, [x18], #8
    1e88:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
    1e8c:	aa0003e4 	mov	x4, x0
/home/ubuntu/lunatik/lua/ldo.c:878
  if (l_unlikely(!yieldable(L))) {
    1e90:	529fffe6 	mov	w6, #0xffff                	// #65535
/home/ubuntu/lunatik/lua/ldo.c:872
                        lua_KFunction k) {
    1e94:	910003fd 	mov	x29, sp
/home/ubuntu/lunatik/lua/ldo.c:878
  if (l_unlikely(!yieldable(L))) {
    1e98:	b940b007 	ldr	w7, [x0, #176]
/home/ubuntu/lunatik/lua/ldo.c:876
  ci = L->ci;
    1e9c:	f9401005 	ldr	x5, [x0, #32]
/home/ubuntu/lunatik/lua/ldo.c:878
  if (l_unlikely(!yieldable(L))) {
    1ea0:	6b0600ff 	cmp	w7, w6
    1ea4:	54000288 	b.hi	1ef4 <lua_yieldk+0x7c>  // b.pmore
/home/ubuntu/lunatik/lua/ldo.c:884
  L->status = LUA_YIELD;
    1ea8:	52800020 	mov	w0, #0x1                   	// #1
    1eac:	39002880 	strb	w0, [x4, #10]
/home/ubuntu/lunatik/lua/ldo.c:885
  ci->u2.nyield = nresults;  /* save number of results */
    1eb0:	b90038a1 	str	w1, [x5, #56]
/home/ubuntu/lunatik/lua/ldo.c:886
  if (isLua(ci)) {  /* inside a hook? */
    1eb4:	79407ca0 	ldrh	w0, [x5, #62]
    1eb8:	37080320 	tbnz	w0, #1, 1f1c <lua_yieldk+0xa4>
/home/ubuntu/lunatik/lua/ldo.c:899
}
    1ebc:	f85f8e5e 	ldr	x30, [x18, #-8]!
    1ec0:	52800000 	mov	w0, #0x0                   	// #0
    1ec4:	f84107fd 	ldr	x29, [sp], #16
    1ec8:	d50323bf 	autiasp
    1ecc:	d2800001 	mov	x1, #0x0                   	// #0
    1ed0:	d2800002 	mov	x2, #0x0                   	// #0
    1ed4:	d2800003 	mov	x3, #0x0                   	// #0
    1ed8:	d2800004 	mov	x4, #0x0                   	// #0
    1edc:	d2800005 	mov	x5, #0x0                   	// #0
    1ee0:	d2800006 	mov	x6, #0x0                   	// #0
    1ee4:	d2800007 	mov	x7, #0x0                   	// #0
    1ee8:	d2800010 	mov	x16, #0x0                   	// #0
    1eec:	d2800011 	mov	x17, #0x0                   	// #0
    1ef0:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:879
    if (L != G(L)->mainthread)
    1ef4:	f9400c01 	ldr	x1, [x0, #24]
    1ef8:	f9408421 	ldr	x1, [x1, #264]
    1efc:	eb00003f 	cmp	x1, x0
    1f00:	54000080 	b.eq	1f10 <lua_yieldk+0x98>  // b.none
/home/ubuntu/lunatik/lua/ldo.c:880
      luaG_runerror(L, "attempt to yield across a C-call boundary");
    1f04:	90000001 	adrp	x1, 0 <correctstack-0x8>
			1f04: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.8+0xc8
    1f08:	91000021 	add	x1, x1, #0x0
			1f08: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.8+0xc8
    1f0c:	94000000 	bl	0 <luaG_runerror>
			1f0c: R_AARCH64_CALL26	luaG_runerror
/home/ubuntu/lunatik/lua/ldo.c:882
      luaG_runerror(L, "attempt to yield from outside a coroutine");
    1f10:	90000001 	adrp	x1, 0 <correctstack-0x8>
			1f10: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.8+0xf8
    1f14:	91000021 	add	x1, x1, #0x0
			1f14: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.8+0xf8
    1f18:	94000000 	bl	0 <luaG_runerror>
			1f18: R_AARCH64_CALL26	luaG_runerror
/home/ubuntu/lunatik/lua/ldo.c:892
    if ((ci->u.c.k = k) != NULL)  /* is there a continuation? */
    1f1c:	f90010a3 	str	x3, [x5, #32]
    1f20:	b4000043 	cbz	x3, 1f28 <lua_yieldk+0xb0>
/home/ubuntu/lunatik/lua/ldo.c:893
      ci->u.c.ctx = ctx;  /* save context */
    1f24:	f90018a2 	str	x2, [x5, #48]
/home/ubuntu/lunatik/lua/ldo.c:894
    luaD_throw(L, LUA_YIELD);
    1f28:	aa0403e0 	mov	x0, x4
    1f2c:	52800021 	mov	w1, #0x1                   	// #1
    1f30:	94000000 	bl	270 <luaD_throw>
			1f30: R_AARCH64_CALL26	luaD_throw
    1f34:	d503201f 	nop
    1f38:	d503201f 	nop
    1f3c:	d503201f 	nop

0000000000001f40 <luaD_closeprotected>:
luaD_closeprotected():
/home/ubuntu/lunatik/lua/ldo.c:924
int luaD_closeprotected (lua_State *L, ptrdiff_t level, int status) {
    1f40:	d503201f 	nop
    1f44:	d503201f 	nop
    1f48:	d503233f 	paciasp
    1f4c:	f800865e 	str	x30, [x18], #8
    1f50:	a9ba7bfd 	stp	x29, x30, [sp, #-96]!
    1f54:	d5384103 	mrs	x3, sp_el0
    1f58:	910003fd 	mov	x29, sp
    1f5c:	a90153f3 	stp	x19, x20, [sp, #16]
    1f60:	aa0003f3 	mov	x19, x0
    1f64:	91180060 	add	x0, x3, #0x600
    1f68:	a9025bf5 	stp	x21, x22, [sp, #32]
    1f6c:	90000014 	adrp	x20, 0 <correctstack-0x8>
			1f6c: R_AARCH64_ADR_PREL_PG_HI21	.text+0xc0
    1f70:	aa0103f5 	mov	x21, x1
    1f74:	f9001bf7 	str	x23, [sp, #48]
    1f78:	2a0203e3 	mov	w3, w2
    1f7c:	91000294 	add	x20, x20, #0x0
			1f7c: R_AARCH64_ADD_ABS_LO12_NC	.text+0xc0
/home/ubuntu/lunatik/lua/ldo.c:925
  CallInfo *old_ci = L->ci;
    1f80:	f9401276 	ldr	x22, [x19, #32]
/home/ubuntu/lunatik/lua/ldo.c:924
int luaD_closeprotected (lua_State *L, ptrdiff_t level, int status) {
    1f84:	f9400001 	ldr	x1, [x0]
    1f88:	f9002fe1 	str	x1, [sp, #88]
    1f8c:	d2800001 	mov	x1, #0x0                   	// #0
/home/ubuntu/lunatik/lua/ldo.c:926
  lu_byte old_allowhooks = L->allowhook;
    1f90:	39402e77 	ldrb	w23, [x19, #11]
/home/ubuntu/lunatik/lua/ldo.c:929
    pcl.level = restorestack(L, level); pcl.status = status;
    1f94:	f9401a64 	ldr	x4, [x19, #48]
/home/ubuntu/lunatik/lua/ldo.c:928
    struct CloseP pcl;
    1f98:	a904ffff 	stp	xzr, xzr, [sp, #72]
/home/ubuntu/lunatik/lua/ldo.c:930
    status = luaD_rawrunprotected(L, &closepaux, &pcl);
    1f9c:	910123e2 	add	x2, sp, #0x48
/home/ubuntu/lunatik/lua/ldo.c:929
    pcl.level = restorestack(L, level); pcl.status = status;
    1fa0:	8b150084 	add	x4, x4, x21
/home/ubuntu/lunatik/lua/ldo.c:930
    status = luaD_rawrunprotected(L, &closepaux, &pcl);
    1fa4:	aa1403e1 	mov	x1, x20
    1fa8:	aa1303e0 	mov	x0, x19
/home/ubuntu/lunatik/lua/ldo.c:929
    pcl.level = restorestack(L, level); pcl.status = status;
    1fac:	f90027e4 	str	x4, [sp, #72]
    1fb0:	b90053e3 	str	w3, [sp, #80]
/home/ubuntu/lunatik/lua/ldo.c:930
    status = luaD_rawrunprotected(L, &closepaux, &pcl);
    1fb4:	94000000 	bl	498 <luaD_rawrunprotected>
			1fb4: R_AARCH64_CALL26	luaD_rawrunprotected
    1fb8:	2a0003e3 	mov	w3, w0
/home/ubuntu/lunatik/lua/ldo.c:931
    if (l_likely(status == LUA_OK))  /* no more errors? */
    1fbc:	350002a0 	cbnz	w0, 2010 <luaD_closeprotected+0xd0>
/home/ubuntu/lunatik/lua/ldo.c:938
}
    1fc0:	d5384101 	mrs	x1, sp_el0
/home/ubuntu/lunatik/lua/ldo.c:932
      return pcl.status;
    1fc4:	b94053e0 	ldr	w0, [sp, #80]
/home/ubuntu/lunatik/lua/ldo.c:938
}
    1fc8:	f9402fe3 	ldr	x3, [sp, #88]
    1fcc:	f9430022 	ldr	x2, [x1, #1536]
    1fd0:	eb020063 	subs	x3, x3, x2
    1fd4:	d2800002 	mov	x2, #0x0                   	// #0
    1fd8:	54000221 	b.ne	201c <luaD_closeprotected+0xdc>  // b.any
    1fdc:	a94153f3 	ldp	x19, x20, [sp, #16]
    1fe0:	a9425bf5 	ldp	x21, x22, [sp, #32]
    1fe4:	f9401bf7 	ldr	x23, [sp, #48]
    1fe8:	f85f8e5e 	ldr	x30, [x18, #-8]!
    1fec:	f84607fd 	ldr	x29, [sp], #96
    1ff0:	d50323bf 	autiasp
    1ff4:	d2800001 	mov	x1, #0x0                   	// #0
    1ff8:	d2800002 	mov	x2, #0x0                   	// #0
    1ffc:	d2800003 	mov	x3, #0x0                   	// #0
    2000:	d2800004 	mov	x4, #0x0                   	// #0
    2004:	d2800010 	mov	x16, #0x0                   	// #0
    2008:	d2800011 	mov	x17, #0x0                   	// #0
    200c:	d65f03c0 	ret
/home/ubuntu/lunatik/lua/ldo.c:935
      L->allowhook = old_allowhooks;
    2010:	39002e77 	strb	w23, [x19, #11]
/home/ubuntu/lunatik/lua/ldo.c:934
      L->ci = old_ci;
    2014:	f9001276 	str	x22, [x19, #32]
/home/ubuntu/lunatik/lua/ldo.c:927
  for (;;) {  /* keep closing upvalues until no more errors */
    2018:	17ffffdf 	b	1f94 <luaD_closeprotected+0x54>
/home/ubuntu/lunatik/lua/ldo.c:938
}
    201c:	94000000 	bl	0 <__stack_chk_fail>
			201c: R_AARCH64_CALL26	__stack_chk_fail
    2020:	d503201f 	nop
    2024:	d503201f 	nop

0000000000002028 <luaD_pcall>:
luaD_pcall():
/home/ubuntu/lunatik/lua/ldo.c:947
                ptrdiff_t old_top, ptrdiff_t ef) {
    2028:	d503201f 	nop
    202c:	d503201f 	nop
    2030:	d503233f 	paciasp
    2034:	f800865e 	str	x30, [x18], #8
    2038:	a9b97bfd 	stp	x29, x30, [sp, #-112]!
    203c:	d5384105 	mrs	x5, sp_el0
    2040:	910003fd 	mov	x29, sp
    2044:	a90153f3 	stp	x19, x20, [sp, #16]
    2048:	aa0003f3 	mov	x19, x0
    204c:	a9025bf5 	stp	x21, x22, [sp, #32]
    2050:	aa0303f5 	mov	x21, x3
    2054:	a90363f7 	stp	x23, x24, [sp, #48]
    2058:	f94300a6 	ldr	x6, [x5, #1536]
    205c:	f90037e6 	str	x6, [sp, #104]
    2060:	d2800006 	mov	x6, #0x0                   	// #0
/home/ubuntu/lunatik/lua/ldo.c:950
  lu_byte old_allowhooks = L->allowhook;
    2064:	39402c18 	ldrb	w24, [x0, #11]
/home/ubuntu/lunatik/lua/ldo.c:951
  ptrdiff_t old_errfunc = L->errfunc;
    2068:	f9405416 	ldr	x22, [x0, #168]
/home/ubuntu/lunatik/lua/ldo.c:952
  L->errfunc = ef;
    206c:	f9005404 	str	x4, [x0, #168]
/home/ubuntu/lunatik/lua/ldo.c:949
  CallInfo *old_ci = L->ci;
    2070:	f9401017 	ldr	x23, [x0, #32]
/home/ubuntu/lunatik/lua/ldo.c:953
  status = luaD_rawrunprotected(L, func, u);
    2074:	94000000 	bl	498 <luaD_rawrunprotected>
			2074: R_AARCH64_CALL26	luaD_rawrunprotected
    2078:	2a0003f4 	mov	w20, w0
/home/ubuntu/lunatik/lua/ldo.c:954
  if (l_unlikely(status != LUA_OK)) {  /* an error occurred? */
    207c:	35000300 	cbnz	w0, 20dc <luaD_pcall+0xb4>
/home/ubuntu/lunatik/lua/ldo.c:961
  L->errfunc = old_errfunc;
    2080:	f9005676 	str	x22, [x19, #168]
/home/ubuntu/lunatik/lua/ldo.c:963
}
    2084:	d5384100 	mrs	x0, sp_el0
    2088:	f94037e2 	ldr	x2, [sp, #104]
    208c:	f9430001 	ldr	x1, [x0, #1536]
    2090:	eb010042 	subs	x2, x2, x1
    2094:	d2800001 	mov	x1, #0x0                   	// #0
    2098:	54000561 	b.ne	2144 <luaD_pcall+0x11c>  // b.any
    209c:	a9425bf5 	ldp	x21, x22, [sp, #32]
    20a0:	2a1403e0 	mov	w0, w20
    20a4:	a94153f3 	ldp	x19, x20, [sp, #16]
    20a8:	a94363f7 	ldp	x23, x24, [sp, #48]
    20ac:	f85f8e5e 	ldr	x30, [x18, #-8]!
    20b0:	f84707fd 	ldr	x29, [sp], #112
    20b4:	d50323bf 	autiasp
    20b8:	d2800001 	mov	x1, #0x0                   	// #0
    20bc:	d2800002 	mov	x2, #0x0                   	// #0
    20c0:	d2800003 	mov	x3, #0x0                   	// #0
    20c4:	d2800004 	mov	x4, #0x0                   	// #0
    20c8:	d2800005 	mov	x5, #0x0                   	// #0
    20cc:	d2800006 	mov	x6, #0x0                   	// #0
    20d0:	d2800010 	mov	x16, #0x0                   	// #0
    20d4:	d2800011 	mov	x17, #0x0                   	// #0
    20d8:	d65f03c0 	ret
    20dc:	f90023f9 	str	x25, [sp, #64]
/home/ubuntu/lunatik/lua/ldo.c:955
    L->ci = old_ci;
    20e0:	90000019 	adrp	x25, 0 <correctstack-0x8>
			20e0: R_AARCH64_ADR_PREL_PG_HI21	.text+0xc0
    20e4:	91000339 	add	x25, x25, #0x0
			20e4: R_AARCH64_ADD_ABS_LO12_NC	.text+0xc0
luaD_closeprotected():
/home/ubuntu/lunatik/lua/ldo.c:929
    pcl.level = restorestack(L, level); pcl.status = status;
    20e8:	f9401a63 	ldr	x3, [x19, #48]
luaD_pcall():
/home/ubuntu/lunatik/lua/ldo.c:956
    L->allowhook = old_allowhooks;
    20ec:	39002e78 	strb	w24, [x19, #11]
/home/ubuntu/lunatik/lua/ldo.c:955
    L->ci = old_ci;
    20f0:	f9001277 	str	x23, [x19, #32]
luaD_closeprotected():
/home/ubuntu/lunatik/lua/ldo.c:930
    status = luaD_rawrunprotected(L, &closepaux, &pcl);
    20f4:	910163e2 	add	x2, sp, #0x58
/home/ubuntu/lunatik/lua/ldo.c:929
    pcl.level = restorestack(L, level); pcl.status = status;
    20f8:	8b150063 	add	x3, x3, x21
/home/ubuntu/lunatik/lua/ldo.c:928
    struct CloseP pcl;
    20fc:	a905ffff 	stp	xzr, xzr, [sp, #88]
/home/ubuntu/lunatik/lua/ldo.c:930
    status = luaD_rawrunprotected(L, &closepaux, &pcl);
    2100:	aa1903e1 	mov	x1, x25
    2104:	aa1303e0 	mov	x0, x19
/home/ubuntu/lunatik/lua/ldo.c:929
    pcl.level = restorestack(L, level); pcl.status = status;
    2108:	f9002fe3 	str	x3, [sp, #88]
    210c:	b90063f4 	str	w20, [sp, #96]
/home/ubuntu/lunatik/lua/ldo.c:930
    status = luaD_rawrunprotected(L, &closepaux, &pcl);
    2110:	94000000 	bl	498 <luaD_rawrunprotected>
			2110: R_AARCH64_CALL26	luaD_rawrunprotected
    2114:	2a0003f4 	mov	w20, w0
/home/ubuntu/lunatik/lua/ldo.c:931
    if (l_likely(status == LUA_OK))  /* no more errors? */
    2118:	35fffe80 	cbnz	w0, 20e8 <luaD_pcall+0xc0>
luaD_pcall():
/home/ubuntu/lunatik/lua/ldo.c:958
    luaD_seterrorobj(L, status, restorestack(L, old_top));
    211c:	f9401a62 	ldr	x2, [x19, #48]
    2120:	aa1303e0 	mov	x0, x19
luaD_closeprotected():
/home/ubuntu/lunatik/lua/ldo.c:932
      return pcl.status;
    2124:	b94063f4 	ldr	w20, [sp, #96]
luaD_pcall():
/home/ubuntu/lunatik/lua/ldo.c:958
    luaD_seterrorobj(L, status, restorestack(L, old_top));
    2128:	8b150042 	add	x2, x2, x21
    212c:	2a1403e1 	mov	w1, w20
    2130:	94000000 	bl	120 <luaD_seterrorobj>
			2130: R_AARCH64_CALL26	luaD_seterrorobj
/home/ubuntu/lunatik/lua/ldo.c:959
    luaD_shrinkstack(L);   /* restore stack size in case of overflow */
    2134:	aa1303e0 	mov	x0, x19
    2138:	94000000 	bl	858 <luaD_shrinkstack>
			2138: R_AARCH64_CALL26	luaD_shrinkstack
    213c:	f94023f9 	ldr	x25, [sp, #64]
    2140:	17ffffd0 	b	2080 <luaD_pcall+0x58>
    2144:	f90023f9 	str	x25, [sp, #64]
/home/ubuntu/lunatik/lua/ldo.c:963
}
    2148:	94000000 	bl	0 <__stack_chk_fail>
			2148: R_AARCH64_CALL26	__stack_chk_fail
    214c:	d503201f 	nop
    2150:	d503201f 	nop
    2154:	d503201f 	nop

0000000000002158 <luaD_protectedparser>:
luaD_protectedparser():
/home/ubuntu/lunatik/lua/ldo.c:1006


int luaD_protectedparser (lua_State *L, ZIO *z, const char *name,
                                        const char *mode) {
    2158:	d503201f 	nop
    215c:	d503201f 	nop
    2160:	d503233f 	paciasp
    2164:	f800865e 	str	x30, [x18], #8
    2168:	a9b67bfd 	stp	x29, x30, [sp, #-160]!
    216c:	d5384104 	mrs	x4, sp_el0
    2170:	910003fd 	mov	x29, sp
    2174:	a90153f3 	stp	x19, x20, [sp, #16]
    2178:	aa0003f3 	mov	x19, x0
    217c:	aa0303f4 	mov	x20, x3
    2180:	a9025bf5 	stp	x21, x22, [sp, #32]
    2184:	aa0203f5 	mov	x21, x2
    2188:	aa0103f6 	mov	x22, x1
    218c:	f9430080 	ldr	x0, [x4, #1536]
    2190:	f9004fe0 	str	x0, [sp, #152]
    2194:	d2800000 	mov	x0, #0x0                   	// #0
/home/ubuntu/lunatik/lua/ldo.c:1007
  struct SParser p;
    2198:	d2800c02 	mov	x2, #0x60                  	// #96
    219c:	52800001 	mov	w1, #0x0                   	// #0
    21a0:	9100e3e0 	add	x0, sp, #0x38
    21a4:	94000000 	bl	0 <memset>
			21a4: R_AARCH64_CALL26	memset
/home/ubuntu/lunatik/lua/ldo.c:1015
  p.z = z; p.name = name; p.mode = mode;
  p.dyd.actvar.arr = NULL; p.dyd.actvar.size = 0;
  p.dyd.gt.arr = NULL; p.dyd.gt.size = 0;
  p.dyd.label.arr = NULL; p.dyd.label.size = 0;
  luaZ_initbuffer(L, &p.buff);
  status = luaD_pcall(L, f_parser, &p, savestack(L, L->top.p), L->errfunc);
    21a8:	9100e3e2 	add	x2, sp, #0x38
    21ac:	f9400a65 	ldr	x5, [x19, #16]
    21b0:	aa1303e0 	mov	x0, x19
    21b4:	f9405664 	ldr	x4, [x19, #168]
/home/ubuntu/lunatik/lua/ldo.c:1010
  p.z = z; p.name = name; p.mode = mode;
    21b8:	f9001ff6 	str	x22, [sp, #56]
/home/ubuntu/lunatik/lua/ldo.c:1009
  incnny(L);  /* cannot yield during parsing */
    21bc:	b940b261 	ldr	w1, [x19, #176]
/home/ubuntu/lunatik/lua/ldo.c:1015
  status = luaD_pcall(L, f_parser, &p, savestack(L, L->top.p), L->errfunc);
    21c0:	f9401a63 	ldr	x3, [x19, #48]
/home/ubuntu/lunatik/lua/ldo.c:1009
  incnny(L);  /* cannot yield during parsing */
    21c4:	11404021 	add	w1, w1, #0x10, lsl #12
    21c8:	b900b261 	str	w1, [x19, #176]
/home/ubuntu/lunatik/lua/ldo.c:1015
  status = luaD_pcall(L, f_parser, &p, savestack(L, L->top.p), L->errfunc);
    21cc:	90000001 	adrp	x1, 0 <correctstack-0x8>
			21cc: R_AARCH64_ADR_PREL_PG_HI21	.text+0x310
    21d0:	91000021 	add	x1, x1, #0x0
			21d0: R_AARCH64_ADD_ABS_LO12_NC	.text+0x310
    21d4:	cb0300a3 	sub	x3, x5, x3
/home/ubuntu/lunatik/lua/ldo.c:1010
  p.z = z; p.name = name; p.mode = mode;
    21d8:	a908d7f4 	stp	x20, x21, [sp, #136]
/home/ubuntu/lunatik/lua/ldo.c:1015
  status = luaD_pcall(L, f_parser, &p, savestack(L, L->top.p), L->errfunc);
    21dc:	94000000 	bl	2028 <luaD_pcall>
			21dc: R_AARCH64_CALL26	luaD_pcall
/home/ubuntu/lunatik/lua/ldo.c:1016
  luaZ_freebuffer(L, &p.buff);
    21e0:	d2800003 	mov	x3, #0x0                   	// #0
    21e4:	f94023e1 	ldr	x1, [sp, #64]
/home/ubuntu/lunatik/lua/ldo.c:1015
  status = luaD_pcall(L, f_parser, &p, savestack(L, L->top.p), L->errfunc);
    21e8:	2a0003f5 	mov	w21, w0
/home/ubuntu/lunatik/lua/ldo.c:1016
  luaZ_freebuffer(L, &p.buff);
    21ec:	f9402be2 	ldr	x2, [sp, #80]
    21f0:	aa1303e0 	mov	x0, x19
/home/ubuntu/lunatik/lua/ldo.c:1017
  luaM_freearray(L, p.dyd.actvar.arr, p.dyd.actvar.size);
    21f4:	52800314 	mov	w20, #0x18                  	// #24
/home/ubuntu/lunatik/lua/ldo.c:1016
  luaZ_freebuffer(L, &p.buff);
    21f8:	94000000 	bl	0 <luaM_saferealloc_>
			21f8: R_AARCH64_CALL26	luaM_saferealloc_
/home/ubuntu/lunatik/lua/ldo.c:1017
  luaM_freearray(L, p.dyd.actvar.arr, p.dyd.actvar.size);
    21fc:	b94067e2 	ldr	w2, [sp, #100]
    2200:	f9402fe1 	ldr	x1, [sp, #88]
/home/ubuntu/lunatik/lua/ldo.c:1016
  luaZ_freebuffer(L, &p.buff);
    2204:	aa0003e3 	mov	x3, x0
/home/ubuntu/lunatik/lua/ldo.c:1017
  luaM_freearray(L, p.dyd.actvar.arr, p.dyd.actvar.size);
    2208:	aa1303e0 	mov	x0, x19
/home/ubuntu/lunatik/lua/ldo.c:1016
  luaZ_freebuffer(L, &p.buff);
    220c:	f90023e3 	str	x3, [sp, #64]
/home/ubuntu/lunatik/lua/ldo.c:1017
  luaM_freearray(L, p.dyd.actvar.arr, p.dyd.actvar.size);
    2210:	9b347c42 	smull	x2, w2, w20
/home/ubuntu/lunatik/lua/ldo.c:1016
  luaZ_freebuffer(L, &p.buff);
    2214:	f9002bff 	str	xzr, [sp, #80]
/home/ubuntu/lunatik/lua/ldo.c:1017
  luaM_freearray(L, p.dyd.actvar.arr, p.dyd.actvar.size);
    2218:	94000000 	bl	0 <luaM_free_>
			2218: R_AARCH64_CALL26	luaM_free_
/home/ubuntu/lunatik/lua/ldo.c:1018
  luaM_freearray(L, p.dyd.gt.arr, p.dyd.gt.size);
    221c:	b94077e2 	ldr	w2, [sp, #116]
    2220:	f94037e1 	ldr	x1, [sp, #104]
    2224:	aa1303e0 	mov	x0, x19
    2228:	9b347c42 	smull	x2, w2, w20
    222c:	94000000 	bl	0 <luaM_free_>
			222c: R_AARCH64_CALL26	luaM_free_
/home/ubuntu/lunatik/lua/ldo.c:1019
  luaM_freearray(L, p.dyd.label.arr, p.dyd.label.size);
    2230:	b94087e2 	ldr	w2, [sp, #132]
    2234:	f9403fe1 	ldr	x1, [sp, #120]
    2238:	aa1303e0 	mov	x0, x19
    223c:	9b347c42 	smull	x2, w2, w20
    2240:	94000000 	bl	0 <luaM_free_>
			2240: R_AARCH64_CALL26	luaM_free_
/home/ubuntu/lunatik/lua/ldo.c:1020
  decnny(L);
    2244:	b940b262 	ldr	w2, [x19, #176]
/home/ubuntu/lunatik/lua/ldo.c:1022
  return status;
}
    2248:	d5384101 	mrs	x1, sp_el0
/home/ubuntu/lunatik/lua/ldo.c:1020
  decnny(L);
    224c:	51404042 	sub	w2, w2, #0x10, lsl #12
    2250:	b900b262 	str	w2, [x19, #176]
/home/ubuntu/lunatik/lua/ldo.c:1022
}
    2254:	f9404fe0 	ldr	x0, [sp, #152]
    2258:	f9430022 	ldr	x2, [x1, #1536]
    225c:	eb020000 	subs	x0, x0, x2
    2260:	d2800002 	mov	x2, #0x0                   	// #0
    2264:	540001e1 	b.ne	22a0 <luaD_protectedparser+0x148>  // b.any
    2268:	a94153f3 	ldp	x19, x20, [sp, #16]
    226c:	2a1503e0 	mov	w0, w21
    2270:	a9425bf5 	ldp	x21, x22, [sp, #32]
    2274:	f85f8e5e 	ldr	x30, [x18, #-8]!
    2278:	f84a07fd 	ldr	x29, [sp], #160
    227c:	d50323bf 	autiasp
    2280:	d2800001 	mov	x1, #0x0                   	// #0
    2284:	d2800002 	mov	x2, #0x0                   	// #0
    2288:	d2800003 	mov	x3, #0x0                   	// #0
    228c:	d2800004 	mov	x4, #0x0                   	// #0
    2290:	d2800005 	mov	x5, #0x0                   	// #0
    2294:	d2800010 	mov	x16, #0x0                   	// #0
    2298:	d2800011 	mov	x17, #0x0                   	// #0
    229c:	d65f03c0 	ret
    22a0:	94000000 	bl	0 <__stack_chk_fail>
			22a0: R_AARCH64_CALL26	__stack_chk_fail
