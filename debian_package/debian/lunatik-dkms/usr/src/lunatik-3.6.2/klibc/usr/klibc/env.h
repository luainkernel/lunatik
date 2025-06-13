#ifndef ENV_H
#define ENV_H

/* str should be a duplicated version of the input string;
   len is the length of the key including the = sign */
int __put_env(char *str, size_t len, int overwrite);

extern char *const __null_environ[];

#endif
