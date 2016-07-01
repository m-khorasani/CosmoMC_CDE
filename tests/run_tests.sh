cd /cosmomc/forutils
make ReleaseMPI

cd /cosmomc
wget http://irsa.ipac.caltech.edu/data/Planck/release_2/software/COM_Likelihood_Code-v2.0.R2.00.tar.bz2
tar xvfj COM_Likelihood_Code-v2.*.tar.bz2
cd plc-2.0
./waf configure --install_all_deps
./waf install
source ./bin/clik_profile.sh
cd ..
wget http://irsa.ipac.caltech.edu/data/Planck/release_2/software/COM_Likelihood_Data-baseline_R2.00.tar.gz
tar xvfj COM_Likelihood_Data-baseline_R2.00.tar.gz
ln -s $(pwd)/plc_2.0 ./data/clik
rm -f COM_Likelihood_Data-baseline_R2.00.tar.gz

make ReleaseMPI

mpirun -np 1 ./cosmomc test.ini

mpirun -np 1 ./cosmomc test_planck.ini
rc=$?


exit $rc

