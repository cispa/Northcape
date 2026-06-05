#ifndef SKADI_PIPE_H
#define SKADI_PIPE_H

#include <zephyr/kernel.h>
#include <zephyr/skadi/skadi_subsystem.h>

#ifdef SKADI_SUBSYSTEM
/* in the loader, use the z_impl_* variants directly */

#define SKADI_PIPE_ASSERT(PIPE, FILE, LINE) \
	__ASSERT(PIPE, "Pipe is null at %s:%d", FILE, LINE)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_pipe_init, struct k_pipe *pipe, unsigned char *buffer, size_t size);

static inline void _skadi_pipe_init(struct k_pipe *pipe, unsigned char *buffer, size_t size, const char *file, const int line){
	unsigned char *buffer_token = skadi_cap_ops_derive_arg(buffer, size);

	SKADI_PIPE_ASSERT(pipe, file, line);

	__ASSERT_NO_MSG(buffer_token);

	__skadi_pipe_init(pipe, buffer_token, size);
	
	/* cleanup using drop */
	pipe->pipe_token_dynamic = false;
}

#define skadi_pipe_init(PIPE, BUFFER, SIZE) _skadi_pipe_init(PIPE, BUFFER, SIZE, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_pipe_cleanup, struct k_pipe *pipe);


static inline void _skadi_pipe_cleanup(struct k_pipe *pipe, const char *file, const int line){

	SKADI_PIPE_ASSERT(pipe, file, line);

	__skadi_pipe_cleanup(pipe);
	
	if(pipe->pipe_token_dynamic == false){
		skadi_cap_ops_drop(pipe->buffer);
	}

	skadi_cap_ops_drop(pipe);
}

#define skadi_pipe_cleanup(PIPE) _skadi_pipe_cleanup(PIPE, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_pipe_alloc_init, struct k_pipe *pipe, size_t size);

static inline int _skadi_pipe_alloc_init(struct k_pipe *pipe, size_t size, const char *file, const int line){
	int ret;


	SKADI_PIPE_ASSERT(pipe, file, line);
	
	ret = __skadi_pipe_alloc_init(pipe, size);
	
	pipe->pipe_token_dynamic = true;

	return ret;
}

#define skadi_pipe_alloc_init(PIPE, SIZE) _skadi_pipe_alloc_init(PIPE, SIZE, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_pipe_put, struct k_pipe *pipe, const void *data, size_t bytes_to_write, size_t *bytes_written, size_t min_xfer, k_timeout_t timeout);

static inline int _skadi_pipe_put(struct k_pipe *pipe, const void *data, size_t bytes_to_write, size_t *bytes_written, size_t min_xfer, k_timeout_t timeout, const char *file, const int line){
	const void *data_token = skadi_cap_ops_derive_arg_ro(data, bytes_to_write);
	size_t *bytes_written_token =  bytes_written ? skadi_cap_ops_derive_arg(bytes_written, sizeof(*bytes_written)) : NULL;
	
	int ret;

	SKADI_PIPE_ASSERT(pipe, file, line);

	__ASSERT_NO_MSG(bytes_written_token);
	__ASSERT_NO_MSG(data_token);
	
	ret = __skadi_pipe_put(pipe, data_token, bytes_to_write, bytes_written_token, min_xfer, timeout);
	
	if(bytes_written_token){
		skadi_cap_ops_drop(bytes_written_token);
	}

	if(data_token){
		skadi_cap_ops_drop(data_token);
	}

	return ret;
}

#define skadi_pipe_put(PIPE, DATA, BYTES_TO_WRITE, BYTES_WRITTEN, MIN_XFER, TIMEOUT) _skadi_pipe_put(PIPE, DATA, BYTES_TO_WRITE, BYTES_WRITTEN, MIN_XFER, TIMEOUT, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_pipe_get, struct k_pipe *pipe, void *data, size_t bytes_to_read, size_t *bytes_read, size_t min_xfer, k_timeout_t timeout);

static inline int _skadi_pipe_get(struct k_pipe *pipe, void *data, size_t bytes_to_read, size_t *bytes_read, size_t min_xfer, k_timeout_t timeout, const char *file, const int line){
	void *data_token = skadi_cap_ops_derive_arg(data, bytes_to_read);
	size_t *bytes_read_token =  bytes_read ? skadi_cap_ops_derive_arg(bytes_read, sizeof(*bytes_read)) : NULL;
	
	int ret;

	SKADI_PIPE_ASSERT(pipe, file, line);

	__ASSERT_NO_MSG(bytes_read_token);
	__ASSERT_NO_MSG(data_token);
	
	ret = __skadi_pipe_get(pipe, data_token, bytes_to_read, bytes_read_token, min_xfer, timeout);
	
	if(bytes_read_token){
		skadi_cap_ops_drop(bytes_read_token);
	}

	if(data_token){
		skadi_cap_ops_drop(data_token);
	}

	return ret;
}

#define skadi_pipe_get(PIPE, DATA, BYTES_TO_WRITE, BYTES_WRITTEN, MIN_XFER, TIMEOUT) _skadi_pipe_get(PIPE, DATA, BYTES_TO_WRITE, BYTES_WRITTEN, MIN_XFER, TIMEOUT, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(size_t, __skadi_pipe_read_avail, struct k_pipe *pipe);

static inline size_t _skadi_pipe_read_avail(struct k_pipe *pipe, const char *file, const int line){

	SKADI_PIPE_ASSERT(pipe, file, line);

	return __skadi_pipe_read_avail(pipe);
}

#define skadi_pipe_read_avail(PIPE) _skadi_pipe_read_avail(PIPE, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(size_t, __skadi_pipe_write_avail, struct k_pipe *pipe);

static inline size_t _skadi_pipe_write_avail(struct k_pipe *pipe, const char *file, const int line){

	SKADI_PIPE_ASSERT(pipe, file, line);

	return __skadi_pipe_write_avail(pipe);
}

#define skadi_pipe_write_avail(PIPE) _skadi_pipe_write_avail(PIPE, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_pipe_flush, struct k_pipe *pipe);

static inline void _skadi_pipe_flush(struct k_pipe *pipe, const char *file, const int line){

	SKADI_PIPE_ASSERT(pipe, file, line);

	__skadi_pipe_flush(pipe);
}

#define skadi_pipe_flush(PIPE) _skadi_pipe_flush(PIPE, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_pipe_buffer_flush, struct k_pipe *pipe);

static inline void _skadi_pipe_buffer_flush(struct k_pipe *pipe, const char *file, const int line){

	SKADI_PIPE_ASSERT(pipe, file, line);

	__skadi_pipe_buffer_flush(pipe);
}

#define skadi_pipe_buffer_flush(PIPE) _skadi_pipe_buffer_flush(PIPE, __FILE__, __LINE__)

#endif /* SKADI_SUBSYSTEM */

#endif /* SKADI_PIPE_H */
