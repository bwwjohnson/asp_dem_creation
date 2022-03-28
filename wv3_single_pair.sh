#!/bin/bash
 
# Created by J. Hollingsworth
# Modifications by B. Johnson in March 2022 
# email benedict.johnson@st-annes.ox.ac.uk

# User input required to set up input files etc below. In addition to this, you should tweak parameters in stereo and point2dem.
# Running this script on a server machine is better for speed. 

### Summary of process (turn steps off to avoid repetative processing (e.g. if fiddling with point2dem parameters, turn off generate_wv, mapproject and stereo)):
# 1. generate_wv: put together the tiled Worldview3 images to make a the two stereo pair GeoTIFFs
# 2. mapproject: orthorectify these images using low-res reference DEM. This helps stereo correlate the two images and reduces gaps.
# 3. stereo: searches the two images for matching points, and uses triangulation to produce the point cloud
# 4. rasterize: uses point2dem to filter the point cloud for outliers and grids it to make a DEM
# 5. stereo_alignment: aligns the ASP DEM with a standard global DEM (e.g. ALOS). Then differences the DEMs. Check this difference map for systematic errors
# 6. ortho: create orthoimages using the raw imagery and the ASP DEM

########################## USER INPUT REQUIRED BELOW ###########################
########################## CHANGE WHEN YOU FIRST USE THE SCRIPT ################
### check StereoPipeline path -- adapt this to your StereoPipeline path
[[ ":$PATH:" != *":/home/cometsoft/StereoPipeline/bin:"* ]] && PATH="/home/cometsoft/StereoPipeline/bin:${PATH}"
### variables for making the reference DEM
big_dem=/home/cometraid13/benj/phd/GIS/data/topo/jaxa_from_cometraid4/jaxa_merge_pamir.tif # change to your reference DEM path
demdir="/home/cometraid13/benj/khait/asp/jaxa" # change to your clipped DEM path
clip_polygon=ref_dem_clip # polygon for clipping your large DEM -- create yourself in QGIS
clipped_dem=$demdir/jaxa_ref
dem=${clipped_dem}_utm42.tif  # 30m DEM for differencing (to check stereo process has completed successfully)
demmp=${clipped_dem}_utm42_150.tif # downsampled DEM for mapprojecting before stereo
epsg="32642" # NUTM42 -- change to your UTM zone
### computer processing variables 
processes="4"
threads="12"
mem_lim="300000"  # memory limit in mb -- change to fit your RAM availability

########################## CHANGE ON A RUN-BY-RUN BASIS #####################
### AOI (for cropping) -- feed lon/lat here
# LL="70.55 39.15" #= entire region (all overlaps)
# UR="71.05 39.29"
# LLutm=$(echo $LL | gdaltransform -s_srs EPSG:4326 -t_srs EPSG:$epsg | awk '{print $1,$2}')
# URutm=$(echo $UR | gdaltransform -s_srs EPSG:4326 -t_srs EPSG:$epsg | awk '{print $1,$2}')
# EXTENTS=$(echo $LLutm $URutm)

# alternatively give extents in UTM coords (minX minY maxX maxY)
EXTENTS="645898 4339044 647514 4339768"

# what to run?... 0 = no | 1 = yes
create_refdem="0"
generate_wv="1"
mapproject="1"
stereo="1"
rasterize="1"
stereo_alignment="1"
ortho="1"

# set the image dir
wdir="/home/cometraid13/benj/khait/014162243010_01/014162243010_01_P002_PAN"
# set the run name
runid=sgm0.3_p002p004_overlap
# set resolution (m)
resmp="0.3" # res of mapproj images used for stereo (likely is same as resdem)
res="0.3" # res of the final orthos
resdem="0.3" # res of the final DEM
########################## END OF USER INPUT ################
if (($create_refdem == 1 )) ; then
	# prepare your reference DEM
	rm $clipped_dem*.tif
	echo "clip the dem"
	gdalwarp -of GTiff -cutline ${clip_polygon}.shp -cl $clip_polygon -crop_to_cutline -co COMPRESS=DEFLATE -co PREDICTOR=2 -co ZLEVEL=9 $big_dem $clipped_dem_wgs84
	echo "wgs84 --> UTM"
	gdalwarp -s_srs EPSG:4326 -t_srs EPSG:$epsg -r bilinear -co COMPRESS=DEFLATE -co PREDICTOR=2 -co ZLEVEL=9 -of GTiff ${clipped_dem}_wgs84.tif ${clipped_dem}_utm42.tif
	echo "downsample"
	gdalwarp -tr 150 150 -r average -of GTiff ${clipped_dem}_utm42.tif ${clipped_dem}_utm42_150.tif
	echo "oversample 150m dem, interpolate w/ cubic spline to make smoothed 30m dem"
	gdalwarp -tr 30 30 -r cubicspline -of GTiff ${clipped_dem}_utm42_150.tif ${clipped_dem}_utm42_smooth.tif
	rm ${clipped_dem}_wgs84.tif 
fi
#####################################
# lets go...
if (($generate_wv == 1 )) ; then
	cd $wdir
	# merge tiles
	pair=$(ls *XML)
	left=$(echo $pair | awk '{print $1}' | sed "s@.XML@@g")
	right=$(echo $pair | awk '{print $2}' | sed "s@.XML@@g")
	leftp=$(echo $left | sed "s@-@ @g" | awk '{print $1}')
	rightp=$(echo $right | sed "s@-@ @g" | awk '{print $1}')
	echo variables assigned
	gdalwarp -multi -wo NUM_THREADS=val/ALL_CPUS -co BIGTIFF=YES *${leftp}*.TIF $left.TIF
	echo gdalwarp left done
	gdalwarp -multi -wo NUM_THREADS=val/ALL_CPUS  -co BIGTIFF=YES *${rightp}*.TIF $right.TIF
	echo gdalwarp right done
	# no wv_correct needed for WV03 + mosaicing is done via gdalwarp (because the RPCs are delivered for the entire tile, a la Pleiades)
fi #generate_wvl


#####################################
# assign images
pair=$(ls *XML)
L=$(echo $pair | awk '{print $1}' | sed "s@.XML@@g").TIF
R=$(echo $pair | awk '{print $2}' | sed "s@.XML@@g").TIF


#####################################
## mapproject... for easier stereo matching
if (($mapproject == 1 )) ; then
	echo "mapproject..."
	mkdir -p $wdir/asp
	cd $wdir/asp
	rm -r $wdir/asp/$runid
	mkdir -p $wdir/asp/$runid
	for f in $(echo $L $R) ; do
		mapproject -t rpc $demmp $wdir/$f.TIF $wdir/$f.XML $runid/${f}_MP.tif --t_projwin $EXTENTS --nodata-value -250 --num-processes $processes --threads $threads --tr $resmp
	done
fi #mapproject


#####################################
## run stereo
if (($stereo == 1 )) ; then
	echo "stereo..."
	cd $wdir/asp
	out=$(echo "$runid/${L}__${R}")
	rm -r $out  # CAREFUL!
	session="-t rpcmaprpc --alignment-method none"
	# run stereo...
	filtering="--rm-cleanup-passes 1 --filter-mode 2 --rm-threshold 3.5 --rm-min-matches 50 --rm-half-kernel 9 9"
	# sgm correlation
	parallel_stereo $session $runid/${L}_MP.tif $runid/${R}_MP.tif $runid/${L}_MP.RPB $runid/${R}_MP.RPB $out/dem $demmp --corr-timeout 600 --stereo-algorithm 2 --corr-kernel 7 7 --cost-mode 3 --subpixel-mode 12 --corr-memory-limit-mb $mem_lim --threads-multiprocess $threads --processes $processes --xcorr-threshold -1 --min-xcorr-level 1 --corr-seed-mode 1 --sgm-collar-size 512 --corr-tile-size 2048 --min-num-ip 10 --nodata-value 0  $filtering --num-matches-from-disparity 1000
	# block matching correlator
	# parallel_stereo $session $runid/${L}_MP.tif $runid/${R}_MP.tif $runid/${L}_MP.RPB $runid/${R}_MP.RPB $out/dem $demmp --corr-timeout 600 --stereo-algorithm 0 --corr-kernel 25 25 --cost-mode 2 --subpixel-mode 2 --subpixel-kernel 25 25 --corr-memory-limit-mb $mem_lim --threads-multiprocess $threads --processes $processes --xcorr-threshold 2 --corr-seed-mode 1 --sgm-collar-size 512 --corr-tile-size 2048 --min-num-ip 30 --nodata-value 0  $filtering --num-matches-from-disparity 1000
fi # stereo

#####################################
## rasterize point cloud > DEM
if (($rasterize == 1 )) ; then
	echo "rasterize..."
	cd $wdir/asp
	# rasterize DEM
	out=$(echo "$runid/${L}__${R}")
	point2dem --t_srs "EPSG:$epsg" --tr $resmp $out/dem-PC.tif --median-filter-params 9 9 --dem-hole-fill-len 150 --erode-length 0 --nodata-value -250 --tif-compress None --errorimage --threads 8 --remove-outliers-params 85 3
fi # rasterize

#####################################
## align each DEM independently to AW3D30
if (($stereo_alignment == 1 )) ; then
	echo "#### pc_align..."
	cd $wdir/asp
	out=$(echo "$runid/${L}__${R}")
	# get extents of stereo-dem (at 30m grid size)
	EXTENTS=$(gdalinfo $out/dem-DEM.tif | awk '/(Lower Left)|(Upper Right)/' | awk '{gsub(/,|\)|\(/," ");print $3 " " $4}' | sed ':a;N;$!ba;s/\n/ /g')
	echo "#### crop reference DEM to same size"
	gdalwarp -te $EXTENTS -tr 30 30 -tap $dem $out/ref_crop.tif -overwrite
	echo "#### align reference DEM to stereo-dem (best if low-res is aligned to high-res... we will use the inverse transform later)"
	pc_align --max-displacement 150 --alignment-method point-to-plane $out/dem-DEM.tif $out/ref_crop.tif --save-inv-transformed-reference-points -o $out/trans --outlier-ratio 0.85 --num-iterations 1000 --highest-accuracy --threads $threads --max-num-source-points 1000000
	# re-rasterize transformed pointcloud
	point2dem --t_srs "$proj" --tr $resmp $out/trans-trans_reference.tif --median-filter-params 9 9 --dem-hole-fill-len 150 --erode-length 0 --nodata-value 0 --tif-compress None --errorimage --remove-outliers-params 95 3 --threads $threads --max-valid-triangulation-error 15.0 #trans-trans_reference-DEM.tif
	mv $out/trans-trans_reference-DEM.tif $out/dem-DEM_aligned.tif
	echo "#### difference aligned stereo-DEM with reference (quick quality control assessment)"
	gdalwarp -tr 30 30 -r average -te $EXTENTS $out/dem-DEM_aligned.tif $out/dem-DEM_aligned_30m.tif -overwrite -srcnodata 0 -dstnodata 0 # -tap 
	geodiff $out/ref_crop.tif $out/dem-DEM_aligned_30m.tif -o  $out/diff_aligned
	echo "#### transform cameras (so they match the aligned DEM)"
	cp $out/dem-disp-${L}___${R}_.match $out/ba1-${L}__${R}.match
	bundle_adjust -t rpc --force-reuse-match-files --skip-matching $wdir/$L.TIF $wdir/$R.TIF $wdir/$L.xml $wdir/$R.xml -o $out/ba1 --datum wgs84 --threads $threads --initial-transform $out/trans-inverse-transform.txt --max-iterations 0 --robust-threshold 0.5 --num-passes 1
	echo "#### mapproject to get final ortho"
	for f in $(echo $L $R) ; do
		mapproject -t rpc $out/dem-DEM_aligned.tif $wdir/$f.TIF $wdir/$f.xml $runid/${f}_ortho_aligned.tif  --nodata-value -250 --threads 4  --tr $res --bundle-adjust-prefix $out/ba1
	done
fi # stereo_alignment
#####################################