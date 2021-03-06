!-------------------------------------------------------------------------------
!> module PROCESS
!!
!! @par Description
!!          MPI/non-MPI management module
!!
!! @author Team SCALE
!!
!<
#include "scalelib.h"
module scale_prc
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use mpi
  use scale_precision
  use scale_io
  use scale_fpm, only: &
     FPM_alive,  &
     FPM_Polling
  use scale_sigvars
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: PRC_MPIstart
  public :: PRC_UNIVERSAL_setup
  public :: PRC_GLOBAL_setup
  public :: PRC_LOCAL_setup
  public :: PRC_SINGLECOM_setup
  public :: PRC_abort
  public :: PRC_MPIfinish
  public :: PRC_MPIsplit

  public :: PRC_MPIbarrier
  public :: PRC_MPItime
  public :: PRC_MPItimestat

  public :: PRC_set_file_closer

  public :: PRC_ERRHANDLER_setup

  abstract interface
     subroutine closer( skip_abort )
       logical, intent(in), optional :: skip_abort
     end subroutine closer
  end interface

  !-----------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !
  !-----------------------------------------------------------------------------
  !                          [ communicator system ]
  !    MPI_COMM_WORLD
  !          |
  ! PRC_UNIVERSAL_COMM_WORLD --split--> BULK_COMM_WORLD
  !                                     |
  !                            PRC_GLOBAL_COMM_WORLD --split--> PRC_LOCAL_COMM_WORLD
  !-----------------------------------------------------------------------------
  integer, public, parameter :: PRC_masterrank      = 0    !< master process in each communicator
  integer, public, parameter :: PRC_DOMAIN_nlim = 10000    !< max depth of domains
  integer, public, parameter :: PRC_COMM_NULL = MPI_COMM_NULL

  ! universal world
  integer, public :: PRC_UNIVERSAL_COMM_WORLD = -1      !< original communicator
  integer, public :: PRC_UNIVERSAL_myrank     = -1      !< myrank         in universal communicator
  integer, public :: PRC_UNIVERSAL_nprocs     = -1      !< process num    in universal communicator
  logical, public :: PRC_UNIVERSAL_IsMaster   = .false. !< master process in universal communicator?

  integer, public :: PRC_UNIVERSAL_jobID      = 0       !< my job ID      in universal communicator

  ! global world
  integer, public :: PRC_GLOBAL_COMM_WORLD    = -1      !< global communicator
  integer, public :: PRC_GLOBAL_myrank        = -1      !< myrank         in global communicator
  integer, public :: PRC_GLOBAL_nprocs        = -1      !< process num    in global communicator
  logical, public :: PRC_GLOBAL_IsMaster      = .false. !< master process in global communicator?

  integer, public :: PRC_GLOBAL_domainID      = 0       !< my domain ID   in global communicator
  integer, public :: PRC_GLOBAL_ROOT(PRC_DOMAIN_nlim+1) !< root processes in global members

  ! local world
  integer, public :: PRC_LOCAL_COMM_WORLD     = -1      !< local communicator
  integer, public :: PRC_nprocs               = 1       !< myrank         in local communicator
  integer, public :: PRC_myrank               = 0       !< process num    in local communicator
  logical, public :: PRC_IsMaster             = .false. !< master process in local communicator?

  ! error handling
  logical, public :: PRC_mpi_alive = .false.            !< MPI is alive?
  integer, public :: PRC_UNIVERSAL_handler              !< error handler  in universal communicator
  integer, public :: PRC_ABORT_COMM_WORLD               !< communicator for aborting
  integer, public :: PRC_ABORT_handler                  !< error handler communicator for aborting

  !-----------------------------------------------------------------------------
  !
  !++ Private procedure
  !
  private :: PRC_MPIcoloring
  private :: PRC_sort_ascd

  !-----------------------------------------------------------------------------
  !
  !++ Private parameters & variables
  !
  integer, private, parameter :: PRC_ABORT_code = -1     !< MPI abort code in error handler
!  integer, private, parameter :: PRC_ABORT_code_p = 2 !< mpi abort code in error handler from parent
!  integer, private, parameter :: PRC_ABORT_code_d = 3 !< mpi abort code in error handler from daughter

  procedure(closer), pointer :: PRC_FILE_Closer => NULL()

  !-----------------------------------------------------------------------------
contains
  !-----------------------------------------------------------------------------
  !> Start MPI
  subroutine PRC_MPIstart( &
       comm )
    implicit none

    integer, intent(out) :: comm ! communicator

    integer :: ierr
    !---------------------------------------------------------------------------

    call MPI_Init(ierr)

    PRC_mpi_alive = .true.
!    PRC_UNIVERSAL_handler = MPI_ERRHANDLER_NULL
!    call MPI_COMM_CREATE_ERRHANDLER( PRC_MPI_errorhandler, PRC_UNIVERSAL_handler, ierr )

    comm = MPI_COMM_WORLD
    PRC_ABORT_COMM_WORLD = comm

    return
  end subroutine PRC_MPIstart

  !-----------------------------------------------------------------------------
  !> setup MPI in universal communicator
  subroutine PRC_UNIVERSAL_setup( &
       comm,    &
       nprocs,  &
       ismaster )
    implicit none

    integer, intent(in)  :: comm     ! communicator
    integer, intent(out) :: nprocs   ! number of procs in this communicator
    logical, intent(out) :: ismaster ! master process in this communicator?

    integer :: ierr
    !---------------------------------------------------------------------------

    PRC_UNIVERSAL_COMM_WORLD = comm

    call MPI_Comm_size(PRC_UNIVERSAL_COMM_WORLD,PRC_UNIVERSAL_nprocs,ierr)
    call MPI_Comm_rank(PRC_UNIVERSAL_COMM_WORLD,PRC_UNIVERSAL_myrank,ierr)

    if ( PRC_UNIVERSAL_myrank == PRC_masterrank ) then
       PRC_UNIVERSAL_IsMaster = .true.
    else
       PRC_UNIVERSAL_IsMaster = .false.
    endif

    nprocs   = PRC_UNIVERSAL_nprocs
    ismaster = PRC_UNIVERSAL_IsMaster



!    PRC_ABORT_COMM_WORLD = PRC_UNIVERSAL_COMM_WORLD
!
!    call MPI_Comm_set_errhandler(PRC_ABORT_COMM_WORLD,PRC_UNIVERSAL_handler,ierr)
!    call MPI_Comm_get_errhandler(PRC_ABORT_COMM_WORLD,PRC_ABORT_handler    ,ierr)

    return
  end subroutine PRC_UNIVERSAL_setup

  !-----------------------------------------------------------------------------
  !> setup MPI in global communicator
  subroutine PRC_GLOBAL_setup( &
       abortall, &
       comm      )
    implicit none

    logical, intent(in)  :: abortall ! abort all jobs?
    integer, intent(in)  :: comm     ! communicator

    integer :: ierr
    !---------------------------------------------------------------------------

    PRC_GLOBAL_COMM_WORLD = comm

    call MPI_Comm_size(PRC_GLOBAL_COMM_WORLD,PRC_GLOBAL_nprocs,ierr)
    call MPI_Comm_rank(PRC_GLOBAL_COMM_WORLD,PRC_GLOBAL_myrank,ierr)

    if ( PRC_GLOBAL_myrank == PRC_masterrank ) then
       PRC_GLOBAL_IsMaster = .true.
    else
       PRC_GLOBAL_IsMaster = .false.
    endif

!    if ( .NOT. abortall ) then
!       PRC_ABORT_COMM_WORLD = PRC_GLOBAL_COMM_WORLD
!
!       call MPI_COMM_SET_ERRHANDLER(PRC_ABORT_COMM_WORLD,PRC_UNIVERSAL_handler,ierr)
!       call MPI_COMM_GET_ERRHANDLER(PRC_ABORT_COMM_WORLD,PRC_ABORT_handler    ,ierr)
!    endif

    return
  end subroutine PRC_GLOBAL_setup

  !-----------------------------------------------------------------------------
  !> Setup MPI in local communicator
  subroutine PRC_LOCAL_setup( &
       comm,    &
       myrank,  &
       ismaster )
    implicit none

    integer, intent(in)  :: comm     ! communicator
    integer, intent(out) :: myrank   ! myrank         in this communicator
    logical, intent(out) :: ismaster ! master process in this communicator?

    integer :: ierr
    !---------------------------------------------------------------------------

    PRC_LOCAL_COMM_WORLD = comm

    call MPI_COMM_RANK(PRC_LOCAL_COMM_WORLD,PRC_myrank,ierr)
    call MPI_COMM_SIZE(PRC_LOCAL_COMM_WORLD,PRC_nprocs,ierr)

    if ( PRC_myrank == PRC_masterrank ) then
       PRC_IsMaster = .true.
    else
       PRC_IsMaster = .false.
    endif

    myrank   = PRC_myrank
    ismaster = PRC_IsMaster

    return
  end subroutine PRC_LOCAL_setup

  !-----------------------------------------------------------------------------
  !> Setup MPI single communicator (not use universal-global-local setting)
  subroutine PRC_SINGLECOM_setup( &
       comm,    &
       nprocs,  &
       myrank,  &
       ismaster )
    implicit none

    integer, intent(in)  :: comm     ! communicator
    integer, intent(out) :: nprocs   ! number of procs
    integer, intent(out) :: myrank   ! myrank
    logical, intent(out) :: ismaster ! master process?

    integer :: ierr
    !---------------------------------------------------------------------------

    call MPI_Comm_size(comm,nprocs,ierr)
    call MPI_Comm_rank(comm,myrank,ierr)

    if ( myrank == PRC_masterrank ) then
       ismaster = .true.
    else
       ismaster = .false.
    endif

    PRC_UNIVERSAL_COMM_WORLD = comm
    PRC_UNIVERSAL_nprocs     = nprocs
    PRC_UNIVERSAL_myrank     = myrank
    PRC_UNIVERSAL_IsMaster   = ismaster

    PRC_GLOBAL_COMM_WORLD    = comm
    PRC_GLOBAL_nprocs        = nprocs
    PRC_GLOBAL_myrank        = myrank
    PRC_GLOBAL_IsMaster      = ismaster

    PRC_LOCAL_COMM_WORLD     = comm
    PRC_nprocs               = nprocs
    PRC_myrank               = myrank
    PRC_IsMaster             = ismaster



    PRC_ABORT_COMM_WORLD = comm

!    call MPI_Comm_set_errhandler(PRC_ABORT_COMM_WORLD,PRC_UNIVERSAL_handler,ierr)
!    call MPI_Comm_get_errhandler(PRC_ABORT_COMM_WORLD,PRC_ABORT_handler    ,ierr)

    return
  end subroutine PRC_SINGLECOM_setup

  !-----------------------------------------------------------------------------
  !> Setup MPI error handler
  subroutine PRC_ERRHANDLER_setup( &
       use_fpm, &
       master   )
    implicit none

    logical, intent(in) :: use_fpm ! fpm switch
    logical, intent(in) :: master  ! master flag

    integer :: ierr
    !---------------------------------------------------------------------------

    call MPI_COMM_CREATE_ERRHANDLER(PRC_MPI_errorhandler,PRC_UNIVERSAL_handler,ierr)

    call MPI_COMM_SET_errhandler(PRC_ABORT_COMM_WORLD,PRC_UNIVERSAL_handler,ierr)
    call MPI_COMM_GET_errhandler(PRC_ABORT_COMM_WORLD,PRC_ABORT_handler    ,ierr)

    if ( PRC_UNIVERSAL_handler /= PRC_ABORT_handler ) then
       if( PRC_UNIVERSAL_IsMaster ) write(*,*) ""
       if( PRC_UNIVERSAL_IsMaster ) write(*,*) "ERROR: MPI HANDLER is INCONSISTENT"
       if( PRC_UNIVERSAL_IsMaster ) write(*,*) "     PRC_UNIVERSAL_handler = ", PRC_UNIVERSAL_handler
       if( PRC_UNIVERSAL_IsMaster ) write(*,*) "     PRC_ABORT_handler     = ", PRC_ABORT_handler
       call PRC_abort
    endif

    if ( use_fpm ) then
       call SIGVARS_Get_all( master )
       call signal( SIGINT,  PRC_abort )
       call signal( SIGQUIT, PRC_abort )
       call signal( SIGABRT, PRC_abort )
       call signal( SIGFPE,  PRC_abort )
       call signal( SIGSEGV, PRC_abort )
       call signal( SIGTERM, PRC_abort )
    endif

    return
  end subroutine PRC_ERRHANDLER_setup

  !-----------------------------------------------------------------------------
  !> Abort Process
  subroutine PRC_abort
    implicit none

    integer :: ierr
    !---------------------------------------------------------------------------

    if ( PRC_mpi_alive ) then
       ! tentative approach; input "PRC_UNIVERSAL_COMM_WORLD".
       call MPI_COMM_CALL_ERRHANDLER(PRC_UNIVERSAL_COMM_WORLD,PRC_ABORT_code,ierr)
    endif

    stop
  end subroutine PRC_abort

  !-----------------------------------------------------------------------------
  !> Stop MPI peacefully
  subroutine PRC_MPIfinish
    implicit none

    integer :: ierr
    logical :: sign_status
    logical :: sign_exit
    !---------------------------------------------------------------------------

    ! FPM polling
    if ( FPM_alive ) then
       sign_status = .false.
       sign_exit   = .false.
       do while ( .NOT. sign_exit )
          call FPM_Polling( sign_status, sign_exit )
       enddo
    endif

    if (PRC_UNIVERSAL_handler .NE. MPI_ERRHANDLER_NULL) then
        call MPI_Errhandler_free(PRC_UNIVERSAL_handler, ierr)
    endif
    if (PRC_ABORT_handler .NE. MPI_ERRHANDLER_NULL) then
        call MPI_Errhandler_free(PRC_ABORT_handler, ierr)
    endif

    ! Stop MPI
    if ( PRC_mpi_alive ) then
       LOG_NEWLINE
       LOG_PROGRESS(*) 'finalize MPI...'

       ! free splitted communicator
       if ( PRC_LOCAL_COMM_WORLD  /= PRC_GLOBAL_COMM_WORLD ) then
          call MPI_Comm_free(PRC_LOCAL_COMM_WORLD,ierr)
       endif

       call MPI_Barrier(PRC_UNIVERSAL_COMM_WORLD,ierr)

       call MPI_Finalize(ierr)
       LOG_PROGRESS(*) 'MPI is peacefully finalized'
    endif

    ! Close logfile, configfile
    if ( IO_L ) then
       if( IO_FID_LOG /= IO_FID_STDOUT ) close(IO_FID_LOG)
    endif
    close(IO_FID_CONF)

    return
  end subroutine PRC_MPIfinish

  !-----------------------------------------------------------------------------
  !> MPI Communicator Split
  subroutine PRC_MPIsplit( &
      ORG_COMM,         & ! [in ]
      NUM_DOMAIN,       & ! [in ]
      PRC_DOMAINS,      & ! [in ]
      CONF_FILES,       & ! [in ]
      LOG_SPLIT,        & ! [in ]
      bulk_split,       & ! [in ]
      color_reorder,    & ! [in ]
      INTRA_COMM,       & ! [out]
      inter_parent,     & ! [out]
      inter_child,      & ! [out]
      fname_local       ) ! [out]
    implicit none

    integer,               intent(in)  :: ORG_COMM
    integer,               intent(in)  :: NUM_DOMAIN
    integer,               intent(in)  :: PRC_DOMAINS(:)
    character(len=*),      intent(in)  :: CONF_FILES(:)
    logical,               intent(in)  :: LOG_SPLIT
    logical,               intent(in)  :: bulk_split
    logical,               intent(in)  :: color_reorder
    integer,               intent(out) :: intra_comm
    integer,               intent(out) :: inter_parent
    integer,               intent(out) :: inter_child
    character(len=H_LONG), intent(out) :: fname_local

    integer :: PARENT_COL(PRC_DOMAIN_nlim)        ! parent color number
    integer :: CHILD_COL(PRC_DOMAIN_nlim)         ! child  color number
    integer :: PRC_ROOT(0:PRC_DOMAIN_nlim)        ! root process in the color
    integer, allocatable :: COLOR_LIST(:)   ! member list in each color
    integer, allocatable :: KEY_LIST(:)     ! local process number in each color

    integer :: total_nmax
    integer :: ORG_myrank  ! my rank number in the original communicator
    integer :: ORG_nmax    ! total rank number in the original communicator

    logical :: do_create_p(PRC_DOMAIN_nlim)
    logical :: do_create_c(PRC_DOMAIN_nlim)
    logical :: reordering

    character(len=H_LONG) :: COL_FILE(0:PRC_DOMAIN_nlim)
    character(len=4)      :: col_num

    integer :: i, ii
    integer :: itag, ierr
    !---------------------------------------------------------------------------

    INTRA_COMM   = ORG_COMM
    inter_parent = MPI_COMM_NULL
    inter_child  = MPI_COMM_NULL
    fname_local  = CONF_FILES(1)

    if ( NUM_DOMAIN > 1 ) then ! multi domain run
       call MPI_COMM_RANK(ORG_COMM,ORG_myrank,ierr)
       call MPI_COMM_SIZE(ORG_COMM,ORG_nmax,  ierr)
       allocate( COLOR_LIST(0:ORG_nmax-1) )
       allocate( KEY_LIST  (0:ORG_nmax-1) )

       total_nmax = 0
       do i = 1, NUM_DOMAIN
          total_nmax = total_nmax + PRC_DOMAINS(i)
       enddo
       if ( total_nmax /= ORG_nmax ) then
          if( PRC_UNIVERSAL_IsMaster ) then
             LOG_ERROR("PRC_MPIsplit",*) "MPI PROCESS NUMBER is INCONSISTENT"
             LOG_ERROR_CONT(*) " REQUESTED NPROCS = ", total_nmax, "  LAUNCHED NPROCS = ", ORG_nmax
          end if
          call PRC_abort
       endif

       reordering = color_reorder
       if ( bulk_split ) then
          reordering = .false.
       endif
       call PRC_MPIcoloring( ORG_COMM,    & ! [IN]
                             NUM_DOMAIN,  & ! [IN]
                             PRC_DOMAINS, & ! [IN]
                             CONF_FILES,  & ! [IN]
                             reordering,  & ! [IN]
                             LOG_SPLIT,   & ! [IN]
                             COLOR_LIST,  & ! [OUT]
                             PRC_ROOT,    & ! [OUT]
                             KEY_LIST,    & ! [OUT]
                             PARENT_COL,  & ! [OUT]
                             CHILD_COL,   & ! [OUT]
                             COL_FILE     ) ! [OUT]

       if ( bulk_split ) then
          ii = 1
          do i=0, PRC_DOMAIN_nlim
             PRC_GLOBAL_ROOT(ii) = PRC_ROOT(i)
             ii = ii + 1
          enddo
       endif

       ! split comm_world
       call MPI_COMM_SPLIT(ORG_COMM,               &
                           COLOR_LIST(ORG_myrank), &
                           KEY_LIST(ORG_myrank),   &
                           INTRA_COMM, ierr)
       if ( bulk_split ) then
          write(col_num,'(I4.4)') COLOR_LIST(ORG_myrank)
          fname_local = col_num
          PRC_UNIVERSAL_jobID  = COLOR_LIST(ORG_myrank)
       else
          fname_local = COL_FILE(COLOR_LIST(ORG_myrank))
       endif

       ! set parent-child relationship
       do_create_p(:) = .false.
       do_create_c(:) = .false.
       if ( .NOT. bulk_split ) then
          if ( PRC_UNIVERSAL_IsMaster ) write(*,*)
          if ( PRC_UNIVERSAL_IsMaster ) write(*,*) "INFO [PRC_MPIsplit] Inter-domain relationship information"
          do i = 1, NUM_DOMAIN-1
             if ( PRC_UNIVERSAL_IsMaster ) write(*,'(5x,A,I2.2)')  "Relationship No. ", i
             if ( PRC_UNIVERSAL_IsMaster ) write(*,'(5x,2(A,I2))') "Parent color = ", PARENT_COL(i), &
                                                                   " <=> child color = ", CHILD_COL (i)
             if ( COLOR_LIST(ORG_myrank) == PARENT_COL(i) ) then
                do_create_p(i) = .true.
             elseif ( COLOR_LIST(ORG_myrank) == CHILD_COL(i) ) then
                do_create_c(i) = .true.
             endif
          enddo
       endif

       ! create inter-commnunicator
       inter_parent = MPI_COMM_NULL
       inter_child  = MPI_COMM_NULL
       if ( .NOT. bulk_split ) then
          do i = 1, NUM_DOMAIN-1
             itag = i*100
             if    ( do_create_p(i) ) then ! as a parent
                call MPI_INTERCOMM_CREATE( INTRA_COMM, PRC_masterrank,          &
                                           ORG_COMM,   PRC_ROOT(CHILD_COL(i)),  &
                                           itag, inter_child,  ierr             )
             elseif( do_create_c(i) ) then ! as a child
                call MPI_INTERCOMM_CREATE( INTRA_COMM, PRC_masterrank,          &
                                           ORG_COMM,   PRC_ROOT(PARENT_COL(i)), &
                                           itag, inter_parent, ierr             )
             endif
             call MPI_BARRIER(ORG_COMM, ierr)
          enddo
       endif

       deallocate( COLOR_LIST, KEY_LIST )

    elseif ( NUM_DOMAIN == 1 ) then ! single domain run
       ! if ( PRC_UNIVERSAL_IsMaster ) write (*,*) "INFO [PRC_MPIsplit] a single communicator"
    else
       if ( PRC_UNIVERSAL_IsMaster ) then
          write(*,*)"ERROR [RPC_MPIsplit] REQUESTED DOMAIN NUMBER IS NOT ACCEPTABLE"
       end if
       call PRC_abort
    endif

    return
  end subroutine PRC_MPIsplit

  !-----------------------------------------------------------------------------
  !> Set color and keys for COMM_SPLIT
  subroutine PRC_MPIcoloring( &
      ORG_COMM,        & ! [in ]
      NUM_DOMAIN,      & ! [in ]
      PRC_DOMAINS,     & ! [in ]
      CONF_FILES,      & ! [in ]
      color_reorder,   & ! [in ]
      LOG_SPLIT,       & ! [in ]
      COLOR_LIST,      & ! [out]
      PRC_ROOT,        & ! [out]
      KEY_LIST,        & ! [out]
      PARENT_COL,      & ! [out]
      CHILD_COL,       & ! [out]
      COL_FILE         ) ! [out]
    implicit none

    integer,               intent(in)  :: ORG_COMM
    integer,               intent(in)  :: NUM_DOMAIN
    integer,               intent(in)  :: PRC_DOMAINS(:)
    character(len=*),      intent(in)  :: CONF_FILES(:)
    logical,               intent(in)  :: color_reorder
    logical,               intent(in)  :: LOG_SPLIT
    integer,               intent(out) :: COLOR_LIST(:)             ! member list in each color
    integer,               intent(out) :: PRC_ROOT(0:PRC_DOMAIN_nlim)     ! root process in each color
    integer,               intent(out) :: KEY_LIST(:)               ! local process number in each color
    integer,               intent(out) :: PARENT_COL(:)             ! parent color number
    integer,               intent(out) :: CHILD_COL(:)              ! child  color number
    character(len=H_LONG), intent(out) :: COL_FILE(0:PRC_DOMAIN_nlim) ! conf file in each color

    integer               :: touch         (  PRC_DOMAIN_nlim)
    integer               :: PRC_ORDER     (  PRC_DOMAIN_nlim) ! reordered number of process
    integer               :: ORDER2DOM     (  PRC_DOMAIN_nlim) ! get domain number by order number
    integer               :: DOM2ORDER     (  PRC_DOMAIN_nlim) ! get order number by domain number
    integer               :: DOM2COL       (  PRC_DOMAIN_nlim) ! get color number by domain number
    integer               :: COL2DOM       (0:PRC_DOMAIN_nlim) ! get domain number by color number

    integer               :: RO_PRC_DOMAINS(  PRC_DOMAIN_nlim) ! reordered values
    integer               :: RO_DOM2COL    (  PRC_DOMAIN_nlim) ! reordered values
    integer               :: RO_PARENT_COL (  PRC_DOMAIN_nlim) ! reordered values
    integer               :: RO_CHILD_COL  (  PRC_DOMAIN_nlim) ! reordered values
    character(len=H_LONG) :: RO_CONF_FILES (  PRC_DOMAIN_nlim) ! reordered values

    integer :: ORG_nmax   ! parent domain number
    integer :: id_parent  ! parent domain number
    integer :: id_child   ! child domain number
    integer :: dnum, nprc, order, key
    integer :: i, j
    integer :: ierr
    !---------------------------------------------------------------------------

    ORDER2DOM     (:) = -1
    DOM2ORDER     (:) = -1
    RO_PRC_DOMAINS(:) = -1
    RO_DOM2COL    (:) = -1
    RO_CONF_FILES (:) = ""
    RO_PARENT_COL (:) = -1
    RO_CHILD_COL  (:) = -1

    call MPI_COMM_SIZE(ORG_COMM,ORG_nmax, ierr)

    if ( color_reorder ) then
       !--- make color order
       !    domain num is counted from 1
       !    color num  is counted from 0
       touch    (:) = -1
       PRC_ORDER(:) = PRC_DOMAINS(:)

       call PRC_sort_ascd( PRC_ORDER(1:NUM_DOMAIN), 1, NUM_DOMAIN )

       do i = 1, NUM_DOMAIN
       do j = NUM_DOMAIN, 1, -1
          if ( PRC_DOMAINS(i) == PRC_ORDER(j) .AND. touch(j) < 0 ) then
             DOM2COL(i  ) = j-1 ! domain_num --> color_num
             COL2DOM(j-1) = i   ! color_num  --> domain_num
             touch  (j  ) = 1
             exit
          endif
       enddo
       enddo

       PARENT_COL(:) = -1
       CHILD_COL (:) = -1
       do i = 1, NUM_DOMAIN
          id_parent = i - 1
          id_child  = i + 1

          if ( 1 <= id_parent .AND. id_parent <= NUM_DOMAIN ) then
             PARENT_COL(i) = DOM2COL(id_parent)
          endif
          if ( 1 <= id_child  .AND. id_child  <= NUM_DOMAIN ) then
             CHILD_COL (i) = DOM2COL(id_child)
          endif

          if ( PRC_UNIVERSAL_IsMaster .AND. LOG_SPLIT ) then
             write(*,'(1x,A,I2,1x,A,I2,2(2x,A,I2))') &
             "DOMAIN: ", i, "MY_COL: ", DOM2COL(i), "PARENT: COL= ", PARENT_COL(i), "CHILD: COL= ", CHILD_COL(i)
          endif
       enddo

       !--- reorder following color order
       do i = 1, NUM_DOMAIN
          dnum = COL2DOM(i-1)

          ORDER2DOM     (i)    = dnum
          DOM2ORDER     (dnum) = i
          RO_PRC_DOMAINS(i)    = PRC_DOMAINS(dnum)
          RO_DOM2COL    (dnum) = DOM2COL    (dnum)
          RO_CONF_FILES (i)    = CONF_FILES (dnum)
          RO_PARENT_COL (i)    = PARENT_COL (dnum)
          RO_CHILD_COL  (i)    = CHILD_COL  (dnum)
       enddo

       !--- set relationship by ordering of relationship number
       PARENT_COL(:) = -1
       CHILD_COL (:) = -1
       do i = 1, NUM_DOMAIN-1
          PARENT_COL(i) = RO_PARENT_COL(DOM2ORDER(i+1)) ! from child to parent
          CHILD_COL (i) = RO_CHILD_COL (DOM2ORDER(i)  ) ! from parent to child
       enddo

       if( PRC_UNIVERSAL_IsMaster ) write(*,*)
       if( PRC_UNIVERSAL_IsMaster ) write(*,*) 'INFO [PRC_MPIcoloring] Domain information (with reordering)'
       do i = 1, NUM_DOMAIN
          if( PRC_UNIVERSAL_IsMaster ) write(*,*)
          if( PRC_UNIVERSAL_IsMaster ) write(*,'(5x,2(A,I2.2))') "Order No. ",i," -> Domain No. ", ORDER2DOM(i)
          if( PRC_UNIVERSAL_IsMaster ) write(*,'(5x,A,I5)')      "Number of process      = ", RO_PRC_DOMAINS(i)
          if( PRC_UNIVERSAL_IsMaster ) write(*,'(5x,A,I5)')      "Color of this   domain = ", RO_DOM2COL(ORDER2DOM(i))
          if ( RO_PARENT_COL(i) >= 0 ) then
             if( PRC_UNIVERSAL_IsMaster ) write(*,'(5x,A,I5)')   "Color of parent domain = ", RO_PARENT_COL(i)
          else
             if( PRC_UNIVERSAL_IsMaster ) write(*,'(5x,A)'   )   "Color of parent domain = no parent"
          endif
          if ( RO_CHILD_COL(i) >= 0 ) then
             if( PRC_UNIVERSAL_IsMaster ) write(*,'(5x,A,I5)')   "Color of child  domain = ", RO_CHILD_COL(i)
          else
             if( PRC_UNIVERSAL_IsMaster ) write(*,'(5x,A)'   )   "Color of child  domain = no child"
          endif
          if( PRC_UNIVERSAL_IsMaster ) write(*,'(5x,A,A)')       "Name of config file    = ", trim(RO_CONF_FILES(i))
       enddo

       do i = 1, NUM_DOMAIN
          COL_FILE(i-1) = RO_CONF_FILES(i) ! final copy
       enddo

    else !--- without reordering of colors

       do i = 1, NUM_DOMAIN
          ORDER2DOM     (i) = i
          RO_PRC_DOMAINS(i) = PRC_DOMAINS(i)
          RO_DOM2COL    (i) = i-1
          RO_CONF_FILES (i) = CONF_FILES(i)
       enddo

       do i = 1, NUM_DOMAIN
          id_parent = i - 1
          id_child  = i + 1

          if ( 1 <= id_parent .AND. id_parent <= NUM_DOMAIN ) then
             RO_PARENT_COL(i) = RO_DOM2COL(id_parent)
          endif
          if ( 1 <= id_child  .AND. id_child  <= NUM_DOMAIN ) then
             RO_CHILD_COL (i) = RO_DOM2COL(id_child)
          endif
       enddo

       ! make relationship
       do i = 1, NUM_DOMAIN-1
          PARENT_COL(i) = RO_PARENT_COL(i+1) ! from child to parent
          CHILD_COL (i) = RO_CHILD_COL (i  ) ! from parent to child
       enddo

    endif

    ! make a process table
    order = 1
    key   = 0
    nprc  = RO_PRC_DOMAINS(order)
    PRC_ROOT(:) = -999

    do i = 0, ORG_nmax-1
       COLOR_LIST(i+1) = RO_DOM2COL(ORDER2DOM(order))
       KEY_LIST  (i+1) = key

       if ( key == 0 ) then
          PRC_ROOT(COLOR_LIST(i+1)) = i
          COL_FILE(COLOR_LIST(i+1)) = RO_CONF_FILES(order)
       endif

       if ( LOG_SPLIT .AND. PRC_UNIVERSAL_IsMaster ) then
          write(*,'(5x,4(A,I5))') &
          "PE:", i, " COLOR:", COLOR_LIST(i+1), " KEY:", KEY_LIST(i+1), " PRC_ROOT:", PRC_ROOT(COLOR_LIST(i+1))
       endif

       key = key + 1
       if ( key >= nprc ) then
          order = order + 1
          key   = 0
          nprc  = RO_PRC_DOMAINS(order)
       endif
    enddo

    return
  end subroutine PRC_MPIcoloring

  !-----------------------------------------------------------------------------
  !> quicksort (ascending order)
  recursive subroutine PRC_sort_ascd(a, top, bottom)
    implicit none
    integer, intent(inout) :: a(:)
    integer, intent(in)    :: top, bottom
    integer :: i, j, cnt, trg
    !---------------------------------------------------------------------------
    cnt = a( (top+bottom) / 2 )
    i = top; j = bottom
    do
       do while ( a(i) > cnt ) !ascending evaluation
          i = i + 1
       enddo
       do while ( cnt > a(j) ) !ascending evaluation
          j = j - 1
       enddo
       if ( i >= j ) exit
       trg = a(i);  a(i) = a(j);  a(j) = trg
       i = i + 1
       j = j - 1
    enddo
    if ( top < i-1    ) call PRC_sort_ascd( a, top, i-1    )
    if ( j+1 < bottom ) call PRC_sort_ascd( a, j+1, bottom )
    return
  end subroutine PRC_sort_ascd

  !-----------------------------------------------------------------------------
  !> Barrier MPI
  subroutine PRC_MPIbarrier
    implicit none

    integer  :: ierr
    !---------------------------------------------------------------------------

    if ( PRC_mpi_alive ) then
       call MPI_barrier(PRC_LOCAL_COMM_WORLD,ierr)
    endif

  end subroutine PRC_MPIbarrier

  !-----------------------------------------------------------------------------
  !> Get MPI time
  !> @return time
  function PRC_MPItime() result(time)
    implicit none

    real(DP) :: time
    !---------------------------------------------------------------------------

    if ( PRC_mpi_alive ) then
       time = real(MPI_WTIME(), kind=DP)
    else
       call CPU_TIME(time)
    endif

  end function PRC_MPItime

  !-----------------------------------------------------------------------------
  !> Calc global statistics for timer
  subroutine PRC_MPItimestat( &
      avgvar, &
      maxvar, &
      minvar, &
      maxidx, &
      minidx, &
      var     )
    implicit none

    real(DP), intent(out) :: avgvar(:) !< average
    real(DP), intent(out) :: maxvar(:) !< maximum
    real(DP), intent(out) :: minvar(:) !< minimum
    integer,  intent(out) :: maxidx(:) !< index of maximum
    integer,  intent(out) :: minidx(:) !< index of minimum
    real(DP), intent(in)  :: var(:)    !< values for statistics

    real(DP), allocatable :: statval(:,:)
    integer               :: vsize

    real(DP) :: totalvar
    integer  :: ierr
    integer  :: v, p
    !---------------------------------------------------------------------------

    vsize = size(var(:))

    allocate( statval(vsize,0:PRC_nprocs-1) )
    statval(:,:) = 0.0_DP

    do v = 1, vsize
       statval(v,PRC_myrank) = var(v)
    enddo

    ! MPI broadcast
    do p = 0, PRC_nprocs-1
       call MPI_Bcast( statval(1,p),         &
                       vsize,                &
                       MPI_DOUBLE_PRECISION, &
                       p,                    &
                       PRC_LOCAL_COMM_WORLD, &
                       ierr                  )
    enddo

    do v = 1, vsize
       totalvar = 0.0_DP
       do p = 0, PRC_nprocs-1
          totalvar = totalvar + statval(v,p)
       enddo
       avgvar(v) = totalvar / PRC_nprocs

       maxvar(v)   = maxval(statval(v,:))
       minvar(v)   = minval(statval(v,:))
       maxidx(v:v) = maxloc(statval(v,:))
       minidx(v:v) = minloc(statval(v,:))
    enddo

    deallocate( statval )

    return
  end subroutine PRC_MPItimestat

  !-----------------------------------------------------------------------------
  !> MPI Error Handler
  subroutine PRC_MPI_errorhandler( &
      comm,     &
      errcode   )
    implicit none

    ! attributes are needed to be the same with COMM_ERRHANDLER function
    integer :: comm    !< MPI communicator
    integer :: errcode !< error code

    character(len=MPI_MAX_ERROR_STRING) :: msg
    integer :: len
    integer :: ierr
    logical :: sign_status
    logical :: sign_exit
    !---------------------------------------------------------------------------

!print *, "into errhandler:", PRC_UNIVERSAL_myrank

    ! FPM polling
    if ( FPM_alive ) then
       sign_status = .false.
       sign_exit   = .false.
       do while ( .NOT. sign_exit )
          call FPM_Polling( sign_status, sign_exit )
       enddo
    endif

    ! Print Error Messages
    if ( PRC_mpi_alive ) then
          ! flush 1kbyte
       if ( IO_L ) then
          LOG_PROGRESS(*) 'abort MPI'
          flush(IO_FID_LOG)
       endif

       if ( PRC_IsMaster ) then
          write(*,*) '+++++ BULK   ID       : ', PRC_UNIVERSAL_jobID
          write(*,*) '+++++ DOMAIN ID       : ', PRC_GLOBAL_domainID
          write(*,*) '+++++ MASTER LOCATION : ', PRC_UNIVERSAL_myrank,'/',PRC_UNIVERSAL_nprocs
          write(*,*) '+++++ GLOBAL LOCATION : ', PRC_GLOBAL_myrank,'/',PRC_GLOBAL_nprocs
          write(*,*) '+++++ LOCAL  LOCATION : ', PRC_myrank,'/',PRC_nprocs
          write(*,*) ''
       endif

       if    ( errcode == PRC_ABORT_code ) then ! called from PRC_abort
          ! do nothing
       elseif( errcode <= MPI_ERR_LASTCODE ) then
          call MPI_ERROR_STRING(errcode, msg, len, ierr)
          if( IO_L ) write(IO_FID_LOG,*) '+++++ ', errcode, trim(msg)
          write(*,*)                     '+++++ ', errcode, trim(msg)
       else
          if( IO_L ) write(IO_FID_LOG,*) '+++++ Unexpected error code', errcode
          write(*,*)                     '+++++ Unexpected error code', errcode
       endif

       if ( comm /= PRC_ABORT_COMM_WORLD ) then
          if( IO_L ) write(IO_FID_LOG,*) '+++++ Unexpected communicator'
          write(*,*)                     '+++++ Unexpected communicator'
       endif
       if( IO_L ) write(IO_FID_LOG,*) ''
       write(*,*)                     ''
    endif

    if ( associated( PRC_FILE_CLOSER ) ) call PRC_FILE_Closer( .true. )

    ! Close logfile, configfile
    if ( IO_L ) then
       if( IO_FID_LOG /= IO_FID_STDOUT ) close(IO_FID_LOG)
    endif
    close(IO_FID_CONF)

    ! Abort MPI
    if ( PRC_mpi_alive ) then
       call sleep(5)
       call MPI_ABORT(PRC_ABORT_COMM_WORLD, PRC_ABORT_code, ierr)
    endif

    stop
  end subroutine PRC_MPI_errorhandler

  subroutine PRC_set_file_closer( routine )
    procedure(closer) :: routine

    PRC_FILE_Closer => routine

    return
  end subroutine PRC_set_file_closer

end module scale_prc
