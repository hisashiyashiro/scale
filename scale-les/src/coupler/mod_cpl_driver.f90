!-------------------------------------------------------------------------------
!> module CPL driver
!!
!! @par Description
!!          Coupler driver
!!
!! @author Team SCALE
!! @li      2013-08-31 (T.Yamaura)  [new]
!<
!-------------------------------------------------------------------------------
module mod_cpl_driver
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use scale_precision
  use scale_stdio
  use scale_prof
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: CPL_driver_setup
  public :: CPL_driver

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
  !-----------------------------------------------------------------------------
  !> Setup
  subroutine CPL_driver_setup
    use mod_cpl_vars, only: &
       sw_AtmLnd => CPL_sw_AtmLnd, &
       sw_AtmUrb => CPL_sw_AtmUrb, &
       sw_AtmOcn => CPL_sw_AtmOcn, &
       CPL_vars_merge,             &
       CPL_vars_fillhalo
    use mod_cpl_atmos_land_driver, only: &
       CPL_AtmLnd_driver_setup
    use mod_cpl_atmos_urban_driver, only: &
       CPL_AtmUrb_driver_setup
    use mod_cpl_atmos_ocean_driver, only: &
       CPL_AtmOcn_driver_setup
    implicit none
    !---------------------------------------------------------------------------

    if( sw_AtmLnd ) call CPL_AtmLnd_driver_setup
    if( sw_AtmUrb ) call CPL_AtmUrb_driver_setup
    if( sw_AtmOcn ) call CPL_AtmOcn_driver_setup

    call CPL_vars_merge

    call CPL_vars_fillhalo

    return
  end subroutine CPL_driver_setup

  !-----------------------------------------------------------------------------
  !> CPL calcuration
  subroutine CPL_driver
    use mod_cpl_vars, only: &
       sw_AtmLnd  => CPL_sw_AtmLnd,  &
       sw_AtmUrb  => CPL_sw_AtmUrb,  &
       sw_AtmOcn  => CPL_sw_AtmOcn,  &
       LST_UPDATE => CPL_LST_UPDATE, &
       UST_UPDATE => CPL_UST_UPDATE, &
       SST_UPDATE => CPL_SST_UPDATE, &
       CPL_vars_fillhalo,            &
       CPL_vars_merge,               &
       CPL_vars_history
    use mod_cpl_atmos_land_driver, only: &
       CPL_AtmLnd_driver
    use mod_cpl_atmos_urban_driver, only: &
       CPL_AtmUrb_driver
    use mod_cpl_atmos_ocean_driver, only: &
       CPL_AtmOcn_driver
    implicit none
    !---------------------------------------------------------------------------

    !########## Coupler Atoms-Land ##########
    if( sw_AtmLnd ) then
      call PROF_rapstart('CPL Atmos-Land')
      call CPL_AtmLnd_driver( LST_UPDATE )
      call PROF_rapend  ('CPL Atmos-Land')
    endif

    !########## Coupler Atoms-Urban ##########
    if( sw_AtmUrb ) then
      call PROF_rapstart('CPL Atmos-Urban')
      call CPL_AtmUrb_driver( UST_UPDATE )
      call PROF_rapend  ('CPL Atmos-Urban')
    endif

    !########## Coupler Atoms-Ocean ##########
    if( sw_AtmOcn ) then
      call PROF_rapstart('CPL Atmos-Ocean')
      call CPL_AtmOcn_driver( SST_UPDATE )
      call PROF_rapend  ('CPL Atmos-Ocean')
    endif

    !########## merge Land-Ocean ##########
    call CPL_vars_merge

    !########## Fill HALO ##########
    call CPL_vars_fillhalo

    !########## History & Monitor ##########
    call PROF_rapstart('CPL History')
    call CPL_vars_history
    call PROF_rapend  ('CPL History')

    return
  end subroutine CPL_driver

end module mod_cpl_driver
