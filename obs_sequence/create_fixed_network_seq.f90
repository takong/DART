! DART software - Copyright 2004 - 2011 UCAR. This open source software is
! provided by UCAR, "as is", without charge, subject to all terms of use at
! http://www.image.ucar.edu/DAReS/DART/DART_download

program create_fixed_network_seq

! <next few lines under version control, do not edit>
! $URL: https://proxy.subversion.ucar.edu/DAReS/DART/releases/Kodiak/obs_sequence/create_fixed_network_seq.f90 $
! $Id: create_fixed_network_seq.f90 4933 2011-06-01 17:55:44Z thoar $
! $Revision: 4933 $
! $Date: 2011-06-01 12:55:44 -0500 (Wed, 01 Jun 2011) $

use        types_mod, only : r8
use    utilities_mod, only : timestamp, register_module, open_file, close_file, &
                             initialize_utilities
use      obs_def_mod, only : obs_def_type, get_obs_def_time, set_obs_def_time
use obs_sequence_mod, only : obs_sequence_type, obs_type, read_obs_seq, &
                             get_num_obs, init_obs_sequence, get_first_obs, &
                             write_obs_seq, set_copy_meta_data, get_obs_def, &
                             set_obs_def, append_obs_to_seq, get_next_obs, &
                             insert_obs_in_seq, init_obs, assignment(=), &
                             static_init_obs_sequence, get_num_copies, get_num_qc, &
                             get_copy_meta_data, get_qc_meta_data, set_qc_meta_data
use time_manager_mod, only : time_type, set_time, interactive_time, &
                             operator(*), operator(+)
use        model_mod, only : static_init_model

implicit none

! version controlled file description for error handling, do not edit
character(len=128), parameter :: &
   source   = "$URL: https://proxy.subversion.ucar.edu/DAReS/DART/releases/Kodiak/obs_sequence/create_fixed_network_seq.f90 $", &
   revision = "$Revision: 4933 $", &
   revdate  = "$Date: 2011-06-01 12:55:44 -0500 (Wed, 01 Jun 2011) $"


type(obs_sequence_type) :: seq, seq_in
type(obs_type)          :: obs, next_obs, new_obs
type(obs_def_type)      :: obs_def
character(len = 129)    :: file_name
logical                 :: is_there_one, is_this_last
type(time_type)         :: ob_time, init_time, this_time, period
integer                 :: seconds, days, i, j, network_size, option, num_times, num_copies, num_qc

! Record the current time, date, etc. to the logfile
call initialize_utilities('Create_fixed_network_seq')
call register_module(source,revision,revdate)

! Call the underlying model's static initialization for calendar info
call static_init_model()

! Initialize the obs_sequence module
call static_init_obs_sequence

! Write the sequence to a file
write(*, *) 'Input filename for network definition sequence (usually  set_def.out  )'
read(*, *) file_name
call read_obs_seq(file_name, 0, 0, 0, seq_in)

! Find out how many obs there are
network_size = get_num_obs(seq_in)

! Initialize the obs_type variables
num_copies = get_num_copies(seq_in)
num_qc     = get_num_qc(seq_in)
call init_obs(     obs, num_copies, num_qc)
call init_obs(next_obs, num_copies, num_qc)
call init_obs( new_obs, num_copies, num_qc)

! Get the time information 

20 write(*, *) 'To input a regularly repeating time sequence enter 1'
write(*, *) 'To enter an irregular list of times enter 2'
read(*, *) option

! Should also allow both regular and irregular for same set,
! but too much work for now

if(option == 1) then

   write(*, *) 'Input number of observation times in sequence'
   read(*, *) num_times

   write(*, *) 'Input initial time in sequence'
   call interactive_time(init_time)

   write(*, *) 'Input period of obs in sequence in days and seconds'
   read(*, *) days, seconds
   period = set_time(seconds, days)

! Initialize the output sequence
   call init_obs_sequence(seq, num_copies, &
      num_qc, network_size * num_times)
! Get the metadata (might want a call in obs_sequence to do this)
   do i = 1, num_copies
      call set_copy_meta_data(seq, i, get_copy_meta_data(seq_in, i))
   end do
   do i = 1, num_qc
      call set_qc_meta_data(seq, i, get_qc_meta_data(seq_in, i))
   end do

   do j = 1, num_times
      write(*, *) j
      ob_time = init_time + (j - 1) * period

      is_there_one = get_first_obs(seq_in, obs)

      do i = 1, network_size
         new_obs = obs
! Set the time
         call get_obs_def(new_obs, obs_def)
         call set_obs_def_time(obs_def, ob_time) 
         call set_obs_def(new_obs, obs_def)
! Append it to the sequence
         call append_obs_to_seq(seq, new_obs)
! Find the next observation in the input set
         call get_next_obs(seq_in, obs, next_obs, is_this_last)
         if(.not. is_this_last) obs = next_obs
      end do

   enddo

!-------------------------------------------------------------------------

else if(option == 2) then

   ! The irregular input section does minimal error checking.
   ! non-monotonic input times will cause an error in add_obs_set().
   write(*, *) 'Input an upper bound on the number of observation times'
   read(*, *) num_times

   ! Initialize the output sequence
   call init_obs_sequence(seq, num_copies, num_qc, network_size * num_times)

   ! Get the metadata (might want a call in obs_sequence to do this)
   do i = 1, num_copies
      call set_copy_meta_data(seq, i, get_copy_meta_data(seq_in, i))
   end do
   do i = 1, num_qc
      call set_qc_meta_data(seq, i, get_qc_meta_data(seq_in, i))
   end do

   IRREGULAR : do j = 1, num_times

! TJH this block does not provide for an 'early exit' ... interactive_time
!     would need an optional output argument for status ... maybe later.
!     write(*, *) 'Input this time time redundant message'
!     call interactive_time(this_time)

! TJH this block is annoying, because create_obs_sequence and the 'regular-
!     in-time' block use YYYY MM DD HH MM SS if calendar is Gregorian.

      write(*, *) 'Input time in days and seconds, negative days if finished with this set'
      read(*, *) days, seconds

      if ( days < 0 ) exit IRREGULAR         ! Done with this set.

      this_time = set_time(seconds, days)    ! Set the time

      ! Input this on a long list for later sorting
      ! (fixed storage for now should be changed)

      ob_time = this_time

      ! Put all the observations in the output sequence with this time      

      is_there_one = get_first_obs(seq_in, obs)
      
      do i = 1, network_size

         new_obs = obs

         call get_obs_def(new_obs, obs_def)
         call set_obs_def_time(obs_def, ob_time) 
         call set_obs_def(new_obs, obs_def)
         call insert_obs_in_seq(seq, new_obs)

         call get_next_obs(seq_in, obs, next_obs, is_this_last)
         if(.not. is_this_last) obs = next_obs

      end do

   enddo IRREGULAR

else
   write(*, *) 'option must be 1 or 2, try again'
   goto 20
endif

write(*, *) 'What is output file name for sequence (  obs_seq.in   is recommended )'
read(*, *) file_name
call write_obs_seq(seq, file_name)

! Clean up
call timestamp(string1=source,string2=revision,string3=revdate,pos='end')

end program create_fixed_network_seq
