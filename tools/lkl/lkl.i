%module lkl

%begin %{
/* char* represents the 'bytes' type, not an unicode string */
#define SWIG_PYTHON_STRICT_BYTE_CHAR
%}

%{
/* Includes the header in the wrapper code */
#include "lkl.h"
#include "lkl_host.h"
#include <limits.h>
%}

%import "cstring.i";

/* We will later refine these function types below. */
%ignore lkl_mount_dev;
%ignore lkl_sys_read;
%ignore lkl_sys_write;
%ignore lkl_opendir;
%ignore lkl_readdir;

/* And these structures. */
%ignore lkl_linux_dirent64;
%ignore lkl_linux_dirent;

%nodefaultctor lkl_dir;
%nodefaultdtor lkl_dir;

/* Make the SWIG parser not choke on some files */
#define __attribute__(...)

/* Parse the header file to generate wrappers */
#define CONFIG_AUTO_LKL_POSIX_HOST 1
%include <lkl.h>
%include <lkl_host.h>
%include <lkl/asm/host_ops.h>
/* lkl_umode_t etc. */
%include <lkl/asm/syscalls.h>
/* LKL_MS_RDONLY etc. */
%include <lkl/linux/fs.h>
/* LKL_O_RDWR etc. */
%include <lkl/asm-generic/fcntl.h>
/* LKL_EEXIST etc. */
%include <lkl/asm-generic/errno-base.h>
%include "hack.h"

/* Now apply the overrides. */


%rename do_lkl_mount_dev lkl_mount_dev;
%cstring_bounded_output(char *mnt_str, PATH_MAX)
%inline %{
void do_lkl_mount_dev(unsigned int disk_id, unsigned int part, const char *fs_type,
                      int flags, const char *opts,
                      char *mnt_str, int* OUTPUT)
{
    *OUTPUT = lkl_mount_dev(disk_id, part, fs_type, flags, opts, mnt_str, PATH_MAX);
}
%}
%clear char *mnt_str;

%rename do_lkl_sys_read lkl_sys_read;
%cstring_output_withsize(char *buf, lkl_size_t *count)
%inline %{
void do_lkl_sys_read(unsigned int fd, char *buf, lkl_size_t *count, int *OUTPUT)
{
    long ret = lkl_sys_read(fd, buf, *count);
    if (ret < 0)
        *count = 0;
    else
        *count = ret;
    *OUTPUT = ret;
}
%}
%clear char *buf, lkl_size_t *count;

%rename do_lkl_sys_write lkl_sys_write;
%apply (char *STRING, size_t LENGTH) { (const char *buf, lkl_size_t count) };
%inline %{
void do_lkl_sys_write(unsigned int fd, const char *buf, lkl_size_t count, int* OUTPUT)
{
    *OUTPUT = lkl_sys_write(fd, buf, count);
}
%}
%clear const char *buf, lkl_size_t count;

%rename do_lkl_sys_stat lkl_sys_stat;
%inline %{
struct lkl_stat *do_lkl_sys_stat(const char *filename, int* OUTPUT)
{
    struct lkl_stat *statbuf = malloc(sizeof(*statbuf));
    if (!statbuf) {
        *OUTPUT = -ENOMEM;
        return NULL;
    }
    *OUTPUT = lkl_sys_stat(filename, statbuf);
    if (*OUTPUT) {
        free(statbuf);
        return NULL;
    }
    return statbuf;
}
%}

%rename do_lkl_opendir lkl_opendir;
%inline %{
struct lkl_dir *do_lkl_opendir(const char *path, int *OUTPUT)
{
    return lkl_opendir(path, OUTPUT);
}
%}

/*
 * struct lkl_linux_dirent64 has: char d_name[0]; so of course swig thinks
 * that's always a zero-length string... So do more wrapping.
 */
%rename wrapped_lkl_dirent lkl_dirent;
%inline %{
struct wrapped_lkl_dirent {
	lkl_u64		d_ino;
	lkl_s64		d_off;
	unsigned short	d_reclen;
	unsigned char	d_type;
	char		*d_name;
};
%}

%rename do_lkl_readdir lkl_readdir;
%inline %{
struct wrapped_lkl_dirent *do_lkl_readdir(struct lkl_dir *dir, int *OUTPUT)
{
    struct lkl_linux_dirent64 *de;
    struct wrapped_lkl_dirent *wrapped_de = malloc(sizeof(*wrapped_de));

    if (!wrapped_de) {
        *OUTPUT = -ENOMEM;
        return NULL;
    }

    de = lkl_readdir(dir);

    if (!de) {
        *OUTPUT = lkl_errdir(dir);
        free(wrapped_de);
        return NULL;
    }

    *OUTPUT = 0;
    wrapped_de->d_ino = de->d_ino;
    wrapped_de->d_off = de->d_off;
    wrapped_de->d_reclen = de->d_reclen;
    wrapped_de->d_type = de->d_type;
    wrapped_de->d_name = strdup(de->d_name);

    return wrapped_de;
}
%}
