module mod_initflow
  use mpi
  use decomp_2d
  use mod_common_mpi, only: ierr,coord,myid
  use mod_param     , only: dims,rey
  implicit none
  private
  public initflow,add_noise
  contains
  subroutine initflow(inivel,n,zclzi,dzclzi,dzflzi,visc,norm,u,v,w,p)
    !
    ! computes initial conditions for the velocity field
    !
    implicit none
    character(len=3), intent(in) :: inivel
    integer, intent(in), dimension(3) :: n
    real(8), intent(in), dimension(0:) :: zclzi,dzclzi,dzflzi
    real(8), intent(in) :: norm
    real(8), intent(in) :: visc
    real(8), dimension(0:,0:,0:), intent(out) :: u,v,w,p
    real(8), allocatable, dimension(:) :: u1d
    !real(8), allocatable, dimension(:,:) :: u2d
    integer :: i,j,k
    real(8) :: q
    logical :: is_noise,is_mean
    !
    allocate(u1d(n(3)))
    is_noise = .false.
    is_mean  = .false.
    q = .5d0
    select case(inivel)
    case('cou')
      call couette(   q,n(3),zclzi,norm,u1d)
    case('poi')
      call poiseuille(q,n(3),zclzi,norm,u1d)
      is_mean=.true.
    case('zer')
      u1d(:) = 0.
    case('log')
      call log_profile(q,n(3),zclzi,visc,u1d)
      is_noise = .true.
      is_mean = .true.
    case('hcl')
      deallocate(u1d)
      allocate(u1d(2*n(3)))
      call log_profile(q,2*n(3),zclzi,visc,u1d)
      is_noise = .true.
      is_mean=.true.
    case('hcp')
      deallocate(u1d)
      allocate(u1d(2*n(3)))
      call poiseuille(q,2*n(3),zclzi,norm,u1d)
      is_mean = .true.
    case default
      if(myid.eq.0) print*, 'ERROR: invalid name for initial velocity field'
      if(myid.eq.0) print*, ''
      if(myid.eq.0) print*, '*** Simulation abortited due to errors in the case file ***'
      if(myid.eq.0) print*, '    check setup.h90'
      call decomp_2d_finalize
      call MPI_FINALIZE(ierr)
      call exit
    end select
    do k=1,n(3)
      do j=1,n(2)
        do i=1,n(1)
          u(i,j,k) = u1d(k)
          v(i,j,k) = 0.d0
          w(i,j,k) = 0.d0
          p(i,j,k) = 0.d0
        enddo
      enddo
    enddo
    deallocate(u1d)
    if(is_noise) then
      call add_noise(n,123,.50d0,u(1:n(1),1:n(2),1:n(3)))
      call add_noise(n,456,.50d0,v(1:n(1),1:n(2),1:n(3)))
      call add_noise(n,789,.50d0,w(1:n(1),1:n(2),1:n(3)))
    endif
    if(is_mean) then
      call set_mean(n,1.d0,dzflzi,u(1:n(1),1:n(2),1:n(3)))
    endif
    return
  end subroutine initflow
  !
  subroutine add_noise(n,iseed,norm,p)
    implicit none
    integer, intent(in), dimension(3) :: n
    integer, intent(in) :: iseed
    real(8), intent(in) :: norm 
    real(8), intent(inout), dimension(n(1),n(2),n(3)) :: p
    integer(4), allocatable, dimension(:) :: seed
    real(8) :: rn
    integer, dimension(3) :: ng
    integer :: i,j,k,ii,jj
    allocate(seed(64))
    seed(:) = iseed
    call random_seed( put = seed )
    ng(:) = n(:)
    ng(1:2) = ng(1:2)*dims(1:2)
    do k=1,ng(3)
      do j=1,ng(2)
        jj = j-coord(2)*n(2)
        do i=1,ng(1)
          ii = i-coord(1)*n(1)
          call random_number(rn)
          if(ii.ge.1.and.ii.le.n(1) .and. &
             jj.ge.1.and.jj.le.n(2) ) then
             p(ii,jj,k) = p(ii,jj,k) + 2.d0*(rn-.5d0)*norm
          endif
        enddo
      enddo
    enddo
    return
  end subroutine add_noise
  !
  subroutine set_mean(n,mean,dzlzi,p)
  implicit none
  integer, intent(in), dimension(3) :: n
  real(8), intent(in), dimension(0:) :: dzlzi 
  real(8), intent(in) :: mean
  real(8), intent(inout), dimension(n(1),n(2),n(3)) :: p
  real(8) :: meanold
  integer :: i,j,k
    meanold = 0.d0
    !$OMP PARALLEL DO DEFAULT(none) &
    !$OMP SHARED(n,p,dzlzi) &
    !$OMP PRIVATE(i,j,k) &
    !$OMP REDUCTION(+:meanold)
    do k=1,n(3)
      do j=1,n(2)
        do i=1,n(1)
          meanold = meanold + p(i,j,k)*dzlzi(k)
        enddo
      enddo
    enddo
    !$OMP END PARALLEL DO
    call mpi_allreduce(MPI_IN_PLACE,meanold,1,MPI_REAL8,MPI_SUM,MPI_COMM_WORLD,ierr)
    meanold = meanold/(1.d0*n(1)*dims(1)*n(2)*dims(2))
    !
    if(meanold.ne.0.d0) then
      !$OMP WORKSHARE
      p(:,:,:) = p(:,:,:)/meanold*mean
      !$OMP END WORKSHARE
    endif
    return
  end subroutine set_mean
  !
  subroutine couette(q,n,zc,norm,p)
    !
    ! plane couette profile normalized by the wall velocity difference
    !
    implicit none
    real(8), intent(in)   :: q
    integer, intent(in)   :: n
    real(8), intent(in), dimension(0:) :: zc
    real(8), intent(in)   :: norm
    real(8), intent(out), dimension(n) :: p
    integer :: k
    real(8) :: z
    do k=1,n
      z    = zc(k)!1.d0*((k-1)+q)/(1.d0*n)
      p(k) = .5d0*(1.d0-2.d0*z)/norm
    enddo
    return
  end subroutine couette
  !
  subroutine poiseuille(q,n,zc,norm,p)
    implicit none
    real(8), intent(in)   :: q
    integer, intent(in)   :: n
    real(8), intent(in), dimension(0:) :: zc
    real(8), intent(in)   :: norm
    real(8), intent(out), dimension(n) :: p
    integer :: k
    real(8) :: z
    !
    ! plane poiseuille profile normalized by the bulk velocity
    !
    do k=1,n
      z    = zc(k)!1.d0*((k-1)+q)/(1.d0*n)
      p(k) = 6.d0*z*(1.d0-z)/norm
    enddo
    return
  end subroutine poiseuille
  !
  subroutine log_profile(q,n,zc,visc,p)
    implicit none
    real(8), intent(in)   :: q
    integer, intent(in)   :: n
    real(8), intent(in), dimension(0:) :: zc
    real(8), intent(in)   :: visc
    real(8), intent(out), dimension(n) :: p
    integer :: k
    real(8) :: z,reb,retau ! z/lz and bulk Reynolds number
    reb = rey
    retau = 0.09*reb**(0.88) ! from Pope's book
    do k=1,n/2
      z    = zc(k)*2.*retau!1.d0*((k-1)+q)/(1.d0*n)*2.*retau
      p(k) = 2.5d0*log(z) + 5.5d0
      if (z.le.11.6d0) p(k)=z
      p(n+1-k) = p(k)
    enddo
    return
  end subroutine log_profile
end module mod_initflow
