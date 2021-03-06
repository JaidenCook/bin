#!/usr/bin/python

__author__ = "Jaiden Cook"
__credits__ = ["Jaiden Cook"]
__version__ = "1.0.1"
__maintainer__ = "Jaiden Cook"
__email__ = "Jaiden.Cook@student.curtin.edu"

# Generic stuff:
import os,sys
import time
from datetime import datetime
import glob
import shutil
import re
from math import pi
import warnings
import subprocess
warnings.filterwarnings("ignore")

# Array stuff:
import numpy as np
warnings.simplefilter('ignore', np.RankWarning)

# Plotting stuff:
import matplotlib.pyplot as plt
import matplotlib.animation as animation

# Parser options:
from optparse import OptionParser

# Multiprocessing stuff:
from joblib import Parallel, delayed
import multiprocessing
from tqdm import tqdm

# Scipy stuff:
import scipy
from scipy import stats

# Astropy stuff:\
from astropy import units as u
from astropy.coordinates import SkyCoord
from astropy import wcs
from astropy.io import fits
from astropy.io import ascii
from astropy.io.votable import parse_single_table
from astropy.table import Table,Column,vstack
from astropy.io.votable import writeto as writetoVO

# This is a temporary hack.
sys.path.append(os.path.abspath("/home/jaiden/Documents/Masters_Project/bin"))
from JOOF import *

def subprocess_cmd(command,silent=False):
	process = subprocess.Popen(command, stdout=subprocess.PIPE, shell=True)
	proc_stdout = process.communicate()[0].strip()
	if (silent==False):
		print proc_stdout
	return (proc_stdout)

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


def gcd(ra1, dec1, ra2, dec2):
    """
    Great circle distance as calculated by the haversine formula.
    ra/dec in degrees
    returns:
    sep in degrees
    """
    from math import pi

    ra1 = np.radians(ra1)
    ra2 = np.radians(ra2)
    dec1 = np.radians(dec1)
    dec2 = np.radians(dec2)

    Del_RA = np.abs(ra1 - ra2)
    Del_DEC = np.abs(dec1 - dec2)
    d = 2.0*np.arcsin(np.sqrt(np.sin(Del_DEC/2.0)**2 + np.cos(dec1)*np.cos(dec2)*(np.sin(Del_RA/2.0))**2))

    #return sep
    return np.degrees(d)


def circle_subset(R,d,PA,r_vec,phi_vec):
	"""
	This function determines whether a given set of points in polar coordinates lie within an
	arbitrary circle. 

	Args:

	R : scalar; Radial size of the arbitrary circle.
	d : scalar; Distance from the origin to the arbitrary circle centre.
	PA : scalar; Position vector of the arbitrary circle centre.
	r_vec : vector_like; The orthographic polar radial coordinates of the given data points.
	phi_vec : vector_like; The azimuthal vector of a set of data points.
	"""

	if d > R:

		theta = np.arcsin(R/d)

		phi_min = PA - theta
		phi_max = PA + theta
		# This condition exists when the azimuthal angle wraps around 2pi.
		phi_min_cond = False

		if phi_min < 0.0:

			if phi_min + 2*pi > phi_max:

				t = phi_min
				phi_min = phi_max
				phi_max = t + 2*pi
			else:
				phi_min = phi_min + 2*pi

			phi_min_cond = True

		# If phi_min <0.0 we need a new approach.

		if phi_min_cond == True:

			phi_ind_1 = np.logical_and(phi_vec <= phi_max, phi_vec < phi_min)
			phi_ind_2 = np.logical_and(phi_vec >= phi_max, phi_vec > phi_min)

			phi_ind = np.logical_or(phi_ind_1 == True, phi_ind_2 == True)

		else:
			phi_ind = np.logical_and(phi_vec <= phi_max, phi_vec > phi_min)

		r1,r2 = draw_circle(R,d,PA,phi_vec[phi_ind])

		r_ind = np.array([(r_vec[phi_ind][i] >= r2[i]) and (r_vec[phi_ind][i] <= r1[i]) for i in range(len(r_vec[phi_ind]))])


		circ_ind = np.arange(len(phi_ind))[phi_ind][r_ind]

		return circ_ind

	elif d <= R:

		theta_OpAO = np.arcsin((d/R)*np.sin(np.abs(phi_vec - PA)))
		theta_OOpA = pi - np.abs(phi_vec - PA) - theta_OpAO

		rp = np.sqrt(d**2 + R**2 - 2*d*R*np.cos(theta_OOpA))

		circ_ind = np.array([r_vec[i] <= rp[i] for i in range(len(r_vec))])

		return np.arange(len(rp))[circ_ind]


def draw_circle(R,d,PA,phi_vec=None):
	"""
	For a given circle radius, distance from polar origin, position angle this function will
	determine the points in that circle. If a azimuthal vector is given (phi_vec != None) then the 
	radius from the origin, to the point on the arbitray circle that corresponds to the given 
	azimuth is returned.

	Args:

	R : scalar; Radial size of the arbitrary circle.
	d : scalar; Distance from the origin to the arbitrary circle centre.
	PA : scalar; Position vector of the arbitrary circle centre. Should be in radians
	phi_vec : vector_like; (default = None) The azimuthal vector of a set of data points. If given
	the function determines the distance from the origin to the circle for the given azimuth points.
	"""

	if R >= d:

		if np.any(phi_vec) == None:
		
			phi_vec = np.linspace(0,2*pi,100)
			
			# The angle bwetween the radius from the origin to the point on the arbitrary circle 
			# and the radius to the centre of the arbitrary circle.	
			theta = np.abs(phi_vec - PA)
	
			# angle between the radius to the point from the origin and the radius from the arbitrary
			# circle to the point.
			angle_OpAO = np.arcsin((d/R)*np.sin(theta))
			
			# Angle between the radius from the origin to the centre of the arbitrary circle, and from the
			# centre of the arbitrary circle to the point. All the angle of the triange ^OO'A.
			angle_OOpA = pi - theta - angle_OpAO
	
			# Radius from the origin to the point on the arbitrary circle.
			radius = np.sqrt(d**2 + R**2 -2.0*d*R*np.cos(angle_OOpA))
	
			return radius,phi_vec

		else:

			# The angle bwetween the radius from the origin to the point on the arbitrary circle 
			# and the radius to the centre of the arbitrary circle.	
			theta = np.abs(phi_vec - PA)
	
			# angle between the radius to the point from the origin and the radius from the arbitrary
			# circle to the point.
			angle_OpAO = np.arcsin((d/R)*np.sin(theta))
			
			# Angle between the radius from the origin to the centre of the arbitrary circle, and from the
			# centre of the arbitrary circle to the point. All the angle of the triange ^OO'A.
			angle_OOpA = pi - theta - angle_OpAO
	
			# Radius from the origin to the point on the arbitrary circle.
			radius = np.sqrt(d**2 + R**2 -2.0*d*R*np.cos(angle_OOpA))
	
			return radius

	elif R <= d:

		if np.any(phi_vec) == None:

			theta = np.arcsin(R/d)
			phi_min = PA - theta
			phi_max = PA + theta
	
			phi_vec = np.linspace(phi_min,phi_max,1000)
	
			theta_OOp = np.arcsin((d/R)*np.sin(np.abs(PA-phi_vec)))
	
			theta_OA = pi - np.abs(PA - phi_vec) - theta_OOp
	
			r1 = np.sqrt(d**2 + R**2 - 2*d*R*np.cos(theta_OA))
	
			theta_OpB = pi - theta_OOp
			theta_AB = pi - 2*theta_OpB
	
			r2 = np.sqrt(d**2 + R**2 - 2*d*R*np.cos(theta_OA + theta_AB))
	
			AB = r2 - r1
	
			radius = np.vstack((r1,r2[::-1])).flatten()
			Phi = np.vstack((phi_vec,phi_vec[::-1])).flatten()
	
			return radius,Phi

		else:

			theta_OOp = np.arcsin((d/R)*np.sin(np.abs(PA-phi_vec)))
	
			theta_OA = pi - np.abs(PA - phi_vec) - theta_OOp
	
			r1 = np.sqrt(d**2 + R**2 - 2*d*R*np.cos(theta_OA))
	
			theta_OpB = pi - theta_OOp
			theta_AB = pi - 2*theta_OpB
	
			r2 = np.sqrt(d**2 + R**2 - 2*d*R*np.cos(theta_OA + theta_AB))
	
			AB = r2 - r1
	
			return r1,r2

def com(x,y,weights=None,polar=False):
	"""
	This function determines the centre of mass for the given dataset, with the option
	of the data set being a polar or cartesian dataset. If the dataset is polar then 
	the input vector x is the radial vector and the input vector y is the azimuthal 
	vector. The option for weighted centre of mass is also given.

	Args:
	x : vector_like; If polar=False this is the cartesian x vector, if polar=True then
	this is the radial vector.
	y : vector_like; If polar=False this is the cartesian y vector, if polar=True then
	this is the radial vector.
	weights : vector_like;(default=None) This is the weight vector, if given the centre 
	of mass is the weighted centre of mass.
	polar : boolean; If false the input datasets are cartesian, if ture the input datasets
	are polar.
	"""

	if polar == True:

		# When polar r = x, phi = y.
		if np.any(weights) == None:
			
			# Unweighted case.
			xx = x*np.cos(y)
			yy = x*np.sin(y)
	
			R = np.sqrt(np.sum(xx)**2 + np.sum(yy)**2)/len(x)
			phi_PA = np.arctan2(np.sum(yy),np.sum(xx))
		
			return R, phi_PA
	
		else:
	
			# Weighted case.
			xxw = x*weights*np.cos(y)
			yyw = x*weights*np.sin(y)
	
			R = np.sqrt(np.sum(xw)**2 + np.sum(yw)**2)/np.sum(weights)
			phi_PA = np.arctan2(np.sum(yw)/np.sum(weights),np.sum(xw)/np.sum(weights))
		
			return R, phi_PA

	else:

		# Cartesian case.
		if np.any(weights) == None:
					
			x_avg = np.sum(x)/len(x)
			y_avg = np.sum(y)/len(y)

			return x_avg, y_avg
	
		else:
	
			# Weighted case.
			xw = x*weights
			yw = y*weights
	
			xw_avg = np.sum(xw)/np.sum(weights)
			yw_avg = np.sum(yw)/np.sum(weights)

			return xw_avg, yw_avg

def lobe_subset(RA,DEC,Flux,OBSID,d,PA,R=0.1,Az=None,r=None,plot_cond=False,output_cond=False,verb_cond=False):
	"""
	This function takes an input RA and DEC vector, transforms them into their corresponding Alt and Az vectors for a given
	OBSID. It then uses the position angle of the pointing centre in azimuthal cooridinates, as well as the distance to the
	poitning centre from zenith to define the centre of the primary beam (pb). It then subsets the sources in the pb by 
	drawing a circle in polar coordinates using the functions 'draw_circle()' and 'circle_subset()'. It then iterates this
	process by increasing the input radius 'R' by i*0.01. It repeats this process until the same number of sources are found 
	in subsequent iterations. The function the determines the weighted centre of mass, using the integrated flux densities
	of sources, and writes the string of the weighted RA and DEC in 'hms', 'dms' format. This process can be repeated for
	the grating lobes, or sidelobes of the tile beam pattern, so long as the position angle 'PA', and distance to the 
	supposed centre 'd' is defined.

	Args:
	RA : vector_like [deg]; Vector of right ascension positions in degrees.
	DEC : vector_like [deg]; Vector of declination positions in degrees.
	Flux : Vector_like; Vector of the integrated apparent flux densities for the given sources, corresponds to the RA and 
	OBSID : scalar; GPS time of the obsid.
	DEC positions.
	d : scalar; Radial distance in the orthographic projection from zenith to the supposed centre of the lobe.
	PA : scalar; Position angle of the supposed centre of the lobe.
	R : scalar; Initial radius of arbitrary circle, (default = 0.1).
	Az : Vector_like; (default = None) Optional to include the azimuth vector for each source, computed from the OBSID
	r : Vector_like; (default = None) Optional to include the rorthographic radius vector for each source, computed from the OBSID
	plot_cond : boolean; (default = False) Option to plot the orthographic projection in polar coordinates, with the defined
	subsetting regions.
	output_cond : boolean; (default = False) Option to give addition output, this provides the subsetted RA, DEC, Az, r vectors.
	The non-verbose output gives only the circle indices.
	verb_cond : boolean; (default = False) Option to give verbose output, this prints additional information to the command
	line about the operations of the function. This is useful for diagnostics tests.
	"""
	
	if plot_cond == True:

		fig = plt.figure(figsize = (12.5,9.5), dpi=90)
	
	if verb_cond == True:
		
		print "Radius of search circle = {0}".format(R)
		print "Distance to circle centre = {0}".format(np.round(d,3))

	if np.any(Az) == None or np.any(r) == None:

		# Case when the altitude and Azimuth are not provided.
		Alt, Az, Zen = mwa_alt_az_za(OBSID, RA, DEC, degrees=True)
		r = np.cos(np.radians(Alt))
	else:
		pass

	# Circle growing condition.
	lobe_cond = True
	dR = (2.0/100.0)

	for i in range(100):

		if i == 0:

			# Getting the index of sources in the circle.
			circ_ind = circle_subset(R,d,PA,r,np.radians(Az))
			
			# The number of sources in the circle
			N_circ_sources = len(circ_ind)

		else:

			# Getting the index of sources in the circle.
			circ_ind = circle_subset(R + i*dR,d,PA,r,np.radians(Az))

			if len(circ_ind) != N_circ_sources:

				# Update the number of souces in the circle.
				N_circ_sources = len(circ_ind)

			elif len(circ_ind) == N_circ_sources:

				# Else if the number of sources doesn't change then subset out pb sources.
				r_nu = np.delete(r,circ_ind)
				Az_nu = np.delete(Az,circ_ind)

				# Specifying the primary beam RA and DEC subsets.
				# Can use these and the com function to determine the centre of the image, as well as the size.
				RA_sub = RA[circ_ind]
				DEC_sub = DEC[circ_ind]
				Flux_sub = Flux[circ_ind]

				# Defining the centre of mass RA and DEC.
				#RA_sub_wcent, DEC_sub_wcent = com(RA_sub,DEC_sub,weights=Flux_sub)
				RA_sub_wcent, DEC_sub_wcent = quadrant_check(np.radians(RA_sub),np.radians(DEC_sub),weights=Flux_sub,gcd_cond=False)
				print "RA min, RA max",np.min(RA_sub),np.max(RA_sub)
				print "RA com",RA_sub_wcent

				# Getting the hmsdms format of the pointing centre.
				Cent_hmsdms_string = SkyCoord(ra=RA_sub_wcent*u.degree, dec=DEC_sub_wcent*u.degree).to_string('hmsdms')

				# Condition to break the for loop.
				lobe_cond = False

		if plot_cond == True:
				
			ax1 = fig.add_subplot(111,projection="polar")
			pcm1 = ax1.scatter(np.radians(np.delete(Az,circ_ind)), np.delete(r,circ_ind), \
				c=np.log10(np.delete(Flux,circ_ind)), cmap='viridis')
			
			radius, phi_vec = draw_circle(R + i*dR,d,PA)
			
			ax1.plot(phi_vec,radius)
			ax1.set_rmin(0.0)
			ax1.set_rmax(1.2)
			ax1.set_theta_zero_location('N')
			fig.colorbar(pcm1, ax=ax1, label='Apparent flux')
			
			plt.show(block=False)
			plt.pause(0.5)
			plt.clf()
			#plt.close()

		if lobe_cond == False:

			# Exit the for loop.
			break

	# Returning the angular disance from the com to each point.
	dtheta = quadrant_check(np.radians(RA_sub),np.radians(DEC_sub),weights=Flux_sub,gcd_cond=True)

	# This is used to determine the scale of the images.
	dDEC = np.abs(np.max(DEC[circ_ind]) - np.min(DEC[circ_ind]))
	#dRA = np.abs(np.max(RA[circ_ind]) - np.min(RA[circ_ind]))
	dRA = np.degrees(np.arccos((np.cos(2*np.max(np.radians(dtheta)))/np.cos(np.radians(dDEC)))))

	if verb_cond == True:
		print "Final circle radius = {0}".format(R + i*(1.0/100.0))
		print "Number of sources in lobe = {0}".format(len(circ_ind))
		print "Max(RA-pb) = {0} [deg], Min(RA-pb) = {1} [deg]".format(np.round(np.float(np.max(RA[circ_ind])),3),np.round(np.float(np.min(RA[circ_ind])),3))
		print "Max(DEC-pb) = {0} [deg], Min(DEC-pb) = {1} [deg]".format(np.round(np.float(np.max(DEC[circ_ind])),3),np.round(np.float(np.min(DEC[circ_ind])),3))
		print "Weighted centre of mass {0}".format(Cent_hmsdms_string)

	if output_cond == True:
		
		# Verbose output condition.
		return Cent_hmsdms_string, RA_pb, DEC_pb, r_nu, Az_nu, dRA, dDEC

	else:
		
		# Non-verbose output.
		return Cent_hmsdms_string, circ_ind, dRA, dDEC



def sidelobe_finder(r,Az,weights=None,plot_cond=False,verb_cond=False):
	"""
	This function is run after the pb has been subtracted from the dataset. This function takes an 
	input radius and azimuth vecotr for an orthographic poar projection. It then seperates the data
	into azimuthal slices that are 2pi/8 in width. It counts the number of sources in each slice,
	selecting the slice with the maximum number of sources. This will likely correspond to a grating
	lobe. It then finds the weighted average and position angle of the slice, which should be close 
	to the centre of the grating lobe. This function then outputs the weighted average radius and 
	position angle.

	Args:

	r : vector_like; Vector of radius values for the orthographic polar projection.
	Az : vector_like; Vector of azimuthal values for the orthographic polar projection.
	Weights : vector_like; (default = None) Vector of weights with the same dimensions as radius and 
	azimuth vectors. This vector is used to find the weighted average radius and position angle for 
	the azimuthal slice with the most number of sources.
	plot_cond : boolean; (default = False) Option to plot the orthographic projection in polar coordinates, 
	with the defined subsetting regions.
	verb_cond : boolean; (default = False) Option to give verbose output, this prints additional information 
	to the command line about the operations of the function. This is useful for diagnostics tests.
	"""
	phi_slice = np.linspace(0,2*pi,9)

	N_sources_per_slice = []

	for i in range(len(phi_slice)):

		if i==0:

			pass

		else:
			
			# Creating a temporary phi slice radius vector.
			r_tpm = r[np.logical_and(Az >= np.degrees(phi_slice[i-1]),Az <= np.degrees(phi_slice[i]))]
			
			# Determining the number of sources per slice.
			N_sources_per_slice.append(len(r_tpm))

			if verb_cond == True:
				print "Azimuthal slice: [{0},{1}] [deg]".format(np.round(np.degrees(phi_slice[i-1]),3),np.round(np.degrees(phi_slice[i]),3))
				print "Mean radius = {0} [sin(theta)]".format(np.round(np.mean(r_tpm),3))
				print "Number of sources in slice = {0}\n".format(len(r_tpm))

			if plot_cond == True and np.any(weights) != None:
			
				# Creating a phi slice apparent flux vector.
				App_flux_slice = weights[np.logical_and(Az >= np.degrees(phi_slice[i-1]),Az <= np.degrees(phi_slice[i]))]

				# Plotting the histogram of every slice.
				plt.hist(np.degrees(np.arcsin(r_tpm)),bins=25,edgecolor='k',label='radius',weights=App_flux_slice)
				plt.title(r"$\theta \in  [{0},{1}]  $".format(np.round(np.degrees(phi_slice[i-1]),3),np.round(np.degrees(phi_slice[i]),3)))
				plt.xlabel(r'$\rm{radius [\sin(\theta)]}$',fontsize=14)
				plt.show()
				plt.close()

			else:

				pass

	if np.max(N_sources_per_slice) <= 10:
		# Case when there is no cler sidelobe, return none.
		return None

	else:
		pass

	# Index for the slice with the max number of sources.
	Max_slice_ind = np.argmax(N_sources_per_slice)

	sub_set_ind = np.logical_and(Az >= np.degrees(phi_slice[Max_slice_ind]),Az <= np.degrees(phi_slice[Max_slice_ind+1]))

	# Subset of the orthographic radius values for sources in slice.
	r_max_slice = r[sub_set_ind]
	
	# Subset of azimuth values for sources in slice.
	Az_max_slice = Az[sub_set_ind]

	if np.any(weights) == None:

		# Determining the position angle of the maximum slice.
		PA_max_slice = np.radians(np.mean(Az_max_slice))
		# Determining the mean radius for the maximum slice.
		r_mean_max_slice = np.mean(r_max_slice)

	else:
		# weights will need to be subsetted too.
		weights = weights[sub_set_ind]

		# This option is for determining the weighted average.
		PA_max_slice = np.radians(np.sum(Az_max_slice*weights)/np.sum(weights))

		r_mean_max_slice = np.sum(r_max_slice*weights)/np.sum(weights)

	return r_mean_max_slice, PA_max_slice

def file_write_positions(file,obsid,centre,Npix_RA,Npix_DEC,pix_scale,zen_cond=False):
	"""
	This function writes the inputs to a given file.
	"""

	file.write("chgcentre {0}.ms {1}\n".format(obsid,centre))

	file.write("wsclean -name {0}_deeper -size {1} {2} -niter 30000 -auto-threshold 8.0 -auto-mask 10.0 -pol I -weight uniform \
	-scale {3}asec -abs-mem 31 -j 12 -apply-primary-beam -mwa-path $mwapath -mgain 0.85 -minuv-l 60  {0}.ms\n".format(obsid,Npix_RA,Npix_DEC,pix_scale))

	if zen_cond == True:
		file.write("chgcentre -zenith {0}.ms\n".format(obsid))
		file.write("Place-holder until model save script written\n")
	else:
		pass

def quadrant_check(RA,DEC,weights=None,gcd_cond=False):
	"""
	This function is designed to deal with fringe case sources, when the RA values are both less than
	pi/2 and greater than 3pi/2. This corresponds to sources in quadrants 4 and 1, where the angle
	wraps back around again. To properly determine the angular distances between sources, and the centre
	of mass (com) sources need to be shifted into two other neighbouring quadrants that don't wrap. This
	function flips the RA values then calculates the new com. It then shifts the com RA value back to
	it's appropriate quadrant. This function also can alternatively return the angular distance between
	each source and the com, if gcd_cond=True. This is useful for determining the size of the images
	required map the lobes.

	Args:

	RA : vector_like; Vector of Right Ascention values in radians.
	DEC : vector_like; Vector of Declination values in radians.
	weights : vector_like; (default=None) Vector of weights.
	gcd_cond : boolean; If True, the function determines the angular distance to every given point 
	relative to the centre of mass. It does this in the shifted frame since the distance from the com
	is only relative.
	"""

	if (np.any(RA > 0.0) and np.any(RA <= pi/2.0)) and (np.any(RA <= 2*pi) and np.any(RA >= (3.0/2.0)*pi)):

		# shifting the RA values into neighbouring unwrapped quadrants. 
		RA[RA > (3.0/2.0)*pi] = pi + (2*pi - RA[RA > (3.0/2.0)*pi])
		RA[RA < pi/2.0] = pi - RA[RA < pi/2.0]

		# Calculating the weighted or unweighted com.
		#RA_com,DEC_com = com(RA,DEC,weights)
		RA_com,DEC_com = com(RA,DEC)#,weights)

		if gcd_cond == True:

			# The angular separtation between the com and every source.
			sep_vec = gcd(np.degrees(RA_com),np.degrees(DEC_com),np.degrees(RA),np.degrees(DEC))

			return sep_vec
		else:
			pass
			
		# Shifting the com back to the original quadrant.
		if RA_com >= pi:
	
			RA_com = 2*pi - (RA_com - pi)
	
		elif RA_com < pi:
	
			RA_com = pi - RA_com

		return np.degrees(RA_com), np.degrees(DEC_com)
		#return RA_com, DEC_com

	else:

		# Calculating the weighted or unweighted com.
		RA_com,DEC_com = com(RA,DEC)#,weights)
		#RA_com,DEC_com = com(RA,DEC,weights)

		if gcd_cond == True:

			# The angular separation between the com and every source.
			sep_vec = gcd(np.degrees(RA_com),np.degrees(DEC_com),np.degrees(RA),np.degrees(DEC))

			return sep_vec

		else:

			return np.degrees(RA_com), np.degrees(DEC_com)
			#return RA_com, DEC_com
	
def rad_plt(R,d,PA,Az,r,Flux):
	"""
	This function is just ot check that the positioning of the sidelobes is correct.
	"""

	print R
	print d
	print PA

	fig = plt.figure(figsize = (12.5,9.5), dpi=90)
	ax1 = fig.add_subplot(111,projection="polar")
	pcm1 = ax1.scatter(np.radians(Az), r, c=np.log10(Flux), cmap='viridis')
	
	radius,phi_vec = draw_circle(R,d,PA)
	
	ax1.plot(phi_vec,radius)
	ax1.scatter(PA,d,color='r',s=30)
	ax1.set_rmin(0.0)
	ax1.set_rmax(1.2)
	ax1.set_theta_zero_location('N')
	fig.colorbar(pcm1, ax=ax1, label='Apparent flux')
	
	plt.show()
	#plt.show(block=False)
	#plt.pause(0.5)
	#plt.clf()
	plt.close()



if __name__ == "__main__":

	# Setting up parser options:
	usage="Usage: %prog [options]\n"
	parser = OptionParser(usage=usage)
	parser.add_option('--obsid',dest="obsid",default=None,help="Input OBSID")
	parser.add_option('--scale',dest="scale",default=None,help="Pixel scale in arcseconds")
	parser.add_option('--v',dest="verbcond",default=False,help="Verbose output condition, default is false, useful for diagnostics.")
	parser.add_option('--plot',dest="plotcond",default=False,help="Plotting condition, default is false, useful for diagnostics.")
	
	(options, args) = parser.parse_args()

	# Setting the conditions.
	if str(options.verbcond) == 'True':
		verbcond = True
	else:
		verbcond = False

	if str(options.plotcond) == 'True':
		plotcond = True
	else:
		plotcond = False

	newfile = open('{0}_position.txt'.format(options.obsid),'w')

	#################################################################################
	# Setting initial parameters
	#################################################################################

	# Opening the metafits file:
	metadata = fits.open('{0}.metafits'.format(options.obsid))[0].header

	# Opening the model file:
	header = fits.getheader("{0}-sources_comp.fits".format(options.obsid))
	data = fits.getdata("{0}-sources_comp.fits".format(options.obsid))

	# loading in the table data.
	t = Table(data)

	# Initialsing the RA, DEC and apparent flux vectors.
	RA = np.array(t['ra'])
	DEC = np.array(t['dec'])
	App_int_flux = np.array(t['int_flux'])
	err_App_int_flux = np.array(t['err_int_flux'])

	# Initialising the user inputted pixel scale.
	pix_scale = float(options.scale)
	thresh_cond = 0.95

	# RA and DEC of the pointing centre.
	PC_RA = metadata['RA']
	PC_DEC = metadata['DEC']

	print "lobe-finder.py version = {0}\n".format(__version__)

	if pix_scale == None:

		print "No pixel scale given, pixel should be given in units of arcseconds."
		print "exiting lobe-finder.py!"

		sys.exit(0)
	else:
		pass

	print "OBSID = {0}".format(int(options.obsid))
	print "Pixel scale = {0} [arcseconds]".format(options.scale)
	print "Pointing centre RA = {0} [deg]".format(np.round(PC_RA),3)
	print "Pointing centre DEC = {0} [deg]".format(np.round(PC_DEC),3)

	# Creating the Alt, Az, Zenith and radial orthographic vectors.
	Alt, Az, Zen = mwa_alt_az_za(options.obsid, RA, DEC, degrees=True)
	r = np.cos(np.radians(Alt))

	#################################################################################
	# Specifying circle parameters:
	#################################################################################
	
	theta_PA = np.radians(metadata['azimuth'])
	d = np.cos(np.radians(metadata['altitude']))
	
	print "Pointing centre azmiuth = {0} [deg]".format(np.degrees(theta_PA))
	print "Pointing centre altitude = {0} [deg]".format(np.round(metadata['altitude']),5)
	print "Max apparent int flux = {0} [Jy]".format(np.round(np.max(App_int_flux)),3)
	print "Total apparent flux = {0} [Jy]".format(np.round(np.sum(App_int_flux)),3)
		
	#################################################################################
	# Subsetting the pb.
	#################################################################################

	print "########################################################################"
	print "# Finding and subtracting the number of sources in the primary beam pb.#"
	print "########################################################################"

	centre,circ_ind,dRA,dDEC = lobe_subset(RA,DEC,App_int_flux,options.obsid,d,theta_PA,Az=Az,r=r,verb_cond=verbcond,plot_cond=plotcond)

	# Determining the pixel dimensions:
	Npix_RA = int(dRA*3600/pix_scale) + 5
	Npix_DEC = int(dDEC*3600/pix_scale) + 5

	print "Pixel dimensions for the pb (RA,DEC) = {0}x{1}".format(Npix_RA,Npix_DEC)

	# Writing the new centre of the lobe to file.
	file_write_positions(newfile,options.obsid,centre,Npix_RA,Npix_DEC,pix_scale,zen_cond=True)

	# Aggregate apparent flux for each identified lobe.
	lobe_app_flux = np.sum(App_int_flux[circ_ind])
	print "1",np.sum(App_int_flux[circ_ind])

	# Creating the pb subtrated datasets.
	r_nu = np.delete(r,circ_ind)
	RA_nu = np.delete(RA,circ_ind)
	DEC_nu = np.delete(DEC,circ_ind)
	App_int_flux_nu = np.delete(App_int_flux,circ_ind)
	Az_nu = np.delete(Az,circ_ind)

	#################################################################################
	# Subsetting the grating lobes.
	#################################################################################

	print "########################################################################"
	print "# Identifying the sidelobes azimuthal positions.                       #"
	print "########################################################################"

	for i in range(4):

		# Need to add condition when no sidelobe is found. Set sidelobe_finder to return None.
		# Condition if a sidelobe is not found.
		if sidelobe_finder(r_nu,Az_nu,weights=r_nu/App_int_flux_nu,verb_cond=verbcond) == None:
			break
		else:
			d_GL, PA_GL = sidelobe_finder(r_nu,Az_nu,weights=r_nu/App_int_flux_nu,verb_cond=verbcond)
	
		print "########################################################################"
		print "# Finding and subtracting grating lobe #{0}.                             #".format(i+1)
		print "########################################################################"
	
		# Subsetting the sidelobes.
		centre,circ_ind_nu,dRA,dDEC = lobe_subset(RA_nu,DEC_nu,App_int_flux_nu,options.obsid,d_GL,PA_GL,\
			Az=Az_nu,r=r_nu,verb_cond=verbcond,plot_cond=plotcond)

	###############################################################################

		centre_deg = SkyCoord(centre.split()[0],centre.split()[1],frame='icrs')

		print centre,centre_deg.ra.deg,centre_deg.dec.deg

		centre_Alt, centre_Az, centre_Zen = mwa_alt_az_za(options.obsid, centre_deg.ra.deg, centre_deg.dec.deg)
		d_centre = np.sin(np.radians(centre_Zen))

		print centre_Az,centre_Zen
		print centre_Az,np.sin(np.radians(centre_Zen))

		#(R,d,PA,Az,r,Flux)
		rad_plt(np.sqrt(dRA**2 + dDEC**2)/90.0,np.abs(d_centre),np.radians(centre_Az),Az,r,App_int_flux)

	###############################################################################

		# Determining the pixel dimensions:
		Npix_RA = int(dRA*3600/pix_scale) + 5
		Npix_DEC = int(dDEC*3600/pix_scale) + 5
	
		print "Pixel dimensions for the pb (RA,DEC) = {0}x{1}".format(Npix_RA,Npix_DEC)
		# Writing the new centre of the lobe to file.
		file_write_positions(newfile,options.obsid,centre,Npix_RA,Npix_DEC,pix_scale,zen_cond=True)

		# Updating the total apparent flux in the subtracted lobes.		
		lobe_app_flux += np.sum(App_int_flux_nu[circ_ind_nu])

		# Deleting the new set of sources.
		r_nu = np.delete(r_nu,circ_ind_nu)
		RA_nu = np.delete(RA_nu,circ_ind_nu)
		DEC_nu = np.delete(DEC_nu,circ_ind_nu)
		App_int_flux_nu = np.delete(App_int_flux_nu,circ_ind_nu)
		Az_nu = np.delete(Az_nu,circ_ind_nu)

	#################################################################################
	# Final output.
	#################################################################################

	print "Total apparent flux = {0} [Jy]".format(np.round(np.sum(App_int_flux),3))
	print "Total apparent flux in lobes = {0} [Jy]".format(np.round(lobe_app_flux,3))
	print "Percentage of flux captured = {0} %".format(100*np.round(lobe_app_flux/np.sum(App_int_flux),3))
	

	for i in range(3):

		if lobe_app_flux/np.sum(App_int_flux) <= thresh_cond:

			if i==0:
	
				print "Apparent flux is below the threshold condition of lobe_flux/total_flux = {0}".format(thresh_cond)
				print "Searching for brightes apparent source in the list."
	
				print "########################################################################"
				print "# Searching for additional bright point sources.                       #"
				print "########################################################################"

	
			circ_ind_nu = np.argmax(App_int_flux_nu)

			print "Source apparent flux density = {0} [Jy]".format(App_int_flux_nu[circ_ind_nu])

			centre = SkyCoord(ra=RA_nu[circ_ind_nu]*u.degree, dec=DEC_nu[circ_ind_nu]*u.degree).to_string('hmsdms')
			
			# Writing the new centre of the lobe to file.
			file_write_positions(newfile,options.obsid,centre,100,100,pix_scale,zen_cond=True)

			print "Source location {0}".format(centre)

			# Updating the total apparent flux in the subtracted lobes.		
			lobe_app_flux += np.sum(App_int_flux_nu[circ_ind_nu])
	
			print "Total apparent flux in lobes = {0} [Jy]".format(np.round(lobe_app_flux,3))
			print "Percentage of flux captured = {0} %".format(100*np.round(lobe_app_flux/np.sum(App_int_flux),3))

			# Deleting the new set of sources.
			r_nu = np.delete(r_nu,circ_ind_nu)
			RA_nu = np.delete(RA_nu,circ_ind_nu)
			DEC_nu = np.delete(DEC_nu,circ_ind_nu)
			App_int_flux_nu = np.delete(App_int_flux_nu,circ_ind_nu)
			Az_nu = np.delete(Az_nu,circ_ind_nu)

		else:
			break

	newfile.close()

	print "chgcentre and wsclean commands writtent to file {0}_position.txt".format(options.obsid)




