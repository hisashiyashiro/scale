!-------------------------------------------------------------------------------
!> module GRID
!!
!! @par Description
!!          Grid module for plane cartesian coordinate
!!
!! @author Team SCALE
!!
!! @par History
!! @li      2011-11-11 (H.Yashiro)   [new]
!! @li      2012-03-23 (H.Yashiro)   [mod] Explicit index parameter inclusion
!! @li      2012-06-25 (Y.Sato)      [mod] change for unisotropic grid
!! @li      2012-07-05 (S.Nishizawa) [mod] divided setup into some subroutines
!!
!<
!-------------------------------------------------------------------------------
module mod_grid
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use mod_stdio, only: &
     IO_FID_LOG, &
     IO_L,       &
     IO_FILECHR
  use mod_time, only: &
     TIME_rapstart, &
     TIME_rapend
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ included parameters
  !
  include "inc_precision.h"
  include "inc_index.h"

  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: GRID_allocate
  public :: GRID_setup
  public :: GRID_generate

  !-----------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !
  integer,  public, save :: ISG              !< start of the inner domain: x, global
  integer,  public, save :: IEG              !< end   of the inner domain: x, global
  integer,  public, save :: JSG              !< start of the inner domain: y, global
  integer,  public, save :: JEG              !< end   of the inner domain: y, global

  real(RP), public, save :: GRID_CZ(KA)      !< center coordinate [m]: z, local=global
  real(RP), public, save :: GRID_CX(IA)      !< center coordinate [m]: x, local
  real(RP), public, save :: GRID_CY(JA)      !< center coordinate [m]: y, local
  real(RP), public, save :: GRID_CDZ(KA)     !< z-length of control volume [m]
  real(RP), public, save :: GRID_CDX(IA)     !< x-length of control volume [m]
  real(RP), public, save :: GRID_CDY(JA)     !< y-length of control volume [m]
  real(RP), public, save :: GRID_RCDZ(KA)    !< reciprocal of center-dz
  real(RP), public, save :: GRID_RCDX(IA)    !< reciprocal of center-dx
  real(RP), public, save :: GRID_RCDY(JA)    !< reciprocal of center-dy

  real(RP), public, save :: GRID_FZ(0:KA)    !< face   coordinate [m]: z, local=global
  real(RP), public, save :: GRID_FX(0:IA)    !< face   coordinate [m]: x, local
  real(RP), public, save :: GRID_FY(0:JA)    !< face   coordinate [m]: y, local
  real(RP), public, save :: GRID_FDZ(KA-1)   !< z-length of grid(k)-to-grid(k-1) [m]
  real(RP), public, save :: GRID_FDX(IA-1)   !< x-length of grid(i)-to-grid(i-1) [m]
  real(RP), public, save :: GRID_FDY(JA-1)   !< y-length of grid(j)-to-grid(j-1) [m]
  real(RP), public, save :: GRID_RFDZ(KA-1)  !< reciprocal of face-dz
  real(RP), public, save :: GRID_RFDX(IA-1)  !< reciprocal of face-dx
  real(RP), public, save :: GRID_RFDY(JA-1)  !< reciprocal of face-dy

  logical,  public, save :: GRID_CZ_mask(KA) !< main/buffer region mask: z
  logical,  public, save :: GRID_CX_mask(IA) !< main/buffer region mask: x
  logical,  public, save :: GRID_CY_mask(JA) !< main/buffer region mask: y

  real(RP), public, save :: GRID_CBFZ(KA)    !< center buffer factor [0-1]: z
  real(RP), public, save :: GRID_CBFX(IA)    !< center buffer factor [0-1]: x
  real(RP), public, save :: GRID_CBFY(JA)    !< center buffer factor [0-1]: y
  real(RP), public, save :: GRID_FBFZ(KA)    !< face   buffer factor [0-1]: z
  real(RP), public, save :: GRID_FBFX(IA)    !< face   buffer factor [0-1]: x
  real(RP), public, save :: GRID_FBFY(JA)    !< face   buffer factor [0-1]: y

  real(RP), public, allocatable, save :: GRID_FXG(:)      !< face   coordinate [m]: x, global
  real(RP), public, allocatable, save :: GRID_FYG(:)      !< face   coordinate [m]: y, global
  real(RP), public, allocatable, save :: GRID_CXG(:)      !< center coordinate [m]: x, global
  real(RP), public, allocatable, save :: GRID_CYG(:)      !< center coordinate [m]: y, global
  real(RP), public, allocatable, save :: GRID_FBFXG(:)    !< face   buffer factor [0-1]: x, global
  real(RP), public, allocatable, save :: GRID_FBFYG(:)    !< face   buffer factor [0-1]: y, global
  real(RP), public, allocatable, save :: GRID_CBFXG(:)    !< center buffer factor [0-1]: x, global
  real(RP), public, allocatable, save :: GRID_CBFYG(:)    !< center buffer factor [0-1]: y, global
  logical,  public, allocatable, save :: GRID_CXG_mask(:) !< main/buffer region mask: x, global
  logical,  public, allocatable, save :: GRID_CYG_mask(:) !< main/buffer region mask: y, global

  !-----------------------------------------------------------------------------
  !
  !++ Private procedure
  !
  public :: GRID_read

  !-----------------------------------------------------------------------------
  !
  !++ Private parameters & variables
  !
  character(len=IO_FILECHR), private :: GRID_IN_BASENAME  = ''
  character(len=IO_FILECHR), private :: GRID_OUT_BASENAME = ''
  real(RP)                 , private :: GRID_OFFSET_X = 0.0_RP
  real(RP)                 , private :: GRID_OFFSET_Y = 0.0_RP

  !-----------------------------------------------------------------------------
contains
  !-----------------------------------------------------------------------------
  !> Setup
  subroutine GRID_setup
    use mod_stdio, only: &
       IO_FID_CONF
    use mod_process, only: &
       PRC_MPIstop, &
       PRC_myrank,  &
       PRC_2Drank,  &
       PRC_NUM_X,   &
       PRC_NUM_Y
    implicit none

    namelist / PARAM_GRID / &
       GRID_IN_BASENAME,  &
       GRID_OUT_BASENAME, &
       GRID_OFFSET_X,     &
       GRID_OFFSET_Y,     &
       DX,                &
       DY,                &
       DZ,                &
       BUFFER_DZ,         &
       BUFFER_DX,         &
       BUFFER_DY,         &
       BUFFFACT

    integer :: ierr
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[CARTESIAN_PLANE]/Categ[GRID]'

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_GRID,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_GRID. Check!'
       call PRC_MPIstop
    endif
    if( IO_L ) write(IO_FID_LOG,nml=PARAM_GRID)

    ! horizontal index (global domain)
    ISG = IHALO + 1    + PRC_2Drank(PRC_myrank,1) * IMAX
    IEG = IHALO + IMAX + PRC_2Drank(PRC_myrank,1) * IMAX
    JSG = JHALO + 1    + PRC_2Drank(PRC_myrank,2) * JMAX
    JEG = JHALO + JMAX + PRC_2Drank(PRC_myrank,2) * JMAX

    if( IO_L ) write(IO_FID_LOG,*) '*** GRID INFORMATION ***'
    if( IO_L ) write(IO_FID_LOG,'(1x,A,f6.0,f6.0,f6.0)')         '*** delta Z, X, Y [m]                  :', &
                                                       DZ, DX, DY
    if( IO_L ) write(IO_FID_LOG,'(1x,A,I6,A,I6,A,I6)') '*** No. of Computational Grid (global) :', &
                                                       KMAX,           ' x ',                      &
                                                       IMAX*PRC_NUM_X, ' x ',                      &
                                                       JMAX*PRC_NUM_Y
    call GRID_allocate

    if ( GRID_IN_BASENAME /= '' ) then
       call GRID_read
    else
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found input grid file. Generate!'
       
       call GRID_generate
    endif

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,'(1x,A,I6,A,I6,A,I6)') '*** No. of Grid (including HALO,1node) :', &
                                                       KA," x ",IA," x ",JA
    if( IO_L ) write(IO_FID_LOG,'(1x,A,I6,A,I6)')      '*** Global Grid Index (X)              :', &
                                                       ISG," - ",IEG
    if( IO_L ) write(IO_FID_LOG,'(1x,A,I6,A,I6)')      '*** Global Grid Index (Y)              :', &
                                                       JSG," - ",JEG
    if( IO_L ) write(IO_FID_LOG,'(1x,A,I6,A,I6,A,I6)') '*** No. of Computational Grid (1 node) :', &
                                                       KMAX,' x ',IMAX,' x ',JMAX

    if( IO_L ) write(IO_FID_LOG,*) '*** Domain size [km] (this node) :'
    if( IO_L ) write(IO_FID_LOG,'(1x,6(A,f8.3))') '  X:',                    &
                  GRID_FX(0) *1.E-3_RP, ' -HALO- ', GRID_FX(IS-1)*1.E-3_RP, ' | ', &
                  GRID_CX(IS)*1.E-3_RP, ' - ',      GRID_CX(IE)  *1.E-3_RP, ' | ', &
                  GRID_FX(IE)*1.E-3_RP, ' -HALO- ', GRID_FX(IA)  *1.E-3_RP
    if( IO_L ) write(IO_FID_LOG,'(1x,6(A,f8.3))') '  Y:',                    &
                  GRID_FY(0) *1.E-3_RP, ' -HALO- ', GRID_FY(JS-1)*1.E-3_RP, ' | ', &
                  GRID_CY(JS)*1.E-3_RP, ' - ',      GRID_CY(JE)  *1.E-3_RP, ' | ', &
                  GRID_FY(JE)*1.E-3_RP, ' -HALO- ', GRID_FY(JA)  *1.E-3_RP

    return
  end subroutine GRID_setup

  !-----------------------------------------------------------------------------
  !> Allocate arrays
  subroutine GRID_allocate
    use mod_process, only: &
       PRC_NUM_X, &
       PRC_NUM_Y
    implicit none

    integer :: IAG, JAG
    !---------------------------------------------------------------------------

    ! array size (global domain)
    IAG = IHALO + IMAX*PRC_NUM_X + IHALO
    JAG = JHALO + JMAX*PRC_NUM_Y + JHALO

    allocate( GRID_FXG     (0:IAG) )
    allocate( GRID_FYG     (0:JAG) )
    allocate( GRID_CXG     (  IAG) )
    allocate( GRID_CYG     (  JAG) )
    allocate( GRID_CBFXG   (  IAG) )
    allocate( GRID_CBFYG   (  JAG) )
    allocate( GRID_FBFXG   (  IAG) )
    allocate( GRID_FBFYG   (  JAG) )
    allocate( GRID_CXG_mask(  IAG) )
    allocate( GRID_CYG_mask(  JAG) )

  end subroutine GRID_allocate

  !-----------------------------------------------------------------------------
  !> Read horizontal&vertical grid
  subroutine GRID_read
    use gtool_file, only: &
       FileRead
    use mod_process, only: &
       PRC_myrank
    implicit none

    character(len=IO_FILECHR) :: bname

    integer :: k, i, j
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '*** Input grid file ***'

    write(bname,'(A,A,F15.3)') trim(GRID_IN_BASENAME)

    call FileRead( GRID_CZ(:), bname, 'CZ', 1, PRC_myrank )
    call FileRead( GRID_CX(:), bname, 'CX', 1, PRC_myrank )
    call FileRead( GRID_CY(:), bname, 'CY', 1, PRC_myrank )
    call FileRead( GRID_FZ(:), bname, 'FZ', 1, PRC_myrank )
    call FileRead( GRID_FX(:), bname, 'FX', 1, PRC_myrank )
    call FileRead( GRID_FY(:), bname, 'FY', 1, PRC_myrank )

    call FileRead( GRID_CDZ(:), bname, 'CDZ', 1, PRC_myrank )
    call FileRead( GRID_CDX(:), bname, 'CDX', 1, PRC_myrank )
    call FileRead( GRID_CDY(:), bname, 'CDY', 1, PRC_myrank )
    call FileRead( GRID_FDZ(:), bname, 'FDZ', 1, PRC_myrank )
    call FileRead( GRID_FDX(:), bname, 'FDX', 1, PRC_myrank )
    call FileRead( GRID_FDY(:), bname, 'FDY', 1, PRC_myrank )

    GRID_RCDZ(:) = 1.0_RP / GRID_CDZ(:)
    GRID_RCDX(:) = 1.0_RP / GRID_CDX(:)
    GRID_RCDY(:) = 1.0_RP / GRID_CDY(:)
    GRID_RFDZ(:) = 1.0_RP / GRID_FDZ(:)
    GRID_RFDX(:) = 1.0_RP / GRID_FDX(:)
    GRID_RFDY(:) = 1.0_RP / GRID_FDY(:)

    call FileRead( GRID_CBFZ(:), bname, 'CBFZ', 1, PRC_myrank )
    call FileRead( GRID_CBFX(:), bname, 'CBFX', 1, PRC_myrank )
    call FileRead( GRID_CBFY(:), bname, 'CBFY', 1, PRC_myrank )
    call FileRead( GRID_FBFZ(:), bname, 'FBFZ', 1, PRC_myrank )
    call FileRead( GRID_FBFX(:), bname, 'FBFX', 1, PRC_myrank )
    call FileRead( GRID_FBFY(:), bname, 'FBFY', 1, PRC_myrank )

    do k = 1, KA
       if ( GRID_CBFZ(k) == 0.0_RP ) then
          GRID_CZ_mask(k) = .true.
       else
          GRID_CZ_mask(k) = .false.
       endif
    enddo

    do i = 1, IA
       if ( GRID_CBFX(i) == 0.0_RP ) then
          GRID_CX_mask(i) = .true.
       else
          GRID_CX_mask(i) = .false.
       endif
    enddo

    do j = 1, JA
       if ( GRID_CBFY(j) == 0.0_RP ) then
          GRID_CY_mask(j) = .true.
       else
          GRID_CY_mask(j) = .false.
       endif
    enddo

    return
  end subroutine GRID_read

  !-----------------------------------------------------------------------------
  !> Generate horizontal&vertical grid
  subroutine GRID_generate
    use mod_process, only: &
       PRC_MPIstop, &
       PRC_myrank,  &
       PRC_2Drank,  &
       PRC_NUM_X,   &
       PRC_NUM_Y
    implicit none

    integer :: IAG ! # of x whole cells (global, with HALO)
    integer :: JAG ! # of y whole cells (global, with HALO)

    real(RP), allocatable :: buffz(:), buffx(:), buffy(:)
    real(RP)              :: bufftotz, bufftotx, bufftoty

    integer :: kbuff, ibuff, jbuff
    integer :: kmain, imain, jmain

    integer :: k, i, j, ii, jj
    !---------------------------------------------------------------------------

    !##### coordinate in global domain #####

    ! array size (global domain)
    IAG = IHALO + IMAX*PRC_NUM_X + IHALO
    JAG = JHALO + JMAX*PRC_NUM_Y + JHALO

    allocate( buffx(0:IAG) )
    allocate( buffy(0:JAG) )

    ! X-direction
    ! calculate buffer grid size
    buffx(0) = DX
    bufftotx = 0.0_RP

    do i = 1, IAG
       if( bufftotx >= BUFFER_DX ) exit

       buffx(i) = buffx(i-1) * BUFFFACT
       bufftotx = bufftotx + buffx(i)
    enddo
    ibuff = i - 1
    imain = IAG - 2*ibuff - 2*IHALO

    if ( imain < 1 ) then
       write(*,*) 'xxx Not appropriate buffer length for global domain(X). Check!', BUFFER_DX
       call PRC_MPIstop
    endif

    ! horizontal coordinate (global domaim)
    GRID_FXG(IHALO) = GRID_OFFSET_X
    do i = IHALO-1, 0, -1
       GRID_FXG(i) = GRID_FXG(i+1) - buffx(ibuff)
    enddo

    do i = 1, IHALO
       GRID_CXG     (i) = 0.5_RP * ( GRID_FXG(i)+GRID_FXG(i-1) )
       GRID_CXG_mask(i) = .false.
    enddo

    if ( ibuff > 0 ) then
       do i = IHALO+1, IHALO+ibuff
          GRID_FXG     (i) = GRID_FXG(i-1) + buffx(ibuff+IHALO+1-i)
          GRID_CXG     (i) = 0.5_RP * ( GRID_FXG(i)+GRID_FXG(i-1) )
          GRID_CXG_mask(i) = .false.
       enddo
    endif

    do i = IHALO+ibuff+1, IHALO+ibuff+imain
       GRID_FXG     (i) = GRID_FXG(i-1) + DX
       GRID_CXG     (i) = 0.5_RP * ( GRID_FXG(i)+GRID_FXG(i-1) )
       GRID_CXG_mask(i) = .true.
    enddo

    if ( ibuff > 0 ) then
       do i = IHALO+ibuff+imain+1, IHALO+ibuff+imain+ibuff
          GRID_FXG     (i) = GRID_FXG(i-1) + buffx(i-IHALO-ibuff-imain)
          GRID_CXG     (i) = 0.5_RP * ( GRID_FXG(i)+GRID_FXG(i-1) )
          GRID_CXG_mask(i) = .false.
       enddo
    endif

    do i = IHALO+ibuff+imain+ibuff+1, IHALO+ibuff+imain+ibuff+IHALO
       GRID_FXG     (i) = GRID_FXG(i-1) + buffx(ibuff)
       GRID_CXG     (i) = 0.5_RP * ( GRID_FXG(i)+GRID_FXG(i-1) )
       GRID_CXG_mask(i) = .false.
    enddo

    ! calc buffer factor (global domaim)
    GRID_CBFXG(:) = 0.0_RP
    GRID_FBFXG(:) = 0.0_RP
    do i = 1, IHALO
       GRID_CBFXG(i) = 1.0_RP
       GRID_FBFXG(i) = 1.0_RP
    enddo

    if ( ibuff > 0 ) then
       do i = IHALO+1, IHALO+ibuff
          GRID_CBFXG(i) = (bufftotx+GRID_FXG(IHALO)-GRID_CXG(i)) / bufftotx
          GRID_FBFXG(i) = (bufftotx+GRID_FXG(IHALO)-GRID_FXG(i)) / bufftotx
       enddo

       do i = IHALO+ibuff+imain+1, IHALO+ibuff+imain+ibuff
          GRID_CBFXG(i) = (bufftotx-GRID_FXG(IAG-IHALO)+GRID_CXG(i)) / bufftotx
          GRID_FBFXG(i) = (bufftotx-GRID_FXG(IAG-IHALO)+GRID_FXG(i)) / bufftotx
       enddo
    endif

    do i = IHALO+ibuff+imain+ibuff+1, IHALO+ibuff+imain+ibuff+IHALO
       GRID_CBFXG(i) = 1.0_RP
       GRID_FBFXG(i) = 1.0_RP
    enddo

    GRID_CBFXG(:) = max( min( GRID_CBFXG(:), 1.0_RP ), 0.0_RP )
    GRID_FBFXG(:) = max( min( GRID_FBFXG(:), 1.0_RP ), 0.0_RP )

    ! Y-direction
    ! calculate buffer grid size
    buffy(0) = DY
    bufftoty = 0.0_RP

    do j = 1, JAG
       if( bufftoty >= BUFFER_DY ) exit

       buffy(j) = buffy(j-1) * BUFFFACT
       bufftoty = bufftoty + buffy(j)
    enddo
    jbuff = j - 1
    jmain = JAG - 2*jbuff - 2*JHALO

    if ( jmain < 1 ) then
       write(*,*) 'xxx Not appropriate buffer length for global domain(Y). Check!', BUFFER_DY
       call PRC_MPIstop
    endif

    ! horizontal coordinate (global domaim)
    GRID_FYG(JHALO) = GRID_OFFSET_Y
    do j = JHALO-1, 0, -1
       GRID_FYG(j) = GRID_FYG(j+1) - buffy(jbuff)
    enddo

    do j = 1, JHALO
       GRID_CYG     (j) = 0.5_RP * ( GRID_FYG(j)+GRID_FYG(j-1) )
       GRID_CYG_mask(j) = .false.
    enddo

    if ( jbuff > 0 ) then
       do j = JHALO+1, JHALO+jbuff
          GRID_FYG     (j) = GRID_FYG(j-1) + buffy(jbuff+JHALO+1-j)
          GRID_CYG     (j) = 0.5_RP * ( GRID_FYG(j)+GRID_FYG(j-1) )
          GRID_CYG_mask(j) = .false.
       enddo
    endif

    do j = JHALO+jbuff+1, JHALO+jbuff+jmain
       GRID_FYG     (j) = GRID_FYG(j-1) + DY
       GRID_CYG     (j) = 0.5_RP * ( GRID_FYG(j)+GRID_FYG(j-1) )
       GRID_CYG_mask(j) = .true.
    enddo

    if ( jbuff > 0 ) then
       do j = JHALO+jbuff+jmain+1, JHALO+jbuff+jmain+jbuff
          GRID_FYG     (j) = GRID_FYG(j-1) + buffy(j-JHALO-jbuff-jmain)
          GRID_CYG     (j) = 0.5_RP * ( GRID_FYG(j)+GRID_FYG(j-1) )
          GRID_CYG_mask(j) = .false.
       enddo
    endif

    do j = JHALO+jbuff+jmain+jbuff+1, JHALO+jbuff+jmain+jbuff+JHALO
       GRID_FYG     (j) = GRID_FYG(j-1) + buffy(jbuff)
       GRID_CYG     (j) = 0.5_RP * ( GRID_FYG(j)+GRID_FYG(j-1) )
       GRID_CYG_mask(j) = .false.
    enddo

    ! calc buffer factor (global domaim)
    GRID_CBFYG(:) = 0.0_RP
    GRID_FBFYG(:) = 0.0_RP
    do j = 1, JHALO
       GRID_CBFYG(j) = 1.0_RP
       GRID_FBFYG(j) = 1.0_RP
    enddo

    if ( jbuff > 0 ) then
       do j = JHALO+1, JHALO+jbuff
          GRID_CBFYG(j) = (bufftoty+GRID_FYG(JHALO)-GRID_CYG(j)) / bufftoty
          GRID_FBFYG(j) = (bufftoty+GRID_FYG(JHALO)-GRID_FYG(j)) / bufftoty
       enddo

       do j = JHALO+jbuff+jmain+1, JHALO+jbuff+jmain+jbuff
          GRID_CBFYG(j) = (bufftoty-GRID_FYG(JAG-JHALO)+GRID_CYG(j)) / bufftoty
          GRID_FBFYG(j) = (bufftoty-GRID_FYG(JAG-JHALO)+GRID_FYG(j)) / bufftoty
       enddo
    endif

    do j = JHALO+jbuff+jmain+jbuff+1, JHALO+jbuff+jmain+jbuff+JHALO
       GRID_CBFYG(j) = 1.0_RP
       GRID_FBFYG(j) = 1.0_RP
    enddo
    GRID_CBFYG(:) = max( min( GRID_CBFYG(:), 1.0_RP ), 0.0_RP )
    GRID_FBFYG(:) = max( min( GRID_FBFYG(:), 1.0_RP ), 0.0_RP )

    deallocate( buffx )
    deallocate( buffy )

    !##### coordinate in local domain #####

    allocate( buffz(0:KA) )

    ! Z-direction
    ! calculate buffer grid size
    buffz(0) = DZ
    bufftotz = 0.0_RP

    do k = 1, KA
       if( bufftotz >= BUFFER_DZ ) exit

       buffz(k) = buffz(k-1) * BUFFFACT
       bufftotz = bufftotz + buffz(k)
    enddo
    kbuff = k - 1
    kmain = KE - KS + 1 - kbuff

    if ( kmain < 1 ) then
       write(*,*) 'xxx Not appropriate buffer length for global domain(Z). Check!', BUFFER_DZ
       call PRC_MPIstop
    endif

    ! vartical coordinate (local=global domaim)
    GRID_FZ(KS-1) = 0.0_RP
    do k = KS-2, 0, -1
       GRID_FZ(k) = GRID_FZ(k+1) - DZ
    enddo

    do k = 1, KS-1
       GRID_CZ     (k) = 0.5_RP * ( GRID_FZ(k)+GRID_FZ(k-1) )
       GRID_CZ_mask(k) = .true.
    enddo

    do k = KS, KS+kmain-1
       GRID_FZ     (k) = GRID_FZ(k-1) + DZ
       GRID_CZ     (k) = 0.5_RP * ( GRID_FZ(k)+GRID_FZ(k-1) )
       GRID_CZ_mask(k) = .true.
    enddo

    if ( kbuff > 0 ) then
       do k = KS+kmain, KE
          GRID_FZ     (k) = GRID_FZ(k-1) + buffz(k-KS-kmain+1)
          GRID_CZ     (k) = 0.5_RP * ( GRID_FZ(k)+GRID_FZ(k-1) )
          GRID_CZ_mask(k) = .false.
       enddo
    endif

    do k = KE+1, KA
       GRID_FZ     (k) = GRID_FZ(k-1) + buffz(kbuff)
       GRID_CZ     (k) = 0.5_RP * ( GRID_FZ(k)+GRID_FZ(k-1) )
       GRID_CZ_mask(k) = .false.
    enddo

    ! calc buffer factor (global domaim)
    GRID_CBFZ(:) = 0.0_RP
    GRID_FBFZ(:) = 0.0_RP
    if ( kbuff > 0 ) then
       do k = KS+kmain, KE
          GRID_CBFZ(k) = (bufftotz-GRID_FZ(KE)+GRID_CZ(k)) / bufftotz
          GRID_FBFZ(k) = (bufftotz-GRID_FZ(KE)+GRID_FZ(k)) / bufftotz
       enddo
    endif

    do k = KE+1, KA
       GRID_CBFZ(k) = 1.0_RP
       GRID_FBFZ(k) = 1.0_RP
    enddo
    GRID_CBFZ(:) = max( min( GRID_CBFZ(:), 1.0_RP ), 0.0_RP )
    GRID_FBFZ(:) = max( min( GRID_FBFZ(:), 1.0_RP ), 0.0_RP )

    deallocate( buffz )

    ! vartical coordinate (local domaim)
    do k = 1, KA
       GRID_CDZ (k) = GRID_FZ(k) - GRID_FZ(k-1)
       GRID_RCDZ(k) = 1.0_RP / GRID_CDZ(k)
    enddo

    do k = 1, KA-1
       GRID_FDZ (k) = GRID_CZ(k+1)-GRID_CZ(k)
       GRID_RFDZ(k) = 1.0_RP / GRID_FDZ(k)
    enddo

    ! X-direction
    ! horizontal coordinate (local domaim)
    do i = 0, IA
       ii = i + PRC_2Drank(PRC_myrank,1) * IMAX

       GRID_FX(i) = GRID_FXG(ii)
    enddo

    do i = 1, IA
       ii = i + PRC_2Drank(PRC_myrank,1) * IMAX

       GRID_CX     (i) = GRID_CXG     (ii)
       GRID_CX_mask(i) = GRID_CXG_mask(ii)

       GRID_CBFX(i) = GRID_CBFXG(ii)
       GRID_FBFX(i) = GRID_FBFXG(ii)

       GRID_CDX (i) = GRID_FX(i) - GRID_FX(i-1)
       GRID_RCDX(i) = 1.0_RP / GRID_CDX(i)
    enddo

    do i = 1, IA-1
       GRID_FDX (i) = GRID_CX(i+1)-GRID_CX(i)
       GRID_RFDX(i) = 1.0_RP / GRID_FDX(i)
    enddo

    ! Y-direction
    ! horizontal coordinate (local domaim)
    do j = 0, JA
       jj = j + PRC_2Drank(PRC_myrank,2) * JMAX

       GRID_FY(j) = GRID_FYG(jj)
    enddo

    do j = 1, JA
       jj = j + PRC_2Drank(PRC_myrank,2) * JMAX

       GRID_CY     (j) = GRID_CYG     (jj)
       GRID_CY_mask(j) = GRID_CYG_mask(jj)

       GRID_CBFY(j) = GRID_CBFYG(jj)
       GRID_FBFY(j) = GRID_FBFYG(jj)

       GRID_CDY (j) = GRID_FY(j) - GRID_FY(j-1)
       GRID_RCDY(j) = 1.0_RP / GRID_CDY(j)
    enddo

    do j = 1, JA-1
       GRID_FDY (j) = GRID_CY(j+1)-GRID_CY(j)
       GRID_RFDY(j) = 1.0_RP / GRID_FDY(j)
    enddo

    ! report
    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '*** Main/buffer Grid (global) :'
    if( IO_L ) write(IO_FID_LOG,'(1x,2(A,I6))')  '  Z: buffer = ', kbuff,' x 1, main = ',kmain
    if( IO_L ) write(IO_FID_LOG,'(1x,2(A,I6))')  '  X: buffer = ', ibuff,' x 2, main = ',imain
    if( IO_L ) write(IO_FID_LOG,'(1x,2(A,I6))')  '  Y: buffer = ', jbuff,' x 2, main = ',jmain

    if( IO_L ) write(IO_FID_LOG,*) '*** Domain size [km] (global) :'
    if( IO_L ) write(IO_FID_LOG,'(1x,7(A,f8.3))') '  Z:',                &
                  GRID_FZ(0)       *1.E-3_RP, ' -HALO-                   ', &
                  GRID_FZ(KS-1)    *1.E-3_RP, ' | ',                        &
                  GRID_CZ(KS)      *1.E-3_RP, ' - ',                        &
                  GRID_CZ(KE-kbuff)*1.E-3_RP, ' | ',                        &
                  GRID_FZ(KE-kbuff)*1.E-3_RP, ' -buffer- ',                 &
                  GRID_FZ(KE)      *1.E-3_RP, ' -HALO- ',                   &
                  GRID_FZ(KA)      *1.E-3_RP
    if( IO_L ) write(IO_FID_LOG,'(1x,8(A,f8.3))') '  X:',        &
                  GRID_FXG(0)              *1.E-3_RP, ' -HALO- ',   &
                  GRID_FXG(IHALO)          *1.E-3_RP, ' -buffer- ', &
                  GRID_FXG(IHALO+ibuff)    *1.E-3_RP, ' | ',        &
                  GRID_CXG(IHALO+ibuff+1)  *1.E-3_RP, ' - ',        &
                  GRID_CXG(IAG-IHALO-ibuff)*1.E-3_RP, ' | ',        &
                  GRID_FXG(IAG-IHALO-ibuff)*1.E-3_RP, ' -buffer- ', &
                  GRID_FXG(IAG-IHALO)      *1.E-3_RP, ' -HALO- ',   &
                  GRID_FXG(IAG)            *1.E-3_RP
    if( IO_L ) write(IO_FID_LOG,'(1x,8(A,f8.3))') '  Y:',        &
                  GRID_FYG(0)              *1.E-3_RP, ' -HALO- ',   &
                  GRID_FYG(JHALO)          *1.E-3_RP, ' -buffer- ', &
                  GRID_FYG(JHALO+jbuff)    *1.E-3_RP, ' | ',        &
                  GRID_CYG(JHALO+jbuff+1)  *1.E-3_RP, ' - ',        &
                  GRID_CYG(JAG-JHALO-jbuff)*1.E-3_RP, ' | ',        &
                  GRID_FYG(JAG-JHALO-jbuff)*1.E-3_RP, ' -buffer- ', &
                  GRID_FYG(JAG-JHALO)      *1.E-3_RP, ' -HALO- ',   &
                  GRID_FYG(JAG)            *1.E-3_RP

! for debug
!    if( IO_L ) write(IO_FID_LOG,*)
!    if( IO_L ) write(IO_FID_LOG,*) ' ', 0, GRID_FZ(0)
!    do k = 1, KA-1
!       if( IO_L ) write(IO_FID_LOG,*) k, GRID_CZ(k), GRID_CBFZ(k), GRID_CDZ(k), GRID_CZ_mask(k)
!       if( IO_L ) write(IO_FID_LOG,*) ' ', k, GRID_FZ(k), GRID_FBFZ(k), GRID_FDZ(k)
!    enddo
!    k = KA
!    if( IO_L ) write(IO_FID_LOG,*) k, GRID_CZ(k), GRID_CBFZ(k), GRID_CDZ(k), GRID_CZ_mask(k)
!    if( IO_L ) write(IO_FID_LOG,*) ' ', k, GRID_FZ(k), GRID_FBFZ(k)

!    if( IO_L ) write(IO_FID_LOG,*)
!    if( IO_L ) write(IO_FID_LOG,*) ' ', 0, GRID_FX(0)
!    do i = 1, IA-1
!       if( IO_L ) write(IO_FID_LOG,*) i, GRID_CX(i), GRID_CBFX(i), GRID_CDX(i), GRID_CX_mask(i)
!       if( IO_L ) write(IO_FID_LOG,*) ' ', i, GRID_FX(i), GRID_FBFX(i), GRID_FDX(i)
!    enddo
!    i = IA
!    if( IO_L ) write(IO_FID_LOG,*) i, GRID_CX(i), GRID_CBFX(i), GRID_CDX(i), GRID_CX_mask(i)
!    if( IO_L ) write(IO_FID_LOG,*) ' ', i, GRID_FX(i), GRID_FBFX(i)

!    if( IO_L ) write(IO_FID_LOG,*)
!    if( IO_L ) write(IO_FID_LOG,*) ' ', 0, GRID_FY(0)
!    do j = 1, JA-1
!       if( IO_L ) write(IO_FID_LOG,*) j, GRID_CY(j), GRID_CBFY(j), GRID_CDY(j), GRID_CY_mask(j)
!       if( IO_L ) write(IO_FID_LOG,*) ' ', j, GRID_FY(j), GRID_FBFY(j), GRID_FDY(j)
!    enddo
!    j = JA
!    if( IO_L ) write(IO_FID_LOG,*) j, GRID_CY(j), GRID_CBFY(j), GRID_CDY(j), GRID_CY_mask(j)
!    if( IO_L ) write(IO_FID_LOG,*) ' ', j, GRID_FY(j), GRID_FBFY(j)

    return
  end subroutine GRID_generate

end module mod_grid