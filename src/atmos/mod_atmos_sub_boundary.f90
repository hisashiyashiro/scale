
!-------------------------------------------------------------------------------
!> module Atmosphere / Boundary treatment
!!
!! @par Description
!!          Boundary treatment of model domain
!!          Additional forcing, Sponge layer, rayleigh dumping
!!
!! @author H.Tomita and SCALE developpers
!!
!! @par History
!! @li      2011-12-07 (Y.Miyamoto) [new]
!! @li      2011-12-11 (H.Yashiro)  [mod] integrate to SCALE3
!!
!<
!-------------------------------------------------------------------------------
module mod_atmos_boundary
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use mod_stdio, only: &
     IO_FILECHR
  use mod_fileio_h, only: &
     FIO_HSHORT, &
     FIO_HMID,   &
     FIO_REAL8
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: ATMOS_BOUNDARY_setup
  public :: ATMOS_BOUNDARY_read
  public :: ATMOS_BOUNDARY_write
  public :: ATMOS_BOUNDARY_generate
  public :: ATMOS_BOUNDARY_alpha
  !-----------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !
  real(8), public, allocatable, save :: atmos_refvar(:,:,:,:)  !> reference container (with HALO)

  integer, public, parameter :: I_REF_VELZ = 1 ! reference velocity (z) [m/s]
  integer, public, parameter :: I_REF_VELX = 2 ! reference velocity (x) [m/s]
  integer, public, parameter :: I_REF_VELY = 3 ! reference velocity (y) [m/s]
  integer, public, parameter :: I_REF_POTT = 4 ! reference potential temperature [K]
  integer, public, parameter :: I_REF_QV   = 5 ! reference water vapor [kg/kg]

  real(8), public, allocatable, save :: DAMP_alphau(:,:,:) ! damping coefficient for u  [0-1]
  real(8), public, allocatable, save :: DAMP_alphav(:,:,:) ! damping coefficient for v  [0-1]
  real(8), public, allocatable, save :: DAMP_alphaw(:,:,:) ! damping coefficient for w  [0-1]
  real(8), public, allocatable, save :: DAMP_alphat(:,:,:) ! damping coefficient for pt [0-1]
  real(8), public, allocatable, save :: DAMP_alphaq(:,:,:) ! damping coefficient for qv and scalars [0-1]

  !-----------------------------------------------------------------------------
  !
  !++ Private procedure
  !
  !-----------------------------------------------------------------------------
  !
  !++ Private parameters & variables
  !
  character(len=IO_FILECHR), private :: ATMOS_BOUNDARY_IN_BASENAME  = ''
  character(len=IO_FILECHR), private :: ATMOS_BOUNDARY_OUT_BASENAME = ''
  logical,                   private :: ATMOS_BOUNDARY_USE_VELZ     = .false. ! read from file?
  logical,                   private :: ATMOS_BOUNDARY_USE_VELX     = .false. ! read from file?
  logical,                   private :: ATMOS_BOUNDARY_USE_VELY     = .false. ! read from file?
  logical,                   private :: ATMOS_BOUNDARY_USE_POTT     = .false. ! read from file?
  logical,                   private :: ATMOS_BOUNDARY_USE_QV       = .false. ! read from file?
  real(8),                   private :: ATMOS_BOUNDARY_VALUE_VELX   =  5.D0 ! u at boundary, 5 [m/s]
  real(8),                   private :: ATMOS_BOUNDARY_tauz         = 75.D0 ! maximum value for damping tau (z) [s]
  real(8),                   private :: ATMOS_BOUNDARY_taux         = 75.D0 ! maximum value for damping tau (x) [s]
  real(8),                   private :: ATMOS_BOUNDARY_tauy         = 75.D0 ! maximum value for damping tau (y) [s]

  character(len=FIO_HSHORT), private :: REF_NAME(5)
  data REF_NAME / 'VELZ_ref','VELX_ref','VELY_ref','POTT_ref','QV_ref' /

  !-----------------------------------------------------------------------------
contains

  !-----------------------------------------------------------------------------
  !> Initialize Boundary Treatment
  !-----------------------------------------------------------------------------
  subroutine ATMOS_BOUNDARY_setup
    use mod_stdio, only: &
       IO_FID_CONF, &
       IO_FID_LOG,  &
       IO_L
    use mod_process, only: &
       PRC_MPIstop
    use mod_const, only: &
       CONST_UNDEF8
    use mod_grid, only : &
       IA => GRID_IA, &
       JA => GRID_JA, &
       KA => GRID_KA
    implicit none

    NAMELIST / PARAM_ATMOS_BOUNDARY / &
       ATMOS_BOUNDARY_IN_BASENAME,  &
       ATMOS_BOUNDARY_OUT_BASENAME, &
       ATMOS_BOUNDARY_USE_VELZ,     &
       ATMOS_BOUNDARY_USE_VELX,     &
       ATMOS_BOUNDARY_USE_VELY,     &
       ATMOS_BOUNDARY_USE_POTT,     &
       ATMOS_BOUNDARY_USE_QV,       &
       ATMOS_BOUNDARY_VALUE_VELX,   &
       ATMOS_BOUNDARY_tauz,         &
       ATMOS_BOUNDARY_taux,         &
       ATMOS_BOUNDARY_tauy

    integer :: ierr
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[Boundary]/Categ[ATMOS]'

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_ATMOS_BOUNDARY,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_ATMOS_BOUNDARY. Check!'
       call PRC_MPIstop
    endif
    if( IO_L ) write(IO_FID_LOG,nml=PARAM_ATMOS_BOUNDARY)

    !--- set reference field for boundary
    allocate( atmos_refvar(KA,IA,JA,5) ); atmos_refvar(:,:,:,:) = CONST_UNDEF8

    if ( ATMOS_BOUNDARY_IN_BASENAME /= '' ) then
       call ATMOS_BOUNDARY_read
    elseif( ATMOS_BOUNDARY_OUT_BASENAME /= '' ) then
       atmos_refvar(:,:,:,:) = 0.D0
    endif

    if ( ATMOS_BOUNDARY_OUT_BASENAME /= '' ) then
       call ATMOS_BOUNDARY_generate
       call ATMOS_BOUNDARY_write
    endif

    call ATMOS_BOUNDARY_alpha

    return
  end subroutine ATMOS_BOUNDARY_setup

  !-----------------------------------------------------------------------------
  !> Calc dumping coefficient alpha
  !-----------------------------------------------------------------------------
  subroutine ATMOS_BOUNDARY_alpha
    use mod_stdio, only: &
       IO_FID_CONF, &
       IO_FID_LOG,  &
       IO_L
    use mod_process, only: &
       PRC_MPIstop
    use mod_const, only: &
       CONST_UNDEF8, &
       PI => CONST_PI
    use mod_grid, only : &
       IA => GRID_IA, &
       JA => GRID_JA, &
       KA => GRID_KA, &
       IS => GRID_IS, &
       IE => GRID_IE, &
       JS => GRID_JS, &
       JE => GRID_JE, &
       KS => GRID_KS, &
       KE => GRID_KE, &
       WS => GRID_WS, &
       WE => GRID_WE, &
       GRID_CBFX, &
       GRID_CBFY, &
       GRID_CBFZ, &
       GRID_FBFX, &
       GRID_FBFY, &
       GRID_FBFZ

    real(8) :: coef, alpha
    real(8) :: ee1, ee2

    integer :: i, j, k
    !---------------------------------------------------------------------------

    !--- set damping coefficient
    allocate( DAMP_alphau(KA,IA,JA) ); DAMP_alphau(:,:,:) = 0.D0
    allocate( DAMP_alphav(KA,IA,JA) ); DAMP_alphav(:,:,:) = 0.D0
    allocate( DAMP_alphaw(KA,IA,JA) ); DAMP_alphaw(:,:,:) = 0.D0
    allocate( DAMP_alphat(KA,IA,JA) ); DAMP_alphat(:,:,:) = 0.D0
    allocate( DAMP_alphaq(KA,IA,JA) ); DAMP_alphaq(:,:,:) = 0.D0

    coef = 1.D0 / ATMOS_BOUNDARY_taux

    do i = IS, IE
       ee1 = GRID_CBFX(i)
       ee2 = GRID_FBFX(i)

       if ( ee1 > 0.0D0 .AND. ee1 <= 0.5D0 ) then
          alpha = coef * 0.5D0 * ( 1.D0 - dcos( ee1*PI ) )
          DAMP_alphav(KS:KE,i,JS:JE) = max( alpha, DAMP_alphav(KS:KE,i,JS:JE) )
          DAMP_alphat(KS:KE,i,JS:JE) = max( alpha, DAMP_alphat(KS:KE,i,JS:JE) )
          DAMP_alphaq(KS:KE,i,JS:JE) = max( alpha, DAMP_alphaq(KS:KE,i,JS:JE) )
          DAMP_alphaw(WS:WE,i,JS:JE) = max( alpha, DAMP_alphaw(WS:WE,i,JS:JE) )
       elseif( ee1 > 0.5D0 .AND. ee1 <= 1.0D0 ) then
          alpha = coef * 0.5D0 * ( 1.D0 + dsin( (ee1-0.5D0)*PI ) )
          DAMP_alphav(KS:KE,i,JS:JE) = max( alpha, DAMP_alphav(KS:KE,i,JS:JE) )
          DAMP_alphat(KS:KE,i,JS:JE) = max( alpha, DAMP_alphat(KS:KE,i,JS:JE) )
          DAMP_alphaq(KS:KE,i,JS:JE) = max( alpha, DAMP_alphaq(KS:KE,i,JS:JE) )
          DAMP_alphaw(WS:WE,i,JS:JE) = max( alpha, DAMP_alphaw(WS:WE,i,JS:JE) )
       endif

       if ( ee2 > 0.0D0 .AND. ee2 <= 0.5D0 ) then
          alpha = coef * 0.5D0 * ( 1.D0 - dcos( ee2*PI ) )
          DAMP_alphau(KS:KE,i,JS:JE) = max( alpha, DAMP_alphau(KS:KE,i,JS:JE) )
       elseif( ee2 > 0.5D0 .AND. ee2 <= 1.0D0 ) then
          alpha = coef * 0.5D0 * ( 1.D0 + dsin( (ee2-0.5D0)*PI ) )
          DAMP_alphau(KS:KE,i,JS:JE) = max( alpha, DAMP_alphau(KS:KE,i,JS:JE) )
       endif
    enddo

    coef = 1.D0 / ATMOS_BOUNDARY_tauy

    do j = JS, JE
       ee1 = GRID_CBFY(j)
       ee2 = GRID_FBFY(j)

       if ( ee1 > 0.0D0 .AND. ee1 <= 0.5D0 ) then
          alpha = coef * 0.5D0 * ( 1.D0 - dcos( ee1*PI ) )
          DAMP_alphau(KS:KE,IS:IE,j) = max( alpha, DAMP_alphau(KS:KE,IS:IE,j) )
          DAMP_alphaw(WS:WE,IS:IE,j) = max( alpha, DAMP_alphaw(WS:WE,IS:IE,j) )
          DAMP_alphat(KS:KE,IS:IE,j) = max( alpha, DAMP_alphat(KS:KE,IS:IE,j) )
          DAMP_alphaq(KS:KE,IS:IE,j) = max( alpha, DAMP_alphaq(KS:KE,IS:IE,j) )
       elseif( ee1 > 0.5D0 .AND. ee1 <= 1.0D0 ) then
          alpha = coef * 0.5D0 * ( 1.D0 + dsin( (ee1-0.5D0)*PI ) )
          DAMP_alphau(KS:KE,IS:IE,j) = max( alpha, DAMP_alphau(KS:KE,IS:IE,j) )
          DAMP_alphaw(WS:WE,IS:IE,j) = max( alpha, DAMP_alphaw(WS:WE,IS:IE,j) )
          DAMP_alphat(KS:KE,IS:IE,j) = max( alpha, DAMP_alphat(KS:KE,IS:IE,j) )
          DAMP_alphaq(KS:KE,IS:IE,j) = max( alpha, DAMP_alphaq(KS:KE,IS:IE,j) )
       endif

       if ( ee2 > 0.0D0 .AND. ee2 <= 0.5D0 ) then
          alpha = coef * 0.5D0 * ( 1.D0 - dcos( ee2*PI ) )
          DAMP_alphav(KS:KE,IS:IE,j) = max( alpha, DAMP_alphav(KS:KE,IS:IE,j) )
       elseif( ee2 > 0.5D0 .AND. ee2 <= 1.0D0 ) then
          alpha = coef * 0.5D0 * ( 1.D0 + dsin( (ee2-0.5D0)*PI ) )
          DAMP_alphav(KS:KE,IS:IE,j) = max( alpha, DAMP_alphav(KS:KE,IS:IE,j) )
       endif
    enddo

    coef = 1.D0 / ATMOS_BOUNDARY_tauz

    do k = KS, KE
       ee1 = GRID_CBFZ(k)

       if    ( ee1 > 0.0D0 .AND. ee1 <= 0.5D0 ) then
          alpha = coef * 0.5D0 * ( 1.D0 - dcos( ee1*PI ) )
          DAMP_alphau(k,IS:IE,JS:JE) = max( alpha, DAMP_alphau(k,IS:IE,JS:JE) )
          DAMP_alphav(k,IS:IE,JS:JE) = max( alpha, DAMP_alphav(k,IS:IE,JS:JE) )
          DAMP_alphat(k,IS:IE,JS:JE) = max( alpha, DAMP_alphat(k,IS:IE,JS:JE) )
          DAMP_alphaq(k,IS:IE,JS:JE) = max( alpha, DAMP_alphaq(k,IS:IE,JS:JE) )
       elseif( ee1 > 0.5D0 .AND. ee1 <= 1.0D0 ) then
          alpha = coef * 0.5D0 * ( 1.D0 + dsin( (ee1-0.5D0)*PI ) )
          DAMP_alphau(k,IS:IE,JS:JE) = max( alpha, DAMP_alphau(k,IS:IE,JS:JE) )
          DAMP_alphav(k,IS:IE,JS:JE) = max( alpha, DAMP_alphav(k,IS:IE,JS:JE) )
          DAMP_alphat(k,IS:IE,JS:JE) = max( alpha, DAMP_alphat(k,IS:IE,JS:JE) )
          DAMP_alphaq(k,IS:IE,JS:JE) = max( alpha, DAMP_alphaq(k,IS:IE,JS:JE) )
       endif
    enddo

    do k = WS, WE
       ee2 = GRID_FBFZ(k)

       if    ( ee2 > 0.0D0 .AND. ee2 <= 0.5D0 ) then
          alpha = coef * 0.5D0 * ( 1.D0 - dcos( ee2*PI ) )
          DAMP_alphaw(k,IS:IE,JS:JE) = max( alpha, DAMP_alphaw(k,IS:IE,JS:JE) )
       elseif( ee2 > 0.5D0 .AND. ee2 <= 1.0D0 ) then
          alpha = coef * 0.5D0 * ( 1.D0 + dsin( (ee2-0.5D0)*PI ) )
          DAMP_alphaw(k,IS:IE,JS:JE) = max( alpha, DAMP_alphaw(k,IS:IE,JS:JE) )
       endif
    enddo

    do j = JS-1, JE+1
    do i = IS-1, IE+1
       do k = KS, KE
          if ( atmos_refvar(k,i,j,I_REF_VELX) == CONST_UNDEF8 ) then
             DAMP_alphau(k,i,j) = 0.D0
          endif
          if ( atmos_refvar(k,i,j,I_REF_VELY) == CONST_UNDEF8 ) then
            DAMP_alphav(k,i,j) = 0.D0
          endif
          if ( atmos_refvar(k,i,j,I_REF_POTT) == CONST_UNDEF8 ) then
             DAMP_alphat(k,i,j) = 0.D0
          endif
          if ( atmos_refvar(k,i,j,I_REF_QV) == CONST_UNDEF8 ) then
             DAMP_alphaq(k,i,j) = 0.D0
          endif
       enddo

       do k = WS, WE
          if ( atmos_refvar(k,i,j,I_REF_VELZ) == CONST_UNDEF8 ) then
             DAMP_alphaw(k,i,j) = 0.D0
         endif
      enddo
    enddo
    enddo

    return
  end subroutine ATMOS_BOUNDARY_alpha

  !-----------------------------------------------------------------------------
  !> Read boundary data
  !-----------------------------------------------------------------------------
  subroutine ATMOS_BOUNDARY_read
    use mod_fileio, only: &
       FIO_input
    use mod_grid, only : &
       IA   => GRID_IA,   &
       JA   => GRID_JA,   &
       KA   => GRID_KA,   &
       IMAX => GRID_IMAX, &
       JMAX => GRID_JMAX, &
       KMAX => GRID_KMAX, &
       IS   => GRID_IS,   &
       IE   => GRID_IE,   &
       JS   => GRID_JS,   &
       JE   => GRID_JE,   &
       KS   => GRID_KS,   &
       KE   => GRID_KE
    use mod_comm, only: &
       COMM_vars, &
       COMM_wait
    implicit none

    real(8) :: reference_atmos(KMAX,IMAX,JMAX) !> restart file (no HALO)

    character(len=IO_FILECHR) :: bname
    character(len=8)          :: lname

    integer :: iv, i, j
    !---------------------------------------------------------------------------

    bname = ATMOS_BOUNDARY_IN_BASENAME
    write(lname,'(A,I4.4)') 'ZDEF', KMAX

    if ( ATMOS_BOUNDARY_USE_VELZ ) then
       call FIO_input( reference_atmos(:,:,:), bname, 'VELZ', lname, 1, KMAX, 1 )
       atmos_refvar(KS:KE,IS:IE,JS:JE,I_REF_VELZ) = reference_atmos(1:KMAX,1:IMAX,1:JMAX)
    endif

    if ( ATMOS_BOUNDARY_USE_VELX ) then
       call FIO_input( reference_atmos(:,:,:), bname, 'VELX', lname, 1, KMAX, 1 )
       atmos_refvar(KS:KE,IS:IE,JS:JE,I_REF_VELX) = reference_atmos(1:KMAX,1:IMAX,1:JMAX)
    endif

    if ( ATMOS_BOUNDARY_USE_VELY ) then
       call FIO_input( reference_atmos(:,:,:), bname, 'VELY', lname, 1, KMAX, 1 )
       atmos_refvar(KS:KE,IS:IE,JS:JE,I_REF_VELY) = reference_atmos(1:KMAX,1:IMAX,1:JMAX)
    endif

    if ( ATMOS_BOUNDARY_USE_POTT ) then
       call FIO_input( reference_atmos(:,:,:), bname, 'POTT', lname, 1, KMAX, 1 )
       atmos_refvar(KS:KE,IS:IE,JS:JE,I_REF_POTT) = reference_atmos(1:KMAX,1:IMAX,1:JMAX)
    endif

    if ( ATMOS_BOUNDARY_USE_QV ) then
       call FIO_input( reference_atmos(:,:,:), bname, 'QV',   lname, 1, KMAX, 1 )
       atmos_refvar(KS:KE,IS:IE,JS:JE,I_REF_QV) = reference_atmos(1:KMAX,1:IMAX,1:JMAX)
    endif

    ! fill IHALO & JHALO
    do iv = I_REF_VELZ, I_REF_QV
       call COMM_vars( atmos_refvar(:,:,:,iv), iv )
    enddo

    do iv = I_REF_VELZ, I_REF_QV
       call COMM_wait( iv )
    enddo

    ! fill KHALO
    do iv = I_REF_VELZ, I_REF_QV
    do j  = 1, JA
    do i  = 1, IA
       atmos_refvar(   1:KS-1,i,j,iv) = atmos_refvar(KS,i,j,iv)
       atmos_refvar(KE+1:KA,  i,j,iv) = atmos_refvar(KE,i,j,iv)
    enddo
    enddo
    enddo

    return
  end subroutine ATMOS_BOUNDARY_read

  !-----------------------------------------------------------------------------
  !> Write boundary data
  !-----------------------------------------------------------------------------
  subroutine ATMOS_BOUNDARY_write
    use mod_time, only: &
       NOWSEC => TIME_NOWSEC
    use mod_fileio, only: &
       FIO_output
    use mod_grid, only : &
       IA   => GRID_IA,   &
       JA   => GRID_JA,   &
       KA   => GRID_KA,   &
       IMAX => GRID_IMAX, &
       JMAX => GRID_JMAX, &
       KMAX => GRID_KMAX, &
       IS   => GRID_IS,   &
       IE   => GRID_IE,   &
       JS   => GRID_JS,   &
       JE   => GRID_JE,   &
       KS   => GRID_KS,   &
       KE   => GRID_KE
    implicit none

    real(8) :: reference_atmos(KMAX,IMAX,JMAX) !> restart file (no HALO)

    character(len=IO_FILECHR) :: bname
    character(len=FIO_HMID)   :: desc
    character(len=8)          :: lname
    !---------------------------------------------------------------------------

    bname = ATMOS_BOUNDARY_OUT_BASENAME
    desc  = 'SCALE3 BOUNDARY CONDITION'
    write(lname,'(A,I4.4)') 'ZDEF', KMAX

    if ( ATMOS_BOUNDARY_USE_VELZ ) then
       reference_atmos(1:KMAX,1:IMAX,1:JMAX) = atmos_refvar(KS:KE,IS:IE,JS:JE,I_REF_VELZ)
       call FIO_output( reference_atmos(:,:,:), bname, desc, '',     &
                        'VELZ', 'Reference Velocity w', '', 'm/s',   &
                        FIO_REAL8, lname, 1, KMAX, 1, NOWSEC, NOWSEC )
    endif

    if ( ATMOS_BOUNDARY_USE_VELX ) then
       reference_atmos(1:KMAX,1:IMAX,1:JMAX) = atmos_refvar(KS:KE,IS:IE,JS:JE,I_REF_VELX)
       call FIO_output( reference_atmos(:,:,:), bname, desc, '',     &
                        'VELX', 'Reference Velocity u', '', 'm/s',   &
                        FIO_REAL8, lname, 1, KMAX, 1, NOWSEC, NOWSEC )
    endif

    if ( ATMOS_BOUNDARY_USE_VELY ) then
       reference_atmos(1:KMAX,1:IMAX,1:JMAX) = atmos_refvar(KS:KE,IS:IE,JS:JE,I_REF_VELY)
       call FIO_output( reference_atmos(:,:,:), bname, desc, '',     &
                        'VELY', 'Reference Velocity v', '', 'm/s',   &
                        FIO_REAL8, lname, 1, KMAX, 1, NOWSEC, NOWSEC )
    endif

    if ( ATMOS_BOUNDARY_USE_POTT ) then
       reference_atmos(1:KMAX,1:IMAX,1:JMAX) = atmos_refvar(KS:KE,IS:IE,JS:JE,I_REF_POTT)
       call FIO_output( reference_atmos(:,:,:), bname, desc, '',     &
                        'POTT', 'Reference PT', '', 'K',             &
                        FIO_REAL8, lname, 1, KMAX, 1, NOWSEC, NOWSEC )
    endif

    if ( ATMOS_BOUNDARY_USE_QV ) then
       reference_atmos(1:KMAX,1:IMAX,1:JMAX) = atmos_refvar(KS:KE,IS:IE,JS:JE,I_REF_QV)
       call FIO_output( reference_atmos(:,:,:), bname, desc, '',     &
                        'QV', 'Reference water vapor', '', 'kg/kg',  &
                        FIO_REAL8, lname, 1, KMAX, 1, NOWSEC, NOWSEC )
    endif

    return
  end subroutine ATMOS_BOUNDARY_write

  !-----------------------------------------------------------------------------
  !> generate boundary data (temporal)
  !-----------------------------------------------------------------------------
  subroutine ATMOS_BOUNDARY_generate
    use mod_const, only: &
       CONST_UNDEF8
    use mod_grid, only : &
       KA => GRID_KA, &
       IA => GRID_IA, &
       JA => GRID_JA, &
       KS => GRID_KS, &
       KE => GRID_KE, &
       WS => GRID_WS, &
       WE => GRID_WE, &
       IS => GRID_IS, &
       IE => GRID_IE, &
       JS => GRID_JS, &
       JE => GRID_JE, &
       CZ_mask => GRID_CZ_mask, &
       CX_mask => GRID_CX_mask, &
       GRID_CBFZ, &
       GRID_FBFX
    use mod_comm, only: &
       COMM_vars, &
       COMM_wait
    use mod_atmos_refstate, only: &
       ATMOS_REFSTATE_pott
    implicit none

    integer :: i, j, k, iv
    !---------------------------------------------------------------------------

    do k = KS, KE
       if ( CZ_mask(k) ) then
          atmos_refvar(k,:,:,I_REF_VELZ) = CONST_UNDEF8
          atmos_refvar(k,:,:,I_REF_VELY) = CONST_UNDEF8
          atmos_refvar(k,:,:,I_REF_POTT) = 300.D0
       else
          atmos_refvar(k,:,:,I_REF_VELZ) = 0.D0
          atmos_refvar(k,:,:,I_REF_VELY) = 0.D0
          atmos_refvar(k,:,:,I_REF_POTT) = ATMOS_REFSTATE_pott(k)
       endif
    enddo
    atmos_refvar(:,:,:,I_REF_QV) = CONST_UNDEF8

    do j = JS-1, JE+1
    do i = IS-1, IE+1
       do k = KS, KE
          if ( CZ_mask(k) .AND. CX_mask(i) ) then
             atmos_refvar(k,i,j,I_REF_VELX) = 0.D0
          else
             atmos_refvar(k,i,j,I_REF_VELX) = GRID_FBFX(i) * ATMOS_BOUNDARY_VALUE_VELX &
                                            * ( 1.D0 - GRID_CBFZ(k) )
          endif
       enddo
    enddo
    enddo

    ! fill IHALO & JHALO
    do iv = I_REF_VELZ, I_REF_QV
       call COMM_vars( atmos_refvar(:,:,:,iv), iv )
    enddo

    do iv = I_REF_VELZ, I_REF_QV
       call COMM_wait( iv )
    enddo

    ! fill KHALO
    do iv = I_REF_VELZ, I_REF_QV
    do j  = 1, JA
    do i  = 1, IA
       atmos_refvar(   1:KS-1,i,j,iv) = atmos_refvar(KS,i,j,iv)
       atmos_refvar(KE+1:KA,  i,j,iv) = atmos_refvar(KE,i,j,iv)
    enddo
    enddo
    enddo

    return
  end subroutine ATMOS_BOUNDARY_generate

end module mod_atmos_boundary
