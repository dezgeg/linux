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
long do_lkl_mount_dev(unsigned int disk_id, unsigned int part, const char *fs_type,
                      int flags, const char *opts,
                      char *mnt_str)
{
    return lkl_mount_dev(disk_id, part, fs_type, flags, opts, mnt_str, PATH_MAX);
}
%}
%clear char *mnt_str;

%rename do_lkl_sys_read lkl_sys_read;
%cstring_output_withsize(char *buf, lkl_size_t *count)
%inline %{
long do_lkl_sys_read(unsigned int fd, char *buf, lkl_size_t *count)
{
    long ret = lkl_sys_read(fd, buf, *count);
    if (ret < 0)
        *count = 0;
    else
        *count = ret;
    return ret;
}
%}
%clear char *buf, lkl_size_t *count;

%rename do_lkl_sys_write lkl_sys_write;
%apply (char *STRING, size_t LENGTH) { (const char *buf, lkl_size_t count) };
%inline %{
long do_lkl_sys_write(unsigned int fd, const char *buf, lkl_size_t count)
{
    return lkl_sys_write(fd, buf, count);
}
%}
%clear const char *buf, lkl_size_t count;

%typemap(in, numinputs=0) struct lkl_stat **res (struct lkl_stat* temp) {
    $1 = &temp;
}
%typemap(argout) struct lkl_stat **res {
    %append_output(SWIG_NewPointerObj((void*)($1), $1_descriptor, SWIG_POINTER_OWN));
}

%rename do_lkl_sys_stat lkl_sys_stat;
%inline %{
int do_lkl_sys_stat(const char *filename, struct lkl_stat **res)
{
    struct lkl_stat *statbuf = malloc(sizeof(*statbuf));
    int ret;
    if (!statbuf) {
        *res = NULL;
        return -ENOMEM;
    }
    ret = lkl_sys_stat(filename, statbuf);
    if (ret) {
        free(statbuf);
        return ret;
    }
    *res = statbuf;
    return 0;
}
%}
%clear struct lkl_stat **res;

%typemap(in, numinputs=0) struct lkl_dir **res (struct lkl_dir* temp) {
    $1 = &temp;
}
%typemap(argout) struct lkl_dir **res {
    %append_output(SWIG_NewPointerObj((void*)*($1), $*1_descriptor, SWIG_POINTER_OWN));
}

%rename do_lkl_opendir lkl_opendir;
%inline %{
int do_lkl_opendir(const char *path, struct lkl_dir **res)
{
    int ret = 0;
    struct lkl_dir* dir = lkl_opendir(path, &ret);
    *res = dir;

    return ret;
}
%}
%clear struct lkl_dir **res;

/*
 * struct lkl_linux_dirent64 has: char d_name[0]; so of course swig thinks
 * that's always a zero-length string... So do more wrapping.
 */
%typemap(in, numinputs=0) struct wrapped_lkl_dirent **res (struct wrapped_lkl_dirent* temp) {
    $1 = &temp;
}
%typemap(argout) struct wrapped_lkl_dirent **res {
    %append_output(SWIG_NewPointerObj((void*)*($1), $*1_descriptor, SWIG_POINTER_OWN));
}

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
int do_lkl_readdir(struct lkl_dir *dir, struct wrapped_lkl_dirent **res)
{
    struct lkl_linux_dirent64 *de;
    struct wrapped_lkl_dirent *wrapped_de = malloc(sizeof(*wrapped_de));

    if (!wrapped_de) {
        free(wrapped_de);
        *res = NULL;
        return -ENOMEM;
    }

    de = lkl_readdir(dir);
    if (!de) {
        free(wrapped_de);
        *res = NULL;
        return lkl_errdir(dir);
    }

    wrapped_de->d_ino = de->d_ino;
    wrapped_de->d_off = de->d_off;
    wrapped_de->d_reclen = de->d_reclen;
    wrapped_de->d_type = de->d_type;
    wrapped_de->d_name = strdup(de->d_name);

    *res = wrapped_de;
    return 0;
}
%}
%clear struct wrapped_lkl_dirent **res;
