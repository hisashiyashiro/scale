#! /bin/bash -x

export HMDIR=~/GCMresults/sol/latest/output
export BIN=~/Dropbox/Inbox/scale3/bin/MacOSX-ifort
export EXE=init_coldbubble

export OUTDIR=${HMDIR}/${EXE}

# Run Command
export MPIRUN="/usr/local/mpich213/bin/mpiexec -np 4 -f /Users/yashiro/libs/mpilib/machines_local"

mkdir -p $OUTDIR
cd $OUTDIR

########################################################################
cat << End_of_SYSIN > ${OUTDIR}/${EXE}.cnf

#####
#
# Scale3 init_coldbubble configulation
#
#####

&PARAM_TIME
 TIME_STARTDATE             =  2000, 1, 1, 0, 0, 0,
 TIME_STARTMS               =  0.D0,
/









&PARAM_PRC
 PRC_NUM_X = 2,
 PRC_NUM_Y = 2,
 PRC_PERIODIC_X  = .true.,
 PRC_PERIODIC_Y  = .true.,
/

&PARAM_GRID
 GRID_IMAX = 100,
 GRID_JMAX = 100,
 GRID_KMAX = 40,
 GRID_DX   = 200.D0,
 GRID_DY   = 200.D0,
 GRID_DZ   = 200.D0,
/

&PARAM_ATMOS
 ATMOS_TYPE_DYN    = 'fent_fct',
 ATMOS_TYPE_PHY_TB = 'smagorinsky',
 ATMOS_TYPE_PHY_MP = 'NDW6',
 ATMOS_TYPE_PHY_RD = 'mstrnX',
/

&PARAM_ATMOS_VARS
 ATMOS_QTRC_NMAX = 11,
 ATMOS_RESTART_OUT_BASENAME = "${EXE}",
/

&PARAM_MKEXP_COLDBUBBLE
 XC_BBL = 20.0D3,
 YC_BBL = 20.0D3,
 ZC_BBL = 4.0D3,
 XR_BBL = 1.0D3,
 YR_BBL = 1.0D3,
 ZR_BBL = 2.0D3,
/

End_of_SYSIN
########################################################################

# run
echo "job ${RUNNAME} started at " `date`
$MPIRUN $BIN/$EXE ${EXE}.cnf > STDOUT 2>&1
echo "job ${RUNNAME} end     at " `date`

exit