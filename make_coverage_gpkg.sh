#!/bin/bash


# requires to_shapefile.sh (make sure permissions correct with chmod 774)
# make sure gdal conda environment activated or that latest version of gdal has priority in $PATH
# assuming directory structure with one image per dir (i.e NO *p_002*)
for dir in 7*1; do cp $dir/*_P_*/*KMZ . ; done
../kmz2shp.sh


# strip ones
for f in *.shp ;do mv $f  `echo  $f |  awk -F"-" '{print $1}'`.shp ; done
for f in *.dbf ;do mv $f  `echo  $f |  awk -F"-" '{print $1}'`.dbf ; done
for f in *.prj ;do mv $f  `echo  $f |  awk -F"-" '{print $1}'`.prj ; done
for f in *.shx ;do mv $f  `echo  $f |  awk -F"-" '{print $1}'`.shx ; done
# create gpkg
for f in *.shp ; do ogr2ogr -f gpkg -append -update coverage.gpkg $f ;done

#tidy

mkdir shp
mv *.shp shp/
mv *.dbf shp/
mv *.prj shp/
mv *.shx shp/

mkdir kmz
mv *.KMZ kmz/
rm *.KML
