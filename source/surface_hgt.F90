!|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||

 module surface_hgt

!BOP
! !MODULE: surface_hgt
!
! !DESCRIPTION:
!  Contains routine for computing change in surface height.
!
! !REVISION HISTORY:
!  SVN:$Id: surface_hgt.F90 14564 2009-02-26 21:37:49Z njn01 $

! !USES:

   use POP_KindsMod
   use POP_ErrorMod

   use POP_DomainSizeMod, only : POP_maxBlocksClinic

   use blocks, only: nx_block, ny_block, block, get_block
   use domain, only: nblocks_clinic, blocks_clinic
   use constants, only: grav, c0
   use prognostic, only: PSURF, GRADPX, GRADPY, newtime,  &
       curtime, oldtime
   use forcing_fields, only: FW, FW_OLD
   use grid, only: sfc_layer_type, sfc_layer_varthick, sfc_layer_rigid,      &
       sfc_layer_oldfree, CALCU, tgrid_to_ugrid
   use time_management, only: mix_pass, dtp
   use tavg, only: define_tavg_field, tavg_requested, accumulate_tavg_field
   use movie, only: define_movie_field, movie_requested, update_movie_field

   implicit none
   private
   save

! !PUBLIC MEMBER FUNCTIONS:

   public :: init_surface_hgt, &
             dhdt

!EOP
!BOC
!-----------------------------------------------------------------------
!
!  tavg ids for surface height diagnostics
!
!-----------------------------------------------------------------------

   integer (POP_i4) :: &
      tavg_SSH,          &! tavg id for sea surface height
      tavg_H2,           &! tavg id for sea surface height squared
      tavg_H3             ! tavg id for (Dx(SSH))**2 + (Dy(SSH))**2

!-----------------------------------------------------------------------
!
!  movie ids for surface height diagnostics
!
!-----------------------------------------------------------------------

   integer (POP_i4) :: &
      movie_SSH            ! movie id for sea surface height

!EOC
!***********************************************************************

 contains

!***********************************************************************
!BOP
! !IROUTINE: init_surface_hgt
! !INTERFACE:

 subroutine init_surface_hgt(errorCode)

! !DESCRIPTION:
!  Initialized quantities related to SSH, namely some tavg diagnostic
!  ids.
!
! !REVISION HISTORY:
!  same as module

! !OUTPUT PARAMETERS:

   integer (POP_i4), intent(out) :: &
      errorCode       ! returned error code

!EOP
!BOC
!-----------------------------------------------------------------------
!
!  define tavg diagnostic fields
!
!-----------------------------------------------------------------------

   errorCode = POP_Success

   call define_tavg_field(tavg_SSH,'SSH',2,                            &
                          long_name='Sea Surface Height',              &
                          units='centimeter', grid_loc='2110')

   call define_tavg_field(tavg_H2,'H2',2,                              &
                          long_name='SSH**2',                          &
                          units='cm^2', grid_loc='2110')

   call define_tavg_field(tavg_H3,'H3',2,                              &
                          long_name='(Dx(SSH))**2 + (Dy(SSH))**2',     &
                          units='----', grid_loc='2110')

!-----------------------------------------------------------------------
!
!  define movie diagnostic fields
!
!-----------------------------------------------------------------------

   call define_movie_field(movie_SSH,'SSH',0,                          &
                          long_name='Sea Surface Height',              &
                          units='cm', grid_loc='2110')

!-----------------------------------------------------------------------
!EOC

 end subroutine init_surface_hgt

!***********************************************************************
!BOP
! !IROUTINE: dhdt
! !INTERFACE:

 subroutine dhdt(DH,DHU, errorCode)

! !DESCRIPTION:
!  This routine calculates the change in surface height 
!  $d\eta/dt$ from surface pressure and including freshwater 
!  flux for a variable-thickness surface layer 
!  $(d\eta/dt - F_W)$.
!
!  The surface pressure contribution at T points is
!  \begin{equation}  
!    {{d\eta}\over{dt}} = {{(p^n - p^{n-1})}\over{g\Delta t}}.
!  \end{equation}  
!  At U points, the change in surface height is the area-weighted 
!  average of its value at surrounding T points.
!
!  In the advection routines, the vertical velocity $w = w_t,w_u$ in 
!  T,U columns is determined by integrating the continuity equation 
!  $L(1) = 0$ from the surface down to level k.  Depending on surface 
!  layer type, the integration starts with:
!  \begin{equation}\begin{array}{llll}
!     w &=& 0               &{\rm (rigid\ lid)}       \\
!     w &=& d\eta/dt        &{\rm (old\ free\ surface)}\\
!     w &=& d\eta/dt - F_W  &{\rm (variable\ thickness\ surface\ layer)}
!  \end{array}\end{equation}
!
!  At the surface, the time change of the surface height
!  in T columns satisfies the barotropic continuity equation:
!  \begin{equation}
!     d\eta/dt + \nabla\cdot(H{\bf U}) = 0,
!  \end{equation}
!  where ${\bf U} = (U,V)$ is the barotropic velocity.
!
!  On the second pass of a matsuno timestep, the predicted pressure
!  from the 1st pass is contained in array PSURF(:,:,newtime) 
!  (PSURF(:,:,curtime) is not updated until the end of the matsuno 
!  step).
!
!  Note that DH, DHU represents $d\eta/dt - F_W$ at 
!  T, U points in variable thickness surface layer
!
! !REVISION HISTORY:
!  same as module

! !OUTPUT PARAMETERS:

   real (POP_r8), dimension(nx_block,ny_block,POP_maxBlocksClinic), &
      intent(out) :: &
      DH, DHU        ! change in surface height (-Fw) at T,U points

   integer (POP_i4), intent(out) :: &
      errorCode       ! returned error code

!EOP
!BOC
!-----------------------------------------------------------------------
!
!  local variables
!
!-----------------------------------------------------------------------

   integer (POP_i4) :: & 
      iblock             ! block index

   type (block) ::       &
      this_block         ! block information for current block

   real (POP_r8), dimension(nx_block,ny_block) :: &
      WORK                ! temporary work space

!  real (POP_r8), dimension(nx_block,ny_block) :: WORKX,WORKY
!  real (POP_r8) :: div_error, div_mag, dh_dt,dfw,dhtot

!-----------------------------------------------------------------------
!
!  calculate dh/dt or dh/dt - Fw at T points
!
!-----------------------------------------------------------------------

   errorCode = POP_Success

   !$OMP PARALLEL DO PRIVATE(iblock, this_block, WORK)

   do iblock = 1,nblocks_clinic
      this_block = get_block(blocks_clinic(iblock),iblock)  

      select case (sfc_layer_type)

      case (sfc_layer_varthick)
         if (mix_pass == 2) then
            DH(:,:,iblock) = (PSURF(:,:,newtime,iblock) - &
                              PSURF(:,:,curtime,iblock))/(grav*dtp) - &
                              FW(:,:,iblock)
         else
            DH(:,:,iblock) = (PSURF(:,:,curtime,iblock) - &
                              PSURF(:,:,oldtime,iblock))/(grav*dtp) - &
                              FW_OLD(:,:,iblock)
         endif

      case (sfc_layer_rigid)
         DH(:,:,iblock) = c0

      case (sfc_layer_oldfree)
         if (mix_pass == 2) then
            DH(:,:,iblock) = (PSURF(:,:,newtime,iblock) - &
                              PSURF(:,:,curtime,iblock))/(grav*dtp)
         else
            DH(:,:,iblock) = (PSURF(:,:,curtime,iblock) - &
                              PSURF(:,:,oldtime,iblock))/(grav*dtp)
         endif

      end select

!-----------------------------------------------------------------------
!
!     Some debugging diagnostics
!     ...check barotropic continuity equation:
!
!-----------------------------------------------------------------------
!
!     WORKX = HU(:,:,iblock)*UBTROP(:,:,curtime,iblock)
!     WORKY = HU(:,:,iblock)*VBTROP(:,:,curtime,iblock)
!     call div(1,WORK,WORKX,WORKY,this_block)
!     WORKX = (DH(:,:,iblock)*TAREA(:,:,iblock) + WORK)**2
!     WORKY = TAREA(:,:,iblock)**2
!     div_error = sqrt(global_sum(WORKX,distrb_clinic,field_loc_center,RCALCT)/&
!                      global_sum(WORKY,distrb_clinic,field_loc_center,RCALCT))
!     WORKX = (DH(:,:,iblock)*TAREA(:,:,iblock))**2
!     WORKY = TAREA(:,:,iblock)**2
!     div_mag=sqrt(global_sum(WORKX,distrb_clinic,field_loc_center,RCALCT)/&
!                  global_sum(WORKY,distrb_clinic,field_loc_center,RCALCT))
!     if (my_task == master_task) then
!        write(stdout,*) ' div error: ', div_error, div_mag
!     endif
!     WORK = -WORK/TAREA(:,:,iblock)
!
!     WORKX = TAREA(:,:,iblock)*(PSURF(:,:,curtime,iblock) - &
!                                PSURF(:,:,oldtime,iblock))/grav
!     WORKY = dtp*TAREA(:,:,iblock)*FW_OLD(:,:,iblock)
!     WORK  = TAREA(:,:,iblock)*PSURF(:,:,curtime,iblock)/grav
!     dh_dt  = global_sum(WORKX,distrb_clinic,field_loc_center,RCALCT)/area_t
!     dfw    = global_sum(WORKY,distrb_clinic,field_loc_center,RCALCT)/area_t
!     dhtot  = global_sum(WORK ,distrb_clinic,field_loc_center,RCALCT)/area_t
!     if (my_task == master_task) then
!        write(stdout,*) ' '
!        write(stdout,*) 'mean surface height           ', dhtot
!        write(stdout,*) 'mean change in surface height ', dh_dt
!        write(stdout,*) 'mean change from freshwater   ', dfw
!     endif
!
!-----------------------------------------------------------------------

!-----------------------------------------------------------------------
!
!     calculate dh/dt (or dh/dt - Fw) at U points as the area-weighted 
!     average of value at T points.
!
!-----------------------------------------------------------------------

      call tgrid_to_ugrid(DHU(:,:,iblock),DH(:,:,iblock), iblock)

      where (.not. CALCU(:,:,iblock)) DHU(:,:,iblock) = c0  ! zero on land

!-----------------------------------------------------------------------
!
!     accumulate surface height tavg diagnostics if requested
!
!-----------------------------------------------------------------------

      if (tavg_requested(tavg_SSH) .and. mix_pass /= 1) then
         WORK = PSURF(:,:,curtime,iblock)/grav
         call accumulate_tavg_field(WORK, tavg_SSH, iblock, 1)
      endif

      if (tavg_requested(tavg_H2) .and. mix_pass /= 1) then
         WORK = (PSURF(:,:,curtime,iblock)/grav)**2
         call accumulate_tavg_field(WORK, tavg_H2, iblock, 1)
      endif

      if (tavg_requested(tavg_H3) .and. mix_pass /= 1) then
         WORK = ((GRADPX(:,:,curtime,iblock)/grav)**2 +  &
                 (GRADPY(:,:,curtime,iblock)/grav)**2)
        call accumulate_tavg_field(WORK, tavg_H3, iblock, 1)
      endif

!-----------------------------------------------------------------------
!
!     accumulate surface height movie diagnostics if requested
!
!-----------------------------------------------------------------------

      if (movie_requested(movie_SSH) .and. mix_pass /= 1) then
         WORK = PSURF(:,:,curtime,iblock)/grav
         call update_movie_field(WORK, movie_SSH, iblock, 1)
      endif

   end do  ! block loop

   !$OMP END PARALLEL DO

!-----------------------------------------------------------------------

 end subroutine dhdt

!***********************************************************************

 end module surface_hgt

!|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
