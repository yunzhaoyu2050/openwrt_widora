#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <time.h>
#include <stdint.h>
#include <errno.h>

#define SPI_POWER_FUNC_PATH "/dev/spidev32766.1"

struct bl0939_val_st_tmp {
	uint32_t chA[16];
	uint32_t chB[16];
	uint32_t vtg;
};
struct bl0939_val_st_tmp bvst;

void bl0939_print_qu(uint32_t *buf)
{
	int i;
	printf("buf: ");
	for (i = 0; i < 16; i++) {
		printf("%.2X, ",buf[i]);
	}
	printf(".\r\n");
}
int main()
{
    int flag;
    int is_block = 0;

    flag = 0;
    flag |= O_RDWR;
    if (is_block == 0)
        flag |= O_NONBLOCK; //若为0则表示以非阻塞方式打开

    int fd = open(SPI_POWER_FUNC_PATH, flag);
    if (fd < 0)
    {
        perror("Open device file err:");
        return -1;
    }
    // char read_buf[1024] = {0};

    while (1) {
        memset(&bvst, 0 ,sizeof(bvst));
        int ret = read(fd, &bvst, sizeof(bvst));
        if (ret < 0)
            printf("error: read, ret:%d.\n", ret);
        else {
            // printf("info; read: %s, len:%d.\n", read_buf, ret);
            bl0939_print_qu(bvst.chA);
            bl0939_print_qu(bvst.chB);
            printf("asd vtg:%.2X\r\n", bvst.vtg);
        }
        usleep(400 * 1000);
    }
    close(fd);
    return 0;
}