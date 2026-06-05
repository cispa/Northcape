#ifndef SKADI_MQTT_H
#define SKADI_MQTT_H

#include <zephyr/net/mqtt.h>
#include <zephyr/skadi/skadi_subsystem.h>

#ifdef CONFIG_MQTT_LIB_TLS_USE_ALPN
#error Not supported in Skadi
#endif

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mqtt_client_init, struct mqtt_client *client);

static inline void skadi_mqtt_client_init(struct mqtt_client *client){
    struct mqtt_client *client_token = skadi_cap_ops_derive_arg(client, sizeof(*client));

    __ASSERT_NO_MSG(client_token);
    if(!client_token){
        return;
    }

    /* structure is memset */
    __skadi_mqtt_client_init(client_token);
    client->client_token = client_token;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mqtt_connect, struct mqtt_client *client);

static inline int skadi_relocate_mqtt_utf8(struct mqtt_utf8 *utf8){
    if(utf8 && utf8->size){
        __ASSERT_NO_MSG(utf8->utf8);
        utf8->utf8 = (const uint8_t *)skadi_cap_ops_derive_arg_ro(utf8->utf8, utf8->size);
        __ASSERT_NO_MSG(utf8->utf8);
        if(!utf8->utf8){
            return -ENOMEM;
        }
    }
    return 0;
}

static inline int skadi_relocate_mqtt_binstr(struct mqtt_binstr *binstr){
    if(binstr && binstr->len){
        __ASSERT_NO_MSG(binstr->data);
        binstr->data = (uint8_t *)skadi_cap_ops_derive_arg_ro(binstr->data, binstr->len);
        __ASSERT_NO_MSG(binstr->data);
        if(!binstr->data){
            return -ENOMEM;
        }
    }
    return 0;
}


static inline int skadi_mqtt_connect(struct mqtt_client *client){
    /* old client token from init - should have been there before coming here */
    __ASSERT_NO_MSG(client->client_token);
    if(!client->client_token){
        return -ENOMEM;
    }

    if(client->skadi_initialized){
        /* do not need to set up everything again*/
        goto do_call;
    }
    

#ifdef CONFIG_MQTT_LIB_TLS

    if(client->transport.type == MQTT_TRANSPORT_SECURE){
        if(client->transport.tls.config.cipher_count){

            client->transport.tls.config.cipher_list = skadi_cap_ops_derive_arg_ro(client->transport.tls.config.cipher_list, client->transport.tls.config.cipher_count * sizeof(int));
            __ASSERT_NO_MSG(client->transport.tls.config.cipher_list);
            if(!client->transport.tls.config.cipher_list){
                return -ENOMEM;
            }
        }

        if(client->transport.tls.config.sec_tag_count){

            client->transport.tls.config.sec_tag_list = skadi_cap_ops_derive_arg_ro(client->transport.tls.config.sec_tag_list, client->transport.tls.config.sec_tag_count * sizeof(sec_tag_t));
            __ASSERT_NO_MSG(client->transport.tls.config.sec_tag_list);
            if(!client->transport.tls.config.sec_tag_list){
                return -ENOMEM;
            }
        }
    }

#endif

#if defined(CONFIG_MQTT_LIB_TLS)
    if(client->transport.tls.config.hostname){
        client->transport.tls.config.hostname = skadi_cap_ops_derive_arg_ro(client->transport.tls.config.hostname, strlen(client->transport.tls.config.hostname)+1);
        __ASSERT_NO_MSG(client->transport.tls.config.hostname);
        if(!client->transport.tls.config.hostname){
            return -ENOMEM;
        }
    }
    if(client->transport.tls.config.cipher_list){
        size_t cipher_list_size;
        const int *iterator = client->transport.tls.config.cipher_list;
        for(cipher_list_size = 0; *iterator != 0; cipher_list_size++){
            iterator++;
        }
        client->transport.tls.config.cipher_list = skadi_cap_ops_derive_arg_ro(client->transport.tls.config.cipher_list, cipher_list_size * sizeof(int));
        __ASSERT_NO_MSG(client->transport.tls.config.cipher_list);
        if(!client->transport.tls.config.cipher_list){
            return -ENOMEM;
        }
    }
#if defined(CONFIG_MQTT_LIB_TLS_USE_ALPN)
#error Not yet supported!
#endif /* CONFIG_MQTT_LIB_TLS_USE_ALPN */
    if(client->transport.tls.config.sec_tag_count){
        client->transport.tls.config.sec_tag_list = skadi_cap_ops_derive_arg_ro(client->transport.tls.config.sec_tag_list, client->transport.tls.config.sec_tag_count * sizeof(sec_tag_t));
        __ASSERT_NO_MSG(client->transport.tls.config.sec_tag_list);
        if(!client->transport.tls.config.sec_tag_list){
            return -ENOMEM;
        }
    }

#endif

    if(skadi_relocate_mqtt_utf8(&client->client_id)){
        return -ENOMEM;
    }

    if(client->user_name){
        client->user_name = (struct mqtt_utf8*) skadi_cap_ops_derive_arg(client->user_name, sizeof(*client->user_name));
        __ASSERT_NO_MSG(client->user_name);
        if(!client->user_name){
            return -ENOMEM;
        }
    }

    if(client->password){
        client->password = (struct mqtt_utf8*) skadi_cap_ops_derive_arg(client->password, sizeof(*client->password));
        __ASSERT_NO_MSG(client->password);
        if(!client->password){
            return -ENOMEM;
        }
    }

    if(skadi_relocate_mqtt_utf8(client->user_name)){
        return -ENOMEM;
    }
    
    if(skadi_relocate_mqtt_utf8(client->password)){
        return -ENOMEM;
    }

    if(client->will_topic){
        client->will_topic = (struct mqtt_topic*) skadi_cap_ops_derive_arg(client->will_topic, sizeof(*client->will_topic));
        if(skadi_relocate_mqtt_utf8(&client->will_topic->topic)){
            return -ENOMEM;
        }
    }

    if(client->will_message){
        client->will_message = (struct mqtt_utf8*) skadi_cap_ops_derive_arg(client->will_message, sizeof(*client->will_message));
        __ASSERT_NO_MSG(client->will_message);
        if(!client->will_message){
            return -ENOMEM;
        }
    }

    if(skadi_relocate_mqtt_utf8(client->will_message)){
        return -ENOMEM;
    }

    client->rx_buf = (uint8_t*) skadi_cap_ops_derive_arg(client->rx_buf, client->rx_buf_size);

    __ASSERT_NO_MSG(client->rx_buf);
    if(!client->rx_buf){
        return -ENOMEM;
    }
    
    client->tx_buf = (uint8_t*) skadi_cap_ops_derive_arg(client->tx_buf, client->tx_buf_size);

    __ASSERT_NO_MSG(client->tx_buf);
    if(!client->tx_buf){
        return -ENOMEM;
    }

    client->skadi_initialized = true;

    do_call:
        return __skadi_mqtt_connect(client->client_token);

}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mqtt_publish, struct mqtt_client *client, const struct mqtt_publish_param *param);

static inline int skadi_mqtt_publish(struct mqtt_client *client, const struct mqtt_publish_param *param){
    struct mqtt_publish_param tmp_param;
    const struct mqtt_publish_param *param_token = NULL;
    int ret;
    __ASSERT_NO_MSG(client);
    __ASSERT_NO_MSG(param);

    tmp_param = *param;
    
    if(skadi_relocate_mqtt_utf8(&tmp_param.message.topic.topic)){
        ret = -ENOMEM;
        goto out;
    }

    if(skadi_relocate_mqtt_binstr(&tmp_param.message.payload)){
        ret= -ENOMEM;
        goto out;
    }

    param_token = (const struct mqtt_publish_param*) skadi_cap_ops_derive_arg_ro(&tmp_param, sizeof(tmp_param));

    __ASSERT_NO_MSG(param_token);
    if(!param_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_mqtt_publish(client->client_token, param_token);
    out:
    if(param_token){
        (void)skadi_cap_ops_drop(param_token);
    }
    if(tmp_param.message.topic.topic.utf8){
        (void)skadi_cap_ops_drop(tmp_param.message.topic.topic.utf8);
    }
    if(tmp_param.message.payload.data){
        (void)skadi_cap_ops_drop(tmp_param.message.payload.data);
    }
    return ret;
    
}


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mqtt_publish_qos1_ack, struct mqtt_client *client, const struct mqtt_puback_param *param);

static inline int skadi_mqtt_publish_qos1_ack(struct mqtt_client *client, const struct mqtt_puback_param *param){
    const struct mqtt_puback_param *param_token = skadi_cap_ops_derive_arg_ro(param, sizeof(*param));
    int ret;
    __ASSERT_NO_MSG(param_token);
    if(!param_token){
        return -ENOMEM;
    }
    ret = __skadi_mqtt_publish_qos1_ack(client->client_token, param_token);

    (void)skadi_cap_ops_drop(param_token);
    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mqtt_publish_qos2_receive, struct mqtt_client *client, const struct mqtt_pubrec_param *param);

static inline int skadi_mqtt_publish_qos2_receive(struct mqtt_client *client, const struct mqtt_pubrec_param *param){
    const struct mqtt_pubrec_param *param_token = skadi_cap_ops_derive_arg_ro(param, sizeof(*param));
    int ret;
    __ASSERT_NO_MSG(param_token);
    if(!param_token){
        return -ENOMEM;
    }
    ret = __skadi_mqtt_publish_qos2_receive(client->client_token, param_token);

    (void)skadi_cap_ops_drop(param_token);
    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mqtt_publish_qos2_release, struct mqtt_client *client, const struct mqtt_pubrel_param *param);

static inline int skadi_mqtt_publish_qos2_release(struct mqtt_client *client, const struct mqtt_pubrel_param *param){
    const struct mqtt_pubrel_param *param_token = skadi_cap_ops_derive_arg_ro(param, sizeof(*param));
    int ret;
    __ASSERT_NO_MSG(param_token);
    if(!param_token){
        return -ENOMEM;
    }
    ret = __skadi_mqtt_publish_qos2_release(client->client_token, param_token);

    (void)skadi_cap_ops_drop(param_token);
    return ret;
}


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mqtt_publish_qos2_complete, struct mqtt_client *client, const struct mqtt_pubcomp_param *param);

static inline int skadi_mqtt_publish_qos2_complete(struct mqtt_client *client, const struct mqtt_pubcomp_param *param){
    const struct mqtt_pubcomp_param *param_token = skadi_cap_ops_derive_arg_ro(param, sizeof(*param));
    int ret;
    __ASSERT_NO_MSG(param_token);
    if(!param_token){
        return -ENOMEM;
    }
    ret = __skadi_mqtt_publish_qos2_complete(client->client_token, param_token);

    (void)skadi_cap_ops_drop(param_token);
    return ret;
}

/* TODO functions not implemented */

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mqtt_ping, struct mqtt_client *client);
#define skadi_mqtt_ping(ARG) __skadi_mqtt_ping((ARG)->client_token)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mqtt_disconnect, struct mqtt_client *client);
#define skadi_mqtt_disconnect(ARG) __skadi_mqtt_disconnect((ARG)->client_token)


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mqtt_abort, struct mqtt_client *client);
#define skadi_mqtt_abort(ARG) __skadi_mqtt_abort((ARG)->client_token)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mqtt_live, struct mqtt_client *client);
#define skadi_mqtt_live(ARG) __skadi_mqtt_live((ARG)->client_token)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mqtt_input, struct mqtt_client *client);
#define skadi_mqtt_input(ARG) __skadi_mqtt_input((ARG)->client_token)

#endif /* SKADI_MQTT_H */
