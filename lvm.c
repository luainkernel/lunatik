/*
** $Id: lvm.c,v 1.39 1999/01/15 13:14:24 roberto Exp roberto $
** Lua virtual machine
** See Copyright Notice in lua.h
*/


#include <ctype.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lauxlib.h"
#include "ldo.h"
#include "lfunc.h"
#include "lgc.h"
#include "lmem.h"
#include "lobject.h"
#include "lopcodes.h"
#include "lstate.h"
#include "lstring.h"
#include "ltable.h"
#include "ltm.h"
#include "luadebug.h"
#include "lvm.h"


#ifdef OLD_ANSI
#define strcoll(a,b)	strcmp(a,b)
#endif


#define skip_word(pc)	(pc+=2)
#define get_word(pc)	((*(pc)<<8)+(*((pc)+1)))
#define next_word(pc)   (pc+=2, get_word(pc-2))


/* Extra stack size to run a function: LUA_T_LINE(1), TM calls(2), ... */
#define	EXTRA_STACK	5



static TaggedString *strconc (TaggedString *l, TaggedString *r) {
  long nl = l->u.s.len;
  long nr = r->u.s.len;
  char *buffer = luaL_openspace(nl+nr);
  memcpy(buffer, l->str, nl);
  memcpy(buffer+nl, r->str, nr);
  return luaS_newlstr(buffer, nl+nr);
}


int luaV_tonumber (TObject *obj) {  /* LUA_NUMBER */
  if (ttype(obj) != LUA_T_STRING)
    return 1;
  else {
    double t;
    char *e = svalue(obj);
    int sig = 1;
    while (isspace((unsigned char)*e)) e++;
    if (*e == '+') e++;
    else if (*e == '-') {
      e++;
      sig = -1;
    }
    t = luaO_str2d(e);
    if (t<0) return 2;
    nvalue(obj) = (real)t*sig;
    ttype(obj) = LUA_T_NUMBER;
    return 0;
  }
}


int luaV_tostring (TObject *obj) {  /* LUA_NUMBER */
  if (ttype(obj) != LUA_T_NUMBER)
    return 1;
  else {
    char s[32];  /* 16 digits, signal, point and \0  (+ some extra...) */
    sprintf(s, "%.16g", (double)nvalue(obj));
    tsvalue(obj) = luaS_new(s);
    ttype(obj) = LUA_T_STRING;
    return 0;
  }
}


void luaV_setn (Hash *t, int val) {
  TObject index, value;
  ttype(&index) = LUA_T_STRING; tsvalue(&index) = luaS_new("n");
  ttype(&value) = LUA_T_NUMBER; nvalue(&value) = val;
  *(luaH_set(t, &index)) = value;
}


void luaV_closure (int nelems)
{
  if (nelems > 0) {
    struct Stack *S = &L->stack;
    Closure *c = luaF_newclosure(nelems);
    c->consts[0] = *(S->top-1);
    memcpy(&c->consts[1], S->top-(nelems+1), nelems*sizeof(TObject));
    S->top -= nelems;
    ttype(S->top-1) = LUA_T_CLOSURE;
    (S->top-1)->value.cl = c;
  }
}


/*
** Function to index a table.
** Receives the table at top-2 and the index at top-1.
*/
void luaV_gettable (void) {
  struct Stack *S = &L->stack;
  TObject *im;
  if (ttype(S->top-2) != LUA_T_ARRAY)  /* not a table, get "gettable" method */
    im = luaT_getimbyObj(S->top-2, IM_GETTABLE);
  else {  /* object is a table... */
    int tg = (S->top-2)->value.a->htag;
    im = luaT_getim(tg, IM_GETTABLE);
    if (ttype(im) == LUA_T_NIL) {  /* and does not have a "gettable" method */
      TObject *h = luaH_get(avalue(S->top-2), S->top-1);
      if (ttype(h) != LUA_T_NIL) {
        --S->top;
        *(S->top-1) = *h;
      }
      else if (ttype(im=luaT_getim(tg, IM_INDEX)) != LUA_T_NIL)
        luaD_callTM(im, 2, 1);
      else {
        --S->top;
        ttype(S->top-1) = LUA_T_NIL;
      }
      return;
    }
    /* else it has a "gettable" method, go through to next command */
  }
  /* object is not a table, or it has a "gettable" method */
  if (ttype(im) == LUA_T_NIL)
    lua_error("indexed expression not a table");
  luaD_callTM(im, 2, 1);
}


/*
** Function to store indexed based on values at the stack.top
** deep = 1: "deep L->stack.stack" store (with tag methods)
*/
void luaV_settable (TObject *t, int deep) {
  struct Stack *S = &L->stack;
  TObject *im;
  if (ttype(t) != LUA_T_ARRAY)  /* not a table, get "settable" method */
    im = luaT_getimbyObj(t, IM_SETTABLE);
  else {  /* object is a table... */
    im = luaT_getim(avalue(t)->htag, IM_SETTABLE);
    if (ttype(im) == LUA_T_NIL) {  /* and does not have a "settable" method */
      *(luaH_set(avalue(t), t+1)) = *(S->top-1);
      /* if deep, pop only value; otherwise, pop table, index and value */
      S->top -= (deep) ? 1 : 3;
      return;
    }
    /* else it has a "settable" method, go through to next command */
  }
  /* object is not a table, or it has a "settable" method */
  if (ttype(im) == LUA_T_NIL)
    lua_error("indexed expression not a table");
  if (deep) {  /* table and index were not on top; copy them */
    *(S->top+1) = *(L->stack.top-1);
    *(S->top) = *(t+1);
    *(S->top-1) = *t;
    S->top += 2;  /* WARNING: caller must assure stack space */
  }
  luaD_callTM(im, 3, 0);
}


void luaV_rawsettable (TObject *t) {
  if (ttype(t) != LUA_T_ARRAY)
    lua_error("indexed expression not a table");
  else {
    struct Stack *S = &L->stack;
    *(luaH_set(avalue(t), t+1)) = *(S->top-1);
    S->top -= 3;
  }
}


void luaV_getglobal (TaggedString *ts) {
  /* WARNING: caller must assure stack space */
  /* only userdata, tables and nil can have getglobal tag methods */
  static char valid_getglobals[] = {1, 0, 0, 1, 0, 0, 1, 0};  /* ORDER LUA_T */
  TObject *value = &ts->u.s.globalval;
  if (valid_getglobals[-ttype(value)]) {
    TObject *im = luaT_getimbyObj(value, IM_GETGLOBAL);
    if (ttype(im) != LUA_T_NIL) {  /* is there a tag method? */
      struct Stack *S = &L->stack;
      ttype(S->top) = LUA_T_STRING;
      tsvalue(S->top) = ts;
      S->top++;
      *S->top++ = *value;
      luaD_callTM(im, 2, 1);
      return;
    }
    /* else no tag method: go through to default behavior */
  }
  *L->stack.top++ = *value;  /* default behavior */
}


void luaV_setglobal (TaggedString *ts) {
  TObject *oldvalue = &ts->u.s.globalval;
  TObject *im = luaT_getimbyObj(oldvalue, IM_SETGLOBAL);
  if (ttype(im) == LUA_T_NIL)  /* is there a tag method? */
    luaS_rawsetglobal(ts, --L->stack.top);
  else {
    /* WARNING: caller must assure stack space */
    struct Stack *S = &L->stack;
    TObject newvalue = *(S->top-1);
    ttype(S->top-1) = LUA_T_STRING;
    tsvalue(S->top-1) = ts;
    *S->top++ = *oldvalue;
    *S->top++ = newvalue;
    luaD_callTM(im, 3, 0);
  }
}


static void call_binTM (IMS event, char *msg)
{
  TObject *im = luaT_getimbyObj(L->stack.top-2, event);/* try first operand */
  if (ttype(im) == LUA_T_NIL) {
    im = luaT_getimbyObj(L->stack.top-1, event);  /* try second operand */
    if (ttype(im) == LUA_T_NIL) {
      im = luaT_getim(0, event);  /* try a 'global' i.m. */
      if (ttype(im) == LUA_T_NIL)
        lua_error(msg);
    }
  }
  lua_pushstring(luaT_eventname[event]);
  luaD_callTM(im, 3, 1);
}


static void call_arith (IMS event)
{
  call_binTM(event, "unexpected type in arithmetic operation");
}


static int luaV_strcomp (char *l, long ll, char *r, long lr)
{
  for (;;) {
    long temp = strcoll(l, r);
    if (temp != 0) return temp;
    /* strings are equal up to a '\0' */
    temp = strlen(l);  /* index of first '\0' in both strings */
    if (temp == ll)  /* l is finished? */
      return (temp == lr) ? 0 : -1;  /* l is equal or smaller than r */
    else if (temp == lr)  /* r is finished? */
      return 1;  /* l is greater than r (because l is not finished) */
    /* both strings longer than temp; go on comparing (after the '\0') */
    temp++;
    l += temp; ll -= temp; r += temp; lr -= temp;
  }
}

void luaV_comparison (lua_Type ttype_less, lua_Type ttype_equal,
                      lua_Type ttype_great, IMS op) {
  struct Stack *S = &L->stack;
  TObject *l = S->top-2;
  TObject *r = S->top-1;
  real result;
  if (ttype(l) == LUA_T_NUMBER && ttype(r) == LUA_T_NUMBER)
    result = nvalue(l)-nvalue(r);
  else if (ttype(l) == LUA_T_STRING && ttype(r) == LUA_T_STRING)
    result = luaV_strcomp(svalue(l), tsvalue(l)->u.s.len,
                          svalue(r), tsvalue(r)->u.s.len);
  else {
    call_binTM(op, "unexpected type in comparison");
    return;
  }
  S->top--;
  nvalue(S->top-1) = 1;
  ttype(S->top-1) = (result < 0) ? ttype_less :
                                (result == 0) ? ttype_equal : ttype_great;
}


void luaV_pack (StkId firstel, int nvararg, TObject *tab) {
  TObject *firstelem = L->stack.stack+firstel;
  int i;
  Hash *htab;
  if (nvararg < 0) nvararg = 0;
  htab = avalue(tab) = luaH_new(nvararg+1);  /* +1 for field 'n' */
  ttype(tab) = LUA_T_ARRAY;
  for (i=0; i<nvararg; i++)
    luaH_setint(htab, i+1, firstelem+i);
  luaV_setn(htab, nvararg);  /* store counter in field "n" */
}


static void adjust_varargs (StkId first_extra_arg)
{
  TObject arg;
  luaV_pack(first_extra_arg,
       (L->stack.top-L->stack.stack)-first_extra_arg, &arg);
  luaD_adjusttop(first_extra_arg);
  *L->stack.top++ = arg;
}



/*
** Execute the given opcode, until a RET. Parameters are between
** [stack+base,top). Returns n such that the the results are between
** [stack+n,top).
*/
StkId luaV_execute (Closure *cl, TProtoFunc *tf, StkId base)
{
  struct Stack *S = &L->stack;  /* to optimize */
  Byte *pc = tf->code;
  TObject *consts = tf->consts;
  if (lua_callhook)
    luaD_callHook(base, tf, 0);
  luaD_checkstack((*pc++)+EXTRA_STACK);
  if (*pc < ZEROVARARG)
    luaD_adjusttop(base+*(pc++));
  else {  /* varargs */
    luaC_checkGC();
    adjust_varargs(base+(*pc++)-ZEROVARARG);
  }
  for (;;) {
    int aux;
    switch ((OpCode)(aux = *pc++)) {

      case PUSHNIL0:
        ttype(S->top++) = LUA_T_NIL;
        break;

      case PUSHNIL:
        aux = *pc++;
        do {
          ttype(S->top++) = LUA_T_NIL;
        } while (aux--);
        break;

      case PUSHNUMBER:
        aux = *pc++; goto pushnumber;

      case PUSHNUMBERW:
        aux = next_word(pc); goto pushnumber;

      case PUSHNUMBER0: case PUSHNUMBER1: case PUSHNUMBER2:
        aux -= PUSHNUMBER0;
      pushnumber:
        ttype(S->top) = LUA_T_NUMBER;
        nvalue(S->top) = aux;
        S->top++;
        break;

      case PUSHLOCAL:
        aux = *pc++; goto pushlocal;

      case PUSHLOCAL0: case PUSHLOCAL1: case PUSHLOCAL2: case PUSHLOCAL3:
      case PUSHLOCAL4: case PUSHLOCAL5: case PUSHLOCAL6: case PUSHLOCAL7:
        aux -= PUSHLOCAL0;
      pushlocal:
        *S->top++ = *((S->stack+base) + aux);
        break;

      case GETGLOBALW:
        aux = next_word(pc); goto getglobal;

      case GETGLOBAL:
        aux = *pc++; goto getglobal;

      case GETGLOBAL0: case GETGLOBAL1: case GETGLOBAL2: case GETGLOBAL3:
      case GETGLOBAL4: case GETGLOBAL5: case GETGLOBAL6: case GETGLOBAL7:
        aux -= GETGLOBAL0;
      getglobal:
        luaV_getglobal(tsvalue(&consts[aux]));
        break;

      case GETTABLE:
       luaV_gettable();
       break;

      case GETDOTTEDW:
        aux = next_word(pc); goto getdotted;

      case GETDOTTED:
        aux = *pc++; goto getdotted;

      case GETDOTTED0: case GETDOTTED1: case GETDOTTED2: case GETDOTTED3:
      case GETDOTTED4: case GETDOTTED5: case GETDOTTED6: case GETDOTTED7:
        aux -= GETDOTTED0;
      getdotted:
        *S->top++ = consts[aux];
        luaV_gettable();
        break;

      case PUSHSELFW:
        aux = next_word(pc); goto pushself;

      case PUSHSELF:
        aux = *pc++; goto pushself;

      case PUSHSELF0: case PUSHSELF1: case PUSHSELF2: case PUSHSELF3:
      case PUSHSELF4: case PUSHSELF5: case PUSHSELF6: case PUSHSELF7:
        aux -= PUSHSELF0;
      pushself: {
        TObject receiver = *(S->top-1);
        *S->top++ = consts[aux];
        luaV_gettable();
        *S->top++ = receiver;
        break;
      }

      case PUSHCONSTANTW:
        aux = next_word(pc); goto pushconstant;

      case PUSHCONSTANT:
        aux = *pc++; goto pushconstant;

      case PUSHCONSTANT0: case PUSHCONSTANT1: case PUSHCONSTANT2:
      case PUSHCONSTANT3: case PUSHCONSTANT4: case PUSHCONSTANT5:
      case PUSHCONSTANT6: case PUSHCONSTANT7:
        aux -= PUSHCONSTANT0;
      pushconstant:
        *S->top++ = consts[aux];
        break;

      case PUSHUPVALUE:
        aux = *pc++; goto pushupvalue;

      case PUSHUPVALUE0: case PUSHUPVALUE1:
        aux -= PUSHUPVALUE0;
      pushupvalue:
        *S->top++ = cl->consts[aux+1];
        break;

      case SETLOCAL:
        aux = *pc++; goto setlocal;

      case SETLOCAL0: case SETLOCAL1: case SETLOCAL2: case SETLOCAL3:
      case SETLOCAL4: case SETLOCAL5: case SETLOCAL6: case SETLOCAL7:
        aux -= SETLOCAL0;
      setlocal:
        *((S->stack+base) + aux) = *(--S->top);
        break;

      case SETGLOBALW:
        aux = next_word(pc); goto setglobal;

      case SETGLOBAL:
        aux = *pc++; goto setglobal;

      case SETGLOBAL0: case SETGLOBAL1: case SETGLOBAL2: case SETGLOBAL3:
      case SETGLOBAL4: case SETGLOBAL5: case SETGLOBAL6: case SETGLOBAL7:
        aux -= SETGLOBAL0;
      setglobal:
        luaV_setglobal(tsvalue(&consts[aux]));
        break;

      case SETTABLE0:
       luaV_settable(S->top-3, 0);
       break;

      case SETTABLE:
        luaV_settable(S->top-3-(*pc++), 1);
        break;

      case SETLISTW:
        aux = next_word(pc); aux *= LFIELDS_PER_FLUSH; goto setlist;

      case SETLIST:
        aux = *(pc++) * LFIELDS_PER_FLUSH; goto setlist;

      case SETLIST0:
        aux = 0;
      setlist: {
        int n = *(pc++);
        TObject *arr = S->top-n-1;
        for (; n; n--) {
          ttype(S->top) = LUA_T_NUMBER;
          nvalue(S->top) = n+aux;
          *(luaH_set(avalue(arr), S->top)) = *(S->top-1);
          S->top--;
        }
        break;
      }

      case SETMAP0:
        aux = 0; goto setmap;

      case SETMAP:
        aux = *pc++;
      setmap: {
        TObject *arr = S->top-(2*aux)-3;
        do {
          *(luaH_set(avalue(arr), S->top-2)) = *(S->top-1);
          S->top-=2;
        } while (aux--);
        break;
      }

      case POP:
        aux = *pc++; goto pop;

      case POP0: case POP1:
        aux -= POP0;
      pop:
        S->top -= (aux+1);
        break;

      case CREATEARRAYW:
        aux = next_word(pc); goto createarray;

      case CREATEARRAY0: case CREATEARRAY1:
        aux -= CREATEARRAY0; goto createarray;

      case CREATEARRAY:
        aux = *pc++;
      createarray:
        luaC_checkGC();
        avalue(S->top) = luaH_new(aux);
        ttype(S->top) = LUA_T_ARRAY;
        S->top++;
        break;

      case EQOP: case NEQOP: {
        int res = luaO_equalObj(S->top-2, S->top-1);
        S->top--;
        if (aux == NEQOP) res = !res;
        ttype(S->top-1) = res ? LUA_T_NUMBER : LUA_T_NIL;
        nvalue(S->top-1) = 1;
        break;
      }

       case LTOP:
         luaV_comparison(LUA_T_NUMBER, LUA_T_NIL, LUA_T_NIL, IM_LT);
         break;

      case LEOP:
        luaV_comparison(LUA_T_NUMBER, LUA_T_NUMBER, LUA_T_NIL, IM_LE);
        break;

      case GTOP:
        luaV_comparison(LUA_T_NIL, LUA_T_NIL, LUA_T_NUMBER, IM_GT);
        break;

      case GEOP:
        luaV_comparison(LUA_T_NIL, LUA_T_NUMBER, LUA_T_NUMBER, IM_GE);
        break;

      case ADDOP: {
        TObject *l = S->top-2;
        TObject *r = S->top-1;
        if (tonumber(r) || tonumber(l))
          call_arith(IM_ADD);
        else {
          nvalue(l) += nvalue(r);
          --S->top;
        }
        break;
      }

      case SUBOP: {
        TObject *l = S->top-2;
        TObject *r = S->top-1;
        if (tonumber(r) || tonumber(l))
          call_arith(IM_SUB);
        else {
          nvalue(l) -= nvalue(r);
          --S->top;
        }
        break;
      }

      case MULTOP: {
        TObject *l = S->top-2;
        TObject *r = S->top-1;
        if (tonumber(r) || tonumber(l))
          call_arith(IM_MUL);
        else {
          nvalue(l) *= nvalue(r);
          --S->top;
        }
        break;
      }

      case DIVOP: {
        TObject *l = S->top-2;
        TObject *r = S->top-1;
        if (tonumber(r) || tonumber(l))
          call_arith(IM_DIV);
        else {
          nvalue(l) /= nvalue(r);
          --S->top;
        }
        break;
      }

      case POWOP:
        call_binTM(IM_POW, "undefined operation");
        break;

      case CONCOP: {
        TObject *l = S->top-2;
        TObject *r = S->top-1;
        if (tostring(l) || tostring(r))
          call_binTM(IM_CONCAT, "unexpected type for concatenation");
        else {
          tsvalue(l) = strconc(tsvalue(l), tsvalue(r));
          --S->top;
        }
        luaC_checkGC();
        break;
      }

      case MINUSOP:
        if (tonumber(S->top-1)) {
          ttype(S->top) = LUA_T_NIL;
          S->top++;
          call_arith(IM_UNM);
        }
        else
          nvalue(S->top-1) = - nvalue(S->top-1);
        break;

      case NOTOP:
        ttype(S->top-1) =
           (ttype(S->top-1) == LUA_T_NIL) ? LUA_T_NUMBER : LUA_T_NIL;
        nvalue(S->top-1) = 1;
        break;

      case ONTJMPW:
        aux = next_word(pc); goto ontjmp;

      case ONTJMP:
        aux = *pc++;
      ontjmp:
        if (ttype(S->top-1) != LUA_T_NIL) pc += aux;
        else S->top--;
        break;

      case ONFJMPW:
        aux = next_word(pc); goto onfjmp;

      case ONFJMP:
        aux = *pc++;
      onfjmp:
        if (ttype(S->top-1) == LUA_T_NIL) pc += aux;
        else S->top--;
        break;

      case JMPW:
        aux = next_word(pc); goto jmp;

      case JMP:
        aux = *pc++;
      jmp:
        pc += aux;
        break;

      case IFFJMPW:
        aux = next_word(pc); goto iffjmp;

      case IFFJMP:
        aux = *pc++;
      iffjmp:
        if (ttype(--S->top) == LUA_T_NIL) pc += aux;
        break;

      case IFTUPJMPW:
        aux = next_word(pc); goto iftupjmp;

      case IFTUPJMP:
        aux = *pc++;
      iftupjmp:
        if (ttype(--S->top) != LUA_T_NIL) pc -= aux;
        break;

      case IFFUPJMPW:
        aux = next_word(pc); goto iffupjmp;

      case IFFUPJMP:
        aux = *pc++;
      iffupjmp:
        if (ttype(--S->top) == LUA_T_NIL) pc -= aux;
        break;

      case CLOSUREW:
        aux = next_word(pc); goto closure;

      case CLOSURE:
        aux = *pc++;
      closure:
        *S->top++ = consts[aux];
        luaV_closure(*pc++);
        luaC_checkGC();
        break;

      case CALLFUNC:
        aux = *pc++; goto callfunc;

      case CALLFUNC0: case CALLFUNC1:
        aux -= CALLFUNC0;
      callfunc: {
        StkId newBase = (S->top-S->stack)-(*pc++);
        luaD_call(newBase, aux);
        break;
      }

      case ENDCODE:
        S->top = S->stack + base;
        /* goes through */
      case RETCODE:
        if (lua_callhook)
          luaD_callHook(base, NULL, 1);
        return (base + ((aux==RETCODE) ? *pc : 0));

      case SETLINEW:
        aux = next_word(pc); goto setline;

      case SETLINE:
        aux = *pc++;
      setline:
        if ((S->stack+base-1)->ttype != LUA_T_LINE) {
          /* open space for LINE value */
          luaD_openstack((S->top-S->stack)-base);
          base++;
          (S->stack+base-1)->ttype = LUA_T_LINE;
        }
        (S->stack+base-1)->value.i = aux;
        if (lua_linehook)
          luaD_lineHook(aux);
        break;

#ifdef DEBUG
      default:
        LUA_INTERNALERROR("opcode doesn't match");
#endif
    }
  }
}

