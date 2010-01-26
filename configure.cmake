# Copyright (C) 2009 Sun Microsystems,Inc
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
#

INCLUDE (CheckCSourceCompiles)
INCLUDE (CheckCXXSourceCompiles)
INCLUDE (CheckStructHasMember)
INCLUDE (CheckLibraryExists)
INCLUDE (CheckFunctionExists)
INCLUDE (CheckCCompilerFlag)
INCLUDE (CheckCSourceRuns)
INCLUDE (CheckSymbolExists)


# Sometimes it is handy to know if PIC option
# is set, to avoid recompilation of the same source 
# for shared libs. We also allow it as an option for
# fast compile.
IF(UNIX)
  IF(APPLE)  
    # OSX  executable are always PIC
    SET(WITH_PIC ON)
  ELSE()
    OPTION(WITH_PIC "Generate PIC objects" OFF)
    IF(WITH_PIC)
      SET(CMAKE_C_FLAGS 
        "${CMAKE_C_FLAGS} ${CMAKE_SHARED_LIBRARY_C_FLAGS}")
      SET(CMAKE_CXX_FLAGS 
        "${CMAKE_CXX_FLAGS} ${CMAKE_SHARED_LIBRARY_CXX_FLAGS}")
    ENDIF()
  ENDIF()
ENDIF()


#
# Tests for OS
#
IF (CMAKE_SYSTEM_NAME MATCHES "Linux")
  SET(TARGET_OS_LINUX 1)
  SET(HAVE_NPTL 1)
  SET(_GNU_SOURCE 1)
ELSEIF(CMAKE_SYSTEM_NAME MATCHES "SunOS")
  SET(TARGET_OS_SOLARIS 1)
ENDIF()

# System type affects version_compile_os variable 
IF(NOT SYSTEM_TYPE)
  IF(PLATFORM)
    SET(SYSTEM_TYPE ${PLATFORM})
  ELSE()
    SET(SYSTEM_TYPE ${CMAKE_SYSTEM_NAME})
  ENDIF()
ENDIF()


IF(CMAKE_COMPILER_IS_GNUCXX)
  SET(CMAKE_CXX_FLAGS 
    "${CMAKE_CXX_FLAGS} -fno-implicit-templates -fno-exceptions -fno-rtti")
  IF(CMAKE_CXX_FLAGS)
    STRING(REGEX MATCH "fno-implicit-templates" NO_IMPLICIT_TEMPLATES
      ${CMAKE_CXX_FLAGS})
    IF (NO_IMPLICIT_TEMPLATES)
      SET(HAVE_EXPLICIT_TEMPLATE_INSTANTIATION TRUE)
    ENDIF()
  ENDIF()
  IF(APPLE AND CMAKE_OSX_DEPLOYMENT_TARGET)
    # Workaround linker problems  on OSX 10.4
    IF(CMAKE_OSX_DEPLOYMENT_TARGET VERSION_LESS "10.5")
      ADD_DEFINITIONS(-fno-common)
    ENDIF()
  ENDIF()
ENDIF()


# Large files
SET(_LARGEFILE_SOURCE  1)
IF(CMAKE_SYSTEM_NAME STREQUAL "HP-UX")
  SET(_LARGEFILE64_SOURCE 1)
  SET(_FILE_OFFSET_BITS 64)
ENDIF()
IF(CMAKE_SYSTEM_NAME STREQUAL "Linux" OR CMAKE_SYSTEM_NAME STREQUAL "SunOS" )
  SET(_FILE_OFFSET_BITS 64)
ENDIF()
IF(CMAKE_SYSTEM_NAME MATCHES "AIX" OR CMAKE_SYSTEM_NAME MATCHES "OS400")
  SET(_LARGE_FILES 1)
ENDIF()


IF(CMAKE_GENERATOR MATCHES "Visual Studio 7")
    # VS2003 has a bug that prevents linking mysqld with module definition file 
    # (/DEF option for linker). Linker would incorrectly complain about multiply
    # defined symbols. Workaround is to disable dynamic plugins, so /DEF is not
    # used.
    MESSAGE(
   "Warning: Building MySQL with Visual Studio 2003.NET is no more supported.")
    MESSAGE("Please use a newer version of Visual Studio.")
    SET(WITHOUT_DYNAMIC_PLUGINS TRUE)
	
    # VS2003 needs the /Op compiler option to disable floating point 
    # optimizations
    SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /Op")
    SET(CMAKE_C_FLAGS "${CMAKE_CXX_FLAGS} /Op")
ENDIF()


IF(CMAKE_SYSTEM_NAME STREQUAL "HP-UX" )
  IF(CMAKE_SIZEOF_VOID_P EQUAL 4)
    # HPUX linker crashes building plugins
    SET(WITHOUT_DYNAMIC_PLUGINS TRUE)
  ENDIF()
  # If Itanium make shared library suffix .so
  # OS understands both .sl and .so. CMake would
  # use .sl, however MySQL prefers .so
  IF(NOT CMAKE_SYSTEM_PROCESSOR MATCHES "9000")
    SET(CMAKE_SHARED_LIBRARY_SUFFIX ".so" CACHE INTERNAL "" FORCE)
    SET(CMAKE_SHARED_MODULE_SUFFIX ".so" CACHE INTERNAL "" FORCE)
  ENDIF()
ENDIF()

# Ensure we have clean build for shared libraries
# without extra dependencies and without unresolved symbols
# (on system that support it)
IF(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  FOREACH(LANG C CXX)
  STRING(REPLACE "-rdynamic" "" 
    CMAKE_SHARED_LIBRARY_LINK_${LANG}_FLAGS
    ${CMAKE_SHARED_LIBRARY_LINK_${LANG}_FLAGS}  
  )
  ENDFOREACH()
  SET(LINK_FLAG_NO_UNDEFINED "--Wl,--no-undefined")
ENDIF()

#Some OS specific hacks
IF(CMAKE_SYSTEM_NAME MATCHES "FreeBSD")
  ADD_DEFINITIONS(-DNET_RETRY_COUNT=1000000)
ELSEIF(CMAKE_SYSTEM MATCHES "HP-UX" AND CMAKE_SYSTEM MATCHES "11")
  ADD_DEFINITIONS(-DHPUX11)
ENDIF()

IF(CMAKE_SYSTEM_NAME MATCHES "SunOS")
  ADD_DEFINITIONS(-DHAVE_RWLOCK_T)
ENDIF()


# Figure out what engines to build and how (statically or dynamically),
# add preprocessor defines for storage engines.
IF(WITHOUT_DYNAMIC_PLUGINS)
  MESSAGE("Dynamic plugins are disabled.")
ENDIF(WITHOUT_DYNAMIC_PLUGINS)


# Searches function in libraries
# if function is found, sets output parameter result to the name of the library
# if function is found in libc, result will be empty 
FUNCTION(MY_SEARCH_LIBS func libs result)
  CHECK_FUNCTION_EXISTS(${func} HAVE_${func}_IN_LIBC)
  IF(HAVE_${func}_IN_LIBC)
    SET(${result} "" PARENT_SCOPE)
    RETURN()
  ENDIF()
  FOREACH(lib  ${libs})
    CHECK_LIBRARY_EXISTS(${lib} ${func} "" HAVE_${func}_IN_${lib}) 
    IF(HAVE_${func}_IN_${lib})
      SET(${result} ${lib} PARENT_SCOPE)
      RETURN()
    ENDIF()
  ENDFOREACH()
ENDFUNCTION()

IF(UNIX)
  MY_SEARCH_LIBS(floor m LIBM)
  IF(NOT LIBM)
    MY_SEARCH_LIBS(__infinity m LIBM)
  ENDIF()
  
  IF(CMAKE_SYSTEM_NAME MATCHES "SunOS")
   # On  Solaris, use of intrinsics will screw the lib search logic
   # Force using -lm, so rint etc are found.
   SET(LIBM m)
  ENDIF()

  MY_SEARCH_LIBS(gethostbyname_r  "nsl_r;nsl" LIBNSL)
  MY_SEARCH_LIBS(bind "bind;socket" LIBBIND)
  MY_SEARCH_LIBS(crypt crypt LIBCRYPT)
  MY_SEARCH_LIBS(setsockopt socket LIBSOCKET)
  MY_SEARCH_LIBS(dlopen dl LIBDL)
  MY_SEARCH_LIBS(sched_yield rt LIBRT)
  IF(NOT LIBRT)
    MY_SEARCH_LIBS(clock_gettime rt LIBRT)
  ENDIF()
  FIND_PACKAGE(Threads)

  IF(CMAKE_SYSTEM_NAME MATCHES "SunOS")
    # CMake defined -lthread as thread flag 
    # This crashes in dlopen when trying to load plugins 
    # Workaround with -lpthread
    SET(CMAKE_THREADS_LIBS_INIT -lpthread)
  ENDIF()

  SET(CMAKE_REQUIRED_LIBRARIES 
    ${LIBM} ${LIBNSL} ${LIBBIND} ${LIBCRYPT} ${LIBSOCKET} ${LIBDL} ${CMAKE_THREAD_LIBS_INIT} ${LIBRT})

  LIST(REMOVE_DUPLICATES CMAKE_REQUIRED_LIBRARIES)
  LINK_LIBRARIES(${CMAKE_THREAD_LIBS_INIT})
  
  OPTION(WITH_LIBWRAP "Compile with tcp wrappers support" OFF)
  IF(WITH_LIBWRAP)
    SET(SAVE_CMAKE_REQUIRED_LIBRARIES ${CMAKE_REQUIRED_LIBRARIES})
    SET(CMAKE_REQUIRED_LIBRARIES ${CMAKE_REQUIRED_LIBRARIES} wrap)
    CHECK_C_SOURCE_COMPILES(
    "
    #include <tcpd.h>
    int allow_severity = 0;
    int deny_severity  = 0;
    int main()
    {
      hosts_access(0);
    }"
    HAVE_LIBWRAP)
    SET(CMAKE_REQUIRED_LIBRARIES ${SAVE_CMAKE_REQUIRED_LIBRARIES})
    IF(HAVE_LIBWRAP)
      SET(MYSYS_LIBWRAP_SOURCE  ${CMAKE_SOURCE_DIR}/mysys/my_libwrap.c)
      SET(LIBWRAP "wrap")
    ENDIF()
  ENDIF()
ENDIF()

# Workaround for CMake bug#9051
IF(CMAKE_OSX_SYSROOT)
 SET(ENV{CMAKE_OSX_SYSROOT} ${CMAKE_OSX_SYSROOT})
ENDIF()
IF(CMAKE_OSX_SYSROOT)
 SET(ENV{MACOSX_DEPLOYMENT_TARGET} ${OSX_DEPLOYMENT_TARGET})
ENDIF()


# System check macros that do nothing on Windows.
# Very often, it is known that some function is not available
# on Windows. In such cases it makes sense to use these macros
# as build  with Visual Studio is considerably faster if irrelevant
# checks are omitted.
MACRO(CHECK_INCLUDE_FILES_UNIX INCLUDES VAR)
IF(UNIX)
  CHECK_INCLUDE_FILES ("${INCLUDES}" ${VAR})
ENDIF()
ENDMACRO()

MACRO(CHECK_C_SOURCE_COMPILES_UNIX SRC VAR)
IF(UNIX)
  CHECK_C_SOURCE_COMPILES("${SRC}" ${VAR})
ENDIF()
ENDMACRO()

MACRO(CHECK_CXX_SOURCE_COMPILES_UNIX SRC VAR)
IF(UNIX)
  CHECK_CXX_SOURCE_COMPILES("${SRC}" ${VAR})
ENDIF()
ENDMACRO()

MACRO(CHECK_FUNCTION_EXISTS_UNIX FUNC VAR)
IF(UNIX)
  CHECK_FUNCTION_EXISTS("${FUNC}" ${VAR})
ENDIF()
ENDMACRO()

MACRO (CHECK_SYMBOL_EXISTS_UNIX SYM HEADER VAR)
IF(UNIX)
  CHECK_SYMBOL_EXISTS("${SYM}" "${HEADER}" ${VAR})
ENDIF()
ENDMACRO()

#
# Tests for header files
#
INCLUDE (CheckIncludeFiles)

CHECK_INCLUDE_FILES ("stdlib.h;stdarg.h;string.h;float.h" STDC_HEADERS)
CHECK_INCLUDE_FILES (sys/types.h HAVE_SYS_TYPES_H)
CHECK_INCLUDE_FILES_UNIX (alloca.h HAVE_ALLOCA_H)
CHECK_INCLUDE_FILES_UNIX (aio.h HAVE_AIO_H)
CHECK_INCLUDE_FILES_UNIX (arpa/inet.h HAVE_ARPA_INET_H)
CHECK_INCLUDE_FILES_UNIX (crypt.h HAVE_CRYPT_H)
CHECK_INCLUDE_FILES (dirent.h HAVE_DIRENT_H)
CHECK_INCLUDE_FILES_UNIX (dlfcn.h HAVE_DLFCN_H)
CHECK_INCLUDE_FILES_UNIX (execinfo.h HAVE_EXECINFO_H)
CHECK_INCLUDE_FILES (fcntl.h HAVE_FCNTL_H)
CHECK_INCLUDE_FILES (fenv.h HAVE_FENV_H)
CHECK_INCLUDE_FILES (float.h HAVE_FLOAT_H)
CHECK_INCLUDE_FILES_UNIX (floatingpoint.h HAVE_FLOATINGPOINT_H)
CHECK_INCLUDE_FILES_UNIX (fpu_control.h HAVE_FPU_CONTROL_H)
CHECK_INCLUDE_FILES_UNIX (grp.h HAVE_GRP_H)
CHECK_INCLUDE_FILES_UNIX (ieeefp.h HAVE_IEEEFP_H)
CHECK_INCLUDE_FILES (inttypes.h HAVE_INTTYPES_H)
CHECK_INCLUDE_FILES_UNIX (langinfo.h HAVE_LANGINFO_H)
CHECK_INCLUDE_FILES (limits.h HAVE_LIMITS_H)
CHECK_INCLUDE_FILES (locale.h HAVE_LOCALE_H)
CHECK_INCLUDE_FILES (malloc.h HAVE_MALLOC_H)
CHECK_INCLUDE_FILES (memory.h HAVE_MEMORY_H)
CHECK_INCLUDE_FILES_UNIX (netinet/in.h HAVE_NETINET_IN_H)
CHECK_INCLUDE_FILES_UNIX (paths.h HAVE_PATHS_H)
CHECK_INCLUDE_FILES_UNIX (port.h HAVE_PORT_H)
CHECK_INCLUDE_FILES_UNIX (pwd.h HAVE_PWD_H)
CHECK_INCLUDE_FILES_UNIX (sched.h HAVE_SCHED_H)
CHECK_INCLUDE_FILES_UNIX (select.h HAVE_SELECT_H)
CHECK_INCLUDE_FILES_UNIX (semaphore.h HAVE_SEMAPHORE_H)
CHECK_INCLUDE_FILES_UNIX (sys/dir.h HAVE_SYS_DIR_H)
CHECK_INCLUDE_FILES_UNIX (sys/pte.h HAVE_SYS_PTE_H)
CHECK_INCLUDE_FILES_UNIX (sys/ptem.h HAVE_SYS_PTEM_H)
CHECK_INCLUDE_FILES (stddef.h HAVE_STDDEF_H)
CHECK_INCLUDE_FILES (stdint.h HAVE_STDINT_H)
CHECK_INCLUDE_FILES (stdlib.h HAVE_STDLIB_H)
CHECK_INCLUDE_FILES (strings.h HAVE_STRINGS_H)
CHECK_INCLUDE_FILES (string.h HAVE_STRING_H)
CHECK_INCLUDE_FILES_UNIX (synch.h HAVE_SYNCH_H)
CHECK_INCLUDE_FILES_UNIX (sysent.h HAVE_SYSENT_H)
CHECK_INCLUDE_FILES_UNIX (sys/cdefs.h HAVE_SYS_CDEFS_H)
CHECK_INCLUDE_FILES_UNIX (sys/file.h HAVE_SYS_FILE_H)
CHECK_INCLUDE_FILES_UNIX (sys/fpu.h HAVE_SYS_FPU_H)
CHECK_INCLUDE_FILES_UNIX (sys/ioctl.h HAVE_SYS_IOCTL_H)
CHECK_INCLUDE_FILES_UNIX (sys/ipc.h HAVE_SYS_IPC_H)
CHECK_INCLUDE_FILES_UNIX (sys/malloc.h HAVE_SYS_MALLOC_H)
CHECK_INCLUDE_FILES_UNIX (sys/mman.h HAVE_SYS_MMAN_H)
CHECK_INCLUDE_FILES_UNIX (sys/prctl.h HAVE_SYS_PRCTL_H)
CHECK_INCLUDE_FILES_UNIX (sys/resource.h HAVE_SYS_RESOURCE_H)
CHECK_INCLUDE_FILES_UNIX (sys/select.h HAVE_SYS_SELECT_H)
CHECK_INCLUDE_FILES_UNIX (sys/shm.h HAVE_SYS_SHM_H)
CHECK_INCLUDE_FILES_UNIX (sys/socket.h HAVE_SYS_SOCKET_H)
CHECK_INCLUDE_FILES (sys/stat.h HAVE_SYS_STAT_H)
CHECK_INCLUDE_FILES_UNIX (sys/stream.h HAVE_SYS_STREAM_H)
CHECK_INCLUDE_FILES_UNIX (sys/termcap.h HAVE_SYS_TERMCAP_H)
CHECK_INCLUDE_FILES ("time.h;sys/timeb.h" HAVE_SYS_TIMEB_H)
CHECK_INCLUDE_FILES_UNIX ("curses.h;term.h" HAVE_TERM_H)
CHECK_INCLUDE_FILES_UNIX (termios.h HAVE_TERMIOS_H)
CHECK_INCLUDE_FILES_UNIX (termio.h HAVE_TERMIO_H)
CHECK_INCLUDE_FILES_UNIX (termcap.h HAVE_TERMCAP_H)
CHECK_INCLUDE_FILES_UNIX (unistd.h HAVE_UNISTD_H)
CHECK_INCLUDE_FILES (utime.h HAVE_UTIME_H)
CHECK_INCLUDE_FILES (varargs.h HAVE_VARARGS_H)
CHECK_INCLUDE_FILES (sys/time.h HAVE_SYS_TIME_H)
CHECK_INCLUDE_FILES (sys/utime.h HAVE_SYS_UTIME_H)
CHECK_INCLUDE_FILES_UNIX (sys/wait.h HAVE_SYS_WAIT_H)
CHECK_INCLUDE_FILES_UNIX (sys/param.h HAVE_SYS_PARAM_H)
CHECK_INCLUDE_FILES_UNIX (sys/vadvise.h HAVE_SYS_VADVISE_H)
CHECK_INCLUDE_FILES_UNIX (fnmatch.h HAVE_FNMATCH_H)
CHECK_INCLUDE_FILES (stdarg.h  HAVE_STDARG_H)
CHECK_INCLUDE_FILES_UNIX("stdlib.h;sys/un.h" HAVE_SYS_UN_H)

# Figure out threading library
#
FIND_PACKAGE (Threads)

#
# Tests for functions
#
#CHECK_FUNCTION_EXISTS (aiowait HAVE_AIOWAIT)
CHECK_FUNCTION_EXISTS_UNIX (aio_read HAVE_AIO_READ)
CHECK_FUNCTION_EXISTS_UNIX (alarm HAVE_ALARM)
SET(HAVE_ALLOCA 1)
CHECK_FUNCTION_EXISTS_UNIX (backtrace HAVE_BACKTRACE)
CHECK_FUNCTION_EXISTS_UNIX (backtrace_symbols HAVE_BACKTRACE_SYMBOLS)
CHECK_FUNCTION_EXISTS_UNIX (backtrace_symbols_fd HAVE_BACKTRACE_SYMBOLS_FD)
CHECK_FUNCTION_EXISTS_UNIX (printstack HAVE_PRINTSTACK)
CHECK_FUNCTION_EXISTS_UNIX (bcmp HAVE_BCMP)
CHECK_FUNCTION_EXISTS_UNIX (bfill HAVE_BFILL)
CHECK_FUNCTION_EXISTS_UNIX (bmove HAVE_BMOVE)
CHECK_FUNCTION_EXISTS (bsearch HAVE_BSEARCH)
CHECK_FUNCTION_EXISTS (index HAVE_INDEX)
CHECK_FUNCTION_EXISTS_UNIX (bzero HAVE_BZERO)
CHECK_FUNCTION_EXISTS_UNIX (clock_gettime HAVE_CLOCK_GETTIME)
CHECK_FUNCTION_EXISTS_UNIX (cuserid HAVE_CUSERID)
CHECK_FUNCTION_EXISTS_UNIX (directio HAVE_DIRECTIO)
CHECK_FUNCTION_EXISTS_UNIX (_doprnt HAVE_DOPRNT)
CHECK_FUNCTION_EXISTS_UNIX (flockfile HAVE_FLOCKFILE)
CHECK_FUNCTION_EXISTS_UNIX (ftruncate HAVE_FTRUNCATE)
CHECK_FUNCTION_EXISTS_UNIX (getline HAVE_GETLINE)
CHECK_FUNCTION_EXISTS_UNIX (compress HAVE_COMPRESS)
CHECK_FUNCTION_EXISTS_UNIX (crypt HAVE_CRYPT)
CHECK_FUNCTION_EXISTS_UNIX (dlerror HAVE_DLERROR)
CHECK_FUNCTION_EXISTS_UNIX (dlopen HAVE_DLOPEN)
IF (CMAKE_COMPILER_IS_GNUCC)
 IF (CMAKE_EXE_LINKER_FLAGS MATCHES " -static " 
     OR CMAKE_EXE_LINKER_FLAGS MATCHES " -static$")
   SET(HAVE_DLOPEN FALSE CACHE "Disable dlopen due to -static flag" FORCE)
   SET(WITHOUT_DYNAMIC_PLUGINS TRUE)
 ENDIF()
ENDIF()
CHECK_FUNCTION_EXISTS_UNIX (fchmod HAVE_FCHMOD)
CHECK_FUNCTION_EXISTS_UNIX (fcntl HAVE_FCNTL)
CHECK_FUNCTION_EXISTS_UNIX (fconvert HAVE_FCONVERT)
CHECK_SYMBOL_EXISTS_UNIX(fdatasync "unistd.h" HAVE_FDATASYNC)
CHECK_FUNCTION_EXISTS_UNIX (fesetround HAVE_FESETROUND)
CHECK_FUNCTION_EXISTS_UNIX (fpsetmask HAVE_FPSETMASK)
CHECK_FUNCTION_EXISTS_UNIX (fseeko HAVE_FSEEKO)
CHECK_FUNCTION_EXISTS_UNIX (fsync HAVE_FSYNC)
CHECK_FUNCTION_EXISTS (getcwd HAVE_GETCWD)
CHECK_FUNCTION_EXISTS_UNIX (gethostbyaddr_r HAVE_GETHOSTBYADDR_R)
CHECK_FUNCTION_EXISTS_UNIX (gethostbyname_r HAVE_GETHOSTBYNAME_R)
CHECK_FUNCTION_EXISTS_UNIX (gethrtime HAVE_GETHRTIME)
CHECK_FUNCTION_EXISTS (getnameinfo HAVE_GETNAMEINFO)
CHECK_FUNCTION_EXISTS_UNIX (getpass HAVE_GETPASS)
CHECK_FUNCTION_EXISTS_UNIX (getpassphrase HAVE_GETPASSPHRASE)
CHECK_FUNCTION_EXISTS_UNIX (getpwnam HAVE_GETPWNAM)
CHECK_FUNCTION_EXISTS_UNIX (getpwuid HAVE_GETPWUID)
CHECK_FUNCTION_EXISTS_UNIX (getrlimit HAVE_GETRLIMIT)
CHECK_FUNCTION_EXISTS_UNIX (getrusage HAVE_GETRUSAGE)
CHECK_FUNCTION_EXISTS_UNIX (getwd HAVE_GETWD)
CHECK_FUNCTION_EXISTS_UNIX (gmtime_r HAVE_GMTIME_R)
CHECK_FUNCTION_EXISTS_UNIX (initgroups HAVE_INITGROUPS)
CHECK_FUNCTION_EXISTS_UNIX (issetugid HAVE_ISSETUGID)
CHECK_FUNCTION_EXISTS (ldiv HAVE_LDIV)
CHECK_FUNCTION_EXISTS_UNIX (localtime_r HAVE_LOCALTIME_R)
CHECK_FUNCTION_EXISTS (longjmp HAVE_LONGJMP)
CHECK_FUNCTION_EXISTS (lstat HAVE_LSTAT)
CHECK_FUNCTION_EXISTS_UNIX (madvise HAVE_MADVISE)
CHECK_FUNCTION_EXISTS_UNIX (mallinfo HAVE_MALLINFO)
CHECK_FUNCTION_EXISTS (memcpy HAVE_MEMCPY)
CHECK_FUNCTION_EXISTS (memmove HAVE_MEMMOVE)
CHECK_FUNCTION_EXISTS (mkstemp HAVE_MKSTEMP)
CHECK_FUNCTION_EXISTS_UNIX (mlock HAVE_MLOCK)
CHECK_FUNCTION_EXISTS_UNIX (mlockall HAVE_MLOCKALL)
CHECK_FUNCTION_EXISTS_UNIX (mmap HAVE_MMAP)
CHECK_FUNCTION_EXISTS_UNIX (mmap64 HAVE_MMAP64)
CHECK_FUNCTION_EXISTS (perror HAVE_PERROR)
CHECK_FUNCTION_EXISTS_UNIX (poll HAVE_POLL)
CHECK_FUNCTION_EXISTS_UNIX (port_create HAVE_PORT_CREATE)
CHECK_FUNCTION_EXISTS_UNIX (posix_fallocate HAVE_POSIX_FALLOCATE)
CHECK_FUNCTION_EXISTS_UNIX (pread HAVE_PREAD)
CHECK_FUNCTION_EXISTS_UNIX (pthread_attr_create HAVE_PTHREAD_ATTR_CREATE)
CHECK_FUNCTION_EXISTS_UNIX (pthread_attr_getstacksize HAVE_PTHREAD_ATTR_GETSTACKSIZE)
CHECK_FUNCTION_EXISTS_UNIX (pthread_attr_setscope HAVE_PTHREAD_ATTR_SETSCOPE)
CHECK_FUNCTION_EXISTS_UNIX (pthread_attr_setstacksize HAVE_PTHREAD_ATTR_SETSTACKSIZE)
CHECK_FUNCTION_EXISTS_UNIX (pthread_condattr_create HAVE_PTHREAD_CONDATTR_CREATE)
CHECK_FUNCTION_EXISTS_UNIX (pthread_condattr_setclock HAVE_PTHREAD_CONDATTR_SETCLOCK)
CHECK_FUNCTION_EXISTS_UNIX (pthread_init HAVE_PTHREAD_INIT)
CHECK_FUNCTION_EXISTS_UNIX (pthread_key_delete HAVE_PTHREAD_KEY_DELETE)
CHECK_FUNCTION_EXISTS_UNIX (pthread_rwlock_rdlock HAVE_PTHREAD_RWLOCK_RDLOCK)
CHECK_FUNCTION_EXISTS_UNIX (pthread_sigmask HAVE_PTHREAD_SIGMASK)
CHECK_FUNCTION_EXISTS_UNIX (pthread_threadmask HAVE_PTHREAD_THREADMASK)
CHECK_FUNCTION_EXISTS_UNIX (pthread_yield_np HAVE_PTHREAD_YIELD_NP)
CHECK_FUNCTION_EXISTS (putenv HAVE_PUTENV)
CHECK_FUNCTION_EXISTS_UNIX (readdir_r HAVE_READDIR_R)
CHECK_FUNCTION_EXISTS_UNIX (readlink HAVE_READLINK)
CHECK_FUNCTION_EXISTS_UNIX (re_comp HAVE_RE_COMP)
CHECK_FUNCTION_EXISTS_UNIX (regcomp HAVE_REGCOMP)
CHECK_FUNCTION_EXISTS_UNIX (realpath HAVE_REALPATH)
CHECK_FUNCTION_EXISTS (rename HAVE_RENAME)
CHECK_FUNCTION_EXISTS_UNIX (rwlock_init HAVE_RWLOCK_INIT)
CHECK_FUNCTION_EXISTS_UNIX (sched_yield HAVE_SCHED_YIELD)
CHECK_FUNCTION_EXISTS_UNIX (setenv HAVE_SETENV)
CHECK_FUNCTION_EXISTS (setlocale HAVE_SETLOCALE)
CHECK_FUNCTION_EXISTS_UNIX (setfd HAVE_SETFD)
CHECK_FUNCTION_EXISTS_UNIX (sigaction HAVE_SIGACTION)
CHECK_FUNCTION_EXISTS_UNIX (sigthreadmask HAVE_SIGTHREADMASK)
CHECK_FUNCTION_EXISTS_UNIX (sigwait HAVE_SIGWAIT)
CHECK_FUNCTION_EXISTS_UNIX (sigaddset HAVE_SIGADDSET)
CHECK_FUNCTION_EXISTS_UNIX (sigemptyset HAVE_SIGEMPTYSET)
CHECK_FUNCTION_EXISTS_UNIX (sighold HAVE_SIGHOLD) 
CHECK_FUNCTION_EXISTS_UNIX (sigset HAVE_SIGSET)
CHECK_FUNCTION_EXISTS_UNIX (sleep HAVE_SLEEP)
CHECK_FUNCTION_EXISTS (snprintf HAVE_SNPRINTF)
CHECK_FUNCTION_EXISTS_UNIX (stpcpy HAVE_STPCPY)
CHECK_FUNCTION_EXISTS (strcoll HAVE_STRCOLL)
CHECK_FUNCTION_EXISTS (strerror HAVE_STRERROR)
CHECK_FUNCTION_EXISTS_UNIX (strlcpy HAVE_STRLCPY)
CHECK_FUNCTION_EXISTS (strnlen HAVE_STRNLEN)
CHECK_FUNCTION_EXISTS_UNIX (strlcat HAVE_STRLCAT)
CHECK_FUNCTION_EXISTS_UNIX (strsignal HAVE_STRSIGNAL)
CHECK_FUNCTION_EXISTS_UNIX (fgetln HAVE_FGETLN)
CHECK_FUNCTION_EXISTS (strpbrk HAVE_STRPBRK)
CHECK_FUNCTION_EXISTS (strsep HAVE_STRSEP)
CHECK_FUNCTION_EXISTS (strstr HAVE_STRSTR)
CHECK_FUNCTION_EXISTS_UNIX (strtok_r HAVE_STRTOK_R)
CHECK_FUNCTION_EXISTS (strtol HAVE_STRTOL)
CHECK_FUNCTION_EXISTS (strtoll HAVE_STRTOLL)
CHECK_FUNCTION_EXISTS (strtoul HAVE_STRTOUL)
CHECK_FUNCTION_EXISTS (strtoull HAVE_STRTOULL)
CHECK_FUNCTION_EXISTS (strcasecmp HAVE_STRCASECMP)
CHECK_FUNCTION_EXISTS (strncasecmp HAVE_STRNCASECMP)
CHECK_FUNCTION_EXISTS (strdup HAVE_STRDUP)
CHECK_FUNCTION_EXISTS_UNIX (shmat HAVE_SHMAT) 
CHECK_FUNCTION_EXISTS_UNIX (shmctl HAVE_SHMCTL)
CHECK_FUNCTION_EXISTS_UNIX (shmdt HAVE_SHMDT)
CHECK_FUNCTION_EXISTS_UNIX (shmget HAVE_SHMGET)
CHECK_FUNCTION_EXISTS (tell HAVE_TELL)
CHECK_FUNCTION_EXISTS (tempnam HAVE_TEMPNAM)
CHECK_FUNCTION_EXISTS_UNIX (thr_setconcurrency HAVE_THR_SETCONCURRENCY)
CHECK_FUNCTION_EXISTS_UNIX (thr_yield HAVE_THR_YIELD)
CHECK_FUNCTION_EXISTS_UNIX (vasprintf HAVE_VASPRINTF)
CHECK_FUNCTION_EXISTS (vsnprintf HAVE_VSNPRINTF)
CHECK_FUNCTION_EXISTS_UNIX (vprintf HAVE_VPRINTF)
CHECK_FUNCTION_EXISTS_UNIX (valloc HAVE_VALLOC)
CHECK_FUNCTION_EXISTS_UNIX (memalign HAVE_MEMALIGN)
CHECK_FUNCTION_EXISTS_UNIX (chown HAVE_CHOWN)
CHECK_FUNCTION_EXISTS_UNIX (nl_langinfo HAVE_NL_LANGINFO)

#--------------------------------------------------------------------
# Support for WL#2373 (Use cycle counter for timing)
#--------------------------------------------------------------------

CHECK_INCLUDE_FILES_UNIX(time.h HAVE_TIME_H)
CHECK_INCLUDE_FILES_UNIX(sys/time.h HAVE_SYS_TIME_H)
CHECK_INCLUDE_FILES_UNIX(sys/times.h HAVE_SYS_TIMES_H)
CHECK_INCLUDE_FILES_UNIX(asm/msr.h HAVE_ASM_MSR_H)
#msr.h has rdtscll()

CHECK_INCLUDE_FILES_UNIX(ia64intrin.h HAVE_IA64INTRIN_H)

CHECK_FUNCTION_EXISTS_UNIX(times HAVE_TIMES)
CHECK_FUNCTION_EXISTS_UNIX(gettimeofday HAVE_GETTIMEOFDAY)
CHECK_FUNCTION_EXISTS_UNIX(read_real_time HAVE_READ_REAL_TIME)
# This should work on AIX.

CHECK_FUNCTION_EXISTS_UNIX(ftime HAVE_FTIME)
# This is still a normal call for milliseconds.

CHECK_FUNCTION_EXISTS_UNIX(time HAVE_TIME)
# We can use time() on Macintosh if there is no ftime().

CHECK_FUNCTION_EXISTS_UNIX(rdtscll HAVE_RDTSCLL)
# I doubt that we'll ever reach the check for this.


#
# Tests for symbols
#

CHECK_SYMBOL_EXISTS_UNIX(sys_errlist "stdio.h" HAVE_SYS_ERRLIST)
CHECK_SYMBOL_EXISTS_UNIX(madvise "sys/mman.h" HAVE_DECL_MADVISE)
CHECK_SYMBOL_EXISTS(tzname "time.h" HAVE_TZNAME)
CHECK_SYMBOL_EXISTS_UNIX(lrand48 "stdlib.h" HAVE_LRAND48)
CHECK_SYMBOL_EXISTS_UNIX(getpagesize "unistd.h" HAVE_GETPAGESIZE)
CHECK_SYMBOL_EXISTS_UNIX(TIOCGWINSZ "sys/ioctl.h" GWINSZ_IN_SYS_IOCTL)
CHECK_SYMBOL_EXISTS_UNIX(FIONREAD "sys/ioctl.h" FIONREAD_IN_SYS_IOCTL)
CHECK_SYMBOL_EXISTS_UNIX(TIOCSTAT "sys/ioctl.h" TIOCSTAT_IN_SYS_IOCTL)
CHECK_SYMBOL_EXISTS(gettimeofday "sys/time.h" HAVE_GETTIMEOFDAY)

CHECK_SYMBOL_EXISTS(finite  "math.h" HAVE_FINITE_IN_MATH_H)
IF(HAVE_FINITE_IN_MATH_H)
  SET(HAVE_FINITE TRUE CACHE INTERNAL "")
ELSE()
  CHECK_SYMBOL_EXISTS(finite  "ieeefp.h" HAVE_FINITE)
ENDIF()
CHECK_SYMBOL_EXISTS(log2  math.h HAVE_LOG2)
CHECK_SYMBOL_EXISTS(isnan math.h HAVE_ISNAN)
CHECK_SYMBOL_EXISTS(rint  math.h HAVE_RINT)

# isinf() prototype not found on Solaris
CHECK_CXX_SOURCE_COMPILES(
"#include  <math.h>
int main() { 
  isinf(0.0); 
  return 0;
}" HAVE_ISINF)



#
# Test for endianess
#
INCLUDE(TestBigEndian)
IF(APPLE)
  # Cannot  run endian test on universal PPC/Intel binaries 
  # would return inconsistent result.
  # config.h.cmake includes a special #ifdef for Darwin
ELSE()
  TEST_BIG_ENDIAN(WORDS_BIGENDIAN)
ENDIF()

#
# Tests for type sizes (and presence)
#
INCLUDE (CheckTypeSize)
set(CMAKE_REQUIRED_DEFINITIONS ${CMAKE_REQUIRED_DEFINITIONS}
        -D_LARGEFILE_SOURCE -D_LARGE_FILES -D_FILE_OFFSET_BITS=64
        -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS)
SET(CMAKE_EXTRA_INCLUDE_FILES signal.h)
CHECK_TYPE_SIZE(sigset_t SIZEOF_SIGSET_T)
IF(SIZEOF_SIGSET_T)
  SET(HAVE_SIGSET_T 1) 
ENDIF()
IF(NOT SIZEOF_SIGSET_T)
 SET(sigset_t int)
ENDIF()
CHECK_TYPE_SIZE(mode_t SIZEOF_MODE_T)
IF(NOT SIZEOF_MODE_T)
 SET(mode_t int)
ENDIF()


IF(HAVE_STDINT_H)
  SET(CMAKE_EXTRA_INCLUDE_FILES stdint.h)
ENDIF(HAVE_STDINT_H)

IF(NOT APPLE)
  CHECK_TYPE_SIZE("char *" SIZEOF_CHARP)
  CHECK_TYPE_SIZE(long SIZEOF_LONG)
  CHECK_TYPE_SIZE(size_t SIZEOF_SIZE_T)
ENDIF()
CHECK_TYPE_SIZE(char SIZEOF_CHAR)
CHECK_TYPE_SIZE(short SIZEOF_SHORT)
CHECK_TYPE_SIZE(int SIZEOF_INT)
CHECK_TYPE_SIZE("long long" SIZEOF_LONG_LONG)
SET(CMAKE_EXTRA_INCLUDE_FILES stdio.h sys/types.h)
CHECK_TYPE_SIZE(off_t SIZEOF_OFF_T)
CHECK_TYPE_SIZE(uchar SIZEOF_UCHAR)
CHECK_TYPE_SIZE(uint SIZEOF_UINT)
CHECK_TYPE_SIZE(ulong SIZEOF_ULONG)
CHECK_TYPE_SIZE(int8 SIZEOF_INT8)
CHECK_TYPE_SIZE(uint8 SIZEOF_UINT8)
CHECK_TYPE_SIZE(int16 SIZEOF_INT16)
CHECK_TYPE_SIZE(uint16 SIZEOF_UINT16)
CHECK_TYPE_SIZE(int32 SIZEOF_INT32)
CHECK_TYPE_SIZE(uint32 SIZEOF_UINT32)
CHECK_TYPE_SIZE(u_int32_t SIZEOF_U_INT32_T)
CHECK_TYPE_SIZE(int64 SIZEOF_INT64)
CHECK_TYPE_SIZE(uint64 SIZEOF_UINT64)
SET (CMAKE_EXTRA_INCLUDE_FILES sys/types.h)
CHECK_TYPE_SIZE(bool  SIZEOF_BOOL)
SET(CMAKE_EXTRA_INCLUDE_FILES)
IF(HAVE_SYS_SOCKET_H)
  SET(CMAKE_EXTRA_INCLUDE_FILES sys/socket.h)
ENDIF(HAVE_SYS_SOCKET_H)
CHECK_TYPE_SIZE(socklen_t SIZEOF_SOCKLEN_T)
SET(CMAKE_EXTRA_INCLUDE_FILES)

IF(HAVE_IEEEFP_H)
  SET(CMAKE_EXTRA_INCLUDE_FILES ieeefp.h)
  CHECK_TYPE_SIZE(fp_except SIZEOF_FP_EXCEPT)
  IF(SIZEOF_FP_EXCEPT)
    SET(HAVE_FP_EXCEPT TRUE)
  ENDIF() 
ENDIF()


#
# Code tests
#

CHECK_C_SOURCE_COMPILES("
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#endif
int main()
{
  getaddrinfo( 0, 0, 0, 0);
  return 0;
}"
HAVE_GETADDRINFO)

CHECK_C_SOURCE_COMPILES("
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#endif
int main()
{
  select(0,0,0,0,0);
  return 0;
}"
HAVE_SELECT)

#
# Check if timespec has ts_sec and ts_nsec fields
#

CHECK_C_SOURCE_COMPILES_UNIX("
#include <pthread.h>

int main(int ac, char **av)
{
  struct timespec abstime;
  abstime.ts_sec = time(NULL)+1;
  abstime.ts_nsec = 0;
}
" HAVE_TIMESPEC_TS_SEC)


#
# Check return type of qsort()
#
CHECK_C_SOURCE_COMPILES("
#include <stdlib.h>
#ifdef __cplusplus
extern \"C\"
#endif
void qsort(void *base, size_t nel, size_t width,
  int (*compar) (const void *, const void *));
int main(int ac, char **av) {}
" QSORT_TYPE_IS_VOID)
IF(QSORT_TYPE_IS_VOID)
  SET(RETQSORTTYPE "void")
ELSE(QSORT_TYPE_IS_VOID)
  SET(RETQSORTTYPE "int")
ENDIF(QSORT_TYPE_IS_VOID)

IF(WIN32)
SET(SOCKET_SIZE_TYPE int)
ELSE()
CHECK_CXX_SOURCE_COMPILES("
#include <sys/socket.h>
int main(int argc, char **argv)
{
  getsockname(0,0,(socklen_t *) 0);
  return 0; 
}"
HAVE_SOCKET_SIZE_T_AS_socklen_t)

IF(HAVE_SOCKET_SIZE_T_AS_socklen_t)
  SET(SOCKET_SIZE_TYPE socklen_t)
ELSE()
  CHECK_CXX_SOURCE_COMPILES("
  #include <sys/socket.h>
  int main(int argc, char **argv)
  {
    getsockname(0,0,(int *) 0);
    return 0; 
  }"
  HAVE_SOCKET_SIZE_T_AS_int)
  IF(HAVE_SOCKET_SIZE_T_AS_int)
    SET(SOCKET_SIZE_TYPE int)
  ELSE()
    CHECK_CXX_SOURCE_COMPILES("
    #include <sys/socket.h>
    int main(int argc, char **argv)
    {
      getsockname(0,0,(size_t *) 0);
      return 0; 
    }"
    HAVE_SOCKET_SIZE_T_AS_size_t)
    IF(HAVE_SOCKET_SIZE_T_AS_size_t)
      SET(SOCKET_SIZE_TYPE size_t)
    ELSE()
      SET(SOCKET_SIZE_TYPE int)
    ENDIF()
  ENDIF()
ENDIF()
ENDIF()

CHECK_CXX_SOURCE_COMPILES_UNIX("
#include <pthread.h>
int main()
{
  pthread_yield();
  return 0;
}
" HAVE_PTHREAD_YIELD_ZERO_ARG)

IF(NOT STACK_DIRECTION)
  IF(CMAKE_CROSSCOMPILING)
   MESSAGE(FATAL_ERROR 
   "STACK_DIRECTION is not defined.  Please specify -DSTACK_DIRECTION=1 "
   "or -DSTACK_DIRECTION=-1 when calling cmake.")
  ELSE()
    TRY_RUN(STACKDIR_RUN_RESULT STACKDIR_COMPILE_RESULT    
     ${CMAKE_BINARY_DIR} 
     ${CMAKE_SOURCE_DIR}/cmake/stack_direction.c
     )
     # Test program returns 0 (down) or 1 (up).
     # Convert to -1 or 1
     IF(STACKDIR_RUN_RESULT EQUAL 0)
       SET(STACK_DIRECTION -1 CACHE INTERNAL "Stack grows direction")
     ELSE()
       SET(STACK_DIRECTION 1 CACHE INTERNAL "Stack grows direction")
     ENDIF()
     MESSAGE(STATUS "Checking stack direction : ${STACK_DIRECTION}")
   ENDIF()
ENDIF()

#
# Check return type of signal handlers
#
CHECK_C_SOURCE_COMPILES("
#include <signal.h>
#ifdef signal
# undef signal
#endif
#ifdef __cplusplus
extern \"C\" void (*signal (int, void (*)(int)))(int);
#else
void (*signal ()) ();
#endif
int main(int ac, char **av) {}
" SIGNAL_RETURN_TYPE_IS_VOID)
IF(SIGNAL_RETURN_TYPE_IS_VOID)
  SET(RETSIGTYPE void)
ELSE(SIGNAL_RETURN_TYPE_IS_VOID)
  SET(RETSIGTYPE int)
ENDIF(SIGNAL_RETURN_TYPE_IS_VOID)


CHECK_INCLUDE_FILES_UNIX("time.h;sys/time.h" TIME_WITH_SYS_TIME)
CHECK_SYMBOL_EXISTS_UNIX(O_NONBLOCK "unistd.h;fcntl.h" HAVE_FCNTL_NONBLOCK)
IF(NOT HAVE_FCNTL_NONBLOCK)
 SET(NO_FCNTL_NONBLOCK 1)
ENDIF()

#
# Test for how the C compiler does inline, if at all
#
CHECK_C_SOURCE_COMPILES("
static inline int foo(){return 0;}
int main(int argc, char *argv[]){return 0;}"
                            C_HAS_inline)
IF(NOT C_HAS_inline)
  CHECK_C_SOURCE_COMPILES("
  static __inline int foo(){return 0;}
  int main(int argc, char *argv[]){return 0;}"
                            C_HAS___inline)
  SET(C_INLINE __inline)
ENDIF()

IF(NOT CMAKE_CROSSCOMPILING AND NOT MSVC)
  STRING(TOLOWER ${CMAKE_SYSTEM_PROCESSOR}  processor)
  IF(processor MATCHES "86" OR processor MATCHES "amd64" OR processor MATCHES "x64")
  #Check for x86 PAUSE instruction
  # We have to actually try running the test program, because of a bug
  # in Solaris on x86_64, where it wrongly reports that PAUSE is not
  # supported when trying to run an application.  See
  # http://bugs.opensolaris.org/bugdatabase/printableBug.do?bug_id=6478684
  CHECK_C_SOURCE_RUNS("
  int main()
  { 
    __asm__ __volatile__ (\"pause\"); 
    return 0;
  }"  HAVE_PAUSE_INSTRUCTION)
  ENDIF()
  IF (NOT HAVE_PAUSE_INSTRUCTION)
    CHECK_C_SOURCE_COMPILES("
    int main()
    {
     __asm__ __volatile__ (\"rep; nop\");
     return 0;
    }
   " HAVE_FAKE_PAUSE_INSTRUCTION)
  ENDIF()
ENDIF()
  
CHECK_SYMBOL_EXISTS_UNIX(tcgetattr "termios.h" HAVE_TCGETATTR 1)
CHECK_INCLUDE_FILES_UNIX(sys/ioctl.h HAVE_SYS_IOCTL 1)

#
# Check type of signal routines (posix, 4.2bsd, 4.1bsd or v7)
#
CHECK_C_SOURCE_COMPILES_UNIX("
  #include <signal.h>
  int main(int ac, char **av)
  {
    sigset_t ss;
    struct sigaction sa;
    sigemptyset(&ss); sigsuspend(&ss);
    sigaction(SIGINT, &sa, (struct sigaction *) 0);
    sigprocmask(SIG_BLOCK, &ss, (sigset_t *) 0);
  }"
  HAVE_POSIX_SIGNALS)

IF(NOT HAVE_POSIX_SIGNALS)
 CHECK_C_SOURCE_COMPILES_UNIX("
  #include <signal.h>
  int main(int ac, char **av)
  {
    int mask = sigmask(SIGINT);
    sigsetmask(mask); sigblock(mask); sigpause(mask);
  }"
  HAVE_BSD_SIGNALS)
  IF (NOT HAVE_BSD_SIGNALS)
    CHECK_C_SOURCE_COMPILES_UNIX("
    #include <signal.h>
    void foo() { }
    int main(int ac, char **av)
    {
      int mask = sigmask(SIGINT);
      sigset(SIGINT, foo); sigrelse(SIGINT);
      sighold(SIGINT); sigpause(SIGINT);
    }"
   HAVE_SVR3_SIGNALS)  
   IF (NOT HAVE_SVR3_SIGNALS)
    SET(HAVE_V7_SIGNALS 1)
   ENDIF(NOT HAVE_SVR3_SIGNALS)
 ENDIF(NOT HAVE_BSD_SIGNALS)
ENDIF(NOT HAVE_POSIX_SIGNALS)

# Assume regular sprintf
SET(SPRINTFS_RETURNS_INT 1)

IF(CMAKE_COMPILER_IS_GNUXX)
CHECK_CXX_SOURCE_COMPILES("
 #include <cxxabi.h>
 int main(int argc, char **argv) 
  {
    char *foo= 0; int bar= 0;
    foo= abi::__cxa_demangle(foo, foo, 0, &bar);
    return 0;
  }"
  HAVE_ABI_CXA_DEMANGLE)
IF(HAVE_ABI_CXA_DEMANGLE)
 SET(HAVE_CXXABI_H 1)
ENDIF()
ENDIF()

CHECK_C_SOURCE_COMPILES_UNIX("
  int main(int argc, char **argv) 
  {
    extern char *__bss_start;
    return __bss_start ? 1 : 0;
  }"
HAVE_BSS_START)

CHECK_C_SOURCE_COMPILES_UNIX("
    int main()
    {
      extern void __attribute__((weak)) foo(void);
      return 0;
    }"
    HAVE_WEAK_SYMBOL
)


CHECK_CXX_SOURCE_COMPILES("
    #include <new>
    int main()
    {
      char *c = new char;
      return 0;
    }"
    HAVE_CXX_NEW
)

CHECK_CXX_SOURCE_COMPILES_UNIX("
    #undef inline
    #if !defined(SCO) && !defined(__osf__) && !defined(_REENTRANT)
    #define _REENTRANT
    #endif
    #include <pthread.h>
    #include <sys/types.h>
    #include <sys/socket.h>
    #include <netinet/in.h>
    #include <arpa/inet.h>
    #include <netdb.h>
    int main()
    {

       struct hostent *foo =
       gethostbyaddr_r((const char *) 0,
          0, 0, (struct hostent *) 0, (char *) NULL,  0, (int *)0);
       return 0;
    }
  "
  HAVE_SOLARIS_STYLE_GETHOST)

CHECK_CXX_SOURCE_COMPILES_UNIX("
    #undef inline
    #if !defined(SCO) && !defined(__osf__) && !defined(_REENTRANT)
    #define _REENTRANT
    #endif
    #include <pthread.h>
    #include <sys/types.h>
    #include <sys/socket.h>
    #include <netinet/in.h>
    #include <arpa/inet.h>
    #include <netdb.h>
    int main()
    {
       int ret = gethostbyname_r((const char *) 0,
	(struct hostent*) 0, (char*) 0, 0, (struct hostent **) 0, (int *) 0);
      return 0;
    }"
    HAVE_GETHOSTBYNAME_R_GLIBC2_STYLE)

CHECK_CXX_SOURCE_COMPILES_UNIX("
    #undef inline
    #if !defined(SCO) && !defined(__osf__) && !defined(_REENTRANT)
    #define _REENTRANT
    #endif
    #include <pthread.h>
    #include <sys/types.h>
    #include <sys/socket.h>
    #include <netinet/in.h>
    #include <arpa/inet.h>
    #include <netdb.h>
    int main()
    {
      int ret = gethostbyname_r((const char *) 0, (struct hostent*) 0, (struct hostent_data*) 0);
      return 0;
    }"
    HAVE_GETHOSTBYNAME_R_RETURN_INT)

IF(CMAKE_SYSTEM_NAME STREQUAL "Linux")
 CHECK_SYMBOL_EXISTS(SHM_HUGETLB sys/shm.h  HAVE_DECL_SHM_HUGETLB)
 IF(HAVE_DECL_SHM_HUGETLB)
   SET(HAVE_LARGE_PAGES 1)
   SET(HUGETLB_USE_PROC_MEMINFO 1)
   SET(HAVE_LARGE_PAGE_OPTION 1)
  ENDIF()
ENDIF()

IF(CMAKE_SYSTEM_NAME STREQUAL "SunOS")
 CHECK_SYMBOL_EXISTS(MHA_MAPSIZE_VA sys/mman.h  HAVE_DECL_MHA_MAPSIZE_VA)
 IF(HAVE_DECL_MHA_MAPSIZE_VA)
   SET(HAVE_SOLARIS_LARGE_PAGES 1)
   SET(HAVE_LARGE_PAGE_OPTION 1)
  ENDIF()
ENDIF()

# Use of ALARMs to wakeup on timeout on sockets
#
# This feature makes use of a mutex and is a scalability hog we
# try to avoid using. However we need support for SO_SNDTIMEO and
# SO_RCVTIMEO socket options for this to work. So we will check
# if this feature is supported by a simple TRY_RUN macro. However
# on some OS's there is support for setting those variables but
# they are silently ignored. For those OS's we will not attempt
# to use SO_SNDTIMEO and SO_RCVTIMEO even if it is said to work.
# See Bug#29093 for the problem with SO_SND/RCVTIMEO on HP/UX.
# To use alarm is simple, simply avoid setting anything.

IF(WIN32)
  SET(HAVE_SOCKET_TIMEOUT 1)
ELSEIF(CMAKE_SYSTEM MATCHES "HP")
  SET(HAVE_SOCKET_TIMEOUT 0)
ELSEIF(CMAKE_CROSSCOMPILING)
  SET(HAVE_SOCKET_TIMEOUT 0)
ELSE()
SET(CMAKE_REQUIRED_LIBRARIES ${LIBNSL} ${LIBSOCKET}) 
CHECK_C_SOURCE_RUNS(
"
 #include <sys/types.h>
 #include <sys/socket.h>
 #include <sys/time.h>
 
 int main()
 {    
   int fd = socket(AF_INET, SOCK_STREAM, 0);
   struct timeval tv;
   int ret= 0;
   tv.tv_sec= 2;
   tv.tv_usec= 0;
   ret|= setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
   ret|= setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
   return !!ret;
 }
" HAVE_SOCKET_TIMEOUT)
ENDIF()

SET(NO_ALARM "${HAVE_SOCKET_TIMEOUT}" CACHE BOOL 
   "No need to use alarm to implement socket timeout")
MARK_AS_ADVANCED(NO_ALARM)

IF(CMAKE_SYSTEM_NAME STREQUAL "AIX" OR CMAKE_SYSTEM_NAME STREQUAL "OS400")
  # xlC oddity - it complains about same inline function defined multiple times
  # in different compilation units
  INCLUDE(CheckCXXCompilerFlag)
  CHECK_CXX_COMPILER_FLAG("-qstaticinline" HAVE_QSTATICINLINE)
  IF(HAVE_QSTATICINLINE)
    SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -qstaticinline")
  ENDIF()

  # The following is required to export all symbols 
  # (also with leading underscore)
  STRING(REPLACE  "-bexpall" "-bexpfull" CMAKE_SHARED_LIBRARY_LINK_CXX_FLAGS
          ${CMAKE_SHARED_LIBRARY_LINK_CXX_FLAGS})
  STRING(REPLACE  "-bexpall" "-bexpfull" CMAKE_SHARED_LIBRARY_LINK_C_FLAGS
          ${CMAKE_SHARED_LIBRARY_LINK_C_FLAGS})
ENDIF()

IF(CMAKE_COMPILER_IS_GNUCXX)
IF(WITH_ATOMIC_OPS STREQUAL "up")
  SET(MY_ATOMIC_MODE_DUMMY 1 CACHE BOOL "Assume single-CPU mode, no concurrency")
ELSEIF(WITH_ATOMIC_OPS STREQUAL "rwlocks")
  SET(MY_ATOMIC_MODE_RWLOCK 1 CACHE BOOL "Use pthread rwlocks for atomic ops")
ELSEIF(WITH_ATOMIC_OPS STREQUAL "smp")
ELSEIF(NOT WITH_ATOMIC_OPS)
  CHECK_CXX_SOURCE_COMPILES("
  int main()
  {
    int foo= -10; int bar= 10;
    long long int foo64= -10; long long int bar64= 10;
    if (!__sync_fetch_and_add(&foo, bar) || foo)
      return -1;
    bar= __sync_lock_test_and_set(&foo, bar);
    if (bar || foo != 10)
      return -1;
    bar= __sync_val_compare_and_swap(&bar, foo, 15);
    if (bar)
      return -1;
    if (!__sync_fetch_and_add(&foo64, bar64) || foo64)
      return -1;
    bar64= __sync_lock_test_and_set(&foo64, bar64);
    if (bar64 || foo64 != 10)
      return -1;
    bar64= __sync_val_compare_and_swap(&bar64, foo, 15);
    if (bar64)
      return -1;
    return 0;
  }"
  HAVE_GCC_ATOMIC_BUILTINS)
ELSE()
  MESSAGE(FATAL_ERROR "${WITH_ATOMIC_OPS} is not a valid value for WITH_ATOMIC_OPS!")
ENDIF()
ENDIF()

SET(WITH_ATOMIC_LOCKS "${WITH_ATOMIC_LOCKS}" CACHE STRING
"Implement atomic operations using pthread rwlocks or atomic CPU
instructions for multi-processor or uniprocessor
configuration. By default gcc built-in sync functions are used,
if available and 'smp' configuration otherwise.")
MARK_AS_ADVANCED(WITH_ATOMIC_LOCKS MY_ATOMIC_MODE_RWLOCK MY_ATOMIC_MODE_DUMMY)

IF(CMAKE_SYSTEM_NAME STREQUAL "SunOS")
 CHECK_C_SOURCE_RUNS(
 "
 #include  <atomic.h>
  int main()
  {
    int foo = -10; int bar = 10;
    int64_t foo64 = -10; int64_t bar64 = 10;
    if (atomic_add_int_nv((uint_t *)&foo, bar) || foo)
      return -1;
    bar = atomic_swap_uint((uint_t *)&foo, (uint_t)bar);
    if (bar || foo != 10)
     return -1;
    bar = atomic_cas_uint((uint_t *)&bar, (uint_t)foo, 15);
    if (bar)
      return -1;
    if (atomic_add_64_nv((volatile uint64_t *)&foo64, bar64) || foo64)
      return -1;
    bar64 = atomic_swap_64((volatile uint64_t *)&foo64, (uint64_t)bar64);
    if (bar64 || foo64 != 10)
      return -1;
    bar64 = atomic_cas_64((volatile uint64_t *)&bar64, (uint_t)foo64, 15);
    if (bar64)
      return -1;
    atomic_or_64((volatile uint64_t *)&bar64, 0);
    return 0;
  }
"  HAVE_SOLARIS_ATOMIC)
ENDIF()

#--------------------------------------------------------------------
# Check for IPv6 support
#--------------------------------------------------------------------
CHECK_INCLUDE_FILE(netinet/in6.h HAVE_NETINET_IN6_H)

IF(UNIX)
  SET(CMAKE_EXTRA_INCLUDE_FILES sys/types.h netinet/in.h sys/socket.h)
  IF(HAVE_NETINET_IN6_H)
    SET(CMAKE_EXTRA_INCLUDE_FILES ${CMAKE_EXTRA_INCLUDE_FILES} netinet/in6.h)
  ENDIF()
ELSEIF(WIN32)
  SET(CMAKE_EXTRA_INCLUDE_FILES ${CMAKE_EXTRA_INCLUDE_FILES} winsock2.h ws2ipdef.h)
ENDIF()

CHECK_TYPE_SIZE("struct sockaddr_in6" SIZEOF_SOCKADDR_IN6)
CHECK_TYPE_SIZE("struct in6_addr" SIZEOF_IN6_ADDR)
IF(SIZEOF_SOCKADDR_IN6)
  SET(HAVE_STRUCT_SOCKADDR_IN6 1)
ENDIF()
IF(SIZEOF_IN6_ADDR)
  SET(HAVE_STRUCT_IN6_ADDR 1)
ENDIF()

IF(HAVE_STRUCT_SOCKADDR_IN6 OR HAVE_STRUCT_IN6_ADDR)
  SET(HAVE_IPV6 TRUE CACHE INTERNAL "")
ENDIF()


# Check for sockaddr_storage.ss_family
# It is called differently under OS400 and older AIX

CHECK_STRUCT_HAS_MEMBER("struct sockaddr_storage"
 ss_family "${CMAKE_EXTRA_INCLUDE_FILES}" HAVE_SOCKADDR_STORAGE_SS_FAMILY)
IF(NOT HAVE_SOCKADDR_STORAGE_SS_FAMILY)
  CHECK_STRUCT_HAS_MEMBER("struct sockaddr_storage"
  __ss_family "${CMAKE_EXTRA_INCLUDE_FILES}" HAVE_SOCKADDR_STORAGE___SS_FAMILY)
  IF(HAVE_SOCKADDR_STORAGE___SS_FAMILY)
    SET(ss_family __ss_family)
  ENDIF()
ENDIF()
SET(CMAKE_EXTRA_INCLUDE_FILES) 

CHECK_STRUCT_HAS_MEMBER("struct dirent" d_ino "dirent.h"  STRUCT_DIRENT_HAS_D_INO)
CHECK_STRUCT_HAS_MEMBER("struct dirent" d_namlen "dirent.h"  STRUCT_DIRENT_HAS_D_NAMLEN)
SET(SPRINTF_RETURNS_INT 1)

