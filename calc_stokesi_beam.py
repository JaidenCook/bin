#!/usr/bin/env python

# Calculate Stokes I beam from Stokes XX & YY beams
# I = (XX + YY)/2

import sys
import os
from astropy.io import fits
from optparse import OptionParser

# Read input parameters
beam_xx=str(raw_input('Input Stokes XX beam?'))
beam_yy=str(raw_input('Input Stokes YY beam?'))
beam_i=str(raw_input('Output Stokes I beam?'))

# Open Stokes XX && YY beams
beam1=fits.open(beam_xx)
beam2=fits.open(beam_yy)

# Calculate Stokes I beam
beam1[0].data+=beam2[0].data
beam1[0].data=beam1[0].data/2.0

# Write beam to file
beam1.writeto(beam_i,clobber=True)

