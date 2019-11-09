#!/usr/bin/python

import numpy,os,sys
try:
        import pyfits
except:
        import astropy.io.fits as pyfits

from optparse import OptionParser

######################################################################
def main():

    usage="Usage: %prog [options]\n"
    usage+='\tCopies FITS header information from metafits file to a FITS image\n'
    parser = OptionParser(usage=usage)
    parser.add_option('-i','--image',dest='image',default=None,
                      help='Image (to have header update)')
    parser.add_option('-x','--xtension',dest='ext',default=0,
                      type='int',
                      help='FITS extension to update [default=%default]')
    parser.add_option('-m','--metafits',dest='metafits',default=None,
                      help='Input metafits (origin of header info)')
    parser.add_option('-e','--exclude',dest='exclude',default=None,
                      help='Header keywords to exclude')
    parser.add_option('-v','--verbose',action="store_true",
                      dest="verbose",default=False,
                      help="Increase verbosity of output")

    (options, args) = parser.parse_args()
    if options.image is None:
        print "Must supply input image"
        sys.exit(1)
    if options.metafits is None:
        print "Must supply input metafits"
        sys.exit(1)
    if not os.path.exists(options.metafits):
        print 'Metafits file %s does not exist' % options.metafits
        sys.exit(1)
    if not os.path.exists(options.image):
        print 'Image file %s does not exist' % options.image
        sys.exit(1)
    try:
        fm=pyfits.open(options.metafits)
    except IOError, err:
        print 'Unable to open FITS file %s\n\t%s' % (options.metafits,err)
        sys.exit(1)
    try:
        fi=pyfits.open(options.image,mode='update')
    except IOError, err:
        print 'Unable to open FITS file %s\n\t%s' % (options.image,err)
        sys.exit(1)

    if options.exclude is not None:
        exclude=options.exclude.split(',')
    else:
        exclude=[]
    for k in fm[0].header.keys():
        if not k in fi[0].header.keys():
            if k in exclude:
                if options.verbose:
                    print 'Excluding update of %s' % k
                    continue
            # this allows for multiple versions of PYFITS
            # with different implementations
            else:
                try:
                    fi[options.ext].header[k]=fm[0].header[k]
                except KeyError:
                    fi[options.ext].header.update(k,fm[0].header[k])
                if options.verbose:
                    print 'Updated %s=%s' % (k,fm[0].header[k])
        
    if options.verbose:
        print '%s[%d] updated' % (options.image,options.ext)
            
    fi.flush()
######################################################################

if __name__=="__main__":
    main()
