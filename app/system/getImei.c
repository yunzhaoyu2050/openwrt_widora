#include <fcntl.h>
#include <getopt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <unistd.h>

static const char *device = "/dev/ttyUSB2";
static char timer_count = 120; // 2 min
// static const char *imeiFile = "/etc/imei";

static void print_usage(const char *prog) {
    printf("Usage: %s [-pthi]\n", prog);
    puts(
        "  -p --port   device to use (default /dev/ttyUSB2)\n"
        // "  -i --imei     imei save file path (default /etc/imei)\n"
        "  -c --count    count get (default 120[s])\n"
        "  -h            help\n");
    exit(1);
}

static void parse_opts(int argc, char *argv[]) {
    while (1) {
        static const struct option lopts[] = {
            {"port", 1, 0, 'p'}, {"count", 1, 0, 'c'}, /*{"imei", 1, 0, 'i'}, */{NULL, 0, 0, 0},
        };
        int c;
        c = getopt_long(argc, argv, "D:c:h", lopts, NULL);
        if (c == -1)
            break;

        switch (c) {
        case 'p':
            device = optarg;
            break;
        case 'c':
            timer_count = atoi(optarg);
            break;
        /*case 'i':
            imeiFile = optarg;
            break;*/
        default:
            print_usage(argv[0]);
            break;
        }
    }
}

const char *cgsncmd = "AT+CGSN\r\n";

int main(int argc, char *argv[]) {
    parse_opts(argc, argv);

    int smd_fd = -1;
    char imei[16] = "860000000000000";
    smd_fd = open(device, O_RDWR | O_NONBLOCK | O_NOCTTY);
    if (smd_fd >= 0) {
        int iRet;
        int n, ret;
        fd_set fds;
        struct timeval timeout = {1, 0};
        char rxbuf[256] = {0};
        FD_ZERO(&fds);
        FD_SET(smd_fd, &fds);
        for (n = 0; n < timer_count; n++) {
            iRet = write(smd_fd, cgsncmd, strlen(cgsncmd));
            ret = select(smd_fd + 1, &fds, NULL, NULL, &timeout);
            if (ret > 0) {
                memset(rxbuf, 0, sizeof(rxbuf));
                iRet = read(smd_fd, rxbuf, 256);
                if (iRet > 0) {
                    int i = 0;
                    char *p = strchr(rxbuf, '8');
                    if (p != NULL) {
                        while (*p >= '0' && *p <= '9') {
                            if (i >= sizeof(imei))
                                break;
                            imei[i++] = *p++;
                        }
                        imei[i] = '\0';
                        // int iFd = open(imeiFile, O_RDWR | O_CREAT);
                        // if (iFd < 0) {
                        //     printf("[ERROR]: open %s failed.\n", imeiFile);
                        //     goto SU_END;
                        // } else {
                        //     ftruncate(iFd, 0);
                        //     lseek(iFd, 0, SEEK_SET);
                        //     ret = write(iFd, imei, strlen(imei));
                        //     if (ret < 0) {
                        //         printf("[ERROR]: write %s failed. ret:%d.\n", imeiFile,
                        //                ret);
                        //     }
                        //     close(iFd);
                        // }
                        printf("IMEI:%s", imei);
                        goto SU_END;
                    }
                }
            }
        }
        printf("ERROR:can't get imei, please module.");
    SU_END:
        close(smd_fd);
        return 0;
    }
    printf("ERROR:open failed.");
    return -1;
}