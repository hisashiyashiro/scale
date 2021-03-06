program netcdf2grads_h
  !-----------------------------------------------------------------------------------------
  !> post-process for scale high-performance (under the nickname of POPSCA)
  !!
  !! @par Description
  !!      convert from netcdf to grads format (with combine and slice)
  !!
  !! @author Team SCALE
  !!
  !! @par History
  !! @li  2015-02-03 (R.Yoshida)  original
  !<
  !-----------------------------------------------------------------------------------------

  use mod_net2g_vars
  use mod_net2g_error
  use mod_net2g_calender
#ifdef MPIUSE
  use mod_net2g_comm
#endif
  use mod_net2g_io
  use mod_net2g_netcdf
  use mod_net2g_setup
  use mod_net2g_anal

  implicit none

  !++ included parameters
#include "inc_net2g.h"
  !-----------------------------------------------------------------------------------------

  !--- variables for work
  real(SP),allocatable :: zlev(:), cz(:), cdz(:)
  real(SP),allocatable :: cx(:), cdx(:)
  real(SP),allocatable :: cy(:), cdy(:)
  real(SP),allocatable :: lcz(:), ucz(:), ocz(:)
  real(SP),allocatable :: lon(:,:), lat(:,:)
  real(SP),allocatable :: var_2d(:,:)
  real(SP),allocatable :: p_var(:,:)
  real(SP),allocatable :: p_ref(:,:,:)

  real(SP),allocatable :: recvbuf(:,:)
  real(SP),allocatable :: cx_gather(:)
  real(SP),allocatable :: cy_gather(:)
  real(SP),allocatable :: cdx_gather(:)
  real(SP),allocatable :: cdy_gather(:)

  real(SP),allocatable :: p_cx(:), p_cdx(:)     ! partial grid data
  real(SP),allocatable :: p_cy(:), p_cdy(:)     ! partial grid data
  real(SP),allocatable :: p_lon(:,:), p_lat(:,:)

  real(SP),allocatable :: vgrid(:)


  integer :: vtype = -1
  integer :: atype = -1
  integer :: ctype = -1
  integer :: nt
  integer :: nx   ! num of x-dimension in the combined file
  integer :: ny   ! num of y-dimension in the combined file
  integer :: nz   ! num of z-dimension in the combined file
  integer :: uz   ! num of z-dimension in the combined file for urban
  integer :: lz   ! num of z-dimension in the combined file for land
  integer :: oz   ! num of z-dimension in the combined file for ocean
  integer :: nzg  ! num of z-dimension in the combined file for grid
  integer :: nxh  ! num of halo grids for x-dimension
  integer :: nyh  ! num of halo grids for y-dimension
  integer :: nzh  ! num of halo grids for z-dimension
  integer :: nz_all(4)
  integer :: ks, ke
  integer :: nst, nen

  integer :: xproc, yproc, tproc
  integer :: it, ix, jy, iz, iv
  integer :: zz
  integer :: ndim
  integer :: idom
  integer :: ierr
  logical :: lstat

#ifndef MPIUSE
  integer :: irank = 0
  integer :: isize = 1
#endif

  integer :: nxp   ! num of x-dimension in partial file
  integer :: nyp   ! num of y-dimension in partial file
  integer :: nxgp  ! num of x-dimension in partial file for grid
  integer :: nygp  ! num of y-dimension in partial file for grid
  integer :: mnxp  ! maximum num of x-grid in partial file among all files
  integer :: mnyp  ! maximum num of y-grid in partial file among all files
  integer :: nxg_tproc
  integer :: nyg_tproc
  integer :: mnx   ! maximum num of x-dimension in partial file among all files
  integer :: mny   ! maximum num of y-dimension in partial file among all files

  integer :: nm
  integer :: nmnge  ! number of managing files
  integer :: work
  integer :: yy, mm, dd, hh, mn, sc
  integer,allocatable :: rk_mnge(:)

  integer :: irec_time
  integer :: irec_timelev

  character(6)    :: num
  character(CLNG) :: ncfile
  character(CMID) :: varname
  character(CLNG) :: long_name
  character(CMID) :: unit
  character(CMID) :: fconf
  character(CLNG) :: fname_save

  !----------------------------------------------------------------------------------------
  ! Below variables are not required for net2g
  logical             :: PRC_PERIODIC_X                         = .true.    !< periodic condition or not (X)?
  logical             :: PRC_PERIODIC_Y                         = .true.    !< periodic condition or not (Y)?
  logical             :: PRC_CART_REORDER                       = .false.   !< flag for rank reordering over the cartesian map

  real(DP)            :: MAPPROJECTION_basepoint_x                          !> position of base point in the model [m]
  real(DP)            :: MAPPROJECTION_basepoint_y                          !> position of base point in the model [m]
  real(DP)            :: MAPPROJECTION_rotation                 = 0.0_DP    !> rotation factor (only for 'NONE' type)
  real(DP)            :: MAPPROJECTION_PS_lat                               !> standard latitude1 for P.S. projection [deg]
  real(DP)            :: MAPPROJECTION_M_lat                    = 0.0_DP    !> standard latitude1 for Mer. projection [deg]
  real(DP)            :: MAPPROJECTION_EC_lat                   = 0.0_DP    !> standard latitude1 for E.C. projection [deg]

  character(len=CMID) :: FILE_HISTORY_TITLE                     = ""        !> Header information of the output file: title
  character(len=CMID) :: FILE_HISTORY_SOURCE                    = ""        !> Header information of the output file: model name
  character(len=CMID) :: FILE_HISTORY_INSTITUTION               = ""        !> Header information of the output file: institution
  character(len=CMID) :: FILE_HISTORY_TIME_UNITS                = "seconds" !> Unit for time axis
  logical             :: FILE_HISTORY_DEFAULT_POSTFIX_TIMELABEL = .false.   !> Add timelabel to the basename?
  character(len=CSHT) :: FILE_HISTORY_DEFAULT_ZCOORD            = ""        !> Default z-coordinate
  logical             :: FILE_HISTORY_DEFAULT_TAVERAGE          = .false.   !> Apply time average?
  character(len=CSHT) :: FILE_HISTORY_DEFAULT_DATATYPE          = "REAL4"   !> Data type
  logical             :: FILE_HISTORY_OUTPUT_STEP0              = .false.   !> Output value at step=0?
  real(DP)            :: FILE_HISTORY_OUTPUT_WAIT               = 0.0_DP    !> Time length to suppress output
  character(len=CSHT) :: FILE_HISTORY_OUTPUT_WAIT_TUNIT         = "SEC"     !> Time unit
  real(DP)            :: FILE_HISTORY_OUTPUT_SWITCH_TINTERVAL   = -1.0_DP   !> Time interval to switch output file
  character(len=CSHT) :: FILE_HISTORY_OUTPUT_SWITCH_TUNIT       = "SEC"     !> Time unit
  logical             :: FILE_HISTORY_ERROR_PUTMISS             = .true.    !> Abort if the value is never stored after last output?
  logical             :: FILE_HISTORY_AGGREGATE                 = .false.   !> Switch to use aggregate file I/O
  character(len=CMID) :: FILE_HISTORY_options                   = ""        !> option to give file.  'filetype1:key1=val1&filetype2:key2=val2&...'
  logical             :: debug                                  = .false.

  integer             :: FILE_HISTORY_CARTESC_PRES_nlayer       = 0
  real(DP)            :: FILE_HISTORY_CARTESC_PRES(300)         = 0.0_DP    !> pressure level to output [hPa]
  !-----------------------------------------------------------------------------------------

  namelist /LOGOUT/            &
    LOG_BASENAME,              &
    LOG_ALL_OUTPUT,            &
    LOG_LEVEL
  namelist /INFO/              &
    TIME_STARTDATE,            &
    START_TSTEP,               &
    END_TSTEP,                 &
    INC_TSTEP,                 &
    DOMAIN_NUM,                &
    ZCOUNT,                    &
    ZSTART,                    &
    CONFFILE,                  &
    IDIR,                      &
    ODIR,                      &
    Z_LEV_TYPE,                &
    Z_MERGE_OUT,               &
    T_MERGE_OUT,               &
    MAPPROJ_ctl
  namelist /EXTRA/             &
    EXTRA_TINTERVAL,           &
    EXTRA_TUNIT
  namelist /ANAL/              &
    ANALYSIS
  namelist /VARI/              &
    VNAME,                     &
    TARGET_ZLEV

  ! read from run.conf
  !namelist  /PARAM_TIME/       &
  !  TIME_STARTDATE

  namelist  /PARAM_PRC_CARTESC/        &
    PRC_NUM_X,                 &
    PRC_NUM_Y,                 &
    PRC_PERIODIC_X,            & ! not required
    PRC_PERIODIC_Y,            & ! not required
    PRC_CART_REORDER             ! not required

  namelist / PARAM_MAPPROJECTION / &
     MAPPROJECTION_basepoint_lon, &
     MAPPROJECTION_basepoint_lat, &
     MAPPROJECTION_basepoint_x,   & ! not required
     MAPPROJECTION_basepoint_y,   & ! not required
     MAPPROJECTION_type,          &
     MAPPROJECTION_rotation,      & ! not required
     MAPPROJECTION_LC_lat1,       &
     MAPPROJECTION_LC_lat2,       &
     MAPPROJECTION_PS_lat,        & ! not required
     MAPPROJECTION_M_lat,         & ! not required
     MAPPROJECTION_EC_lat           ! not required

  namelist / PARAM_FILE_HISTORY / &
     FILE_HISTORY_TITLE,                     & ! not required
     FILE_HISTORY_SOURCE,                    & ! not required
     FILE_HISTORY_INSTITUTION,               & ! not required
     FILE_HISTORY_TIME_UNITS,                & ! not required
     FILE_HISTORY_DEFAULT_BASENAME,          &
     FILE_HISTORY_DEFAULT_POSTFIX_TIMELABEL, & ! not required
     FILE_HISTORY_DEFAULT_ZCOORD,            & ! not required
     FILE_HISTORY_DEFAULT_TINTERVAL,         &
     FILE_HISTORY_DEFAULT_TUNIT,             &
     FILE_HISTORY_DEFAULT_TAVERAGE,          & ! not required
     FILE_HISTORY_DEFAULT_DATATYPE,          & ! not required
     FILE_HISTORY_OUTPUT_STEP0,              & ! not required
     FILE_HISTORY_OUTPUT_WAIT,               & ! not required
     FILE_HISTORY_OUTPUT_WAIT_TUNIT,         & ! not required
     FILE_HISTORY_OUTPUT_SWITCH_TINTERVAL,   & ! not required
     FILE_HISTORY_OUTPUT_SWITCH_TUNIT,       & ! not required
     FILE_HISTORY_ERROR_PUTMISS,             & ! not required
     FILE_HISTORY_AGGREGATE,                 & ! not required
     FILE_HISTORY_OPTIONS,                   & ! not required
     debug,                                  & ! not required
     FILE_HISTORY_DEFAULT_ZDIM                 ! added?

  namelist / PARAM_FILE_HISTORY_CARTESC / &
     FILE_HISTORY_CARTESC_PRES_nlayer, & ! not required
     FILE_HISTORY_CARTESC_PRES,        & ! not required
     FILE_HISTORY_CARTESC_BOUNDARY
  !-----------------------------------------------------------------------------------------

  !### initialization
  !-----------------------------------------------------------------------------------------
#ifdef MPIUSE
  call comm_initialize
#endif

  !--- Read from argument
  if ( COMMAND_ARGUMENT_COUNT() /= 1 ) then
     write(*, *) "ERROR: Program needs a config file!"
     call err_abort( 1, __LINE__, loc_main )
  else
     call get_command_argument(1,fconf)
  endif

  call read_conf_logout
  call io_log_init( irank, LOUT )

  if ( LOUT ) write( FID_LOG, '(1X,A)') "-----------------------------------"
  if ( LOUT ) write( FID_LOG, '(1X,A)') "     START : netcdf to grads"
  if ( LOUT ) write( FID_LOG, '(1X,A)') "-----------------------------------"
  if ( LOUT ) write( FID_LOG, '(1X,"isize:",I6,2X,"irank:",I6)') isize, irank
  call read_conf

  idom  = DOMAIN_NUM
  xproc = PRC_NUM_X
  yproc = PRC_NUM_Y
  tproc = xproc * yproc
  nmnge = tproc / isize
  work = mod( tproc, isize )
  if ( work /= 0 ) then
     write (*, *) "ERROR: specified num of mpi processes is not adequate."
     write (*, *) "*** specify the num; PRC_X*PRC_Y shuold be divisable by the num."
     call err_abort( 1, __LINE__, loc_main )
  elseif ( isize > tproc ) then
     write (*, *) "ERROR: num of mpi processes is larger than that of the scale-rm run."
     call err_abort( 1, __LINE__, loc_main )
  endif

  allocate ( rk_mnge (nmnge) )
  call set_rank_manage( irank, nmnge, rk_mnge )

  !### read and combine
  !-----------------------------------------------------------------------------------------
  write ( num,'(I6.6)' ) rk_mnge(1)
  ncfile = trim(IDIR)//"/"//trim(FILE_HISTORY_DEFAULT_BASENAME)//".pe"//num//".nc"
  call netcdf_retrieve_dims( ncfile,                          &
                             nxp, nxgp, nxh, nyp, nygp, nyh,  &
                             nz,  nzg,  nzh, uz, lz, oz, ks, ke   )
  nz_all(1) = nz
  nz_all(2) = uz
  nz_all(3) = lz
  nz_all(4) = oz

  call set_array_size( nxp, nyp, nxgp, nygp, nx, ny, mnx, mny,  &
                       mnxp, mnyp, nxg_tproc, nyg_tproc         )
  call allocation( irank ) ! "irank" is right, not "rk_mnge"
#ifdef MPIUSE
  call comm_setup( mnxp, mnyp, nxgp, nygp, nmnge )
#endif
  ! allocation
  call netcdf_setup( mnxp, mnyp, nz_all )

  call set_atype( atype )
  call set_ctype( ctype )
  if ( atype == a_conv ) then ! allocation
     call anal_setup( mnxp, mnyp, nz_all, nmnge )
     if ( ctype == c_height ) then !--- get reference height
        do nm = 1, nmnge
           it = START_TSTEP
           call netcdf_read_ref( rk_mnge(nm), nxp, nyp, mnxp, mnyp, &
                                 it, nz_all, ctype, p_ref )
           call anal_input_ref( p_ref, nm )
        enddo
     endif
  endif
  do nm = 1, nmnge
     call netcdf_read_grid( rk_mnge(nm), nm, nxgp, nygp,             &
                            zlev, cz, cdz, p_cx, p_cdx, p_cy, p_cdy  )
  enddo

#ifdef MPIUSE
  call comm_gather_grid( nxgp, nygp, nmnge, p_cx, p_cdx, p_cy, p_cdy, &
                         cx_gather, cdx_gather, cy_gather, cdy_gather )

  if ( irank == master ) call combine_grid( cx_gather, cdx_gather, cy_gather, cdy_gather )
#else
  call combine_grid( p_cx, p_cdx, p_cy, p_cdy )
#endif

  if ( Z_MERGE_OUT ) call make_vgrid


  !---read lon,lat data
  zz = 1
  do nm = 1, nmnge
     varname = 'lon'
     call netcdf_read_var( rk_mnge(nm), nm, nxp, nyp, mnxp, mnyp,   &
          it, zz, nz_all, varname, a_slice, -1, vt_tpmsk, long_name, unit, p_lon )
     varname = 'lat'
     call netcdf_read_var( rk_mnge(nm), nm, nxp, nyp, mnxp, mnyp,   &
          it, zz, nz_all, varname, a_slice, -1, vt_tpmsk, long_name, unit, p_lat )
  enddo

#ifdef MPIUSE
  call comm_gather_vars( mnxp, mnyp, nmnge, p_lon, recvbuf )
#endif
  if ( irank == master ) then
#ifdef MPIUSE
     call combine_vars_2d( recvbuf, lon)
#else
     call combine_vars_2d( p_lon, lon )
#endif
  endif

#ifdef MPIUSE
  call comm_gather_vars( mnxp, mnyp, nmnge, p_lat, recvbuf )
#endif
  if ( irank == master ) then
#ifdef MPIUSE
     call combine_vars_2d( recvbuf, lat)
#else
     call combine_vars_2d( p_lat, lat)
#endif
  endif

  !--- read data and combine
  nst = START_TSTEP
  nen = END_TSTEP
  if ( .not. T_MERGE_OUT )then ! nt is used for TDEF in ctl file
     nt = 1
  else
     nt  = (nen - nst + 1) / INC_TSTEP
  endif

  !if ( nt > max_tcount ) then
  !   write (*, *) "ERROR: overflow maximum of tcount"
  !   call err_abort( 1, __LINE__, loc_main )
  !endif

  call cal_init( yy, mm, dd, hh, mn, sc, DELT )

  irec_time = 1
  do it = nst, nen, INC_TSTEP !--- time loop
     if( .not. T_MERGE_OUT ) irec_time = 1

     call set_calender( yy, mm, dd, hh, mn, sc, STIME, FTIME )
     if ( LOUT ) write( FID_LOG, '(1X,A)' ) ""
     if ( LOUT ) write( FID_LOG, '(1X,A,I3)' ) "+++ TIME STEP:   ", it
     if ( LOUT ) write( FID_LOG, * ) "+++ Date: ", STIME

     if ( ctype == c_pres ) then !--- update reference pressure
        do nm = 1, nmnge
           call netcdf_read_ref( rk_mnge(nm), nxp, nyp, mnxp, mnyp, &
                                 it, nz_all, ctype, p_ref )
           call anal_input_ref( p_ref, nm )
        enddo
     endif

     do iv = 1, vcount !--- var loop
        varname = trim( VNAME(iv) )
        call netcdf_var_dim( ncfile, varname, ndim )
        call set_vtype( ndim, varname, vtype, atype )
        if ( LOUT ) write( FID_LOG, '(1X,A)' ) "|"
        if ( LOUT ) write( FID_LOG, '(1X,A,A,A,I1,A)' ) &
        "+++ VARIABLE: ", trim(varname), " (vtype = ", vtype, ")"

        select case( vtype )
        case ( vt_urban, vt_land, vt_ocean, vt_height, vt_3d )
        !-----------------------------------------------------------------------------------

           ! read axis
           if((it == nst).and.(irank == master))then
              select case( vtype )
              case ( vt_urban )
                 if(uz < 0)then
                    write (*,*) "ERROR: Not found urban layer axis: uz"
                    call err_abort( 1, __LINE__, loc_main )
                 endif
                 call netcdf_read_grid_sfc( master, 'UCZ', ucz )
              case ( vt_land )
                 if(lz < 0)then
                    write (*,*) "ERROR: Not found land layer axis: lz"
                    call err_abort( 1, __LINE__, loc_main )
                 endif
                 call netcdf_read_grid_sfc( master, 'LCZ', lcz )
              case ( vt_ocean )
                 if(oz < 0)then
                    write (*,*) "ERROR: Not found land layer axis: oz"
                    call err_abort( 1, __LINE__, loc_main )
                 endif
                 call netcdf_read_grid_sfc( master, 'OCZ', ocz )
              end select
           endif

           irec_timelev = irec_time
           do iz = 1, ZCOUNT        !--- level loop
              if ( atype == a_slice ) then
                 zz = int(TARGET_ZLEV(iz))
                 if ( LOUT ) write( FID_LOG, '(1X,A,I6)' ) "+++ Z LEVEL: ", zz
                 call check_targ_zlev( zz )
              elseif ( atype == a_conv ) then
                 zz = int(TARGET_ZLEV(iz))
                 if ( ctype == c_pres ) then
                    if ( LOUT ) write( FID_LOG, '(1X,A,I6,A)' ) "+++ Z LEVEL: ", zz, " [hPa]"
                 elseif ( ctype == c_height ) then
                    if ( LOUT ) write( FID_LOG, '(1X,A,I6,A)' ) "+++ Z LEVEL: ", zz, " [m]"
                 endif
              endif

              do nm = 1, nmnge
                 call netcdf_read_var( rk_mnge(nm), nm, nxp, nyp, mnxp, mnyp,  &
                                       it, zz, nz_all, varname, atype, ctype, vtype, long_name, unit, p_var )
              enddo

#ifdef MPIUSE
              call comm_gather_vars( mnxp, mnyp, nmnge, p_var, recvbuf )
#endif

              if ( irank == master ) then
#ifdef MPIUSE
                 call combine_vars_2d( recvbuf, var_2d )
#else
                 call combine_vars_2d( p_var, var_2d )
#endif
                 !if ( iz /= 1 .and. Z_MERGE_OUT ) then
                    call io_write_vars( var_2d, varname, atype, vtype, &
                                        idom, nx, ny, zz, irec_timelev )
                 !else
                 !   call io_write_vars( var_2d, varname, atype, vtype, &
                 !                       idom, nx, ny, zz, irec_timelev )
                 !endif
              endif

              irec_timelev = irec_timelev + 1
           enddo !--- level loop

        case ( vt_2d, vt_tpmsk )
        !-----------------------------------------------------------------------------------

           zz = 1
           do nm = 1, nmnge
              call netcdf_read_var( rk_mnge(nm), nm, nxp, nyp, mnxp, mnyp,   &
                                    it, zz, nz_all, varname, atype, ctype, vtype, long_name, unit, p_var )
           enddo

#ifdef MPIUSE
           call comm_gather_vars( mnxp, mnyp, nmnge, p_var, recvbuf )
#endif

           !zz = 0 ! used as file name
           if ( irank == master ) then
#ifdef MPIUSE
              call combine_vars_2d( recvbuf, var_2d )
#else
              call combine_vars_2d( p_var, var_2d )
#endif
              call io_write_vars( var_2d, varname, atype, vtype, &
                                  idom, nx, ny, zz, irec_time )
           endif

        case default
        !-----------------------------------------------------------------------------------
           call err_abort( 0, __LINE__, loc_main )
        end select

        if ( irank == master ) then  ! make ctl file

           if( ( T_MERGE_OUT .and. (irec_time == 1) ).or.( .not. T_MERGE_OUT ) )then

              if ( .not. Z_MERGE_OUT ) then
                 do iz = 1, ZCOUNT                 !--- level loop
                    if ( atype == a_slice ) then
                       zz = int(TARGET_ZLEV(iz))
                    elseif ( atype == a_conv ) then
                       zz = int(TARGET_ZLEV(iz))
                    endif
                    call io_create_ctl( varname, atype, ctype, vtype, idom, &
                         nx, ny, zz, nt, cx, cy, vgrid, zlev,               &
                         lz, uz, oz, lcz, ucz, ocz, long_name, unit )
                    if ( MAPPROJ_ctl )then
                       call io_create_ctl_mproj( varname, atype, ctype, vtype, idom, &
                            nx, ny, zz, nt, cx, cy, vgrid, zlev,                     &
                            lz, uz, oz, lcz, ucz, ocz, minval(lon), minval(lat), long_name, unit )
                    endif
                 enddo
              else
                 call io_create_ctl( varname, atype, ctype, vtype, idom, &
                      nx, ny, 1, nt, cx, cy, vgrid, zlev,                &
                      lz, uz, oz, lcz, ucz, ocz, long_name, unit )
                 if ( MAPPROJ_ctl )then
                    call io_create_ctl_mproj( varname, atype, ctype, vtype, idom, &
                         nx, ny, 1, nt, cx, cy, vgrid, zlev,                      &
                         lz, uz, oz, lcz, ucz, ocz, minval(lon), minval(lat), long_name, unit )
                 endif
              endif

           endif
        endif

     enddo !--- var loop

     call cal_increment( yy, mm, dd, hh, mn, sc )
    if ( ZCOUNT == 0 ) then
       write (*, *) "ERROR: at record increment"
       call err_abort( 0, __LINE__, loc_main )
    endif
     irec_time = irec_time + ZCOUNT
  enddo !--- time loop

  ! finalization
  if ( LOUT ) write( FID_LOG, '(1X,A)') ""
  if ( LOUT ) write( FID_LOG, '(1X,A)') "     FINISH : netcdf to grads"
  if ( LOUT ) write( FID_LOG, '(1X,A)') "-----------------------------------"
  call io_close_all

#ifdef MPIUSE
  call comm_finalize
#endif

  !-----------------------------------------------------------------------------------------
  !> END MAIN ROUTINE
  !-----------------------------------------------------------------------------------------
contains

  !-----------------------------------------------------------------------------------------
  !> Individual Procedures
  !-----------------------------------------------------------------------------------------

  !> combine region divided data: grid data
  !-----------------------------------------------------------------------------------------
  subroutine combine_grid( &
      cx_gather,   & ! [in]
      cdx_gather,  & ! [in]
      cy_gather,   & ! [in]
      cdy_gather   ) ! [in]
    implicit none

    real(SP), intent(in) :: cx_gather (:)
    real(SP), intent(in) :: cdx_gather(:)
    real(SP), intent(in) :: cy_gather (:)
    real(SP), intent(in) :: cdy_gather(:)

    integer :: ix, jy, iix, jjy
    integer :: is, ie, js, je
    integer :: gix, gjy
    integer :: gis, gie, gjs, gje
    !---------------------------------------------------------------------------

    jy = 1
    do ix = 1, xproc
       call set_index( ix, jy, nxp, nyp, is, ie, js, je )
       call set_index_grid( ix, jy, nxgp, nygp, gis, gie, gjs, gje )

       gix = gis
       do iix = is, ie
          cdx(iix) = cdx_gather(gix+nxh)
          cx(iix)  = cx_gather( gix+nxh)
          gix = gix + 1
       enddo
    enddo

    ix = 1
    do jy = 1, yproc
       call set_index( ix, jy, nxp, nyp, is, ie, js, je )
       call set_index_grid( ix, jy, nxgp, nygp, gis, gie, gjs, gje )

       gjy = gjs
       do jjy = js, je
          cdy(jjy) = cdy_gather(gjy+nyh)
          cy(jjy)  = cy_gather( gjy+nyh)
          gjy = gjy + 1
       enddo
    enddo

    return
  end subroutine combine_grid

  !> combine region divided data: [2D]
  !-----------------------------------------------------------------------------------------
  subroutine combine_vars_2d( &
      gathered,   & ! [in ]
      combined    ) ! [out]
    implicit none

    real(SP), intent(in)  :: gathered(:,:)
    real(SP), intent(out) :: combined(:,:)

    integer :: ix, jy, iix, jjy, gix, gjy
    integer :: is, ie, js, je
    integer :: gis, gie, gjs, gje
    !---------------------------------------------------------------------------

    do jy = 1, yproc
    do ix = 1, xproc
       call set_index( ix, jy, nxp, nyp, is, ie, js, je )
       call set_index_gathered( ix, jy, mnxp, mnyp, gis, gie, gjs, gje )

       gjy = gjs
       do jjy = js, je
          gix = gis
          do iix = is, ie
             combined(iix,jjy) = gathered( gix, gjy )
             gix = gix + 1
          enddo
          gjy = gjy + 1
       enddo
    enddo
    enddo

    return
  end subroutine combine_vars_2d


  !> read configulation namelists
  !-----------------------------------------------------------------------------------------
  subroutine read_conf_logout()
    implicit none
    !---------------------------------------------------------------------------

    inquire (file=trim(fconf), exist=lstat)
    if ( .not. lstat ) then
       write (*, *) "ERROR: Not found the configuration file :", trim(fconf)
       call err_abort( 1, __LINE__, loc_main )
    endif

    open ( FID_CONF, file=trim(fconf), status='old', &
           form="formatted", delim='apostrophe', iostat=ierr )
    if ( ierr /= 0 ) then
       write (*, *) "ERROR: Fail to open the configuration file :", trim(fconf)
       call err_abort( 1, __LINE__, loc_main )
    endif

    read  ( FID_CONF, nml=LOGOUT, iostat=ierr )

    close ( FID_CONF )
    return
  end subroutine read_conf_logout


  !> read configulation namelists
  !-----------------------------------------------------------------------------------------
  subroutine read_conf()
    implicit none

    integer :: n, m, iz
    !---------------------------------------------------------------------------

    !--- read namelist file
    inquire (file=trim(fconf), exist=lstat)
    if ( .not. lstat ) then
       write (*, *) "ERROR: Not found the configuration file :", trim(fconf)
       call err_abort( 1, __LINE__, loc_main )
    endif

    open ( FID_CONF, file=trim(fconf), status='old', &
           form="formatted", delim='apostrophe', iostat=ierr )
    if ( ierr /= 0 ) then
       write (*, *) "ERROR: Fail to open the configuration file :", trim(fconf)
       call err_abort( 1, __LINE__, loc_main )
    endif

    read  ( FID_CONF, nml=INFO, iostat=ierr )
    if ( LOUT .and. LOG_DBUG ) write ( FID_LOG, nml=INFO )

    if ( ZCOUNT > max_zcount ) then
       write (*, *) "ERROR: overflow maximum of zcount"
       call err_abort( 1, __LINE__, loc_main )
    endif

    rewind( FID_CONF )
    read  ( FID_CONF, nml=EXTRA, iostat=ierr )
    if ( LOUT .and. LOG_DBUG ) write ( FID_LOG, nml=EXTRA )

    rewind( FID_CONF )
    read  ( FID_CONF, nml=ANAL, iostat=ierr )
    if ( LOUT .and. LOG_DBUG ) write ( FID_LOG, nml=ANAL )

    rewind( FID_CONF )
    read  ( FID_CONF, nml=VARI, iostat=ierr )
    if ( LOUT .and. LOG_DBUG ) write ( FID_LOG, nml=VARI )
    if ( LOUT .and. LOG_DBUG ) write( FID_LOG,* ) ""

    VCOUNT = 0
    do n=1, max_vcount
       if ( trim(VNAME(n)).eq."" ) exit
       VCOUNT = VCOUNT + 1
    enddo
    if ( VCOUNT >= max_vcount ) then
       write (*, *) "ERROR: overflow maximum of vcount"
       call err_abort( 1, __LINE__, loc_main )
    elseif( VCOUNT < 1 ) then
       if ( LOUT ) write( FID_LOG, '(1X,A)' ) "+++ Use Default set of VNAME"
       VCOUNT = num_std_vname
       do n=1, VCOUNT
          VNAME(n) = trim(std_vname(n))
       enddo
    endif

    do n=1, VCOUNT
       VNAME(n) = trim(VNAME(n))
       if ( LOUT ) write( FID_LOG, '(1X,A,I3,A,A)' ) "+++ Listing Vars: (", n, ") ", VNAME(n)
    enddo
    if ( LOUT ) write( FID_LOG,* ) ""

    if ( int(TARGET_ZLEV(1)) >= 0 ) then
       if ( ZCOUNT == 0 ) then
          ZCOUNT = 0
          do n=1, max_zcount
             if ( int(TARGET_ZLEV(n)) < 0 ) exit
             ZCOUNT = ZCOUNT + 1
          enddo
       endif

       Z_LEV_LIST = .true.
       select case( trim(Z_LEV_TYPE) )
       case ( "ZLEV", "zlev" )
          do n=1, ZCOUNT
             iz = int(TARGET_ZLEV(n))
             if ( LOUT ) write( FID_LOG, '(1X,A,I3,A,I5,A)' ) "+++ Listing Levs: (", n, ") ",iz," [m]"
          enddo
       case ( "PLEV", "plev" )
          do n=1, ZCOUNT
             iz = int(TARGET_ZLEV(n))
             if ( LOUT ) write( FID_LOG, '(1X,A,I3,A,I5,A)' ) "+++ Listing Levs: (", n, ") ",iz," [hPa]"
          enddo
       case ( "original" ) ! If Z_LEV_TYPE = original, then TARGET_ZLEV is ignored.
          Z_LEV_LIST = .false.
          m = ZSTART
          do n=1, ZCOUNT
             TARGET_ZLEV(n) = real(m)
             iz = int(TARGET_ZLEV(n))
             if ( LOUT ) write( FID_LOG, '(1X,A,I3,A,I5,A)' ) "+++ Listing Levs: (", n, ") ",iz," [grid]"
             m = m + 1
          enddo
       case default
          do n=1, ZCOUNT
             iz = int(TARGET_ZLEV(n))
             if ( LOUT ) write( FID_LOG, '(1X,A,I3,A,I5,A)' ) "+++ Listing Levs: (", n, ") ",iz," [grid]"
          enddo
       end select
    else
       select case( trim(Z_LEV_TYPE) )
       case ( "ZLEV", "zlev" )
          Z_LEV_LIST = .true.
          if ( LOUT ) write( FID_LOG, '(1X,A)' ) "+++ Use Default set of HEGIHT LEVELs"
          ZCOUNT = num_std_zlev
          do n=1, ZCOUNT
             TARGET_ZLEV(n) = real(std_zlev(n))
             iz = int(TARGET_ZLEV(n))
             if ( LOUT ) write( FID_LOG, '(1X,A,I3,A,I5,A)' ) "+++ Listing Levs: (", n, ") ",iz," [m]"
          enddo
       case ( "PLEV", "plev" )
          Z_LEV_LIST = .true.
          if ( LOUT ) write( FID_LOG, '(1X,A)' ) "+++ Use Default set of PRESSURE LEVELs"
          ZCOUNT = num_std_plev
          do n=1, ZCOUNT
             TARGET_ZLEV(n) = real(std_plev(n))
             iz = int(TARGET_ZLEV(n))
             if ( LOUT ) write( FID_LOG, '(1X,A,I3,A,I5,A)' ) "+++ Listing Levs: (", n, ") ",iz," [hPa]"
          enddo
       case default
          if ( ZCOUNT == 0 ) then
             write (*, *) "ERROR: plz, specify ZCOUNT or TARGET_ZLEV."
             call err_abort( 1, __LINE__, loc_main )
          endif
          Z_LEV_LIST = .false.
          m = ZSTART
          do n=1, ZCOUNT
             TARGET_ZLEV(n) = real(m)
             iz = int(TARGET_ZLEV(n))
             if ( LOUT ) write( FID_LOG, '(1X,A,I3,A,I5,A)' ) "+++ Listing Levs: (", n, ") ",iz," [grid]"
             m = m + 1
          enddo
       end select
    endif
    if ( LOUT ) write( FID_LOG,* ) ""

    !rewind( FID_CONF )
    !read  ( FID_CONF, nml=GRADS, iostat=ierr )
    !if ( LOUT .and. LOG_DBUG ) write ( FID_LOG, nml=GRADS )

    close ( FID_CONF )


    !--- read run.conf file
    inquire (file=trim(CONFFILE), exist=lstat)
    if ( .not. lstat ) then
       write (*, *) "ERROR: Not found the configuration file :", trim(CONFFILE)
       call err_abort( 1, __LINE__, loc_main )
    endif

    open ( FID_RCNF, file=trim(CONFFILE), status='old', &
           form="formatted", delim='apostrophe', iostat=ierr )
    if ( ierr /= 0 ) then
       write (*, *) "ERROR: Fail to open the configuration file :", trim(CONFFILE)
       call err_abort( 1, __LINE__, loc_main )
    endif

    !read  ( FID_RCNF, nml=PARAM_TIME, iostat=ierr )
    !if ( LOUT .and. LOG_DBUG ) write ( FID_LOG, nml=PARAM_TIME )

    rewind( FID_RCNF )
    read  ( FID_RCNF, nml=PARAM_PRC_CARTESC, iostat=ierr )
    if ( LOUT .and. LOG_DBUG ) write ( FID_LOG, nml=PARAM_PRC_CARTESC )

    rewind( FID_RCNF )
    read  ( FID_RCNF, nml=PARAM_FILE_HISTORY_CARTESC, iostat=ierr )
    if ( LOUT .and. LOG_DBUG ) write ( FID_LOG, nml=PARAM_FILE_HISTORY_CARTESC )

    rewind( FID_RCNF )
    read  ( FID_RCNF, nml=PARAM_FILE_HISTORY, iostat=ierr )
    if ( LOUT .and. LOG_DBUG ) write ( FID_LOG, nml=PARAM_FILE_HISTORY )

    if ( MAPPROJ_ctl )then
       rewind( FID_RCNF )
       read  ( FID_RCNF, nml=PARAM_MAPPROJECTION, iostat=ierr )
       if ( LOUT .and. LOG_DBUG ) write ( FID_LOG, nml=PARAM_MAPPROJECTION )
    endif

    close(FID_RCNF)

    if ( EXTRA_TINTERVAL > 0 ) then
       FILE_HISTORY_DEFAULT_TINTERVAL = EXTRA_TINTERVAL
       FILE_HISTORY_DEFAULT_TUNIT     = EXTRA_TUNIT
       if ( LOUT ) write( FID_LOG, '(1X,A,F5.1,A)' ) "+++ USE EXTRA TIME: ", &
                        FILE_HISTORY_DEFAULT_TINTERVAL, trim(FILE_HISTORY_DEFAULT_TUNIT)
    endif

    !--- tentative
    if ( FILE_HISTORY_CARTESC_BOUNDARY ) then
       if ( LOUT ) write (*, *) "FILE_HISTORY_CARTESC_BOUNDARY is currently unsupported"
       call err_abort( 1, __LINE__, loc_main )
    endif

    return
  end subroutine read_conf


  !> check of zlev compatibility
  !-----------------------------------------------------------------------------------------
  subroutine check_targ_zlev( &
      zz   ) ! [in]
    implicit none

    integer, intent(in)  :: zz
    !---------------------------------------------------------------------------

    select case( vtype )
    case ( vt_urban )
       if ( zz < 1 .or. zz > uz ) then
          write (*, *) "ERROR: requested level is in K-HALO [urban]"
          write (*, *) "*** requested level =",zz,", min = 1, max = ",uz
          call err_abort( 1, __LINE__, loc_main )
       endif
    case ( vt_land )
       if ( zz < 1 .or. zz > lz ) then
          write (*, *) "ERROR: requested level is in K-HALO [land]"
          write (*, *) "*** requested level =",zz,", min = 1, max = ",lz
          call err_abort( 1, __LINE__, loc_main )
       endif
    case ( vt_ocean )
       if ( zz < 1 .or. zz > oz ) then
          write (*, *) "ERROR: requested level is in K-HALO [ocean]"
          write (*, *) "*** requested level =",zz,", min = 1, max = ",oz
          call err_abort( 1, __LINE__, loc_main )
       endif
    case ( vt_height )
       if ( zz < ks .or. zz > ke ) then
           write (*, *) "ERROR: requested level is in K-HALO [height]"
          write (*, *) "*** requested level =",zz,", min = ",ks," max = ",ke
          call err_abort( 1, __LINE__, loc_main )
       endif
    case ( vt_3d )
       if ( zz < ks .or. zz > ke ) then
          write (*, *) "ERROR: requested level is in K-HALO [3D data]"
          write (*, *) "*** requested level =",zz,", min = ",ks," max = ",ke
          call err_abort( 1, __LINE__, loc_main )
       endif
    case ( vt_2d, vt_tpmsk )
       if ( zz /= 1 ) then
          write (*, *) "ERROR: requested level is not exist [2D data]"
          call err_abort( 1, __LINE__, loc_main )
       endif
    case default
        call err_abort( 0, __LINE__, loc_main )
    end select

    return
  end subroutine check_targ_zlev

  !> make vgrid for merged-z output
  !-----------------------------------------------------------------------------------------
  subroutine make_vgrid()
    implicit none

    integer :: iz, ik, k
    real(DP) :: diff, mini
    !---------------------------------------------------------------------------

    allocate( vgrid( ZCOUNT ) )

    if ( atype == a_conv ) then
       do iz = 1, ZCOUNT
          vgrid(iz) = int(TARGET_ZLEV(iz))
          if ( LOUT ) write( FID_LOG, '(1X,A,I3,A,F8.2)' ) "+++ Target Height: (", iz, ") ", vgrid(iz)
       enddo

    else
       do iz = 1, ZCOUNT
          vgrid(iz) = zlev( int(TARGET_ZLEV(iz)) )
          if ( LOUT ) write( FID_LOG, '(1X,A,I3,A,F8.2,A,I3)' ) &
                      "+++ Target Height: (", iz, ") ", vgrid(iz), " - req. lev = ", int(TARGET_ZLEV(iz))
       enddo

    endif
    if ( LOUT ) write( FID_LOG, '(1X,A)' ) ""

    return
  end subroutine make_vgrid


  !> allocation of data arrays
  !---------------------------------------------------------------------------
  subroutine allocation( &
      irank   ) ! [in]
    implicit none

    integer, intent(in) :: irank
    !---------------------------------------------------------------------------

    allocate( p_var       (mnxp,       mnyp*nmnge     ) )
    allocate( p_ref       (mnxp,       mnyp,       nz ) )
    allocate( p_cdx       (nxgp*nmnge                 ) )
    allocate( p_cdy       (nygp*nmnge                 ) )
    allocate( p_cx        (nxgp*nmnge                 ) )
    allocate( p_cy        (nygp*nmnge                 ) )
    allocate( cdz         (nz+2*nzh                   ) )
    allocate( cz          (nz+2*nzh                   ) )
    allocate( zlev        (nz                         ) )

    allocate( p_lon       (mnxp, mnyp*nmnge           ) )
    allocate( p_lat       (mnxp, mnyp*nmnge           ) )

    if ( irank == master ) then
       if (lz > 0) allocate( lcz       (lz     ) )
       if (uz > 0) allocate( ucz       (uz     ) )
       if (oz > 0) allocate( ocz       (oz     ) )
       allocate( var_2d    (nx, ny ) )
       allocate( cx        (nx     ) )
       allocate( cy        (ny     ) )
       allocate( cdx       (nx     ) )
       allocate( cdy       (ny     ) )
       allocate( lon       (nx, ny ) )
       allocate( lat       (nx, ny ) )
    endif

#ifdef MPIUSE
    if ( irank == master ) then
       allocate( recvbuf   (mnxp,             mnyp*nmnge*tproc ) )
       allocate( cx_gather (nxgp*nmnge*tproc                   ) )
       allocate( cy_gather (nygp*nmnge*tproc                   ) )
       allocate( cdx_gather(nxgp*nmnge*tproc                   ) )
       allocate( cdy_gather(nygp*nmnge*tproc                   ) )
    else
       allocate( recvbuf   (1,                1                ) )
       allocate( cx_gather (1                                  ) )
       allocate( cy_gather (1                                  ) )
       allocate( cdx_gather(1                                  ) )
       allocate( cdy_gather(1                                  ) )
    endif
#endif

    return
  end subroutine allocation

end program netcdf2grads_h
