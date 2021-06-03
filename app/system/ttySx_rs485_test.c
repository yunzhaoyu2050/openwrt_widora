#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <termios.h>
#include <errno.h>
#include <string.h>
#include <pthread.h>
#include <signal.h>
#include <unistd.h>
#include <stdio.h>
#include <termios.h>
#include <fcntl.h>
#include <string.h>
#include <time.h>
#include <stdint.h>
#include <errno.h>
/*
 * Serial interface for controlling RS485 settings on chips with suitable
 * support. Set with TIOCSRS485 and get with TIOCGRS485 if supported by your
 * platform. The set function returns the new state, with any unsupported bits
 * reverted appropriately.
 */

struct serial_rs485
{
  uint32_t flags;                         /* RS485 feature flags */
#define SER_RS485_ENABLED (1 << 0)        /* If enabled */
#define SER_RS485_RTS_ON_SEND (1 << 1)    /* Logical level for \
                         RTS pin when                          \
                         sending */
#define SER_RS485_RTS_AFTER_SEND (1 << 2) /* Logical level for \
                         RTS pin after sent*/
#define SER_RS485_RX_DURING_TX (1 << 4)
  uint32_t delay_rts_before_send; /* Delay before send (milliseconds) */
  uint32_t delay_rts_after_send;  /* Delay after send (milliseconds) */
  uint32_t padding[5];            /* Memory is cheap, new structs
					   are a royal PITA .. */
};

int speed_arr[] = {
    B115200,
    B57600,
    B38400,
    B19200,
    B9600,
    B4800,
    B2400,
    B1200,
    B300,
    B115200,
    B57600,
    B38400,
    B19200,
    B9600,
    B4800,
    B2400,
    B1200,
    B300,
};

int name_arr[] = {
    115200,
    57600,
    38400,
    19200,
    9600,
    4800,
    2400,
    1200,
    300,
    115200,
    57600,
    38400,
    19200,
    9600,
    4800,
    2400,
    1200,
    300,
};

/*----------------------------------------------------------------------------- 
  函数名:      set_speed 
  参数:        int fd ,int speed 
  返回值:      void 
  描述:        设置fd表述符的串口波特率 
 *-----------------------------------------------------------------------------*/
void set_speed(int fd, int speed)
{
  struct termios opt;
  int i;
  int status;

  tcgetattr(fd, &opt);
  for (i = 0; i < sizeof(speed_arr) / sizeof(int); i++)
  {
    if (speed == name_arr[i]) //找到标准的波特率与用户一致
    {
      tcflush(fd, TCIOFLUSH);          //清除IO输入和输出缓存
      cfsetispeed(&opt, speed_arr[i]); //设置串口输入波特率
      cfsetospeed(&opt, speed_arr[i]); //设置串口输出波特率

      status = tcsetattr(fd, TCSANOW, &opt); //将属性设置到opt的数据结构中，并且立即生效
      if (status != 0)
        perror("tcsetattr fd:"); //设置失败
      return;
    }
    tcflush(fd, TCIOFLUSH); //每次清除IO缓存
  }
}
/*----------------------------------------------------------------------------- 
  函数名:      set_parity 
  参数:        int fd 
  返回值:      int 
  描述:        设置fd表述符的奇偶校验 
 *-----------------------------------------------------------------------------*/
int set_parity(int fd)
{
  struct termios opt;

  if (tcgetattr(fd, &opt) != 0) //或许原先的配置信息
  {
    perror("Get opt in parity error:");
    return -1;
  }

  /*通过设置opt数据结构，来配置相关功能，以下为八个数据位，不使能奇偶校验*/
  opt.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
  opt.c_oflag &= ~OPOST;
  opt.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
  opt.c_cflag &= ~(CSIZE | PARENB);
  opt.c_cflag |= CS8;

  tcflush(fd, TCIFLUSH); //清空输入缓存

  if (tcsetattr(fd, TCSANOW, &opt) != 0)
  {
    perror("set attr parity error:");
    return -1;
  }

  return 0;
}
/*----------------------------------------------------------------------------- 
  函数名:      serial_init 
  参数:        char *dev_path,int speed,int is_block 
  返回值:      初始化成功返回打开的文件描述符 
  描述:        串口初始化，根据串口文件路径名，串口的速度，和串口是否阻塞,
block为1表示阻塞 
 *-----------------------------------------------------------------------------*/
int serial_init(char *dev_path, int speed, int is_block)
{
  int fd;
  int flag;

  flag = 0;
  flag |= O_RDWR; //设置为可读写的串口属性文件
  if (is_block == 0)
    flag |= O_NONBLOCK; //若为0则表示以非阻塞方式打开

  fd = open(dev_path, flag); //打开设备文件
  if (fd < 0)
  {
    perror("Open device file err:");
    close(fd);
    return -1;
  }

  /*打开设备文件后，下面开始设置波特率*/
  set_speed(fd, speed); //考虑到波特率可能被单独设置，所以独立成函数

  /*设置奇偶校验*/
  if (set_parity(fd) != 0)
  {
    perror("set parity error:");
    close(fd); //一定要关闭文件，否则文件一直为打开状态
    return -1;
  }

  return fd;
}

#define TTYS_485_DEV_PATH "/dev/ttyS1" // default dev

int main(int argc, const char *argv[])
{
  /*
    int fd = open(TTYS_485_DEV_PATH,  O_RDWR | O_NOCTTY);
    if (fd < 0)
        return -1;
    */

  int fd = serial_init(TTYS_485_DEV_PATH, 9600, 1);
  int ret = 0;
  struct serial_rs485 rs485conf;
  rs485conf.flags |= SER_RS485_ENABLED;
  rs485conf.flags |= SER_RS485_RTS_ON_SEND;
  rs485conf.flags |= SER_RS485_RTS_AFTER_SEND;
  ret = ioctl(fd, TIOCSRS485, &rs485conf);
  if (ret < 0) {
    printf("error: ioctl rs485 failed. ret:%d, err:%d.\r\n", ret, errno);
    return -1;
  }
  char send_buf[64] = "123456789abcdefghigklmnopqrstuvwlllllllll";
  char read_buf[64] = {0};
  printf("info: write <%s>, sleep 1s loop.\r\n", send_buf);

  while (1)
  {
    ret = write(fd, send_buf, strlen(send_buf));
    if (ret < 0)
      printf("error: write, ret:%d.\n", ret);
    // else
    //   printf("info; write: %s, len:%d.\n", send_buf, ret);

    /* read */
    // ret = read(fd, read_buf, 63);
    // if (ret < 0)
    //   printf("error: read, ret:%d.\n", ret);;
    // else
    //   printf("info; read: %s, len:%d.\n", read_buf, ret);

    sleep(1);
  }
}
