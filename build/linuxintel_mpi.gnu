#-----------------------------------------------------------------------
#
# File:  sgialtix_mpi.gnu
#
#  Contains compiler and loader options for the SGI Altix using the 
#  intel compiler and specifies the mpi directory for communications 
#  modules.
#
#-----------------------------------------------------------------------
F77 = ifort
F90 = ifort
LD = ifort
CC = cc
Cp = /bin/cp
Cpp = cpp -P
AWK = /usr/bin/awk
ABI = 
COMMDIR = mpi
 
#  Enable MPI library for parallel code, yes/no.

MPI = yes

# Adjust these to point to where netcdf is installed

# These have been loaded as a module so no values necessary
#NETCDFINC = -I/netcdf_include_path
#NETCDFLIB = -L/netcdf_library_path
#NETCDFINC = -I/usr/projects/climate/maltrud/local/include_coyote
#NETCDFLIB = -L/usr/projects/climate/maltrud/local/lib_coyote
NETCDFINC = -I/scratch2/bzhao/netcdf-3.6.1/include
NETCDFLIB = -L/scratch2/bzhao/netcdf-3.6.1/lib

#  Enable trapping and traceback of floating point exceptions, yes/no.
#  Note - Requires 'setenv TRAP_FPE "ALL=ABORT,TRACE"' for traceback.

TRAP_FPE = no

#------------------------------------------------------------------
#  precompiler options
#------------------------------------------------------------------

#DCOUPL              = -Dcoupled

Cpp_opts =   \
      $(DCOUPL)

Cpp_opts := $(Cpp_opts) -DPOSIX 
 
#----------------------------------------------------------------------------
#
#                           C Flags
#
#----------------------------------------------------------------------------
 
CFLAGS = $(ABI) 

ifeq ($(OPTIMIZE),yes)
  CFLAGS := $(CFLAGS) -O 
else
  CFLAGS := $(CFLAGS) -g -check all -ftrapuv
endif
 
#----------------------------------------------------------------------------
#
#                           FORTRAN Flags
#
#----------------------------------------------------------------------------

FBASE = $(ABI) $(NETCDFINC) $(MPI_COMPILE_FLAGS) -I$(DepDir) 
MODSUF = mod

ifeq ($(TRAP_FPE),yes)
  FBASE := $(FBASE) 
endif

ifeq ($(OPTIMIZE),yes)
  FFLAGS = $(FBASE) -O3
else
  FFLAGS = $(FBASE) -g -check bounds
endif
 
#----------------------------------------------------------------------------
#
#                           Loader Flags and Libraries
#
#----------------------------------------------------------------------------
 
LDFLAGS = $(ABI) 
 
LIBS = $(NETCDFLIB) -lnetcdf
 
ifeq ($(MPI),yes)
  LIBS := $(LIBS) $(MPI_LD_FLAGS) -lmpi 
endif

ifeq ($(TRAP_FPE),yes)
  LIBS := $(LIBS) 
endif
 
LDLIBS = $(LIBS)
 
#----------------------------------------------------------------------------
