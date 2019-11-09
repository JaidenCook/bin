#!/usr/bin/python

import sys,os,re
try:
    import astropy.io.fits as pyfits
except ImportError:
    import pyfits
from optparse import OptionParser

usage="Usage: %prog [options] <file>\n"
parser = OptionParser(usage=usage)
parser.add_option('-f','--filename',dest="filename",default=None,
                  help="Rename <FILE>",metavar="FILE")
parser.add_option('-v','--version',dest="version",default=2.1,type=float,
                  help="Version of the data reduction used.")
(options, args) = parser.parse_args()
if options.filename is None:
    print "Must supply a filename"
    sys.exit(1)
else:
    filename=options.filename
    hdulist = pyfits.open(filename)
    formatstring="{0:s}_{1:03.0f}-{2:03.0f}MHz_{3:s}_r{4:1.1f}_v{5:1.1f}.fits"
    newfilename=formatstring.format(
                filename.split("_")[0],
                1e-6*(hdulist[0].header['CRVAL3']-(hdulist[0].header['CDELT3']/2)),
                1e-6*(hdulist[0].header['CRVAL3']+(hdulist[0].header['CDELT3']/2)),
                filename.split("-")[2],
                float(re.findall("[+-]?\d+(?:\.\d+)?",hdulist[0].header['WSCWEIGH'])[0]),
                options.version)
    print newfilename
