# asp_dem_creation

Scripts to create digital elevation models (DEMs) from satellite stereo-imagery for the COMET group in Oxford. 
wv3_single.sh -- operates on individual Worldview3 stereo pairs. 

This can be scaled by wrapping wv3_single_pair.sh in a batch script, where wv3_single_pair.sh is fed a different Worldview3 directory via the "wdir" variable. 
If the stereo_align step is enabled, all products should be aligned to the same global DEM and so aligned with eachother.
