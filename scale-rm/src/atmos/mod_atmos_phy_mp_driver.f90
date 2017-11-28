!-------------------------------------------------------------------------------
!> module atmosphere / physics / cloud microphysics
!!
!! @par Description
!!          Cloud Microphysics driver
!!
!! @author Team SCALE
!!
!<
!-------------------------------------------------------------------------------
#include "inc_openmp.h"
module mod_atmos_phy_mp_driver
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use scale_precision
  use scale_stdio
  use scale_prof
  use scale_grid_index
  use scale_tracer
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: ATMOS_PHY_MP_driver_tracer_setup
  public :: ATMOS_PHY_MP_driver_setup
  public :: ATMOS_PHY_MP_driver_resume
  public :: ATMOS_PHY_MP_driver

  !-----------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !
  !-----------------------------------------------------------------------------
  !
  !++ Private procedure
  !
  !-----------------------------------------------------------------------------
  !
  !++ Private parameters & variables
  !
  logical,  private :: MP_doprecipitation   = .true.  !> apply sedimentation (precipitation)?
  logical,  private :: MP_donegative_fixer  = .true.  !> apply negative fixer?
  real(RP), private :: MP_limit_negative    = 1.0_RP  !> Abort if abs(fixed negative vaue) > abs(MP_limit_negative)
  logical,  private :: MP_doexplicit_icegen = .false. !> apply explicit ice generation?
  integer,  private :: MP_ntmax_sedimentation = 1     !> number of time step for sedimentation
  real(RP), private :: MP_max_term_vel = 10.0_RP      !> terminal velocity for calculate dt of sedimentation
  real(RP), private :: MP_cldfrac_thleshold           !> thleshold for cloud fraction
  logical,  private :: MP_couple_aerosol    = .false. !> apply CCN effect?

  integer,  private :: MP_NSTEP_SEDIMENTATION
  real(RP), private :: MP_RNSTEP_SEDIMENTATION
  real(DP), private :: MP_DTSEC_SEDIMENTATION

  !-----------------------------------------------------------------------------
contains
  !-----------------------------------------------------------------------------
  !> Config
  subroutine ATMOS_PHY_MP_driver_tracer_setup
    use scale_process, only: &
       PRC_abort
    use scale_atmos_hydrometeor, only: &
       ATMOS_HYDROMETEOR_regist
    use scale_atmos_phy_mp_tomita08, only: &
       ATMOS_PHY_MP_TOMITA08_NLIQ, &
       ATMOS_PHY_MP_TOMITA08_NICE, &
       ATMOS_PHY_MP_TOMITA08_NAME, &
       ATMOS_PHY_MP_TOMITA08_DESC, &
       ATMOS_PHY_MP_TOMITA08_UNIT
    use mod_atmos_admin, only: &
       ATMOS_PHY_MP_TYPE, &
       ATMOS_sw_phy_mp
    use mod_atmos_phy_mp_vars, only: &
       QA_MP, &
       QS_MP, &
       QE_MP
    ! obsolute
    use scale_atmos_phy_mp, only: &
       ATMOS_PHY_MP_config, &
       QA_MP_obsolute => QA_MP, &
       QS_MP_obsolute => QS_MP
    implicit none
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '++++++ Module[Tracer Setup] / Categ[ATMOS PHY_MP] / Origin[SCALE-RM]'

    if ( ATMOS_sw_phy_mp ) then
       select case ( ATMOS_PHY_MP_TYPE )
       case ( 'TOMITA08' )
          call ATMOS_HYDROMETEOR_regist( &
               QS_MP,                         & ! [OUT]
               ATMOS_PHY_MP_TOMITA08_NLIQ,    & ! [IN]
               ATMOS_PHY_MP_TOMITA08_NICE,    & ! [IN]
               ATMOS_PHY_MP_TOMITA08_NAME(:), & ! [IN]
               ATMOS_PHY_MP_TOMITA08_DESC(:), & ! [IN]
               ATMOS_PHY_MP_TOMITA08_UNIT(:)  ) ! [IN]
          QA_MP = 1 + ATMOS_PHY_MP_TOMITA08_NLIQ + ATMOS_PHY_MP_TOMITA08_NICE
       case default
          call ATMOS_PHY_MP_config( ATMOS_PHY_MP_TYPE )
          QA_MP = QA_MP_obsolute
          QS_MP = QS_MP_obsolute
          ! if ( IO_L ) write(IO_FID_LOG,*) '+++ ATMOS_PHY_MP_TYPE is invalud: ', trim(ATMOS_PHY_MP_TYPE)
          ! call PRC_abort
       end select
    end if

    QE_MP = QS_MP + QA_MP - 1

    return
  end subroutine ATMOS_PHY_MP_driver_tracer_setup

  !-----------------------------------------------------------------------------
  !> Setup
  subroutine ATMOS_PHY_MP_driver_setup
    use scale_process, only: &
       PRC_abort
    use scale_grid, only: &
       CDZ => GRID_CDZ
    use scale_const, only: &
       EPS => CONST_EPS
    use scale_time, only: &
       TIME_DTSEC_ATMOS_PHY_MP
    use scale_atmos_phy_mp, only: &
       ATMOS_PHY_MP_setup
    use scale_atmos_phy_mp_tomita08, only: &
       ATMOS_PHY_MP_TOMITA08_setup
    use mod_atmos_admin, only: &
       ATMOS_PHY_MP_TYPE, &
       ATMOS_sw_phy_mp
    use mod_atmos_phy_mp_vars, only: &
       SFLX_rain => ATMOS_PHY_MP_SFLX_rain, &
       SFLX_snow => ATMOS_PHY_MP_SFLX_snow
    implicit none
    
    NAMELIST / PARAM_ATMOS_PHY_MP / &
       MP_doprecipitation,     &
       MP_donegative_fixer,    &
       MP_limit_negative,      &
       MP_doexplicit_icegen,   &
       MP_ntmax_sedimentation, &
       MP_max_term_vel,        &
       MP_cldfrac_thleshold,   &
       MP_couple_aerosol

    integer :: nstep_max

    integer :: ierr
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '++++++ Module[DRIVER] / Categ[ATMOS PHY_MP] / Origin[SCALE-RM]'

    if ( ATMOS_sw_phy_mp ) then

       MP_cldfrac_thleshold = EPS

       !--- read namelist
       rewind(IO_FID_CONF)
       read(IO_FID_CONF,nml=PARAM_ATMOS_PHY_MP,iostat=ierr)
       if( ierr < 0 ) then !--- missing
          if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
       elseif( ierr > 0 ) then !--- fatal error
          write(*,*) 'xxx Not appropriate names in namelist PARAM_ATMOS_PHY_MP. Check!'
          call PRC_abort
       endif
       if( IO_NML ) write(IO_FID_NML,nml=PARAM_ATMOS_PHY_MP)

       nstep_max = ceiling( ( TIME_DTSEC_ATMOS_PHY_MP * MP_max_term_vel ) / minval( CDZ(:) ) )
       MP_ntmax_sedimentation = max( MP_ntmax_sedimentation, nstep_max )

       MP_NSTEP_SEDIMENTATION  = MP_ntmax_sedimentation
       MP_RNSTEP_SEDIMENTATION = 1.0_RP / real(MP_ntmax_sedimentation,kind=RP)
       MP_DTSEC_SEDIMENTATION  = TIME_DTSEC_ATMOS_PHY_MP * MP_RNSTEP_SEDIMENTATION

       if( IO_L ) write(IO_FID_LOG,*)
       if( IO_L ) write(IO_FID_LOG,*) '*** Enable negative fixer?                    : ', MP_donegative_fixer
       if( IO_L ) write(IO_FID_LOG,*) '*** Value limit of negative fixer (abs)       : ', abs(MP_limit_negative)
       if( IO_L ) write(IO_FID_LOG,*) '*** Enable sedimentation (precipitation)?     : ', MP_doprecipitation
       if( IO_L ) write(IO_FID_LOG,*) '*** Enable explicit ice generation?           : ', MP_doexplicit_icegen
       if( IO_L ) write(IO_FID_LOG,*) '*** Timestep of sedimentation is divided into : ', MP_ntmax_sedimentation, 'step'
       if( IO_L ) write(IO_FID_LOG,*) '*** DT of sedimentation                       : ', MP_DTSEC_SEDIMENTATION, '[s]'

       select case ( ATMOS_PHY_MP_TYPE )
       case ( 'TOMITA08' )
          call ATMOS_PHY_MP_tomita08_setup( &
               KA, KS, KE, IA, ISB, IEB, JA, JSB, JEB, &
               MP_doexplicit_icegen, &
               MP_couple_aerosol     )
       case default
          ! setup library component
          call ATMOS_PHY_MP_setup
       end select

    else

       if( IO_L ) write(IO_FID_LOG,*) '*** this component is never called.'
       if( IO_L ) write(IO_FID_LOG,*) '*** SFLX_rain and SFLX_snow is set to zero.'
       SFLX_rain(:,:) = 0.0_RP
       SFLX_snow(:,:) = 0.0_RP

    endif

    return
  end subroutine ATMOS_PHY_MP_driver_setup

  !-----------------------------------------------------------------------------
  !> resume
  subroutine ATMOS_PHY_MP_driver_resume
    use mod_atmos_admin, only: &
       ATMOS_sw_phy_mp
    implicit none

    if ( ATMOS_sw_phy_mp ) then

       ! run once (only for the diagnostic value)
       call PROF_rapstart('ATM_Microphysics', 1)
       call ATMOS_PHY_MP_driver( update_flag = .true. )
       call PROF_rapend  ('ATM_Microphysics', 1)

    end if

    return
  end subroutine ATMOS_PHY_MP_driver_resume

  !-----------------------------------------------------------------------------
  !> Driver
  subroutine ATMOS_PHY_MP_driver( update_flag )
    use mod_atmos_admin, only: &
       ATMOS_PHY_MP_TYPE
    use scale_time, only: &
       dt_MP => TIME_DTSEC_ATMOS_PHY_MP
    use scale_grid_real, only: &
       REAL_CZ, &
       REAL_FZ
    use scale_rm_statistics, only: &
       STATISTICS_checktotal, &
       STAT_total
    use scale_history, only: &
       HIST_in
    use scale_atmos_hydrometeor, only: &
       N_HYD, &
       I_HC,  &
       I_HR,  &
       I_HI,  &
       I_HS,  &
       I_HG,  &
       I_HH,  &
       QLA,   &
       QIA
    use scale_atmos_phy_mp, only: &
       ATMOS_PHY_MP,                 &
       ATMOS_PHY_MP_CloudFraction,   &
       ATMOS_PHY_MP_EffectiveRadius, &
       ATMOS_PHY_MP_MixingRatio
    use scale_atmos_phy_mp_common, only: &
       ATMOS_PHY_MP_precipitation, &
       ATMOS_PHY_MP_precipitation_momentum
    use scale_atmos_phy_mp_tomita08, only: &
       ATMOS_PHY_MP_TOMITA08_adjustment, &
       ATMOS_PHY_MP_TOMITA08_terminal_velocity, &
       ATMOS_PHY_MP_TOMITA08_mixing_ratio, &
       ATMOS_PHY_MP_TOMITA08_effective_radius, &
       ATMOS_PHY_MP_TOMITA08_cloud_fraction
    use mod_atmos_vars, only: &
       DENS   => DENS_av, &
       MOMZ   => MOMZ_av, &
       U, &
       V, &
       W, &
       POTT, &
       QTRC   => QTRC_av, &
       DENS_t => DENS_tp, &
       MOMZ_t => MOMZ_tp, &
       RHOU_t => RHOU_tp, &
       RHOV_t => RHOV_tp, &
       RHOT_t => RHOT_tp, &
       RHOQ_t => RHOQ_tp, &
       RHOH   => RHOH_p, &
       TEMP, &
       PRES, &
       CVtot, &
       CPtot, &
       EXNER, &
       MOMX   => MOMX_av, &
       MOMY   => MOMY_av, &
       RHOT   => RHOT_av, &
       MOMX_t => MOMX_tp, &
       MOMY_t => MOMY_tp
    use mod_atmos_phy_mp_vars, only: &
       QA_MP, &
       QS_MP, &
       QE_MP, &
       DENS_t_MP => ATMOS_PHY_MP_DENS_t,    &
       MOMZ_t_MP => ATMOS_PHY_MP_MOMZ_t,    &
       RHOT_t_MP => ATMOS_PHY_MP_RHOT_t,    &
       RHOU_t_MP => ATMOS_PHY_MP_RHOU_t,    &
       RHOV_t_MP => ATMOS_PHY_MP_RHOV_t,    &
       RHOQ_t_MP => ATMOS_PHY_MP_RHOQ_t,    &
       RHOH_MP   => ATMOS_PHY_MP_RHOH,      &
       EVAPORATE => ATMOS_PHY_MP_EVAPORATE, &
       SFLX_rain => ATMOS_PHY_MP_SFLX_rain, &
       SFLX_snow => ATMOS_PHY_MP_SFLX_snow, &
       MOMX_t_MP => ATMOS_PHY_MP_MOMX_t,    &
       MOMY_t_MP => ATMOS_PHY_MP_MOMY_t,    &
       CLDFRAC   => ATMOS_PHY_MP_CLDFRAC,   &
       Re        => ATMOS_PHY_MP_Re,        &
       Qe        => ATMOS_PHY_MP_Qe
    use mod_atmos_phy_ae_vars, only: &
       CCN_t => ATMOS_PHY_AE_CCN_t
    implicit none

    logical, intent(in) :: update_flag

    real(RP) :: TEMP1 (KA,IA,JA)
    real(RP) :: CPtot1(KA,IA,JA)
    real(RP) :: CVtot1(KA,IA,JA)
    real(RP) :: CCN   (KA,IA,JA)
    real(RP) :: vterm (KA,QS_MP+1:QE_MP)

!    real(RP), target :: QTRC1(KA,IA,JA,QS_MP:QA_MP)

    ! obsolute
    real(RP) :: DENS1(KA,IA,JA)
    real(RP) :: MOMZ1(KA,IA,JA)
    real(RP) :: MOMX1(KA,IA,JA)
    real(RP) :: MOMY1(KA,IA,JA)
    real(RP) :: RHOT1(KA,IA,JA)
    real(RP), target :: QTRC1(KA,IA,JA,QA)

    real(RP) :: FLX_hydro(KA)
    real(RP) :: DENS2    (KA)
    real(RP) :: TEMP2    (KA)
    real(RP) :: CPtot2   (KA)
    real(RP) :: CVtot2   (KA)
    real(RP) :: RHOE     (KA)
    real(RP) :: RHOE2    (KA)
    real(RP) :: RHOQ2    (KA,QS_MP+1:QE_MP)
    real(RP) :: mflux    (KA)
    real(RP) :: sflux    (2)  !> 1: rain, 2: snow

    real(RP) :: FDZ (KA)
    real(RP) :: RFDZ(KA)
    real(RP) :: RCDZ(KA)

    real(RP) :: precip   (IA,JA)

    real(RP) :: total ! dummy

    integer :: k, i, j, iq
    integer :: step
    !---------------------------------------------------------------------------

    if ( update_flag ) then

       CCN(:,:,:) = CCN_t(:,:,:) * dt_MP

       ! negative fixer
       ! if ( MP_donegative_fixer ) then
       !!!!!!!!!!!!!!!!!!!!!!!!!!!
       !!!!!!!!!!!!!!!!!!!!!!!!!!!
       ! call ATMOS_PHY_MP_negative_fixer
       ! end if

       select case ( ATMOS_PHY_MP_TYPE )
       case ( 'TOMITA08' )
!OCL XFILL
          TEMP1(:,:,:) = TEMP(:,:,:)
!OCL XFILL
          QTRC1(:,:,:,QS_MP:QE_MP) = QTRC(:,:,:,QS_MP:QE_MP)
!OCL XFILL
          CVtot1(:,:,:) = CVtot(:,:,:)
!OCL XFILL
          CPtot1(:,:,:) = CPtot(:,:,:)

          call ATMOS_PHY_MP_tomita08_adjustment( &
               KA, KS, KE, IA, ISB, IEB, JA, JSB, JEB, &
               DENS(:,:,:), PRES(:,:,:),        & ! [IN]
               CCN(:,:,:),                      & ! [IN]
               dt_MP,                           & ! [IN]
               TEMP1(:,:,:),                    & ! [INOUT]
               QTRC1(:,:,:,QS_MP:QE_MP),        & ! [INOUT]
               CPtot1(:,:,:), CVtot1(:,:,:),    & ! [INOUT]
               RHOH_MP(:,:,:), EVAPORATE(:,:,:) ) ! [OUT]

          do iq = QS_MP, QE_MP
          do j = JSB, JEB
          do i = ISB, IEB
          do k = KS, KE
             RHOQ_t_MP(k,i,j,iq) = ( QTRC1(k,i,j,iq) - QTRC(k,i,j,iq) ) * DENS(k,i,j) / dt_MP
          enddo
          enddo
          enddo
          enddo

          call ATMOS_PHY_MP_tomita08_cloud_fraction( &
               KA, KS, KE, IA, IS, IE, JA, JS, JE, &
               QTRC(:,:,:,QS_MP:QE_MP), & ! [IN]
               MP_cldfrac_thleshold,    & ! [IN]
               CLDFRAC(:,:,:,:)         ) ! [OUT]

          call ATMOS_PHY_MP_tomita08_effective_radius( &
               KA, KS, KE, IA, IS, IE, JA, JS, JE, &
               DENS(:,:,:), TEMP(:,:,:), &
               QTRC(:,:,:,QS_MP:QE_MP),  &
               Re(:,:,:,:)               )

          call ATMOS_PHY_MP_tomita08_mixing_ratio( &
               KA, KS, KE, IA, IS, IE, JA, JS, JE, &
               QTRC(:,:,:,QS_MP:QE_MP), &
               Qe(:,:,:,:)              )

       case default

!OCL XFILL
          DENS1(:,:,:) = DENS(:,:,:) ! save
!OCL XFILL
          MOMZ1(:,:,:) = MOMZ(:,:,:) ! save
!OCL XFILL
          MOMX1(:,:,:) = MOMX(:,:,:) ! save
!OCL XFILL
          MOMY1(:,:,:) = MOMY(:,:,:) ! save
!OCL XFILL
          RHOT1(:,:,:) = RHOT(:,:,:) ! save
!OCL XFILL
          QTRC1(:,:,:,:) = QTRC(:,:,:,:) ! save

          call ATMOS_PHY_MP( DENS1    (:,:,:),   & ! [INOUT]
                             MOMZ1    (:,:,:),   & ! [INOUT]
                             MOMX1    (:,:,:),   & ! [INOUT]
                             MOMY1    (:,:,:),   & ! [INOUT]
                             RHOT1    (:,:,:),   & ! [INOUT]
                             QTRC1    (:,:,:,:), & ! [INOUT]
                             CCN      (:,:,:),   & ! [IN]
                             EVAPORATE(:,:,:),   & ! [OUT]
                             SFLX_rain(:,:),     & ! [OUT]
                             SFLX_snow(:,:)      ) ! [OUT]
!OCL XFILL
          !$omp parallel do default(none) private(i,j,k) OMP_SCHEDULE_ collapse(2) &
          !$omp shared(JSB,JEB,ISB,IEB,KS,KE,DENS_t_MP,DENS1,DENS,MOMZ_t_MP,MOMZ1,MOMZ,MOMX_t_MP,MOMX1) &
          !$omp shared(MOMX,MOMY_t_MP,MOMY1,MOMY,RHOT_t_MP,RHOT1,RHOT,dt_MP)
          do j = JSB, JEB
          do i = ISB, IEB
          do k = KS, KE
             DENS_t_MP(k,i,j) = ( DENS1(k,i,j) - DENS(k,i,j) ) / dt_MP
             MOMZ_t_MP(k,i,j) = ( MOMZ1(k,i,j) - MOMZ(k,i,j) ) / dt_MP
             MOMX_t_MP(k,i,j) = ( MOMX1(k,i,j) - MOMX(k,i,j) ) / dt_MP
             MOMY_t_MP(k,i,j) = ( MOMY1(k,i,j) - MOMY(k,i,j) ) / dt_MP
             RHOT_t_MP(k,i,j) = ( RHOT1(k,i,j) - RHOT(k,i,j) ) / dt_MP
          enddo
          enddo
          enddo

!OCL XFILL
          do iq = QS_MP, QE_MP
          !$omp parallel do default(none) &
          !$omp shared(JSB,JEB,ISB,IEB,KS,KE,RHOQ_t_MP,iq,QTRC1,QTRC,DENS1,DENS,dt_MP) &
          !$omp private(i,j,k) OMP_SCHEDULE_ collapse(2)
          do j  = JSB, JEB
          do i  = ISB, IEB
          do k  = KS, KE
             RHOQ_t_MP(k,i,j,iq) = ( QTRC1(k,i,j,iq) * DENS1(k,i,j) &
                                   - QTRC (k,i,j,iq) * DENS (k,i,j) ) / dt_MP
          enddo
          enddo
          enddo
          enddo

          call ATMOS_PHY_MP_CloudFraction( CLDFRAC(:,:,:,:),    & ! [OUT]
                                           QTRC(:,:,:,:),       & ! [IN]
                                           MP_cldfrac_thleshold ) ! [IN]

          call ATMOS_PHY_MP_EffectiveRadius( Re  (:,:,:,:), & ! [OUT]
                                             QTRC(:,:,:,:), & ! [IN]
                                             DENS(:,:,:),   & ! [IN]
                                             TEMP(:,:,:)    ) ! [IN]

          call ATMOS_PHY_MP_MixingRatio( Qe  (:,:,:,:), & ! [OUT]
                                         QTRC(:,:,:,:)  ) ! [IN]

          MP_doprecipitation = .false.

       end select

       if ( MP_doprecipitation ) then

          do j = JSB, JEB
          do i = ISB, IEB

             FDZ(KS-1) = REAL_CZ(KS,i,j) - REAL_FZ(KS-1,i,j)
             RFDZ(KS-1) = 1.0_RP / FDZ(KS-1)
             do k = KS, KE
                FDZ(k) = REAL_CZ(k+1,i,j) - REAL_CZ(k  ,i,j)
                RFDZ(k) = 1.0_RP / FDZ(k)
                RCDZ(k) = 1.0_RP / ( REAL_FZ(k  ,i,j) - REAL_FZ(k-1,i,j) )
             enddo

             DENS2(:) = DENS(:,i,j)
             TEMP2(:) = TEMP1(:,i,j) ! use updated value
             CPtot2(:) = CPtot1(:,i,j) ! use updated value
             CVtot2(:) = CVtot1(:,i,j) ! use updated value
!             TEMP2(:) = TEMP(:,i,j) ! use original value
!             CPtot2(:) = CPtot(:) ! use original value
!             CVtot2(:) = CVtot(:) ! use original value
             do k = KS, KE
!                RHOE(k) = TEMP(k,i,j) * CVtot(k,i,j) ! use original value
                RHOE(k) = TEMP2(k) * CVtot1(k,i,j) ! use updated value
                RHOE2(k) = RHOE(k)
             end do
             do iq = QS_MP+1, QE_MP
             do k = KS, KE
!                RHOQ2(k,iq) = DENS2(k) * QTRC(k,i,j,iq) ! use original value
                RHOQ2(k,iq) = DENS2(k) * QTRC1(k,i,j,iq) ! use updated value
             end do
             end do

             TEMP2(KE+1) = 0.0_RP

             SFLX_rain(i,j) = 0.0_RP
             SFLX_snow(i,j) = 0.0_RP
             FLX_hydro(:) = 0.0_RP
             do step = 1, MP_NSTEP_SEDIMENTATION

                call ATMOS_PHY_MP_tomita08_terminal_velocity( &
                     KA, KS, KE, &
                     DENS2(:), TEMP2(:), RHOQ2(:,:), & ! [IN]
                     vterm(:,:)                      ) ! [OUT]

                call ATMOS_PHY_MP_precipitation( &
                     KA, KS, KE, QA_MP-1, QLA, QIA, &
                     TEMP2(:), vterm(:,:),   & ! [IN]
                     FDZ(:), RCDZ(:),        & ! [IN]
                     MP_DTSEC_SEDIMENTATION, & ! [IN]
                     i, j,                   & ! [IN]
                     DENS2(:), RHOQ2(:,:),   & ! [INOUT]
                     CPtot2(:), CVtot2(:),   & ! [INOUT]
                     RHOE2(:),               & ! [INOUT]
                     mflux(:), sflux(:)      ) ! [OUT]

                do k = KS, KE
                   TEMP2(k) = RHOE2(k) / CVtot2(k)
                end do

                do k = KS-1, KE-1
                   FLX_hydro(k) = FLX_hydro(k) + mflux(k) * MP_RNSTEP_SEDIMENTATION
                enddo

                SFLX_rain(i,j) = SFLX_rain(i,j) - sflux(1) * MP_RNSTEP_SEDIMENTATION
                SFLX_snow(i,j) = SFLX_snow(i,j) - sflux(2) * MP_RNSTEP_SEDIMENTATION

             enddo

!OCL XFILL
             do k = KS, KE
                DENS_t_MP(k,i,j) = ( DENS2(k) - DENS(k,i,j) ) / dt_MP
             end do

             do k = KS, KE
                RHOH_MP(k,i,j) = RHOH_MP(k,i,j) &
                     + ( RHOE2(k) - RHOE(k) ) / dt_MP
             end do

             do iq = QS_MP+1, QE_MP
             do k  = KS, KE
                RHOQ_t_MP(k,i,j,iq) = RHOQ_t_MP(k,i,j,iq) &
                     + ( RHOQ2(k,iq) - DENS(k,i,j) * QTRC1(k,i,j,iq) ) / dt_MP
             enddo
             enddo

             call ATMOS_PHY_MP_precipitation_momentum( &
                     KA, KS, KE, &
                     DENS(:,i,j), MOMZ(:,i,j), U(:,i,j), V(:,i,j),        & ! [IN]
                     FLX_hydro(:),                                        & ! [IN]
                     RCDZ(:), RFDZ(:),                                    & ! [IN]
                     MOMZ_t_MP(:,i,j), RHOU_t_MP(:,i,j), RHOV_t_MP(:,i,j) ) ! [OUT]

          enddo
          enddo

       end if


!OCL XFILL
       do j = JS, JE
       do i = IS, IE
          precip(i,j) = SFLX_rain(i,j) + SFLX_snow(i,j)
       end do
       end do

       call HIST_in( SFLX_rain(:,:),   'RAIN_MP',   'surface rain rate by MP',          'kg/m2/s',  nohalo=.true. )
       call HIST_in( SFLX_snow(:,:),   'SNOW_MP',   'surface snow rate by MP',          'kg/m2/s',  nohalo=.true. )
       call HIST_in( precip   (:,:),   'PREC_MP',   'surface precipitation rate by MP', 'kg/m2/s',  nohalo=.true. )
       call HIST_in( EVAPORATE(:,:,:), 'EVAPORATE', 'evaporated cloud number',          'num/m3/s', nohalo=.true. )

       call HIST_in( DENS_t_MP(:,:,:), 'DENS_t_MP', 'tendency DENS in MP',  'kg/m3/s'  , nohalo=.true. )
       call HIST_in( MOMZ_t_MP(:,:,:), 'MOMZ_t_MP', 'tendency MOMZ in MP',  'kg/m2/s2' , nohalo=.true. )
       call HIST_in( RHOU_t_MP(:,:,:), 'RHOU_t_MP', 'tendency RHOU in MP',  'kg/m2/s2' , nohalo=.true. )
       call HIST_in( RHOV_t_MP(:,:,:), 'RHOV_t_MP', 'tendency RHOV in MP',  'kg/m2/s2' , nohalo=.true. )
       call HIST_in( RHOT_t_MP(:,:,:), 'RHOT_t_MP', 'tendency RHOT in MP',  'K*kg/m3/s', nohalo=.true. )
       call HIST_in( RHOH_MP  (:,:,:), 'RHOH_MP',   'adiabatic heat in MP', 'J*kg/m3/s', nohalo=.true. )
       call HIST_in( MOMX_t_MP(:,:,:), 'MOMX_t_MP', 'tendency MOMX in MP',  'kg/m2/s2' , nohalo=.true. )
       call HIST_in( MOMY_t_MP(:,:,:), 'MOMY_t_MP', 'tendency MOMY in MP',  'kg/m2/s2' , nohalo=.true. )

       do iq = QS_MP, QE_MP
          call HIST_in( RHOQ_t_MP(:,:,:,iq), trim(TRACER_NAME(iq))//'_t_MP', &
                        'tendency rho*'//trim(TRACER_NAME(iq))//' in MP', 'kg/m3/s', nohalo=.true. )
       enddo

       call HIST_in( Re(:,:,:,I_HC), 'Re_QC', 'effective radius cloud water', 'cm', nohalo=.true. )
       call HIST_in( Re(:,:,:,I_HR), 'Re_QR', 'effective radius rain',        'cm', nohalo=.true. )
       call HIST_in( Re(:,:,:,I_HI), 'Re_QI', 'effective radius ice water',   'cm', nohalo=.true. )
       call HIST_in( Re(:,:,:,I_HS), 'Re_QS', 'effective radius snow',        'cm', nohalo=.true. )
       call HIST_in( Re(:,:,:,I_HG), 'Re_QG', 'effective radius graupel',     'cm', nohalo=.true. )
       call HIST_in( Re(:,:,:,I_HH), 'Re_QH', 'effective radius hail',        'cm', nohalo=.true. )
    endif

    !$omp parallel do default(none) private(i,j,k) OMP_SCHEDULE_ collapse(2) &
    !$omp shared(JS,JE,IS,IE,KS,KE,DENS_t,DENS_t_MP,MOMZ_t,MOMZ_t_MP,MOMX_t,MOMX_t_MP,MOMY_t) &
    !$omp shared(MOMY_t_MP,RHOT_t,RHOT_t_MP)
    do j = JSB, JEB
    do i = ISB, IEB
    do k = KS, KE
       DENS_t(k,i,j) = DENS_t(k,i,j) + DENS_t_MP(k,i,j)
       MOMZ_t(k,i,j) = MOMZ_t(k,i,j) + MOMZ_t_MP(k,i,j)
       RHOU_t(k,i,j) = RHOU_t(k,i,j) + RHOU_t_MP(k,i,j)
       RHOV_t(k,i,j) = RHOV_t(k,i,j) + RHOV_t_MP(k,i,j)
       RHOT_t(k,i,j) = RHOT_t(k,i,j) + RHOT_t_MP(k,i,j)
       RHOH  (k,i,j) = RHOH  (k,i,j) + RHOH_MP  (k,i,j)
       MOMX_t(k,i,j) = MOMX_t(k,i,j) + MOMX_t_MP(k,i,j)
       MOMY_t(k,i,j) = MOMY_t(k,i,j) + MOMY_t_MP(k,i,j)
    enddo
    enddo
    enddo

    do iq = QS_MP, QE_MP
    !$omp parallel do default(none) private(i,j,k) OMP_SCHEDULE_ &
    !$omp shared(JSB,JEB,ISB,IEB,KS,KE,RHOQ_t,iq,RHOQ_t_MP)
    do j = JSB, JEB
    do i = ISB, IEB
    do k = KS, KE
       RHOQ_t(k,i,j,iq) = RHOQ_t(k,i,j,iq) + RHOQ_t_MP(k,i,j,iq)
    enddo
    enddo
    enddo
    enddo

    if ( STATISTICS_checktotal ) then
       call STAT_total( total, DENS_t_MP(:,:,:), 'DENS_t_MP' )
       call STAT_total( total, MOMZ_t_MP(:,:,:), 'MOMZ_t_MP' )
       call STAT_total( total, MOMX_t_MP(:,:,:), 'MOMX_t_MP' )
       call STAT_total( total, MOMY_t_MP(:,:,:), 'MOMY_t_MP' )
       call STAT_total( total, RHOT_t_MP(:,:,:), 'RHOT_t_MP' )

       do iq = QS_MP, QE_MP
          call STAT_total( total, RHOQ_t_MP(:,:,:,iq), trim(TRACER_NAME(iq))//'_t_MP' )
       enddo
    endif

    return
  end subroutine ATMOS_PHY_MP_driver

end module mod_atmos_phy_mp_driver
