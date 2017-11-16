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

%ignore lkl_mount_dev;
%ignore lkl_sys_read;
%ignore lkl_sys_write;

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

/* Apply overrides */
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
