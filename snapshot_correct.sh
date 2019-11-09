#!/bin/bash -l

# Apply flux scale and ionospheric corrections to individual snapshot images

#SBATCH --account=mwasci
#SBATCH --partition=workq
#SBATCH --time=06:00:00
#SBATCH --nodes=1
#SBATCH --output=/astro/mwasci/nseymour/snapshot_correct.o%A_%a
#SBATCH --error=/astro/mwasci/nseymour/snapshot_correct.e%A_%a
#SBATCH --export=NONE

# module load mwa_profile
# #############SBATCH --mem=62gb

stilts='java -jar /group/mwa/software/stilts/stilts.jar'

start_time=`date +%s`

# Read the options
TEMP=`getopt -o a:b:c:d: --long input_dir:,output_dir:,obsid_list:,chan: -- "$@"`
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
if [ $chan != "69" ] && [ $chan != "93" ] && [ $chan != "121" ] && [ $chan != "145" ] && [ $chan != "169" ]; then
  echo "Error: chan should be set to 69, 93, 121, 145 or 169. Aborting."
  exit 1
fi

# Set obsid
obsid=`sed "${SLURM_ARRAY_TASK_ID}q;d" $obsid_list | awk '{print $1}'`

# Check existence of files required for flux scale and ionospheric corrections
gleam_catalogue=/group/mwasci/code/MWA_Tools/catalogues/GLEAMIDR6_published.fits # GLEAM IDR6 catalogue for flux scale corrections
# default is 8
sclip=6
# trying 30 to see if it will complete (default 75)
nsrc_target=40 # Minimum number of sources > "sclip" sigma required to be detected in snapshot
gp_mim_file=/group/mwa/software/MWA_Tools/MWA_Tools/gleam_scripts/catalogue/gp.mim # Galactic plane .mim region file
mrc_catalogue=/group/mwasci/code/MWA_Tools/catalogues/MRC_extended.vot # MRC catalogue for ionospheric corrections
if [ ! -e $gleam_catalogue ]; then
  echo "Error: GLEAM catalogue $gleam_catalogue does not exist, aborting."
  exit 1
fi
if [ ! -e $gp_mim_file ]; then
  echo "Error: Galactic plane .mim region file $gp_mim_file does not exist, aborting."
  exit 1
fi
if [ ! -e $mrc_catalogue ]; then
  echo "Error: MRC catalogue $mrc_catalogue does not exist, aborting."
  exit 1
fi

# Set other input parameters
ncpus=20
maxsize=9000

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
fi

# Write input parameters to file for record
cat >> $output_dir/$obsid/input_parameters_snapshot_correct.txt <<EOPAR
input_dir = $input_dir
output_dir = $output_dir
obsid_list = $obsid_list
chan = $chan
ncpus = $ncpus
gleam_catalogue = $gleam_catalogue
nsrc_target = $nsrc_target
gp_mim_file = $gp_mim_file
mrc_catalogue = $mrc_catalogue
maxsize = $maxsize
EOPAR

if [[ $chan -eq 69 ]]; then
  freq[1]="072-080MHz"
  freq[2]="080-088MHz"
  freq[3]="088-095MHz"
  freq[4]="095-103MHz"
  freq[5]="072-103MHz"
elif [[ $chan -eq 93 ]]; then
  freq[1]="103-111MHz"
  freq[2]="111-118MHz"
  freq[3]="118-126MHz"
  freq[4]="126-134MHz"
  freq[5]="103-134MHz"
elif [[ $chan -eq 121 ]]; then
  freq[1]="139-147MHz"
  freq[2]="147-154MHz"
  freq[3]="154-162MHz"
  freq[4]="162-170MHz"
  freq[5]="139-170MHz"
elif [[ $chan -eq 145 ]]; then
  freq[1]="170-177MHz"
  freq[2]="177-185MHz"
  freq[3]="185-193MHz"
  freq[4]="193-200MHz"
  freq[5]="170-200MHz"
elif [[ $chan -eq 169 ]]; then
  freq[1]="200-208MHz"
  freq[2]="208-216MHz"
  freq[3]="216-223MHz"
  freq[4]="223-231MHz"
  freq[5]="200-231MHz"
fi

subband[1]="0000"
subband[2]="0001"
subband[3]="0002"
subband[4]="0003"
subband[5]="MFS"

# Copy Stokes XX & YY 7.68 MHz subband images to output directory
cd $input_dir/$obsid
for ((i=1; i<=(4); i++ )); do
  Xfile[$i]=$(ls *${freq[$i]}_XX_*v2.1.fits)
  Yfile[$i]=$(ls *${freq[$i]}_YY_*v2.1.fits)
  if [ -e ${Xfile[$i]} ]; then
    cp ${Xfile[$i]} $output_dir/$obsid
  else
    echo "Error: input image $input_dir/$obsid/${Xfile[$i]} does not exist. Aborting."
    exit 1
  fi
  if [ -e ${Yfile[$i]} ]; then
    cp ${Yfile[$i]} $output_dir/$obsid
  else
    echo "Error: input image $input_dir/$obsid/${Yfile[$i]} does not exist. Aborting."
    exit 1
  fi
done

# Copy Stokes I 30.72 MHz subband image to output directory
Ifile=$(ls *${freq[5]}_I_*v2.1.fits)
if [ -e $Ifile ]; then
  cp $Ifile $output_dir/$obsid
else
  echo "Error: input image $input_dir/$obsid/$Ifile does not exist. Aborting."
  exit 1
fi

# Copy metafits file to output directory
cd $output_dir/$obsid
if [ -e $input_dir/$obsid/$obsid.metafits ]; then
  cp $input_dir/$obsid/$obsid.metafits .
else
# updated Andrew's correction
  wget "http://mwa-metadata01.pawsey.org.au/metadata/fits?obs_id=${obsid}&min_bad_dipoles=5" -O $obsid.metafits
#  make_metafits.py -g $obsid -o $obsid.metafits
fi

# -------------------------------------------------------------------------------------
# Calculate RMS noise and add to fits header
# -------------------------------------------------------------------------------------

for file in *.fits; do
  BANE --cores=$ncpus --compress $file
  rms=$(rms_measure.py --middle --mean --boxsize=20 -f ${file%%.fits}_rms.fits)
  pyhead.py -u IMAGERMS $rms $file
  rm -f ${file%%.fits}_rms.fits ${file%%.fits}_bkg.fits
done

# -------------------------------------------------------------------------------------
# Apply flux scale corrections
# -------------------------------------------------------------------------------------

# Get snapshot RA (extract RA from metafits file)
ra=$(fitshdr $obsid.metafits | grep 'RA of pointing center' | awk '{print $3}')

# Get snapshot Dec (extract using get_central_dec.py, round to nearest integer)
dec=`get_central_dec.py -f ${Xfile[1]} --round`

# Get image size
imsize=$(fitshdr ${Xfile[1]} | grep NAXIS1  | awk '{print $3}')

(( imin=($imsize-$maxsize)/2 +1 ))
(( imax=$imin+$maxsize -1 ))
(( mid=$imsize/2 )) 
echo "checking size = $maxsize, $imsize, $imin, $imax, $mid"

# Make primary-beam-corrected XX and YY images in order to measure correction w.r.t. GLEAM year 1 catalogue
for ((i=1; i<=(4); i++ )); do
# Generate the primary beam
  make_beam.py -v -f ${Xfile[$i]} -m $obsid.metafits --model=2016
# Rename primary beam images
  for pol in XX YY; do
    file=`echo ${Xfile[$i]} | sed "s/.fits/_beam${pol}.fits/"`
    mv $file beam-${subband[$i]}-${pol}.fits
  done
done

# Apply XX and YY primary beam corrections for each subband
for ((i=1; i<=(4); i++ )); do
  Xcorr[$i]=`echo ${Xfile[$i]} | sed "s/.fits/_pb.fits/"`
  Ycorr[$i]=`echo ${Yfile[$i]} | sed "s/.fits/_pb.fits/"`
  python /group/mwa/software/MWA_Tools/MWA_Tools/gleam_scripts/mosaics/scripts/pb_correct.py --input ${Xfile[$i]} --output ${Xcorr[$i]} --beam beam-${subband[$i]}-XX.fits
  python /group/mwa/software/MWA_Tools/MWA_Tools/gleam_scripts/mosaics/scripts/pb_correct.py --input ${Yfile[$i]} --output ${Ycorr[$i]} --beam beam-${subband[$i]}-YY.fits
done

# Create regions file for source finding on snapshots
MIMAS -o ${obsid}_fov.mim +c $ra $dec 40
MIMAS -o ${obsid}_nogal.mim +r ${obsid}_fov.mim -r $gp_mim_file

# Apply flux scale correction to Stokes XX and YY 7.68 MHz subband images
for ((i=1; i<=(4); i++ )); do
  for file in ${Xcorr[$i]} ${Ycorr[$i]}; do
# Run Aegean on the pb-corrected XX and YY snapshots
    root=`echo $file | sed "s/.fits//"`
    vot=${root}_comp.vot
    echo "Source-finding on $file."
    BANE --cores=$ncpus --compress $file
    aegean --region=${obsid}_nogal.mim --cores=$ncpus --seedclip=$sclip --maxsummits=5 --noise=${root}_rms.fits --background=${root}_bkg.fits --out=/dev/null --table=$root.vot $file
# Correct flux scale of snapshot image by cross-matching sources detected in the image with the GLEAM IDR6 catalogue
    if [[ -e $vot ]]; then
      nsrc=`grep "<TR>" $vot | wc -l`
      if [[ $nsrc -ge $nsrc_target ]]; then
# Correction is to be applied to *original* (i.e. not primary beam corrected) XX and YY snaphots
        if [ "$file" == "${Xcorr[$i]}"  ]; then
          rm $file
          file=${Xfile[$i]}
        elif [ "$file" == "${Ycorr[$i]}"  ]; then
          rm $file
          file=${Yfile[$i]}
        fi
# Apply flux scale correction
        correct_gleam_flux.py --input_image=$file --input_catalogue=$vot --input_ref_catalogue=$gleam_catalogue
# Update IMAGERMS in flux scale corrected image (correct_gleam_flux.py leaves IMAGERMS unchanged so it needs to be multiplied by the flux scale correction factor)
        corr_factor=$(tail -n 1 ${file%%.fits}_flux_corrections.txt | awk '{print $2}')
        noise=$(pyhead.py -p IMAGERMS ${file%%.fits}_fluxscaled.fits | awk '{print $3}')
        noise=`echo "$noise*$corr_factor" | bc -l`
        pyhead.py -u IMAGERMS $noise ${file%%.fits}_fluxscaled.fits
	if [[ $imsize -gt $maxsize ]]; then
	    echo "Cropping snapshot${file%%.fits}_fluxscaled.fits as size >=  $maxsize"
	    mv ${file%%.fits}_fluxscaled.fits ${file%%.fits}_fluxscaled_orig.fits
	    getfits -v -o ${file%%.fits}_fluxscaled.fits ${file%%.fits}_fluxscaled_orig.fits $mid $mid -x $maxsize $maxsize
	fi
      else
        echo "No flux scale correction applied to $file as only $nsrc sources > $sclip sigma were detected in the image (minimum required is ${nsrc_target})"
        echo "Check image quality."
      fi
    else
      echo "No flux scale correction applied to $file as $file didn't source-find correctly."
      echo "Check image quality."
    fi
  done
done

# Apply flux scale correction to Stokes I 30.72 MHz subband image
# Run Aegean on the I snapshot
root=`echo $Ifile | sed "s/.fits//"`
vot=${root}_comp.vot
echo "Source-finding on $Ifile."
BANE --cores=$ncpus --compress $Ifile
aegean --region=${obsid}_nogal.mim --cores=$ncpus --seedclip=$sclip --maxsummits=5 --noise=${root}_rms.fits --background=${root}_bkg.fits --out=/dev/null --table=$root.vot $Ifile
# Correct flux scale of snapshot image by cross-matching sources detected in the image with the GLEAM IDR6 catalogue
if [[ -e $vot ]]; then
  nsrc=`grep "<TR>" $vot | wc -l`
  if [[ $nsrc -ge $nsrc_target ]]; then
# Apply flux scale correction
    correct_gleam_flux.py --input_image=$Ifile --input_catalogue=$vot --input_ref_catalogue=$gleam_catalogue
# Update IMAGERMS in flux scale corrected image (correct_gleam_flux.py leaves IMAGERMS unchanged so it needs to be multiplied by the flux scale correction factor)
    corr_factor=$(tail -n 1 ${root}_flux_corrections.txt | awk '{print $2}')
    noise=$(pyhead.py -p IMAGERMS ${root}_fluxscaled.fits | awk '{print $3}')
    noise=`echo "$noise*$corr_factor" | bc -l`
    pyhead.py -u IMAGERMS $noise ${root}_fluxscaled.fits
# crop image if > 8k x8k
   if [[ $imsize -gt $maxsize ]]; then
       echo "Cropping snapshot ${root}_fluxscaled.fits as size >= $maxsize"
       mv ${root}_fluxscaled.fits ${root}_fluxscaled_orig.fits
       getfits -v -o ${root}_fluxscaled.fits ${root}_fluxscaled_orig.fits $mid $mid -x $maxsize $maxsize
   fi
  else
    echo "No flux scale correction applied to $Ifile as only $nsrc sources > $sclip sigma were detected in the image (minimum required is ${nsrc_target})"
    echo "Check image quality."
  fi
else
  echo "No flux scale correction applied to $Ifile as $Ifile didn't source-find correctly."
  echo "Check image quality."
fi

# -------------------------------------------------------------------------------------
# Apply ionospheric corrections
# -------------------------------------------------------------------------------------
echo "Starting ionospheric corrections."
echo "Cross-matching catalogues."

# Set MWA catalogue to Aegean N sigma catalogue for I 30.72 MHz sub-band image
mwa_catalogue=`echo $Ifile | sed "s/.fits//"`
mwa_catalogue=${mwa_catalogue}_comp.vot

# Filter MRC catalogue
# Exclude sources that have a flag in the Mflag column
# Also add a column with the position angle; set this to 0.0
#topcat -stilts tpipe \
$stilts tpipe \
ifmt=votable \
ofmt=votable \
in=$mrc_catalogue \
out=t.vot \
cmd='select "NULL_MFLAG"' \
cmd='addcol "PA" 0.0'

# Match MWA and MRC catalogues
#topcat -stilts tmatch2 \
$stilts tmatch2 \
ifmt1=votable \
ifmt2=votable \
ofmt=votable \
in1=t.vot \
in2=$mwa_catalogue \
out=t2.vot \
matcher=skyellipse \
params=30 \
values1="_RAJ2000 _DEJ2000 e_RA2000 e_DE2000 PA" \
values2="ra dec a b pa"

# Remove sources that have abs(delRA)>=1.0
#topcat -stilts tpipe \
$stilts tpipe \
ifmt=votable \
ofmt=votable \
in=t2.vot \
out=mwa_mrc_xmatch_table.vot \
cmd='addcol "delRA" "_RAJ2000-ra"' \
cmd='addcol "delDec" "_DEJ2000-dec"' \
cmd='select "abs(delRA)<1.0"'

rm -f t.vot t2.vot

# Run warping code on all I, XX and YY snaphots
echo "Running fitswarp"
#fits_warp.py --plot --xm mwa_mrc_xmatch_table.vot --infits '*fluxscaled.fits' --ra1 ra --dec1 dec --ra2 _RAJ2000 --dec2 _DEJ2000 --suffix warp
# turn off plot
fits_warp.py --xm mwa_mrc_xmatch_table.vot --infits '*fluxscaled.fits' --ra1 ra --dec1 dec --ra2 _RAJ2000 --dec2 _DEJ2000 --suffix warp
# break into separate runs:
#fits_warp.py --xm mwa_mrc_xmatch_table.vot --infits '*XX*fluxscaled.fits' --ra1 ra --dec1 dec --ra2 _RAJ2000 --dec2 _DEJ2000 --suffix warp
#fits_warp.py --xm mwa_mrc_xmatch_table.vot --infits '*YY*fluxscaled.fits' --ra1 ra --dec1 dec --ra2 _RAJ2000 --dec2 _DEJ2000 --suffix warp
#fits_warp.py --xm mwa_mrc_xmatch_table.vot --infits '*I*fluxscaled.fits' --ra1 ra --dec1 dec --ra2 _RAJ2000 --dec2 _DEJ2000 --suffix warp

# We won't update IMAGERMS in the FITS header after applying the warping correction as running BANE is expensive and the warping correction
# is not expected to change the RMS noise (or at least have a minimal effect)

# -------------------------------------------------------------------------------------

end_time=`date +%s`
duration=`echo "$end_time-$start_time" | bc -l`
echo "Total runtime = $duration sec"

# Move output and error files to output directory
mv /astro/mwasci/$USER/snapshot_correct.o${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} /astro/mwasci/$USER/snapshot_correct.e${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} .

exit 0
