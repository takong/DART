! DART software - Copyright 2004 - 2011 UCAR. This open source software is
! provided by UCAR, "as is", without charge, subject to all terms of use at
! http://www.image.ucar.edu/DAReS/DART/DART_download

program convert_madis_satwnd

! <next few lines under version control, do not edit>
! $URL: https://proxy.subversion.ucar.edu/DAReS/DART/releases/Kodiak/observations/MADIS/convert_madis_satwnd.f90 $
! $Id: convert_madis_satwnd.f90 4925 2011-05-31 17:39:55Z nancy $
! $Revision: 4925 $
! $Date: 2011-05-31 12:39:55 -0500 (Tue, 31 May 2011) $

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!   convert_madis_satwnd - program that reads a MADIS netCDF satellite
!                          wind observation file and writes a DART
!                          obs_seq file using the DART library routines.
!                          This version works on the standard METAR files.
!
!     created Dec. 2007 Ryan Torn, NCAR/MMM
!     modified Dec. 2008 Soyoung Ha and David Dowell, NCAR/MMM
!     - added dewpoint as an output variable
!     - added relative humidity as an output variable
!
!     modified to include QC_flag check (Soyoung Ha, NCAR/MMM, 08-04-2009)
!     split from the mesonet version (Glen Romine, NCAR/MMM, Feb 2010)
!
!     modified to use a common set of utilities, better netcdf error checks,
!     able to insert obs with any time correctly (not only monotonically
!     increasing times)    nancy collins,  ncar/image   11 march 2010
!     
!     keep original obs times, make source for all converters as similar
!     as possbile.   nancy collins,  ncar/image   26 march 2010
!
!     adapted May 2011, nancy collins, ncar/image
!     - split from the metar version
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

use         types_mod, only : r8, missing_r8
use     utilities_mod, only : nc_check, initialize_utilities, finalize_utilities
use  time_manager_mod, only : time_type, set_calendar_type, set_date, &
                              increment_time, get_time, operator(-), GREGORIAN
use      location_mod, only : VERTISPRESSURE
use  obs_sequence_mod, only : obs_sequence_type, obs_type, read_obs_seq, &
                              static_init_obs_sequence, init_obs, write_obs_seq, & 
                              init_obs_sequence, get_num_obs, & 
                              set_copy_meta_data, set_qc_meta_data
use        meteor_mod, only : wind_dirspd_to_uv
use       obs_err_mod, only : sat_wind_error, sat_wv_wind_error
use      obs_kind_mod, only : SAT_U_WIND_COMPONENT, SAT_V_WIND_COMPONENT
use obs_utilities_mod, only : getvar_real, get_or_fill_QC, add_obs_to_seq, &
                              create_3d_obs, getvar_int, getdimlen

use           netcdf

implicit none

character(len=16),  parameter :: satwnd_netcdf_file = 'satwnd_input.nc'
character(len=129), parameter :: satwnd_out_file    = 'obs_seq.satwnd'
logical,            parameter :: exclude_special     = .true.

logical, parameter :: use_input_qc              = .true. 

integer, parameter :: num_copies = 1,   &   ! number of copies in sequence
                      num_qc     = 1        ! number of QC entries


logical :: iruse, visuse, wvuse, swiruse, allbands

character (len=5)   :: rtype
integer  :: ncid, nobs, n, i, oday, osec, nused
logical  :: file_exist, first_obs
real(r8) :: wdir_miss, wspd_miss
integer  :: band_miss

! FIXME:from ssec version
!logical :: iruse, visuse, wvuse, swiruse, file_exist, qifile, eefile, &
!           userfqc, useqiqc, useeeqc

integer :: iyear, imonth, iday, ihour, imin, isec, qctype
real(r8) :: uwnd, vwnd, oerr, &
            qc, qcthresh, rfqc, qiqc, eeqc
! end FIXME


real(r8), allocatable :: lat(:), lon(:), latu(:), lonu(:), &
                          pres(:), prsu(:), tobs(:), tobu(:), &
                          wdir(:), wspd(:)
integer,  allocatable :: band(:), bndu(:)
integer,  allocatable :: qc_wdir(:), qc_wspd(:)

type(obs_sequence_type) :: obs_seq
type(obs_type)          :: obs, prev_obs
type(time_type)         :: comp_day0, time_obs, prev_time


!------------
! start of executable code
!------------

call initialize_utilities('convert_madis_satwnd')

! band selections
print*,'Do you want to include IR, VISIBLE, and WV data? (T/F, 3 times)'
read*, iruse, visuse, wvuse

! set a flag to tell us if we are going to select by band or accept all
if (.not. iruse  .or.  .not. visuse  .or.  .not. wvuse) then
   allbands = .false.
else
   allbands = .true.
endif

! put the reference date into DART format
call set_calendar_type(GREGORIAN)
comp_day0 = set_date(1970, 1, 1, 0, 0, 0)

first_obs = .true.


call nc_check( nf90_open(satwnd_netcdf_file, nf90_nowrite, ncid), &
               'convert_madis_satwnd', 'opening file '//trim(satwnd_netcdf_file))

call getdimlen(ncid, "recNum", nobs)

allocate( lat(nobs))  ;  allocate( lon(nobs))
allocate(latu(nobs))  ;  allocate(lonu(nobs))
allocate(pres(nobs))  ;  allocate(prsu(nobs))
allocate(tobs(nobs))  ;  allocate(tobu(nobs))
allocate(band(nobs))  ;  allocate(bndu(nobs))
allocate(wdir(nobs))  ;  allocate(wspd(nobs))
allocate(qc_wdir(nobs)) ;  allocate(qc_wspd(nobs))

! read in the data arrays
call getvar_real(ncid, "obLat",       lat            ) ! latitude
call getvar_real(ncid, "obLon",       lon            ) ! longitude
call getvar_real(ncid, "pressure",    pres           ) ! pressure
call getvar_real(ncid, "windDir",     wdir, wdir_miss) ! wind direction
call getvar_real(ncid, "windSpd",     wspd, wspd_miss) ! wind speed
call getvar_real(ncid, "validTime",   tobs           ) ! observation time
call getvar_int (ncid, "satelliteWindMethod", band, band_miss) ! band

! if user says to use them, read in QCs if present
if (use_input_qc) then
   call getvar_int(ncid, "windDirQCR",   qc_wdir ) ! wind direction qc
   call getvar_int(ncid, "windSpdQCR",   qc_wspd ) ! wind speed qc
else
   qc_wdir = 0 ;  qc_wspd = 0
endif

!  either read existing obs_seq or create a new one
call static_init_obs_sequence()
call init_obs(obs,      num_copies, num_qc)
call init_obs(prev_obs, num_copies, num_qc)

inquire(file=satwnd_out_file, exist=file_exist)

if ( file_exist ) then

  ! existing file found, append to it
  call read_obs_seq(satwnd_out_file, 0, 0, 2*nobs, obs_seq)

else

  ! create a new one
  call init_obs_sequence(obs_seq, num_copies, num_qc, 2*nobs)
  do i = 1, num_copies
    call set_copy_meta_data(obs_seq, i, 'MADIS observation')
  end do
  do i = 1, num_qc
    call set_qc_meta_data(obs_seq, i, 'Data QC')
  end do

endif

! Set the DART data quality control.  Be consistent with NCEP codes;
! 0 is 'must use', 1 is good, no reason not to use it.
qc = 1.0_r8

nused = 0
obsloop: do n = 1, nobs

  ! compute time of observation
  time_obs = increment_time(comp_day0, nint(tobs(n)))

  ! check the lat/lon values to see if they are ok
  if ( lat(n) >  90.0_r8 .or. lat(n) <  -90.0_r8 ) cycle obsloop
  if ( lon(n) > 180.0_r8 .or. lon(n) < -180.0_r8 ) cycle obsloop

  if ( lon(n) < 0.0_r8 )  lon(n) = lon(n) + 360.0_r8

  ! Check for duplicate observations
  do i = 1, nused
    if ( lon(n) == lonu(i) .and. &
         lat(n) == latu(i) .and. &
        prsu(n) == pres(i) .and. &
        band(n) == bndu(i) .and. &
        tobs(n) == tobu(i) ) cycle obsloop
  end do

  ! if selecting only certain bands, cycle if not wanted
  if (.not. allbands) then
     if (.not. iruse  .and. band(n) == 1) cycle obsloop
     if (.not. visuse .and. band(n) == 2) cycle obsloop
     if (.not. wvuse  .and. &
         (band(n) == 3  .or.  band(n) == 5  .or. band(n) == 7)) cycle obsloop
  endif

  ! extract actual time of observation in file into oday, osec.
  call get_time(time_obs, osec, oday)

  ! add wind component data to obs_seq
  if ( wdir(n) /= wdir_miss .and. qc_wdir(n) == 0 .and. &
       wspd(n) /= wspd_miss .and. qc_wspd(n) == 0 ) then

    call wind_dirspd_to_uv(wdir(n), wspd(n), uwnd, vwnd)
    oerr = sat_wind_error(pres(n)/100.0_r8)  ! comes in as pascals already

   !  perform sanity checks on observation errors and values
   if ( oerr == missing_r8 .or. wdir(n) < 0.0_r8 .or. wdir(n) > 360.0_r8 .or. &
      wspd(n) < 0.0_r8 .or. wspd(n) > 120.0_r8 )  cycle obsloop

      call create_3d_obs(lat(n), lon(n), pres(n), VERTISPRESSURE, uwnd, &
                         SAT_U_WIND_COMPONENT, oerr, oday, osec, qc, obs)
      call add_obs_to_seq(obs_seq, obs, time_obs, prev_obs, prev_time, first_obs)

      call create_3d_obs(lat(n), lon(n), pres(n), VERTISPRESSURE, vwnd, &
                         SAT_V_WIND_COMPONENT, oerr, oday, osec, qc, obs)
      call add_obs_to_seq(obs_seq, obs, time_obs, prev_obs, prev_time, first_obs)

  endif

  nused = nused + 1
  latu(nused) =  lat(n)
  lonu(nused) =  lon(n)
  prsu(nused) = pres(n)
  band(nused) = bndu(n)
  tobu(nused) = tobs(n)

end do obsloop

! need to wait to close file because in the loop it queries the
! report types.
call nc_check( nf90_close(ncid) , &
               'convert_madis_satwnd', 'closing file '//trim(satwnd_netcdf_file))

! if we added any obs to the sequence, write it now.
if ( get_num_obs(obs_seq) > 0 )  call write_obs_seq(obs_seq, satwnd_out_file)

! end of main program
call finalize_utilities()

end program
