#!/usr/bin/python

import sys
try:
    import astropy.io.fits as pyfits
except ImportError:
    import pyfits
from optparse import OptionParser
from numpy import std, average, min, max

usage="Usage: %prog [options] <file>\n"
parser = OptionParser(usage=usage)
parser.add_option('--corners',action="store_true",dest="corners",default=True,
                  help="Use the four corners to measure the rms?")
parser.add_option('--middle',action="store_false",dest="corners",default=True,
                  help="Use the middle of the image to measure the rms?")
parser.add_option('--mean',action="store_true",dest="mean",default=False,
                  help="Report the mean of the data instead of the rms (useful for images of the rms).")
parser.add_option('--maximum',action="store_true",dest="maximum",default=False,
                  help="Report the max of the data instead of the rms).")
parser.add_option('--minimum',action="store_true",dest="minimum",default=False,
                  help="Report the min of the data instead of the rms).")
# 300 pixels is a good compromise between speed, excluding undeconvolved sources, and getting enough pixels to make a sensible measurement
parser.add_option('--boxsize',dest="side",default=300,type=int,
                  help="Set the box side size in pixels; default = 300x300 pixels")
parser.add_option('-f','--filename',dest="filename",default=None,
                  help="Measure rms of <FILE>",metavar="FILE")
(options, args) = parser.parse_args()

if options.filename is None:
    print "Must supply a filename"
    sys.exit(1)
else:
    side=options.side
    rms=[]
    hdulist = pyfits.open(options.filename)
    if hdulist[0].data.shape[0]>1:
        #format is e.g. RA, Dec, stokes, spectral -- unusual for MWA images
        totlen=hdulist[0].data.shape[0]
        sfxy=False
    else:
        # format is e.g. stokes, spectral, RA, Dec -- usual for MWA images
        totlen=hdulist[0].data.shape[2]
        sfxy=True

    scidata=[]
    if totlen>0:
        if options.corners:
            if sfxy:
                scidata.append(hdulist[0].data[:,:,totlen-side:totlen,totlen-side:totlen][0][0])
                scidata.append(hdulist[0].data[:,:,0:side,totlen-side:totlen][0][0])
                scidata.append(hdulist[0].data[:,:,totlen-side:totlen,0:side][0][0])
                scidata.append(hdulist[0].data[:,:,0:side,0:side][0][0])
            else:
                scidata.append(hdulist[0].data[totlen-side:totlen,totlen-side:totlen][0][0])
                scidata.append(hdulist[0].data[0:side,totlen-side:totlen][0][0])
                scidata.append(hdulist[0].data[totlen-side:totlen,0:side][0][0])
                scidata.append(hdulist[0].data[0:side,0:side][0][0])
        else:
            half=int(totlen/2)
            if sfxy:
                scidata=hdulist[0].data[:,:,half-side:half+side,half-side:half+side]
            else:
                scidata=hdulist[0].data[half-side:half+side,half-side:half+side]
        if options.mean:
            print average(scidata)
        elif options.maximum:
            print max(scidata)
        elif options.minimum:
            print min(scidata)
        else:
            print std(scidata)
