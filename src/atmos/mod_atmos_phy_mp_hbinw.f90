!-------------------------------------------------------------------------------
!> Module Spectran Bin Microphysical Module in SCALE-LED ver. 3
!!
!! @par Description:
!!      This module contains subroutines for the Spectral Bin Model
!!
!! - Reference
!!  - Suzuki et al., 2006!!    Correlation Pattern between Effective Radius and Optical Thickness of Water Clouds Simulated by a Spectral Bin Microphysics Cloud Model
!!    SOLA, 2: 116–119 doi:10.2151/sola.2006‒030
!!  - Suzuki et al., 2010!!    A Study of Microphysical Mechanisms for Correlation Patterns between Droplet Radius and Optical Thickness of Warm Clouds with a Spectral Bin
!!    J. Atmos. Sci., 67: 1126-1141
!!  - Sato et al., 2009!!    Application of a Monte Carlo integration method to collision and coagulation growth processes of hydrometeors in a bin-type model
!!    J. Geophy. Res., 114: D09215, doi:10.1029/2008JD011247
!!
!! @author : Team SCALE
!!
!! @par History: Hbinw
!! @li  ver.0.00   2012-06-14 (Y.Sato) [new] Import from version 4.1 of original code
!! @li  ver.0.01   2012-09-14 (Y.Sato) [mod] add a stochastic method (Sato et al. 2009)
!! @li  ver.0.01   2013-02-12 (Y.Sato) [mod] modified for latest version
!<
!-------------------------------------------------------------------------------
#include "macro_thermodyn.h"
module mod_atmos_phy_mp
  !-----------------------------------------------------------------------------
  !
  !++ Used modules
  !
  use mod_stdio, only: &
     IO_FID_LOG,  &
     IO_L
  use mod_time, only: &
     TIME_rapstart, &
     TIME_rapend
  use mod_const, only: &
     pi => CONST_PI, &
     CONST_CPdry, &
     CONST_CVdry, &
     CONST_DWATR, &
     CONST_GRAV, &
     CONST_Rvap, &
     CONST_Rdry, &
     CONST_LH0, &
     CONST_LHS0, &
     CONST_EMELT, &
     CONST_TEM00, &
     CONST_TMELT, &
     CONST_PSAT0, &
     CONST_PRE00, &
     CONST_CPovCV, &
     CONST_RovCP
  use mod_history, only: &
     HIST_in
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: ATMOS_PHY_MP_setup
  public :: ATMOS_PHY_MP
  public :: ATMOS_PHY_MP_CloudFraction
  public :: ATMOS_PHY_MP_EffectiveRadius
  public :: ATMOS_PHY_MP_Mixingratio

  !-----------------------------------------------------------------------------
  !
  !++ included parameters
  !
  include 'inc_precision.h'
  include 'inc_index.h'
  include 'inc_tracer.h'
  !-----------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !
  !-----------------------------------------------------------------------------
  real(RP), public, save :: MP_DENS(MP_QA)     ! hydrometeor density [kg/m3]=[g/L]

  !-----------------------------------------------------------------------------
  !
  !++ Private procedure
  !
  !-----------------------------------------------------------------------------
  !
  !++ Private parameters
  !
  !--- Indeces
  integer, parameter :: il = 1

  !--- bin information of hydrometeors
  real(RP) :: xctr( nbin )         !--- log( m ) value of bin center
  real(RP) :: xbnd( nbin+1 )       !--- log( m ) value of bin boundary
  real(RP) :: radc( nbin )         !--- radius of hydrometeor at bin center [m]
  real(RP) :: dxmic                !--- d( log(m) ) of hydrometeor bin
  real(RP) :: cctr( 7,nbin )       !--- capacitance of hydrometeor at bin center
  real(RP) :: cbnd( 7,nbin+1 )     !--- capacitance of hydrometeor at bin boundary
  real(RP) :: ck( 7,7,nbin,nbin )  !-- collection kernel
  real(RP) :: vt( 7,nbin )         !--- terminal velocity of hydrometeor [m/s]
  real(RP) :: br( 7,nbin )         !--- bulk density of hydrometeor [kg/m^3]
  !--- bin information of aerosol (not supported)
  real(RP) :: xactr( nccn )        !--- log( ma ) value of bin center
  real(RP) :: xabnd( nccn+1 )      !--- log( ma ) value of bin boundary
  real(RP) :: dxaer                !--- d( log(ma) ) of aerosol bin
  real(RP) :: xasta
  real(RP) :: xaend
  real(RP) :: rada( nccn )
  real(RP) :: sfc_precp
  real(RP), allocatable, save :: velw( :,:,:,: )
  integer, private, save :: MP_NSTEP_SEDIMENTATION
  real(RP), private, save :: MP_RNSTEP_SEDIMENTATION
  real(RP), private, save :: MP_DTSEC_SEDIMENTATION
  integer, private, save :: ntmax_sedimentation= 1

  !--- constant for bin
  real(RP), parameter :: cldmin = 1.0E-10_RP, eps = 1.0E-30_RP
  real(RP), parameter :: OneovThird = 1.0_RP/3.0_RP, ThirdovForth = 3.0_RP/4.0_RP
  real(RP), parameter :: TwoovThird = 2.0_RP/3.0_RP
  !--- constant for aerosol
  real(RP) :: rhoa   = 2.25E+03_RP         ! density of aerosol ( NaCl )
  real(RP) :: emaer  = 58.0_RP             ! molecular weight of aerosol ( salt )
  real(RP) :: emwtr  = 18.0_RP             ! molecular weight of water
  real(RP) :: rasta  = 1.E-08_RP           ! minimum radius of aerosol (m)
  real(RP) :: raend  = 1.E-06_RP           ! maximum radius of aerosol (m)
  real(RP) :: r0a    = 1.E-07_RP           ! average radius of aerosol (m)
  logical :: flg_regeneration=.false.      ! flag regeneration of aerosol
  logical :: flg_nucl=.false.              ! flag nucleated cloud move into smallest bin
  logical :: flg_icenucl=.false.           ! flag ice nucleation
  logical :: flg_sf_aero =.false.          ! flag surface flux of aerosol
  integer, private, save :: rndm_flgp = 0  ! flag for sthastic integration for coll.-coag.
  logical, private, save :: doautoconversion = .true.
  logical, private, save :: doprecipitation  = .true.
  logical, private, save :: donegative_fixer = .true.  ! apply negative fixer?

  real(RP) :: marate( nccn )               ! mass rate of each aerosol bin to total aerosol mass
  integer, private, save       :: K10_1, K10_2        ! scaling factor for 10m value (momentum)
  real(RP), private, save      :: R10M1, R10M2        ! scaling factor for 10m value (momentum)
  real(RP), private, save      :: R10H1, R10H2        ! scaling factor for 10m value (heat)
  real(RP), private, save      :: R10E1, R10E2        ! scaling factor for 10m value (tracer)

  character(11),parameter :: fname_micpara="micpara.dat"
  integer(4) :: fid_micpara

  !--- Use for stochastic method
  integer, allocatable :: blrg( :,: ), bsml( :,: )
  real(RP) :: wgtbin
  integer  :: mspc = 49
  integer  :: mbin = nbin/2
  real(RP), private :: rndm(1,1,1)
  !----------------------------------------------------------------------------
contains
  !-----------------------------------------------------------------------------
  !> Setup Cloud Microphysics
  !-----------------------------------------------------------------------------
  subroutine ATMOS_PHY_MP_setup
    use mod_stdio, only: &
      IO_get_available_fid, &
      IO_FID_CONF
    use mod_process, only: &
      PRC_MPIstop
    use mod_grid, only: &
      CDZ => GRID_CDZ, &
      CZ  => GRID_CZ,  &
      FZ  => GRID_FZ
    use mod_atmos_vars, only: &
      ATMOS_TYPE_PHY_MP
    use mod_time, only: &
       TIME_DTSEC_ATMOS_PHY_MP
    use mod_const, only: &
       CONST_DWATR
    implicit none
    !---------------------------------------------------------------------------

    real(RP) :: ATMOS_PHY_MP_RHOA  !--- density of aerosol
    real(RP) :: ATMOS_PHY_MP_EMAER !--- moleculer weight of aerosol
    real(RP) :: ATMOS_PHY_MP_RAMIN !--- minimum radius of aerosol (um)
    real(RP) :: ATMOS_PHY_MP_RAMAX !--- maximum radius of aerosol (um)
    real(RP) :: ATMOS_PHY_MP_R0A   !--- maximum radius of aerosol (um)
    logical :: ATMOS_PHY_MP_FLAG_REGENE  !--- flag of regeneration
    logical :: ATMOS_PHY_MP_FLAG_NUCLEAT !--- flag of regeneration
    logical :: ATMOS_PHY_MP_FLAG_ICENUCLEAT !--- flag of regeneration
    logical :: ATMOS_PHY_MP_FLAG_SFAERO  !--- flag of surface flux of aeorol
    integer :: ATMOS_PHY_MP_RNDM_FLGP  !--- flag of surface flux of aeorol
    integer :: ATMOS_PHY_MP_RNDM_MSPC
    integer :: ATMOS_PHY_MP_RNDM_MBIN


    NAMELIST / PARAM_ATMOS_PHY_MP / &
       ATMOS_PHY_MP_RHOA,  &
       ATMOS_PHY_MP_EMAER, &
       ATMOS_PHY_MP_RAMIN, &
       ATMOS_PHY_MP_RAMAX, &
       ATMOS_PHY_MP_FLAG_REGENE,  &
       ATMOS_PHY_MP_FLAG_NUCLEAT, &
       ATMOS_PHY_MP_FLAG_ICENUCLEAT, &
       ATMOS_PHY_MP_FLAG_SFAERO,  &
       ATMOS_PHY_MP_R0A,   &
       ATMOS_PHY_MP_RNDM_FLGP, &
       ATMOS_PHY_MP_RNDM_MSPC, &
       ATMOS_PHY_MP_RNDM_MBIN, &
       doautoconversion, &
       doprecipitation, &
       donegative_fixer

    integer :: nnspc, nnbin
    integer :: nn, mm, mmyu, nnyu
    integer :: myu, nyu, i, j, k, n, ierr


    ATMOS_PHY_MP_RHOA = rhoa
    ATMOS_PHY_MP_EMAER = emaer
    ATMOS_PHY_MP_RAMIN = rasta
    ATMOS_PHY_MP_RAMAX = raend
    ATMOS_PHY_MP_R0A = r0a
    ATMOS_PHY_MP_FLAG_REGENE = flg_regeneration
    ATMOS_PHY_MP_FLAG_NUCLEAT = flg_nucl
    ATMOS_PHY_MP_FLAG_ICENUCLEAT = flg_icenucl
    ATMOS_PHY_MP_FLAG_SFAERO = flg_sf_aero
    ATMOS_PHY_MP_RNDM_FLGP = rndm_flgp
    ATMOS_PHY_MP_RNDM_MSPC = mspc
    ATMOS_PHY_MP_RNDM_MBIN = mbin

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[Cloud Microphisics]/Categ[ATMOS]'
    if( IO_L ) write(IO_FID_LOG,*) '*** Wrapper for SBM (warm cloud)'

    if ( ATMOS_TYPE_PHY_MP .ne. 'HBINW' ) then
       if ( IO_L ) write(IO_FID_LOG,*) 'xxx ATMOS_TYPE_PHY_MP is not HBINW. Check!'
       call PRC_MPIstop
    end if

    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_ATMOS_PHY_MP,iostat=ierr)

    if( ierr < 0 ) then !--- missing
     if( IO_L ) write(IO_FID_LOG,*)  '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
     write(*,*) 'xxx Not appropriate names in namelist PARAM_ATMOS_PHY_MP, Check!'
     call PRC_MPIstop
    end if
    if( IO_L ) write(IO_FID_LOG,nml=PARAM_ATMOS_PHY_MP)

    rhoa = ATMOS_PHY_MP_RHOA
    emaer = ATMOS_PHY_MP_EMAER
    rasta = ATMOS_PHY_MP_RAMIN
    raend = ATMOS_PHY_MP_RAMAX
    r0a   = ATMOS_PHY_MP_R0A
    flg_regeneration = ATMOS_PHY_MP_FLAG_REGENE
    flg_nucl = ATMOS_PHY_MP_FLAG_NUCLEAT
    flg_icenucl = ATMOS_PHY_MP_FLAG_ICENUCLEAT
    flg_sf_aero = ATMOS_PHY_MP_FLAG_SFAERO
    rndm_flgp = ATMOS_PHY_MP_RNDM_FLGP
    mspc = ATMOS_PHY_MP_RNDM_MSPC
    mbin = ATMOS_PHY_MP_RNDM_MBIN

    fid_micpara = IO_get_available_fid()
    !--- open parameter of cloud microphysics
    open ( fid_micpara, file = fname_micpara, form = 'formatted', status = 'old' )

    read( fid_micpara,* ) nnspc, nnbin

    ! grid parameter
    if( IO_L ) write(IO_FID_LOG,*)  '*** Radius of cloud ****'
    do n = 1, nbin
      read( fid_micpara,* ) nn, xctr( n ), radc( n )
      if( IO_L ) write(IO_FID_LOG,'(a,1x,i3,1x,a,1x,e15.7,1x,a)')  "Radius of ", n, "th cloud bin (bin center)= ", radc( n ) , "[m]"
    end do
    do n = 1, nbin+1
      read( fid_micpara,* ) nn, xbnd( n )
    end do
    read( fid_micpara,* ) dxmic
    if( IO_L ) write(IO_FID_LOG,*)  '*** Width of Cloud SDF= ', dxmic

    ! capacity
    do myu = 1, 7
     do n = 1, nbin
      read( fid_micpara,* ) mmyu, nn, cctr( myu,n )
     end do
     do n = 1, nbin+1
      read( fid_micpara,* ) mmyu, nn, cbnd( myu,n )
     end do
    end do

    ! collection kernel
    do myu = 1, 7
     do nyu = 1, 7
      do i = 1, nbin
       do j = 1, nbin
        read( fid_micpara,* ) mmyu, nnyu, mm, nn, ck( myu,nyu,i,j )
       enddo
      enddo
     enddo
    enddo

    ! terminal velocity
    do myu = 1, 7
     do n = 1, nbin
      read( fid_micpara,* ) mmyu, nn, vt( myu,n )
     enddo
    enddo

    ! bulk density
    do myu = 1, 7
     do n = 1, nbin
      read( fid_micpara,* ) mmyu, nn, br( myu,n )
     enddo
    enddo

    close ( fid_micpara )

    !--- aerosol ( CCN ) (not supported)
    xasta = log( rhoa*4.0_RP/3.0_RP*pi * ( rasta )**3 )
    xaend = log( rhoa*4.0_RP/3.0_RP*pi * ( raend )**3 )

    dxaer = ( xaend-xasta )/nccn

    do n = 1, nccn+1
     xabnd( n ) = xasta + dxaer*( n-1 )
    enddo
    do n = 1, nccn
     xactr( n ) = ( xabnd( n )+xabnd( n+1 ) )*0.50_RP
     rada( n )  = ( exp( xactr( n ) )*ThirdovForth/pi/rhoa )**( OneovThird )
     if( IO_L ) write(IO_FID_LOG,'(a,1x,i3,1x,a,1x,e15.7,1x,a)')  "Radius of ", n, "th aerosol bin (bin center)= ", rada( n ) , "[m]"
    enddo

    if( flg_sf_aero ) then
     if ( CZ(KS) >= 10.0_RP ) then
          R10M1 = 10.0_RP / CZ(KS) * 0.50_RP ! scale with height
          R10M2 = 10.0_RP / CZ(KS) * 0.50_RP ! scale with height
          R10H1 = 1.0_RP * 0.50_RP
          R10H2 = 1.0_RP * 0.0_RP
          R10E1 = 1.0_RP * 0.50_RP
          R10E2 = 1.0_RP * 0.50_RP
          K10_1 = KS
          K10_2 = KS
     else
       k = 1
       do while ( CZ(k) < 10.0_RP )
          k = k + 1
          K10_1 = k
          K10_2 = k + 1
          R10M1 = ( CZ(k+1) - 10.0_RP ) / CDZ(k)
          R10M2 = ( 10.0_RP   - CZ(k) ) / CDZ(k)
          R10H1 = ( CZ(k+1) - 10.0_RP ) / CDZ(k)
          R10H2 = ( 10.0_RP   - CZ(k) ) / CDZ(k)
          R10E1 = ( CZ(k+1) - 10.0_RP ) / CDZ(k)
          R10E2 = ( 10.0_RP   - CZ(k) ) / CDZ(k)
       enddo
     endif
    endif

    MP_DENS(I_mp_QC)  = CONST_DWATR

    !--- random number setup for stochastic method
    if( rndm_flgp > 0 ) then
     call random_setup( IA*JA*KA )
    endif

    allocate( velw(KA,IA,JA,QA) )
    velw(:,:,:,I_QV) = 0.0_RP
    velw(:,:,:,QQE+1:QA) = 0.0_RP
    mm = 0
    do n = 1, nbin
      velw(:,:,:,n+I_QV) = -vt( 1,n )
    enddo

    MP_NSTEP_SEDIMENTATION  = ntmax_sedimentation
    MP_RNSTEP_SEDIMENTATION = 1.0_RP / real(ntmax_sedimentation,kind=RP)
    MP_DTSEC_SEDIMENTATION  = TIME_DTSEC_ATMOS_PHY_MP * MP_RNSTEP_SEDIMENTATION

    return
  end subroutine ATMOS_PHY_MP_setup

  !-----------------------------------------------------------------------------
  !> Cloud Microphysics
  !-----------------------------------------------------------------------------
  subroutine ATMOS_PHY_MP
    use mod_time, only: &
       TIME_DTSEC_ATMOS_PHY_MP, &
       TIME_NOWDAYSEC
    use mod_grid, only : &
       GRID_CZ,  &
       GRID_FZ,  &
       GRID_CDZ, &
       GRID_FDZ
    use mod_comm, only: &
       COMM_vars8, &
       COMM_wait
    use mod_atmos_vars, only: &
       ATMOS_vars_total,   &
       DENS, &
       MOMX, &
       MOMY, &
       MOMZ, &
       RHOT, &
       QTRC
    use mod_atmos_thermodyn, only : &
       AQ_CV, &
       AQ_CP
    use mod_atmos_precipitation, only : &
       precipitation => ATMOS_PRECIPITATION
    use mod_atmos_phy_mp_common, only: &
       MP_negative_fixer => ATMOS_PHY_MP_negative_fixer
    use mod_atmos_saturation, only : &
       pres2qsat_liq => ATMOS_SATURATION_pres2qsat_liq,   &
       pres2qsat_ice => ATMOS_SATURATION_pres2qsat_ice
    implicit none

    real(RP) :: dz (KA)
    real(RP) :: dzh(KA)
    real(RP) :: dt
    real(RP) :: ct

    real(RP) :: temp_mp  (KA,IA,JA)
    real(RP) :: pres_mp  (KA,IA,JA)
    real(RP) :: gdgc     (KA,IA,JA,nbin) !-- SDF of hydrometeors [kg/m^3/unit ln(r)]
    real(RP) :: qv_mp    (KA,IA,JA)      !-- Qv [kg/kg]
    real(RP) :: wfall( KA )
    real(RP) :: gdga     (KA,IA,JA,nccn) !-- SDF of aerosol (not supported)

    real(RP) :: ssliq, ssice, sum1, rtotal, sum2
    integer :: n, k, i, j, iq
    logical, save :: ofirst_sdfa = .true.

    real(RP) :: VELX(IA,JA)
    real(RP) :: VELY(IA,JA)
    real(RP) :: SFLX_AERO(IA,JA,nccn)
    real(RP) :: Uabs, bparam
    real(RP) :: AMR(KA,IA,JA)

    real(RP) :: rhogq(KA,IA,JA,QA)
    real(RP) :: rrhog(KA,IA,JA)
    real(RP) :: q(KA,IA,JA,QA)
    real(RP) :: qd(KA,IA,JA)
    real(RP) :: cva(KA,IA,JA)
    real(RP) :: cpa(KA,IA,JA)
    real(RP) :: rhoge(KA,IA,JA)
    real(RP) :: th(KA,IA,JA)
    real(RP) :: Rmoist

    real(RP) :: wflux_rain(KA,IA,JA)
    real(RP) :: wflux_snow(KA,IA,JA)
    real(RP) :: flux_rain (KA,IA,JA)
    real(RP) :: flux_snow (KA,IA,JA)
    real(RP) :: flux_prec (IA,JA)
    integer  :: step
    !---------------------------------------------------------------------------

#ifdef _FPCOLL_
call START_COLLECTION("MICROPHYSICS")
#endif

     if( donegative_fixer ) then
       call MP_negative_fixer( DENS(:,:,:),  & ! [INOUT]
                               RHOT(:,:,:),  & ! [INOUT]
                               QTRC(:,:,:,:) ) ! [INOUT]
       QTRC(:,:,:,QQE+1:QA) = max( QTRC(:,:,:,QQE+1:QA),0.0_RP )
     endif


    if( IO_L ) write(IO_FID_LOG,*) '*** Physics step: Microphysics(SBM-liquid only)'

    if( flg_sf_aero ) then
     do j = JS-2, JE+2
     do i = IS-2, IE+1
       VELX(i,j) = MOMX(K10_1,i,j) / ( DENS(K10_1,i+1,j)+DENS(K10_1,i,j) ) * R10M1 &
                 + MOMX(K10_2,i,j) / ( DENS(K10_2,i+1,j)+DENS(K10_2,i,j) ) * R10M2
     enddo
     enddo

     do j = JS-2, JE+1
     do i = IS-2, IE+2
       VELY(i,j) = MOMY(K10_1,i,j) / ( DENS(K10_1,i,j+1)+DENS(K10_1,i,j) ) * R10M1 &
                 + MOMY(K10_2,i,j) / ( DENS(K10_2,i,j+1)+DENS(K10_2,i,j) ) * R10M2
     enddo
     enddo
    end if

    call TIME_rapstart('MPX ijkconvert')
    dz (:) = GRID_CDZ(:)
    dzh(1) = GRID_FDZ(1)
    dzh(2:KA) = GRID_FDZ(1:KA-1)

    dt = TIME_DTSEC_ATMOS_PHY_MP
    ct = TIME_NOWDAYSEC

    gdgc(:,:,:,:) = 0.0_RP
    gdga(:,:,:,:) = 0.0_RP
    pres_mp(:,:,:) = 0.0_RP
    temp_mp(:,:,:) = 0.0_RP
    qv_mp(:,:,:) = 0.0_RP
    do j = JS, JE
    do i = IS, IE

       do k = KS-1, KE+1
          rrhog(k,i,j) = 1.0_RP / DENS(k,i,j)
          q(k,i,j,1:QA) = QTRC(k,i,j,1:QA)
       enddo
       do k = KS, KE
          th(k,i,j) = RHOT(k,i,j) * rrhog(k,i,j)
       enddo
       do k = KS, KE
          CALC_QDRY( qd(k,i,j), q, k, i, j, iq )
       enddo
       do k = KS, KE
          CALC_CV( cva(k,i,j), qd(k,i,j), q, k, i, j, iq, CONST_CVdry, AQ_CV )
       enddo
       do k = KS, KE
          CALC_R( Rmoist, q(k,i,j,I_QV), qd(k,i,j), CONST_Rdry, CONST_Rvap )
          cpa(k,i,j) = cva(k,i,j) + Rmoist
          CALC_PRE( pres_mp(k,i,j), DENS(k,i,j), th(k,i,j), Rmoist, cpa(k,i,j), CONST_PRE00 )
          temp_mp(k,i,j) = pres_mp(k,i,j) / ( DENS(k,i,j) * Rmoist )
          qv_mp(k,i,j) = QTRC(k,i,j,I_QV)

          do n = 1, nbin
           gdgc( k,i,j,n ) = &
               QTRC(k,i,j,n+I_QV)*DENS(k,i,j)/dxmic
          end do
          do n = 1, nccn
           gdga( k,i,j,n ) = &
               QTRC(k,i,j,n+nbin+I_QV)*DENS(k,i,j)/dxaer
          end do
          !--- store initial SDF of aerosol
          if( ofirst_sdfa ) then
           sum2 = 0.0_RP
           do n = 1, nccn
             marate( n ) = gdga(k,i,j,n)/exp( xactr( n ) )
             sum2 = sum2 + gdga(k,i,j,n)/exp( xactr( n ) )
           end do
           if( sum2 /= 0.0_RP ) then
            marate( 1:nccn ) = marate( 1:nccn )/sum2
            ofirst_sdfa = .false.
           end if
          end if
       enddo

    enddo
    enddo

    call TIME_rapend  ('MPX ijkconvert')

    do k = KS, KE
    do j = JS, JE
    do i = IS, IE

!      call getsups &
!        (  qv_mp(k,i,j), temp_mp(k,i,j), pres_mp(k,i,j), &
!           ssliq, ssice )

      call pres2qsat_liq( ssliq,temp_mp(k,i,j),pres_mp(k,i,j) )
      call pres2qsat_ice( ssice,temp_mp(k,i,j),pres_mp(k,i,j) )
      ssliq = qv_mp(k,i,j)/ssliq-1.0_RP
      ssice = qv_mp(k,i,j)/ssice-1.0_RP

      sum1 = 0.0_RP
      do n = 1, nbin
        sum1 = sum1 + gdgc(k,i,j,n)*dxmic
      end do

      if( ssliq > 0.0_RP .or. sum1 > cldmin ) then
       call mp_hbinw_evolve                    &
            ( pres_mp(k,i,j), DENS(k,i,j), dt, &  !--- in
              gdgc(k,i,j,1:nbin),              &  !--- inout
              gdga(k,i,j,1:nccn),              &  !--- inout  for aerosol tracer
              qv_mp(k,i,j), temp_mp(k,i,j)     )  !--- inout
      end if

    end do
    end do
    end do


    !--- SURFACE FLUX by Monahan et al. (1986)
    if( flg_sf_aero ) then
     do j = JS-1, JE
     do i = IS-1, IE
       Uabs = sqrt(  ( ( VELX(i,j) + VELX(i-1,j  ) ) * 0.50_RP )**2 &
                   + ( ( VELY(i,j) + VELY(i  ,j-1) ) * 0.50_RP )**2 )
       do n = 1, nccn
        if( rada( n ) <= 2.0E-5_RP .and. rada( n ) >= 3.0E-7_RP ) then
         bparam = ( 0.38_RP - log( rada( n ) ) )/0.65_RP
         SFLX_AERO(i,j,n) = 1.373_RP * Uabs**( 3.41_RP ) * rada( n )**( -3.0_RP ) &
                          * ( 1.0_RP + 0.057_RP * rada( n )**( 1.05_RP ) ) &
                          * 10.0_RP**( 1.19_RP * exp( -bparam*bparam ) )
         ! convert from [#/m^2/um/s] -> [kg/m^3/unit log (m)]
         SFLX_AERO(i,j,n) = SFLX_AERO(i,j,n) / DENS(KS,i,j) &
                          / GRID_CDZ(KS) * rada( n ) / 3.0_RP * dt * exp( xactr( n ) )
         gdga(KS,i,j,n) = gdga(KS,i,j,n)+SFLX_AERO(i,j,n)/dxaer
        end if
       end do
     end do
     end do
    end if

    call TIME_rapstart('MPX ijkconvert')
    AMR(:,:,:) = 0.0_RP
    do j = JS, JE
     do i = IS, IE
       do k = KS, KE
          QTRC(k,i,j,I_QV) = qv_mp(k,i,j)
          do n = 1, nbin
            QTRC(k,i,j,n+I_QV) = gdgc(k,i,j,n)/DENS(k,i,j)*dxmic
            if( QTRC(k,i,j,n+I_QV) <= eps ) then
              QTRC(k,i,j,n+I_QV) = 0.0_RP
            end if
          end do
          do n = 1, nccn
            QTRC(k,i,j,n+I_QV+nbin)=gdga(k,i,j,n)/DENS(k,i,j)*dxaer
            AMR(k,i,j) = AMR(k,i,j) + QTRC(k,i,j,n+I_QV+nbin)
          end do
          do n = 1, QA
           q(k,i,j,n) = QTRC(k,i,j,n)
          enddo
       enddo

       do k = KS, KE
          CALC_QDRY( qd(k,i,j), q, k, i, j, iq )
       enddo
       do k  = KS, KE
          CALC_CP( cpa(k,i,j), qd(k,i,j), q, k, i, j, iq, CONST_CPdry, AQ_CP )
          CALC_R( Rmoist, QTRC(k,i,j,I_QV), qd(k,i,j), CONST_Rdry, CONST_Rvap )
          RHOT(k,i,j) = temp_mp(k,i,j) * ( CONST_PRE00 / pres_mp(k,i,j) )**(Rmoist/cpa(k,i,j)) &
               * DENS(k,i,j)
       enddo

     enddo
    enddo

    call HIST_in( AMR(:,:,:),  'aerosol', 'aerosol mass', 'kg/m^3', dt)

    !--- gravitational falling
    if ( doprecipitation ) then
    do j = JS, JE
    do i = IS, IE
    do k = KS-1, KE
       flux_rain(k,i,j) = 0.0_RP
       flux_snow(k,i,j) = 0.0_RP
    enddo
    enddo
    enddo

    do step = 1, MP_NSTEP_SEDIMENTATION

       do j = JS, JE
       do i = IS, IE
       do k = KS, KE
          do iq = 1, QA
            rhogq(k,i,j,iq) = QTRC(k,i,j,iq) * DENS(k,i,j)
            q(k,i,j,iq) = QTRC(k,i,j,iq)
          enddo
          th(k,i,j) = RHOT(k,i,j) / DENS(k,i,j)
       enddo
       do k = KS, KE
          CALC_QDRY( qd(k,i,j), q, k, i, j, iq )
       enddo
       do k = KS, KE
          CALC_CV( cva(k,i,j), qd(k,i,j), q, k, i, j, iq, CONST_CVdry, AQ_CV )
       enddo
       do k = KS, KE
          CALC_R( Rmoist, q(k,i,j,I_QV), qd(k,i,j), CONST_Rdry, CONST_Rvap )
          cpa(k,i,j) = cva(k,i,j) + Rmoist
          CALC_PRE( pres_mp(k,i,j), DENS(k,i,j), th(k,i,j), Rmoist, cpa(k,i,j), CONST_PRE00 )
          temp_mp(k,i,j) = pres_mp(k,i,j) / ( DENS(k,i,j) * Rmoist )
       enddo
       do k = KS, KE
          rhoge(k,i,j)  = DENS(k,i,j) * temp_mp(k,i,j) * cva(k,i,j)
       enddo
       enddo
       enddo

       call precipitation( wflux_rain(:,:,:),     &
                           wflux_snow(:,:,:),     &
                           velw(:,:,:,:),         &
                           rhogq(:,:,:,:),        &
                           rhoge(:,:,:),          &
                           temp_mp(:,:,:),        &
                           MP_DTSEC_SEDIMENTATION )

       do j = JS, JE
       do i = IS, IE
          do k = KS-1, KE
             flux_rain(k,i,j) = flux_rain(k,i,j) + wflux_rain(k,i,j) * MP_RNSTEP_SEDIMENTATION
             flux_snow(k,i,j) = flux_snow(k,i,j) + wflux_snow(k,i,j) * MP_RNSTEP_SEDIMENTATION
          enddo
          flux_prec(i,j) = flux_rain(KS-1,i,j) + flux_snow(KS-1,i,j)
       enddo
       enddo

    enddo

    endif

    if( donegative_fixer ) then
       call MP_negative_fixer( DENS(:,:,:),  & ! [INOUT]
                               RHOT(:,:,:),  & ! [INOUT]
                               QTRC(:,:,:,:) ) ! [INOUT]
       QTRC(:,:,:,QQE+1:QA) = max( QTRC(:,:,:,QQE+1:QA),0.0_RP )
    endif

    call HIST_in( flux_rain(KS-1,:,:), 'RAIN', 'surface rain rate', 'kg/m2/s', dt)
    call HIST_in( flux_snow(KS-1,:,:), 'SNOW', 'surface snow rate', 'kg/m2/s', dt)
    call HIST_in( flux_prec(:,:),      'PREC', 'surface precipitaion rate', 'kg/m2/s', dt)

    call TIME_rapend  ('MPX ijkconvert')

    call COMM_vars8( DENS(:,:,:), 1 )
    call COMM_vars8( MOMZ(:,:,:), 2 )
    call COMM_vars8( MOMX(:,:,:), 3 )
    call COMM_vars8( MOMY(:,:,:), 4 )
    call COMM_vars8( RHOT(:,:,:), 5 )
    call COMM_wait ( DENS(:,:,:), 1 )
    call COMM_wait ( MOMZ(:,:,:), 2 )
    call COMM_wait ( MOMX(:,:,:), 3 )
    call COMM_wait ( MOMY(:,:,:), 4 )
    call COMM_wait ( RHOT(:,:,:), 5 )

    do iq = 1, QA
       call COMM_vars8( QTRC(:,:,:,iq), iq )
    enddo
    do iq = 1, QA
       call COMM_wait ( QTRC(:,:,:,iq), iq )
    enddo

#ifdef _FPCOLL_
call STOP_COLLECTION("MICROPHYSICS")
#endif

    call ATMOS_vars_total

    return
  end subroutine ATMOS_PHY_MP
  !-----------------------------------------------------------------------------
  subroutine getsups        &
       ( qvap, temp, pres,  & !--- in
         ssliq, ssice )       !--- out
  !
  real(RP), intent(in) :: qvap  !  specific humidity [ kg/kg ]
  real(RP), intent(in) :: temp  !  temperature [ K ]
  real(RP), intent(in) :: pres  !  pressure [ Pa ]
  !
  real(RP), intent(out) :: ssliq
  real(RP), intent(out) :: ssice
  !
  real(RP) :: epsl, rr, evap, esatl, esati
  !
  epsl = CONST_Rdry/CONST_Rvap
  !
  rr = qvap / ( 1.0_RP-qvap )
  evap = rr*pres/( epsl+rr )

  esatl = fesatl( temp )
  esati = fesati( temp )

  ssliq = evap/esatl - 1.0_RP
  ssice = evap/esati - 1.0_RP

  return

  end subroutine getsups
  !-----------------------------------------------------------------------------
  subroutine mp_hbinw_evolve        &
      ( pres, dens,                 & !--- in
        dtime,                      & !--- in
        gc,                         & !--- inout
        ga,                         & !--- inout
        qvap, temp                  ) !--- inout

  real(RP), intent(in) :: pres   !  pressure
  real(RP), intent(in) :: dens   !  density of dry air
  real(RP), intent(in) :: dtime  !  time interval

  real(RP), intent(inout) :: gc( nbin )
  real(RP), intent(inout) :: ga( nccn )  !--- aerosol SDF (not supported)
  real(RP), intent(inout) :: qvap  !  specific humidity
  real(RP), intent(inout) :: temp  !  temperature
  integer :: n
  !
  !
  !--- nucleat
  call nucleat                  &
         ( dens, pres, dtime,   & !--- in
           gc, ga, qvap, temp   ) !--- inout

  !--- condensation / evaporation
  call cndevpsbl                &
         ( dtime,               & !--- in
           dens, pres,          & !--- in
           gc, ga, qvap, temp   ) !--- inout

  !--- collision-coagulation
  if( doautoconversion ) then
   call  collmain               &
          ( dtime,              & !--- in
            gc                  ) !--- inout
  endif

  return

  end subroutine mp_hbinw_evolve
  !-----------------------------------------------------------------------------
  subroutine nucleat        &
      ( dens, pres, dtime,  & !--- in
        gc, ga, qvap, temp  ) !--- inout
  !
  !  liquid nucleation from aerosol particle
  !
  !
  use mod_const, only: &
     cp    => CONST_CPdry, &
     rhow  => CONST_DWATR, &
     qlevp => CONST_LH0, &
     rvap  => CONST_Rvap
  use mod_atmos_saturation, only : &
       pres2qsat_liq => ATMOS_SATURATION_pres2qsat_liq,   &
       pres2qsat_ice => ATMOS_SATURATION_pres2qsat_ice
  real(RP), intent(in) :: dens   !  density  [ kg/m3 ]
  real(RP), intent(in) :: pres   !  pressure [ Pa ]
  real(RP), intent(in) :: dtime
  !
  real(RP), intent(inout) :: gc( nbin )  !  SDF ( hydrometeors )
  real(RP), intent(inout) :: ga( nccn )  !  SDF ( aerosol ) : mass
  real(RP), intent(inout) :: qvap  !  specific humidity [ kg/kg ]
  real(RP), intent(inout) :: temp  !  temperature [ K ]
  !
  !--- local
  real(RP) :: gan( nccn )  !  SDF ( aerosol ) : number
  real(RP) :: ssliq, ssice, delcld
  real(RP) :: sumold, sumnew, acoef, bcoef, xcrit, rcrit
  real(RP) :: ractr, rcld, xcld, part, vdmp, dmp
  integer :: n, nc, ncrit
  integer, allocatable, save :: ncld( : )
  logical, save :: ofirst = .true.
  !
  !--- use for aerosol coupled model
  real(RP), parameter :: sigma = 7.5E-02_RP  ! water surface tension [ N/m2 ]
  real(RP), parameter :: vhfct = 2.0_RP    ! van't hoff factor
  !
  !--- supersaturation
!  call  getsups               &
!          ( qvap, temp, pres, & !--- in
!            ssliq, ssice  )     !--- out
  call pres2qsat_liq( ssliq,temp,pres )
  call pres2qsat_ice( ssice,temp,pres )
  ssliq = qvap/ssliq-1.0_RP
  ssice = qvap/ssice-1.0_RP

  if ( ssliq <= 0.0_RP ) return
  !--- use for aerosol coupled model
  !--- mass -> number
  do n = 1, nccn
    gan( n ) = ga( n )/exp( xactr( n ) )
  end do

  acoef = 2.0_RP*sigma/rvap/rhow/temp
  bcoef = vhfct* rhoa/rhow * emwtr/emaer

  !--- relationship of bin number
  if ( ofirst ) then
    allocate ( ncld( 1:nccn ) )
    do n = 1, nccn
      ractr = ( exp( xactr( n ) )*ThirdovForth/pi/rhoa )**( OneovThird )
      rcld  = sqrt( 3.0_RP*bcoef*ractr*ractr*ractr / acoef )
      xcld  = log( rhow * 4.0_RP*pi*OneovThird*rcld*rcld*rcld )
     if( flg_nucl ) then
      ncld( n ) = 1
     else
      ncld( n ) = int( ( xcld-xctr( 1 ) )/dxmic ) + 1
      ncld( n ) = min( max( ncld( n ),1 ),nbin )
     end if
    end do
    ofirst = .false.
  end if

  !--- nucleation
  do n = nccn, 1, -1

!    call  getsups                &
!            ( qvap, temp, pres,  & !--- in
!              ssliq, ssice )       !--- out
      call pres2qsat_liq( ssliq,temp,pres )
      call pres2qsat_ice( ssice,temp,pres )
      ssliq = qvap/ssliq-1.0_RP
      ssice = qvap/ssice-1.0_RP

    if ( ssliq <= 0.0_RP ) exit
    !--- use for aerosol coupled model
    acoef = 2.0_RP*sigma/rvap/rhow/temp
    rcrit = acoef*OneovThird * ( 4.0_RP/bcoef )**( OneovThird ) / ssliq**( TwoovThird )
    xcrit = log( rhoa * 4.0_RP*pi*OneovThird * rcrit*rcrit*rcrit )
    ncrit = int( ( xcrit-xabnd( 1 ) )/dxaer ) + 1

    if ( n == ncrit ) then
      part = ( xabnd( ncrit+1 )-xcrit )/dxaer
    else if ( n > ncrit ) then
      part = 1.0_RP
    else
      exit
    end if

    nc = ncld( n )
    dmp = part*gan( n )*dxaer*exp( xctr( nc ) )
    dmp = min( dmp,qvap*dens )
    gc( nc ) = gc( nc ) + dmp/dxmic
    gan( n ) = gan( n ) - dmp/dxaer/exp( xctr( nc ) )
    gan( n ) = max( gan( n ), 0.0_RP )
    qvap = qvap - dmp/dens
    qvap = max( qvap,0.0_RP )
    temp = temp + dmp/dens*qlevp/cp
  end do

  !--- number -> mass
  do n = 1, nccn
    ga( n ) = gan( n )*exp( xactr( n ) )
  end do
  !
  return
  !
  end subroutine nucleat
  !-----------------------------------------------------------------------------
  subroutine  cndevpsbl     &
      ( dtime,              & !--- in
        dens, pres,         & !--- in
        gc, ga, qvap, temp  ) !--- inout
  !
  real(RP), intent(in) :: dtime
  real(RP), intent(in) :: dens   !  atmospheric density [ kg/m3 ]
  real(RP), intent(in) :: pres   !  atmospheric pressure [ Pa ]
  real(RP), intent(inout) :: gc( nbin )  ! Size Distribution Function
  real(RP), intent(inout) :: ga( nccn )  !  SDF ( aerosol ) : mass
  real(RP), intent(inout) :: qvap    !  specific humidity [ kg/kg ]
  real(RP), intent(inout) :: temp    !  temperature [ K ]
  !
  !--- local variables
  integer :: iflg( il ), n, iliq
  real(RP) :: csum( il )
  real(RP) :: regene_gcn
  !
  !
  iflg( : ) = 0
  csum( : ) = 0.0_RP
  regene_gcn = 0.0_RP
  do n = 1, nbin
    csum( il ) = csum( il )+gc( n )*dxmic
  end do

  if ( csum( il ) > cldmin ) iflg( il ) = 1

  iliq = iflg( il )

  if ( iliq == 1 ) then
      call  liqphase            &
              ( dtime, iliq,    & !--- in
                dens, pres,     & !--- in
                gc, qvap, temp, & !--- inout
                regene_gcn      ) !--- out
     !--- regeneration of aerosol
      if( flg_regeneration ) then
       call faero( regene_gcn,  & !--- in
                   ga           ) !--- inout
      end if
  end if
  !
  end subroutine cndevpsbl
  !-----------------------------------------------------------------------------
  subroutine liqphase   &
      ( dtime, iflg,    & !--- in
        dens, pres,     & !--- in
        gc, qvap, temp, & !--- inout
        regene_gcn      ) !--- out
  !
  use mod_const, only: &
     cp    => CONST_CPdry, &
     rhow  => CONST_DWATR, &
     qlevp => CONST_LH0, &
     rvap  => CONST_Rvap
    use mod_atmos_saturation, only : &
       pres2qsat_liq => ATMOS_SATURATION_pres2qsat_liq,   &
       pres2qsat_ice => ATMOS_SATURATION_pres2qsat_ice
  real(RP), intent(in) :: dtime
  integer, intent(in) :: iflg
  real(RP), intent(in) :: dens, pres
  real(RP), intent(inout) :: gc( nbin ), qvap, temp
  real(RP), intent(out) :: regene_gcn
  !
  !--- local variables
  integer :: n, nloop, ncount
  real(RP) :: gclold, gclnew, gtliq, umax, dtcnd
  real(RP) :: sumliq, cefliq, a, sliqtnd, cndmss, ssliq, ssice
  real(RP) :: gcn( nbin ), gdu( nbin+1 ), gcnold( nbin )
  real(RP), parameter :: cflfct = 0.50_RP
  real(RP) :: old_sum_gcn, new_sum_gcn
  !
  gclold = 0.0_RP
  do n = 1, nbin
    gclold = gclold + gc( n )
  end do
  gclold = gclold * dxmic
  !
  !------- mass -> number
  gcn( 1:nbin ) = gc( 1:nbin ) / exp( xctr( 1:nbin ) )

  !
  !------- CFL condition
!  call  getsups                &
!          ( qvap, temp, pres,  & !--- in
!            ssliq, ssice )       !--- out
      call pres2qsat_liq( ssliq,temp,pres )
      call pres2qsat_ice( ssice,temp,pres )
      ssliq = qvap/ssliq-1.0_RP
      ssice = qvap/ssice-1.0_RP

  gtliq = gliq( pres,temp )
  umax = cbnd( il,1 )/exp( xbnd( 1 ) )*gtliq*abs( ssliq )
  dtcnd = cflfct*dxmic/umax
  nloop = int( dtime/dtcnd ) + 1
  dtcnd = dtime / nloop
  !
  regene_gcn = 0.0_RP
  !------- loop
  do ncount = 1, nloop

  !----- matrix for supersaturation tendency
!  call  getsups                &
!          ( qvap, temp, pres,  & !--- in
!            ssliq, ssice )       !--- out
      call pres2qsat_liq( ssliq,temp,pres )
      call pres2qsat_ice( ssice,temp,pres )
      ssliq = qvap/ssliq-1.0_RP
      ssice = qvap/ssice-1.0_RP

  gtliq = gliq( pres,temp )
  sumliq = 0.0_RP
  old_sum_gcn = 0.0_RP
  do n = 1, nbin
    sumliq = sumliq + gcn( n )*cctr( il,n )
  end do
  sumliq = sumliq * dxmic
  cefliq = ( ssliq+1.0_RP )*( 1.0_RP/qvap + qlevp*qlevp/cp/rvap/temp/temp )
  a = - cefliq*sumliq*gtliq/dens
  !
  !----- supersaturation tendency
  if ( abs( a*dtcnd ) >= 0.10_RP ) then
    sliqtnd = ssliq*( exp( a*dtcnd )-1.0_RP )/( a*dtcnd )
  else
    sliqtnd = ssliq
  end if
  !
  !----- change of SDF
  gdu( 1:nbin+1 ) = cbnd( il,1:nbin+1 )/exp( xbnd( 1:nbin+1 ) )*gtliq*sliqtnd
  gcnold( : ) = gcn( : )
  call  advection              &
          ( dtcnd,             & !--- in
            gdu( 1:nbin+1 ),   & !--- in
            gcn( 1:nbin ),     & !--- inout
            regene_gcn         ) !--- inout
  !
  !----- new mass
  gclnew = 0.0_RP
  new_sum_gcn = 0.0_RP
  do n = 1, nbin
    gclnew = gclnew + gcn( n )*exp( xctr( n ) )
    old_sum_gcn = old_sum_gcn + gcnold( n )*dxmic
    new_sum_gcn = new_sum_gcn + gcn( n )*dxmic
  end do

  gclnew = gclnew*dxmic
  !
  !----- change of humidity and temperature
  cndmss = gclnew - gclold
  qvap = qvap - cndmss/dens
  temp = temp + cndmss/dens*qlevp/cp
  !
  gclold = gclnew
  !
  !----- continue/end
  end do
  !
  !------- number -> mass
  do n = 1 , nbin
   gc( n ) = gcn( n )*exp( xctr( n ) )
   if( gc( n ) < 0.0_RP ) then
     cndmss = -gc( n )
     gc( n ) = 0.0_RP
     qvap = qvap + cndmss/dens
     temp = temp - cndmss/dens*qlevp/cp
   endif
  enddo
  !
  end subroutine liqphase
  !-------------------------------------------------------------------------------
  subroutine advection  &
       ( dtime,         & !--- in
         gdu,           & !--- in
         gdq, regene    ) !--- inout
  !
  real(RP), intent(in) :: dtime, gdu( 1:nbin+1 )
  real(RP), intent(inout) :: gdq( 1:nbin ), regene
  !
  !--- local variables
  real(RP) :: delx
  real(RP) :: qadv( -1:nbin+2 ), uadv( 0:nbin+2 )
  real(RP) :: flq( 1:nbin+1 )
  integer, parameter :: ldeg = 2
  real(RP), parameter :: epsl = 1.E-10_RP
  real(RP) :: acoef( 0:nbin+1,0:ldeg ), sum
  real(RP) :: crn( 0:nbin+2 )
  real(RP) :: aip( 0:nbin+1 ), aim( 0:nbin+1 ), ai( 0:nbin+1 )
  real(RP) :: cmins, cplus
  integer :: i, n
  !
  !
  delx = dxmic
  do i = 1, nbin
    qadv( i ) = gdq( i )
  end do
  qadv( -1 )     = 0.0_RP
  qadv( 0  )     = 0.0_RP
  qadv( nbin+1 ) = 0.0_RP
  qadv( nbin+2 ) = 0.0_RP

  do i = 1, nbin+1
    uadv( i ) = gdu( i )
  end do
  uadv( 0  ) = 0.0_RP
  uadv( nbin+2 ) = 0.0_RP

  !--- flux
  do i = 0, nbin+1
    acoef( i,0 ) = - ( qadv( i+1 )-26.0_RP*qadv( i )+qadv( i-1 ) ) / 24.0_RP
    acoef( i,1 ) = ( qadv( i+1 )-qadv( i-1 ) ) * 0.50_RP
    acoef( i,2 ) = ( qadv( i+1 )-2.0_RP*qadv( i )+qadv( i-1 ) ) * 0.50_RP
  end do

  crn( 0:nbin+2 ) = uadv( 0:nbin+2 )*dtime/delx

  do i = 0, nbin+1
    cplus = ( crn( i+1 ) + abs( crn( i+1 ) ) ) * 0.50_RP
    sum = 0.0_RP
    do n = 0, ldeg
      sum = sum + acoef( i,n )/( n+1 )/2.0_RP**( n+1 )  &
                *( 1.0_RP-( 1.0_RP-2.0_RP*cplus )**( n+1 ) )
    end do
    aip( i ) = max( sum,0.0_RP )
  end do

  do i = 0, nbin+1
    cmins = - ( crn( i ) - abs( crn( i ) ) ) * 0.50_RP
    sum = 0.0_RP
    do n = 0, ldeg
      sum = sum + acoef( i,n )/( n+1 )/2.0_RP**( n+1 ) * (-1)**n &
                *( 1.0_RP-( 1.0_RP-2.0_RP*cmins )**( n+1 ) )
    end do
    aim( i ) = max( sum,0.0_RP )
  end do

  do i = 0, nbin+1
    sum = 0.0_RP
    do n = 0, ldeg
      sum = sum + acoef( i,n )/( n+1 )/2.0_RP**( n+1 ) * ( (-1)**n+1 )
    end do
    ai( i ) = max( sum,aip( i )+aim( i )+epsl )
  end do

  do i = 1, nbin+1
    flq( i ) = ( aip( i-1 )/ai( i-1 )*qadv( i-1 )  &
                -aim( i   )/ai( i   )*qadv( i   ) )*delx/dtime
  end do

  if( flg_regeneration .and. gdu( 1 ) < 0.0_RP ) then
   regene = regene+( -flq( 1 )*dtime/delx )
  else
   regene = 0.0_RP
  end if

  do i = 1, nbin
    gdq( i ) = gdq( i ) - ( flq( i+1 )-flq( i ) )*dtime/delx
  end do

  end subroutine advection
  !-------------------------------------------------------------------------------
  function  gliq( pres,temp )
  !
  use mod_const, only : rair  => CONST_Rdry,  &
                        rvap  => CONST_Rvap,  &
                        qlevp => CONST_LH0
  !
  real(RP), intent(in) :: pres, temp
  real(RP) :: gliq
  !
  real(RP) :: emu, dens, cefd, cefk, f1, f2
  real(RP), parameter :: fct = 1.4E+3_RP
  !
  emu = fmyu( temp )
  dens = pres/rair/temp
  cefd = emu/dens
  cefk = fct*emu

  f1 = rvap*temp/fesatl( temp )/cefd
  f2 = qlevp/cefk/temp*( qlevp/rvap/temp - 1.0_RP )

  gliq = 4.0_RP*pi/( f1+f2 )

  end function gliq
  !-------------------------------------------------------------------------------
  function fmyu( temp )
  !
  !
  use mod_const, only: &
     tmlt => CONST_TMELT
  real(RP), intent(in) :: temp
  real(RP) :: fmyu
  !
  real(RP), parameter :: a = 1.72E-05_RP, b = 3.93E+2_RP, c = 1.2E+02_RP
  !
  fmyu = a*( b/( temp+c ) )*( temp/tmlt )**1.50_RP
  !
  end function fmyu
  !-------------------------------------------------------------------------------
  function fesatl( temp )
  !
  use mod_const, only: &
     temp0 => CONST_TEM00, &
     esat0 => CONST_PSAT0, &
     qlevp => CONST_LH0, &
     rvap  => CONST_Rvap
  real(RP), intent(in) :: temp
  real(RP) :: fesatl
  !
  fesatl = esat0*exp( qlevp/rvap*( 1.0_RP/temp0 - 1.0_RP/temp ) )
  !
  return

  end function fesatl
  !-----------------------------------------------------------------------
  function fesati( temp )
  !
  use mod_const, only: &
     temp0 => CONST_TEM00, &
     esat0 => CONST_PSAT0, &
     qlsbl => CONST_LHS0, &
     rvap  => CONST_Rvap
  real(RP), intent(in) :: temp
  real(RP) :: fesati
  !
  fesati = esat0*exp( qlsbl/rvap*( 1.0_RP/temp0 - 1.0_RP/temp ) )
  !
  return

  end function fesati
  !-------------------------------------------------------------------------------
 subroutine collmain &
      ( dtime,       & !--- in
        gc           ) !--- inout

  use mod_process, only: &
     PRC_MPIstop
  !
  real(RP), intent(in) :: dtime
  real(RP), intent(inout) :: gc( nbin )
  !
  !--- local variables
  integer :: iflg( 1 ), n
  real(RP) :: csum( 1 )
  real(RP), parameter :: tcrit = 271.15_RP
  !
  !--- judgement of particle existence
    iflg( : ) = 0
    csum( : ) = 0.0_RP
    do n = 1, nbin
      csum( il ) = csum( il ) + gc( n )*dxmic
    end do
    if ( csum( il ) > cldmin ) iflg( il ) = 1
  !
  !--- interaction
   if ( iflg( il ) == 1 ) then
      if ( rndm_flgp == 1 ) then  !--- stochastic method

        call r_collcoag            &
            ( dtime,  wgtbin,  & !--- in
              gc               ) !--- inout

      else  !--- default method

        call  collcoag        &
            ( dtime,      & !--- in
              gc          ) !--- inout

      end if
   end if
  !
  !
  return
  !
  end subroutine collmain
  !-------------------------------------------------------------------------------
  subroutine  collcoag( dtime,gc )
  !-------------------------------------------------------------------------------
  !--- reference paper
  !    Bott et al. (1998) J. Atmos. Sci. vol.55, pp. 2284-
  !-------------------------------------------------------------------------------
  !
  real(RP), intent(in) :: dtime
  real(RP), intent(inout) :: gc( nbin )
  !
  !--- local variables
  integer :: i, j, k, l
  real(RP) :: xi, xj, xnew, dmpi, dmpj, frci, frcj
  real(RP) :: gprime, gprimk, wgt, crn, sum, flux
  integer, parameter :: ldeg = 2
  real(RP) :: acoef( 0:ldeg )
  real(RP), parameter :: dmpmin = 1.E-01_RP
  real(RP) :: suri, surj
  !
  small : do i = 1, nbin-1
    if ( gc( i ) <= cldmin ) cycle small
  large : do j = i+1, nbin
    if ( gc( j ) <= cldmin ) cycle large

    xi = exp( xctr( i ) )
    xj = exp( xctr( j ) )
    xnew = log( xi+xj )
    k = int( ( xnew-xctr( 1 ) )/dxmic ) + 1
    k = max( max( k,j ),i )
    if ( k >= nbin ) cycle small

    dmpi = ck( 1,1,i,j )*gc( j )/xj*dxmic*dtime
    dmpj = ck( 1,1,i,j )*gc( i )/xi*dxmic*dtime

    if ( dmpi <= dmpmin ) then
      frci = gc( i )*dmpi
    else
      frci = gc( i )*( 1.0_RP-exp( -dmpi ) )
    end if

    if ( dmpj <= dmpmin ) then
      frcj = gc( j )*dmpj
    else
      frcj = gc( j )*( 1.0_RP-exp( -dmpj ) )
    end if

    gprime = frci+frcj
    if ( gprime <= 0.0_RP ) cycle large

    suri = gc( i )
    surj = gc( j )
    gc( i ) = gc( i )-frci
    gc( j ) = gc( j )-frcj
    gc( i ) = max( gc( i )-frci, 0.0_RP )
    gc( j ) = max( gc( j )-frcj, 0.0_RP )
    frci = suri - gc( i )
    frcj = surj - gc( j )
    gprime = frci+frcj

    gprimk = gc( k ) + gprime
    wgt = gprime / gprimk
    crn = ( xnew-xctr( k ) )/( xctr( k+1 )-xctr( k ) )

    acoef( 0 ) = -( gc( k+1 )-26.0_RP*gprimk+gc( k-1 ) )/24.0_RP
    acoef( 1 ) = ( gc( k+1 )-gc( k-1 ) ) *0.50_RP
    acoef( 2 ) = ( gc( k+1 )-2.0_RP*gprimk+gc( k-1 ) ) *0.50_RP

    sum = 0.0_RP
    do l = 0, ldeg
      sum = sum + acoef( l )/( l+1 )/2.0_RP**( l+1 )   &
                *( 1.0_RP-( 1.0_RP-2.0_RP*crn )**( l+1 ) )
    end do

    flux = wgt*sum
    flux = min( max( flux,0.0_RP ),gprime )

    gc( k ) = gprimk - flux
    gc( k+1 ) = gc( k+1 ) + flux

  end do large
  end do small
  !
  return
  !
  end subroutine collcoag
  !-------------------------------------------------------------------------------
  subroutine  advec_1d     &
      ( delxa, delxb,      & !--- in
        gdu,               & !--- in
        dtime,             & !--- in
        gdq              )   !--- inout

  real(RP), intent(in) :: delxa( KA ), delxb( KA )
  real(RP), intent(in) :: gdu( KA )
  real(RP), intent(in) :: dtime
  real(RP), intent(inout) :: gdq( KA )

  !--- local
  integer :: i
  real(RP) :: fq( KS:KE+1 )
  real(RP) :: dqr, dql, dq, qstar
  !
  !
  !--- reset of fluxes
  fq( : ) = 0.0_RP

  !--- tracer flux
  !--- terminal velocity is always negative
  do i = KS, KE
      dqr = ( gdq( i+1 )-gdq( i   ) )/delxb( i+1 )
      dql = ( gdq( i   )-gdq( i-1 ) )/delxb( i )
      if ( dqr*dql > 0.0_RP ) then
        dq = 2.0_RP / ( 1.0_RP/dqr+1.0_RP/dql )
      else
        dq = 0.0_RP
      end if
      qstar = gdq( i )-( delxa( i )+gdu( i )*dtime )*dq*0.50_RP
      fq( i ) = qstar*gdu( i )
  end do

  !--- change of concentration by flux convergence
  do i = KS, KE
    gdq( i ) = gdq( i ) - dtime/delxa( i )*( fq( i+1 )-fq( i ) )
    if( i == KS ) then
     sfc_precp = dtime/delxa( i )*( -fq( i ) )
    endif
  end do
  !
  !
  return

  end subroutine  advec_1d
  !-----------------------------------------------------------------------------
  subroutine faero( f0,ga )

  real(RP), intent(in) ::  f0
  real(RP), intent(inout) :: ga( nccn )
  real(RP) :: gaero( nccn ) !, f1, radmax, radmin
  real(RP), parameter :: alpha = 3.0_RP
  integer :: n

  do n = 1, nccn
   gaero( n ) = f0*marate( n )*exp( xactr( n ) )/dxaer
   ga( n ) = ga( n )+gaero( n )
  end do

  return

  end subroutine faero
  !-------------------------------------------------------------------------------
  !
  ! + Y. Sato added for stochastic method
  ! + Reference Sato et al. (2009) JGR, doi:10.1029/2008JD011247
  !
  !-------------------------------------------------------------------------------
  subroutine random_setup( mset ) !--- in

   use mod_random, only: &
       RANDOM_get
   use mod_process, only: &
       PRC_MPIstop

   integer, intent(in) :: mset

   !--- local ----
   integer :: n
   real(RP) :: nbinr, tmp1
   real(RP) :: rans( mbin ), ranl( mbin )
   integer, parameter :: pq = nbin*(nbin-1)/2
   real(RP) :: ranstmp( pq )
   real(RP) :: ranltmp( pq )
   integer :: p, q
   integer :: k, temp
   integer :: orderb( pq )
   real(RP) :: abq1
   real(RP) :: a
   real(RP) :: randnum(1,1,pq)
  !-------------------------------------------------------
   allocate( blrg( mset, mbin ) )
   allocate( bsml( mset, mbin ) )

   a = real( nbin )*real( nbin-1 )*0.50_RP
   if( a < mbin ) then
    write(*,*) "mbin should be smaller than {nbin}_C_{2}"
    call PRC_MPIstop
   end if

   wgtbin = a/real( mbin )
   nbinr = real( nbin )

    do p = 1, pq
      orderb( p ) = p
    end do

    do p = 1, nbin-1
      ranstmp( (p-1)*nbin-(p*(p-1))/2+1 : p*nbin-(p*(p+1))/2 ) = p
     do q = 1, nbin-p
        ranltmp( (p-1)*nbin-(p*(p-1))/2+q ) = p+q
      end do
   end do

    do n = 1, mset
      call RANDOM_get( randnum )
       do p = 1, pq
        abq1 = randnum( 1,1,p )
        k = int( abq1*( pq-p-1 ) ) + p
        temp = orderb( p )
        orderb( p ) = orderb( k )
        orderb( k ) = temp
       end do

       do p = 1, mbin
        if( p <= pq ) then
         rans( p ) = ranstmp( orderb( p ) )
         ranl( p ) = ranltmp( orderb( p ) )
        else
         rans( p ) = ranstmp( orderb( p-pq ) )
         ranl( p ) = ranltmp( orderb( p-pq ) )
        end if
         if( rans( p ) >= ranl( p ) ) then
          tmp1 = rans( p )
          rans( p ) = ranl( p )
          ranl( p ) = tmp1
         end if
       end do
         blrg( n,1:mbin ) = int( ranl( 1:mbin ) )
         bsml( n,1:mbin ) = int( rans( 1:mbin ) )
    end do

  end subroutine random_setup
 !-------------------------------------------------------------------------------
  subroutine  r_collcoag( dtime, swgt, gc )
  !-------------------------------------------------------------------------------
  !--- reference paper
  !    Bott et al. (1998) J. Atmos. Sci. vol.55, pp. 2284-
  !    Bott et al. (2000) J. Atmos. Sci. Vol.57, pp. 284-
  !-------------------------------------------------------------------------------
  !
  use mod_random, only: &
      RANDOM_get

  real(RP), intent(in) :: dtime
  real(RP), intent(in) :: swgt
  real(RP), intent(inout) :: gc( nbin )
  !
  !--- local variables
  integer :: i, j, k, l
  real(RP) :: xi, xj, xnew, dmpi, dmpj, frci, frcj
  real(RP) :: gprime, gprimk, wgt, crn, sum, flux
  integer, parameter :: ldeg = 2
  real(RP), parameter :: dmpmin = 1.E-01_RP, cmin = 1.E-10_RP
  real(RP) :: acoef( 0:ldeg )
  !
  !--- Y.sato added to use code6
  integer :: nums( mbin ), numl( mbin )
  real(RP), parameter :: gt = 1.0_RP
  integer :: s, det
  real(RP) :: nbinr, mbinr        ! use to weight
!  real(RP) :: beta
  real(RP) :: tmpi, tmpj
 !-----------------------------------------------------
  call RANDOM_get( rndm )
  det = int( rndm(1,1,1)*IA*JA*KA )
  nbinr = real( nbin )
  mbinr = real( mbin )
  nums( 1:mbin ) = bsml( det,1:mbin )
  numl( 1:mbin ) = blrg( det,1:mbin )

   do s = 1, mbin
    i = nums( s )
    j = numl( s )

    if ( gc( i ) <= cmin ) cycle !small
    if ( gc( j ) <= cmin ) cycle !large

    xi = exp( xctr( i ) )
    xj = exp( xctr( j ) )
    xnew = log( xi+xj )
    k = int( ( xnew-xctr( 1 ) )/dxmic ) + 1
    k = max( max( k,j ),i )
    if( k>= nbin ) cycle

    dmpi = ck( 1,1,i,j )*gc( j )/xj*dxmic*dtime
    dmpj = ck( 1,1,i,j )*gc( i )/xi*dxmic*dtime

    if ( dmpi <= dmpmin ) then
      frci = gc( i )*dmpi
    else
      frci = gc( i )*( 1.0_RP-exp( -dmpi ) )
    end if

    if ( dmpj <= dmpmin ) then
      frcj = gc( j )*dmpj
    else
      frcj = gc( j )*( 1.0_RP-exp( -dmpj ) )
    end if
    tmpi = gc( i )
    tmpj = gc( j )

    gc( i ) = gc( i )-frci*swgt
    gc( j ) = gc( j )-frcj*swgt

    if( j /= k ) then
     gc( j ) = max( gc( j ), 0.0_RP )
    end if
     gc( i ) = max( gc( i ), 0.0_RP )

    frci = tmpi - gc( i )
    frcj = tmpj - gc( j )

    gprime = frci+frcj

    !-----------------------------------------------
    !--- Exponential Flux Method (Bott, 2000, JAS)
    !-----------------------------------------------
!    if ( gprime <= 0.0_RP ) cycle !large
!    gprimk = gc( k ) + gprime
!
!    beta = log( gc( k+1 )/gprimk+1.E-60_RP )
!    crn = ( xnew-xctr( k ) )/( xctr( k+1 )-xctr( k ) )
!
!    flux = ( gprime/beta )*( exp( beta*0.50_RP ) -exp( beta*( 0.50_RP-crn ) ) )
!    flux = min( gprimk ,gprime )
!
!    gc( k ) = gprimk - flux
!    gc( k+1 ) = gc( k+1 ) + flux

    !-----------------------------------------------
    !--- Flux Method (Bott, 1998, JAS)
    !-----------------------------------------------
    if ( gprime <= 0.0_RP ) cycle !large
    gprimk = gc( k ) + gprime
    wgt = gprime / gprimk
    crn = ( xnew-xctr( k ) )/( xctr( k+1 )-xctr( k ) )

    acoef( 0 ) = -( gc( k+1 )-26.0_RP*gprimk+gc( k-1 ) )/24.0_RP
    acoef( 1 ) = ( gc( k+1 )-gc( k-1 ) ) *0.5_RP
    acoef( 2 ) = ( gc( k+1 )-2.0_RP*gprimk+gc( k-1 ) ) *0.50_RP

    sum = 0.0_RP
    do l = 0, ldeg
      sum = sum + acoef( l )/( l+1 )/2.0_RP**( l+1 )   &
                *( 1.0_RP-( 1.0_RP-2.0_RP*crn )**( l+1 ) )
    end do

    flux = wgt*sum
    flux = min( max( flux,0.0_RP ),gprime )

    gc( k ) = gprimk - flux
    gc( k+1 ) = gc( k+1 ) + flux

   end do

  !
  return
  !
  end subroutine r_collcoag
  !-----------------------------------------------------------------------------
  !> Calculate Cloud Fraction
  !-----------------------------------------------------------------------------
  subroutine ATMOS_PHY_MP_CloudFraction( &
       cldfrac, &
       QTRC     )
    use mod_const, only: &
       EPS => CONST_EPS
    implicit none

    real(RP), intent(out) :: cldfrac(KA,IA,JA)
    real(RP), intent(in)  :: QTRC   (KA,IA,JA,QA)

    real(RP) :: qhydro
    integer  :: k, i, j, iq, ihydro
    !---------------------------------------------------------------------------

    do j  = JS, JE
    do i  = IS, IE
    do k  = KS, KE
       qhydro = 0.D0
       do ihydro = 1, MP_QA
        do iq = I_QV+nbin*(ihydro-1)+1, I_QV+nbin*ihydro
          qhydro = qhydro + QTRC(k,i,j,iq)
        enddo
       enddo
       cldfrac(k,i,j) = 0.5_RP + sign(0.5_RP,qhydro-EPS)
    enddo
    enddo
    enddo

    return
  end subroutine ATMOS_PHY_MP_CloudFraction
  !-----------------------------------------------------------------------------
  !> Calculate Effective Radius
  subroutine ATMOS_PHY_MP_EffectiveRadius( &
       Re,    &
       QTRC0, &
       DENS0  )
    use mod_const, only: &
       EPS => CONST_EPS
    implicit none

    real(RP), intent(out) :: Re   (KA,IA,JA,MP_QA) ! effective radius
    real(RP), intent(in)  :: QTRC0(KA,IA,JA,QA)    ! tracer mass concentration [kg/kg]
    real(RP), intent(in)  :: DENS0(KA,IA,JA)       ! density                   [kg/m3]

    real(RP) :: sum2(KA,IA,JA,MP_QA), sum3(KA,IA,JA,MP_QA)
    integer  :: i, j, k, iq, ihydro
    !---------------------------------------------------------------------------

    sum2(:,:,:,:) = 0.0_RP
    sum3(:,:,:,:) = 0.0_RP

    do ihydro = 1, MP_QA
    do k = KS, KE
    do j = JS, JE
    do i = IS, JE
      do iq = I_QV+nbin*(ihydro-1)+1, I_QV+nbin*ihydro
         sum3(k,i,j,ihydro) = sum3(k,i,j,ihydro) + &
                            ( ( QTRC0(k,i,j,iq) * DENS0(k,i,j) ) & !--- [kg/kg] -> [kg/m3]
                            / exp( xctr( iq-(I_QV+nbin*(ihydro-1)+iq) ) ) &   !--- mass -> number
                            * radc( iq-(I_QV+nbin*(ihydro-1)+iq) )**3.0_RP )
         sum2(k,i,j,ihydro) = sum2(k,i,j,ihydro) + &
                            ( ( QTRC0(k,i,j,iq) * DENS0(k,i,j) ) & !--- [kg/kg] -> [kg/m3]
                            / exp( xctr( iq-(I_QV+nbin*(ihydro-1)+iq) ) ) &   !--- mass -> number
                            * radc( iq-(I_QV+nbin*(ihydro-1)+iq) )**2.0_RP )
      enddo
      sum2(k,i,j,ihydro) = 0.5_RP + sign(0.5_RP,sum2(k,i,j,ihydro-EPS))
      sum3(k,i,j,ihydro) = 0.5_RP + sign(0.5_RP,sum3(k,i,j,ihydro-EPS))

      if( sum2(k,i,j,ihydro) /= 0.0_RP ) then
       Re(k,i,j,ihydro) = sum3(k,i,j,ihydro) / sum2(k,i,j,ihydro)
      else
       Re(k,i,j,ihydro) = 0.0_RP
      endif
    enddo
    enddo
    enddo
    enddo

    return
  end subroutine ATMOS_PHY_MP_EffectiveRadius
  !-----------------------------------------------------------------------------
  !> Calculate mixing ratio of each category
  subroutine ATMOS_PHY_MP_Mixingratio( &
       Qe,    &
       QTRC0  )
    use mod_const, only: &
       EPS => CONST_EPS
    implicit none

    real(RP), intent(out) :: Qe   (KA,IA,JA,MP_QA) ! mixing ratio of each cateory [kg/kg]
    real(RP), intent(in)  :: QTRC0(KA,IA,JA,QA)    ! tracer mass concentration [kg/kg]

    real(RP) :: sum2
    integer  :: i, j, k, iq, ihydro
    !---------------------------------------------------------------------------

    do k = KS, KE
    do j = JS, JE
    do i = IS, IE
      do ihydro = 1, MP_QA
        sum2 = 0.0_RP
        do iq = I_QV+nbin*(ihydro-1)+1, I_QV+nbin*ihydro
          sum2 = sum2 + QTRC0(k,i,j,iq)
        enddo
        Qe(k,i,j,ihydro) = sum2
      enddo
    enddo
    enddo
    enddo

    return
  end subroutine ATMOS_PHY_MP_Mixingratio
  !-----------------------------------------------------------------------------
end module mod_atmos_phy_mp
!-------------------------------------------------------------------------------
