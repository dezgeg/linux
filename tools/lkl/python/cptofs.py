import argparse
import fnmatch
import lkl
import os
import stat
import sys

cptofs = False
cla = None

def concat_path(p1, p2):
    if not isinstance(p1, bytes):
        p1 = p1.encode('utf-8')
    if not isinstance(p2, bytes):
        p2 = p2.encode('utf-8')

    return b"%s/%s" % (p1, p2)

def open_src(path):
    if cptofs:
        fd = os.open(path, os.O_RDONLY, 0)
    else:
        fd = lkl.lkl_sys_open(path, lkl.LKL_O_RDONLY, 0)

    if fd < 0:
        print("unable to open file %s for reading: %s" % (path, strerror(errno) if cptofs else lkl.lkl_strerror(fd)))

    return fd

def open_dst(path, mode):
    print(("open_dst", path, mode))
    if cptofs:
        fd = lkl.lkl_sys_open(path, lkl.LKL_O_RDWR | lkl.LKL_O_TRUNC | lkl.LKL_O_CREAT, mode)
    else:
        fd = open(path, O_RDWR | O_TRUNC | O_CREAT, mode)

    if fd < 0:
        print("unable to open file %s for writing: %s\n" % (path, lkl.lkl_strerror(fd) if cptofs else strerror(errno)))

    if cla.selinux and cptofs:
        ret = lkl.lkl_sys_fsetxattr(fd, "security.selinux", cla.selinux,
                        strlen(cla.selinux), 0)
        if ret:
            fprintf(stderr, "unable to set selinux attribute on %s: %s\n",
                path, lkl_strerror(ret))

    return fd

def read_src(fd, len):
    #print(('read_src', fd, len))
    if cptofs:
        buf = os.read(fd, len)
    else:
        ret, buf = lkl.lkl_sys_read(fd, len)

        if ret < 0:
            fprintf(stderr, "error reading file: %s\n",
                strerror(errno) if cptofs else lkl_strerror(ret))

    return buf

def write_dst(fd, buf):
    #print(("write_dst", fd, buf))
    if cptofs:
        ret = lkl.lkl_sys_write(fd, buf)
    else:
        ret = write(fd, buf)

    if ret < 0:
        print("error writing file: %s" % lkl.lkl_strerror(ret) if cptofs else strerror(errno))

    return ret

def close_src(fd):
    if cptofs:
        os.close(fd)
    else:
        lkl.lkl_sys_close(fd)

def close_dst(fd):
    if cptofs:
        lkl.lkl_sys_close(fd)
    else:
        close(fd)

def copy_file(src, dst, mode):
    print(("copy_file", src, dst, mode))
    fd_src = open_src(src)
    if fd_src < 0:
        return fd_src

    fd_dst = open_dst(dst, mode)
    if fd_dst < 0:
        return fd_dst

    ret = 0
    while True:
        buf = read_src(fd_src, 4096)
        if len(buf) == 0:
            break

        while len(buf) > 0:
            wrote = write_dst(fd_dst, buf)

            if wrote < 0:
                ret = wrote
                break
            buf = buf[wrote:]

        if ret:
            break

    close_src(fd_src)
    close_dst(fd_dst)

    return ret


def stat_src(path):
    ret = 0
    retval = {}
    if cptofs:
        sr = os.lstat(path)
        retval['type'] = stat.S_IFMT(sr.st_mode)
        retval['mode'] = stat.S_IMODE(sr.st_mode)
        retval['size'] = sr.st_size
        #mtime->tv_sec = stat.st_mtim.tv_sec
        #mtime->tv_nsec = stat.st_mtim.tv_nsec
        #atime->tv_sec = stat.st_atim.tv_sec
        #atime->tv_nsec = stat.st_atim.tv_nsec
    else:
        ret = lkl.lkl_sys_lstat(path)
        #*type = lkl_stat.st_mode & S_IFMT
        #*mode = lkl_stat.st_mode & ~S_IFMT
        #*size = lkl_stat.st_size
        #mtime->tv_sec = lkl_stat.lkl_st_mtime
        #mtime->tv_nsec = lkl_stat.st_mtime_nsec
        #atime->tv_sec = lkl_stat.lkl_st_atime
        #atime->tv_nsec = lkl_stat.st_atime_nsec

    if ret:
        fprintf(stderr, "fsimg lstat(%s) error: %s\n",
            path, strerror(errno) if cptofs else lkl_strerror(ret))
        return ret

    return retval


def mkdir_dst(path, mode):
    if cptofs:
        ret = lkl.lkl_sys_mkdir(path, mode)
        if ret == -lkl.LKL_EEXIST:
            ret = 0
    else:
        ret = mkdir(path, mode)
        if ret < 0 and errno == EEXIST:
            ret = 0

    if ret:
        fprintf(stderr, "unable to create directory %s: %s\n",
            path, strerror(errno) if cptofs else lkl_strerror(ret))

    return ret


def readlink_src(src):
    if cptofs:
        out = os.readlink(src)
    else:
        ret = lkl.lkl_sys_readlink(src, out, outsize)

    if ret < 0:
        fprintf(stderr, "unable to readlink '%s': %s\n", src,
            strerror(errno) if cptofs else lkl_strerror(ret))

    return ret


def symlink_dst(path, target):
    if cptofs:
        ret = lkl.lkl_sys_symlink(target, path)
    else:
        ret = symlink(target, path)

    if ret:
        fprintf(stderr, "unable to symlink '%s' with target '%s': %s\n",
            path, target, lkl_strerror(ret) if cptofs else
            strerror(errno))

    return ret

def copy_symlink(src, dst):
    ret = stat_src(src)
    if ret:
        return ret

    target = readlink_src(src)

    ret = symlink_dst(dst, target)

    return ret


def do_entry(_src, _dst, name):
    print(("do_entry", _src, _dst, name))
    src = concat_path(_src, name)
    dst = concat_path(_dst, name)

    ret = stat_src(src)

    if ret['type'] == stat.S_IFREG:
        ret = copy_file(src, dst, ret['mode'])
    elif ret['type'] == stat.S_IFDIR:
        ret = mkdir_dst(dst, ret['mode'])
        if not ret:
            ret = searchdir(src, dst, None)
    elif ret['type'] == stat.S_IFLNK:
        ret = copy_symlink(src, dst)
    else:
        printf("skipping %s: unsupported entry type %d\n", src, type)

    #if !ret:
    #    if cptofs:
    #        struct lkl_timespec lkl_ts[] =  atime, mtime 

    #        ret = lkl.lkl_sys_utimensat(-1, dst, lkl_ts, LKL_AT_SYMLINK_NOFOLLOW)
    #     else:
    #        struct timespec ts[] = 
    #             .tv_sec = atime.tv_sec, .tv_nsec = atime.tv_nsec, ,
    #             .tv_sec = mtime.tv_sec, .tv_nsec = mtime.tv_nsec, ,

    #        ret = utimensat(-1, dst, ts, AT_SYMLINK_NOFOLLOW)

    if ret:
        print("error processing entry '%s', aborting" % src)

    return ret


def list_dir(path):
    if cptofs:
        res = os.listdir(path)
    else:
        raise 42
        res = lkl_opendir(path)

    if not res:
        fprintf(stderr, "unable to open directory %s: %s\n",
            path, strerror(errno) if cptofs else lkl_strerror(err))
    return res


def read_dir(dir, path):
    if cptofs:
        de = readdir(dir)

        if de:
            name = de.d_name
    else:
        de = lkl_readdir(lkl_dir)
        if de:
            name = de.d_name

    if not name:
        if cptofs:
            if errno:
                err = strerror(errno)
        else:
            if lkl_errdir(lkl_dir):
                err = lkl_strerror(lkl_errdir(lkl_dir))

    if err:
        fprintf(stderr, "error while reading directory %s: %s\n",
            path, err)
    return name


def close_dir(dir):
    if cptofs:
        closedir(dir)
    else:
        lkl_closedir(dir)

def searchdir(src, dst, match):
    print(("searchdir", src, dst, match))
    if src == '':
        src = '.'

    names = list_dir(src)
    if not names:
        return -1

    ret = 0
    for name in names:
        if not name:
            break
        if name == "." or name == "..":
            continue

        if match is not None and not fnmatch.fnmatch(name, match):
            continue

        ret = do_entry(src, dst, name)
        if ret:
            break

    return ret


def match_root(src):
    for i in range(len(src)):
        if src[i] == '.':
            if i > 0 and src[i - 1] == '.':
                return 0
        elif src[i] != '/':
            return 0

    return 1

def copy_one(src, mpoint, dst):
    print(("copy_one", src, mpoint, dst))
    if cptofs:
        src_path = src
        dst_path = concat_path(mpoint, dst)
    else:
        src_path = concat_path(mpoint, src)
        dst_path = dst

    if match_root(src):
        return searchdir(src_path, dst, None)

    src_path_dir = os.path.dirname(src_path)
    src_path_base = os.path.basename(src_path)

    return searchdir(src_path_dir, dst_path, src_path_base)

def main():
    global cptofs
    global cla

    if os.path.basename(sys.argv[0]) == "cptofs.py":
        cptofs = True
        desc = "Copy files to a filesystem image"
    else:
        cptofs = False
        desc = "Copy files from a filesystem image"

    argp = argparse.ArgumentParser(description=desc)
    argp.add_argument('-t', '--filesystem-type', type=str, required=True, help='select filesystem type - mandatory')
    argp.add_argument('-i', '--filesystem-image', type=str, required=True, help='select filesystem type - mandatory')
    argp.add_argument('-p', '--enable-printk', default=False, action='store_true', help='show Linux printks')
    argp.add_argument('-P', '--partition', type=int, default=0, help='partition number')
    argp.add_argument('-s', '--selinux', metavar='CONTEXT', type=str, default=None, help='selinux attributes for destination')
    argp.add_argument('src_paths', metavar='PATH', type=str, nargs='+', help='src paths')
    argp.add_argument('dst_path', metavar='PATH', type=str, help='dst paths')
    cla = argp.parse_args()
    print(cla)

    if not cla.enable_printk:
        lkl.cvar.lkl_host_ops._print = None

    disk = lkl.lkl_disk()
    disk.fd = os.open(cla.filesystem_image, os.O_RDWR if cptofs else os.O_RDONLY)
    if disk.fd < 0:
        fprintf(stderr, "can't open fsimg %s: %s\n", cla.fsimg_path,
            strerror(errno))
        ret = 1

    disk.ops = None

    ret = lkl.lkl_disk_add(disk)
    if ret < 0:
        fprintf(stderr, "can't add disk: %s\n", lkl_strerror(ret))

    disk_id = ret

    lkl.lkl_start_kernel(lkl.cvar.lkl_host_ops, b"mem=100M")

    ret, mpoint = lkl.lkl_mount_dev(disk_id, cla.partition, cla.filesystem_type.encode('utf-8'),
                0 if cptofs else lkl.LKL_MS_RDONLY,
                None)
    if ret:
        fprintf(stderr, "can't mount disk: %s\n", lkl_strerror(ret))
    else:
        for path in cla.src_paths:
            ret = copy_one(path, mpoint, cla.dst_path)
            if ret:
                break

    ret = lkl.lkl_umount_dev(disk_id, cla.partition, 0, 1000)

    os.close(disk.fd)

    lkl.lkl_sys_halt()

if __name__ == "__main__":
    main()
