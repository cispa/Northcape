#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h> 
#include <linux/net_tstamp.h>
#include <netinet/in.h> 

#include <stdint.h>
#include <inttypes.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

#include <time.h>

#include <nc_benchmark.h>

#define REPETITIONS 100
#define PORT 8080

#define ERR_EXIT(ERR,...) fprintf(stderr, "Error: " ERR "\n" __VA_OPT__(,) __VA_ARGS__); exit(1)

static int64_t durations_rx[REPETITIONS], durations_tx[REPETITIONS];

static int my_socket;

static void do_setup(void){
    const int timestamp_flags = SOF_TIMESTAMPING_SOFTWARE | SOF_TIMESTAMPING_TX_SOFTWARE | SOF_TIMESTAMPING_RX_SOFTWARE;
    int ret;
    struct sockaddr_in servaddr;

    my_socket = socket(AF_INET, SOCK_DGRAM, 0);

    if(my_socket < 0){
        ERR_EXIT("Could not open socket: %s", strerror(errno));
    }

    ret = setsockopt(my_socket, SOL_SOCKET, SO_TIMESTAMPING, &timestamp_flags, sizeof(timestamp_flags));

    if(ret){
        ERR_EXIT("Could not set timestamping: %s", strerror(errno));
    }

    memset(&servaddr, 0, sizeof(servaddr)); 

    servaddr.sin_family    = AF_INET; 
    servaddr.sin_addr.s_addr = INADDR_ANY; 
    servaddr.sin_port = htons(PORT); 

    if(bind(my_socket, (const struct sockaddr *) &servaddr, sizeof(servaddr)) < 0){
        ERR_EXIT("Could not bind port %d: %s", PORT, strerror(errno));
    }
}

#define PACKET_BUFSIZE 2048
#define NAME_BUF_LEN 16

struct sockaddr_in client_addr;

static void do_rx_test(int num){
    struct timespec rx_timestamp, current_time;
    int level, type;
    struct msghdr msg = {};
    struct iovec iov;
    char pktbuf[PACKET_BUFSIZE] = {};
    char name_buf[NAME_BUF_LEN] = {};

    int ret;

    char ctrl[CMSG_SPACE(sizeof(struct timespec))];
    struct cmsghdr *cmsg = (struct cmsghdr *) &ctrl;

    msg.msg_control = (char *) ctrl;
    msg.msg_controllen = sizeof(ctrl);

    msg.msg_name = &client_addr;
    msg.msg_namelen = sizeof(client_addr);
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    iov.iov_base = pktbuf;
    iov.iov_len = sizeof(pktbuf);

    ret = recvmsg(my_socket, &msg, 0);

    if(ret < 0){
        ERR_EXIT("Could not recvmsg(): %s", strerror (errno));
    }

    if(clock_gettime(CLOCK_MONOTONIC_RAW, &current_time)){
        ERR_EXIT("Could not get time: %s", strerror(errno));
    }

    for (cmsg = CMSG_FIRSTHDR(&msg); cmsg != NULL; cmsg = CMSG_NXTHDR(&msg, cmsg))
    {
        level = cmsg->cmsg_level;
        type  = cmsg->cmsg_type;

        if (SOL_SOCKET == level && SO_TIMESTAMPING == type) {
            uint64_t duration = current_time.tv_nsec + current_time.tv_sec * 1000000000;
            //ts = (struct timespec *) CMSG_DATA(cmsg);
            memcpy(&rx_timestamp, CMSG_DATA(cmsg), sizeof(rx_timestamp));
            duration -= (rx_timestamp.tv_nsec + rx_timestamp.tv_sec * 1000000000);
            if(inet_ntop(AF_INET, &client_addr.sin_addr, name_buf, sizeof(name_buf)) == NULL){
                ERR_EXIT("inet_ntop");
            }
            durations_rx[num] = duration;

            printf("Message: %s from: %s\n RX Duration: %"PRIu64" ns\n", pktbuf, name_buf, duration);
        }
    }


}

#define ERRQUEUE_SLEEP_S 1
#define ERRQUEUE_TRIES 10

static void do_tx_test(int num){
    struct timespec tx_timestamp, current_time;
    int level, type;
    struct msghdr msg;
    struct iovec iov;
    char pktbuf[PACKET_BUFSIZE] = {};
    const char *send_msg = "Hello back!";

    int ret;
    int tries;

    char ctrl[CMSG_SPACE(sizeof(struct timespec))];
    struct cmsghdr *cmsg = (struct cmsghdr *) &ctrl;

    msg.msg_control = (char *) ctrl;
    msg.msg_controllen = sizeof(ctrl);

    msg.msg_name = NULL;
    msg.msg_namelen = 0;
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    iov.iov_base = NULL;
    iov.iov_len = 0;


    if(clock_gettime(CLOCK_MONOTONIC_RAW, &current_time)){
        ERR_EXIT("Could not get time: %s", strerror(errno));
    }

    if(sendto(my_socket, send_msg, strlen(send_msg) + 1, 0, (const struct sockaddr *)&client_addr, sizeof(client_addr)) == -1){
        ERR_EXIT("Could not sendto: %s", strerror(errno));
    }

    do{
        ret = recvmsg(my_socket, &msg, MSG_ERRQUEUE);
        tries ++;
        if(ret < 0){
            printf("recvmsg() EAGAIN!\n");
            sleep(1);
        }
    }
    while(ret < 0 && tries < ERRQUEUE_TRIES);

    if(ret < 0){
        ERR_EXIT("Could not recvmsg(): %s", strerror (errno));
    }


    for (cmsg = CMSG_FIRSTHDR(&msg); cmsg != NULL; cmsg = CMSG_NXTHDR(&msg, cmsg))
    {
        level = cmsg->cmsg_level;
        type  = cmsg->cmsg_type;
        if (SOL_SOCKET == level && SO_TIMESTAMPING == type) {
            uint64_t duration;
            //ts = (struct timespec *) CMSG_DATA(cmsg);
            memcpy(&tx_timestamp, CMSG_DATA(cmsg), sizeof(tx_timestamp));
            duration = tx_timestamp.tv_nsec + tx_timestamp.tv_sec * 1000000000;
            duration -= (current_time.tv_nsec + current_time.tv_sec * 1000000000);
            printf("Message: %s\n TX Duration: %"PRIu64" ns\n", send_msg, duration);
            durations_tx[num] = duration;
        }
    }
}

static void do_teardown(void){
    (void)close(my_socket);
}

int main(void){

    printf("Doing setups...\n");

    do_setup();

    printf("Doing RX tests...\n");

    for(int i = 0; i < REPETITIONS; i++){
        do_rx_test(i);
    }

    printf("Doing TX tests...\n");

    for(int i = 0; i < REPETITIONS; i++){
        do_tx_test(i);
    }

    printf("Doing teardown...\n");

    do_teardown();

    nc_benchmark_evaluate_samples(durations_rx, REPETITIONS, 0, "RX durations");
    nc_benchmark_evaluate_samples(durations_tx, REPETITIONS, 0, "TX durations");

    printf("Done\n");
}
