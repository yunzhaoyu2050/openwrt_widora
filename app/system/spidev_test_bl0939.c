/*
 * SPI testing utility (using spidev driver)
 *
 * Copyright (c) 2007  MontaVista Software, Inc.
 * Copyright (c) 2007  Anton Vorontsov <avorontsov@ru.mvista.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License.
 *
 * Cross-compile with cross-gcc -I/path/to/cross-kernel/include
 */

#include <stdint.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/types.h>
#include <linux/spi/spidev.h>
#include <sys/select.h>

// ---------------------------------------------queue start
#include <stdlib.h>
#include <string.h>

#define MAX_ELEM_SIZE 17
typedef uint32_t elem_t;
typedef struct cirque
{
	elem_t data[MAX_ELEM_SIZE];
	int head;
	int tail;
}cirque_t;
enum ERROR
{
	C_QUEUE_EMPTY=-3,
	C_QUEUE_FULL=-2,
	C_QUEUE_MALLOC_ERR=0,
	C_QUEUE_ERR=-1,
	C_QUEUE_OK=1,
};
cirque_t *CreatQueue(void);//创建队列
int IsFull(cirque_t *queue);//检测队列是否为满队列
int PushQueue(cirque_t *queue,elem_t *elem);//进队列
int IsEmpty(cirque_t *queue);//检测是否为空队列
int PopQueue(cirque_t *queue,elem_t *elem);//出队列
int DistoryQueue(cirque_t *queue);//销毁队列
int GetLen(cirque_t *queue);//获取当前队列长度
int ReinitQueue(cirque_t *queue);//重新初始化队列
int PrintfQueue(cirque_t *queue);//打印队列----测试时使用
cirque_t *CreatQueue(void)//创建队列
{
	cirque_t *newqueue=(cirque_t *)malloc(sizeof(cirque_t));
	if(NULL==newqueue)
		return C_QUEUE_MALLOC_ERR;
	memset(newqueue,0,sizeof(cirque_t));
	return newqueue;
}
int IsFull(cirque_t *queue)//检测队列是否为满队列
{
	return queue->head==(queue->tail+1)%MAX_ELEM_SIZE;
}
int PushQueue(cirque_t *queue,elem_t *elem)//进队列
{
	if(NULL==queue)
		return C_QUEUE_ERR;
	else if(IsFull(queue))
		return C_QUEUE_FULL;
	queue->data[queue->tail]=*elem;
	queue->tail=(queue->tail+1)%MAX_ELEM_SIZE;
	return C_QUEUE_OK;

}

int IsEmpty(cirque_t *queue)//检测是否为空队列
{
	return queue->head==queue->tail;
}

int PopQueue(cirque_t *queue,elem_t *elem)//出队列
{
	if(NULL==queue)
		return C_QUEUE_ERR;
	else if(IsEmpty(queue))
		return C_QUEUE_EMPTY;
	*elem=queue->data[queue->head];
	queue->head=(queue->head+1)%MAX_ELEM_SIZE;

	return C_QUEUE_OK;
}

int DistoryQueue(cirque_t *queue)//销毁队列
{
	if(NULL==queue)
		return C_QUEUE_ERR;
	queue->head=0;
	queue->tail=0;
	free(queue);
	return C_QUEUE_OK;
}

int GetLen(cirque_t *queue)//获取当前队列长度
{
	return (queue->tail-queue->head+MAX_ELEM_SIZE)%MAX_ELEM_SIZE;
}

int ReinitQueue(cirque_t *queue)//重新初始化队列
{
	if(NULL==queue)
		return C_QUEUE_ERR;
	queue->head=queue->tail=0;
	memset(queue,0,sizeof(MAX_ELEM_SIZE*sizeof(elem_t)));
	return C_QUEUE_OK;
}

int PrintfQueue(cirque_t *queue)//打印队列----测试时使用
{
	if(NULL==queue)
		return C_QUEUE_ERR;
	int i;
	for(i=queue->head;i<queue->tail;i++)
		printf("%d ",queue->data[i]);
	return C_QUEUE_OK;
}

// ---------------------------------------------queue end
// ---------------------------------------------bl0939 start

struct bl0939_val_st {
	cirque_t chA; // 队列
	cirque_t chB;
	uint32_t vtg;
}; // val struct

struct bl0939_val_st g_bvs;
uint32_t g_bvs_rtm_count;

struct bl0939_val_st_tmp {
	uint32_t chA[MAX_ELEM_SIZE];
	uint32_t chB[MAX_ELEM_SIZE];
	uint32_t vtg;
};
// int bl0939_get_all_xqueue(struct bl0939_val_st *bvs)
// {
// 	for (int i = 0; i < GetLen(bvs); i++) {

// 	}
// 	return GetLen(bvs);
// }
void bl0939_print_qu(uint32_t *buf)
{
	int i;
	printf("[");
	for (i = 0; i < MAX_ELEM_SIZE; i++) {
		// if (buf[i] & (0xff << 24)) {
		printf("%.2X, ",buf[i] & 0xffffff);
		// }
	}
	printf("]");
}


// ---------------------------------------------bl0939 end
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

static void pabort(const char *s)
{
	perror(s);
	abort();
}

static const char *device = "/dev/spidev32766.1";
static uint32_t mode;
static uint8_t bits = 8;
static uint32_t speed = 800000; // 500000; change to 800 KHz
static uint16_t delay;

static void transfer(int fd)
{
	int ret;
	uint8_t tx[] = {
		0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
		0x40, 0x00, 0x00, 0x00, 0x00, 0x95,
		0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
		0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
		0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
		0xDE, 0xAD, 0xBE, 0xEF, 0xBA, 0xAD,
		0xF0, 0x0D,
	};
	uint8_t rx[ARRAY_SIZE(tx)] = {0, };
	struct spi_ioc_transfer tr = {
		.tx_buf = (unsigned long)tx,
		.rx_buf = (unsigned long)rx,
		.len = ARRAY_SIZE(tx),
		.delay_usecs = delay,
		.speed_hz = speed,
		.bits_per_word = bits,
	};

	if (mode & SPI_TX_QUAD)
		tr.tx_nbits = 4;
	else if (mode & SPI_TX_DUAL)
		tr.tx_nbits = 2;
	if (mode & SPI_RX_QUAD)
		tr.rx_nbits = 4;
	else if (mode & SPI_RX_DUAL)
		tr.rx_nbits = 2;
	if (!(mode & SPI_LOOP)) {
		if (mode & (SPI_TX_QUAD | SPI_TX_DUAL))
			tr.rx_buf = 0;
		else if (mode & (SPI_RX_QUAD | SPI_RX_DUAL))
			tr.tx_buf = 0;
	}

	ret = ioctl(fd, SPI_IOC_MESSAGE(1), &tr);
	if (ret < 1)
		pabort("can't send spi message");

	for (ret = 0; ret < ARRAY_SIZE(tx); ret++) {
		if (!(ret % 6))
			puts("");
		printf("%.2X ", rx[ret]);
	}
	puts("");
}

static uint32_t bl0939_read_reg(int fd, uint8_t reg)
{
	uint8_t tx[2] = {0x55,reg};
	uint8_t rx[4] = {0};

	struct spi_ioc_transfer tr[2] = {
    {
      .tx_buf = (unsigned long)tx,
      // .rx_buf = (unsigned long)rx,
      .len = ARRAY_SIZE(tx),
      .delay_usecs = delay,
      .speed_hz = speed,
      .bits_per_word = bits,
    },
    {
      // .tx_buf = (unsigned long)tx,
      .rx_buf = (unsigned long)rx,
      .len = ARRAY_SIZE(rx),
      .delay_usecs = delay,
      .speed_hz = speed,
      .bits_per_word = bits,
    }
  };

  int ret = ioctl(fd, SPI_IOC_MESSAGE(2), &tr);
	if (ret < 1)
		pabort("can't send spi message");

  uint32_t val = 0;
	// if(rx_buf[5] == (uint8_t)~(0x55+reg+rx_buf[2]+rx_buf[3]+rx_buf[4]))
	{
		val =	(uint32_t)rx[0]<<16|
						(uint32_t)rx[1]<<8|
						(uint32_t)rx[2]<<0;
	}
	return val;
}

uint32_t r_temp = 0;
static int bl0939_write_reg(int fd, uint8_t reg, uint32_t val,int check)
{
	// int i = 5;
	uint8_t h = val >> 16;
	uint8_t m = val >> 8;
	uint8_t l = val >> 0;
	// do{
	// 	i--;
	// 	HAL_Delay(5);
  	//  bl0939_spi_reset();
		uint8_t tx[6] = {0xA5,reg,h,m,l,~(0XA5+reg+h+m+l)};
    struct spi_ioc_transfer tr[1] = {
      {
        .tx_buf = (unsigned long)tx,
        // .rx_buf = (unsigned long)rx,
        .len = ARRAY_SIZE(tx),
        .delay_usecs = delay,
        .speed_hz = speed,
        .bits_per_word = bits,
      }
    };

    int ret = ioctl(fd, SPI_IOC_MESSAGE(1), &tr);
    if (ret < 1)
      pabort("can't send spi message");

		// HAL_SPI_Transmit(&hspi1,tx_buf,6,0xfff);
		// HAL_Delay(10);
		if(0 == check)
			return 0;
		r_temp = bl0939_read_reg(fd, reg);
		if(r_temp == val)
			return 0;
	// }while(i>0);
	return 1;
}

static void bl0939_spi_reset(int fd)
{
	uint8_t tx[6] = {0xff,0xff,0xff,0xff,0xff,0xff};
	// HAL_SPI_Transmit(&hspi1,tx_buf,6,0xfff);
  struct spi_ioc_transfer tr[1] = {
    {
      .tx_buf = (unsigned long)tx,
      // .rx_buf = (unsigned long)rx,
      .len = ARRAY_SIZE(tx),
      .delay_usecs = delay,
      .speed_hz = speed,
      .bits_per_word = bits,
    }
  };

  int ret = ioctl(fd, SPI_IOC_MESSAGE(1), &tr);
  if (ret < 1)
    pabort("can't send spi message");
}

static void bl0939_reset(int fd)
{
	bl0939_spi_reset(fd);
	bl0939_write_reg(fd, 0x19,0x005a5a5a,0);//复位用户寄存器
	bl0939_write_reg(fd, 0x1a,0x00000055,1);//解除写保护
	bl0939_write_reg(fd, 0x10,0xffff,0);//Threshold A
	bl0939_write_reg(fd, 0x1E,0xffff,1);//Threshold B
//B 通道漏电/过流报警输出指示管脚为 I_leak，无需配置即可直接输出。
//A 通道漏电/过流报警输出指示引脚为 CF，需先设置 MODE[12]=1，再设置 TPS_CTRL[14]=1
//高有效
	bl0939_write_reg(fd, 0x18,0x00002000,1);//cf
	bl0939_write_reg(fd, 0x1B,0x000047ff,0);//cf
	bl0939_write_reg(fd, 0x1a,0x00000000,1);//写保护
}

//T = 40ms
static uint32_t bl0939_get_current_A(int fd)
{
	bl0939_spi_reset(fd);
	uint32_t Ia = bl0939_read_reg(fd, 0x00);
//	return Ia * 1.218f / (float) ( 324004 * 1 );
	return Ia;
}
//T = 40ms
static uint32_t bl0939_get_current_B(int fd)
{
	bl0939_spi_reset(fd);
	uint32_t Ib = bl0939_read_reg(fd, 0x07);
//	return Ib * 1.218f / (float) ( 324004 * 1 );
	return Ib;
}
//T = 400ms
static uint32_t bl0939_get_voltage(int fd)
{
	bl0939_spi_reset(fd);
	uint32_t v = bl0939_read_reg(fd, 0x06);
//	return v * 1.218f * ( 2 + 2000 ) / (float) ( 79931 * 2 * 1000 );
	return v;
}

static void print_usage(const char *prog)
{
	printf("Usage: %s [-DsbdlHOLC3]\n", prog);
	puts("  -D --device   device to use (default /dev/spidev1.1)\n"
	     "  -s --speed    max speed (Hz)\n"
	     "  -d --delay    delay (usec)\n"
	     "  -b --bpw      bits per word \n"
	     "  -l --loop     loopback\n"
	     "  -H --cpha     clock phase\n"
	     "  -O --cpol     clock polarity\n"
	     "  -L --lsb      least significant bit first\n"
	     "  -C --cs-high  chip select active high\n"
	     "  -3 --3wire    SI/SO signals shared\n"
	     "  -N --no-cs    no chip select\n"
	     "  -R --ready    slave pulls low to pause\n"
	     "  -2 --dual     dual transfer\n"
	     "  -4 --quad     quad transfer\n");
	exit(1);
}

static void parse_opts(int argc, char *argv[])
{
	while (1) {
		static const struct option lopts[] = {
			{ "device",  1, 0, 'D' },
			{ "speed",   1, 0, 's' },
			{ "delay",   1, 0, 'd' },
			{ "bpw",     1, 0, 'b' },
			{ "loop",    0, 0, 'l' },
			{ "cpha",    0, 0, 'H' },
			{ "cpol",    0, 0, 'O' },
			{ "lsb",     0, 0, 'L' },
			{ "cs-high", 0, 0, 'C' },
			{ "3wire",   0, 0, '3' },
			{ "no-cs",   0, 0, 'N' },
			{ "ready",   0, 0, 'R' },
			{ "dual",    0, 0, '2' },
			{ "quad",    0, 0, '4' },
			{ NULL, 0, 0, 0 },
		};
		int c;

		c = getopt_long(argc, argv, "D:s:d:b:lHOLC3NR24", lopts, NULL);

		if (c == -1)
			break;

		switch (c) {
		case 'D':
			device = optarg;
			break;
		case 's':
			speed = atoi(optarg);
			break;
		case 'd':
			delay = atoi(optarg);
			break;
		case 'b':
			bits = atoi(optarg);
			break;
		case 'l':
			mode |= SPI_LOOP;
			break;
		case 'H':
			mode |= SPI_CPHA;
			break;
		case 'O':
			mode |= SPI_CPOL;
			break;
		case 'L':
			mode |= SPI_LSB_FIRST;
			break;
		case 'C':
			mode |= SPI_CS_HIGH;
			break;
		case '3':
			mode |= SPI_3WIRE;
			break;
		case 'N':
			mode |= SPI_NO_CS;
			break;
		case 'R':
			mode |= SPI_READY;
			break;
		case '2':
			mode |= SPI_TX_DUAL;
			break;
		case '4':
			mode |= SPI_TX_QUAD;
			break;
		default:
			print_usage(argv[0]);
			break;
		}
	}
	if (mode & SPI_LOOP) {
		if (mode & SPI_TX_DUAL)
			mode |= SPI_RX_DUAL;
		if (mode & SPI_TX_QUAD)
			mode |= SPI_RX_QUAD;
	}
}

int main(int argc, char *argv[])
{
	int ret = 0;
	int fd;

	parse_opts(argc, argv);

	fd = open(device, O_RDWR);
	if (fd < 0)
		pabort("can't open device");

	mode |= SPI_CPHA; // bl0939 default mode 1

	/*
	 * spi mode
	 */
	ret = ioctl(fd, SPI_IOC_WR_MODE32, &mode);
	if (ret == -1)
		pabort("can't set spi mode");

	ret = ioctl(fd, SPI_IOC_RD_MODE32, &mode);
	if (ret == -1)
		pabort("can't get spi mode");

	/*
	 * bits per word
	 */
	ret = ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, &bits);
	if (ret == -1)
		pabort("can't set bits per word");

	ret = ioctl(fd, SPI_IOC_RD_BITS_PER_WORD, &bits);
	if (ret == -1)
		pabort("can't get bits per word");

	/*
	 * max speed hz
	 */
	ret = ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed);
	if (ret == -1)
		pabort("can't set max speed hz");

	ret = ioctl(fd, SPI_IOC_RD_MAX_SPEED_HZ, &speed);
	if (ret == -1)
		pabort("can't get max speed hz");

	printf("spi mode: 0x%x\n", mode);
	printf("bits per word: %d\n", bits);
	printf("max speed: %d Hz (%d KHz)\n", speed, speed/1000);

	// transfer(fd);

	// loop
#if 1
	memset(&g_bvs,0,sizeof(g_bvs));
	g_bvs_rtm_count = 0;

	fd_set recvfd,tempfd;
	FD_ZERO(&recvfd);
	FD_ZERO(&tempfd);
	FD_SET(fd,&recvfd);
	FD_SET(STDIN_FILENO,&recvfd);
	int maxid=(server_sock>STDIN_FILENO ? server_sock+1:STDIN_FILENO+1);

	struct timeval timeout;
#define TIMEOUT_TIME (20 * 1000)
	unsigned long uSec = TIMEOUT_TIME;
	timeout.tv_sec=uSec/1000000;
	timeout.tv_usec=uSec%1000000;

	while(1) {
		// tempfd=recvfd;
        int ret=select(0,NULL,NULL,NULL,&timeout);
		if(-1==ret){
			perror("select error");
			continue;
		}else if(0==ret){
			// printf("timeout\r\n");
			timeout.tv_sec=uSec/1000000;
			timeout.tv_usec=uSec%1000000; // 20 ms
			g_bvs_rtm_count++;
			if (g_bvs_rtm_count < 20) {
				uint32_t chA_val = bl0939_get_current_A(fd);
				uint32_t chB_val = bl0939_get_current_B(fd);
				// PushQueue(&g_bvs.chA, &chA_val);
				// PushQueue(&g_bvs.chB, &chB_val);
				if(bvst.indexA >= MAX_ELEM_SIZE){
					for(i=0;i<MAX_ELEM_SIZE-1;i++){
						bvst.chA[i] = bvst.chA[i+1];
					}
					bvst.indexA = MAX_ELEM_SIZE -1;
				}
				bvst.chA[bvst.indexA++] = chA_val;
				
				if(bvst.indexB >= MAX_ELEM_SIZE){
					for(i=0;i<MAX_ELEM_SIZE-1;i++){
						bvst.chB[i] = bvst.chB[i+1];
					}
           		 bvst.indexB = MAX_ELEM_SIZE -1;
        		}
        		bvst.chB[bvst.indexB++] = chB_val;
			} else if (g_bvs_rtm_count == 20) { // 400ms
				uint32_t vtg_val = bl0939_get_voltage(fd);
				g_bvs.vtg = vtg_val;
				struct bl0939_val_st_tmp bvst;
				memcpy(bvst.chA, g_bvs.chA.data, sizeof(bvst.chA));
				memcpy(bvst.chB, g_bvs.chB.data, sizeof(bvst.chB));
				bvst.vtg = g_bvs.vtg;
				// bvst - > 输出的结构体

				bl0939_print_qu(bvst.chA);
				bl0939_print_qu(bvst.chB);
				printf("vtg:%u.\r\n", bvst.vtg);

				{
					ReinitQueue(&g_bvs.chA);
					ReinitQueue(&g_bvs.chB);
					g_bvs.vtg = 0;
				}
				g_bvs_rtm_count = 0;
			}
			continue;
		}
		// int tfd=0;
        // for(;tfd<maxid;tfd++){
        //     if(!FD_ISSET(tfd,&tempfd)){
        //         continue;
        //     }
		// 	if(fd==tfd){
		// 		// recv - spidev
		// 	}
		// }
	}
#endif
	// struct bl0939_val_st_tmp bvst;
	// while (1) {
    //     memset(&bvst, 0 ,sizeof(bvst));
    //     int ret = read(fd, &bvst, sizeof(bvst));
    //     if (ret < 0)
    //         printf("error: read, ret:%d.\n", ret);
    //     else {
    //         // printf("info; read: %s, len:%d.\n", read_buf, ret);

    //         bl0939_print_qu(bvst.chA);
    //         bl0939_print_qu(bvst.chB);
    //         printf("asd vtg:%.2X\r\n", bvst.vtg);
    //     }
    //     usleep(10 * 1000);
    // }
	// clear
	close(fd);

	return ret;
}