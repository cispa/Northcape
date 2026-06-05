#include <stdio.h>
#include <stdlib.h>
#include <mosquitto.h>
#include <errno.h>
#include <time.h>
#include <string.h>

#include <nc_benchmark.h>

#define WITH_AUTHENTICATION

#define TARGET_USER     "foo"
#define TARGET_PW       "bar"
#define TARGET_TOPIC    "sensors"

#define ERR_EXIT(fmt, ...) fprintf(stderr, "[FATAL]" fmt "\n" __VA_OPT__ (,) __VA_ARGS__); exit(1)
#define LIBMOSQUITTO_ERR_EXIT(err)                                                                        \
    if(err){                                                                                                    \
        ERR_EXIT("Libmosquitto error: %s at %s:%d", mosquitto_strerror(err), __FILE__, __LINE__);    \
    }

#define REPETITIONS 100


#define SEC_TO_NSEC(SEC)((SEC)*1000000000)

static int message_ids[REPETITIONS];

int64_t durations[REPETITIONS];

static char *get_mqtt_payload(int qos){
    static char payload[] = "DOORS:OPEN_QoSx";

	payload[strlen(payload) - 1] = '0' + qos;

    return payload;
}

int main(int argc, char *argv[])
{
    uint8_t reconnect       = true;
    struct mosquitto *mosq  = NULL;
    int err             = 0;
    bool use_tls = false;
    int mqtt_port;

    mosquitto_lib_init ();

    mosq    = mosquitto_new ("linux", true, NULL);

    if(!mosq){
        fprintf(stderr, "Could not create mosquitto instance!\n");
        return 1;
    }

    if(argc < 3){
        fprintf(stderr, "Usage: %s <host> <port>\n\t%s <host> <port> <ca certificate file>\n", argv[0], argv[0]);
        return 1;
    }
    if(argc > 3){
        use_tls = true;
    }

    errno = 0;
    mqtt_port = strtol(argv[2], NULL, 10);
    if(errno){
        perror("strtol");
        return 1;
    }

    if(mosq){

        err = mosquitto_username_pw_set(mosq, TARGET_USER, TARGET_PW);
        LIBMOSQUITTO_ERR_EXIT(err);
        
        if(use_tls){
            err = mosquitto_tls_insecure_set(mosq, true);
            LIBMOSQUITTO_ERR_EXIT(err);

            err = mosquitto_tls_opts_set(mosq, 1, NULL, NULL);
            LIBMOSQUITTO_ERR_EXIT(err);

            printf("Setting CA file %s\n", argv[3]);
            
            err = mosquitto_tls_set(mosq, argv[3], NULL, NULL, NULL, NULL);
            LIBMOSQUITTO_ERR_EXIT(err);

        }

        printf("If you are using TLS, make sure that the date is correct:\ndate -s \"YYYY-MM-DD HH:MM:SS\"\n");

        err = mosquitto_connect(mosq, argv[1], mqtt_port, 60);
        LIBMOSQUITTO_ERR_EXIT(err);

        


        for(int i = 0; i < REPETITIONS; i++){
            uint64_t time_start, time_end;
            struct timespec tp;
            
            err = clock_gettime(CLOCK_MONOTONIC, &tp);
            if(err){
                ERR_EXIT("Could not get time: %s", strerror(errno));
            }

            time_start = SEC_TO_NSEC(tp.tv_sec) + tp.tv_nsec;

            err = mosquitto_loop(mosq, 500, 1);
            LIBMOSQUITTO_ERR_EXIT(err);

            for(int qos = 0; qos < 2; qos++){
                err = mosquitto_publish(mosq, &message_ids[i], TARGET_TOPIC, strlen(get_mqtt_payload(qos)), get_mqtt_payload(qos), qos, false);
                LIBMOSQUITTO_ERR_EXIT(err);

                err = mosquitto_loop(mosq, 500, 1);
                LIBMOSQUITTO_ERR_EXIT(err);
            }

            err = clock_gettime(CLOCK_MONOTONIC, &tp);
            if(err){
                ERR_EXIT("Could not get time: %s", strerror(errno));
            }
            
            time_end = SEC_TO_NSEC(tp.tv_sec) + tp.tv_nsec;

            durations[i] = time_end - time_start;
        }

        nc_benchmark_evaluate_samples(durations, REPETITIONS, 0, use_tls ? "MQTT TLS times" : "MQTT times");

        mosquitto_destroy (mosq);
    }

    mosquitto_lib_cleanup ();

    return 0;
}
