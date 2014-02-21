!-------------------------------------------------------------------------------
!> module COUPLER / Surface Bulk coefficient
!!
!! @par Description
!!          calculation of Bulk coefficient at the surface
!!
!! @author Team SCALE
!!
!! @par History
!! @li      2014-02-18 (T.Yamaura)  [new]
!<
!-------------------------------------------------------------------------------
module mod_cpl_bulkcoef
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use mod_precision
  use mod_stdio
  use mod_prof
  use mod_grid_index
  use mod_tracer
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: CPL_bulkcoef_setup

  abstract interface
     subroutine bc( &
          Cm, Ch, Ce,                    & ! (out)
          pta, pts, za, uabs, z0, zt, ze ) ! (in)
       use mod_precision
       use mod_grid_index
       use mod_tracer
       implicit none

       real(RP), intent(out) :: Cm ! momentum bulk coefficient [no unit]
       real(RP), intent(out) :: Ch ! heat bulk coefficient [no unit]
       real(RP), intent(out) :: Ce ! moisture bulk coefficient [no unit]

       real(RP), intent(in) :: pta  ! potential tempearature at 1st atm. layer [K]
       real(RP), intent(in) :: pts  ! skin potential temperature [K]
       real(RP), intent(in) :: za   ! height at 1st atm. layer [m]
       real(RP), intent(in) :: uabs ! wind speed at 1st atm. layer [m/s]
       real(RP), intent(in) :: z0   ! roughness length of momentum [m]
       real(RP), intent(in) :: zt   ! roughness length of heat [m]
       real(RP), intent(in) :: ze   ! roughness length of moisture [m]
     end subroutine bc
  end interface

  procedure(bc), pointer :: CPL_bulkcoef => NULL()
  public :: CPL_bulkcoef

  !-----------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !
  !-----------------------------------------------------------------------------
  !
  !++ Private procedure
  !
  private :: CPL_bulkcoef_uno
  private :: CPL_bulkcoef_beljaars
  private :: fmUS
  private :: fhUS
  private :: fmS
  private :: fhS

  !-----------------------------------------------------------------------------
  !
  !++ Private parameters & variables
  !
  ! limiter
  real(RP), private, parameter :: Cm_min =   1.0E-8_RP ! minimum bulk coef. of u,v,w
  real(RP), private, parameter :: Ch_min =   1.0E-8_RP !                       T
  real(RP), private, parameter :: Ce_min =   1.0E-8_RP !                       q
  real(RP), private, parameter :: Cm_max =   1.0_RP    ! maximum bulk coef. of u,v,w
  real(RP), private, parameter :: Ch_max =   1.0_RP    !                       T
  real(RP), private, parameter :: Ce_max =   1.0_RP    !                       q

contains

  !-----------------------------------------------------------------------------
  !
  !-----------------------------------------------------------------------------
  subroutine CPL_bulkcoef_setup( BULK_TYPE )
    implicit none

    character(len=H_SHORT), intent(in) :: BULK_TYPE
    !---------------------------------------------------------------------------

    select case( BULK_TYPE )
    case ( 'U95' )
       CPL_bulkcoef => CPL_bulkcoef_uno
    case ( 'BH91' )
       CPL_bulkcoef => CPL_bulkcoef_beljaars
    end select

    return
  end subroutine CPL_bulkcoef_setup

  subroutine CPL_bulkcoef_uno( &
      Cm, Ch, Ce,                    & ! (out)
      pta, pts, za, uabs, z0, zt, ze ) ! (in)
    use mod_const, only: &
      GRAV   => CONST_GRAV,  &
      KARMAN => CONST_KARMAN
    implicit none

    ! argument
    real(RP), intent(out) :: Cm   ! momentum bulk coefficient [no unit]
    real(RP), intent(out) :: Ch   ! heat bulk coefficient [no unit]
    real(RP), intent(out) :: Ce   ! moisture bulk coefficient [no unit]

    real(RP), intent(in) :: pta  ! potential tempearature at 1st atm. layer [K]
    real(RP), intent(in) :: pts  ! skin potential temperature [K]
    real(RP), intent(in) :: za   ! height at 1st atm. layer [m]
    real(RP), intent(in) :: uabs ! wind speed at 1st atm. layer [m/s]
    real(RP), intent(in) :: z0   ! roughness length of momentum [m]
    real(RP), intent(in) :: zt   ! roughness length of heat [m]
    real(RP), intent(in) :: ze   ! roughness length of moisture [m]

    ! constant
    real(RP), parameter :: tPrn = 0.74_RP    ! turbulent Prandtl number (Businger et al. 1971)
    real(RP), parameter :: LFb  = 9.4_RP     ! Louis factor b (Louis 1979)
    real(RP), parameter :: LFbp = 4.7_RP     ! Louis factor b' (Louis 1979)
    real(RP), parameter :: LFdm = 7.4_RP     ! Louis factor d for momemtum (Louis 1979)
    real(RP), parameter :: LFdh = 5.3_RP     ! Louis factor d for heat (Louis 1979)

    ! work
    real(RP) :: RiB, RiBT ! bulk Richardson number [no unit]
    real(RP) :: C0 ! initial drag coefficient [no unit]
    real(RP) :: fm, fh, t0th, q0qe

    C0    = ( KARMAN / log( za/z0 ) )**2
    RiBT  = GRAV * za * ( pta - pts ) / ( pta * uabs**2 )
    RiB   = RiBT

    if( RiBT >= 0.0_RP ) then
      ! stable condition
      fm = 1.0_RP / ( 1.0_RP + LFbp * RiB )**2
      fh = fm
    else
      ! unstable condition
      fm = 1.0_RP - LFb * RiB / ( 1.0_RP + LFb * LFdm * C0 * sqrt( za/z0 ) * sqrt( abs( RiB ) ) )
      fh = 1.0_RP - LFb * RiB / ( 1.0_RP + LFb * LFdh * C0 * sqrt( za/z0 ) * sqrt( abs( RiB ) ) )
    end if

    t0th = 1.0_RP / ( 1.0_RP + log( z0/zt ) / log( za/z0 ) / sqrt( fm ) * fh )
    q0qe = 1.0_RP / ( 1.0_RP + log( z0/ze ) / log( za/z0 ) / sqrt( fm ) * fh )
    RiB  = RiB * t0th

    if( RiBT >= 0.0_RP ) then
      ! stable condition
      fm = 1.0_RP / ( 1.0_RP + LFbp * RiB )**2
      fh = fm
    else
      ! unstable condition
      fm = 1.0_RP - LFb * RiB / ( 1.0_RP + LFb * LFdm * C0 * sqrt( za/z0 ) * sqrt( abs( RiB ) ) )
      fh = 1.0_RP - LFb * RiB / ( 1.0_RP + LFb * LFdh * C0 * sqrt( za/z0 ) * sqrt( abs( RiB ) ) )
    end if

    t0th = 1.0_RP / ( 1.0_RP + log( z0/zt ) / log( za/z0 ) / sqrt( fm ) * fh )
    q0qe = 1.0_RP / ( 1.0_RP + log( z0/ze ) / log( za/z0 ) / sqrt( fm ) * fh )

    Cm = C0 * fm
    Ch = C0 * fh * t0th / tPrn
    Ce = C0 * fh * q0qe / tPrn

    Cm = min( max( Cm, Cm_min ), Cm_max )
    Ch = min( max( Ch, Ch_min ), Ch_max )
    Ce = min( max( Ce, Ce_min ), Ce_max )

    return
  end subroutine CPL_bulkcoef_uno

  subroutine CPL_bulkcoef_beljaars( &
      Cm, Ch, Ce,                    & ! (out)
      pta, pts, za, uabs, z0, zt, ze ) ! (in)
    use mod_const, only: &
      GRAV   => CONST_GRAV, &
      KARMAN => CONST_KARMAN
    implicit none

    ! argument
    real(RP), intent(out) :: Cm   ! momentum bulk coefficient [no unit]
    real(RP), intent(out) :: Ch   ! heat bulk coefficient [no unit]
    real(RP), intent(out) :: Ce   ! moisture bulk coefficient [no unit]

    real(RP), intent(in) :: pta  ! potential tempearature at 1st atm. layer [K]
    real(RP), intent(in) :: pts  ! skin potential temperature [K]
    real(RP), intent(in) :: za   ! height at 1st atm. layer [m]
    real(RP), intent(in) :: uabs ! wind speed at 1st atm. layer [m/s]
    real(RP), intent(in) :: z0   ! roughness length of momentum [m]
    real(RP), intent(in) :: zt   ! roughness length of heat [m]
    real(RP), intent(in) :: ze   ! roughness length of moisture [m]

    ! constant
    integer,  parameter :: nmax    = 100        ! maximum iteration number

    real(RP), parameter :: RiB_min = 1.0E-4_RP
    real(RP), parameter :: res_min = 1.0E-6_RP
    real(RP), parameter :: dL      = 1.0E-10_RP ! delta Obukhov length [m]

    ! variables
    integer :: n
    real(RP) :: RiB0, RiB ! bulk Richardson number [no unit]
    real(RP) :: L ! Obukhov length [m]
    real(RP) :: res, dres
    real(RP) :: dCm, dCh, dCe
    real(RP) :: tmp

    RiB0 = GRAV * za * ( pta - pts ) / ( pta * uabs**2 )
    if( abs( RiB0 ) < RiB_min ) then
      RiB0 = RiB_min
    end if

    ! The initial Obukhov length is assumed by bulk Richardson number.
    L = za / RiB0

    do n = 1, nmax
      if( L < 0.0_RP ) then
        ! unstable condition
        Cm = KARMAN**2 / ( log(za/z0) - fmUS(za/L) + fmUS(z0/L) )**2
        Ch = KARMAN**2 / ( log(za/z0) - fmUS(za/L) + fmUS(z0/L) ) / ( log(za/zt) - fhUS(za/L) + fhUS(zt/L) )
        Ce = KARMAN**2 / ( log(za/z0) - fmUS(za/L) + fmUS(z0/L) ) / ( log(za/ze) - fhUS(za/L) + fhUS(ze/L) )
      else
        ! stable condition
        Cm = KARMAN**2 / ( log(za/z0) - fmS(za/L) + fmS(z0/L) )**2
        Ch = KARMAN**2 / ( log(za/z0) - fmS(za/L) + fmS(z0/L) ) / ( log(za/zt) - fhS(za/L) + fhS(zt/L) )
        Ce = KARMAN**2 / ( log(za/z0) - fmS(za/L) + fmS(z0/L) ) / ( log(za/ze) - fhS(za/L) + fhS(ze/L) )
      end if
      ! calculate residual
      res = L - za * Cm**1.5_RP / ( KARMAN * Ch * RiB0 )

      if( L+dL < 0.0_RP ) then
        ! unstable condition
        dCm = KARMAN**2 / ( log(za/z0) - fmUS(za/(L+dL)) + fmUS(z0/(L+dL)) )**2
        dCh = KARMAN**2 / ( log(za/z0) - fmUS(za/(L+dL)) + fmUS(z0/(L+dL)) ) / ( log(za/zt) - fhUS(za/(L+dL)) + fhUS(zt/(L+dL)) )
        dCe = KARMAN**2 / ( log(za/z0) - fmUS(za/(L+dL)) + fmUS(z0/(L+dL)) ) / ( log(za/ze) - fhUS(za/(L+dL)) + fhUS(ze/(L+dL)) )
      else
        ! stable condition
        dCm = KARMAN**2 / ( log(za/z0) - fmS(za/(L+dL)) + fmS(z0/(L+dL)) )**2
        dCh = KARMAN**2 / ( log(za/z0) - fmS(za/(L+dL)) + fmS(z0/(L+dL)) ) / ( log(za/zt) - fhS(za/(L+dL)) + fhS(zt/(L+dL)) )
        dCe = KARMAN**2 / ( log(za/z0) - fmS(za/(L+dL)) + fmS(z0/(L+dL)) ) / ( log(za/ze) - fhS(za/(L+dL)) + fhS(ze/(L+dL)) )
      end if
      ! calculate d(residual)
      dres = (L+dL) - za * dCm**1.5_RP / ( KARMAN * dCh * RiB0 )

      ! update Obukhov length
      L = L - res / ( dres - res ) * dL

      ! update bulk Richardson nubmer
      RiB = za * Cm**1.5_RP / ( L * KARMAN * Ch )

      if( abs( res ) < res_min ) then
        ! finish iteration
        exit
      end if

    end do

    if( n > nmax ) then
      write(*,*) 'Error: reach maximum iteration in the function of CPL_bulkcoef_beljaars.'
    end if

    Cm = min( max( Cm, Cm_min ), Cm_max )
    Ch = min( max( Ch, Ch_min ), Ch_max )
    Ce = min( max( Ce, Ce_min ), Ce_max )

    return
  end subroutine CPL_bulkcoef_beljaars

  ! stability function for momemtum in unstable condition
  function fmUS( R )
    use mod_const, only: &
      PI => CONST_PI
    implicit none

    ! argument
    real(RP), intent(in) :: R

    ! function
    real(RP) :: fmUS
    
    ! Paulson (1974); Dyer (1974)
    fmUS = log( ( 1.0_RP + ( 1.0_RP - 16.0_RP * R )**0.25_RP )**2 * ( 1.0_RP + sqrt( 1.0_RP - 16.0_RP * R ) ) * 0.125_RP ) &
         - 2.0_RP * atan( ( 1.0_RP - 16.0_RP * R )**0.25_RP ) + PI * 0.5_RP

    return
  end function fmUS

  ! stability function for heat/vapor in unstable condition
  function fhUS( R )
    implicit none

    ! argument
    real(RP), intent(in) :: R

    ! function
    real(RP) :: fhUS
    
    ! Paulson (1974); Dyer (1974)
    fhUS = 2.0_RP * log( ( 1.0_RP + sqrt( 1.0_RP - 16.0_RP * R ) ) * 0.5_RP )

    return
  end function fhUS

  ! stability function for momemtum in stable condition
  function fmS( R )
    implicit none

    ! argument
    real(RP), intent(in) :: R

    ! function
    real(RP) :: fmS
    
    ! parameters of stability functions (Beljaars and Holtslag 1991)
    real(RP), parameter :: a = 1.0_RP
    real(RP), parameter :: b = 0.667_RP
    real(RP), parameter :: c = 5.0_RP
    real(RP), parameter :: d = 0.35_RP

    ! Holtslag and DeBruin (1988)
    fmS = - a*R - b*( R - c/d )*exp( -d*R ) - b*c/d

    return
  end function fmS

  ! stability function for heat/vapor in stable condition
  function fhS( R )
    implicit none

    ! argument
    real(RP), intent(in) :: R

    ! function
    real(RP) :: fhS
    
    ! parameters of stability functions (Beljaars and Holtslag 1991)
    real(RP), parameter :: a = 1.0_RP
    real(RP), parameter :: b = 0.667_RP
    real(RP), parameter :: c = 5.0_RP
    real(RP), parameter :: d = 0.35_RP

    ! Beljaars and Holtslag (1991)
    fhS = 1.0_RP - ( 1.0_RP + 2.0_RP/3.0_RP * a*R )**1.5_RP - b*( R - c/d )*exp( -d*R ) - b*c/d 

    return
  end function fhS

end module mod_cpl_bulkcoef