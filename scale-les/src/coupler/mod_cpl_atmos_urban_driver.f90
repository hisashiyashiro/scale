!-------------------------------------------------------------------------------
!> module COUPLER / Atmosphere-Urban Driver
!!
!! @par Description
!!          Coupler driver: atmosphere-urban
!!
!! @author Team SCALE
!!
!! @par History
!<
!-------------------------------------------------------------------------------
module mod_cpl_atmos_urban_driver
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use scale_precision
  use scale_stdio
  use scale_grid_index
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: CPL_AtmUrb_driver_setup
  public :: CPL_AtmUrb_driver

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
  !-----------------------------------------------------------------------------
contains

  subroutine CPL_AtmUrb_driver_setup
    use mod_atmos_phy_sf_driver, only: &
       ATMOS_PHY_SF_driver_final
    use mod_urban_phy_ucm, only: &
       URBAN_PHY_driver_final
    use scale_cpl_atmos_urban, only: &
       CPL_AtmUrb_setup
    use mod_cpl_vars, only: &
       CPL_TYPE_AtmUrb
    implicit none
    !---------------------------------------------------------------------------

    call ATMOS_PHY_SF_driver_final
    call URBAN_PHY_driver_final

    call CPL_AtmUrb_setup( CPL_TYPE_AtmUrb )
    call CPL_AtmUrb_driver( .false. )

    return
  end subroutine CPL_AtmUrb_driver_setup

  subroutine CPL_AtmUrb_driver( update_flag )
    use scale_const, only: &
       LH0  => CONST_LH0,  &
       I_SW => CONST_I_SW, &
       I_LW => CONST_I_LW
    use scale_grid_real, only: &
       CZ => REAL_CZ, &
       FZ => REAL_FZ
    use scale_cpl_atmos_urban, only: &
       CPL_AtmUrb
    use mod_cpl_vars, only: &
       UST,              &
       ALBG,             &
       DENS => CPL_DENS, &
       MOMX => CPL_MOMX, &
       MOMY => CPL_MOMY, &
       MOMZ => CPL_MOMZ, &
       RHOS => CPL_RHOS, &
       PRES => CPL_PRES, &
       TMPS => CPL_TMPS, &
       QV   => CPL_QV  , &
       PREC => CPL_PREC, &
       SWD  => CPL_SWD , &
       LWD  => CPL_LWD , &
       TG   => CPL_TG,   &
       QVEF => CPL_QVEF, &
       TCS  => CPL_TCS,  &
       DZG  => CPL_DZG,  &
       Z0M  => CPL_Z0M,  &
       Z0H  => CPL_Z0H,  &
       Z0E  => CPL_Z0E,  &
       AtmUrb_XMFLX,     &
       AtmUrb_YMFLX,     &
       AtmUrb_ZMFLX,     &
       AtmUrb_SWUFLX,    &
       AtmUrb_LWUFLX,    &
       AtmUrb_SHFLX,     &
       AtmUrb_LHFLX,     &
       AtmUrb_QVFLX,     &
       Urb_GHFLX,        &
       Urb_PRECFLX,      &
       Urb_QVFLX,        &
       CNT_Atm_Urb,      &
       CNT_Urb
    implicit none

    ! argument
    logical, intent(in) :: update_flag

    ! work
    integer :: i, j

    real(RP) :: XMFLX (IA,JA) ! x-momentum flux at the surface [kg/m2/s]
    real(RP) :: YMFLX (IA,JA) ! y-momentum flux at the surface [kg/m2/s]
    real(RP) :: ZMFLX (IA,JA) ! z-momentum flux at the surface [kg/m2/s]
    real(RP) :: SWUFLX(IA,JA) ! upward shortwave flux at the surface [W/m2]
    real(RP) :: LWUFLX(IA,JA) ! upward longwave flux at the surface [W/m2]
    real(RP) :: SHFLX (IA,JA) ! sensible heat flux at the surface [W/m2]
    real(RP) :: LHFLX (IA,JA) ! latent heat flux at the surface [W/m2]
    real(RP) :: GHFLX (IA,JA) ! ground heat flux at the surface [W/m2]

    real(RP) :: tmpX(IA,JA) ! temporary XMFLX [kg/m2/s]
    real(RP) :: tmpY(IA,JA) ! temporary YMFLX [kg/m2/s]

    real(RP) :: DZ    (IA,JA) ! height from the surface to the lowest atmospheric layer [m]
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*) '*** Coupler: Atmos-Urban'

    DZ(:,:) = CZ(KS,:,:) - FZ(KS-1,:,:)

    call CPL_AtmUrb( &
      UST,                                      & ! (inout)
      XMFLX, YMFLX, ZMFLX,                      & ! (out)
      SWUFLX, LWUFLX, SHFLX, LHFLX, GHFLX,      & ! (out)
      update_flag,                              & ! (in)
      DZ, DENS, MOMX, MOMY, MOMZ,               & ! (in)
      RHOS, PRES, TMPS, QV, SWD, LWD,           & ! (in)
      TG, QVEF, ALBG(:,:,I_SW), ALBG(:,:,I_LW), & ! (in)
      TCS, DZG, Z0M, Z0H, Z0E                   ) ! (in)

    ! interpolate momentum fluxes
    do j = JS, JE
    do i = IS, IE
      tmpX(i,j) = ( XMFLX(i,j) + XMFLX(i+1,j  ) ) * 0.5_RP ! at u/y-layer
      tmpY(i,j) = ( YMFLX(i,j) + YMFLX(i,  j+1) ) * 0.5_RP ! at x/v-layer
    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
      XMFLX(i,j) = tmpX(i,j)
      YMFLX(i,j) = tmpY(i,j)
      ZMFLX(i,j) = ZMFLX(i,j) * 0.5_RP ! at w-layer
    enddo
    enddo

    ! temporal average flux
    AtmUrb_XMFLX (:,:) = ( AtmUrb_XMFLX (:,:) * CNT_Atm_Urb + XMFLX (:,:)     ) / ( CNT_Atm_Urb + 1.0_RP )
    AtmUrb_YMFLX (:,:) = ( AtmUrb_YMFLX (:,:) * CNT_Atm_Urb + YMFLX (:,:)     ) / ( CNT_Atm_Urb + 1.0_RP )
    AtmUrb_ZMFLX (:,:) = ( AtmUrb_ZMFLX (:,:) * CNT_Atm_Urb + ZMFLX (:,:)     ) / ( CNT_Atm_Urb + 1.0_RP )
    AtmUrb_SWUFLX(:,:) = ( AtmUrb_SWUFLX(:,:) * CNT_Atm_Urb + SWUFLX(:,:)     ) / ( CNT_Atm_Urb + 1.0_RP )
    AtmUrb_LWUFLX(:,:) = ( AtmUrb_LWUFLX(:,:) * CNT_Atm_Urb + LWUFLX(:,:)     ) / ( CNT_Atm_Urb + 1.0_RP )
    AtmUrb_SHFLX (:,:) = ( AtmUrb_SHFLX (:,:) * CNT_Atm_Urb + SHFLX (:,:)     ) / ( CNT_Atm_Urb + 1.0_RP )
    AtmUrb_LHFLX (:,:) = ( AtmUrb_LHFLX (:,:) * CNT_Atm_Urb + LHFLX (:,:)     ) / ( CNT_Atm_Urb + 1.0_RP )
    AtmUrb_QVFLX (:,:) = ( AtmUrb_QVFLX (:,:) * CNT_Atm_Urb + LHFLX (:,:)/LH0 ) / ( CNT_Atm_Urb + 1.0_RP )

    Urb_GHFLX  (:,:) = ( Urb_GHFLX  (:,:) * CNT_Urb + GHFLX(:,:)     ) / ( CNT_Urb + 1.0_RP )
    Urb_PRECFLX(:,:) = ( Urb_PRECFLX(:,:) * CNT_Urb + PREC (:,:)     ) / ( CNT_Urb + 1.0_RP )
    Urb_QVFLX  (:,:) = ( Urb_QVFLX  (:,:) * CNT_Urb - LHFLX(:,:)/LH0 ) / ( CNT_Urb + 1.0_RP )

    CNT_Atm_Urb = CNT_Atm_Urb + 1.0_RP
    CNT_Urb     = CNT_Urb     + 1.0_RP

    return
  end subroutine CPL_AtmUrb_driver

end module mod_cpl_atmos_urban_driver
