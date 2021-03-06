#!/bin/bash

# Peel, selfcal and image data

start_time=`date +%s`

# Set default values for optional parameters
peel_threshold=50.0
pbeam_model=2016
sigma_final=1.0
sigma_mask=3.0
# edit for light clean
niter=1000000
#niter=25000
chgcentre=yes
#selfcal="no"
selfcal="yes"
keep_ms=no
multiscale=""
flag=yes
minuv=""

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

# Set obsid
#obsid=`sed "${SLURM_ARRAY_TASK_ID}q;d" $obsid_list | awk '{print $1}'`
obsid=` awk '{print $1}' $obsid_list`

# Set other parameters
#imsize=10000 # image size including the guard band
imsize=5000
#trim=8000 # final image size after trimming the edges which are uncleaned
#robust="-1.0" # Briggs weighting schemes to use
robust=0.0 # Briggs weighting schemes to use (for phase 2)
fwhm=75 # FWHM of Gaussian taper
absmem=61
ncpus=20
pols="I Q U V" # polarisations to generate using pbcorrect
allpols="I Q U V XX XY XYi YY" # polarisations to rescale
nchan="4 -join-channels" #number chans for subchans
#nchan=1 #number chans for subchans
subchans="MFS 0000 0001 0002 0003" # WSClean suffixes for subchannels and MFS
#subchans="MFS" # WSClean suffixes for subchannels and MFS
images="image" # kinds of image to rescale and upload to NGAS
model2=${$input_dir/$obsid/skymodelformat.txt}
echo $input_dir/$obsid/skymodelformat.txt
echo $model2
# Version number of this data reduction (based on WSClean parameters)
# 2.0 = Version 1.5, restoring with longest projected baseline
# 2.1 = Version 1.7, restoring with -fitbeam
version="2.1"

# Create output directory
if [ ! -e $output_dir ]; then
  mkdir $output_dir
fi

# Create snapshot directory
if [ -e $output_dir/$obsid ]; then
  echo "Error: Output directory $output_dir/$obsid already exists. Aborting."
  exit 1
else
  mkdir $output_dir/$obsid
  cd $output_dir/$obsid
fi

# Write input parameters to file for record
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
model = $model
model2 = $model2
version = $version
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

# Copy measurement set and metafits file to output directory
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

# Flag tiles if required
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

# -------------------------------------------------------------------------------------
# Peeling
# -------------------------------------------------------------------------------------

# Change phase centre of measurement set if required
if [ $chgcentre == "yes" ]; then
  $srun chgcentre -minw -shiftback $obsid.ms
fi

# -------------------------
# setting scale for phase 2 (0.55)
# -------------------------

#scale=`echo "1.1 / $chan" | bc -l`
#scale=${scale:0:8}
scale=0.04                                                                                                                                                                               
# -------------------------------------------------------------------------------------
# Apply self-calibration if required
# -------------------------------------------------------------------------------------

#imsize=5000

if [ $selfcal == "yes" ]; then

# Quick and dirty image-based clean to get the initial model for selfcal
#  $srun wsclean -name ${obsid}_initial -size $imsize $imsize -trim $trim $trim -niter 4000 -threshold 0.01 -pol xx,yy,xy,yx -weight briggs -1.0 -scale ${scale} -stopnegative -absmem ${absmem} -joinpolarizations -j $ncpus $obsid.ms
# with taper
#  $srun wsclean -name ${obsid}_initial -size $imsize $imsize -niter 4000 -threshold 0.01 -pol xx,yy,xy,yx -weight briggs $robust -taper-gaussian $fwhm -scale ${scale} -stopnegative -abs-mem ${absmem} -join-polarizations -j $ncpus $obsid.ms
##  $srun wsclean -name ${obsid}_initial -size $imsize $imsize -niter 4000 -threshold 0.01 -pol xx,yy,xy,yx -weight briggs $robust -scale ${scale} -channel-range 0,0 -stopnegative -abs-mem ${absmem} -join-polarizations -j $ncpus $obsid.ms
  wsclean -name ${obsid}_initial -size $imsize $imsize -niter 4000 -threshold 0.01 -apply-primary-beam -pol xx,yy,xy,yx -weight briggs $robust -scale ${scale} -stopnegative -abs-mem ${absmem} -join-polarizations -j $ncpus $obsid.ms
 if [[ ! -e ${obsid}_initial-XX-image.fits ]]; then
    echo "WSClean must have seg-faulted! PANIC!"
    exit 1
  fi


# have to send this to another script or aegean crashes unable to find Aegean tools
  aegean_snapshot.sh ${root}.fits bane compress
  rms=`rms_measure.py --middle --mean --boxsize=10 -f ${root}_rms.fits`

# Might as well add the rms to the headers since we've gone to the trouble of calculating it
  pyhead.py -u IMAGERMS $rms ${root}.fits
  if [[ ! -e ${root}_comp.vot ]]; then
    echo "Aegean failed to run on the initial image, so self-calibration will fail. Terminating the job now."
    exit 1
  fi

# Set Q, U, V to zero
  if [[ ! -d unused ]]; then
    mkdir unused
  fi
  mv ${obsid}_initcor-Q.fits unused/
  mv ${obsid}_initcor-U.fits unused/
  mv ${obsid}_initcor-V.fits unused/

# with taper
#  $srun wsclean -predict -name ${obsid}_initunc -size $imsize $imsize -pol xx,yy,xy,yx -weight briggs $robust -taper-gaussian $fwhm -scale ${scale} -abs-mem ${absmem} -j $ncpus $obsid.ms
# without taper
  wsclean -name ${obsid}_initunc -size $imsize $imsize -apply-primary-beam -pol xx,yy,xy,yx -weight briggs $robust -scale ${scale} -abs-mem ${absmem} -j $ncpus $obsid.ms

# self-cal
# Try minimum baseline = 60 m (30 lambda at 150 MHz = 2 m)
  calibrate -j $ncpus -minuv 60 -a 0.001 0.0001 -p phases.txt gains.txt $caldatacolumn $obsid.ms solutions.bin | tee calibrate.log

  flaggedchans=`grep "gains to NaN" calibrate.log | awk '{printf("%03d\n",$2)}' | sort | uniq | wc -l`
  if [[ $flaggedchans -gt 200 || ! -s solutions.bin ]]; then
    echo "More than a third of the channels were flagged!"
    echo "Will not apply calibration solutions or clean any more deeply."
    exit 1
  fi
  applysolutions $caldatacolumn -copy $obsid.ms solutions.bin

fi

# -------------------------------------------------------------------------------------
# Deep image
# -------------------------------------------------------------------------------------

# Re-run flagger to catch any broken channels after self-calibration
aoflagger -v -column CORRECTED_DATA $obsid.ms

# Super-deep clean with sub-bands
# ----------------------------------
#$srun wsclean -name ${obsid}_deeper -size $imsize $imsize -trim $trim $trim -niter $niter -auto-threshold $sigma_final -auto-mask $sigma_mask -pol XX,YY,XY,YX -weight briggs $robust -scale ${scale} -absmem $absmem -joinpolarizations -joinchannels -j $ncpus -mgain 0.85 -channelsout 4 $minuv $multiscale $obsid.ms
##$srun wsclean -name ${obsid}_deeper -size $imsize $imsize -niter $niter -auto-threshold $sigma_final -auto-mask $sigma_mask -pol XX,YY,XY,YX -weight briggs $robust -scale ${scale} -abs-mem $absmem -join-polarizations -j channel-range 0,0 $ncpus -mgain 0.95 -channels-out $nchan $minuv $multiscale $obsid.ms

wsclean -name ${obsid}_deeper -size $imsize $imsize -niter $niter -auto-threshold $sigma_final -auto-mask $sigma_mask -apply-primary-beam -pol XX,YY,XY,YX -weight briggs $robust -scale ${scale} -abs-mem $absmem -join-polarizations -j $ncpus -mgain 0.95 -channels-out $nchan $minuv $multiscale $obsid.ms

# added '-no-reorder' to speed things up with multiple major cycles
#$srun wsclean -name ${obsid}_deeper -size $imsize $imsize -niter $niter -auto-threshold $sigma_final -auto-mask $sigma_mask -pol XX,YY,XY,YX -weight briggs $robust -scale ${scale} -abs-mem $absmem -join-polarizations -j $ncpus -mgain 0.85 -channels-out $nchan $minuv $multiscale -no-reorder $obsid.ms
# with Gaussuian taper
#$srun wsclean -name ${obsid}_deeper -size $imsize $imsize -niter $niter -auto-threshold $sigma_final -auto-mask $sigma_mask -pol XX,YY,XY,YX -weight briggs $robust -taper-gaussian $fwhm -scale ${scale} -abs-mem $absmem -join-polarizations -j $ncpus -mgain 0.85 -channels-out $nchan $minuv $multiscale $obsid.ms

if [[ ! -e ${obsid}_deeper-MFS-XX-image.fits ]]; then
  echo "WSClean must have seg-faulted! PANIC!"
  exit 1
fi


# Update rms in header for Q,U,V images (not models!)
# (We will do I-MFS more carefully in a minute)
# Disadvantage is that the sub-channels of I are not done
# Quite a hard problem to fix without running Bane, since the noise varies over the map
for pol in $pols; do
  if [[ ${pol} != "I" ]]; then
    for subchan in $subchans; do
      rms=`rms_measure.py --middle -f ${obsid}_deeper-${subchan}-${pol}-image.fits`
      pyhead.py -u IMAGERMS $rms ${obsid}_deeper-${subchan}-${pol}-image.fits
    done
  fi
    # HACK SINCE WSCLEAN DOESN'T REPORT MFS IMAGE KEYS PROPERLY
    # DELETE THIS SECTION WHEN AO HAS FIXED THE BUG
  copy_metafitsheader.py -v -m ${obsid}_deeper-0001-${pol}-image.fits -i ${obsid}_deeper-MFS-${pol}-image.fits
done

# Source-finding
# Do all the calculations on the Stokes I MFS images, and apply to all pols and all sub-bands
root=${obsid}_deeper-MFS-I-image
aegean_snapshot.sh ${root}.fits bane compress
mv ${root}_comp.vot ${root}_${robust}_comp.vot
# Might as well add the rms to the headers since we've gone to the trouble of calculating it
rms=`rms_measure.py --middle --mean --boxsize=10 -f ${root}_rms.fits`
pyhead.py -u IMAGERMS $rms ${root}.fits
if [[ ! -e ${root}_${robust}_comp.vot ]]; then
  echo "Aegean failed to run on the deeper image, so there must be something very wrong with it. Terminating now."
  exit 1
else
  nsrc=`grep "<TR>" ${root}_${robust}_comp.vot | wc -l`
  if [[ $nsrc -lt 20 ]]; then
    echo "Fewer than 20 sources detected in the deep image; must be a really awful image. Terminating now."
    exit 1
  fi
fi

# Record fits keys
for pol in $allpols; do
  for imagetype in $images; do
    for subchan in $subchans; do
      deep=${obsid}_deeper-${subchan}-${pol}-${imagetype}
# Record fits keys
      rms=`pyhead.py -p IMAGERMS $deep.fits | awk '{print $3}'`
      if [[ $rms == "None" ]]; then
        rms=`rms_measure.py --middle -f $deep.fits`
        pyhead.py -u IMAGERMS $rms $deep.fits
      fi
      copy_metafitsheader.py  -v -m ${obsid}.metafits -i $deep.fits -e MJD,LST,HA,RA,DEC,DATESTRT
# HACK SINCE WSCLEAN DOESN'T REPORT MFS IMAGE KEYS PROPERLY
# DELETE THIS SECTION WHEN AO HAS FIXED THE BUG
      if [[ ${subchan} == "MFS" ]]; then
        copy_metafitsheader.py -v -m ${obsid}_deeper-0001-${pol}-${imagetype}.fits -i $deep.fits
      fi
# Rename file to match GLEAM output format
      newfilename=`wsclean2gleam.py -f $deep.fits -v $version`
      cp $deep.fits $newfilename
    done
  done
done

if [ $keep_ms == "no" ]; then
  rm -rf $obsid.ms
fi

# -------------------------------------------------------------------------------------

end_time=`date +%s`
duration=`echo "$end_time-$start_time" | bc -l`
echo "Total runtime = $duration sec"

# Move output and error files to output directory
mv $MYDATA/image.o${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} $MYDATA/image.e${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} .

exit 0
