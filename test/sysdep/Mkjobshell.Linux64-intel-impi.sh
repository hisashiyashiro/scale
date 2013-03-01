#! /bin/bash -x

# Arguments
BINDIR=${1}
INITNAME=${2}
BINNAME=${3}
INITCONF=${4}
RUNCONF=${5}
TPROC=${6}

# System specific
MPIEXEC="mpirun -np ${TPROC}"

# Generate run.sh

cat << EOF1 > ./run.sh
#! /bin/bash -x
################################################################################
#
# ------ FOR Linux64 & intel C&fortran & intel mpi -----
#
################################################################################
export OMP_NUM_THREADS=1
export FORT_FMT_RECL=400


ln -sv ${BINDIR}/${INITNAME} .
ln -sv ${BINDIR}/${BINNAME}  .

# run
${MPIEXEC} ${INITNAME} ${INITCONF} || exit
${MPIEXEC} ${BINNAME}  ${RUNCONF}  || exit

################################################################################
EOF1