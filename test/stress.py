#!/usr/bin/env python
import time
import sys

# ABOUT:
# Simple python script to stress CPU for [time] seconds.

timeout = 10.00 # sec

# Parse shell arguments
next = 1
while ( next < len(sys.argv) ):
    # Print short help message
    if ( sys.argv[next] == "-h" or sys.argv[next] == "--help" ):
        print( 'stress.py <time>' )
        print( '  Stress CPU for <time> seconds.' )
        exit( 0 )
    # Read time
    else:
        try:
            timeout = float( sys.argv[next] )
        except ValueError:
            print( 'ERROR - Bad value:', sys.argv[next] )
            exit( 1 )
    # Next argument
    next+=1

print( 'Doing work for', timeout, 'sec ...' )

# Dummy arithmetic loop
sum = 0.000
start = time.time()
while (1):
    sum+=1.000
    # Exit after [time] seconds
    if ( (time.time()-start) > timeout ):
        break
