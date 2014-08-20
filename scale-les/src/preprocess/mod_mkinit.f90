!-------------------------------------------------------------------------------
!> module INITIAL
!!
!! @par Description
!!          subroutines for preparing initial data
!!
!! @author Team SCALE
!!
!! @par History
!! @li      2011-11-11 (H.Yashiro)  [new] Imported from SCALE-LES ver.2
!! @li      2012-01-31 (Y.Miyamoto) [add] Lamb wave test
!! @li      2012-01-31 (Y.Miyamoto) [add] KH wave test
!! @li      2012-01-31 (Y.Miyamoto) [add] turbulence test
!! @li      2011-02-01 (H.Yashiro)  [add] supercell test, follow the supercell test of WRF
!! @li      2012-02-06 (Y.Miyamoto) [add] advection test
!! @li      2012-02-16 (Y.Miyamoto) [mod] added hydrostatic balance calculation
!! @li      2012-03-27 (H.Yashiro)  [mod] change subroutines into one module
!! @li      2012-04-04 (Y.Miyamoto) [new] SQUALLINE test, for GCSS model comparison (Redelsperger et al. 2000)
!! @li      2012-04-06 (H.Yashiro)  [new] uniform state test
!! @li      2012-04-08 (H.Yashiro)  [mod] merge all init programs
!! @li      2012-06-13 (Y.Sato)     [mod] add hbinw option (***HBINW)
!! @li      2013-02-25 (H.Yashiro)  [mod] ISA profile
!! @li      2014-03-27 (A.Noda)     [mod] add DYCOMS2_RF02_DNS
!! @li      2014-04-28 (R.Yoshida)  [add] real case experiment
!!
!<
!-------------------------------------------------------------------------------
module mod_mkinit
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use scale_precision
  use scale_stdio
  use scale_prof
  use scale_grid_index
  use scale_tracer

  use scale_process, only: &
     PRC_MPIstop
  use scale_const, only: &
     PI    => CONST_PI,    &
     GRAV  => CONST_GRAV,  &
     Pstd  => CONST_Pstd,  &
     Rdry  => CONST_Rdry,  &
     CPdry => CONST_CPdry, &
     RovCP => CONST_RovCP, &
     LH0   => CONST_LH0,   &
     P00   => CONST_PRE00, &
     I_SW  => CONST_I_SW,  &
     I_LW  => CONST_I_LW
  use scale_random, only: &
     RANDOM_get
  use scale_comm, only: &
     COMM_vars8, &
     COMM_wait
  use scale_grid, only: &
     GRID_CZ,  &
     GRID_CX,  &
     GRID_CY,  &
     GRID_FZ,  &
     GRID_FX,  &
     GRID_FY,  &
     GRID_CXG
  use scale_grid_real, only: &
     REAL_CZ, &
     REAL_FZ
  use scale_atmos_profile, only: &
     PROFILE_isa => ATMOS_PROFILE_isa
  use scale_atmos_hydrostatic, only: &
     HYDROSTATIC_buildrho        => ATMOS_HYDROSTATIC_buildrho,       &
     HYDROSTATIC_buildrho_atmos  => ATMOS_HYDROSTATIC_buildrho_atmos, &
     HYDROSTATIC_buildrho_bytemp => ATMOS_HYDROSTATIC_buildrho_bytemp
  use scale_atmos_saturation, only: &
     SATURATION_pres2qsat_all => ATMOS_SATURATION_pres2qsat_all

  use mod_atmos_vars, only: &
     DENS, &
     MOMX, &
     MOMY, &
     MOMZ, &
     RHOT, &
     QTRC
  use mod_atmos_phy_mp_vars, only: &
     SFLX_rain    => ATMOS_PHY_MP_SFLX_rain, &
     SFLX_snow    => ATMOS_PHY_MP_SFLX_snow
  use mod_atmos_phy_rd_vars, only: &
     SFLX_LW_up   => ATMOS_PHY_RD_SFLX_LW_up,   &
     SFLX_LW_dn   => ATMOS_PHY_RD_SFLX_LW_dn,   &
     SFLX_SW_up   => ATMOS_PHY_RD_SFLX_SW_up,   &
     SFLX_SW_dn   => ATMOS_PHY_RD_SFLX_SW_dn,   &
     TOAFLX_LW_up => ATMOS_PHY_RD_TOAFLX_LW_up, &
     TOAFLX_LW_dn => ATMOS_PHY_RD_TOAFLX_LW_dn, &
     TOAFLX_SW_up => ATMOS_PHY_RD_TOAFLX_SW_up, &
     TOAFLX_SW_dn => ATMOS_PHY_RD_TOAFLX_SW_dn
  use mod_realinput
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: MKINIT_setup
  public :: MKINIT

  !-----------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !
  integer, public            :: MKINIT_TYPE     = -1
  integer, public, parameter :: I_IGNORE        =  0

  integer, public, parameter :: I_PLANESTATE    =  1
  integer, public, parameter :: I_TRACERBUBBLE  =  2
  integer, public, parameter :: I_COLDBUBBLE    =  3

  integer, public, parameter :: I_LAMBWAVE      =  4
  integer, public, parameter :: I_GRAVITYWAVE   =  5
  integer, public, parameter :: I_KHWAVE        =  6
  integer, public, parameter :: I_TURBULENCE    =  7
  integer, public, parameter :: I_MOUNTAINWAVE  =  8

  integer, public, parameter :: I_WARMBUBBLE    =  9
  integer, public, parameter :: I_SUPERCELL     = 10
  integer, public, parameter :: I_SQUALLLINE    = 11
  integer, public, parameter :: I_WK1982        = 12
  integer, public, parameter :: I_DYCOMS2_RF01  = 13
  integer, public, parameter :: I_DYCOMS2_RF02  = 14
  integer, public, parameter :: I_RICO          = 15

  integer, public, parameter :: I_INTERPORATION = 16

  integer, public, parameter :: I_LANDCOUPLE    = 17
  integer, public, parameter :: I_OCEANCOUPLE   = 18
  integer, public, parameter :: I_URBANCOUPLE   = 19
  integer, public, parameter :: I_TRIPLECOUPLE  = 20
  integer, public, parameter :: I_BUBBLECOUPLE  = 21

  integer, public, parameter :: I_SEABREEZE     = 22
  integer, public, parameter :: I_HEATISLAND    = 23

  integer, public, parameter :: I_DYCOMS2_RF02_DNS = 24

  integer, public, parameter :: I_REAL          = 25

  !-----------------------------------------------------------------------------
  !
  !++ Private procedure
  !
  private :: BUBBLE_setup
  private :: SBMAERO_setup

  private :: MKINIT_planestate
  private :: MKINIT_tracerbubble
  private :: MKINIT_coldbubble
  private :: MKINIT_lambwave
  private :: MKINIT_gravitywave
  private :: MKINIT_khwave
  private :: MKINIT_turbulence
  private :: MKINIT_mountainwave

  private :: MKINIT_warmbubble
  private :: MKINIT_supercell
  private :: MKINIT_squallline
  private :: MKINIT_wk1982
  private :: MKINIT_DYCOMS2_RF01
  private :: MKINIT_DYCOMS2_RF02
  private :: MKINIT_RICO

  private :: MKINIT_interporation

  private :: MKINIT_landcouple
  private :: MKINIT_oceancouple
  private :: MKINIT_urbancouple
  private :: MKINIT_seabreeze
  private :: MKINIT_heatisland

  private :: MKINIT_DYCOMS2_RF02_DNS

  private :: MKINIT_real

  !-----------------------------------------------------------------------------
  !
  !++ Private parameters & variables
  !
  real(RP), private, parameter :: THETAstd = 300.0_RP ! [K]

  real(RP), private, allocatable :: pres(:,:,:) ! pressure [Pa]
  real(RP), private, allocatable :: temp(:,:,:) ! temperature [K]
  real(RP), private, allocatable :: pott(:,:,:) ! potential temperature [K]
  real(RP), private, allocatable :: qsat(:,:,:) ! satulated water vapor [kg/kg]
  real(RP), private, allocatable :: qv  (:,:,:) ! water vapor [kg/kg]
  real(RP), private, allocatable :: qc  (:,:,:) ! cloud water [kg/kg]
  real(RP), private, allocatable :: velx(:,:,:) ! velocity u [m/s]
  real(RP), private, allocatable :: vely(:,:,:) ! velocity v [m/s]

  real(RP), private, allocatable :: pres_sfc(:,:,:)
  real(RP), private, allocatable :: temp_sfc(:,:,:)
  real(RP), private, allocatable :: pott_sfc(:,:,:)
  real(RP), private, allocatable :: qsat_sfc(:,:,:)
  real(RP), private, allocatable :: qv_sfc  (:,:,:)
  real(RP), private, allocatable :: qc_sfc  (:,:,:)

  real(RP), private, allocatable :: rndm  (:,:,:) ! random number (0-1)
  real(RP), private, allocatable :: bubble(:,:,:) ! bubble factor (0-1)

  real(RP), private, allocatable :: gan(:) ! gamma factor (0-1)
  logical,  private :: flg_bin = .false.

  !-----------------------------------------------------------------------------
contains
  !-----------------------------------------------------------------------------
  !> Setup
  subroutine MKINIT_setup
    implicit none

    character(len=H_SHORT) :: MKINIT_initname = 'NONE'

    NAMELIST / PARAM_MKINIT / &
       MKINIT_initname, &
       flg_bin

    integer :: ierr
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[MKINIT]/Categ[MKINIT]'

    allocate( pres(KA,IA,JA) )
    allocate( temp(KA,IA,JA) )
    allocate( pott(KA,IA,JA) )
    allocate( qsat(KA,IA,JA) )
    allocate( qv  (KA,IA,JA) )
    allocate( qc  (KA,IA,JA) )
    allocate( velx(KA,IA,JA) )
    allocate( vely(KA,IA,JA) )

    allocate( pres_sfc(1,IA,JA) )
    allocate( temp_sfc(1,IA,JA) )
    allocate( pott_sfc(1,IA,JA) )
    allocate( qsat_sfc(1,IA,JA) )
    allocate( qv_sfc  (1,IA,JA) )
    allocate( qc_sfc  (1,IA,JA) )

    allocate( rndm  (KA,IA,JA) )
    allocate( bubble(KA,IA,JA) )


    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) 'xxx Not found namelist. Check!'
       call PRC_MPIstop
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT)

    select case(trim(MKINIT_initname))
    case('NONE')
       MKINIT_TYPE = I_IGNORE
    case('PLANESTATE')
       MKINIT_TYPE = I_PLANESTATE
    case('TRACERBUBBLE')
       MKINIT_TYPE = I_TRACERBUBBLE
       call BUBBLE_setup
    case('COLDBUBBLE')
       MKINIT_TYPE = I_COLDBUBBLE
       call BUBBLE_setup
    case('LAMBWAVE')
       MKINIT_TYPE = I_LAMBWAVE
       call BUBBLE_setup
    case('GRAVITYWAVE')
       MKINIT_TYPE = I_GRAVITYWAVE
       call BUBBLE_setup
    case('KHWAVE')
       MKINIT_TYPE = I_KHWAVE
    case('TURBULENCE')
       MKINIT_TYPE = I_TURBULENCE
    case('MOUNTAINWAVE')
       MKINIT_TYPE = I_MOUNTAINWAVE
    case('WARMBUBBLE')
       MKINIT_TYPE = I_WARMBUBBLE
       call BUBBLE_setup
    case('SUPERCELL')
       MKINIT_TYPE = I_SUPERCELL
       call BUBBLE_setup
    case('SQUALLLINE')
       MKINIT_TYPE = I_SQUALLLINE
    case('WK1982')
       MKINIT_TYPE = I_WK1982
       call BUBBLE_setup
    case('DYCOMS2_RF01')
       MKINIT_TYPE = I_DYCOMS2_RF01
    case('DYCOMS2_RF02')
       MKINIT_TYPE = I_DYCOMS2_RF02
    case('RICO')
       MKINIT_TYPE = I_RICO
    case('INTERPORATION')
       MKINIT_TYPE = I_INTERPORATION
    case('LANDCOUPLE')
       MKINIT_TYPE = I_LANDCOUPLE
    case('OCEANCOUPLE')
       MKINIT_TYPE = I_OCEANCOUPLE
    case('URBANCOUPLE')
       MKINIT_TYPE = I_URBANCOUPLE
    case('TRIPLECOUPLE')
       MKINIT_TYPE = I_TRIPLECOUPLE
    case('BUBBLECOUPLE')
       MKINIT_TYPE = I_BUBBLECOUPLE
       call BUBBLE_setup
    case('SEABREEZE')
       MKINIT_TYPE = I_SEABREEZE
    case('HEATISLAND')
       MKINIT_TYPE = I_HEATISLAND
    case('DYCOMS2_RF02_DNS')
       MKINIT_TYPE = I_DYCOMS2_RF02_DNS
    case('REAL')
       MKINIT_TYPE = I_REAL
    case default
       write(*,*) ' xxx Unsupported TYPE:', trim(MKINIT_initname)
       call PRC_MPIstop
    endselect

    return
  end subroutine MKINIT_setup

  !-----------------------------------------------------------------------------
  !> Driver
  subroutine MKINIT
    use scale_const, only: &
       CONST_UNDEF8
    use scale_landuse, only: &
       LANDUSE_write
    use mod_atmos_vars, only: &
       ATMOS_sw_restart => ATMOS_RESTART_OUTPUT, &
       ATMOS_vars_restart_write
    use mod_ocean_vars, only: &
       OCEAN_sw_restart => OCEAN_RESTART_OUTPUT, &
       OCEAN_vars_restart_write
    use mod_land_vars, only: &
       LAND_sw_restart => LAND_RESTART_OUTPUT, &
       LAND_vars_restart_write
    use mod_urban_vars, only: &
       URBAN_sw_restart => URBAN_RESTART_OUTPUT, &
       URBAN_vars_restart_write
    implicit none

    integer :: iq
    !---------------------------------------------------------------------------

    if ( MKINIT_TYPE == I_IGNORE ) then
      if( IO_L ) write(IO_FID_LOG,*)
      if( IO_L ) write(IO_FID_LOG,*) '++++++ SKIP  MAKING INITIAL DATA ++++++'
    else
      if( IO_L ) write(IO_FID_LOG,*)
      if( IO_L ) write(IO_FID_LOG,*) '++++++ START MAKING INITIAL DATA ++++++'

      !--- Initialize variables
      do iq = 2, QA
         QTRC(:,:,:,iq) = 0.0_RP
      enddo

      pres(:,:,:) = CONST_UNDEF8
      temp(:,:,:) = CONST_UNDEF8
      pott(:,:,:) = CONST_UNDEF8
      qsat(:,:,:) = CONST_UNDEF8
      qv  (:,:,:) = CONST_UNDEF8
      qc  (:,:,:) = CONST_UNDEF8
      velx(:,:,:) = CONST_UNDEF8
      vely(:,:,:) = CONST_UNDEF8

      rndm  (:,:,:) = CONST_UNDEF8

      pres_sfc(:,:,:) = CONST_UNDEF8
      temp_sfc(:,:,:) = CONST_UNDEF8
      pott_sfc(:,:,:) = CONST_UNDEF8
      qsat_sfc(:,:,:) = CONST_UNDEF8
      qv_sfc  (:,:,:) = CONST_UNDEF8
      qc_sfc  (:,:,:) = CONST_UNDEF8

      if ( flg_bin ) then
         if( IO_L ) write(IO_FID_LOG,*) '*** Aerosols for SBM are included ***'
         call SBMAERO_setup
      endif

      select case(MKINIT_TYPE)
      case(I_PLANESTATE)
         call MKINIT_planestate
      case(I_TRACERBUBBLE)
         call MKINIT_tracerbubble
      case(I_COLDBUBBLE)
         call MKINIT_coldbubble
      case(I_LAMBWAVE)
         call MKINIT_lambwave
      case(I_GRAVITYWAVE)
         call MKINIT_gravitywave
      case(I_KHWAVE)
         call MKINIT_khwave
      case(I_TURBULENCE)
         call MKINIT_turbulence
      case(I_MOUNTAINWAVE)
         call MKINIT_mountainwave
      case(I_WARMBUBBLE)
         call MKINIT_warmbubble
      case(I_SUPERCELL)
         call MKINIT_supercell
      case(I_SQUALLLINE)
         call MKINIT_squallline
      case(I_WK1982)
         call MKINIT_wk1982
      case(I_DYCOMS2_RF01)
         call MKINIT_DYCOMS2_RF01
      case(I_DYCOMS2_RF02)
         call MKINIT_DYCOMS2_RF02
      case(I_RICO)
         call MKINIT_RICO
      case(I_INTERPORATION)
         call MKINIT_INTERPORATION
      case(I_OCEANCOUPLE)
         call MKINIT_planestate
         call MKINIT_oceancouple
      case(I_LANDCOUPLE)
         call MKINIT_planestate
         call MKINIT_landcouple
      case(I_URBANCOUPLE)
         call MKINIT_planestate
         call MKINIT_landcouple ! tentative
         call MKINIT_urbancouple
      case(I_TRIPLECOUPLE)
         call MKINIT_planestate
         call MKINIT_oceancouple
         call MKINIT_landcouple
         call MKINIT_urbancouple
      case(I_BUBBLECOUPLE)
         call MKINIT_planestate
         call MKINIT_warmbubble
         call MKINIT_oceancouple
         call MKINIT_landcouple
         call MKINIT_urbancouple
      case(I_SEABREEZE)
         call MKINIT_planestate
         call MKINIT_seabreeze
      case(I_HEATISLAND)
         call MKINIT_planestate
         call MKINIT_heatisland
      case(I_DYCOMS2_RF02_DNS)
         call MKINIT_DYCOMS2_RF02_DNS
      case(I_REAL)
         call MKINIT_real
      case default
         write(*,*) ' xxx Unsupported TYPE:', MKINIT_TYPE
         call PRC_MPIstop
      endselect

      if( IO_L ) write(IO_FID_LOG,*) '++++++ END   MAKING INITIAL  DATA ++++++'

      ! output boundary file
      call LANDUSE_write

      ! output restart file
      if( ATMOS_sw_restart ) call ATMOS_vars_restart_write
      if( OCEAN_sw_restart ) call OCEAN_vars_restart_write
      if( LAND_sw_restart  ) call LAND_vars_restart_write
      if( URBAN_sw_restart ) call URBAN_vars_restart_write
    endif

    return
  end subroutine MKINIT

  !-----------------------------------------------------------------------------
  !> Bubble
  subroutine BUBBLE_setup
    use scale_const, only: &
       CONST_UNDEF8
    implicit none

    ! Bubble
    logical  :: BBL_eachnode = .false.  ! Arrange bubble at each node? [kg/kg]
    real(RP) :: BBL_CZ       =  2.E3_RP ! center location [m]: z
    real(RP) :: BBL_CX       =  2.E3_RP ! center location [m]: x
    real(RP) :: BBL_CY       =  2.E3_RP ! center location [m]: y
    real(RP) :: BBL_RZ       =  2.E3_RP ! bubble radius   [m]: z
    real(RP) :: BBL_RX       =  2.E3_RP ! bubble radius   [m]: x
    real(RP) :: BBL_RY       =  2.E3_RP ! bubble radius   [m]: y

    NAMELIST / PARAM_BUBBLE / &
       BBL_eachnode, &
       BBL_CZ,       &
       BBL_CX,       &
       BBL_CY,       &
       BBL_RZ,       &
       BBL_RX,       &
       BBL_RY

    real(RP) :: CZ_offset
    real(RP) :: CX_offset
    real(RP) :: CY_offset
    real(RP) :: dist

    integer  :: ierr
    integer  :: k, i, j
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[BUBBLE]/Categ[MKINIT]'

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_BUBBLE,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) 'xxx Not found namelist. Check!'
       call PRC_MPIstop
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_BUBBLE. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_BUBBLE)

    bubble(:,:,:) = CONST_UNDEF8

    if ( BBL_eachnode ) then
       CZ_offset = GRID_CZ(KS)
       CX_offset = GRID_CX(IS)
       CY_offset = GRID_CY(JS)
    else
       CZ_offset = 0.0_RP
       CX_offset = 0.0_RP
       CY_offset = 0.0_RP
    endif

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE

       ! make tracer bubble
       dist = ( (GRID_CZ(k)-CZ_offset-BBL_CZ)/BBL_RZ )**2 &
            + ( (GRID_CX(i)-CX_offset-BBL_CX)/BBL_RX )**2 &
            + ( (GRID_CY(j)-CY_offset-BBL_CY)/BBL_RY )**2

       bubble(k,i,j) = cos( 0.5_RP*PI*sqrt( min(dist,1.0_RP) ) )**2

    enddo
    enddo
    enddo

    return
  end subroutine BUBBLE_setup

  !-----------------------------------------------------------------------------
  !> Setup aerosol condition for Spectral Bin Microphysics (SBM) model
  subroutine SBMAERO_setup
    use scale_const, only: &
       PI => CONST_PI
    implicit none

    real(RP) :: xasta, xaend, dxaer
    real(RP), allocatable :: xabnd( : ), xactr( : )

    real(RP) :: F0_AERO      = 1.E+7_RP
    real(RP) :: R0_AERO      = 1.E-7_RP
    real(RP) :: R_MAX        = 1.E-06_RP
    real(RP) :: R_MIN        = 1.E-08_RP
    real(RP) :: A_ALPHA      = 3.0_RP
    real(RP) :: rhoa         = 2.25E+03_RP
    integer  :: nbin_i       = 33
    integer  :: nccn_i       = 20

    NAMELIST / PARAM_SBMAERO / &
       F0_AERO,      &
       R0_AERO,      &
       R_MAX,        &
       R_MIN,        &
       A_ALPHA,      &
       rhoa,         &
       nccn_i,       &
       nbin_i

    integer :: ierr
    integer :: iq, i, j, k
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[AEROBIN]/Categ[MKINIT]'

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_SBMAERO,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) 'xxx Not found namelist. Check!'
       call PRC_MPIstop
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist SBMAERO. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_SBMAERO)

    allocate( gan( nccn_i ) )
    allocate( xactr(nccn_i) )
    allocate( xabnd(nccn_i+1) )

    xasta = log( rhoa*4.0_RP/3.0_RP*pi * ( R_MIN )**3 )
    xaend = log( rhoa*4.0_RP/3.0_RP*pi * ( R_MAX )**3 )
    dxaer = ( xaend-xasta )/nccn_i
    do iq = 1, nccn_i+1
      xabnd( iq ) = xasta + dxaer*( iq-1 )
    enddo
    do iq = 1, nccn_i
      xactr( iq ) = ( xabnd( iq )+xabnd( iq+1 ) )*0.5_RP
    enddo
    do iq = 1, nccn_i
      gan( iq ) = faero( F0_AERO,R0_AERO,xactr( iq ), A_ALPHA, rhoa )*exp( xactr(iq) )
    enddo

    !--- Hydrometeor is zero at initial time for Bin method
    do iq = 2,  QQA
    do j  = JS, JE
    do i  = IS, IE
    do k  = KS, KE
        QTRC(k,i,j,iq) = 0.0_RP
    enddo
    enddo
    enddo
    enddo

    !-- Aerosol distribution
    if( nccn_i /= 0 ) then
     do iq = QQA+1, QA
     do j  = JS, JE
     do i  = IS, IE
     do k  = KS, KE
       QTRC(k,i,j,iq) = gan(iq-QQA) !/ DENS(k,i,j)
     enddo
     enddo
     enddo
     enddo
    endif

    deallocate( xactr )
    deallocate( xabnd )

    return
  end subroutine SBMAERO_setup

  !-----------------------------------------------------------------------------
  function faero( f0,r0,x,alpha,rhoa )
    use scale_const, only: &
       pi => CONST_PI
    implicit none

    real(RP), intent(in) ::  x, f0, r0, alpha, rhoa
    real(RP) :: faero
    real(RP) :: rad
    !---------------------------------------------------------------------------

    rad = ( exp(x) * 3.0_RP / 4.0_RP / pi / rhoa )**(1.0_RP/3.0_RP)

    faero = f0 * (rad/r0)**(-alpha)

    return
  end function faero

  !-----------------------------------------------------------------------------
  !> Make initial state ( horizontally uniform + random disturbance )
  subroutine MKINIT_planestate
    use mod_ocean_vars, only: &
       OCEAN_TEMP,       &
       OCEAN_SFC_TEMP,   &
       OCEAN_SFC_albedo, &
       OCEAN_SFC_Z0
    implicit none

    ! Surface state
    real(RP) :: SFC_THETA               ! surface potential temperature [K]
    real(RP) :: SFC_PRES                ! surface pressure [Pa]
    real(RP) :: SFC_RH       =   0.0_RP ! surface relative humidity [%]
    ! Environment state
    real(RP) :: ENV_THETA               ! potential temperature of environment [K]
    real(RP) :: ENV_TLAPS    =   0.0_RP ! Lapse rate of THETA [K/m]
    real(RP) :: ENV_U        =   0.0_RP ! velocity u of environment [m/s]
    real(RP) :: ENV_V        =   0.0_RP ! velocity v of environment [m/s]
    real(RP) :: ENV_RH       =   0.0_RP ! relative humidity of environment [%]
    ! Disturbance
    real(RP) :: RANDOM_THETA =   0.0_RP ! amplitude of random disturbance theta
    real(RP) :: RANDOM_U     =   0.0_RP ! amplitude of random disturbance u
    real(RP) :: RANDOM_V     =   0.0_RP ! amplitude of random disturbance v
    real(RP) :: RANDOM_RH    =   0.0_RP ! amplitude of random disturbance RH

    NAMELIST / PARAM_MKINIT_PLANESTATE / &
       SFC_THETA,    &
       SFC_PRES,     &
       SFC_RH,       &
       ENV_THETA,    &
       ENV_TLAPS,    &
       ENV_U,        &
       ENV_V,        &
       ENV_RH,       &
       RANDOM_THETA, &
       RANDOM_U,     &
       RANDOM_V,     &
       RANDOM_RH

    integer :: ierr
    integer :: k, i, j
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[Horiz_UNIFORM]/Categ[MKINIT]'

    SFC_THETA = THETAstd
    SFC_PRES  = Pstd
    ENV_THETA = THETAstd

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_PLANESTATE,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_PLANESTATE. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_PLANESTATE)

    ! calc in dry condition
    do j = JS, JE
    do i = IS, IE
       pott_sfc(1,i,j) = SFC_THETA
       pres_sfc(1,i,j) = SFC_PRES
       qv_sfc  (1,i,j) = 0.0_RP
       qc_sfc  (1,i,j) = 0.0_RP

       do k = KS, KE
          qv(k,i,j) = 0.0_RP
          qc(k,i,j) = 0.0_RP
       enddo
    enddo
    enddo

    if ( ENV_THETA < 0.0_RP ) then ! use isa profile

       call PROFILE_isa( KA, KS, KE,      & ! [IN]
                         IA, IS, IE,      & ! [IN]
                         JA, JS, JE,      & ! [IN]
                         pott_sfc(1,:,:), & ! [IN]
                         pres_sfc(1,:,:), & ! [IN]
                         REAL_CZ (:,:,:), & ! [IN]
                         pott    (:,:,:)  ) ! [OUT]

    else

       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          pott(k,i,j) = ENV_THETA + ENV_TLAPS * REAL_CZ(k,i,j)
       enddo
       enddo
       enddo

    endif

    ! make density & pressure profile in moist condition
    call HYDROSTATIC_buildrho( DENS    (:,:,:), & ! [OUT]
                               temp    (:,:,:), & ! [OUT]
                               pres    (:,:,:), & ! [OUT]
                               pott    (:,:,:), & ! [IN]
                               qv      (:,:,:), & ! [IN]
                               qc      (:,:,:), & ! [IN]
                               temp_sfc(:,:,:), & ! [OUT]
                               pres_sfc(:,:,:), & ! [IN]
                               pott_sfc(:,:,:), & ! [IN]
                               qv_sfc  (:,:,:), & ! [IN]
                               qc_sfc  (:,:,:)  ) ! [IN]

    ! calc QV from RH
    call SATURATION_pres2qsat_all( qsat_sfc(1,:,:), temp_sfc(1,:,:), pres_sfc(1,:,:) )
    call SATURATION_pres2qsat_all( qsat    (:,:,:), temp    (:,:,:), pres    (:,:,:) )

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
       qv_sfc(1,i,j) = ( SFC_RH + rndm(KS-1,i,j) * RANDOM_RH ) * 1.E-2_RP * qsat_sfc(1,i,j)

       do k = KS, KE
          qv(k,i,j) = ( ENV_RH + rndm(k,i,j) * RANDOM_RH ) * 1.E-2_RP * qsat(k,i,j)
       enddo
    enddo
    enddo

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
       pott_sfc(1,i,j) = pott_sfc(1,i,j) + rndm(KS-1,i,j) * RANDOM_THETA

       do k = KS, KE
          pott(k,i,j) = pott(k,i,j) + rndm(k,i,j) * RANDOM_THETA
       enddo
    enddo
    enddo

    ! make density & pressure profile in moist condition
    call HYDROSTATIC_buildrho( DENS    (:,:,:), & ! [OUT]
                               temp    (:,:,:), & ! [OUT]
                               pres    (:,:,:), & ! [OUT]
                               pott    (:,:,:), & ! [IN]
                               qv      (:,:,:), & ! [IN]
                               qc      (:,:,:), & ! [IN]
                               temp_sfc(:,:,:), & ! [OUT]
                               pres_sfc(:,:,:), & ! [IN]
                               pott_sfc(:,:,:), & ! [IN]
                               qv_sfc  (:,:,:), & ! [IN]
                               qc_sfc  (:,:,:)  ) ! [IN]

    call COMM_vars8( DENS(:,:,:), 1 )
    call COMM_wait ( DENS(:,:,:), 1 )

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       MOMX(k,i,j) = ( ENV_U + ( rndm(k,i,j) - 0.5_RP ) * 2.0_RP * RANDOM_U ) &
                   * 0.5_RP * ( DENS(k,i+1,j) + DENS(k,i,j) )
    enddo
    enddo
    enddo

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       MOMY(k,i,j) = ( ENV_V + ( rndm(k,i,j) - 0.5_RP ) * 2.0_RP * RANDOM_V ) &
                   * 0.5_RP * ( DENS(k,i,j+1) + DENS(k,i,j) )
    enddo
    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       MOMZ(k,i,j) = 0.0_RP
       RHOT(k,i,j) = pott(k,i,j) * DENS(k,i,j)

       QTRC(k,i,j,I_QV) = qv(k,i,j)
    enddo
    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
       SFLX_rain   (i,j) = 0.0_RP
       SFLX_snow   (i,j) = 0.0_RP
       SFLX_LW_up  (i,j) = 0.0_RP
       SFLX_LW_dn  (i,j) = 0.0_RP
       SFLX_SW_up  (i,j) = 0.0_RP
       SFLX_SW_dn  (i,j) = 0.0_RP
       TOAFLX_LW_up(i,j) = 0.0_RP
       TOAFLX_LW_dn(i,j) = 0.0_RP
       TOAFLX_SW_up(i,j) = 0.0_RP
       TOAFLX_SW_dn(i,j) = 0.0_RP

       OCEAN_TEMP      (i,j)      = THETAstd
       OCEAN_SFC_TEMP  (i,j)      = THETAstd
       OCEAN_SFC_albedo(i,j,I_LW) = 0.04_RP
       OCEAN_SFC_albedo(i,j,I_SW) = 0.05_RP
       OCEAN_SFC_Z0    (i,j)      = 0.0_RP
    enddo
    enddo

    return
  end subroutine MKINIT_planestate

  !-----------------------------------------------------------------------------
  !> Make initial state for tracer bubble experiment
  subroutine MKINIT_tracerbubble
    implicit none

    ! Surface state
    real(RP) :: SFC_THETA               ! surface potential temperature [K]
    real(RP) :: SFC_PRES                ! surface pressure [Pa]
    ! Environment state
    real(RP) :: ENV_THETA               ! potential temperature of environment [K]
    real(RP) :: ENV_U        =   0.0_RP ! velocity u of environment [m/s]
    real(RP) :: ENV_V        =   0.0_RP ! velocity v of environment [m/s]
    ! Bubble
    real(RP) :: BBL_NC       =   1.0_RP ! extremum of NC in bubble [kg/kg]

    NAMELIST / PARAM_MKINIT_TRACERBUBBLE / &
       SFC_THETA, &
       SFC_PRES,  &
       ENV_THETA, &
       ENV_U,     &
       ENV_V,     &
       BBL_NC

    integer :: ierr
    integer :: k, i, j, iq
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[TRACERBUBBLE]/Categ[MKINIT]'

    SFC_THETA = THETAstd
    SFC_PRES  = Pstd
    ENV_THETA = THETAstd

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_TRACERBUBBLE,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_TRACERBUBBLE. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_TRACERBUBBLE)

    ! calc in dry condition
    pres_sfc(1,1,1) = SFC_PRES
    pott_sfc(1,1,1) = SFC_THETA
    qv_sfc  (1,1,1) = 0.0_RP
    qc_sfc  (1,1,1) = 0.0_RP

    do k = KS, KE
       pott(k,1,1) = ENV_THETA
       qv  (k,1,1) = 0.0_RP
       qc  (k,1,1) = 0.0_RP
    enddo

    ! make density & pressure profile in dry condition
    call HYDROSTATIC_buildrho( DENS    (:,1,1), & ! [OUT]
                               temp    (:,1,1), & ! [OUT]
                               pres    (:,1,1), & ! [OUT]
                               pott    (:,1,1), & ! [IN]
                               qv      (:,1,1), & ! [IN]
                               qc      (:,1,1), & ! [IN]
                               temp_sfc(1,1,1), & ! [OUT]
                               pres_sfc(1,1,1), & ! [IN]
                               pott_sfc(1,1,1), & ! [IN]
                               qv_sfc  (1,1,1), & ! [IN]
                               qc_sfc  (1,1,1)  ) ! [IN]

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       DENS(k,i,j) = DENS(k,1,1)
       MOMZ(k,i,j) = 0.0_RP
       MOMX(k,i,j) = ENV_U       * DENS(k,1,1)
       MOMY(k,i,j) = ENV_V       * DENS(k,1,1)
       RHOT(k,i,j) = pott(k,1,1) * DENS(k,1,1)

       do iq = 1, QA
          QTRC(k,i,j,iq) = 0.0_RP
       enddo
    enddo
    enddo
    enddo

    ! make tracer bubble
    if ( I_NC > 0 ) then
       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          QTRC(k,i,j,I_NC) = BBL_NC * bubble(k,i,j)
       enddo
       enddo
       enddo
    else
       write(*,*) 'xxx tracer I_NC is not defined. Check!'
       call PRC_MPIstop
    endif

    if ( flg_bin ) then
       write(*,*) 'xxx SBM cannot be used on tracerbubble. Check!'
       call PRC_MPIstop
    endif

    return
  end subroutine MKINIT_tracerbubble

  !-----------------------------------------------------------------------------
  !> Make initial state for cold bubble experiment
  !! Default values are following by Straka et al. (1993)
  !!  BBL_TEMP = -15.0_RP   ! in temperature  [K]
  !!  BBL_CZ   =   3.0E3_RP ! center location [m]: z
  !!  BBL_CX   =  19.2E3_RP ! center location [m]: x
  !!  BBL_CY   =   1.0E2_RP ! center location [m]: y
  !!  BBL_RZ   =   2.0E3_RP ! bubble radius   [m]: z
  !!  BBL_RX   =   4.0E3_RP ! bubble radius   [m]: x
  !!  BBL_RY   =   1.0E3_RP ! bubble radius   [m]: y
  subroutine MKINIT_coldbubble
    implicit none

    ! Surface state
    real(RP) :: SFC_THETA               ! surface potential temperature [K]
    real(RP) :: SFC_PRES                ! surface pressure [Pa]
    ! Environment state
    real(RP) :: ENV_THETA               ! potential temperature of environment [K]
    ! Bubble
    real(RP) :: BBL_TEMP     = -15.0_RP ! extremum of temperature in bubble [K]

    NAMELIST / PARAM_MKINIT_COLDBUBBLE / &
       SFC_THETA, &
       SFC_PRES,  &
       ENV_THETA, &
       BBL_TEMP

    integer :: ierr
    integer :: k, i, j, iq
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[COLDBUBBLE]/Categ[MKINIT]'

    SFC_THETA = THETAstd
    SFC_PRES  = Pstd
    ENV_THETA = THETAstd

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_COLDBUBBLE,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_COLDBUBBLE. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_COLDBUBBLE)

    ! calc in dry condition
    pres_sfc(1,1,1) = SFC_PRES
    pott_sfc(1,1,1) = SFC_THETA
    qv_sfc  (1,1,1) = 0.0_RP
    qc_sfc  (1,1,1) = 0.0_RP

    do k = KS, KE
       pott(k,1,1) = ENV_THETA
       qv  (k,1,1) = 0.0_RP
       qc  (k,1,1) = 0.0_RP
    enddo

    ! make density & pressure profile in dry condition
    call HYDROSTATIC_buildrho( DENS    (:,1,1), & ! [OUT]
                               temp    (:,1,1), & ! [OUT]
                               pres    (:,1,1), & ! [OUT]
                               pott    (:,1,1), & ! [IN]
                               qv      (:,1,1), & ! [IN]
                               qc      (:,1,1), & ! [IN]
                               temp_sfc(1,1,1), & ! [OUT]
                               pres_sfc(1,1,1), & ! [IN]
                               pott_sfc(1,1,1), & ! [IN]
                               qv_sfc  (1,1,1), & ! [IN]
                               qc_sfc  (1,1,1)  ) ! [IN]

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       DENS(k,i,j) = DENS(k,1,1)
       MOMZ(k,i,j) = 0.0_RP
       MOMX(k,i,j) = 0.0_RP
       MOMY(k,i,j) = 0.0_RP

       ! make cold bubble
       RHOT(k,i,j) = DENS(k,1,1) * ( pott(k,1,1)                                           &
                                   + BBL_TEMP * ( P00/pres(k,1,1) )**RovCP * bubble(k,i,j) )

       do iq = 1, QA
          QTRC(k,i,j,iq) = 0.0_RP
       enddo
    enddo
    enddo
    enddo

    if ( flg_bin ) then
       write(*,*) 'xxx SBM cannot be used on coldbubble. Check!'
       call PRC_MPIstop
    endif

    return
  end subroutine MKINIT_coldbubble

  !-----------------------------------------------------------------------------
  !> Make initial state for cold bubble experiment
  subroutine MKINIT_lambwave
    implicit none

    ! Surface state
    real(RP) :: SFC_PRES                ! surface pressure [Pa]
    ! Environment state
    real(RP) :: ENV_U        =   0.0_RP ! velocity u of environment [m/s]
    real(RP) :: ENV_V        =   0.0_RP ! velocity v of environment [m/s]
    real(RP) :: ENV_TEMP     = 300.0_RP ! temperature of environment [K]
    ! Bubble
    real(RP) :: BBL_PRES     =  100._RP ! extremum of pressure in bubble [Pa]

    NAMELIST / PARAM_MKINIT_LAMBWAVE / &
       SFC_PRES,  &
       ENV_U,     &
       ENV_V,     &
       ENV_TEMP,  &
       BBL_PRES

    integer :: ierr
    integer :: k, i, j, iq
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[LAMBWAVE]/Categ[MKINIT]'

    SFC_PRES  = Pstd

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_LAMBWAVE,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_LAMBWAVE. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_LAMBWAVE)

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       DENS(k,i,j) = SFC_PRES/(Rdry*ENV_TEMP) * exp( - GRAV/(Rdry*ENV_TEMP) * GRID_CZ(k) )
       MOMZ(k,i,j) = 0.0_RP
       MOMX(k,i,j) = ENV_U * DENS(k,i,j)
       MOMY(k,i,j) = ENV_V * DENS(k,i,j)

       ! make pressure bubble
       pres(k,i,j) = DENS(k,i,j) * ENV_TEMP * Rdry + BBL_PRES * bubble(k,i,j)

       RHOT(k,i,j) = DENS(k,i,j) * ENV_TEMP * ( P00/pres(k,i,j) )**RovCP

       do iq = 1, QA
          QTRC(k,i,j,iq) = 0.0_RP
       enddo
    enddo
    enddo
    enddo

    if ( flg_bin ) then
       write(*,*) 'xxx SBM cannot be used on lambwave. Check!'
       call PRC_MPIstop
    endif

    return
  end subroutine MKINIT_lambwave

  !-----------------------------------------------------------------------------
  !> Make initial state for gravity wave experiment
  !! Default values are following by Skamarock and Klemp (1994)
  subroutine MKINIT_gravitywave
    implicit none

    ! Surface state
    real(RP) :: SFC_THETA               ! surface potential temperature [K]
    real(RP) :: SFC_PRES                ! surface pressure [Pa]
    ! Environment state
    real(RP) :: ENV_U        =  20.0_RP ! velocity u of environment [m/s]
    real(RP) :: ENV_V        =   0.0_RP ! velocity v of environment [m/s]
    real(RP) :: ENV_BVF      =  0.01_RP ! Brunt Vaisala frequencies of environment [1/s]
    ! Bubble
    real(RP) :: BBL_THETA    =  0.01_RP ! extremum of potential temperature in bubble [K]

    NAMELIST / PARAM_MKINIT_GRAVITYWAVE / &
       SFC_THETA, &
       SFC_PRES,  &
       ENV_U,     &
       ENV_V,     &
       ENV_BVF,   &
       BBL_THETA

    integer :: ierr
    integer :: k, i, j, iq
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[GRAVITYWAVE]/Categ[MKINIT]'

    SFC_THETA = THETAstd
    SFC_PRES  = Pstd

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_GRAVITYWAVE,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_GRAVITYWAVE. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_GRAVITYWAVE)

    ! calc in dry condition
    pres_sfc(1,1,1) = SFC_PRES
    pott_sfc(1,1,1) = SFC_THETA
    qv_sfc  (1,1,1) = 0.0_RP
    qc_sfc  (1,1,1) = 0.0_RP

    do k = KS, KE
       pott(k,1,1) = SFC_THETA * exp( ENV_BVF*ENV_BVF / GRAV * GRID_CZ(k) )
       qv  (k,1,1) = 0.0_RP
       qc  (k,1,1) = 0.0_RP
    enddo

    ! make density & pressure profile in dry condition
    call HYDROSTATIC_buildrho( DENS    (:,1,1), & ! [OUT]
                               temp    (:,1,1), & ! [OUT]
                               pres    (:,1,1), & ! [OUT]
                               pott    (:,1,1), & ! [IN]
                               qv      (:,1,1), & ! [IN]
                               qc      (:,1,1), & ! [IN]
                               temp_sfc(1,1,1), & ! [OUT]
                               pres_sfc(1,1,1), & ! [IN]
                               pott_sfc(1,1,1), & ! [IN]
                               qv_sfc  (1,1,1), & ! [IN]
                               qc_sfc  (1,1,1)  ) ! [IN]

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       DENS(k,i,j) = DENS(k,1,1)
       MOMZ(k,i,j) = 0.0_RP
       MOMX(k,i,j) = ENV_U * DENS(k,1,1)
       MOMY(k,i,j) = ENV_V * DENS(k,1,1)

       ! make warm bubble
       RHOT(k,i,j) = DENS(k,1,1) * ( pott(k,1,1) + BBL_THETA * bubble(k,i,j) )

       do iq = 1, QA
          QTRC(k,i,j,iq) = 0.0_RP
       enddo
    enddo
    enddo
    enddo

    if ( flg_bin ) then
       write(*,*) 'xxx SBM cannot be used on gravitywave. Check!'
       call PRC_MPIstop
    endif

    return
  end subroutine MKINIT_gravitywave

  !-----------------------------------------------------------------------------
  !> Make initial state for Kelvin-Helmholtz wave experiment
  subroutine MKINIT_khwave
    implicit none

    ! Surface state
    real(RP) :: SFC_THETA                  ! surface potential temperature [K]
    real(RP) :: SFC_PRES                   ! surface pressure [Pa]
    ! Environment state
    real(RP) :: ENV_L1_ZTOP    = 1900.0_RP ! top    height of the layer1 (low  THETA) [m]
    real(RP) :: ENV_L3_ZBOTTOM = 2100.0_RP ! bottom height of the layer3 (high THETA) [m]
    real(RP) :: ENV_L1_THETA   =  300.0_RP ! THETA in the layer1 (low  THETA) [K]
    real(RP) :: ENV_L3_THETA   =  301.0_RP ! THETA in the layer3 (high THETA) [K]
    real(RP) :: ENV_L1_U       =    0.0_RP ! velocity u in the layer1 (low  THETA) [K]
    real(RP) :: ENV_L3_U       =   20.0_RP ! velocity u in the layer3 (high THETA) [K]
    ! Disturbance
    real(RP) :: RANDOM_U       =    0.0_RP ! amplitude of random disturbance u

    NAMELIST / PARAM_MKINIT_KHWAVE / &
       SFC_THETA,      &
       SFC_PRES,       &
       ENV_L1_ZTOP,    &
       ENV_L3_ZBOTTOM, &
       ENV_L1_THETA,   &
       ENV_L3_THETA,   &
       ENV_L1_U,       &
       ENV_L3_U,       &
       RANDOM_U

    real(RP) :: fact

    integer :: ierr
    integer :: k, i, j, iq
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[KH wave]/Categ[MKINIT]'

    SFC_THETA = THETAstd
    SFC_PRES  = Pstd

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_KHWAVE,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_KHWAVE. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_KHWAVE)

    ! calc in dry condition
    pres_sfc(1,1,1) = SFC_PRES
    pott_sfc(1,1,1) = SFC_THETA
    qv_sfc  (1,1,1) = 0.0_RP
    qc_sfc  (1,1,1) = 0.0_RP

    do k = KS, KE
       fact = ( GRID_CZ(k)-ENV_L1_ZTOP ) / ( ENV_L3_ZBOTTOM-ENV_L1_ZTOP )
       fact = max( min( fact, 1.0_RP ), 0.0_RP )

       pott(k,1,1) = ENV_L1_THETA * ( 1.0_RP - fact ) &
                   + ENV_L3_THETA * (          fact )

       qv(k,1,1) = 0.0_RP
       qc(k,1,1) = 0.0_RP
    enddo

    ! make density & pressure profile in dry condition
    call HYDROSTATIC_buildrho( DENS    (:,1,1), & ! [OUT]
                               temp    (:,1,1), & ! [OUT]
                               pres    (:,1,1), & ! [OUT]
                               pott    (:,1,1), & ! [IN]
                               qv      (:,1,1), & ! [IN]
                               qc      (:,1,1), & ! [IN]
                               temp_sfc(1,1,1), & ! [OUT]
                               pres_sfc(1,1,1), & ! [IN]
                               pott_sfc(1,1,1), & ! [IN]
                               qv_sfc  (1,1,1), & ! [IN]
                               qc_sfc  (1,1,1)  ) ! [IN]

    ! calc QV from RH
    call SATURATION_pres2qsat_all( qsat_sfc(1,1,1), temp_sfc(1,1,1), pres_sfc(1,1,1) )
    call SATURATION_pres2qsat_all( qsat    (:,1,1), temp    (:,1,1), pres    (:,1,1) )

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       DENS(k,i,j) = DENS(k,1,1)
       MOMZ(k,i,j) = 0.0_RP
       MOMY(k,i,j) = 0.0_RP
       RHOT(k,i,j) = DENS(k,1,1) * pott(k,1,1)

       do iq = 1, QA
          QTRC(k,i,j,iq) = 0.0_RP
       enddo
    enddo
    enddo
    enddo

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       fact = ( GRID_CZ(k)-ENV_L1_ZTOP ) / ( ENV_L3_ZBOTTOM-ENV_L1_ZTOP )
       fact = max( min( fact, 1.0_RP ), 0.0_RP )

       MOMX(k,i,j) = ( ENV_L1_U * ( 1.0_RP - fact )                 &
                     + ENV_L3_U * (          fact )                 &
                     + ( rndm(k,i,j) - 0.5_RP ) * 2.0_RP * RANDOM_U &
                     ) * DENS(k,i,j)
    enddo
    enddo
    enddo

    if ( flg_bin ) then
       write(*,*) 'xxx SBM cannot be used on khwave. Check!'
       call PRC_MPIstop
    endif

    return
  end subroutine MKINIT_khwave

  !-----------------------------------------------------------------------------
  !> Make initial state for turbulence experiment
  subroutine MKINIT_turbulence
    implicit none

    ! Surface state
    real(RP) :: SFC_THETA               ! surface potential temperature [K]
    real(RP) :: SFC_PRES                ! surface pressure [Pa]
    real(RP) :: SFC_RH       =   0.0_RP ! surface relative humidity [%]
    ! Environment state
    real(RP) :: ENV_THETA               ! potential temperature of environment [K]
    real(RP) :: ENV_TLAPS    = 4.E-3_RP ! Lapse rate of THETA [K/m]
    real(RP) :: ENV_U        =   5.0_RP ! velocity u of environment [m/s]
    real(RP) :: ENV_V        =   0.0_RP ! velocity v of environment [m/s]
    real(RP) :: ENV_RH       =   0.0_RP ! relative humidity of environment [%]
    ! Disturbance
    real(RP) :: RANDOM_THETA =   1.0_RP ! amplitude of random disturbance theta
    real(RP) :: RANDOM_U     =   0.0_RP ! amplitude of random disturbance u
    real(RP) :: RANDOM_V     =   0.0_RP ! amplitude of random disturbance v
    real(RP) :: RANDOM_RH    =   0.0_RP ! amplitude of random disturbance RH

    NAMELIST / PARAM_MKINIT_TURBULENCE / &
       SFC_THETA,    &
       SFC_PRES,     &
       SFC_RH,       &
       ENV_THETA,    &
       ENV_TLAPS,    &
       ENV_U,        &
       ENV_V,        &
       ENV_RH,       &
       RANDOM_THETA, &
       RANDOM_U,     &
       RANDOM_V,     &
       RANDOM_RH

    integer :: ierr
    integer :: k, i, j, iq
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[TURBULENCE]/Categ[MKINIT]'

    SFC_THETA = THETAstd
    SFC_PRES  = Pstd
    ENV_THETA = THETAstd

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_TURBULENCE,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_TURBULENCE. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_TURBULENCE)

    ! calc in dry condition
    pres_sfc(1,1,1) = SFC_PRES
    pott_sfc(1,1,1) = SFC_THETA
    qv_sfc  (1,1,1) = 0.0_RP
    qc_sfc  (1,1,1) = 0.0_RP

    do k = KS, KE
       pott(k,1,1) = ENV_THETA + ENV_TLAPS * GRID_CZ(k)
       qv  (k,1,1) = 0.0_RP
       qc  (k,1,1) = 0.0_RP
    enddo

    ! make density & pressure profile in dry condition
    call HYDROSTATIC_buildrho( DENS    (:,1,1), & ! [OUT]
                               temp    (:,1,1), & ! [OUT]
                               pres    (:,1,1), & ! [OUT]
                               pott    (:,1,1), & ! [IN]
                               qv      (:,1,1), & ! [IN]
                               qc      (:,1,1), & ! [IN]
                               temp_sfc(1,1,1), & ! [OUT]
                               pres_sfc(1,1,1), & ! [IN]
                               pott_sfc(1,1,1), & ! [IN]
                               qv_sfc  (1,1,1), & ! [IN]
                               qc_sfc  (1,1,1)  ) ! [IN]

    ! calc QV from RH
    call SATURATION_pres2qsat_all( qsat_sfc(1,1,1), temp_sfc(1,1,1), pres_sfc(1,1,1) )
    call SATURATION_pres2qsat_all( qsat    (:,1,1), temp    (:,1,1), pres    (:,1,1) )

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
       qv_sfc(1,i,j) = ( SFC_RH + rndm(KS-1,i,j) * RANDOM_RH ) * 1.E-2_RP * qsat_sfc(1,1,1)
       qc_sfc(1,i,j) = 0.0_RP

       do k = KS, KE
          qv(k,i,j) = ( ENV_RH + rndm(k,i,j) * RANDOM_RH ) * 1.E-2_RP * qsat(k,1,1)
          qc(k,i,j) = 0.0_RP
       enddo
    enddo
    enddo

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
       pres_sfc(1,i,j) = SFC_PRES
       pott_sfc(1,i,j) = SFC_THETA + rndm(KS-1,i,j) * RANDOM_THETA

       do k = KS, KE
          pott(k,i,j) = ENV_THETA + ENV_TLAPS * GRID_CZ(k) + rndm(k,i,j) * RANDOM_THETA
       enddo
    enddo
    enddo

    ! make density & pressure profile in moist condition
    call HYDROSTATIC_buildrho( DENS    (:,:,:), & ! [OUT]
                               temp    (:,:,:), & ! [OUT]
                               pres    (:,:,:), & ! [OUT]
                               pott    (:,:,:), & ! [IN]
                               qv      (:,:,:), & ! [IN]
                               qc      (:,:,:), & ! [IN]
                               temp_sfc(:,:,:), & ! [OUT]
                               pres_sfc(:,:,:), & ! [IN]
                               pott_sfc(:,:,:), & ! [IN]
                               qv_sfc  (:,:,:), & ! [IN]
                               qc_sfc  (:,:,:)  ) ! [IN]

    call COMM_vars8( DENS(:,:,:), 1 )
    call COMM_wait ( DENS(:,:,:), 1 )

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       MOMX(k,i,j) = ( ENV_U + ( rndm(k,i,j) - 0.5_RP ) * 2.0_RP * RANDOM_U ) &
                   * 0.5_RP * ( DENS(k,i+1,j) + DENS(k,i,j) )
    enddo
    enddo
    enddo

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       MOMY(k,i,j) = ( ENV_V + ( rndm(k,i,j) - 0.5_RP ) * 2.0_RP * RANDOM_V ) &
                   * 0.5_RP * ( DENS(k,i,j+1) + DENS(k,i,j) )
    enddo
    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       MOMZ(k,i,j) = 0.0_RP
       RHOT(k,i,j) = pott(k,i,j) * DENS(k,i,j)

       QTRC(k,i,j,I_QV) = qv(k,i,j)
    enddo
    enddo
    enddo

    if ( QA >= 2 ) then
       do iq = 2, QA
       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          QTRC(k,i,j,iq) = 0.0_RP
       enddo
       enddo
       enddo
       enddo
    endif

    if ( flg_bin ) then
       write(*,*) 'xxx SBM cannot be used on turbulence. Check!'
       call PRC_MPIstop
    endif

    return
  end subroutine MKINIT_turbulence

  !-----------------------------------------------------------------------------
  !> Make initial state ( horizontally uniform )
  subroutine MKINIT_mountainwave
    implicit none

    ! Surface state
    real(RP) :: SFC_THETA      ! surface potential temperature [K]
    real(RP) :: SFC_PRES       ! surface pressure [Pa]
    ! Environment state
    real(RP) :: ENV_U = 0.0_RP ! velocity u of environment [m/s]
    real(RP) :: ENV_V = 0.0_RP ! velocity v of environment [m/s]

    real(RP) :: SCORER = 2.E-3_RP ! Scorer parameter (~=N/U) [1/m]

    NAMELIST / PARAM_MKINIT_MOUNTAINWAVE / &
       SFC_THETA, &
       SFC_PRES,  &
       ENV_U,     &
       ENV_V,     &
       SCORER

    real(RP) :: Ustar2, N2

    integer :: ierr
    integer :: k, i, j
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[Mountainwave]/Categ[MKINIT]'

    SFC_THETA = THETAstd
    SFC_PRES  = Pstd

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_MOUNTAINWAVE,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_MOUNTAINWAVE. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_MOUNTAINWAVE)

    ! calc in dry condition
    do j = JS, JE
    do i = IS, IE
       pres_sfc(1,i,j) = SFC_PRES
       pott_sfc(1,i,j) = SFC_THETA
       qv_sfc  (1,i,j) = 0.0_RP
       qc_sfc  (1,i,j) = 0.0_RP
    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       Ustar2 = ENV_U * ENV_U + ENV_V * ENV_V
       N2     = Ustar2 * (SCORER*SCORER)

       pott(k,i,j) = SFC_THETA * exp( N2 / GRAV * REAL_CZ(k,i,j) )
       qv  (k,i,j) = 0.0_RP
       qc  (k,i,j) = 0.0_RP
    enddo
    enddo
    enddo

    ! make density & pressure profile in dry condition
    call HYDROSTATIC_buildrho( DENS    (:,:,:), & ! [OUT]
                               temp    (:,:,:), & ! [OUT]
                               pres    (:,:,:), & ! [OUT]
                               pott    (:,:,:), & ! [IN]
                               qv      (:,:,:), & ! [IN]
                               qc      (:,:,:), & ! [IN]
                               temp_sfc(:,:,:), & ! [OUT]
                               pres_sfc(:,:,:), & ! [IN]
                               pott_sfc(:,:,:), & ! [IN]
                               qv_sfc  (:,:,:), & ! [IN]
                               qc_sfc  (:,:,:)  ) ! [IN]

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       DENS(k,i,j) = DENS(k,i,j)
       MOMZ(k,i,j) = 0.0_RP
       MOMX(k,i,j) = ENV_U       * DENS(k,i,j)
       MOMY(k,i,j) = ENV_V       * DENS(k,i,j)
       RHOT(k,i,j) = pott(k,i,j) * DENS(k,i,j)

       QTRC(k,i,j,:) = 0.0_RP
    enddo
    enddo
    enddo

    return
  end subroutine MKINIT_mountainwave

  !-----------------------------------------------------------------------------
  !> Make initial state for warm bubble experiment
  subroutine MKINIT_warmbubble
    implicit none

    ! Surface state
    real(RP) :: SFC_THETA               ! surface potential temperature [K]
    real(RP) :: SFC_PRES                ! surface pressure [Pa]
    real(RP) :: SFC_RH       =  80.0_RP ! surface relative humidity [%]
    ! Environment state
    real(RP) :: ENV_U        =   0.0_RP ! velocity u of environment [m/s]
    real(RP) :: ENV_V        =   0.0_RP ! velocity v of environment [m/s]
    real(RP) :: ENV_RH       =  80.0_RP ! Relative Humidity of environment [%]
    real(RP) :: ENV_L1_ZTOP  =  1.E3_RP ! top height of the layer1 (constant THETA)       [m]
    real(RP) :: ENV_L2_ZTOP  = 14.E3_RP ! top height of the layer2 (small THETA gradient) [m]
    real(RP) :: ENV_L2_TLAPS = 4.E-3_RP ! Lapse rate of THETA in the layer2 (small THETA gradient) [K/m]
    real(RP) :: ENV_L3_TLAPS = 3.E-2_RP ! Lapse rate of THETA in the layer3 (large THETA gradient) [K/m]
    ! Bubble
    real(RP) :: BBL_THETA    =   1.0_RP ! extremum of temperature in bubble [K]

    NAMELIST / PARAM_MKINIT_WARMBUBBLE / &
       SFC_THETA,    &
       SFC_PRES,     &
       ENV_U,        &
       ENV_V,        &
       ENV_RH,       &
       ENV_L1_ZTOP,  &
       ENV_L2_ZTOP,  &
       ENV_L2_TLAPS, &
       ENV_L3_TLAPS, &
       BBL_THETA

    integer :: ierr
    integer :: k, i, j
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[WARMBUBBLE]/Categ[MKINIT]'

    SFC_THETA = THETAstd
    SFC_PRES  = Pstd

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_WARMBUBBLE,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_WARMBUBBLE. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_WARMBUBBLE)

    ! calc in dry condition
    pres_sfc(1,1,1) = SFC_PRES
    pott_sfc(1,1,1) = SFC_THETA
    qv_sfc  (1,1,1) = 0.0_RP
    qc_sfc  (1,1,1) = 0.0_RP

    do k = KS, KE
       if    ( GRID_CZ(k) <= ENV_L1_ZTOP ) then ! Layer 1
          pott(k,1,1) = SFC_THETA
       elseif( GRID_CZ(k) <  ENV_L2_ZTOP ) then ! Layer 2
          pott(k,1,1) = pott(k-1,1,1) + ENV_L2_TLAPS * ( GRID_CZ(k)-GRID_CZ(k-1) )
       else                                ! Layer 3
          pott(k,1,1) = pott(k-1,1,1) + ENV_L3_TLAPS * ( GRID_CZ(k)-GRID_CZ(k-1) )
       endif
       qv(k,1,1) = 0.0_RP
       qc(k,1,1) = 0.0_RP
    enddo

    ! make density & pressure profile in dry condition
    call HYDROSTATIC_buildrho( DENS    (:,1,1), & ! [OUT]
                               temp    (:,1,1), & ! [OUT]
                               pres    (:,1,1), & ! [OUT]
                               pott    (:,1,1), & ! [IN]
                               qv      (:,1,1), & ! [IN]
                               qc      (:,1,1), & ! [IN]
                               temp_sfc(1,1,1), & ! [OUT]
                               pres_sfc(1,1,1), & ! [IN]
                               pott_sfc(1,1,1), & ! [IN]
                               qv_sfc  (1,1,1), & ! [IN]
                               qc_sfc  (1,1,1)  ) ! [IN]

    ! calc QV from RH
    call SATURATION_pres2qsat_all( qsat_sfc(1,1,1), temp_sfc(1,1,1), pres_sfc(1,1,1) )
    call SATURATION_pres2qsat_all( qsat    (:,1,1), temp    (:,1,1), pres    (:,1,1) )

    qv_sfc(1,1,1) = SFC_RH * 1.E-2_RP * qsat_sfc(1,1,1)
    do k = KS, KE
       if    ( GRID_CZ(k) <= ENV_L1_ZTOP ) then ! Layer 1
          qv(k,1,1) = ENV_RH * 1.E-2_RP * qsat(k,1,1)
       elseif( GRID_CZ(k) <= ENV_L2_ZTOP ) then ! Layer 2
          qv(k,1,1) = ENV_RH * 1.E-2_RP * qsat(k,1,1)
       else                                ! Layer 3
          qv(k,1,1) = 0.0_RP
       endif
    enddo

    ! make density & pressure profile in moist condition
    call HYDROSTATIC_buildrho( DENS    (:,1,1), & ! [OUT]
                               temp    (:,1,1), & ! [OUT]
                               pres    (:,1,1), & ! [OUT]
                               pott    (:,1,1), & ! [IN]
                               qv      (:,1,1), & ! [IN]
                               qc      (:,1,1), & ! [IN]
                               temp_sfc(1,1,1), & ! [OUT]
                               pres_sfc(1,1,1), & ! [IN]
                               pott_sfc(1,1,1), & ! [IN]
                               qv_sfc  (1,1,1), & ! [IN]
                               qc_sfc  (1,1,1)  ) ! [IN]

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       DENS(k,i,j) = DENS(k,1,1)
       MOMZ(k,i,j) = 0.0_RP
       MOMX(k,i,j) = ENV_U * DENS(k,i,j)
       MOMY(k,i,j) = ENV_V * DENS(k,i,j)

       ! make warm bubble
       RHOT(k,i,j) = DENS(k,1,1) * ( pott(k,1,1) + BBL_THETA * bubble(k,i,j) )

       QTRC(k,i,j,I_QV) = qv(k,1,1)
    enddo
    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
       SFLX_rain   (i,j) = 0.0_RP
       SFLX_snow   (i,j) = 0.0_RP
       SFLX_LW_up  (i,j) = 0.0_RP
       SFLX_LW_dn  (i,j) = 0.0_RP
       SFLX_SW_up  (i,j) = 0.0_RP
       SFLX_SW_dn  (i,j) = 0.0_RP
       TOAFLX_LW_up(i,j) = 0.0_RP
       TOAFLX_LW_dn(i,j) = 0.0_RP
       TOAFLX_SW_up(i,j) = 0.0_RP
       TOAFLX_SW_dn(i,j) = 0.0_RP
    enddo
    enddo

    return
  end subroutine MKINIT_warmbubble

  !-----------------------------------------------------------------------------
  !> Make initial state for supercell experiment
  subroutine MKINIT_supercell
    implicit none

    character(len=H_LONG) :: ENV_IN_SOUNDING_file = ''
    ! Bubble
    real(RP) :: BBL_THETA = 3.D0 ! extremum of temperature in bubble [K]

    NAMELIST / PARAM_MKINIT_SUPERCELL / &
       ENV_IN_SOUNDING_file, &
       BBL_THETA

    integer, parameter :: EXP_klim = 100
    integer            :: EXP_kmax

    real(RP) :: SFC_THETA            ! surface potential temperature [K]
    real(RP) :: SFC_PRES             ! surface pressure [hPa]
    real(RP) :: SFC_QV               ! surface watervapor [g/kg]

    real(RP) :: EXP_z   (EXP_klim+1) ! height      [m]
    real(RP) :: EXP_pott(EXP_klim+1) ! potential temperature [K]
    real(RP) :: EXP_qv  (EXP_klim+1) ! water vapor [g/kg]
    real(RP) :: EXP_u   (EXP_klim+1) ! velocity u  [m/s]
    real(RP) :: EXP_v   (EXP_klim+1) ! velocity v  [m/s]

    real(RP) :: fact1, fact2

    integer :: ierr, fid
    integer :: k, i, j, kref
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[SUPERCELL]/Categ[INIT]'

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_SUPERCELL,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_SUPERCELL. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_SUPERCELL)

    !--- prepare sounding profile
    if( IO_L ) write(IO_FID_LOG,*) '+++ Input sounding file:', trim(ENV_IN_SOUNDING_file)
    fid = IO_get_available_fid()
    open( fid,                                 &
          file   = trim(ENV_IN_SOUNDING_file), &
          form   = 'formatted',                &
          status = 'old',                      &
          iostat = ierr                        )

       if ( ierr /= 0 ) then
          if( IO_L ) write(*,*) 'xxx Input file not found!'
       endif

       !--- read sounding file till end
       read(fid,*) SFC_PRES, SFC_THETA, SFC_QV

       if( IO_L ) write(IO_FID_LOG,*) '+++ Surface pressure [hPa]',     SFC_PRES
       if( IO_L ) write(IO_FID_LOG,*) '+++ Surface pot. temp  [K]',     SFC_THETA
       if( IO_L ) write(IO_FID_LOG,*) '+++ Surface water vapor [g/kg]', SFC_QV

       do k = 2, EXP_klim
          read(fid,*,iostat=ierr) EXP_z(k), EXP_pott(k), EXP_qv(k), EXP_u(k), EXP_v(k)
          if ( ierr /= 0 ) exit
       enddo

       EXP_kmax = k - 1
    close(fid)

    ! Boundary
    EXP_z   (1)          = 0.0_RP
    EXP_pott(1)          = SFC_THETA
    EXP_qv  (1)          = SFC_QV
    EXP_u   (1)          = EXP_u   (2)
    EXP_v   (1)          = EXP_v   (2)
    EXP_z   (EXP_kmax+1) = 100.E3_RP
    EXP_pott(EXP_kmax+1) = EXP_pott(EXP_kmax)
    EXP_qv  (EXP_kmax+1) = EXP_qv  (EXP_kmax)
    EXP_u   (EXP_kmax+1) = EXP_u   (EXP_kmax)
    EXP_v   (EXP_kmax+1) = EXP_v   (EXP_kmax)

    do k = 1, EXP_kmax+1
       EXP_qv(k) = EXP_qv(k) * 1.E-3_RP ! [g/kg]->[kg/kg]
    enddo

    ! calc in dry condition
    pres_sfc(1,1,1) = SFC_PRES * 1.E2_RP ! [hPa]->[Pa]
    pott_sfc(1,1,1) = SFC_THETA
    qv_sfc  (1,1,1) = SFC_QV * 1.E-3_RP ! [g/kg]->[kg/kg]
    qc_sfc  (1,1,1) = 0.0_RP

    !--- linear interpolate to model grid
    do k = KS, KE
       qc(k,1,1) = 0.0_RP

       do kref = 2, EXP_kmax+1
          if (       GRID_CZ(k) >  EXP_z(kref-1) &
               .AND. GRID_CZ(k) <= EXP_z(kref  ) ) then

             fact1 = ( EXP_z(kref) - GRID_CZ(k)   ) / ( EXP_z(kref)-EXP_z(kref-1) )
             fact2 = ( GRID_CZ(k) - EXP_z(kref-1) ) / ( EXP_z(kref)-EXP_z(kref-1) )

             pott(k,1,1) = EXP_pott(kref-1) * fact1 &
                         + EXP_pott(kref  ) * fact2
             qv  (k,1,1) = EXP_qv  (kref-1) * fact1 &
                         + EXP_qv  (kref  ) * fact2
             velx(k,1,1) = EXP_u   (kref-1) * fact1 &
                         + EXP_u   (kref  ) * fact2
             vely(k,1,1) = EXP_v   (kref-1) * fact1 &
                         + EXP_v   (kref  ) * fact2
          endif
       enddo
    enddo

    ! make density & pressure profile in moist condition
    call HYDROSTATIC_buildrho( DENS    (:,1,1), & ! [OUT]
                               temp    (:,1,1), & ! [OUT]
                               pres    (:,1,1), & ! [OUT]
                               pott    (:,1,1), & ! [IN]
                               qv      (:,1,1), & ! [IN]
                               qc      (:,1,1), & ! [IN]
                               temp_sfc(1,1,1), & ! [OUT]
                               pres_sfc(1,1,1), & ! [IN]
                               pott_sfc(1,1,1), & ! [IN]
                               qv_sfc  (1,1,1), & ! [IN]
                               qc_sfc  (1,1,1)  ) ! [IN]

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       DENS(k,i,j) = DENS(k,1,1)
       MOMZ(k,i,j) = 0.0_RP
       MOMX(k,i,j) = DENS(k,1,1) * velx(k,1,1)
       MOMY(k,i,j) = DENS(k,1,1) * vely(k,1,1)

       ! make warm bubble
       RHOT(k,i,j) = DENS(k,1,1) * ( pott(k,1,1) + BBL_THETA * bubble(k,i,j) )

       QTRC(k,i,j,I_QV) = qv(k,1,1)
    enddo
    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
       SFLX_rain(i,j) = 0.0_RP
       SFLX_snow(i,j) = 0.0_RP
    enddo
    enddo

    return
  end subroutine MKINIT_supercell

  !-----------------------------------------------------------------------------
  !> Make initial state for squallline experiment
  subroutine MKINIT_squallline
    implicit none

    character(len=H_LONG) :: ENV_IN_SOUNDING_file = ''

    real(RP) :: RANDOM_THETA =  0.01_RP
    real(RP) :: OFFSET_velx  = 12.0_RP
    real(RP) :: OFFSET_vely  = -2.0_RP

    NAMELIST / PARAM_MKINIT_SQUALLLINE / &
       ENV_IN_SOUNDING_file, &
       RANDOM_THETA,         &
       OFFSET_velx,          &
       OFFSET_vely

    integer, parameter :: EXP_klim = 100
    integer            :: EXP_kmax

    real(RP) :: SFC_THETA          ! surface potential temperature [K]
    real(RP) :: SFC_PRES           ! surface pressure [hPa]
    real(RP) :: SFC_QV             ! surface watervapor [g/kg]

    real(RP) :: EXP_z   (EXP_klim) ! height      [m]
    real(RP) :: EXP_pott(EXP_klim) ! potential temperature [K]
    real(RP) :: EXP_qv  (EXP_klim) ! water vapor [g/kg]
    real(RP) :: EXP_u   (EXP_klim) ! velocity u  [m/s]
    real(RP) :: EXP_v   (EXP_klim) ! velocity v  [m/s]

    real(RP) :: fact1, fact2

    integer :: ierr, fid
    integer :: k, i, j, kref
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[WARMBUBBLE]/Categ[INIT]'

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_SQUALLLINE,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_SQUALLLINE. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_SQUALLLINE)

    !--- prepare sounding profile
    if( IO_L ) write(IO_FID_LOG,*) '+++ Input sounding file:', trim(ENV_IN_SOUNDING_file)
    fid = IO_get_available_fid()
    open( fid,                                 &
          file   = trim(ENV_IN_SOUNDING_file), &
          form   = 'formatted',                &
          status = 'old',                      &
          iostat = ierr                        )

       if ( ierr /= 0 ) then
          if( IO_L ) write(*,*) 'xxx Input file not found!'
       endif

       !--- read sounding file till end
       read(fid,*) SFC_PRES, SFC_THETA, SFC_QV

       if( IO_L ) write(IO_FID_LOG,*) '+++ Surface pressure [hPa]',     SFC_PRES
       if( IO_L ) write(IO_FID_LOG,*) '+++ Surface pot. temp  [K]',     SFC_THETA
       if( IO_L ) write(IO_FID_LOG,*) '+++ Surface water vapor [g/kg]', SFC_QV

       do k = 2, EXP_klim
          read(fid,*,iostat=ierr) EXP_z(k), EXP_pott(k), EXP_qv(k), EXP_u(k), EXP_v(k)
          if ( ierr /= 0 ) exit
       enddo

       EXP_kmax = k - 1
    close(fid)

    ! Boundary
    EXP_z   (1)          = 0.0_RP
    EXP_pott(1)          = SFC_THETA
    EXP_qv  (1)          = SFC_QV
    EXP_u   (1)          = EXP_u   (2)
    EXP_v   (1)          = EXP_v   (2)
    EXP_z   (EXP_kmax+1) = 100.E3_RP
    EXP_pott(EXP_kmax+1) = EXP_pott(EXP_kmax)
    EXP_qv  (EXP_kmax+1) = EXP_qv  (EXP_kmax)
    EXP_u   (EXP_kmax+1) = EXP_u   (EXP_kmax)
    EXP_v   (EXP_kmax+1) = EXP_v   (EXP_kmax)

    do k = 1, EXP_kmax+1
       EXP_qv(k) = EXP_qv(k) * 1.E-3_RP ! [g/kg]->[kg/kg]
    enddo

    ! calc in dry condition
    pres_sfc(1,1,1) = SFC_PRES * 1.E2_RP ! [hPa]->[Pa]
    pott_sfc(1,1,1) = SFC_THETA
    qv_sfc  (1,1,1) = SFC_QV * 1.E-3_RP ! [g/kg]->[kg/kg]
    qc_sfc  (1,1,1) = 0.0_RP

    !--- linear interpolate to model grid
    do k = KS, KE
       qc(k,1,1) = 0.0_RP

       do kref = 2, EXP_kmax+1
          if (       GRID_CZ(k) >  EXP_z(kref-1) &
               .AND. GRID_CZ(k) <= EXP_z(kref  ) ) then

             fact1 = ( EXP_z(kref) - GRID_CZ(k)   ) / ( EXP_z(kref)-EXP_z(kref-1) )
             fact2 = ( GRID_CZ(k) - EXP_z(kref-1) ) / ( EXP_z(kref)-EXP_z(kref-1) )

             pott(k,1,1) = EXP_pott(kref-1) * fact1 &
                         + EXP_pott(kref  ) * fact2
             qv  (k,1,1) = EXP_qv  (kref-1) * fact1 &
                         + EXP_qv  (kref  ) * fact2
             velx(k,1,1) = EXP_u   (kref-1) * fact1 &
                         + EXP_u   (kref  ) * fact2
             vely(k,1,1) = EXP_v   (kref-1) * fact1 &
                         + EXP_v   (kref  ) * fact2
          endif
       enddo
    enddo

    ! make density & pressure profile in moist condition
    call HYDROSTATIC_buildrho( DENS    (:,1,1), & ! [OUT]
                               temp    (:,1,1), & ! [OUT]
                               pres    (:,1,1), & ! [OUT]
                               pott    (:,1,1), & ! [IN]
                               qv      (:,1,1), & ! [IN]
                               qc      (:,1,1), & ! [IN]
                               temp_sfc(1,1,1), & ! [OUT]
                               pres_sfc(1,1,1), & ! [IN]
                               pott_sfc(1,1,1), & ! [IN]
                               qv_sfc  (1,1,1), & ! [IN]
                               qc_sfc  (1,1,1)  ) ! [IN]

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       DENS(k,i,j) = DENS(k,1,1)
       MOMZ(k,i,j) = 0.0_RP
       MOMX(k,i,j) = ( velx(k,1,1) - OFFSET_velx ) * DENS(k,1,1)
       MOMY(k,i,j) = ( vely(k,1,1) - OFFSET_vely ) * DENS(k,1,1)
       RHOT(k,i,j) = DENS(k,1,1) * ( pott(k,1,1) + rndm(k,i,j) * RANDOM_THETA )

       QTRC(k,i,j,I_QV) = qv(k,1,1)
    enddo
    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
       SFLX_rain(i,j) = 0.0_RP
       SFLX_snow(i,j) = 0.0_RP
    enddo
    enddo

    return
  end subroutine MKINIT_squallline

  !-----------------------------------------------------------------------------
  !> Make initial state by Weisman and Klemp (1982)
  subroutine MKINIT_wk1982
    implicit none

    ! Surface state
    real(RP) :: SFC_THETA = 300.0_RP   ! surface pot. temperature [K]
    real(RP) :: SFC_PRES               ! surface pressure         [Pa]
    ! Parameter in Weisman and Klemp (1982)
    real(RP) :: TR_Z      = 12000.0_RP ! height           of tropopause  [m]
    real(RP) :: TR_THETA  =   343.0_RP ! pot. temperature at tropopause  [K]
    real(RP) :: TR_TEMP   =   213.0_RP ! temperature      at tropopause  [K]
    real(RP) :: SHEAR_Z   =  3000.0_RP ! center height of shear layer    [m]
    real(RP) :: SHEAR_U   =    15.0_RP ! velocity u over the shear layer [m/s]
    ! Bubble
    real(RP) :: BBL_THETA = 3.D0 ! extremum of temperature in bubble [K]

    NAMELIST / PARAM_MKINIT_WK1982 / &
       SFC_THETA, &
       SFC_PRES,  &
       TR_Z,      &
       TR_THETA,  &
       TR_TEMP,   &
       SHEAR_Z,   &
       SHEAR_U,   &
       BBL_THETA

    real(RP) :: rh    (KA,IA,JA)
    real(RP) :: rh_sfc(1 ,IA,JA)

    integer :: ierr
    integer :: k, i, j, iq
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[WK1982)]/Categ[MKINIT]'

    SFC_PRES  = Pstd

    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_WK1982,iostat=ierr)
    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_WK1982. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_WK1982)

    ! calc in dry condition
    do j = JS, JE
    do i = IS, IE
       pres_sfc(1,i,j) = SFC_PRES
       pott_sfc(1,i,j) = SFC_THETA
       qv_sfc  (1,i,j) = 0.0_RP
       qc_sfc  (1,i,j) = 0.0_RP

       do k = KS, KE
          if ( REAL_CZ(k,i,j) <= TR_Z ) then ! below initial cloud top
             pott(k,i,j) = pott_sfc(1,i,j) &
                         + ( TR_THETA - pott_sfc(1,i,j) ) * ( REAL_CZ(k,i,j) / TR_Z )**1.25_RP
          else
             pott(k,i,j) = TR_THETA * exp( GRAV * ( REAL_CZ(k,i,j) - TR_Z ) / CPdry / TR_TEMP )
          endif

          qv(k,i,j) = 0.0_RP
          qc(k,i,j) = 0.0_RP
       enddo
    enddo
    enddo

    ! make density & pressure profile in dry condition
    call HYDROSTATIC_buildrho( DENS    (:,:,:), & ! [OUT]
                               temp    (:,:,:), & ! [OUT]
                               pres    (:,:,:), & ! [OUT]
                               pott    (:,:,:), & ! [IN]
                               qv      (:,:,:), & ! [IN]
                               qc      (:,:,:), & ! [IN]
                               temp_sfc(:,:,:), & ! [OUT]
                               pres_sfc(:,:,:), & ! [IN]
                               pott_sfc(:,:,:), & ! [IN]
                               qv_sfc  (:,:,:), & ! [IN]
                               qc_sfc  (:,:,:)  ) ! [IN]

    ! calc QV from RH
    do j = JS, JE
    do i = IS, IE
       rh_sfc(1,i,j) = 1.0_RP - 0.75_RP * ( REAL_FZ(KS-1,i,j) / TR_Z )**1.25_RP

       do k = KS, KE
          if ( REAL_CZ(k,i,j) <= TR_Z ) then ! below initial cloud top
             rh(k,i,j) = 1.0_RP - 0.75_RP * ( REAL_CZ(k,i,j) / TR_Z )**1.25_RP
          else
             rh(k,i,j) = 0.25_RP
          endif
       enddo
    enddo
    enddo

    call SATURATION_pres2qsat_all( qsat_sfc(1,:,:), temp_sfc(1,:,:), pres_sfc(1,:,:) )
    call SATURATION_pres2qsat_all( qsat    (:,:,:), temp    (:,:,:), pres    (:,:,:) )

    do j = JS, JE
    do i = IS, IE
       qv_sfc(1,i,j) = rh_sfc(1,i,j) * qsat_sfc(1,i,j)
       do k = KS, KE
          qv(k,i,j) = rh(k,i,j) * qsat(k,i,j)
       enddo
    enddo
    enddo

    ! make density & pressure profile in moist condition
    call HYDROSTATIC_buildrho( DENS    (:,:,:), & ! [OUT]
                               temp    (:,:,:), & ! [OUT]
                               pres    (:,:,:), & ! [OUT]
                               pott    (:,:,:), & ! [IN]
                               qv      (:,:,:), & ! [IN]
                               qc      (:,:,:), & ! [IN]
                               temp_sfc(:,:,:), & ! [OUT]
                               pres_sfc(:,:,:), & ! [IN]
                               pott_sfc(:,:,:), & ! [IN]
                               qv_sfc  (:,:,:), & ! [IN]
                               qc_sfc  (:,:,:)  ) ! [IN]

do k = KS, KE
   if( IO_L ) write(IO_FID_LOG,*) k, REAL_CZ(k,IS,JS), pres(k,IS,JS), pott(k,IS,JS), rh(k,IS,JS), qv(k,IS,JS)*1000
enddo

    call COMM_vars8( DENS(:,:,:), 1 )
    call COMM_wait ( DENS(:,:,:), 1 )

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       MOMX(k,i,j) = SHEAR_U * tanh( REAL_CZ(k,i,j) / SHEAR_Z ) &
                   * 0.5_RP * ( DENS(k,i+1,j) + DENS(k,i,j) )
    enddo
    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       MOMY(k,i,j) = 0.0_RP
       MOMZ(k,i,j) = 0.0_RP
       RHOT(k,i,j) = pott(k,i,j) * DENS(k,i,j)

       ! make warm bubble
       RHOT(k,i,j) = DENS(k,i,j) * ( pott(k,i,j) + BBL_THETA * bubble(k,i,j) )

       QTRC(k,i,j,I_QV) = qv(k,i,j)
    enddo
    enddo
    enddo

    if ( QA >= 2 ) then
       do iq = 2, QA
       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          QTRC(k,i,j,iq) = 0.0_RP
       enddo
       enddo
       enddo
       enddo
    endif

    do j = JS, JE
    do i = IS, IE
       SFLX_rain(i,j) = 0.0_RP
       SFLX_snow(i,j) = 0.0_RP
    enddo
    enddo

    return
  end subroutine MKINIT_wk1982

  !-----------------------------------------------------------------------------
  !> Make initial state for stratocumulus
  subroutine MKINIT_DYCOMS2_RF01
    implicit none

    real(RP) :: PERTURB_AMP = 0.0_RP
    integer  :: RANDOM_LIMIT = 5
    integer  :: RANDOM_FLAG  = 0       ! 0 -> no perturbation
                                       ! 1 -> petrurbation for pt
                                       ! 2 -> perturbation for u, v, w
    logical  :: USE_LWSET    = .false. ! use liq. water. static energy temp.?

    NAMELIST / PARAM_MKINIT_RF01 / &
       PERTURB_AMP,     &
       RANDOM_LIMIT,    &
       RANDOM_FLAG,     &
       USE_LWSET

    real(RP) :: potl(KA,IA,JA) ! liquid potential temperature

    real(RP) :: qall ! QV+QC
    real(RP) :: fact
    real(RP) :: pi2
    real(RP) :: sint
    real(RP) :: GEOP_sw ! switch for geopotential energy correction

    integer :: ierr
    integer :: k, i, j, iq
    !---------------------------------------------------------------------------

    pi2 = atan(1.0_RP) * 2.0_RP ! pi/2

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[DYCOMS2_RF01)]/Categ[MKINIT]'

    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_RF01,iostat=ierr)
    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_RF01. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_RF01)

    if ( USE_LWSET ) then
       GEOP_sw = 1.0_RP
    else
       GEOP_sw = 0.0_RP
    endif

    ! calc in dry condition
    do j = JS, JE
    do i = IS, IE

       pres_sfc(1,i,j) = 1017.8E2_RP ! [Pa]
       pott_sfc(1,i,j) = 289.0_RP    ! [K]
       qv_sfc  (1,i,j) = 0.0_RP
       qc_sfc  (1,i,j) = 0.0_RP

       do k = KS, KE
          velx(k,i,j) =   7.0_RP
          vely(k,i,j) =  -5.5_RP
          if ( GRID_CZ(k) < 820.0_RP ) then ! below initial cloud top
             potl(k,i,j) = 289.0_RP - GRAV / CPdry * GRID_CZ(k) * GEOP_sw
          elseif( GRID_CZ(k) <= 860.0_RP ) then
             sint = sin( pi2 * ( GRID_CZ(k)-840.0_RP ) / 20.0_RP ) * 0.5_RP
             potl(k,i,j) = ( 289.0_RP - GRAV / CPdry * GRID_CZ(k) * GEOP_sw                          ) * (0.5_RP-sint) &
                         + ( 297.5_RP+sign(abs(GRID_CZ(k)-840.0_RP)**(1.0_RP/3.0_RP),GRID_CZ(k)-840.0_RP) &
                           - GRAV / CPdry * GRID_CZ(k) * GEOP_sw                                     ) * (0.5_RP+sint)
          else
             potl(k,i,j) = 297.5_RP + ( GRID_CZ(k)-840.0_RP )**(1.0_RP/3.0_RP) &
                         - GRAV / CPdry * GRID_CZ(k) * GEOP_sw
          endif

          qv(k,i,j) = 0.0_RP
          qc(k,i,j) = 0.0_RP
       enddo

    enddo
    enddo

    ! make density & pressure profile in dry condition
    call HYDROSTATIC_buildrho( DENS    (:,:,:), & ! [OUT]
                               temp    (:,:,:), & ! [OUT]
                               pres    (:,:,:), & ! [OUT]
                               potl    (:,:,:), & ! [IN]
                               qv      (:,:,:), & ! [IN]
                               qc      (:,:,:), & ! [IN]
                               temp_sfc(:,:,:), & ! [OUT]
                               pres_sfc(:,:,:), & ! [IN]
                               pott_sfc(:,:,:), & ! [IN]
                               qv_sfc  (:,:,:), & ! [IN]
                               qc_sfc  (:,:,:)  ) ! [IN]

    ! calc in moist condition
    do j = JS, JE
    do i = IS, IE
       qv_sfc  (1,i,j) = 9.0E-3_RP   ! [kg/kg]
       qc_sfc  (1,i,j) = 0.0_RP

       do k = KS, KE
          if    ( GRID_CZ(k) <   820.0_RP ) then ! below initial cloud top
             qall = 9.0E-3_RP
          elseif( GRID_CZ(k) <=  860.0_RP ) then ! boundary
             sint = sin( pi2 * ( GRID_CZ(k)-840.0_RP ) / 20.0_RP ) * 0.5_RP
             qall = 9.0E-3_RP * (0.5_RP-sint) &
                         + 1.5E-3_RP * (0.5_RP+sint)
          elseif( GRID_CZ(k) <= 5000.0_RP ) then
             qall = 1.5E-3_RP
          else
             qall = 0.0_RP
          endif

          if    ( GRID_CZ(k) <=  600.0_RP ) then
             qc(k,i,j) = 0.0_RP
          elseif( GRID_CZ(k) < 820.0_RP ) then ! in the cloud
             fact = ( GRID_CZ(k)-600.0_RP ) / ( 840.0_RP-600.0_RP )
             qc(k,i,j) = 0.45E-3_RP * fact
          elseif( GRID_CZ(k) <= 860.0_RP ) then ! boundary
             sint = sin( pi2 * ( GRID_CZ(k)-840.0_RP ) / 20.0_RP ) * 0.5_RP
             fact = ( GRID_CZ(k)-600.0_RP ) / ( 840.0_RP-600.0_RP )
             qc(k,i,j) = 0.45E-3_RP * fact * (0.5_RP-sint)
          else
             qc(k,i,j) = 0.0_RP
          endif

          qv(k,i,j) = qall - qc(k,i,j)
       enddo

    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       temp(k,i,j) = temp(k,i,j) + LH0 / CPdry * qc(k,i,j)
    enddo
    enddo
    enddo

    ! make density & pressure profile in moist condition
    call HYDROSTATIC_buildrho_bytemp( DENS    (:,:,:), & ! [OUT]
                                      pott    (:,:,:), & ! [OUT]
                                      pres    (:,:,:), & ! [OUT]
                                      temp    (:,:,:), & ! [IN]
                                      qv      (:,:,:), & ! [IN]
                                      qc      (:,:,:), & ! [IN]
                                      pott_sfc(:,:,:), & ! [OUT]
                                      pres_sfc(:,:,:), & ! [IN]
                                      temp_sfc(:,:,:), & ! [IN]
                                      qv_sfc  (:,:,:), & ! [IN]
                                      qc_sfc  (:,:,:)  ) ! [IN]

    do j  = JS, JE
    do i  = IS, IE
       DENS(   1:KS-1,i,j) = DENS(KS,i,j)
       DENS(KE+1:KA,  i,j) = DENS(KE,i,j)
    enddo
    enddo

    call COMM_vars8( DENS(:,:,:), 1 )
    call COMM_wait ( DENS(:,:,:), 1 )

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       if ( RANDOM_FLAG == 2 .and. k <= RANDOM_LIMIT ) then ! below initial cloud top
          MOMZ(k,i,j) = ( 2.0_RP * ( rndm(k,i,j)-0.5_RP ) * PERTURB_AMP ) &
                      * 0.5_RP * ( DENS(k+1,i,j) + DENS(k,i,j) )
       else
          MOMZ(k,i,j) = 0.0_RP
       endif
    enddo
    enddo
    enddo

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       if ( RANDOM_FLAG == 2 .AND. k <= RANDOM_LIMIT ) then ! below initial cloud top
          MOMX(k,i,j) = ( velx(k,i,j) + 2.0_RP * ( rndm(k,i,j)-0.5_RP ) * PERTURB_AMP ) &
                      * 0.5_RP * ( DENS(k,i+1,j) + DENS(k,i,j) )
       else
          MOMX(k,i,j) = velx(k,i,j) * 0.5_RP * ( DENS(k,i+1,j) + DENS(k,i,j) )
       endif
    enddo
    enddo
    enddo

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       if ( RANDOM_FLAG == 2 .AND. k <= RANDOM_LIMIT ) then ! below initial cloud top
          MOMY(k,i,j) = ( vely(k,i,j) + 2.0_RP * ( rndm(k,i,j)-0.5_RP ) * PERTURB_AMP ) &
                      * 0.5_RP * ( DENS(k,i,j+1) + DENS(k,i,j) )
       else
          MOMY(k,i,j) = vely(k,i,j) * 0.5_RP * ( DENS(k,i,j+1) + DENS(k,i,j) )
       endif
    enddo
    enddo
    enddo

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       if ( RANDOM_FLAG == 1 .and. k <= RANDOM_LIMIT ) then ! below initial cloud top
          RHOT(k,i,j) = ( pott(k,i,j) + 2.0_RP * ( rndm(k,i,j)-0.5_RP ) * PERTURB_AMP ) &
                      * DENS(k,i,j)
       else
          RHOT(k,i,j) = pott(k,i,j) * DENS(k,i,j)
       endif
    enddo
    enddo
    enddo

    if ( flg_bin ) then
       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          QTRC(k,i,j,I_QV) = qv(k,i,j) + qc(k,i,j) !--- Super saturated air at initial
          do iq = QQA+1, QA
            QTRC(k,i,j,iq) = QTRC(k,i,j,iq) / DENS(k,i,j)
          enddo
       enddo
       enddo
       enddo
    else
       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          QTRC(k,i,j,I_QV) = qv(k,i,j)
          QTRC(k,i,j,I_QC) = qc(k,i,j)
       enddo
       enddo
       enddo

       if ( I_NC > 0 ) then
          do j = JS, JE
          do i = IS, IE
          do k = KS, KE
             if ( qc(k,i,j) > 0.0_RP ) then
                QTRC(k,i,j,I_NC) = 120.E6_RP / DENS(k,i,j) ! [number/m3] / [kg/m3]
             endif
          enddo
          enddo
          enddo
       endif
    endif

    return
  end subroutine MKINIT_DYCOMS2_RF01

  !-----------------------------------------------------------------------------
  !> Make initial state for stratocumulus
  subroutine MKINIT_DYCOMS2_RF02
    implicit none

    real(RP) :: PERTURB_AMP  = 0.0_RP
    integer  :: RANDOM_LIMIT = 5
    integer  :: RANDOM_FLAG  = 0 ! 0 -> no perturbation
                                 ! 1 -> perturbation for PT
                                 ! 2 -> perturbation for u,v,w

    NAMELIST / PARAM_MKINIT_RF02 / &
       PERTURB_AMP,     &
       RANDOM_LIMIT,    &
       RANDOM_FLAG

    real(RP) :: potl(KA,IA,JA) ! liquid potential temperature

    real(RP) :: qall ! QV+QC
    real(RP) :: fact
    real(RP) :: pi2
    real(RP) :: sint

    integer :: ierr
    integer :: k, i, j, iq
    !---------------------------------------------------------------------------

    pi2 = atan(1.0_RP) * 2.0_RP  ! pi/2
    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[DYCOMS2_RF02)]/Categ[MKINIT]'

    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_RF02,iostat=ierr)
    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_RF02. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_RF02)

    ! calc in dry condition
    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE

       pres_sfc(1,i,j) = 1017.8E2_RP   ! [Pa]
       pott_sfc(1,i,j) = 288.3_RP      ! [K]
       qv_sfc(1,i,j) = 0.0_RP
       qc_sfc(1,i,j) = 0.0_RP

       do k = KS, KE
          velx(k,i,j) =  3.0_RP + 4.3 * GRID_CZ(k)*1.E-3_RP
          vely(k,i,j) = -9.0_RP + 5.6 * GRID_CZ(k)*1.E-3_RP

          if ( GRID_CZ(k) < 775.0_RP ) then ! below initial cloud top
             potl(k,i,j) = 288.3_RP ! [K]
          else if ( GRID_CZ(k) <= 815.0_RP ) then
             sint = sin( pi2 * (GRID_CZ(k) - 795.0_RP)/20.0_RP )
             potl(k,i,j) = 288.3_RP * (1.0_RP-sint)*0.5_RP &
                         + ( 295.0_RP+sign(abs(GRID_CZ(k)-795.0_RP)**(1.0_RP/3.0_RP),GRID_CZ(k)-795.0_RP) ) &
                         * (1.0_RP+sint)*0.5_RP
          else
             potl(k,i,j) = 295.0_RP + ( GRID_CZ(k)-795.0_RP )**(1.0_RP/3.0_RP)
          endif

          qv(k,i,j) = 0.0_RP
          qc(k,i,j) = 0.0_RP
       enddo
    enddo
    enddo

    ! make density & pressure profile in dry condition
    call HYDROSTATIC_buildrho( DENS    (:,:,:), & ! [OUT]
                               temp    (:,:,:), & ! [OUT]
                               pres    (:,:,:), & ! [OUT]
                               potl    (:,:,:), & ! [IN]
                               qv      (:,:,:), & ! [IN]
                               qc      (:,:,:), & ! [IN]
                               temp_sfc(:,:,:), & ! [OUT]
                               pres_sfc(:,:,:), & ! [IN]
                               pott_sfc(:,:,:), & ! [IN]
                               qv_sfc  (:,:,:), & ! [IN]
                               qc_sfc  (:,:,:)  ) ! [IN]

    ! calc in moist condition
    do j = JS, JE
    do i = IS, IE
       qv_sfc  (1,i,j) = 9.45E-3_RP
       qc_sfc  (1,i,j) = 0.0_RP

       do k = KS, KE
          if ( GRID_CZ(k) < 775.0_RP ) then ! below initial cloud top
             qall = 9.45E-3_RP ! [kg/kg]
          else if ( GRID_CZ(k) <= 815.0_RP ) then
             sint = sin( pi2 * (GRID_CZ(k) - 795.0_RP)/20.0_RP )
             qall = 9.45E-3_RP * (1.0_RP-sint)*0.5_RP + &
                   ( 5.E-3_RP - 3.E-3_RP * ( 1.0_RP - exp( (795.0_RP-GRID_CZ(k))/500.0_RP ) ) ) * (1.0_RP+sint)*0.5_RP
          else
             qall = 5.E-3_RP - 3.E-3_RP * ( 1.0_RP - exp( (795.0_RP-GRID_CZ(k))/500.0_RP ) ) ! [kg/kg]
          endif

          if( GRID_CZ(k) < 400.0_RP ) then
             qc(k,i,j) = 0.0_RP
          elseif( GRID_CZ(k) < 775.0_RP ) then
             fact = ( GRID_CZ(k)-400.0_RP ) / ( 795.0_RP-400.0_RP )
             qc(k,i,j) = 0.65E-3_RP * fact
          elseif( GRID_CZ(k) <= 815.0_RP ) then
             sint = sin( pi2 * ( GRID_CZ(k)-795.0_RP )/20.0_RP )
             fact = ( GRID_CZ(k)-400.0_RP ) / ( 795.0_RP-400.0_RP )
             qc(k,i,j) = 0.65E-3_RP * fact * (1.0_RP-sint) * 0.5_RP
          else
             qc(k,i,j) = 0.0_RP
          endif
          qv(k,i,j) = qall - qc(k,i,j)
       enddo

    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       temp(k,i,j) = temp(k,i,j) + LH0 / CPdry * qc(k,i,j)
    enddo
    enddo
    enddo

    ! make density & pressure profile in moist condition
    call HYDROSTATIC_buildrho_bytemp( DENS    (:,:,:), & ! [OUT]
                                      pott    (:,:,:), & ! [OUT]
                                      pres    (:,:,:), & ! [OUT]
                                      temp    (:,:,:), & ! [IN]
                                      qv      (:,:,:), & ! [IN]
                                      qc      (:,:,:), & ! [IN]
                                      pott_sfc(:,:,:), & ! [OUT]
                                      pres_sfc(:,:,:), & ! [IN]
                                      temp_sfc(:,:,:), & ! [IN]
                                      qv_sfc  (:,:,:), & ! [IN]
                                      qc_sfc  (:,:,:)  ) ! [IN]

    do j  = JS, JE
    do i  = IS, IE
       DENS(   1:KS-1,i,j) = DENS(KS,i,j)
       DENS(KE+1:KA,  i,j) = DENS(KE,i,j)
    enddo
    enddo

    call COMM_vars8( DENS(:,:,:), 1 )
    call COMM_wait ( DENS(:,:,:), 1 )

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
     if( RANDOM_FLAG == 2 .and. k <= RANDOM_LIMIT ) then
       MOMZ(k,i,j) = ( 0.0_RP + 2.0_RP * ( rndm(k,i,j)-0.50_RP ) * PERTURB_AMP ) &
                   * 0.5_RP * ( DENS(k+1,i,j) + DENS(k,i,j) )
     else
       MOMZ(k,i,j) = 0.0_RP
     endif
    enddo
    enddo
    enddo

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
     if( RANDOM_FLAG == 2 .and. k <= RANDOM_LIMIT ) then
       MOMX(k,i,j) = ( velx(k,i,j) + 2.0_RP * ( rndm(k,i,j)-0.50_RP ) * PERTURB_AMP ) &
                   * 0.5_RP * ( DENS(k,i+1,j) + DENS(k,i,j) )
     else
       MOMX(k,i,j) = ( velx(k,i,j) ) * 0.5_RP * ( DENS(k,i+1,j) + DENS(k,i,j) )
     endif
    enddo
    enddo
    enddo

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
     if( RANDOM_FLAG == 2 .and. k <= RANDOM_LIMIT ) then
       MOMY(k,i,j) = ( vely(k,i,j) + 2.0_RP * ( rndm(k,i,j)-0.50_RP ) * PERTURB_AMP ) &
                   * 0.5_RP * ( DENS(k,i,j+1) + DENS(k,i,j) )
     else
       MOMY(k,i,j) = vely(k,i,j) * 0.5_RP * ( DENS(k,i,j+1) + DENS(k,i,j) )
     endif
    enddo
    enddo
    enddo

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
     if( RANDOM_FLAG == 1 .and. k <= RANDOM_LIMIT ) then
       RHOT(k,i,j) = ( pott(k,i,j) + 2.0_RP * ( rndm(k,i,j)-0.50_RP ) * PERTURB_AMP ) &
                   * DENS(k,i,j)
     else
       RHOT(k,i,j) = pott(k,i,j) * DENS(k,i,j)
     endif
    enddo
    enddo
    enddo

    if ( flg_bin ) then
       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          !--- Super saturated air at initial
          QTRC(k,i,j,I_QV) = qv(k,i,j) + qc(k,i,j)
          do iq = QQA+1, QA
            QTRC(k,i,j,iq) = QTRC(k,i,j,iq) / DENS(k,i,j)
          enddo
       enddo
       enddo
       enddo
    else
       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          QTRC(k,i,j,I_QV) = qv(k,i,j)
          QTRC(k,i,j,I_QC) = qc(k,i,j)
       enddo
       enddo
       enddo

       if ( I_NC > 0 ) then
          do j = JS, JE
          do i = IS, IE
          do k = KS, KE
             if ( qc(k,i,j) > 0.0_RP ) then
                QTRC(k,i,j,I_NC) = 55.0E6_RP / DENS(k,i,j) ! [number/m3] / [kg/m3]
             endif
          enddo
          enddo
          enddo
       endif
    endif

    return
  end subroutine MKINIT_DYCOMS2_RF02

  !-----------------------------------------------------------------------------
  !> Make initial state for stratocumulus
  subroutine MKINIT_DYCOMS2_RF02_DNS
    implicit none

    real(RP) :: ZB  = 750.0_RP ! domain bottom
!   real(RP) :: ZT  = 900.0_RP ! domain top
    real(RP) :: CONST_U = 0.0_RP
    real(RP) :: CONST_V = 0.0_RP
    real(RP) :: PRES_ZB = 93060.0_RP
    real(RP) :: PERTURB_AMP  = 0.0_RP
    integer  :: RANDOM_LIMIT = 5
    integer  :: RANDOM_FLAG  = 0 ! 0 -> no perturbation
                                 ! 1 -> perturbation for PT
                                 ! 2 -> perturbation for u,v,w

    NAMELIST / PARAM_MKINIT_RF02_DNS / &
       ZB, CONST_U, CONST_V,PRES_ZB,&
       PERTURB_AMP,     &
       RANDOM_LIMIT,    &
       RANDOM_FLAG

    real(RP) :: potl(KA,IA,JA) ! liquid potential temperature

    real(RP) :: qall ! QV+QC
    real(RP) :: fact
    real(RP) :: pi2

    integer :: ierr
    integer :: k, i, j, iq
    !---------------------------------------------------------------------------

    pi2 = atan(1.0_RP) * 2.0_RP  ! pi/2
    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[DYCOMS2_RF02_DNS)]/Categ[MKINIT]'

    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_RF02_DNS,iostat=ierr)
    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_RF02_DNS. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_RF02_DNS)

    ! calc in dry condition
    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE

       pres_sfc(1,i,j) = PRES_ZB
!      pott_sfc(1,i,j) = 288.3_RP      ! [K]
!      qv_sfc  (1,i,j) = 9.45E-3_RP
!      qc_sfc  (1,i,j) = 0.0_RP

       do k = KS, KE

          velx(k,i,j) = CONST_U
          vely(k,i,j) = CONST_V

!         if ( ZB+GRID_CZ(k) < 775.0_RP ) then ! below initial cloud top
          if ( ZB+GRID_CZ(k) <= 795.0_RP ) then ! below initial cloud top
             potl(k,i,j) = 288.3_RP ! [K]
             qall = 9.45E-3_RP ! [kg/kg]
! necessary?
!         else if ( GRID_CZ(k) <= 815.0_RP ) then
!            sint = sin( pi2 * (GRID_CZ(k) - 795.0_RP)/20.0_RP )
!            potl(k,i,j) = 288.3_RP * (1.0_RP-sint)*0.5_RP + &
!                  ( 295.0_RP+sign(abs(GRID_CZ(k)-795.0_RP)**(1.0_RP/3.0_RP),GRID_CZ(k)-795.0_RP) ) * (1.0_RP+sint)*0.5_RP
!            qall = 9.45E-3_RP * (1.0_RP-sint)*0.5_RP + &
!                  ( 5.E-3_RP - 3.E-3_RP * ( 1.0_RP - exp( (795.0_RP-GRID_CZ(k))/500.0_RP ) ) ) * (1.0_RP+sint)*0.5_RP
          else
             potl(k,i,j) = 295.0_RP + ( zb+GRID_CZ(k)-795.0_RP )**(1.0_RP/3.0_RP)
             qall = 5.E-3_RP - 3.E-3_RP * ( 1.0_RP - exp( (795.0_RP-(zb+GRID_CZ(k)))/500.0_RP ) ) ! [kg/kg]
          endif

          if( ZB+GRID_CZ(k) < 400.0_RP ) then
             qc(k,i,j) = 0.0_RP
          elseif( ZB+GRID_CZ(k) <= 795.0_RP ) then
             fact = ( (zb+GRID_CZ(k))-400.0_RP ) / ( 795.0_RP-400.0_RP )
             qc(k,i,j) = 0.8E-3_RP * fact
          else
             qc(k,i,j) = 0.0_RP
          endif
          qv(k,i,j) = qall - qc(k,i,j)

!if(i==is.and.j==js)write(*,*)'chkk',k,cz(k)+zb,qc(k,i,j),qv(k,i,j)
       enddo
    enddo
    enddo

!write(*,*)'chk3',ks,ke
    ! extrapolation (temtative)
    pott_sfc(1,:,:) = potl(ks,:,:)-0.5*(potl(ks+1,:,:)-potl(ks,:,:))
    qv_sfc  (1,:,:) = qv  (ks,:,:)-0.5*(qv  (ks+1,:,:)-qv  (ks,:,:))
    qc_sfc  (1,:,:) = qc  (ks,:,:)-0.5*(qc  (ks+1,:,:)-qc  (ks,:,:))

    ! make density & pressure profile in moist condition
    call HYDROSTATIC_buildrho( DENS    (:,:,:), & ! [OUT]
                               temp    (:,:,:), & ! [OUT]
                               pres    (:,:,:), & ! [OUT]
                               potl    (:,:,:), & ! [IN]
                               qv      (:,:,:), & ! [IN]
                               qc      (:,:,:), & ! [IN]
                               temp_sfc(:,:,:), & ! [OUT]
                               pres_sfc(:,:,:), & ! [IN]
                               pott_sfc(:,:,:), & ! [IN]
                               qv_sfc  (:,:,:), & ! [IN]
                               qc_sfc  (:,:,:)  ) ! [IN]

!write(*,*)'chk4.1'
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       pott(k,i,j) = potl(k,i,j) + LH0 / CPdry * qc(k,i,j) * ( P00/pres(k,i,j) )**RovCP
    enddo
    enddo
    enddo

!write(*,*)'chk5'
    ! make density & pressure profile in moist condition
    call HYDROSTATIC_buildrho( DENS    (:,:,:), & ! [OUT]
                               temp    (:,:,:), & ! [OUT]
                               pres    (:,:,:), & ! [OUT]
                               pott    (:,:,:), & ! [IN]
                               qv      (:,:,:), & ! [IN]
                               qc      (:,:,:), & ! [IN]
                               temp_sfc(:,:,:), & ! [OUT]
                               pres_sfc(:,:,:), & ! [IN]
                               pott_sfc(:,:,:), & ! [IN]
                               qv_sfc  (:,:,:), & ! [IN]
                               qc_sfc  (:,:,:)  ) ! [IN]

    do j  = JS, JE
    do i  = IS, IE
       DENS(   1:KS-1,i,j) = DENS(KS,i,j)
       DENS(KE+1:KA,  i,j) = DENS(KE,i,j)
    enddo
    enddo

    call COMM_vars8( DENS(:,:,:), 1 )
    call COMM_wait ( DENS(:,:,:), 1 )

!write(*,*)'chk7'
    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
     if( RANDOM_FLAG == 2 .and. k <= RANDOM_LIMIT ) then
       MOMZ(k,i,j) = ( 0.0_RP + 2.0_RP * ( rndm(k,i,j)-0.50_RP ) * PERTURB_AMP ) &
                   * 0.5_RP * ( DENS(k+1,i,j) + DENS(k,i,j) )
     else
       MOMZ(k,i,j) = 0.0_RP
     endif
    enddo
    enddo
    enddo

!write(*,*)'chk8'
    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
     if( RANDOM_FLAG == 2 .and. k <= RANDOM_LIMIT ) then
       MOMX(k,i,j) = ( velx(k,i,j) + 2.0_RP * ( rndm(k,i,j)-0.50_RP ) * PERTURB_AMP ) &
                   * 0.5_RP * ( DENS(k,i+1,j) + DENS(k,i,j) )
     else
       MOMX(k,i,j) = ( velx(k,i,j) ) * 0.5_RP * ( DENS(k,i+1,j) + DENS(k,i,j) )
     endif
    enddo
    enddo
    enddo
!write(*,*)'chk9'

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
     if( RANDOM_FLAG == 2 .and. k <= RANDOM_LIMIT ) then
       MOMY(k,i,j) = ( vely(k,i,j) + 2.0_RP * ( rndm(k,i,j)-0.50_RP ) * PERTURB_AMP ) &
                   * 0.5_RP * ( DENS(k,i,j+1) + DENS(k,i,j) )
     else
       MOMY(k,i,j) = vely(k,i,j) * 0.5_RP * ( DENS(k,i,j+1) + DENS(k,i,j) )
     endif
    enddo
    enddo
    enddo
!write(*,*)'chk10'

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
     if( RANDOM_FLAG == 1 .and. k <= RANDOM_LIMIT ) then
       RHOT(k,i,j) = ( pott(k,i,j) + 2.0_RP * ( rndm(k,i,j)-0.50_RP ) * PERTURB_AMP ) &
                   * DENS(k,i,j)
     else
       RHOT(k,i,j) = pott(k,i,j) * DENS(k,i,j)
     endif
    enddo
    enddo
    enddo

!write(*,*)'chk11'
    do iq = 1, QA
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       QTRC(k,i,j,iq) = 0.0_RP
    enddo
    enddo
    enddo
    enddo

!write(*,*)'chk12'
    if ( flg_bin ) then
       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          !--- Super saturated air at initial
          QTRC(k,i,j,I_QV) = qv(k,i,j) + qc(k,i,j)

          !--- for aerosol
          do iq = QQA+1, QA
             QTRC(k,i,j,iq) = gan(iq-QQA) / DENS(k,i,j)
          enddo
       enddo
       enddo
       enddo
    else
       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          QTRC(k,i,j,I_QV) = qv(k,i,j)
          QTRC(k,i,j,I_QC) = qc(k,i,j)
       enddo
       enddo
       enddo

       if ( I_NC > 0 ) then
          do j = JS, JE
          do i = IS, IE
          do k = KS, KE
             if ( qc(k,i,j) > 0.0_RP ) then
                QTRC(k,i,j,I_NC) = 55.0E6_RP / DENS(k,i,j) ! [number/m3] / [kg/m3]
             endif
          enddo
          enddo
          enddo
       endif
    endif

    return
  end subroutine MKINIT_DYCOMS2_RF02_DNS

  !-----------------------------------------------------------------------------
  !> Make initial state for RICO inter comparison
  subroutine MKINIT_RICO
    implicit none

    real(RP):: PERTURB_AMP_PT = 0.1_RP
    real(RP):: PERTURB_AMP_QV = 2.5E-5_RP

    NAMELIST / PARAM_MKINIT_RICO / &
       PERTURB_AMP_PT, &
       PERTURB_AMP_QV

    real(RP) :: potl(KA,IA,JA) ! liquid potential temperature
    real(RP) :: qall ! QV+QC
    real(RP) :: fact

    integer :: ierr
    integer :: k, i, j, iq
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[RICO]/Categ[MKINIT]'

    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_RICO,iostat=ierr)
    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_RICO. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_RICO)

    ! calc in moist condition
    do j = JS, JE
    do i = IS, IE

       pres_sfc(1,i,j) = 1015.4E2_RP ! [Pa]
       pott_sfc(1,i,j) = 297.9_RP
       qv_sfc  (1,i,j) = 0.0_RP
       qc_sfc  (1,i,j) = 0.0_RP

       do k = KS, KE
          !--- potential temperature
          if ( GRID_CZ(k) < 740.0_RP ) then ! below initial cloud top
             potl(k,i,j) = 297.9_RP
          else
             fact = ( GRID_CZ(k)-740.0_RP ) * ( 317.0_RP-297.9_RP ) / ( 4000.0_RP-740.0_RP )
             potl(k,i,j) = 297.9_RP + fact
          endif

          !--- horizontal wind velocity
          if ( GRID_CZ(k) <= 4000.0_RP ) then ! below initial cloud top
             fact = ( GRID_CZ(k)-0.0_RP ) * ( -1.9_RP+9.9_RP ) / ( 4000.0_RP-0.0_RP )
             velx(k,i,j) =  -9.9_RP + fact
             vely(k,i,j) =  -3.8_RP
          else
             velx(k,i,j) =  -1.9_RP
             vely(k,i,j) =  -3.8_RP
          endif

          qv(k,i,j) = 0.0_RP
          qc(k,i,j) = 0.0_RP

       enddo

    enddo
    enddo

    ! make density & pressure profile in moist condition
    call HYDROSTATIC_buildrho( DENS    (:,:,:), & ! [OUT]
                               temp    (:,:,:), & ! [OUT]
                               pres    (:,:,:), & ! [OUT]
                               potl    (:,:,:), & ! [IN]
                               qv      (:,:,:), & ! [IN]
                               qc      (:,:,:), & ! [IN]
                               temp_sfc(:,:,:), & ! [OUT]
                               pres_sfc(:,:,:), & ! [IN]
                               pott_sfc(:,:,:), & ! [IN]
                               qv_sfc  (:,:,:), & ! [IN]
                               qc_sfc  (:,:,:)  ) ! [IN]


    do j = JS, JE
    do i = IS, IE
       qv_sfc  (1,i,j) = 16.0E-3_RP   ! [kg/kg]
       qc_sfc  (1,i,j) = 0.0_RP

       do k = KS, KE
          !--- mixing ratio of vapor
          if ( GRID_CZ(k) <= 740.0_RP ) then ! below initial cloud top
             fact = ( GRID_CZ(k)-0.0_RP ) * ( 13.8E-3_RP-16.0E-3_RP ) / ( 740.0_RP-0.0_RP )
             qall = 16.0E-3_RP + fact
          elseif ( GRID_CZ(k) <= 3260.0_RP ) then ! boundary
             fact = ( GRID_CZ(k)-740.0_RP ) * ( 2.4E-3_RP-13.8E-3_RP ) / ( 3260.0_RP-740.0_RP )
             qall = 13.8E-3_RP + fact
          elseif( GRID_CZ(k) <= 4000.0_RP ) then
             fact = ( GRID_CZ(k)-3260.0_RP ) * ( 1.8E-3_RP-2.4E-3_RP ) / ( 4000.0_RP-3260.0_RP )
             qall = 2.4E-3_RP + fact
          else
             qall = 0.0_RP
          endif

          qc(k,i,j) = 0.0_RP
          qv(k,i,j) = qall - qc(k,i,j)
       enddo

    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       temp(k,i,j) = temp(k,i,j) + LH0 / CPdry * qc(k,i,j)
    enddo
    enddo
    enddo

    ! make density & pressure profile in moist condition
    call HYDROSTATIC_buildrho_bytemp( DENS    (:,:,:), & ! [OUT]
                                      pott    (:,:,:), & ! [OUT]
                                      pres    (:,:,:), & ! [OUT]
                                      temp    (:,:,:), & ! [IN]
                                      qv      (:,:,:), & ! [IN]
                                      qc      (:,:,:), & ! [IN]
                                      pott_sfc(:,:,:), & ! [OUT]
                                      pres_sfc(:,:,:), & ! [IN]
                                      temp_sfc(:,:,:), & ! [IN]
                                      qv_sfc  (:,:,:), & ! [IN]
                                      qc_sfc  (:,:,:)  ) ! [IN]


    do j = JS, JE
    do i = IS, IE
       DENS(   1:KS-1,i,j) = DENS(KS,i,j)
       DENS(KE+1:KA  ,i,j) = DENS(KE,i,j)
    enddo
    enddo

    call COMM_vars8( DENS(:,:,:), 1 )
    call COMM_wait ( DENS(:,:,:), 1 )

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       MOMZ(k,i,j) = 0.0_RP
    enddo
    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       MOMX(k,i,j) = velx(k,i,j) * 0.5_RP * ( DENS(k,i+1,j) + DENS(k,i,j) )
    enddo
    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       MOMY(k,i,j) = vely(k,i,j) * 0.5_RP * ( DENS(k,i,j+1) + DENS(k,i,j) )
    enddo
    enddo
    enddo

    call RANDOM_get(rndm) ! make random
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       RHOT(k,i,j) = ( pott(k,i,j)+2.0_RP*( rndm(k,i,j)-0.5_RP )*PERTURB_AMP_PT ) * DENS(k,i,j)
    enddo
    enddo
    enddo

    call RANDOM_get(rndm) ! make random
    if ( flg_bin ) then
       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          !--- Super saturated air at initial
          QTRC(k,i,j,I_QV) = qv(k,i,j) + 2.0_RP * ( rndm(k,i,j)-0.50_RP ) * PERTURB_AMP_QV &
                           + qc(k,i,j)
          do iq = QQA+1, QA
            QTRC(k,i,j,iq) = QTRC(k,i,j,iq) / DENS(k,i,j)
          enddo
       enddo
       enddo
       enddo
    else
       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          QTRC(k,i,j,I_QV) = qv(k,i,j) + 2.0_RP * ( rndm(k,i,j)-0.50_RP ) * PERTURB_AMP_QV
          QTRC(k,i,j,I_QC) = qc(k,i,j)
       enddo
       enddo
       enddo

       if ( I_NC > 0 ) then
          do j = JS, JE
          do i = IS, IE
          do k = KS, KE
             if ( qc(k,i,j) > 0.0_RP ) then
                QTRC(k,i,j,I_NC) = 70.E6_RP / DENS(k,i,j) ! [number/m3] / [kg/m3]
             endif
          enddo
          enddo
          enddo
       endif
    endif

    return
  end subroutine MKINIT_RICO

  !-----------------------------------------------------------------------------
  subroutine MKINIT_interporation
    use gtool_file, only: &
       FileGetShape, &
       FileRead
    implicit none

    real(RP) :: dz(KA,IA,JA)

    real(RP) :: W(KA,IA,JA)
    real(RP) :: U(KA,IA,JA)
    real(RP) :: V(KA,IA,JA)

    real(RP) :: fact_cz0(KA)
    real(RP) :: fact_cz1(KA)
    real(RP) :: fact_fz0(KA)
    real(RP) :: fact_fz1(KA)
    real(RP) :: fact_cx0(IA)
    real(RP) :: fact_cx1(IA)
    real(RP) :: fact_fx0(IA)
    real(RP) :: fact_fx1(IA)
    real(RP) :: fact_cy0(JA)
    real(RP) :: fact_cy1(JA)
    real(RP) :: fact_fy0(JA)
    real(RP) :: fact_fy1(JA)

    integer :: idx_cz0(KA)
    integer :: idx_cz1(KA)
    integer :: idx_fz0(KA)
    integer :: idx_fz1(KA)
    integer :: idx_cx0(IA)
    integer :: idx_cx1(IA)
    integer :: idx_fx0(IA)
    integer :: idx_fx1(IA)
    integer :: idx_cy0(JA)
    integer :: idx_cy1(JA)
    integer :: idx_fy0(JA)
    integer :: idx_fy1(JA)

    real(RP), allocatable :: DENS_ORG(:,:,:)
    real(RP), allocatable :: MOMZ_ORG(:,:,:)
    real(RP), allocatable :: MOMX_ORG(:,:,:)
    real(RP), allocatable :: MOMY_ORG(:,:,:)
    real(RP), allocatable :: RHOT_ORG(:,:,:)
    real(RP), allocatable :: QTRC_ORG(:,:,:,:)

    real(RP), allocatable :: W_ORG(:,:,:)
    real(RP), allocatable :: U_ORG(:,:,:)
    real(RP), allocatable :: V_ORG(:,:,:)
    real(RP), allocatable :: POTT_ORG(:,:,:)

    real(RP), allocatable :: CZ_ORG(:)
    real(RP), allocatable :: FZ_ORG(:)
    real(RP), allocatable :: CX_ORG(:)
    real(RP), allocatable :: FX_ORG(:)
    real(RP), allocatable :: CY_ORG(:)
    real(RP), allocatable :: FY_ORG(:)

    integer :: dims(3)

    character(len=H_LONG) :: BASENAME_ORG = ''

    NAMELIST / PARAM_MKINIT_INTERPORATION / &
         BASENAME_ORG

    integer :: ierr
    integer :: k, i, j, iq
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[Interporation]/Categ[MKINIT]'

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_INTERPORATION,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_INTERPORATION. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_INTERPORATION)

    call FileGetShape( dims(:),                               &
                       BASENAME_ORG, "DENS", 1, single=.true. )

    allocate( dens_org(dims(1),dims(2),dims(3)) )
    allocate( momz_org(dims(1),dims(2),dims(3)) )
    allocate( momx_org(dims(1),dims(2),dims(3)) )
    allocate( momy_org(dims(1),dims(2),dims(3)) )
    allocate( rhot_org(dims(1),dims(2),dims(3)) )
    allocate( qtrc_org(dims(1),dims(2),dims(3),QA) )

    allocate( w_org(dims(1),dims(2),dims(3)) )
    allocate( u_org(dims(1),dims(2),dims(3)) )
    allocate( v_org(dims(1),dims(2),dims(3)) )
    allocate( pott_org(dims(1),dims(2),dims(3)) )

    allocate( cz_org(dims(1)) )
    allocate( fz_org(dims(1)) )
    allocate( cx_org(dims(2)) )
    allocate( fx_org(dims(2)) )
    allocate( cy_org(dims(3)) )
    allocate( fy_org(dims(3)) )

    call FileRead( dens_org(:,:,:),                          &
                   BASENAME_ORG, "DENS", 1, 1, single=.true. )
    call FileRead( momz_org(:,:,:),                          &
                   BASENAME_ORG, "MOMZ", 1, 1, single=.true. )
    call FileRead( momx_org(:,:,:),                          &
                   BASENAME_ORG, "MOMX", 1, 1, single=.true. )
    call FileRead( momy_org(:,:,:),                          &
                   BASENAME_ORG, "MOMY", 1, 1, single=.true. )
    call FileRead( rhot_org(:,:,:),                          &
                   BASENAME_ORG, "RHOT", 1, 1, single=.true. )
    do iq = 1, QA
       call FileRead( qtrc_org(:,:,:,iq),                            &
                      BASENAME_ORG, AQ_NAME(iq), 1, 1, single=.true. )
    end do

    call FileRead( cz_org(:),                              &
                   BASENAME_ORG, "z" , 1, 1, single=.true. )
    call FileRead( cx_org(:),                              &
                   BASENAME_ORG, "x" , 1, 1, single=.true. )
    call FileRead( cy_org(:),                              &
                   BASENAME_ORG, "y" , 1, 1, single=.true. )
    call FileRead( fx_org(:),                              &
                   BASENAME_ORG, "xh", 1, 1, single=.true. )
    call FileRead( fy_org(:),                              &
                   BASENAME_ORG, "yh", 1, 1, single=.true. )

    do k = KS, KE
       call interporation_fact( fact_cz0(k), fact_cz1(k),     & ! (OUT)
                                idx_cz0( k), idx_cz1 (k),     & ! (OUT)
                                GRID_CZ (k), cz_org, dims(1), & ! (IN)
                                .false.                       ) ! (IN)
       call interporation_fact( fact_fz0(k), fact_fz1(k),     & ! (OUT)
                                idx_fz0 (k), idx_fz1 (k),     & ! (OUT)
                                GRID_FZ (k), fz_org, dims(1), & ! (IN)
                                .false.                       ) ! (IN)
    enddo
    do i = IS, IE
       call interporation_fact( fact_cx0(i), fact_cx1(i),     & ! (OUT)
                                idx_cx0 (i), idx_cx1 (i),     & ! (OUT)
                                GRID_CX (i), cx_org, dims(2), & ! (IN)
                                .true.                        ) ! (IN)
       call interporation_fact( fact_fx0(i), fact_fx1(i),     & ! (OUT)
                                idx_fx0 (i), idx_fx1 (i),     & ! (OUT)
                                GRID_FX (i), fx_org, dims(2), & ! (IN)
                                .true.                        ) ! (IN)
    enddo
    do j = JS, JE
       call interporation_fact( fact_cy0(j), fact_cy1(j),     & ! (OUT)
                                idx_cy0 (j), idx_cy1 (j),     & ! (OUT)
                                GRID_CY (j), cy_org, dims(3), & ! (IN)
                                .true.                        ) ! (IN)
       call interporation_fact( fact_fy0(j), fact_fy1(j),     & ! (OUT)
                                idx_fy0 (j), idx_fy1 (j),     & ! (OUT)
                                GRID_FY (j), fy_org, dims(3), & ! (IN)
                                .true.                        ) ! (IN)
    enddo


    do j = 1, dims(3)
    do i = 1, dims(2)
    do k = 1, dims(1)-1
       w_org(k,i,j) = 2.0_RP * momz_org(k,i,j) / ( dens_org(k+1,i,j) + dens_org(k,i,j) )
    end do
    end do
    end do
    do j = 1, dims(3)
    do i = 1, dims(2)
       w_org(dims(1),i,j) = 0.0_RP
    end do
    end do

    do j = 1, dims(3)
    do i = 1, dims(2)-1
    do k = 1, dims(1)
       u_org(k,i,j) = 2.0_RP * momx_org(k,i,j) / ( dens_org(k,i+1,j) + dens_org(k,i,j) )
    end do
    end do
    end do
    do j = 1, dims(3)
    do k = 1, dims(1)
       u_org(k,dims(2),j) = 2.0_RP * momx_org(k,dims(2),j) / ( dens_org(k,1,j) + dens_org(k,dims(2),j) )
    end do
    end do

    do j = 1, dims(3)-1
    do i = 1, dims(2)
    do k = 1, dims(1)
       v_org(k,i,j) = 2.0_RP * momy_org(k,i,j) / ( dens_org(k,i,j+1) + dens_org(k,i,j) )
    end do
    end do
    end do
    do i = 1, dims(2)
    do k = 1, dims(1)
       v_org(k,i,dims(3)) = 2.0_RP * momy_org(k,i,dims(3)) / ( dens_org(k,i,1) + dens_org(k,i,dims(3)) )
    end do
    end do

    do j = 1, dims(3)
    do i = 1, dims(2)
    do k = 1, dims(1)
       pott_org(k,i,j) = rhot_org(k,i,j) / dens_org(k,i,j)
    end do
    end do
    end do

    do j = 1, dims(3)
    do i = 1, dims(2)
    do k = 1, dims(1)
       dens_org(k,i,j) = log( dens_org(k,i,j) )
    end do
    end do
    end do

    do j = JS, JE
    do i = IS, IE
    do k = KS, IE
       DENS(k,i,j) = exp( &
                     fact_cz0(k)*fact_cx0(i)*fact_cy0(j)*dens_org(idx_cz0(k),idx_cx0(i),idx_cy0(j)) &
                   + fact_cz1(k)*fact_cx0(i)*fact_cy0(j)*dens_org(idx_cz1(k),idx_cx0(i),idx_cy0(j)) &
                   + fact_cz0(k)*fact_cx1(i)*fact_cy0(j)*dens_org(idx_cz0(k),idx_cx1(i),idx_cy0(j)) &
                   + fact_cz1(k)*fact_cx1(i)*fact_cy0(j)*dens_org(idx_cz1(k),idx_cx1(i),idx_cy0(j)) &
                   + fact_cz0(k)*fact_cx0(i)*fact_cy1(j)*dens_org(idx_cz0(k),idx_cx0(i),idx_cy1(j)) &
                   + fact_cz1(k)*fact_cx0(i)*fact_cy1(j)*dens_org(idx_cz1(k),idx_cx0(i),idx_cy1(j)) &
                   + fact_cz0(k)*fact_cx1(i)*fact_cy1(j)*dens_org(idx_cz0(k),idx_cx1(i),idx_cy1(j)) &
                   + fact_cz1(k)*fact_cx1(i)*fact_cy1(j)*dens_org(idx_cz1(k),idx_cx1(i),idx_cy1(j)) &
                   )

       W(k,i,j) = fact_fz0(k)*fact_cx0(i)*fact_cy0(j)*w_org(idx_fz0(k),idx_cx0(i),idx_cy0(j)) &
                + fact_fz1(k)*fact_cx0(i)*fact_cy0(j)*w_org(idx_fz1(k),idx_cx0(i),idx_cy0(j)) &
                + fact_fz0(k)*fact_cx1(i)*fact_cy0(j)*w_org(idx_fz0(k),idx_cx1(i),idx_cy0(j)) &
                + fact_fz1(k)*fact_cx1(i)*fact_cy0(j)*w_org(idx_fz1(k),idx_cx1(i),idx_cy0(j)) &
                + fact_fz0(k)*fact_cx0(i)*fact_cy1(j)*w_org(idx_fz0(k),idx_cx0(i),idx_cy1(j)) &
                + fact_fz1(k)*fact_cx0(i)*fact_cy1(j)*w_org(idx_fz1(k),idx_cx0(i),idx_cy1(j)) &
                + fact_fz0(k)*fact_cx1(i)*fact_cy1(j)*w_org(idx_fz0(k),idx_cx1(i),idx_cy1(j)) &
                + fact_fz1(k)*fact_cx1(i)*fact_cy1(j)*w_org(idx_fz1(k),idx_cx1(i),idx_cy1(j))

       U(k,i,j) = fact_cz0(k)*fact_fx0(i)*fact_cy0(j)*u_org(idx_cz0(k),idx_fx0(i),idx_cy0(j)) &
                + fact_cz1(k)*fact_fx0(i)*fact_cy0(j)*u_org(idx_cz1(k),idx_fx0(i),idx_cy0(j)) &
                + fact_cz0(k)*fact_fx1(i)*fact_cy0(j)*u_org(idx_cz0(k),idx_fx1(i),idx_cy0(j)) &
                + fact_cz1(k)*fact_fx1(i)*fact_cy0(j)*u_org(idx_cz1(k),idx_fx1(i),idx_cy0(j)) &
                + fact_cz0(k)*fact_fx0(i)*fact_cy1(j)*u_org(idx_cz0(k),idx_fx0(i),idx_cy1(j)) &
                + fact_cz1(k)*fact_fx0(i)*fact_cy1(j)*u_org(idx_cz1(k),idx_fx0(i),idx_cy1(j)) &
                + fact_cz0(k)*fact_fx1(i)*fact_cy1(j)*u_org(idx_cz0(k),idx_fx1(i),idx_cy1(j)) &
                + fact_cz1(k)*fact_fx1(i)*fact_cy1(j)*u_org(idx_cz1(k),idx_fx1(i),idx_cy1(j))

       V(k,i,j) = fact_cz0(k)*fact_cx0(i)*fact_fy0(j)*v_org(idx_cz0(k),idx_cx0(i),idx_fy0(j)) &
                + fact_cz1(k)*fact_cx0(i)*fact_fy0(j)*v_org(idx_cz1(k),idx_cx0(i),idx_fy0(j)) &
                + fact_cz0(k)*fact_cx1(i)*fact_fy0(j)*v_org(idx_cz0(k),idx_cx1(i),idx_fy0(j)) &
                + fact_cz1(k)*fact_cx1(i)*fact_fy0(j)*v_org(idx_cz1(k),idx_cx1(i),idx_fy0(j)) &
                + fact_cz0(k)*fact_cx0(i)*fact_fy1(j)*v_org(idx_cz0(k),idx_cx0(i),idx_fy1(j)) &
                + fact_cz1(k)*fact_cx0(i)*fact_fy1(j)*v_org(idx_cz1(k),idx_cx0(i),idx_fy1(j)) &
                + fact_cz0(k)*fact_cx1(i)*fact_fy1(j)*v_org(idx_cz0(k),idx_cx1(i),idx_fy1(j)) &
                + fact_cz1(k)*fact_cx1(i)*fact_fy1(j)*v_org(idx_cz1(k),idx_cx1(i),idx_fy1(j))

       POTT(k,i,j) = fact_cz0(k)*fact_cx0(i)*fact_cy0(j)*pott_org(idx_cz0(k),idx_cx0(i),idx_cy0(j)) &
                   + fact_cz1(k)*fact_cx0(i)*fact_cy0(j)*pott_org(idx_cz1(k),idx_cx0(i),idx_cy0(j)) &
                   + fact_cz0(k)*fact_cx1(i)*fact_cy0(j)*pott_org(idx_cz0(k),idx_cx1(i),idx_cy0(j)) &
                   + fact_cz1(k)*fact_cx1(i)*fact_cy0(j)*pott_org(idx_cz1(k),idx_cx1(i),idx_cy0(j)) &
                   + fact_cz0(k)*fact_cx0(i)*fact_cy1(j)*pott_org(idx_cz0(k),idx_cx0(i),idx_cy1(j)) &
                   + fact_cz1(k)*fact_cx0(i)*fact_cy1(j)*pott_org(idx_cz1(k),idx_cx0(i),idx_cy1(j)) &
                   + fact_cz0(k)*fact_cx1(i)*fact_cy1(j)*pott_org(idx_cz0(k),idx_cx1(i),idx_cy1(j)) &
                   + fact_cz1(k)*fact_cx1(i)*fact_cy1(j)*pott_org(idx_cz1(k),idx_cx1(i),idx_cy1(j))

       do iq = 1, QA
          QTRC(k,i,j,iq) = fact_cz0(k)*fact_cx0(i)*fact_cy0(j)*qtrc_org(idx_cz0(k),idx_cx0(i),idx_cy0(j),iq) &
                         + fact_cz1(k)*fact_cx0(i)*fact_cy0(j)*qtrc_org(idx_cz1(k),idx_cx0(i),idx_cy0(j),iq) &
                         + fact_cz0(k)*fact_cx1(i)*fact_cy0(j)*qtrc_org(idx_cz0(k),idx_cx1(i),idx_cy0(j),iq) &
                         + fact_cz1(k)*fact_cx1(i)*fact_cy0(j)*qtrc_org(idx_cz1(k),idx_cx1(i),idx_cy0(j),iq) &
                         + fact_cz0(k)*fact_cx0(i)*fact_cy1(j)*qtrc_org(idx_cz0(k),idx_cx0(i),idx_cy1(j),iq) &
                         + fact_cz1(k)*fact_cx0(i)*fact_cy1(j)*qtrc_org(idx_cz1(k),idx_cx0(i),idx_cy1(j),iq) &
                         + fact_cz0(k)*fact_cx1(i)*fact_cy1(j)*qtrc_org(idx_cz0(k),idx_cx1(i),idx_cy1(j),iq) &
                         + fact_cz1(k)*fact_cx1(i)*fact_cy1(j)*qtrc_org(idx_cz1(k),idx_cx1(i),idx_cy1(j),iq)
          enddo
    enddo
    enddo
    enddo

    deallocate( dens_org )
    deallocate( momz_org )
    deallocate( momx_org )
    deallocate( momy_org )
    deallocate( rhot_org )
    deallocate( qtrc_org )

    deallocate( w_org )
    deallocate( u_org )
    deallocate( v_org )
    deallocate( pott_org )

    deallocate( cz_org )
    deallocate( fz_org )
    deallocate( cx_org )
    deallocate( fx_org )
    deallocate( cy_org )
    deallocate( fy_org )

    if ( I_QV > 0 ) then
       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          qv(k,i,j) = QTRC(k,i,j,I_QV)
       end do
       end do
       end do
    else
       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          qv(k,i,j) = 0.0_RP
       end do
       end do
       end do
    end if

    if ( I_QC > 0 ) then
       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          qc(k,i,j) = QTRC(k,i,j,I_QC)
       end do
       end do
       end do
    else
       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          qc(k,i,j) = 0.0_RP
       end do
       end do
       end do
    end if

    do j = JS, JE
    do i = IS, IE
    do k = KS+1, KE
       dz(k,i,j) = REAL_CZ(k,i,j) - REAL_CZ(k-1,i,j) ! distance from cell center to cell center
    enddo
    enddo
    enddo

    ! make density & pressure profile in moist condition
    call HYDROSTATIC_buildrho_atmos( DENS(:,:,:), & ! [INOUT]
                                     temp(:,:,:), & ! [OUT]
                                     pres(:,:,:), & ! [OUT]
                                     pott(:,:,:), & ! [IN]
                                     qv  (:,:,:), & ! [IN]
                                     qc  (:,:,:), & ! [IN]
                                     dz  (:,:,:)  ) ! [IN]

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       MOMZ(k,i,j) = 0.5_RP * W(k,i,j) * ( DENS(k,i,j) + DENS(k+1,i,j) )
    enddo
    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       MOMX(k,i,j) = 0.5_RP * U(k,i,j) * ( DENS(k,i+1,j) + DENS(k,i,j) )
    enddo
    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       MOMY(k,i,j) = 0.5_RP * V(k,i,j) * ( DENS(k,i,j+1) + DENS(k,i,j) )
    enddo
    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       RHOT(k,i,j) = pott(k,i,j) * DENS(k,i,j)
    enddo
    enddo
    enddo

    return
  end subroutine MKINIT_interporation

  !-----------------------------------------------------------------------------
  subroutine interporation_fact( &
       fact0, fact1, &
       idx0, idx1,   &
       x, x_org, nx, &
       loop          )
    implicit none

    real(RP), intent(out) :: fact0
    real(RP), intent(out) :: fact1
    integer,  intent(out) :: idx0
    integer,  intent(out) :: idx1
    real(RP), intent(in)  :: x
    integer,  intent(in)  :: nx
    real(RP), intent(in)  :: x_org(nx)
    logical,  intent(in)  :: loop

    real(RP) :: xwork
    integer :: i

    if ( x < x_org(1) ) then
       if ( loop ) then
          xwork = x_org(1) - ( x_org(2) - x_org(1) )**2 / ( x_org(3) - x_org(2) )
          fact0 = ( x_org(1) - x ) / ( x_org(1) - xwork )
          fact1 = ( x - xwork )    / ( x_org(1) - xwork )
          idx0 = nx
          idx1 = 1
       else
          fact0 = ( x_org(2) - x ) / ( x_org(2) - x_org(1) )
          fact1 = ( x - x_org(1) ) / ( x_org(2) - x_org(1) )
          idx0 = 1
          idx1 = 2
       end if
    else if ( x > x_org(nx) ) then
       if ( loop ) then
          xwork = x_org(nx) + ( x_org(nx) - x_org(nx-1) )**2 / ( x_org(nx-1) - x_org(nx-2) )
          fact0 = ( xwork - x )     / ( xwork - x_org(nx) )
          fact1 = ( x - x_org(nx) ) / ( xwork - x_org(nx) )
          idx0 = nx
          idx1 = 1
       else
          fact0 = ( x_org(nx) - x )   / ( x_org(nx) - x_org(nx-1) )
          fact1 = ( x - x_org(nx-1) ) / ( x_org(nx) - x_org(nx-1) )
          idx0 = nx-1
          idx1 = nx
       end if
    else
       do i = 2, nx
          if ( x <= x_org(i) ) then
             fact0 = ( x_org(i) - x )   / ( x_org(i) - x_org(i-1) )
             fact1 = ( x - x_org(i-1) ) / ( x_org(i) - x_org(i-1) )
             idx0 = i-1
             idx1 = i
             exit
          end if
       end do
    end if

    return
  end subroutine interporation_fact
  !-----------------------------------------------------------------------------
  !> Make initial state ( ocean variables )
  subroutine MKINIT_oceancouple
    use mod_ocean_vars, only: &
       OCEAN_TEMP,       &
       OCEAN_SFC_TEMP,   &
       OCEAN_SFC_albedo, &
       OCEAN_SFC_Z0
    implicit none

    ! Flux from Atmosphere
    real(RP) :: FLX_rain      = 0.0_RP ! surface rain flux                         [kg/m2/s]
    real(RP) :: FLX_snow      = 0.0_RP ! surface snow flux                         [kg/m2/s]
    real(RP) :: FLX_LW_dn     = 0.0_RP ! surface downwad long-wave  radiation flux [J/m2/s]
    real(RP) :: FLX_SW_dn     = 0.0_RP ! surface downwad short-wave radiation flux [J/m2/s]
    ! Ocean state
    real(RP) :: OCN_TEMP               ! soil temperature           [K]
    real(RP) :: SFC_TEMP               ! ocean skin temperature      [K]
    real(RP) :: SFC_albedo_LW = 0.0_RP ! ocean surface albedo for LW [0-1]
    real(RP) :: SFC_albedo_SW = 0.0_RP ! ocean surface albedo for SW [0-1]
    real(RP) :: SFC_Z0        = 0.0_RP ! ocean surface roughness length [m]

    NAMELIST / PARAM_MKINIT_OCEANCOUPLE / &
       FLX_rain,      &
       FLX_snow,      &
       FLX_LW_dn,     &
       FLX_SW_dn,     &
       OCN_TEMP,      &
       SFC_TEMP,      &
       SFC_albedo_LW, &
       SFC_albedo_SW, &
       SFC_Z0

    integer :: ierr
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[OceanCouple]/Categ[MKINIT]'

    OCN_TEMP = THETAstd
    SFC_TEMP = THETAstd

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_OCEANCOUPLE,iostat=ierr)
    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_OCEANCOUPLE. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_OCEANCOUPLE)

    SFLX_rain (:,:) = FLX_rain
    SFLX_snow (:,:) = FLX_snow
    SFLX_LW_dn(:,:) = FLX_LW_dn
    SFLX_SW_dn(:,:) = FLX_SW_dn

    OCEAN_TEMP      (:,:)      = OCN_TEMP
    OCEAN_SFC_TEMP  (:,:)      = SFC_TEMP
    OCEAN_SFC_albedo(:,:,I_LW) = SFC_albedo_LW
    OCEAN_SFC_albedo(:,:,I_SW) = SFC_albedo_SW
    OCEAN_SFC_Z0    (:,:)      = SFC_Z0

    return
  end subroutine MKINIT_oceancouple

  !-----------------------------------------------------------------------------
  !> Make initial state ( land variables )
  subroutine MKINIT_landcouple
    use mod_land_vars, only: &
       LAND_TEMP,       &
       LAND_WATER,      &
       LAND_SFC_TEMP,   &
       LAND_SFC_albedo
    implicit none

    ! Flux from Atmosphere
    real(RP) :: FLX_rain      = 0.0_RP ! surface rain flux                         [kg/m2/s]
    real(RP) :: FLX_snow      = 0.0_RP ! surface snow flux                         [kg/m2/s]
    real(RP) :: FLX_LW_dn     = 0.0_RP ! surface downwad long-wave  radiation flux [J/m2/s]
    real(RP) :: FLX_SW_dn     = 0.0_RP ! surface downwad short-wave radiation flux [J/m2/s]
    ! Land state
    real(RP) :: LND_TEMP               ! soil temperature           [K]
    real(RP) :: LND_WATER     = 0.0_RP ! soil moisture              [m3/m3]
    real(RP) :: SFC_TEMP               ! land skin temperature      [K]
    real(RP) :: SFC_albedo_LW = 0.0_RP ! land surface albedo for LW [0-1]
    real(RP) :: SFC_albedo_SW = 0.0_RP ! land surface albedo for SW [0-1]

    NAMELIST / PARAM_MKINIT_LANDCOUPLE / &
       FLX_rain,      &
       FLX_snow,      &
       FLX_LW_dn,     &
       FLX_SW_dn,     &
       LND_TEMP,      &
       LND_WATER,     &
       SFC_TEMP,      &
       SFC_albedo_LW, &
       SFC_albedo_SW

    integer :: ierr
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[LandCouple]/Categ[MKINIT]'

    LND_TEMP = THETAstd
    SFC_TEMP = THETAstd

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_LANDCOUPLE,iostat=ierr)
    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_LANDCOUPLE. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_LANDCOUPLE)

    SFLX_rain (:,:) = FLX_rain
    SFLX_snow (:,:) = FLX_snow
    SFLX_LW_dn(:,:) = FLX_LW_dn
    SFLX_SW_dn(:,:) = FLX_SW_dn

    LAND_TEMP      (:,:,:)    = LND_TEMP
    LAND_WATER     (:,:,:)    = LND_WATER
    LAND_SFC_TEMP  (:,:)      = SFC_TEMP
    LAND_SFC_albedo(:,:,I_LW) = SFC_albedo_LW
    LAND_SFC_albedo(:,:,I_SW) = SFC_albedo_SW

    return
  end subroutine MKINIT_landcouple

  !-----------------------------------------------------------------------------
  !> Make initial state ( urban variables )
  subroutine MKINIT_urbancouple
    use mod_urban_vars, only: &
       TR_URB,  &
       TB_URB,  &
       TG_URB,  &
       TC_URB,  &
       QC_URB,  &
       UC_URB,  &
       TS_URB,  &
       TRL_URB, &
       TBL_URB, &
       TGL_URB
    implicit none

    ! urban state
    real(RP) :: URB_ROOF_TEMP          ! Surface temperature of roof [K]
    real(RP) :: URB_BLDG_TEMP          ! Surface temperature of building [K
    real(RP) :: URB_GRND_TEMP          ! Surface temperature of ground [K]
    real(RP) :: URB_CNPY_TEMP          ! Diagnostic canopy air temperature
    real(RP) :: URB_CNPY_HMDT = 0.0_RP ! Diagnostic canopy humidity [-]
    real(RP) :: URB_CNPY_WIND = 0.0_RP ! Diagnostic canopy wind [m/s]
    real(RP) :: URB_ROOF_LAYER_TEMP    ! temperature in layer of roof [K]
    real(RP) :: URB_BLDG_LAYER_TEMP    ! temperature in layer of building [
    real(RP) :: URB_GRND_LAYER_TEMP    ! temperature in layer of ground [K]

    NAMELIST / PARAM_MKINIT_URBANCOUPLE / &
       URB_ROOF_TEMP,       &
       URB_BLDG_TEMP,       &
       URB_GRND_TEMP,       &
       URB_CNPY_TEMP,       &
       URB_CNPY_HMDT,       &
       URB_CNPY_WIND,       &
       URB_ROOF_LAYER_TEMP, &
       URB_BLDG_LAYER_TEMP, &
       URB_GRND_LAYER_TEMP

    integer :: ierr
    integer :: i, j
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[UrbanCouple]/Categ[MKINIT]'

    URB_ROOF_TEMP       = THETAstd
    URB_BLDG_TEMP       = THETAstd
    URB_GRND_TEMP       = THETAstd
    URB_CNPY_TEMP       = THETAstd
    URB_ROOF_LAYER_TEMP = THETAstd
    URB_BLDG_LAYER_TEMP = THETAstd
    URB_GRND_LAYER_TEMP = THETAstd

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_URBANCOUPLE,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_URBANCOUPLE. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_URBANCOUPLE)

    TR_URB (:,:)   = URB_ROOF_TEMP
    TB_URB (:,:)   = URB_BLDG_TEMP
    TG_URB (:,:)   = URB_GRND_TEMP
    TC_URB (:,:)   = URB_CNPY_TEMP
    QC_URB (:,:)   = URB_CNPY_HMDT
    UC_URB (:,:)   = URB_CNPY_WIND
    TS_URB (:,:)   = URB_CNPY_TEMP
    TRL_URB(:,:,:) = URB_ROOF_LAYER_TEMP
    TBL_URB(:,:,:) = URB_BLDG_LAYER_TEMP
    TGL_URB(:,:,:) = URB_GRND_LAYER_TEMP

    return
  end subroutine MKINIT_urbancouple

  !-----------------------------------------------------------------------------
  !> Make initial state ( sea breeze )
  subroutine MKINIT_seabreeze
    use scale_process, only: &
       PRC_NUM_X
    use scale_landuse, only: &
       LANDUSE_frac_land
    use mod_ocean_vars, only: &
       OCEAN_TEMP,       &
       OCEAN_SFC_TEMP,   &
       OCEAN_SFC_albedo, &
       OCEAN_SFC_Z0
    use mod_land_vars, only: &
       LAND_TEMP,       &
       LAND_WATER,      &
       LAND_SFC_TEMP,   &
       LAND_SFC_albedo
    implicit none

    ! Flux from Atmosphere
    real(RP) :: FLX_rain          = 0.0_RP ! surface rain flux                         [kg/m2/s]
    real(RP) :: FLX_snow          = 0.0_RP ! surface snow flux                         [kg/m2/s]
    real(RP) :: FLX_LW_dn         = 0.0_RP ! surface downwad long-wave  radiation flux [J/m2/s]
    real(RP) :: FLX_SW_dn         = 0.0_RP ! surface downwad short-wave radiation flux [J/m2/s]
    ! Ocean state
    real(RP) :: OCN_TEMP                   ! soil temperature           [K]
    real(RP) :: OCN_SFC_TEMP               ! ocean skin temperature      [K]
    real(RP) :: OCN_SFC_albedo_LW = 0.0_RP ! ocean surface albedo for LW [0-1]
    real(RP) :: OCN_SFC_albedo_SW = 0.0_RP ! ocean surface albedo for SW [0-1]
    real(RP) :: OCN_SFC_Z0        = 0.0_RP ! ocean surface roughness length [m]
    ! Land state
    real(RP) :: LND_TEMP                   ! soil temperature           [K]
    real(RP) :: LND_WATER         = 0.0_RP ! soil moisture              [m3/m3]
    real(RP) :: LND_SFC_TEMP               ! land skin temperature      [K]
    real(RP) :: LND_SFC_albedo_LW = 0.0_RP ! land surface albedo for LW [0-1]
    real(RP) :: LND_SFC_albedo_SW = 0.0_RP ! land surface albedo for SW [0-1]

    NAMELIST / PARAM_MKINIT_SEABREEZE / &
       FLX_rain,          &
       FLX_snow,          &
       FLX_LW_dn,         &
       FLX_SW_dn,         &
       OCN_TEMP,          &
       OCN_SFC_TEMP,      &
       OCN_SFC_albedo_LW, &
       OCN_SFC_albedo_SW, &
       OCN_SFC_Z0,        &
       LND_TEMP,          &
       LND_WATER,         &
       LND_SFC_TEMP,      &
       LND_SFC_albedo_LW, &
       LND_SFC_albedo_SW

    real(RP) :: dist

    integer  :: ierr
    integer  :: i, j
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[Sea Breeze]/Categ[MKINIT]'

    OCN_TEMP  = THETAstd
    LND_TEMP  = THETAstd

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_SEABREEZE,iostat=ierr)
    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_SEABREEZE. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_SEABREEZE)

    ! make surface, land, and ocean conditions
    SFLX_rain (:,:) = FLX_rain
    SFLX_snow (:,:) = FLX_snow
    SFLX_LW_dn(:,:) = FLX_LW_dn
    SFLX_SW_dn(:,:) = FLX_SW_dn

    OCEAN_TEMP      (:,:)      = OCN_TEMP
    OCEAN_SFC_TEMP  (:,:)      = OCN_SFC_TEMP
    OCEAN_SFC_albedo(:,:,I_LW) = OCN_SFC_albedo_LW
    OCEAN_SFC_albedo(:,:,I_SW) = OCN_SFC_albedo_SW
    OCEAN_SFC_Z0    (:,:)      = OCN_SFC_Z0

    LAND_TEMP       (:,:,:)    = LND_TEMP
    LAND_WATER      (:,:,:)    = LND_WATER
    LAND_SFC_TEMP   (:,:)      = LND_SFC_TEMP
    LAND_SFC_albedo (:,:,I_LW) = LND_SFC_albedo_LW
    LAND_SFC_albedo (:,:,I_SW) = LND_SFC_albedo_SW

    ! quartor size of domain
    dist = ( GRID_CXG(IMAX*PRC_NUM_X) - GRID_CXG(1) ) / 8.0_RP

    ! make landuse conditions
    do j = JS, JE
    do i = IS, IE
       if (       GRID_CX(i) >= dist * 3.0_RP &
            .AND. GRID_CX(i) <= dist * 5.0_RP ) then
          LANDUSE_frac_land(i,j) = 1.0_RP
       else
          LANDUSE_frac_land(i,j) = 0.0_RP
       endif
    enddo
    enddo

    return
  end subroutine MKINIT_seabreeze

  !-----------------------------------------------------------------------------
  !> Make initial state ( heat island )
  subroutine MKINIT_heatisland
    use scale_process, only: &
       PRC_NUM_X
    use scale_landuse, only: &
       LANDUSE_frac_land,    &
       LANDUSE_frac_urban
    use mod_land_vars, only: &
       I_ThermalCond,   &
       I_HeatCapacity,  &
       I_Z0M,           &
       LAND_TEMP,       &
       LAND_WATER,      &
       LAND_SFC_TEMP,   &
       LAND_SFC_albedo, &
       LAND_PROPERTY   
    use mod_urban_vars, only: &
       TR_URB,  &
       TB_URB,  &
       TG_URB,  &
       TC_URB,  &
       QC_URB,  &
       UC_URB,  &
       TS_URB,  &
       TRL_URB, &
       TBL_URB, &
       TGL_URB
    implicit none

    ! Flux from Atmosphere
    real(RP) :: FLX_rain          = 0.0_RP ! surface rain flux                         [kg/m2/s]
    real(RP) :: FLX_snow          = 0.0_RP ! surface snow flux                         [kg/m2/s]
    real(RP) :: FLX_LW_dn         = 0.0_RP ! surface downwad long-wave  radiation flux [J/m2/s]
    real(RP) :: FLX_SW_dn         = 0.0_RP ! surface downwad short-wave radiation flux [J/m2/s]
    ! Land state
    real(RP) :: LND_TEMP                   ! soil temperature           [K]
    real(RP) :: LND_WATER         = 0.0_RP ! soil moisture              [m3/m3]
    real(RP) :: LND_SFC_TEMP               ! land skin temperature      [K]
    real(RP) :: LND_SFC_albedo_LW = 0.0_RP ! land surface albedo for LW [0-1]
    real(RP) :: LND_SFC_albedo_SW = 0.0_RP ! land surface albedo for SW [0-1]
    real(RP) :: LND_SFC_ThermalCond        ! land thermal conductivity  [W/m/K]
    real(RP) :: LND_SFC_HeatCapa           ! land heat capacity         [J/m3/K]
    real(RP) :: LND_SFC_Z0                 ! land roughness length      [m]
    
    ! urban state
    real(RP) :: URB_ROOF_TEMP          ! Surface temperature of roof [K]
    real(RP) :: URB_BLDG_TEMP          ! Surface temperature of building [K
    real(RP) :: URB_GRND_TEMP          ! Surface temperature of ground [K]
    real(RP) :: URB_CNPY_TEMP          ! Diagnostic canopy air temperature
    real(RP) :: URB_CNPY_HMDT = 0.0_RP ! Diagnostic canopy humidity [-]
    real(RP) :: URB_CNPY_WIND = 0.0_RP ! Diagnostic canopy wind [m/s]
    real(RP) :: URB_ROOF_LAYER_TEMP    ! temperature in layer of roof [K]
    real(RP) :: URB_BLDG_LAYER_TEMP    ! temperature in layer of building [
    real(RP) :: URB_GRND_LAYER_TEMP 

    NAMELIST / PARAM_MKINIT_HEATISLAND / &
       FLX_rain,            &
       FLX_snow,            &
       FLX_LW_dn,           &
       FLX_SW_dn,           &
       LND_TEMP,            &
       LND_WATER,           &
       LND_SFC_TEMP,        &
       LND_SFC_albedo_LW,   &
       LND_SFC_albedo_SW,   &
       LND_SFC_ThermalCond, &
       LND_SFC_HeatCapa,    &
       LND_SFC_Z0,          &
       URB_ROOF_TEMP,       &
       URB_BLDG_TEMP,       &
       URB_GRND_TEMP,       &
       URB_CNPY_TEMP,       &
       URB_CNPY_HMDT,       &
       URB_CNPY_WIND,       &
       URB_ROOF_LAYER_TEMP, &
       URB_BLDG_LAYER_TEMP, &
       URB_GRND_LAYER_TEMP

    real(RP) :: dist

    integer  :: ierr
    integer  :: i, j
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[Heat island]/Categ[MKINIT]'

    LND_TEMP  = THETAstd
    URB_ROOF_TEMP       = THETAstd
    URB_BLDG_TEMP       = THETAstd
    URB_GRND_TEMP       = THETAstd
    URB_CNPY_TEMP       = THETAstd
    URB_ROOF_LAYER_TEMP = THETAstd
    URB_BLDG_LAYER_TEMP = THETAstd
    URB_GRND_LAYER_TEMP = THETAstd

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_HEATISLAND,iostat=ierr)
    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_HEATISLAND. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_HEATISLAND)

    ! make surface, land, and ocean conditions
    SFLX_rain (:,:) = FLX_rain
    SFLX_snow (:,:) = FLX_snow
    SFLX_LW_dn(:,:) = FLX_LW_dn
    SFLX_SW_dn(:,:) = FLX_SW_dn

    LAND_TEMP       (:,:,:)              = LND_TEMP
    LAND_WATER      (:,:,:)              = LND_WATER
    LAND_SFC_TEMP   (:,:)                = LND_SFC_TEMP
    LAND_SFC_albedo (:,:,I_LW)           = LND_SFC_albedo_LW
    LAND_SFC_albedo (:,:,I_SW)           = LND_SFC_albedo_SW
    LAND_PROPERTY   (:,:,I_ThermalCond)  = LND_SFC_ThermalCond
    LAND_PROPERTY   (:,:,I_HeatCapacity) = LND_SFC_HeatCapa
    LAND_PROPERTY   (:,:,I_Z0M)          = LND_SFC_z0

    TR_URB (:,:)   = URB_ROOF_TEMP
    TB_URB (:,:)   = URB_BLDG_TEMP
    TG_URB (:,:)   = URB_GRND_TEMP
    TC_URB (:,:)   = URB_CNPY_TEMP
    QC_URB (:,:)   = URB_CNPY_HMDT
    UC_URB (:,:)   = URB_CNPY_WIND
    TS_URB (:,:)   = URB_CNPY_TEMP
    TRL_URB(:,:,:) = URB_ROOF_LAYER_TEMP
    TBL_URB(:,:,:) = URB_BLDG_LAYER_TEMP
    TGL_URB(:,:,:) = URB_GRND_LAYER_TEMP

    ! 1/9 size of domain
    dist = ( GRID_CXG(IMAX*PRC_NUM_X) - GRID_CXG(1) ) / 9.0_RP

    ! make landuse conditions
    do j = JS, JE
    do i = IS, IE
       if (       GRID_CX(i) >= dist * 4.0_RP &
            .AND. GRID_CX(i) <  dist * 5.0_RP ) then
          LANDUSE_frac_land(i,j)  = 1.0_RP
          LANDUSE_frac_urban(i,j) = 1.0_RP
       else
          LANDUSE_frac_land(i,j)  = 1.0_RP
          LANDUSE_frac_urban(i,j) = 0.0_RP
       endif
    enddo
    enddo

    return
  end subroutine MKINIT_heatisland

  !-----------------------------------------------------------------------------
  !> Make initial state ( real case )
  subroutine MKINIT_real
    use mod_realinput
    implicit none

    integer                  :: NUMBER_OF_FILES     = 1
    integer                  :: NUMBER_OF_TSTEPS    = 1   ! num of time steps in one file
    integer                  :: INTERP_SERC_DIV_NUM = 10  ! num of dividing blocks in interpolation search
    character(len=H_LONG)    :: BASENAME_ORG        = ''
    character(len=H_LONG)    :: FILETYPE_ORG        = ''
    character(len=H_LONG)    :: BASENAME_BOUNDARY   = 'boundary_real'
    character(len=H_LONG)    :: BOUNDARY_TITLE      = 'SCALE-LES BOUNDARY CONDITION for REAL CASE'
    character(len=H_SHORT)   :: PARENT_MP_TYPE      = 'single'  ! microphysics type of the parent model (single or double)
    real(RP)                 :: BOUNDARY_UPDATE_DT  = 0.0_RP    ! inteval time of boudary data update [s]
    logical                  :: WRF_FILE_TYPE       = .true.    ! wrf filetype: T=wrfout, F=wrfrst
    logical                  :: SERIAL_PROC_READ    = .true.    ! read by one MPI process and broadcast
    logical                  :: NO_ADDITIONAL_INPUT = .false.   ! no additional information


    NAMELIST / PARAM_MKINIT_REAL / &
         NUMBER_OF_FILES,     &
         NUMBER_OF_TSTEPS,    &
         BASENAME_ORG,        &
         FILETYPE_ORG,        &
         BASENAME_BOUNDARY,   &
         BOUNDARY_TITLE,      &
         BOUNDARY_UPDATE_DT,  &
         INTERP_SERC_DIV_NUM, &
         PARENT_MP_TYPE,      &
         WRF_FILE_TYPE,       &
         SERIAL_PROC_READ,    &
         NO_ADDITIONAL_INPUT

    character(len=H_LONG) :: BASENAME_WITHNUM  = ''
    character(len=5)      :: NUM               = ''

    real(RP), allocatable :: DENS_ORG(:,:,:,:)
    real(RP), allocatable :: MOMZ_ORG(:,:,:,:)
    real(RP), allocatable :: MOMX_ORG(:,:,:,:)
    real(RP), allocatable :: MOMY_ORG(:,:,:,:)
    real(RP), allocatable :: RHOT_ORG(:,:,:,:)
    real(RP), allocatable :: QTRC_ORG(:,:,:,:,:)

    integer :: mdlid
    integer :: dims(7)  ! 1-3: normal, 4-6: staggerd, 7: soil-layer
    integer :: totaltimesteps = 1
    integer :: timelen = 1
    integer :: ierr

    integer :: k, i, j, iq, n, ns, ne, l, ll
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[Real Case]/Categ[MKINIT]'

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_MKINIT_REAL,iostat=ierr)
    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_MKINIT_REAL. Check!'
       call PRC_MPIstop
    endif
    if( IO_LNML ) write(IO_FID_LOG,nml=PARAM_MKINIT_REAL)

    if ( BOUNDARY_UPDATE_DT <= 0.0_RP ) then
       write(*,*) 'xxx BOUNDARY_UPDATE_DT is necessary in real case preprocess'
       call PRC_MPIstop
    endif

    totaltimesteps = NUMBER_OF_FILES * NUMBER_OF_TSTEPS

    if     ( FILETYPE_ORG == 'WRF-ARW' ) then
      BASENAME_WITHNUM = trim(BASENAME_ORG)//"_00000"
    else if( FILETYPE_ORG == 'SCALE-LES' ) then
      BASENAME_WITHNUM = trim(BASENAME_ORG)
    else
      write(*,*) ' xxx Unsupported FILE TYPE:', trim(FILETYPE_ORG)
      call PRC_MPIstop
    end if

    call ParentAtomSetup( dims(:), timelen, mdlid,           & ![OUT]
                          BASENAME_WITHNUM, FILETYPE_ORG,    & ![IN]
                          INTERP_SERC_DIV_NUM, WRF_FILE_TYPE ) ![IN]

    if( NUMBER_OF_TSTEPS /= timelen ) then
       if( IO_L ) write(IO_FID_LOG,*) '+++ WARNING: NUMBER_OF_TSTEP is not match with timesteps derived from the file.'
    endif

    allocate( dens_org(KA,IA,JA,totaltimesteps   ) )
    allocate( momz_org(KA,IA,JA,totaltimesteps   ) )
    allocate( momx_org(KA,IA,JA,totaltimesteps   ) )
    allocate( momy_org(KA,IA,JA,totaltimesteps   ) )
    allocate( rhot_org(KA,IA,JA,totaltimesteps   ) )
    allocate( qtrc_org(KA,IA,JA,totaltimesteps,QA) )

    !--- read external file
    do n = 1, NUMBER_OF_FILES
       write(NUM,'(I5.5)') n-1

       if     ( FILETYPE_ORG == 'WRF-ARW' ) then
         BASENAME_WITHNUM = trim(BASENAME_ORG)//"_"//NUM
       else if( FILETYPE_ORG == 'SCALE-LES' ) then
         BASENAME_WITHNUM = trim(BASENAME_ORG)
       else
         write(*,*) ' xxx Unsupported FILE TYPE:', trim(FILETYPE_ORG)
         call PRC_MPIstop
       end if

       if( IO_L ) write(IO_FID_LOG,*) '+++ Target File Name: ',trim(BASENAME_WITHNUM)
       if( IO_L ) write(IO_FID_LOG,*) '    Time Steps in One File: ', NUMBER_OF_TSTEPS

       if( NUMBER_OF_TSTEPS > 1 ) then
          ns = NUMBER_OF_TSTEPS * (n - 1) + 1
          ne = ns + (NUMBER_OF_TSTEPS - 1)
       else
          ns = n
          ne = n
       endif

       call ParentAtomInput( DENS_org(:,:,:,ns:ne),    &
                             MOMZ_org(:,:,:,ns:ne),    &
                             MOMX_org(:,:,:,ns:ne),    &
                             MOMY_org(:,:,:,ns:ne),    &
                             RHOT_org(:,:,:,ns:ne),    &
                             QTRC_org(:,:,:,ns:ne,:),  &
                             BASENAME_WITHNUM,         &
                             dims(:),                  &
                             mdlid,                    &
                             PARENT_MP_TYPE,           &
                             NUMBER_OF_TSTEPS,         &
                             SERIAL_PROC_READ          )
    enddo

    !--- input initial data
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       DENS(k,i,j) = DENS_ORG(k,i,j,1)
       MOMZ(k,i,j) = MOMZ_ORG(k,i,j,1)
       MOMX(k,i,j) = MOMX_ORG(k,i,j,1)
       MOMY(k,i,j) = MOMY_ORG(k,i,j,1)
       RHOT(k,i,j) = RHOT_ORG(k,i,j,1)
    enddo
    enddo
    enddo

    do iq = 1, QA
    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       QTRC(k,i,j,iq) = QTRC_ORG(k,i,j,1,iq)
    enddo
    enddo
    enddo
    enddo

    !--- output boundary data
    call ParentAtomBoundary( DENS_ORG(:,:,:,:),   &
                             MOMZ_ORG(:,:,:,:),   &
                             MOMX_ORG(:,:,:,:),   &
                             MOMY_ORG(:,:,:,:),   &
                             RHOT_ORG(:,:,:,:),   &
                             QTRC_ORG(:,:,:,:,:), &
                             totaltimesteps,      &
                             BOUNDARY_UPDATE_DT,  &
                             BASENAME_BOUNDARY,   &
                             BOUNDARY_TITLE       )

    !--- read/write initial data for bottom boundary models
    n = 1
    write(NUM,'(I5.5)') n-1

    if     ( FILETYPE_ORG == 'WRF-ARW' ) then
      BASENAME_WITHNUM = trim(BASENAME_ORG)//"_"//NUM
    else if( FILETYPE_ORG == 'SCALE-LES' ) then
      BASENAME_WITHNUM = trim(BASENAME_ORG)
    else
      write(*,*) ' xxx Unsupported FILE TYPE:', trim(FILETYPE_ORG)
      call PRC_MPIstop
    end if

    call ParentSurfaceInput( DENS_ORG(:,:,:,:),   &
                             MOMZ_ORG(:,:,:,:),   &
                             MOMX_ORG(:,:,:,:),   &
                             MOMY_ORG(:,:,:,:),   &
                             RHOT_ORG(:,:,:,:),   &
                             QTRC_ORG(:,:,:,:,:), &
                             BASENAME_WITHNUM,    &
                             dims,                &
                             1,                   &
                             mdlid,               &
                             SERIAL_PROC_READ,    &
                             NO_ADDITIONAL_INPUT  )

    do j = JS, JE
    do i = IS, IE
       SFLX_rain   (i,j) = 0.0_RP
       SFLX_snow   (i,j) = 0.0_RP
       SFLX_LW_up  (i,j) = 0.0_RP
       SFLX_LW_dn  (i,j) = 0.0_RP
       SFLX_SW_up  (i,j) = 0.0_RP
       SFLX_SW_dn  (i,j) = 0.0_RP
       TOAFLX_LW_up(i,j) = 0.0_RP
       TOAFLX_LW_dn(i,j) = 0.0_RP
       TOAFLX_SW_up(i,j) = 0.0_RP
       TOAFLX_SW_dn(i,j) = 0.0_RP
    enddo
    enddo

    deallocate( dens_org )
    deallocate( momz_org )
    deallocate( momx_org )
    deallocate( momy_org )
    deallocate( rhot_org )
    deallocate( qtrc_org )

    return
  end subroutine MKINIT_real

end module mod_mkinit
!-------------------------------------------------------------------------------
