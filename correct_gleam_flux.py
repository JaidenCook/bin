#!/usr/bin/env python

# Script to correct the flux scale of a snapshot image by cross-matching sources detected in the image with the GLEAM IDR6 catalogue
# Inputs are:
# (1) Snapshot image
# (2) Source catalogue for the snapshot image

import os
import sys
import glob
import shutil
import numpy as np
from astropy.io import fits
from astropy.io.votable import parse_single_table
import re
import matplotlib as mpl
mpl.use('Agg') # So does not use display
import matplotlib.pylab as plt
from optparse import OptionParser

# topcat kluge:
stilts='java -jar /group/mwa/software/stilts/stilts.jar'


# Enter input parameters
usage="Usage: %prog [options]\n"
parser = OptionParser(usage=usage)
parser.add_option('-i','--input_image',dest="INPUT_IMAGE",default=None,help="Snapshot image to which correction is to be applied")
parser.add_option('-c','--input_catalogue',dest="INPUT_CATALOGUE",default=None,help="Source catalogue for the snapshot image in votable format")
parser.add_option('-r','--input_ref_catalogue',dest="INPUT_REF_CATALOGUE",default=None,help="Reference catalogue in fits format")
(options, args) = parser.parse_args()
input_catalogue = options.INPUT_CATALOGUE
input_ref_catalogue = options.INPUT_REF_CATALOGUE
input_image = options.INPUT_IMAGE

# Check input source catalogue exists
if not os.path.exists(input_catalogue):
  print "Missing "+input_catalogue
  sys.exit(1)

# Check input image exists
if not os.path.exists(input_image):
  print "Missing "+input_image
  sys.exit(1)

# Check reference catalogue exists
if not os.path.exists(input_ref_catalogue):
  print "Can't find "+input_ref_catalogue+"!"
  sys.exit(1)

# Define output file with flux correction
corrfile=input_image.replace(".fits","_flux_corrections.txt")
f=open(corrfile,"w")
corrplot=input_image.replace(".fits","_fluxcorr_vs_flux.pdf")
corrplot2=input_image.replace(".fits","_fluxcorr_vs_ra.pdf")
corrplot3=input_image.replace(".fits","_fluxcorr_vs_dec.pdf")

# Get frequency from image header
try:
  freq = fits.getheader(input_image)['CRVAL3']
except:
  freq = fits.getheader(input_image)['FREQ']

print 'freq =',freq
freq_str = "%03.0f" % (freq/1e6)

# Cross-match input source catalogue with GLEAM IDR6 catalogue
matchvot=input_image.replace(".fits","_match.vot")
ratio=1.0 # this is the flux correction factor; initialise to 1.0
#if not os.path.exists(matchvot):
print "matching"
os.system(stilts+' tmatch2 matcher=skyellipse params=30 in1='+input_ref_catalogue+' in2='+input_catalogue+' out=temp.vot values1="RAJ2000 DEJ2000 e_RAJ2000 e_DEJ2000 pawide" values2="ra dec a b pa" ofmt=votable')
print "downselecting"
# Extrapolate fitted GLEAM 200 MHz flux, Fintfit200, to frequency of snapshot assuming GLEAM spectral index, alpha
os.system(stilts+' tpipe in=temp.vot cmd=\'addcol S_'+freq_str+' "Fintfit200*pow(('+str(freq)+'/200000000.0),alpha)"\' out=temp1.vot')
# Exclude sources that are poorly fit by a power-law
os.system(stilts+' tpipe in=temp1.vot cmd=\'select !NULL_alpha\' out=temp2.vot')    
# Exclude sources with high local rms noise, extended sources and calculate log(ratio of MWA snapshot integrated flux to extrapolated GLEAM integrated flux). Also set weight to SNR in snapshot image.
os.system(stilts+' tpipe in=temp2.vot cmd=\'select (local_rms<1.0)\' cmd=\'select ((int_flux/peak_flux)<2)\' cmd=\'addcol ratio "(S_'+freq_str+'/int_flux)"\' cmd=\'addcol logratio "(ln(ratio))"\' cmd=\'addcol weight "(int_flux/local_rms)"\' cmd=\'addcol delRA "(RAJ2000-ra)"\' cmd=\'addcol delDec "(DEJ2000-dec)"\' omode=out ofmt=vot out=temp3.vot')
# Exclude sources that have abs(delRA)>=1.0
os.system(stilts+' tpipe in=temp3.vot cmd=\'select abs(delRA)<1.0\' out='+matchvot)
# Plot S_gleam/S_snapshot over S_gleam
os.system(stilts+' plot2plane layer_1=mark xlabel=\'S_gleam (Jy)\' ylabel=\'S_gleam / S_snapshot\' in_1='+matchvot+' x_1=S_'+freq_str+' y_1=ratio xlog=true out='+corrplot)
# Plot S_gleam/S_snapshot over RA_GLEAM
os.system(stilts+' plot2plane layer_1=mark xlabel=\'RA_gleam (deg)\' ylabel=\'S_gleam / S_snapshot\' in_1='+matchvot+' x_1=RAJ2000 y_1=ratio out='+corrplot2)
# Plot S_gleam/S_snapshot over Dec_GLEAM
os.system(stilts+' plot2plane layer_1=mark xlabel=\'Dec_gleam (deg)\' ylabel=\'S_gleam / S_snapshot\' in_1='+matchvot+' x_1=DEJ2000 y_1=ratio out='+corrplot3)

os.remove('temp.vot')
os.remove('temp1.vot')
os.remove('temp2.vot')
os.remove('temp3.vot')

# Check the matched table actually has entries
t = parse_single_table(matchvot)
print >> f, '# image  ratio  stdev'
if t.array.shape[0]>0:
# Now calculate the correction factors for the I, XX and YY snapshots
  t = parse_single_table(matchvot)
  ratio=np.exp(np.average(a=t.array['logratio'],weights=(t.array['weight']))) #*(distfunc)))
  stdev=np.std(a=t.array['logratio'])
  print "Ratio of "+str(ratio)+" between "+input_image+" and GLEAM."
  print "stdev= "+str(stdev)
# Apply flux correction to image
  hdu_in = fits.open(input_image)
# Modify to fix flux scaling
  hdu_in[0].data *= ratio
  output_image=input_image.replace(".fits","_fluxscaled.fits")
  hdu_in.writeto(output_image,clobber=True)
  f.write("{0:s} {1:10.8f} {2:10.8f}\n".format(input_image,ratio,stdev))
else:
  print input_image+" had no valid matches!"
f.close()
