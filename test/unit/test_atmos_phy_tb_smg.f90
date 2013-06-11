module test_atmos_phy_tb_smg

  !-----------------------------------------------------------------------------
  use mod_atmos_phy_tb, only: &
     ATMOS_PHY_TB_main
  use dc_test, only: &
     AssertEqual, &
     AssertLessThan
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  public :: test_atmos_phy_tb_smg_run

  !-----------------------------------------------------------------------------
  include 'inc_precision.h'
  include 'inc_index.h'
  include 'inc_tracer.h'
  !-----------------------------------------------------------------------------
  real(RP) :: qflx_sgs_momz(KA,IA,JA,3)
  real(RP) :: qflx_sgs_momx(KA,IA,JA,3)
  real(RP) :: qflx_sgs_momy(KA,IA,JA,3)
  real(RP) :: qflx_sgs_rhot(KA,IA,JA,3)
  real(RP) :: qflx_sgs_qtrc(KA,IA,JA,QA,3)

  real(RP) :: tke (KA,IA,JA) ! TKE
  real(RP) :: nu_C(KA,IA,JA) ! eddy viscosity (center)
  real(RP) :: Pr  (KA,IA,JA) ! Prantle number
  real(RP) :: Ri  (KA,IA,JA) ! Richardson number

  real(RP) :: MOMZ(KA,IA,JA)
  real(RP) :: MOMX(KA,IA,JA)
  real(RP) :: MOMY(KA,IA,JA)
  real(RP) :: RHOT(KA,IA,JA)
  real(RP) :: DENS(KA,IA,JA)
  real(RP) :: QTRC(KA,IA,JA,QA)

  real(RP), save :: ZERO(KA,IA,JA,3)

  integer, save :: KME ! end of main region

  integer :: k, i, j, iq
  character(len=7) :: message
  !-----------------------------------------------------------------------------
contains

  subroutine test_atmos_phy_tb_smg_run
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use mod_atmos_vars, only: &
       ATMOS_TYPE_PHY_TB
  use mod_atmos_phy_tb, only: &
     ATMOS_PHY_TB_setup
  use mod_grid, only: &
     GRID_CZ_mask

  !-----------------------------------------------------------------------------
  implicit none
  !-----------------------------------------------------------------------------
  !
  !++ parameters & variables
  !
  !=============================================================================


  !########## Initial setup ##########
  ATMOS_TYPE_PHY_TB = 'SMAGORINSKY'
  call ATMOS_PHY_TB_setup

  ZERO(:,:,:,:) = 0.0_RP

  do k = KS+1, KE
     if ( .not. GRID_CZ_mask(k) ) then
        KME = k - 1
        exit
     end if
  end do

  !########## test ##########

  call test_zero

  call test_constant

  call test_big

  call test_double

end subroutine test_atmos_phy_tb_smg_run
!=============================================================================


subroutine test_zero

  write(*,*) "Test zero"

  MOMZ(:,:,:) = 0.0_RP
  MOMX(:,:,:) = 0.0_RP
  MOMY(:,:,:) = 0.0_RP
  RHOT(:,:,:) = 1.0_RP
  DENS(:,:,:) = 1.0_RP
  QTRC(:,:,:,:) = 0.0_RP

  call ATMOS_PHY_TB_main( &
       qflx_sgs_momz, qflx_sgs_momx, qflx_sgs_momy, & ! (out)
       qflx_sgs_rhot, qflx_sgs_qtrc,           & ! (out)
       tke, nu_C, Ri, Pr,                      & ! (out)
       MOMZ, MOMX, MOMY, RHOT, DENS, QTRC      ) ! (in)

  call AssertEqual("qflx_sgs_momz", ZERO(KS:KE,IS:IE,JS:JE,:), qflx_sgs_momx(KS:KE,IS:IE,JS:JE,:))
  call AssertEqual("qflx_sgs_momx", ZERO(KS:KE,IS:IE,JS:JE,:), qflx_sgs_momx(KS:KE,IS:IE,JS:JE,:))
  call AssertEqual("qflx_sgs_momy", ZERO(KS:KE,IS:IE,JS:JE,:), qflx_sgs_momy(KS:KE,IS:IE,JS:JE,:))
  call AssertEqual("qflx_sgs_rhot", ZERO(KS:KE,IS:IE,JS:JE,:), qflx_sgs_rhot(KS:KE,IS:IE,JS:JE,:))
  message = "iq = ??"
  do iq = 1, QA
     write(message(6:7), "(i2)") iq
     call AssertEqual(message, ZERO(KS:KE,IS:IE,JS:JE,:), qflx_sgs_rhot(KS:KE,IS:IE,JS:JE,:))
  end do

end subroutine test_zero
!=============================================================================
subroutine test_constant

  write(*,*) "Test constant"

  MOMZ(:,:,:) = 1.0_RP
  MOMX(:,:,:) = 1.0_RP
  MOMY(:,:,:) = 1.0_RP
  RHOT(:,:,:) = 1.0_RP
  DENS(:,:,:) = 1.0_RP
  QTRC(:,:,:,:) = 1.0_RP

  call fill_halo(MOMZ, MOMX, MOMY, RHOT, DENS, QTRC)

  call ATMOS_PHY_TB_main( &
       qflx_sgs_momz, qflx_sgs_momx, qflx_sgs_momy, & ! (out)
       qflx_sgs_rhot, qflx_sgs_qtrc,           & ! (out)
       tke, nu_C, Ri, Pr,                      & ! (out)
       MOMZ, MOMX, MOMY, RHOT, DENS, QTRC      ) ! (in)

  call AssertEqual("qflx_sgs_momz", ZERO(KS+1:KE-1,IS:IE,JS:JE,:), qflx_sgs_momz(KS+1:KE-1,IS:IE,JS:JE,:))
  call AssertEqual("qflx_sgs_momx", ZERO(KS+1:KE,IS:IE,JS:JE,:), qflx_sgs_momx(KS+1:KE,IS:IE,JS:JE,:))
  call AssertEqual("qflx_sgs_momy", ZERO(KS+1:KE,IS:IE,JS:JE,:), qflx_sgs_momy(KS+1:KE,IS:IE,JS:JE,:))
  call AssertEqual("qflx_sgs_rhot", ZERO(KS:KE,IS:IE,JS:JE,:), qflx_sgs_rhot(KS:KE,IS:IE,JS:JE,:))
  message = "iq = ??"
  do iq = 1, QA
     write(message(6:7), "(i2)") iq
     call AssertEqual(message, ZERO(KS:KE,IS:IE,JS:JE,:), qflx_sgs_rhot(KS:KE,IS:IE,JS:JE,:))
  end do

end subroutine test_constant
!=============================================================================
subroutine test_big

  real(RP) :: BIG(KA,IA,JA,3)

  real(RP) :: PI2

  PI2 = atan( 1.0_RP )*8.0_RP

  BIG(:,:,:,:) = 9.99E8_RP

  write(*,*) "Test big"
  ! check not to include BUG (UNDEF) value

  do j = 1, JA
  do i = 1, IA
  do k = 1, KA
     MOMZ(k,i,j) = 1.0_RP * sin( k*1.0_RP + i*2.0_RP + j*3.0_RP )
     MOMX(k,i,j) = 2.0_RP * cos( k*2.0_RP + i*3.0_RP + j*1.0_RP )
     MOMY(k,i,j) = 3.0_RP * sin( k*3.0_RP + i*1.0_RP + j*2.0_RP )
     RHOT(k,i,j) = 4.0_RP * cos( k*1.0_RP + i*1.0_RP + j*3.0_RP ) + 300.0_RP
     DENS(k,i,j) = 5.0_RP * sin( k*2.0_RP + i*2.0_RP + j*2.0_RP ) + 6.0_rp
     do iq = 1, QA
        QTRC(k,i,j,iq) = 6.0_RP * sin( k*3.0_RP + i*3.0_RP + j*1.0_RP + iq*2.0_RP ) + 6.0_RP
     end do
  end do
  end do
  end do

  call fill_halo(MOMZ, MOMX, MOMY, RHOT, DENS, QTRC)

  call ATMOS_PHY_TB_main( &
       qflx_sgs_momz, qflx_sgs_momx, qflx_sgs_momy, & ! (out)
       qflx_sgs_rhot, qflx_sgs_qtrc,           & ! (out)
       tke, nu_C, Ri, Pr,                      & ! (out)
       MOMZ, MOMX, MOMY, RHOT, DENS, QTRC      ) ! (in)

  call AssertLessThan("qflx_sgs_momz", BIG(KS+1:KE-1,IS:IE,JS:JE,:), abs(qflx_sgs_momz(KS+1:KE-1,IS:IE,JS:JE,:)))
  call AssertLessThan("qflx_sgs_momx", BIG(KS:KE,IS:IE,JS:JE,:), abs(qflx_sgs_momx(KS:KE,IS:IE,JS:JE,:)))
  call AssertLessThan("qflx_sgs_momy", BIG(KS:KE,IS:IE,JS:JE,:), abs(qflx_sgs_momy(KS:KE,IS:IE,JS:JE,:)))
  call AssertLessThan("qflx_sgs_rhot", BIG(KS:KE,IS:IE,JS:JE,:), abs(qflx_sgs_rhot(KS:KE,IS:IE,JS:JE,:)))
  message = "iq = ??"
  do iq = 1, QA
     write(message(6:7), "(i2)") iq
     call AssertLessThan(message, BIG(KS:KE,IS:IE,JS:JE,:), abs(qflx_sgs_qtrc(KS:KE,IS:IE,JS:JE,iq,:)))
  end do

end subroutine test_big
!=============================================================================
subroutine test_double

  real(RP) :: qflx_sgs_momz2(KA,IA,JA,3)
  real(RP) :: qflx_sgs_momx2(KA,IA,JA,3)
  real(RP) :: qflx_sgs_momy2(KA,IA,JA,3)
  real(RP) :: qflx_sgs_rhot2(KA,IA,JA,3)
  real(RP) :: qflx_sgs_qtrc2(KA,IA,JA,QA,3)

  real(RP) :: work(KA,IA,JA,3)
  real(RP) :: FOUR(KA,IA,JA,3)
  real(RP) :: PI2

  FOUR(:,:,:,:) = 4.0_RP
  PI2 = atan( 1.0_RP )*8.0_RP

  write(*,*) "Test double"

  do j = 1, JA
  do i = 1, IA
  do k = 1, KA
     MOMZ(k,i,j) = 1.0_RP * sin( PI2 * ( k*1.0_RP/(KE-KS+1) + i*2.0_RP/(IE-IS+1) + j*3.0_RP/(JE-JS+1) ) )
     MOMX(k,i,j) = 2.0_RP * cos( PI2 * ( k*2.0_RP/(KE-KS+1) + i*3.0_RP/(IE-IS+1) + j*1.0_RP/(JE-JS+1) ) )
     MOMY(k,i,j) = 3.0_RP * sin( PI2 * ( k*3.0_RP/(KE-KS+1) + i*1.0_RP/(IE-IS+1) + j*2.0_RP/(JE-JS+1) ) )
     do iq = 1, QA
        QTRC(k,i,j,iq) = real(iq,RP) * sin( PI2 * ( k*2.0_RP/(KE-KS+1) + i*1.0_RP/(IE-IS+1) + j*3.0_RP/(JE-JS+1) ) )
     end do
  end do
  end do
  end do
  DENS(:,:,:) = 1.0_RP
  RHOT(:,:,:) = 1.0_RP ! Ri = 0

  call fill_halo(MOMZ, MOMX, MOMY, RHOT, DENS, QTRC)

  call ATMOS_PHY_TB_main( &
       qflx_sgs_momz, qflx_sgs_momx, qflx_sgs_momy, & ! (out)
       qflx_sgs_rhot, qflx_sgs_qtrc,           & ! (out)
       tke, nu_C, Ri, Pr,                      & ! (out)
       MOMZ, MOMX, MOMY, RHOT, DENS, QTRC      ) ! (in)

  MOMZ(:,:,:) = MOMZ(:,:,:) * 2.0_RP
  MOMX(:,:,:) = MOMX(:,:,:) * 2.0_RP
  MOMY(:,:,:) = MOMY(:,:,:) * 2.0_RP
  QTRC(:,:,:,:) = QTRC(:,:,:,:) * 2.0_RP

  call ATMOS_PHY_TB_main( &
       qflx_sgs_momz2, qflx_sgs_momx2, qflx_sgs_momy2, & ! (out)
       qflx_sgs_rhot2, qflx_sgs_qtrc2,           & ! (out)
       tke, nu_C, Ri, Pr,                      & ! (out)
       MOMZ, MOMX, MOMY, RHOT, DENS, QTRC      ) ! (in)


  call AssertEqual("qflx_sgs_momz", FOUR(KS+1:KME-1,IS:IE,JS:JE,:), &
       qflx_sgs_momz2(KS+1:KME-1,IS:IE,JS:JE,:)/qflx_sgs_momz(KS+1:KME-1,IS:IE,JS:JE,:))
  where(qflx_sgs_momx .ne. 0.0_RP) work = qflx_sgs_momx2 / qflx_sgs_momx
  where(qflx_sgs_momx .eq. 0.0_RP) work = 4.0_RP
  call AssertEqual("qflx_sgs_momx", FOUR(KS:KE,IS:IE,JS:JE,:), work(KS:KE,IS:IE,JS:JE,:))
  where(qflx_sgs_momy .ne. 0.0_RP) work = qflx_sgs_momy2 / qflx_sgs_momy
  where(qflx_sgs_momy .eq. 0.0_RP) work = 4.0_RP
  call AssertEqual("qflx_sgs_momy", FOUR(KS:KE,IS:IE,JS:JE,:), work(KS:KE,IS:IE,JS:JE,:))
  message = "iq = ??"
  do iq = 1, QA
     where(qflx_sgs_qtrc2(:,:,:,iq,:) .ne. 0.0_RP) work = qflx_sgs_qtrc2(:,:,:,iq,:) / qflx_sgs_qtrc(:,:,:,iq,:)
     where(qflx_sgs_qtrc2(:,:,:,iq,:) .eq. 0.0_RP) work = 4.0_RP
     write(message(6:7), "(i2)") iq
     call AssertEqual(message, FOUR(KS:KE,IS:IE,JS:JE,:), work(KS:KE,IS:IE,JS:JE,:))
  end do

end subroutine test_double

!=============================================================================
subroutine fill_halo(MOMZ, MOMX, MOMY, RHOT, DENS, QTRC)
  implicit  none
  real(RP), intent(inout) :: MOMZ(KA,IA,JA)
  real(RP), intent(inout) :: MOMX(KA,IA,JA)
  real(RP), intent(inout) :: MOMY(KA,IA,JA)
  real(RP), intent(inout) :: RHOT(KA,IA,JA)
  real(RP), intent(inout) :: DENS(KA,IA,JA)
  real(RP), intent(inout) :: QTRC(KA,IA,JA,QA)

  do j = 1, JA
  do i = 1, IA
     MOMZ(1:KS-1,i,j) = MOMZ(KS,i,j)
     MOMX(1:KS-1,i,j) = MOMX(KS,i,j)
     MOMY(1:KS-1,i,j) = MOMY(KS,i,j)
     RHOT(1:KS-1,i,j) = RHOT(KS,i,j)
     DENS(1:KS-1,i,j) = DENS(KS,i,j)

     MOMZ(KE+1:KA,i,j) = MOMZ(KE,i,j)
     MOMX(KE+1:KA,i,j) = MOMX(KE,i,j)
     MOMY(KE+1:KA,i,j) = MOMY(KE,i,j)
     RHOT(KE+1:KA,i,j) = RHOT(KE,i,j)
     DENS(KE+1:KA,i,j) = DENS(KE,i,j)
  end do
  end do
  do iq = 1, QA
  do j = 1, JA
  do i = 1, IA
     QTRC(1:KS-1,i,j,iq) = QTRC(KS,i,j,iq)
     QTRC(KE+1:KA,i,j,iq) = QTRC(KE,i,j,iq)
  end do
  end do
  end do

end subroutine fill_halo


end module test_atmos_phy_tb_smg
