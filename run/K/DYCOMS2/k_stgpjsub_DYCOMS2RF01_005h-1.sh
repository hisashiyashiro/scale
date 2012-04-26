#! /bin/bash -x
#
# for K computer
#
#PJM --rsc-list "rscgrp=large"
#PJM --rsc-list "node=96x96"
#PJM --rsc-list "elapse=00:55:00"
#PJM --rsc-list "node-mem=10Gi"
#PJM --stg-transfiles all
#PJM --mpi "use-rankdir"
#PJM --stgin  "rank=* /data1/user0117/scale3/run/K/DYCOMS2/scale3_test_DYCOMS2RF01_005h-1.cnf %r:./"
#PJM --stgin  "rank=* /data1/user0117/scale3/bin/K/DYCOMS2RF01_005m438x8x8_ndw6_              %r:./"
#PJM --stgin  "rank=* /data1/user0117/scale3/output/DYCOMS2RF01_005h438x8x8_ndw6_96x96-0/init_DYCOMS2RF01_63072000000.000.pe%06r %r:./"
#PJM --stgout "rank=* %r:./* /data1/user0117/scale3/output/DYCOMS2RF01_005h438x8x8_ndw6_96x96-1/"
#PJM -s
#
. /work/system/Env_base
#
export PARALLEL=8
export OMP_NUM_THREADS=${PARALLEL}
export LPG="lpgparm -s 32MB -d 32MB -h 32MB -t 32MB -p 32MB"
export fprof=""

outdir=/data1/user0117/scale3/output/DYCOMS2RF01_005h438x8x8_ndw6_96x96-1
mkdir -p ${outdir}

# run
mpiexec ${LPG} ./DYCOMS2RF01_005m438x8x8_ndw6_ ./scale3_test_DYCOMS2RF01_005h-1.cnf
