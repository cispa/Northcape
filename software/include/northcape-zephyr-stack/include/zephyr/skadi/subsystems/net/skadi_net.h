#ifndef SKADI_NET_H
#define SKADI_NET_H
    #include <zephyr/device.h>
    #include <zephyr/drivers/mdio.h>
    #include <zephyr/net/net_pkt.h>
    #include <zephyr/skadi/skadi_subsystem.h>

#define skadi_net_pkt_is_being_overwritten net_pkt_is_being_overwritten

#define skadi_net_buf_simple_tail net_buf_simple_tail

static inline uint16_t skadi_net_buf_max_len(const struct net_buf *buf){
    const struct net_buf_simple *buf_simple = &buf->b;

    return buf_simple->size - (buf_simple->data - buf_simple->__buf);
}

static inline void *skadi_net_buf_add(struct net_buf *buf, size_t len){
    const struct net_buf_simple *buf_simple = &buf->b;

    uint8_t *tail = skadi_net_buf_simple_tail(buf_simple);

    buf->len += len;

    return tail;
}

static inline void skadi_pkt_cursor_jump_inline(struct net_pkt *pkt, bool write)
{
	struct net_pkt_cursor *cursor = &pkt->cursor;

	cursor->buf = cursor->buf->frags;
	while (cursor->buf) {
		const size_t len =
			write ? skadi_net_buf_max_len(cursor->buf) : cursor->buf->len;

		if (!len) {
			cursor->buf = cursor->buf->frags;
		} else {
			break;
		}
	}

	if (cursor->buf) {
		cursor->pos = cursor->buf->data;
	} else {
		cursor->pos = NULL;
	}
}

static inline void skadi_pkt_cursor_advance_inline(struct net_pkt *pkt, bool write)
{
	struct net_pkt_cursor *cursor = &pkt->cursor;
	size_t len;

	if (!cursor->buf) {
		return;
	}

	len = write ? skadi_net_buf_max_len(cursor->buf) : cursor->buf->len;
	if ((cursor->pos - cursor->buf->data) == len) {
		skadi_pkt_cursor_jump_inline(pkt, write);
	}
}

static inline void skadi_pkt_cursor_update_inline(struct net_pkt *pkt,
			      size_t length, bool write)
{
	struct net_pkt_cursor *cursor = &pkt->cursor;
	size_t len;

	if (skadi_net_pkt_is_being_overwritten(pkt)) {
		write = false;
	}

	len = write ? skadi_net_buf_max_len(cursor->buf) : cursor->buf->len;
	if (length + (cursor->pos - cursor->buf->data) == len &&
	    !(net_pkt_is_being_overwritten(pkt) &&
	      len < skadi_net_buf_max_len(cursor->buf))) {
		skadi_pkt_cursor_jump_inline(pkt, write);
	} else {
		cursor->pos += length;
	}
}

static inline int skadi_net_pkt_cursor_operate_inline(struct net_pkt *pkt,
				  void *data, size_t length,
				  bool copy, bool write)
{
	/* We use such variable to avoid lengthy lines */
	struct net_pkt_cursor *c_op = &pkt->cursor;

	while (c_op->buf && length) {
		size_t d_len, len;

		skadi_pkt_cursor_advance_inline(pkt, skadi_net_pkt_is_being_overwritten(pkt) ?
				   false : write);
		if (c_op->buf == NULL) {
			break;
		}

		if (write && !skadi_net_pkt_is_being_overwritten(pkt)) {
			d_len = skadi_net_buf_max_len(c_op->buf) -
				(c_op->pos - c_op->buf->data);
		} else {
			d_len = c_op->buf->len - (c_op->pos - c_op->buf->data);
		}

		if (!d_len) {
			break;
		}

		if (length < d_len) {
			len = length;
		} else {
			len = d_len;
		}

		if (copy && data) {
			memcpy(write ? c_op->pos : data,
			       write ? data : c_op->pos,
			       len);
		} else if (data) {
			memset(c_op->pos, *(int *)data, len);
		}

		if (write && !skadi_net_pkt_is_being_overwritten(pkt)) {
			skadi_net_buf_add(c_op->buf, len);
		}

		skadi_pkt_cursor_update_inline(pkt, len, write);

		if (copy && data) {
			data = (uint8_t *) data + len;
		}

		length -= len;
	}

	if (length) {
		return -ENOBUFS;
	}

	return 0;
}

static inline int skadi_net_pkt_skip_inline(struct net_pkt *pkt, size_t skip)
{
	return skadi_net_pkt_cursor_operate_inline(pkt, NULL, skip, false, true);
}

static inline size_t skadi_net_pkt_get_contiguous_len_inline(struct net_pkt *pkt)
{
	skadi_pkt_cursor_advance_inline(pkt, !skadi_net_pkt_is_being_overwritten(pkt));

	if (pkt->cursor.buf && pkt->cursor.pos) {
		size_t len;

		len = skadi_net_pkt_is_being_overwritten(pkt) ?
			pkt->cursor.buf->len : skadi_net_buf_max_len(pkt->cursor.buf);
		len -= pkt->cursor.pos - pkt->cursor.buf->data;

		return len;
	}

	return 0;
}


static inline bool skadi_net_pkt_is_contiguous_inline(struct net_pkt *pkt, size_t size)
{
	size_t len = skadi_net_pkt_get_contiguous_len_inline(pkt);

	return len >= size;
}



#if defined(CONFIG_NET_DEBUG_NET_PKT_ALLOC)
#define NET_LOG_LEVEL 5
#else
#define NET_LOG_LEVEL CONFIG_NET_PKT_LOG_LEVEL
#endif

    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, skadi_net_recv_data, struct net_if *iface, struct net_pkt *pkt);
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, skadi_net_if_set_link_addr_locked, struct net_if *iface, uint8_t *addr, uint8_t len, enum net_link_type type);

    static inline int skadi_net_if_set_link_addr(struct net_if *iface,
				       uint8_t *addr, uint8_t len,
				       enum net_link_type type)
    {
        return skadi_net_if_set_link_addr_locked(iface, addr, len, type);
    }


#if NET_LOG_LEVEL >= LOG_LEVEL_DBG
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(skadi_net_pkt_unref_debug, struct net_pkt *pkt, const char *caller, int line);
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(struct net_pkt *, skadi_net_pkt_rx_alloc_with_buffer_debug, struct net_if *iface, size_t size, sa_family_t family, enum net_ip_protocol proto, k_timeout_t timeout, const char *caller, int line);
    
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(struct net_pkt *, skadi_net_pkt_rx_alloc_debug, k_timeout_t timeout, const char *caller, int line);

    #define skadi_net_pkt_unref(pkt) skadi_net_pkt_unref_debug(pkt, __func__, __LINE__)

    #define skadi_net_pkt_rx_alloc_with_buffer(_iface, _size, _family,		    \
				     _proto, _timeout)			                                    \
	        skadi_net_pkt_rx_alloc_with_buffer_debug(_iface, _size, _family,	\
					   _proto, _timeout,		                                    \
					   __func__, __LINE__)
    
    #define skadi_net_pkt_rx_alloc(_timeout)			                                    \
               skadi_net_pkt_rx_alloc_debug(_timeout,		                                \
                          __func__, __LINE__)
#else
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(skadi_net_pkt_unref, struct net_pkt *pkt);
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(struct net_pkt *, skadi_net_pkt_rx_alloc_with_buffer, struct net_if *iface, size_t size, sa_family_t family, enum net_ip_protocol proto, k_timeout_t timeout);
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(struct net_pkt *, skadi_net_pkt_rx_alloc, k_timeout_t timeout);
#endif

#if NET_LOG_LEVEL >= LOG_LEVEL_DBG
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(struct net_pkt *, skadi_net_pkt_ref_debug, struct net_pkt *pkt, const char *caller, int line);

    #define skadi_net_pkt_ref(pkt) skadi_net_pkt_ref_debug(pkt, __func__, __LINE__)
#else
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(struct net_pkt *, skadi_net_pkt_ref, struct net_pkt *pkt);
#endif

    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_net_pkt_read, struct net_pkt *pkt, void *data, size_t length);
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_net_pkt_write, struct net_pkt *pkt, const void *data, size_t length);

    static inline int skadi_net_pkt_read(struct net_pkt *pkt, void *data, size_t length){
        void *buffer = skadi_cap_ops_derive_arg_wo(data, length);
        int ret;

        __ASSERT_NO_MSG(buffer);

        if(!buffer){
            return -ENOMEM;
        }

        ret = __skadi_net_pkt_read(pkt, buffer, length);

        skadi_cap_ops_drop(buffer);

        return ret;
    }

    static inline int skadi_net_pkt_read_inline(struct net_pkt *pkt, void *data, size_t length){
        return skadi_net_pkt_cursor_operate_inline(pkt, data, length, true, false);
    }

    static inline int skadi_net_pkt_write(struct net_pkt *pkt, const void *data, size_t length){
        const void *buffer = skadi_cap_ops_derive_arg_ro(data, length);
        int ret;

        __ASSERT_NO_MSG(buffer);

        if(!buffer){
            return -ENOMEM;
        }

        ret = __skadi_net_pkt_write(pkt, buffer, length);

        skadi_cap_ops_drop(buffer);

        return ret;
    }
    /* always-inline version of skadi_net_pkt_write, saves one subsystem call at the cost of larger code size */
    static inline int skadi_net_pkt_write_inline(struct net_pkt *pkt, const void *data, size_t length){
        if (data == pkt->cursor.pos && skadi_net_pkt_is_contiguous_inline(pkt, length)) {
		    return skadi_net_pkt_skip_inline(pkt, length);
	    }

	    return skadi_net_pkt_cursor_operate_inline(pkt, (void *)data, length, true, true);
    }

#undef NET_LOG_LEVEL

#if defined(CONFIG_NET_NATIVE_IPV6)
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(struct net_if_addr *, __skadi_net_if_ipv6_addr_add, struct net_if *iface, struct in6_addr *addr, enum net_addr_type addr_type, uint32_t vlifetime);

    static inline struct net_if_addr *_skadi_net_if_ipv6_addr_add(struct net_if *iface, struct in6_addr *addr, enum net_addr_type addr_type, uint32_t vlifetime){
        struct in6_addr *addr_token = skadi_cap_ops_derive_arg(addr, sizeof(*addr));
        struct net_if_addr *ret;

        __ASSERT_NO_MSG(addr_token);

        if(!addr_token){
            return NULL;
        }

        // iface is used as an opaque handle
        ret = __skadi_net_if_ipv6_addr_add(iface, addr_token, addr_type, vlifetime);

        skadi_cap_ops_drop(addr_token);

        return ret;
    }

    #define skadi_net_if_ipv6_addr_add(IFACE, ADDR, ADDR_TYPE, VLIFETIME) _skadi_net_if_ipv6_addr_add(IFACE, ADDR, ADDR_TYPE, VLIFETIME)

    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(struct net_if_ipv6_prefix *, __skadi_net_if_ipv6_prefix_add, struct net_if *iface, struct in6_addr *prefix, uint8_t len, uint32_t lifetime);

    static inline struct net_if_ipv6_prefix* _skadi_net_if_ipv6_prefix_add(struct net_if *iface, struct in6_addr *prefix, uint8_t len, uint32_t lifetime){
        struct in6_addr *prefix_token = skadi_cap_ops_derive_arg(prefix, sizeof(*prefix));
        struct net_if_ipv6_prefix *ret;

        __ASSERT_NO_MSG(prefix_token);

        if(!prefix_token){
            return NULL;
        }

        // iface is used as an opaque handle
        ret = __skadi_net_if_ipv6_prefix_add(iface, prefix_token, len, lifetime);

        skadi_cap_ops_drop(prefix_token);

        return ret;
    }

    #define skadi_net_if_ipv6_prefix_add(IFACE, PREFIX, LEN, LIFETIME) _skadi_net_if_ipv6_prefix_add(IFACE, PREFIX, LEN, LIFETIME)

#endif

    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(struct net_if_addr *, __skadi_net_if_ipv4_addr_add, struct net_if *iface, struct in_addr *addr, enum net_addr_type addr_type, uint32_t vlifetime);

    static inline struct net_if_addr *_skadi_net_if_ipv4_addr_add(struct net_if *iface, struct in_addr *addr, enum net_addr_type addr_type, uint32_t vlifetime){
        struct in_addr *addr_token = skadi_cap_ops_derive_arg(addr, sizeof(*addr));
        struct net_if_addr *ret;

        __ASSERT_NO_MSG(addr_token);

        if(!addr_token){
            return NULL;
        }

        // iface is used as an opaque handle
        ret = __skadi_net_if_ipv4_addr_add(iface, addr_token, addr_type, vlifetime);

        skadi_cap_ops_drop(addr_token);

        return ret;
    }

    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_net_if_add_tx_timestamp, struct net_pkt *pkt);

    #define skadi_net_if_add_tx_timestamp(PKT) __skadi_net_if_add_tx_timestamp(PKT)

    #define skadi_net_if_ipv4_addr_add(IFACE, ADDR, ADDR_TYPE, VLIFETIME) _skadi_net_if_ipv4_addr_add(IFACE, ADDR, ADDR_TYPE, VLIFETIME)

    static inline uint8_t *skadi_net_pkt_raw_buf(struct net_pkt *pkt){
        __ASSERT_NO_MSG(pkt);
        __ASSERT_NO_MSG(pkt->cursor.buf);
        __ASSERT_NO_MSG(pkt->cursor.buf->__buf);
        return pkt->cursor.buf->__buf;
    }

    static inline void skadi_net_pkt_raw_buf_set(struct net_pkt *pkt, uint8_t *new_buf){
        __ASSERT_NO_MSG(pkt);
        __ASSERT_NO_MSG(pkt->cursor.buf);
        __ASSERT_NO_MSG(pkt->cursor.buf->__buf);
        pkt->cursor.buf->__buf = new_buf;
    }

    static inline uint16_t skadi_net_pkt_raw_buf_len(const struct net_pkt *pkt){
        __ASSERT_NO_MSG(pkt);
        __ASSERT_NO_MSG(pkt->cursor.buf);
        return pkt->cursor.buf->len;
    }

    static inline bool skadi_net_pkt_cursor_advance(struct net_pkt_cursor *cursor){
        if(!cursor->buf->frags){
            /* packet complete */
            return false;
        }
        cursor->buf = cursor->buf->frags;
        return true;
    }

#endif
