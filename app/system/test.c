#include <stdio.h>
typedef struct _server_cell_lte {
    char celltype[14];
    char state[8];
    char rat[8];
    char is_tdd[4];
    unsigned int mcc;
    unsigned int mnc;
    char cellid[12];
    char pcid[8];
    char earfcn[12];
    unsigned int freq_band_ind;
    unsigned int ul_bandwidth;
    unsigned int dl_bandwidth;
    char tac[8];
    int rsrp;
    int rsrq;
    int rssi;
    unsigned int sinr;
    unsigned int srxlev;
} server_cell_lte_t;
server_cell_lte_t sclTemp = {0};  // lte mode下的temp
int main() {
    printf("r:0x%x, n:0x%x.\n", '\r', '\n');
    char str[] =
        "+QENG: "
        "\"servingcell\",\"NOCONN\",\"LTE\",\"TDD\",460,00,B314688,218,38950,40,5,5,91D4,-81,-3,-"
        "78,29,43";
    // sscanf(str,
    //        "%*[^:]:\"%[^\"]\",\"%[^\"]\",\"%[^\"]\",\"%[^\"]\",%d,%d,%s,%s,%s,%d,%d,%d,%s,%d,%d,%d,%d,%d",
    //        sclTemp.celltype, sclTemp.state, sclTemp.rat, sclTemp.is_tdd, &sclTemp.mcc, &sclTemp.mnc,
    //        sclTemp.cellid, sclTemp.pcid, sclTemp.earfcn, &sclTemp.freq_band_ind,
    //        &sclTemp.ul_bandwidth, &sclTemp.dl_bandwidth, sclTemp.tac, &sclTemp.rsrp, &sclTemp.rsrq,
    //        &sclTemp.rssi, &sclTemp.sinr, &sclTemp.srxlev);
	char temp[2048] = {0};
    sscanf(str,
           "%*[^:]:%*[^\"]\"%[^\"]%*[^,]%*[^\"]\"%[^\"]%*[^,]%*[^\"]\"%[^\"]%*[^,]%*[^\"]\"%[^\"]%*[^,],%u,%u,%[^,],%[^,],%[^,],%u,%u,%u,%[^,],%d,%d,%d,%u,%u",
           sclTemp.celltype, sclTemp.state, sclTemp.rat, sclTemp.is_tdd, &sclTemp.mcc, &sclTemp.mnc, sclTemp.cellid, sclTemp.pcid, sclTemp.earfcn, 
		   &sclTemp.freq_band_ind, &sclTemp.ul_bandwidth, &sclTemp.dl_bandwidth, sclTemp.tac,&sclTemp.rsrp, &sclTemp.rsrq,
	       &sclTemp.rssi, &sclTemp.sinr, &sclTemp.srxlev);
    printf(
        "cmd <ccid> info recv:\n"
        "celltype       :%s\n"
        "state          :%s\n"
        "rat            :%s\n"
        "is_tdd         :%s\n"
        "mcc            :%d\n"
        "mnc            :%d\n"
        "cellid         :%s\n"
        "pcid           :%s\n"
        "earfcn         :%s\n"
        "freq_band_ind  :%d\n"
        "ul_bandwidth   :%d\n"
        "dl_bandwidth   :%d\n"
        "tac            :%s\n"
        "rsrp           :%d\n"
        "rsrq           :%d\n"
        "rssi           :%d\n"
        "sinr           :%d\n"
        "srxlev         :%d\n"
		"temp:%s\n",
        sclTemp.celltype, sclTemp.state, sclTemp.rat, sclTemp.is_tdd, sclTemp.mcc, sclTemp.mnc,
        sclTemp.cellid, sclTemp.pcid, sclTemp.earfcn, sclTemp.freq_band_ind, sclTemp.ul_bandwidth,
        sclTemp.dl_bandwidth, sclTemp.tac, sclTemp.rsrp, sclTemp.rsrq, sclTemp.rssi, sclTemp.sinr,
        sclTemp.srxlev,
		temp);
}
