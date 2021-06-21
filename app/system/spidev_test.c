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

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

static void pabort(const char *s)
{
	perror(s);
	abort();
}

static const char *device = "/dev/spidev32766.1";
static uint32_t mode;
static uint8_t bits = 8;
static uint32_t speed = 800000;
static uint16_t delay;

static void transfer(int fd)
{
	int ret;
	uint8_t tx[] = {
		0x55,0x00,0x00,0x00,0x00,0x00,
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
	printf("ret:%d\r\n ", ret);
	for (ret = 0; ret < ARRAY_SIZE(tx); ret++) {
		if (!(ret % 6))
			puts("");
		printf("%.2X ", rx[ret]);
	}
	puts("");
}

unsigned char g_rx_buf[1024];
unsigned char g_tx_buf[1024];

static int bl0939_read_reg(int fd, unsigned char reg)
{
	int ret, val;
	g_tx_buf[0] = 0x55;
	g_tx_buf[1] = reg;
	struct spi_ioc_transfer tr[2] = {{
		.tx_buf = (unsigned long)g_tx_buf,
		.rx_buf = NULL,
		.len = 2,
		.delay_usecs = delay,
		.speed_hz = speed,
		.bits_per_word = bits,
	},
	{
		.tx_buf = NULL,
		.rx_buf = (unsigned long)g_rx_buf,
		.len = 4,
		.delay_usecs = delay,
		.speed_hz = speed,
		.bits_per_word = bits,
	}
	};

	// if (mode & SPI_TX_QUAD)
	// 	tr.tx_nbits = 4;
	// else if (mode & SPI_TX_DUAL)
	// 	tr.tx_nbits = 2;
	// if (mode & SPI_RX_QUAD)
	// 	tr.rx_nbits = 4;
	// else if (mode & SPI_RX_DUAL)
	// 	tr.rx_nbits = 2;
	// if (!(mode & SPI_LOOP)) {
	// 	if (mode & (SPI_TX_QUAD | SPI_TX_DUAL))
	// 		tr.rx_buf = 0;
	// 	else if (mode & (SPI_RX_QUAD | SPI_RX_DUAL))
	// 		tr.tx_buf = 0;
	// }
	// tr.tx_nbits = 1;

	ret = ioctl(fd, SPI_IOC_MESSAGE(2), tr);
	if (ret < 1)
		pabort("can't send spi message");

	// for (ret = 0; ret < ARRAY_SIZE(g_tx_buf); ret++) {
	// 	if (!(ret % 6))
	// 		puts("");
	// 	printf("%.2X ", g_rx_buf[ret]);
	// }
	// puts("");
	printf("%02x,%02x,%02x,%02x,",g_rx_buf[0], g_rx_buf[1], g_rx_buf[2], g_rx_buf[3]);
    // if (g_rx_buf[5] == 
    //     (unsigned char)~(0x55 + reg + g_rx_buf[2] + g_rx_buf[3] + g_rx_buf[4]))
	{
		val = (unsigned int)g_rx_buf[0] << 16 |
						(unsigned int)g_rx_buf[1] << 8 |
						(unsigned int)g_rx_buf[2] << 0;
	}
	return val;
	// return ret;
}

// static unsigned int bl0939_read_reg(int fd, unsigned char reg)
// {
// 	// struct spidev_data *priv = spidev;
// 	unsigned int val = 0;
// 	g_tx_buf[0] = 0x55;
// 	g_tx_buf[1] = reg;
// 	g_tx_buf[2] = 0;
// 	g_tx_buf[3] = 0;
//     g_tx_buf[4] = 0;
//     g_tx_buf[5] = 0;

// 	bl0939_spi_trans(fd, 6);
// 	printf("%02x,%02x,%02x,%02x,%02x,%02x,",g_rx_buf[0], g_rx_buf[1], g_rx_buf[2], g_rx_buf[3], g_rx_buf[4], g_rx_buf[5]);
//     if (g_rx_buf[5] == 
//         (unsigned char)~(0x55 + reg + g_rx_buf[2] + g_rx_buf[3] + g_rx_buf[4]))
// 	{
// 		val = (unsigned int)g_rx_buf[2] << 16 |
// 						(unsigned int)g_rx_buf[3] << 8 |
// 						(unsigned int)g_rx_buf[4] << 0;
// 	}
// 	return val;
// }

unsigned int r_temp = 0;
static int bl0939_write_reg(int fd, unsigned char reg, unsigned int val, int check)
{
	unsigned char h = val >> 16;
	unsigned char m = val >> 8;
	unsigned char l = val >> 0;

	g_tx_buf[0] = 0xA5;
	g_tx_buf[1] = reg;
	g_tx_buf[2] = h;
	g_tx_buf[3] = m;
	g_tx_buf[4] = l;
	g_tx_buf[5] = ~(0XA5 + reg + h + m + l);
	// bl0939_spi_trans(fd, 6);

	struct spi_ioc_transfer tr[1] = {{
		.tx_buf = (unsigned long)g_tx_buf,
		.rx_buf = NULL,
		.len = 6,
		.delay_usecs = delay,
		.speed_hz = speed,
		.bits_per_word = bits,
	}
	};

	int ret = ioctl(fd, SPI_IOC_MESSAGE(1), tr);
	if (ret < 1)
		pabort("can't send spi message");

	if(0 == check)
		return 0;
	r_temp = bl0939_read_reg(fd, reg);
	if (r_temp == val)
		return 0;
	return -1;
}

static void bl0939_spi_reset(int fd)
{
    uint8_t i;
    for (i = 0; i < 6; i++) {
        g_tx_buf[i] = 0xff;
    }
	// bl0939_spi_trans(fd, 6);
	struct spi_ioc_transfer tr[1] = {{
		.tx_buf = (unsigned long)g_tx_buf,
		.rx_buf = NULL,
		.len = 6,
		.delay_usecs = delay,
		.speed_hz = speed,
		.bits_per_word = bits,
	}
	};

	int ret = ioctl(fd, SPI_IOC_MESSAGE(1), tr);
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
unsigned int bl0939_get_current_A(int fd)
{
    unsigned int Ia = 0;
	// bl0939_spi_reset(fd);
	Ia = bl0939_read_reg(fd, 0x00);
//	return Ia * 1.218f / (float) ( 324004 * 1 );
	return Ia;
}
//T = 40ms
unsigned int bl0939_get_current_B(int fd)
{
    unsigned int Ib = 0;
	// bl0939_spi_reset(fd);
	Ib = bl0939_read_reg(fd, 0x07);
//	return Ib * 1.218f / (float) ( 324004 * 1 );
	return Ib;
}
//T = 400ms
unsigned int bl0939_get_voltage(int fd)
{
    unsigned int v = 0;
	// bl0939_spi_reset(fd);
	v = bl0939_read_reg(fd, 0x06);
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

	bl0939_reset(fd);
	while(1) {
		printf("chA: 0x%x\n", bl0939_get_current_A(fd));
		printf("chV: 0x%x\n", bl0939_get_current_B(fd));
		printf("vtg: 0x%x\n", bl0939_get_voltage(fd));
		usleep(400*1000);
	}
	transfer(fd);

	close(fd);

	return ret;
}
