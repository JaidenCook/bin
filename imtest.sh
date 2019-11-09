#!/bin/bash

start_time=`date +%s`

# Set default values for optional parameters
peel_threshold=50.0
pbeam_model=2016
sigma_final=1.0
sigma_mask=3.0
niter=1000000
chgcentre=yes
selfcal="yes"
keep_ms=no
multiscale=""
flag=yes
#minuv=60

# Read the options
TEMP=`getopt -o a:b:c:d:e:f:g:h:i:jklmno: --long input_dir:,output_dir:,obsid_list:,chan:,peel_threshold:,pbeam_model:,sigma_final:,sigma_mask:,niter:,nochgcentre,selfcal,keep_ms,multiscale,noflag,minuv: -- "$@"`
eval set -- "$TEMP"

# Extract options and their arguments into variables
while true ; do
      case "$1" in
        -a|--input_dir) # input directory (required argument)
            case "$2" in
                "") shift 2 ;;
                *) input_dir=$2 ; shift 2 ;;
            esac ;;
        -b|--output_dir) # output directory (required argument)
            case "$2" in
                "") shift 2 ;;
                *) output_dir=$2 ; shift 2 ;;
            esac ;;
        -c|--obsid_list) # obsID list (required argument)
            case "$2" in
                "") shift 2 ;;
                *) obsid_list=$2 ; shift 2 ;;
            esac ;;
        -d|--chan) # channel (required argument); set to 69, 93, 121, 145 or 169
            case "$2" in
                "") shift 2 ;;
                *) chan=$2 ; shift 2 ;;
            esac ;;
        -e|--peel_threshold) # apparent flux cut for peeling in Jy (optional argument)
            case "$2" in
                "") shift 2 ;;
                *) peel_threshold=$2 ; shift 2 ;;
            esac ;;
        -f|--pbeam_model) # Primary beam model (optional argument); set to 2014 or 2016
            case "$2" in
                "") shift 2 ;;
                *) pbeam_model=$2 ; shift 2 ;;
            esac ;;
        -g|--sigma_final) # final CLEAN sigma level (optional argument)
            case "$2" in
                "") shift 2 ;;
                *) sigma_final=$2 ; shift 2 ;;
            esac ;;
        -h|--sigma_mask) # sigma level for masked CLEANing (optional argument)
            case "$2" in
                "") shift 2 ;;
                *) sigma_mask=$2 ; shift 2 ;;
            esac ;;
        -i|--niter) # Maximum number of iterations for final, deep CLEAN (optional argument)
            case "$2" in
                "") shift 2 ;;
                *) niter=$2 ; shift 2 ;;
            esac ;;
        -j|--nochgcentre) chgcentre=no ; shift ;; # do not change phase centre of measurement set before imaging (no argument, acts as flag)
        -k|--selfcal) selfcal=yes ; shift ;; # apply self-calibration (no argument, acts as flag)
        -l|--keep_ms) keep_ms=yes ; shift ;; # keep measurement set (no argument, acts as flag)
        -m|--multiscale) multiscale="-multiscale" ; shift ;; # apply multiscale CLEAN (no argument, acts as flag)
        -n|--noflag) flag=no ; shift ;; # do not flag tiles in obsid_list (no argument, acts as flag)
        -o|--minuv) # Minimum uv distance in lambda; weights also tapered with Tukey transition of size minuv/2 (optional argument)
            case "$2" in
                "") shift 2 ;;
                *) minuv=$2 ; shift 2 ;;
            esac ;;
        --) shift ; break ;;
        *) echo "Internal error!" ; exit 1 ;;
    esac
done

# Check required arguments have been specified
if [ -z "$input_dir" ]; then
  echo "Error: input_dir not specified. Aborting."
  exit 1
elif [ -z "$output_dir" ]; then
  echo "Error: output_dir not specified. Aborting."
  exit 1
elif [ -z "$obsid_list" ]; then
  echo "Error: obsid_list not specified. Aborting."
  exit 1
elif [ -z "$chan" ]; then
  echo "Error: chan not specified. Aborting."
  exit 1
fi

# Check chan parameter
if [ $chan != "69" ] && [ $chan != "93" ] && [ $chan != "121" ] && [ $chan != "145" ] && [ $chan != "169" ] && [ $chan != "236" ] && [ $chan != "237" ]; then
  echo "Error: chan should be set to 69, 93, 121, 145 or 169. Aborting."
  exit 1
fi

# Check pbeam_model parameter
if [ $pbeam_model != "2014" ] && [ $pbeam_model != "2016" ]; then
  echo "Error: pbeam_model should be set to 2014 or 2016. Aborting."
  exit 1
fi

# Set minuv if required
if [ ! -z "$minuv" ]; then
  taper=`echo "$minuv/2.0" | bc -l`
  printf -v taper "%.2f" $taper
  minuv="-minuv-l $minuv -taper-inner-tukey $taper"
fi

# Set obsid:
obsid=` awk '{print $1}' $obsid_list`

# Set other parameters:
imsize=5000
robust=0.0 # Briggs weighting schemes to use (for phase 2)
fwhm=75 # FWHM of Gaussian taper
absmem=31
ncpus=12
pols="I Q U V" # polarisations to generate using pbcorrect
allpols="I Q U V XX XY XYi YY" # polarisations to rescale
nchan="4 -join-channels" #number chans for subchans
subchans="MFS" #"0000 0001 0002 0003" # WSClean suffixes for subchannels and MFS
images="image" # kinds of image to rescale and upload to NGAS

# Create output directory:
if [ ! -e $output_dir ]; then
  mkdir $output_dir
fi

# Create snapshot directory:
if [ -e $output_dir/$obsid ]; then
  echo "Error: Output directory $output_dir/$obsid already exists. Aborting."
  exit 1
else
  mkdir $output_dir/$obsid
  cd $output_dir/$obsid
fi

# Write input parameters to file for record:
cat >> input_parameters_image.txt <<EOPAR
input_dir = $input_dir
output_dir = $output_dir
obsid_list = $obsid_list
chan = $chan
chgcentre = $chgcentre
peel_threshold = $peel_threshold
selfcal = $selfcal
keep_ms = $keep_ms
multiscale = $multiscale
flag = $flag
minuv = $minuv
pbeam_model = $pbeam_model
sigma_final = $sigma_final
sigma_mask = $sigma_mask
niter = $niter
imsize = $imsize
trim = $trim
robust = $robust
absmem = $absmem
ncpus = $ncpus
pols = $pols
allpols = $allpols
subchans = $subchans
images = $images
EOPAR

scale=`echo "1.1 / $chan" | bc -l` # At least 4 pix per synth beam for each channel
if [[ $chan -eq 69 ]]; then
  freq="072-103MHz"
elif [[ $chan -eq 93 ]]; then
  freq="103-134MHz"
elif [[ $chan -eq 121 ]]; then
  freq="139-170MHz"
elif [[ $chan -eq 145 ]]; then
  freq="170-200MHz"
elif [[ $chan -eq 169 ]]; then
  freq="200-231MHz"
elif [[ $chan -eq 236 ]]; then
  freq="288-312MHz"
elif [[ $chan -eq 237 ]]; then
  freq="291-315MHz"
fi

# Copy measurement set and metafits file to output directory:
if [ -e $input_dir/$obsid.ms ]; then
  cp -r $input_dir/$obsid.ms .
  if [ -e $input_dir/$obsid.metafits ]; then
    cp -r $input_dir/$obsid.metafits .
  else
    make_metafits.py -g $obsid -o $obsid.metafits
  fi
elif [ -e $input_dir/$obsid/$obsid.ms ]; then
  cp -r $input_dir/$obsid/$obsid.ms .
  if [ -e $input_dir/$obsid/$obsid.metafits ]; then
    cp -r $input_dir/$obsid/$obsid.metafits .
  else
    make_metafits.py -g $obsid -o $obsid.metafits
  fi
else
  echo "Error: input measurement set is missing. Aborting."
  exit 1
fi

# Flag tiles if required:
if [ $flag == "yes" ]; then
  tile_list=`sed "${SLURM_ARRAY_TASK_ID}q;d" $obsid_list | awk '{print $2}'`
  if [ -z "$tile_list" ]; then
    echo "No tiles to flag for snapshot $obsid"
  elif [ $tile_list == "none" ]; then
    echo "No tiles to flag for snapshot $obsid"
  else
    tile_list=`echo ${tile_list//,/ }`
# Check tiles are integers between 0 and 127
    for tile in ${tile_list[@]}; do  
      if [ "${tile//[0-9]}" != "" ] || [ $(echo "$tile < 0"|bc) -eq 1 ] || [ $(echo "$tile > 127"|bc) -eq 1 ]; then
        echo "Error: tile $tile is not an integer between 0 and 127. Aborting."
        exit 1
      fi
    done
# Flag tiles
    echo "Flagging tiles $tile_list for snapshot $obsid listed in $obsid_list"
    flagantennae $obsid.ms $tile_list
  fi
fi


# Testing the imaging:
#
# Using -apply beam to pb correct the image.
#
# Will trial selfcal later:
#wsclean -name ${obsid}_deeper -size $imsize $imsize -niter $niter -auto-threshold $sigma_final \
#-auto-mask $sigma_mask -apply-primary-beam -pol XX,YY,XY,YX -weight briggs $robust -scale ${scale} -abs-mem $absmem \
#-join-polarizations -j $ncpus -mgain 0.95 -channels-out $nchan $minuv $multiscale $obsid.ms

#wsclean -name ${obsid}_deeper -size 5000 5000 -niter 300000 -auto-threshold 1.0 \
#-auto-mask 3.0 -apply-primary-beam -pol XX,YY,XY,YX -weight uniform -scale 0.04 -abs-mem 31 \
#-join-polarizations -j 12 -mgain 0.95 -channels-out 4 -join-channels -minuv-l 60 -multiscale  $obsid.ms

#wsclean -name ${obsid}_deeper -size 3000 3000 -niter 30000 -auto-threshold 8.0 \
#-auto-mask 10.0 -pol XX,YY,XY,YX -weight uniform -scale 0.03 -abs-mem 31 \
#-join-polarizations -j 12 -mgain 0.95 -channels-out 4 -join-channels -minuv-l 60 -multiscale  $obsid.ms

# Setting scale using asec instead of degrees.
#wsclean -name ${obsid}_deeper -size 5000 5000 -niter 30000 -auto-threshold 8.0 \
#-auto-mask 10.0 -pol XX,YY,XY,YX -weight uniform -scale 82asec -abs-mem 31 \
#-join-polarizations -j 12 -mgain 0.95 -channels-out 4 -join-channels -minuv-l 60 -multiscale  $obsid.ms

# Put thresholds up to 10 sigma. Keep pushing it down until we find an optimal threshold.


# This works, within a time of 4ish hours, depends on the number of w-terms.
wsclean -name ${obsid}_deeper -size 5000 5000 -niter 30000 -auto-threshold 8.0 \
-auto-mask 10.0 -pol I -weight uniform -scale 82asec -abs-mem 31 -j 12 -mgain 0.95 -minuv-l 60 -multiscale  $obsid.ms




