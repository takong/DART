#!/bin/csh
#
# DART software - Copyright 2004 - 2011 UCAR. This open source software is
# provided by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
# DART $Id: testall.csh 4918 2011-05-25 22:57:43Z thoar $

# this script runs the location test code for each of the
# possible location modules.

set LIST = 'annulus column oned threed_sphere twod twod_sphere'

# clean up from before
foreach i ( $LIST )
 # do not cd so as to not accidently remove files in the
 # wrong place if the cd fails.
 rm -f $i/test/*.o $i/test/*.mod $i/test/input.nml*_default $i/test/dart_log.*
 rm -f $i/test/Makefile $i/test/location_test_file* $i/test/location_test
end

# and now build afresh and run tests
foreach i ( $LIST )
 cd $i/test
 echo ""
 echo start $i test
 echo start $i test
 echo start $i test
 mkmf_location_test
 make
 ls -l location_test
 ./location_test  < test.in
 cd ../..
 echo end $i test
 echo end $i test
 echo end $i test
 echo ""
end
