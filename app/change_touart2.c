#include <stdio.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>

typedef enum{
	IOT_DEV_MODE,		// 单网口模式
	IOT_GATEWAY_MODE	// 五网口模式
}work_mode_7628_t;

int set_7628_work_mode(work_mode_7628_t mode)
{
	int ch;
	int mem_fd = open("/dev/mem", O_RDWR|O_SYNC); 
	if(mem_fd == -1)
	{
		perror("open /dev/mem");
		return -1;
	}
	int size = 0x100;
	int *addr = (int *)mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_SHARED, mem_fd, 0x10000000);
	if(addr == MAP_FAILED)
	{
		perror("mmap");
		return -1;
	}
	
	if(mode == IOT_DEV_MODE)
	{
		*(addr+(0x3c/4)) |= 0x0f<<17;
	}
	else
	{
		*(addr+(0x3c/4)) &= ~(0x0f<<17);
	}

	close(mem_fd);
	munmap(addr, size);
	return 0;
}


int main(int argc, char *argv[])
{
	return set_7628_work_mode(IOT_DEV_MODE);
}