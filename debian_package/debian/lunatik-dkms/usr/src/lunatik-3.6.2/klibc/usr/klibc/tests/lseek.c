#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>

int main(void)
{
  int fd = open("test.out", O_RDWR|O_CREAT|O_TRUNC, 0666);
  off_t rv;

  rv = lseek(fd, 123456789012ULL, SEEK_SET);

  printf("seek to: %lld\n", rv);
  return 0;
}
