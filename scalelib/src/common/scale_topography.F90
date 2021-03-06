!-------------------------------------------------------------------------------
!> module TOPOGRAPHY
!!
!! @par Description
!!          Topography module
!!
!! @author Team SCALE
!<
!-------------------------------------------------------------------------------
#include "scalelib.h"
module scale_topography
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use scale_precision
  use scale_io
  use scale_prof
  use scale_atmos_grid_cartesC_index
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: TOPO_setup
  public :: TOPO_fillhalo
  public :: TOPO_write

  !-----------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !
  logical, public :: TOPO_exist = .false. !< topography exists?

  real(RP), public, allocatable :: TOPO_Zsfc(:,:) !< absolute ground height [m]

  !-----------------------------------------------------------------------------
  !
  !++ Private procedure
  !
  private :: TOPO_read

  !-----------------------------------------------------------------------------
  !
  !++ Private parameters & variables
  !
  character(len=H_LONG),  private :: TOPO_IN_BASENAME  = ''                     !< basename of the input  file
  logical,                private :: TOPO_IN_AGGREGATE                          !> switch to use aggregated file
  logical,                private :: TOPO_IN_CHECK_COORDINATES = .false.        !> switch for check of coordinates
  character(len=H_LONG),  private :: TOPO_OUT_BASENAME = ''                     !< basename of the output file
  logical,                private :: TOPO_OUT_AGGREGATE                         !> switch to use aggregated file
  character(len=H_MID),   private :: TOPO_OUT_TITLE    = 'SCALE-RM TOPOGRAPHY'  !< title    of the output file
  character(len=H_SHORT), private :: TOPO_OUT_DTYPE    = 'DEFAULT'              !< REAL4 or REAL8

  !-----------------------------------------------------------------------------
contains
  !-----------------------------------------------------------------------------
  !> Setup
  subroutine TOPO_setup
    use scale_file, only: &
       FILE_AGGREGATE
    use scale_prc, only: &
       PRC_abort
    implicit none

    namelist / PARAM_TOPO / &
       TOPO_IN_BASENAME,          &
       TOPO_IN_AGGREGATE,         &
       TOPO_IN_CHECK_COORDINATES, &
       TOPO_OUT_BASENAME,         &
       TOPO_OUT_AGGREGATE,        &
       TOPO_OUT_DTYPE

    integer :: ierr
    !---------------------------------------------------------------------------

    LOG_NEWLINE
    LOG_INFO("TOPO_setup",*) 'Setup'

    TOPO_IN_AGGREGATE  = FILE_AGGREGATE
    TOPO_OUT_AGGREGATE = FILE_AGGREGATE

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_TOPO,iostat=ierr)
    if( ierr < 0 ) then !--- missing
       LOG_INFO("TOPO_setup",*) 'Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       LOG_ERROR("TOPO_setup",*) 'Not appropriate names in namelist PARAM_TOPO. Check!'
       call PRC_abort
    endif
    LOG_NML(PARAM_TOPO)

    allocate( TOPO_Zsfc(IA,JA) )
    TOPO_Zsfc(:,:) = 0.0_RP

    ! read from file
    call TOPO_read

    return
  end subroutine TOPO_setup

  !-----------------------------------------------------------------------------
  !> HALO Communication
  subroutine TOPO_fillhalo( Zsfc, FILL_BND )
    use scale_comm_cartesC, only: &
       COMM_vars8, &
       COMM_wait
    implicit none

    real(RP), intent(inout), optional :: Zsfc(IA,JA)
    logical,  intent(in),    optional :: FILL_BND

    logical :: FILL_BND_
    !---------------------------------------------------------------------------

    FILL_BND_ = .false.
    if ( present(FILL_BND) ) FILL_BND_ = FILL_BND

    if ( present(Zsfc) ) then
       call COMM_vars8( Zsfc(:,:), 1 )
       call COMM_wait ( Zsfc(:,:), 1, FILL_BND_ )
    else
       call COMM_vars8( TOPO_Zsfc(:,:), 1 )
       call COMM_wait ( TOPO_Zsfc(:,:), 1, FILL_BND_ )
    end if

    return
  end subroutine TOPO_fillhalo

  !-----------------------------------------------------------------------------
  !> Read topography
  subroutine TOPO_read
    use scale_file_cartesC, only: &
       FILE_CARTESC_open, &
       FILE_CARTESC_read, &
       FILE_CARTESC_flush, &
       FILE_CARTESC_check_coordinates, &
       FILE_CARTESC_close
    use scale_prc, only: &
       PRC_abort
    implicit none

    integer :: fid
    !---------------------------------------------------------------------------

    LOG_NEWLINE
    LOG_INFO("TOPO_read",*) 'Input topography file '

    if ( TOPO_IN_BASENAME /= '' ) then

       call FILE_CARTESC_open( TOPO_IN_BASENAME, fid, aggregate=TOPO_IN_AGGREGATE )
       call FILE_CARTESC_read( fid, 'TOPO', 'XY', TOPO_Zsfc(:,:) )

       call FILE_CARTESC_flush( fid )

       if ( TOPO_IN_CHECK_COORDINATES ) then
          call FILE_CARTESC_check_coordinates( fid )
       end if

       call FILE_CARTESC_close( fid )

       call TOPO_fillhalo( FILL_BND=.false. )

       TOPO_exist = .true.

    else
       LOG_INFO_CONT(*) 'topography file is not specified.'

       TOPO_exist = .false.
    endif

    return
  end subroutine TOPO_read

  !-----------------------------------------------------------------------------
  !> Write topography
  subroutine TOPO_write
    use scale_file_cartesC, only: &
       FILE_CARTESC_write
    implicit none
    !---------------------------------------------------------------------------

    if ( TOPO_OUT_BASENAME /= '' ) then

       LOG_NEWLINE
       LOG_INFO("TOPO_write",*) 'Output topography file '

       call TOPO_fillhalo( FILL_BND=.false. )

       call FILE_CARTESC_write( TOPO_Zsfc(:,:), TOPO_OUT_BASENAME, TOPO_OUT_TITLE, & ! [IN]
                                'TOPO', 'Topography', 'm', 'XY',   TOPO_OUT_DTYPE, & ! [IN]
                                standard_name="surface_altitude",                  & ! [IN]
                                haszcoord=.false., aggregate=TOPO_OUT_AGGREGATE    ) ! [IN]

    endif

    return
  end subroutine TOPO_write

end module scale_topography
