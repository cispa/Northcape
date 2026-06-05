#ifndef SKADI_FS_H
#define SKADI_FS_H

#include <zephyr/fs/fs.h>
#include <zephyr/skadi/skadi_subsystem.h>

#define SKADI_FS_PTR_TOKEN(PTR) skadi_cap_ops_derive_arg(PTR, sizeof(*PTR))
#define SKADI_FS_PTR_TOKEN_RO(PTR) skadi_cap_ops_derive_arg_ro(PTR, sizeof(*PTR))
#define SKADI_FS_PTR_TOKEN_SIZED(PTR, SIZE) skadi_cap_ops_derive_arg(PTR, SIZE)
#define SKADI_FS_PTR_TOKEN_RO_SIZED(PTR, SIZE) skadi_cap_ops_derive_arg_ro(PTR, SIZE)
#define SKADI_FS_STR_TOKEN(STR) skadi_cap_ops_derive_arg_ro(STR, strlen(STR) + 1)

#define DECLARE_SKADI_FS_PTR_TOKEN(PTR) __typeof__(PTR) PTR##_token = SKADI_FS_PTR_TOKEN(PTR)
#define DECLARE_SKADI_FS_PTR_TOKEN_RO(PTR) __typeof__(PTR) PTR##_token = SKADI_FS_PTR_TOKEN_RO(PTR)
#define DECLARE_SKADI_FS_PTR_TOKEN_SIZED(PTR, SIZE) __typeof__(PTR) PTR##_token = SKADI_FS_PTR_TOKEN_SIZED(PTR, SIZE)
#define DECLARE_SKADI_FS_PTR_TOKEN_RO_SIZED(PTR, SIZE) __typeof__(PTR) PTR##_token = SKADI_FS_PTR_TOKEN_RO_SIZED(PTR, SIZE)
#define DECLARE_SKADI_FS_STR_TOKEN(STR) __typeof__(STR) STR##_token = SKADI_FS_STR_TOKEN(STR)

#define SKADI_FS_CLEANUP_TOKEN(TOKEN) skadi_cap_ops_drop((TOKEN)) 


#ifdef SKADI_SUBSYSTEM

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_fs_open, struct fs_file_t *zfp, const char *file_name, fs_mode_t flags);

static inline int _skadi_fs_open(struct fs_file_t *zfp, const char *file_name, fs_mode_t flags){
    DECLARE_SKADI_FS_PTR_TOKEN(zfp);
    DECLARE_SKADI_FS_STR_TOKEN(file_name);
    int ret;

    ret = __skadi_fs_open(zfp_token, file_name_token, flags);

    SKADI_FS_CLEANUP_TOKEN(zfp_token);
    SKADI_FS_CLEANUP_TOKEN(file_name_token);

    return ret;
}

#define skadi_fs_open(ZFP, FILE_NAME, FLAGS) _skadi_fs_open(ZFP, FILE_NAME, FLAGS);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_fs_close, struct fs_file_t *zfp);

static inline int _skadi_fs_close(struct fs_file_t *zfp){
    DECLARE_SKADI_FS_PTR_TOKEN(zfp);
    int ret;

    ret = __skadi_fs_close(zfp_token);

    SKADI_FS_CLEANUP_TOKEN(zfp_token);

    return ret;
}

#define skadi_fs_close(ZFP) _skadi_fs_close(ZFP)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(ssize_t, __skadi_fs_read, struct fs_file_t *zfp, void *ptr, size_t size);

static inline ssize_t _skadi_fs_read(struct fs_file_t *zfp, void *ptr, size_t size){
    DECLARE_SKADI_FS_PTR_TOKEN(zfp);
    DECLARE_SKADI_FS_PTR_TOKEN_SIZED(ptr, size);
    int ret;

    ret = __skadi_fs_read(zfp_token, ptr_token, size);

    SKADI_FS_CLEANUP_TOKEN(zfp_token);
    SKADI_FS_CLEANUP_TOKEN(ptr);

    return ret;
}

#define skadi_fs_read(ZFP, PTR, SIZE) _skadi_fs_read(ZFP, PTR, SIZE)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(ssize_t, __skadi_fs_write, struct fs_file_t *zfp, const void *ptr, size_t size);

static inline ssize_t _skadi_fs_write(struct fs_file_t *zfp, const void *ptr, size_t size){
    DECLARE_SKADI_FS_PTR_TOKEN(zfp);
    DECLARE_SKADI_FS_PTR_TOKEN_RO_SIZED(ptr, size);
    int ret;

    ret = __skadi_fs_write(zfp_token, ptr_token, size);

    SKADI_FS_CLEANUP_TOKEN(zfp_token);
    SKADI_FS_CLEANUP_TOKEN(ptr);

    return ret;
}

#define skadi_fs_write(ZFP, PTR, SIZE) _skadi_fs_write(ZFP, PTR, SIZE)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_fs_seek, struct fs_file_t *zfp, off_t offset, int whence);

static inline int _skadi_fs_seek(struct fs_file_t *zfp, off_t offset, int whence){
    DECLARE_SKADI_FS_PTR_TOKEN(zfp);
    int ret;

    ret = __skadi_fs_seek(zfp_token, offset, whence);

    SKADI_FS_CLEANUP_TOKEN(zfp_token);

    return ret;
}

#define skadi_fs_seek(ZFP, OFFSET, WHENCE) _skadi_fs_seek(ZFP, OFFSET, WHENCE)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(off_t, __skadi_fs_tell, struct fs_file_t *zfp);

static inline off_t _skadi_fs_tell(struct fs_file_t *zfp){
    DECLARE_SKADI_FS_PTR_TOKEN(zfp);
    off_t ret;

    ret = __skadi_fs_tell(zfp_token);

    SKADI_FS_CLEANUP_TOKEN(zfp_token);

    return ret;
}

#define skadi_fs_tell(ZFP) _skadi_fs_tell(ZFP)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_fs_truncate, struct fs_file_t *zfp, off_t length);

static inline int _skadi_fs_truncate(struct fs_file_t *zfp, off_t length){
    DECLARE_SKADI_FS_PTR_TOKEN(zfp);
    int ret;

    ret = __skadi_fs_truncate(zfp_token, length);

    SKADI_FS_CLEANUP_TOKEN(zfp_token);

    return ret;
}

#define skadi_fs_truncate(ZFP, LENGTH) _skadi_fs_truncate(ZFP, LENGTH)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_fs_sync, struct fs_file_t *zfp);

static inline int _skadi_fs_sync(struct fs_file_t *zfp){
    DECLARE_SKADI_FS_PTR_TOKEN(zfp);
    int ret;

    ret = __skadi_fs_sync(zfp_token);

    SKADI_FS_CLEANUP_TOKEN(zfp_token);

    return ret;
}

#define skadi_fs_sync(ZFP) _skadi_fs_sync(ZFP)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_fs_opendir, struct fs_dir_t *zdp, const char *abs_path);

static inline int _skadi_fs_opendir(struct fs_dir_t *zdp, const char *abs_path){
    DECLARE_SKADI_FS_PTR_TOKEN(zdp);
    DECLARE_SKADI_FS_STR_TOKEN(abs_path);
    int ret;

    ret = __skadi_fs_opendir(zdp_token, abs_path_token);

    SKADI_FS_CLEANUP_TOKEN(zdp_token);
    SKADI_FS_CLEANUP_TOKEN(abs_path_token);

    return ret;
}

#define skadi_fs_opendir(ZDP, ABS_PATH) _skadi_fs_opendir(ZDP, ABS_PATH);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_fs_readdir, struct fs_dir_t *zdp, struct fs_dirent *entry);

static inline int _skadi_fs_readdir(struct fs_dir_t *zdp, struct fs_dirent *entry){
    DECLARE_SKADI_FS_PTR_TOKEN(zdp);
    DECLARE_SKADI_FS_PTR_TOKEN(entry);
    int ret;

    ret = __skadi_fs_readdir(zdp_token, entry_token);

    SKADI_FS_CLEANUP_TOKEN(zdp_token);
    SKADI_FS_CLEANUP_TOKEN(entry_token);

    return ret;
}

#define skadi_fs_readdir(ZDP, ENTRY) _skadi_fs_readdir(ZDP, ENTRY);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_fs_closedir, struct fs_dir_t *zdp);

static inline int _skadi_fs_closedir(struct fs_dir_t *zdp){
    DECLARE_SKADI_FS_PTR_TOKEN(zdp);
    int ret;

    ret = __skadi_fs_closedir(zdp_token);

    SKADI_FS_CLEANUP_TOKEN(zdp_token);

    return ret;
}

#define skadi_fs_closedir(ZDP) _skadi_fs_closedir(ZDP);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_fs_mkdir, const char *abs_path);

static inline int _skadi_fs_mkdir(const char *abs_path){
    DECLARE_SKADI_FS_STR_TOKEN(abs_path);
    int ret;

    ret = __skadi_fs_mkdir(abs_path_token);

    SKADI_FS_CLEANUP_TOKEN(abs_path_token);

    return ret;
}

#define skadi_fs_mkdir(ZDP) _skadi_fs_mkdir(ZDP);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_fs_unlink, const char *abs_path);

static inline int _skadi_fs_unlink(const char *abs_path){
    DECLARE_SKADI_FS_STR_TOKEN(abs_path);
    int ret;

    ret = __skadi_fs_unlink(abs_path_token);

    SKADI_FS_CLEANUP_TOKEN(abs_path_token);

    return ret;
}

#define skadi_fs_unlink(ZDP) _skadi_fs_unlink(ZDP);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_fs_rename, const char *from, const char *to);


static inline int _skadi_fs_rename(const char *from, const char *to){
    DECLARE_SKADI_FS_STR_TOKEN(from);
    DECLARE_SKADI_FS_STR_TOKEN(to);
    int ret;

    ret = __skadi_fs_rename(from, to);

    SKADI_FS_CLEANUP_TOKEN(from_token);
    SKADI_FS_CLEANUP_TOKEN(to_token);

    return ret;
}

#define skadi_fs_rename(FROM, TO) _skadi_fs_rename(FROM, TO);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_fs_stat, const char *abs_path, struct fs_dirent *entry);

static inline int _skadi_fs_stat(const char *abs_path, struct fs_dirent *entry){
    DECLARE_SKADI_FS_STR_TOKEN(abs_path);
    DECLARE_SKADI_FS_PTR_TOKEN(entry);
    int ret;

    ret = __skadi_fs_stat(abs_path_token, entry_token);

    SKADI_FS_CLEANUP_TOKEN(abs_path_token);
    SKADI_FS_CLEANUP_TOKEN(entry_token);

    return ret;
}

#define skadi_fs_stat(ABS_PATH, ENTRY) _skadi_fs_stat(ABS_PATH, ENTRY)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_fs_statvfs, const char *abs_path, struct fs_statvfs *stat);

static inline int _skadi_fs_statvfs(const char *abs_path, struct fs_statvfs *stat){
    DECLARE_SKADI_FS_STR_TOKEN(abs_path);
    DECLARE_SKADI_FS_PTR_TOKEN(stat);
    int ret;

    ret = __skadi_fs_statvfs(abs_path_token, stat);

    SKADI_FS_CLEANUP_TOKEN(abs_path_token);
    SKADI_FS_CLEANUP_TOKEN(stat_token);

    return ret;
}

#define skadi_fs_statvfs(ABS_PATH, STAT) _skadi_fs_statvfs(ABS_PATH, STAT)



#endif /* SKADI_SUBSYSTEM */

#endif /* SKADI_FS_H */
