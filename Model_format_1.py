#!/usr/bin/python

# Version 1 of the direct beam skymodel pipeline.

import os
import sys
import glob
import shutil
import re
import time
import numpy as np
from scipy.optimize import leastsq
from scipy.optimize import curve_fit

from astropy import wcs
from astropy.io import fits
from astropy.io.votable import parse_single_table
from astropy.table import Table,Column
from astropy.io.votable import writeto as writetoVO

from math import pi

#from mwa_pb import primarybeammap_tant as pbmap
from mwa_pb import primary_beam as pb

import matplotlib as mpl
#mpl.use('Agg') # So does not use display
import matplotlib.pylab as plt

def mwa_alt_az_za(obsid, ra=None, dec=None, degrees=False):
	"""
	Calculate the altitude, azumith and zenith for an obsid
	
	Args:
	obsid : The MWA observation id (GPS time)
	ra : The right acension in HH:MM:SS
	dec : The declintation in HH:MM:SS
	degrees: If true the ra and dec is given in degrees (Default:False)
	"""
	from astropy.time import Time
	from astropy.coordinates import SkyCoord, AltAz, EarthLocation
	from astropy import units as u
	
	obstime = Time(float(obsid),format='gps')
	
	if ra is None or dec is None:
	#if no ra and dec given use obsid ra and dec
		ra, dec = get_common_obs_metadata(obsid)[1:3]
	
	if degrees:
		sky_posn = SkyCoord(ra, dec, unit=(u.deg,u.deg))
	else:
		sky_posn = SkyCoord(ra, dec, unit=(u.hourangle,u.deg))
	earth_location = EarthLocation.of_site('Murchison Widefield Array')
	#earth_location = EarthLocation.from_geodetic(lon="116:40:14.93", lat="-26:42:11.95", height=377.8)
	altaz = sky_posn.transform_to(AltAz(obstime=obstime, location=earth_location))
	Alt = altaz.alt.deg
	Az = altaz.az.deg
	Za = 90. - Alt
	return Alt, Az, Za

# Timing the script duration.
start0 = time.time()

################################################################################
# Defining the parser and initialising input variables.
################################################################################
#"""

# Parser options:
from optparse import OptionParser

usage="Usage: %prog [options]\n"
parser = OptionParser(usage=usage)
parser.add_option('--obsid',dest="obsid",default=None,help="Input OBSID")
parser.add_option('--freq',dest="freq",default=None,help="Input frequency")
parser.add_option('--delays',dest="delays",default=None,help="Input delays")
parser.add_option('--catalogue',dest="catalogue",default=None,help="Input GLEAM catalogue to use")
parser.add_option('--ra',dest="ra_pnt",default=None,help="RA of pointing centre (deg)")
parser.add_option('--dec',dest="dec_pnt",default=None,help="Dec of pointing centre (deg)")
parser.add_option('--threshold',dest="threshold",default=None,help="Input threshold sigma scalar")

# Add option for primary beam model inputs -- make default a typical GLEAMY2 repository location
(options, args) = parser.parse_args()

# Loading in parameters from the metafits file:
# These will become parsed parameters.
metafits = "{0}.metafits".format(int(options.obsid))
hdus = fits.open(metafits)
meta_dat = hdus[0].header

# Reading inputs from the command line.
Tot_Sky_Mod = options.catalogue

# Reading in the delay string, converting to a list where each element is a float.
delays = options.delays
delays = delays[1:len(delays)-1].split(",")
delays_flt = [float(i) for i in delays]
print "Delays = {0}".format(delays_flt)

# Initialising other parameters.
obsid = float(options.obsid)
freq = (float(options.freq))*1e+6 #Central frequency
ra_pnt = float(options.ra_pnt)
dec_pnt = float(options.dec_pnt)
threshold = float(options.threshold)

if not os.path.exists(Tot_Sky_Mod):
   print "Can't find the total sky model catalogue."
   sys.exit(1)

freq_str = "%03.0f" % (freq/1e6)
print "Central frequency = {0} MHz".format(freq_str)

# Loading in the channels for a given observation.
chans = meta_dat['CHANNELS']
print "Channels = {0}\n".format(chans)
chans = chans[:len(chans)].split(",")
Nu = (np.array([float(i) for i in chans])*1.28)*1e+6 #Converting to hz

# Add columns with RA and Dec in sexagesimal format
os.system('stilts tpipe in='+Tot_Sky_Mod+' cmd=\'addcol ra_str "degreesToHms(RAJ2000,2)"\' cmd=\'addcol dec_str "degreesToDms(DEJ2000,2)"\' out=tmp.fits')

# Read in GLEAM IDR4
temp_table = fits.open('tmp.fits')[1].data

RA_samp = temp_table['RAJ2000']
DEC_samp = temp_table['DEJ2000']

#"""
################################################################################
# Thresholding all sources above the horizon, converting RA/DEC to Az/Alt
################################################################################
#"""

# Determining the Altitude, Azimuth and Zenith for each source in the total catalogue.
Alt0, Az0, Zen0 =  mwa_alt_az_za(obsid, RA_samp, DEC_samp, True)

Alt0_samp = Alt0[Alt0 > 0.0]
Az0_samp = np.radians(Az0[Alt0 > 0.0])
Zen0_samp = (pi/2) - np.radians(Alt0_samp)

# Trying to solve an indexing issue with mwa_pb.
Az0_samp = [Az0_samp]
Zen0_samp = [Zen0_samp]

print "Number of sources above the horizon:",len(Alt0_samp)

# Creating new sampled table.
Sky_Mod = temp_table[Alt0 > 0.0]

#start1 = time.time()

#"""
################################################################################
# Thresholding the apparent brightest 1500 sources in the OBSID
################################################################################
#"""

# Determining the beam power at the central frequency for each source above the horizon.
beam_power = pb.MWA_Tile_full_EE(Zen0_samp,Az0_samp,freq,delays_flt)

#end1 = time.time()

# Splitting the xx and yy cross correlation power components
beam_power_XX = np.array(beam_power[0])
beam_power_YY = np.array(beam_power[1])

# Determining the average power or stokes I power.
beamvalue = (beam_power_XX + beam_power_YY)/2

S300_fit = Sky_Mod.field("Fint300")
alpha = Sky_Mod.field("a")
q_curve = Sky_Mod.field("q")

# Next step is to calculate the S_central frequency:
#
# Determining the log-quadratic coefficients for each source:
C1 = np.log10(S300_fit)
C2 = alpha
C3 = q_curve

# Determining the flux density at the central frequency:
S_centralfreq = 10**(C1 + C2*(np.log10(freq/300e+6)) + C3*(np.log10(freq/300e+6))**2)

alpha = C2 + 2*C3*np.log10(freq/300e+6)

# Determining the apparent flux density for each source.
S_centralfreq_uncorrected = S_centralfreq*beamvalue[0,:]

#print 'len beamvalue = ', len(beamvalue[0,:]), 'shape of beamvalue = ',np.shape(beamvalue[0,:])
#print 'Max beamvalue = ',np.max(beamvalue),'| Max app flux = ', np.max(S_centralfreq_uncorrected)

# Hard coding in the threshold:
threshold = 0.0127 #Jy

# Thresh_indices = S_centralfreq_uncorrected >= 5*threshold
# This will make calibration go faster.
Thresh_indices = np.argsort(S_centralfreq_uncorrected)[len(S_centralfreq_uncorrected)-1500:]

#print 'Threshold = ', 5*threshold

#print 'len Thresh_ind = ',len(Thresh_indices), '\t','len S_cent = ', len(S_centralfreq)

# Subsetting by applying flux threshold cut:
S_centralfreq = S_centralfreq[Thresh_indices]
#S_centralfreq_uncorrected = S_centralfreq_uncorrected[Thresh_indices]
beamvalue = beamvalue[0,:][Thresh_indices]
S300_fit = S300_fit[Thresh_indices]
alpha = alpha[Thresh_indices]
q_curve = q_curve[Thresh_indices]

print "Number of sources after thresholding = # ", len(S_centralfreq_uncorrected)

# Loading in the other vectors:
name = Sky_Mod.field("Name")[Thresh_indices]
ra = Sky_Mod.field("RAJ2000")[Thresh_indices]
dec = Sky_Mod.field("DEJ2000")[Thresh_indices]
ra_str = Sky_Mod.field("ra_str")[Thresh_indices]
dec_str = Sky_Mod.field("dec_str")[Thresh_indices]
int_flux_wide = Sky_Mod.field("Fint300")[Thresh_indices]
a_wide = Sky_Mod.field("Major")[Thresh_indices]
b_wide = Sky_Mod.field("Minor")[Thresh_indices]
pa_wide = Sky_Mod.field("PA")[Thresh_indices]
peak_flux_wide = Sky_Mod.field("Fint300")[Thresh_indices]
flags = Sky_Mod.field("flag")[Thresh_indices]
os.remove('tmp.fits')

#"""
################################################################################
# Fitting the beam curvature
################################################################################
"""
In future versions of this code, Ihope to generalise this section to fit, nth
order polynomials, determined by some criteria.
"""
#"""

# Initialising the beam related arrays:
beamvalue_approx = np.zeros(len(name))
q_beam = np.zeros(len(name))
q_uncorrected = np.zeros(len(name))
alpha_beam = np.zeros(len(name))
alpha_uncorrected = np.zeros(len(name))

# Initialising beam_cube:
flat_beam_cube = np.empty([len(Nu),len(name)])

# Retrieving the Az and Zen angles for the top 1500 sources.

#print "##############################################"
#print "number of sources in Az0_samp = ",np.shape(np.array(Az0_samp)[0,:])
#print "##############################################"
#

Az0_samp = [np.array(Az0_samp)[0,:][Thresh_indices]]
Zen0_samp = [np.array(Zen0_samp)[0,:][Thresh_indices]]

#print "##############################################"
#print "number of sources in Az0_samp = ",np.shape(Az0_samp)
#print "##############################################"
#

for i in range(len(Nu)):
	print "Generating channel {0} beam".format(chans[i])
	temp_beam_power = pb.MWA_Tile_full_EE(Zen0_samp,Az0_samp,Nu[i],delays_flt)
	flat_beam_cube[i,:] = ((np.array(temp_beam_power[0]) + np.array(temp_beam_power[1]))/2.0).flatten()

print "Determining the beam spectral index and curvature"


################################################################################
#Creating Fringe table:
################################################################################
"""

cond = False

ra_ind = np.logical_and(ra >= 320, ra <= 340)
dec_ind = np.logical_and(dec >= -30, dec <= -10)
PB_ind = ra_ind*dec_ind

if cond == True:
	
	# Indexing is unfortunately weird due to mwa_pb version on Magnus.
	Source_list = [Zen0_samp[0][:],Az0_samp[0][:],ra,dec]
	#Source_list = [Zen0_samp[0][PB_ind],Az0_samp[0][PB_ind],ra[PB_ind],dec[PB_ind]]
	for k in range(len(chans)):
		Source_list.append(flat_beam_cube[k,:])
		#Source_list.append(flat_beam_cube[k,PB_ind])
	
	# Initialising column names:
	Source_col_names = ['Zen','theta','RA','DEC']
	
	# Creating a string of column names:
	Source_col_names = Source_col_names + chans
	
	print "Creating output high residual fringe table!"
	Source_Table = Table(Source_list,names=Source_col_names,meta={'name':'first table'})
	Source_Table.write("{0}_source_table.fits".format(int(options.obsid)),"w")
else:
	print "Output table is False"

"""
################################################################################
#Plotting residual maps
################################################################################
#"""

start = time.time()
for j in range(len(name)):

	# Polyfit is the fastest polynomial fitting implementation.
	C = np.polyfit(np.log10(Nu/freq),np.log10(flat_beam_cube[:,j]),2)
	
	# Polyfit returns the highest order coefficient first.
	q_beam[j] = C[0]
	alpha_beam[j] = C[1]
	beamvalue_approx[j] = 10**C[2]
	

end = time.time()
print "Beam log-quadratic coefficient fitting duration = ", np.round(end - start,3),"s\n"

# Apparent spectral index and curvature for each source within radius.
alpha_uncorrected = alpha + alpha_beam
q_uncorrected = q_curve + q_beam

# The apparent flux should be the central freq approximate beam value, times the 
# sources flux density, otherwise the estimates for the fine channels will be lower
# than predicted, especially for sources in problematic regions.
S_centralfreq_uncorrected = S_centralfreq*beamvalue_approx

print 'Number of PUMA sources selected = ',len(S_centralfreq_uncorrected)

#"""
################################################################################
# Creating output VO table
################################################################################
#"""

filename_body='model'

newvot = Table( [name, ra_str, dec_str, ra, dec,\
    S_centralfreq, alpha, alpha_beam, alpha_uncorrected, q_curve,\
    q_beam, q_uncorrected, beamvalue, beamvalue_approx, S_centralfreq_uncorrected,\
    peak_flux_wide, int_flux_wide, a_wide, b_wide, pa_wide],\
    names=('Name','ra_str','dec_str','ra','dec','S_centralfreq','alpha',\
        'alpha_beam','alpha_uncorrected','q_curve','q_beam','q_uncorrected',\
        'beamvalue','beamvalue_approx','S_centralfreq_uncorrected','peak_flux_wide','int_flux_wide',\
        'a_wide', 'b_wide', 'pa_wide'), meta={'name': 'first table'} )

writetoVO(newvot, filename_body+"_morecolumns_temp.vot")

#"""
print 'Completed'
end0 = time.time()

print "Total runtime = ", np.round(end0 - start0,3),"s\n"
