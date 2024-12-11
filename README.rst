===================
CosmoMC_CDE
===================
:CosmoMC:  Fortran 2008 parallelized MCMC sampler (general and cosmology)
:Homepage: http://cosmologist.info/cosmomc/


Description
=============================

CosmoMC_CDE is a fork of `CosmoMC Planck 2018 <https://github.com/cmbant/CosmoMC/tree/planck2018>`_. It utilizes an eighth-order Runge-Kutta algorithm to evaluate the Friedmann equation and incorporates the perturbed Klein-Gordon equation for the Cascading Dark Energy (CDE) model `paper <https://arxiv.org/pdf/2208.07631>`_. Furthermore, DESI BAO and Pantheon+ datasets are incorporated.  


Citing CosmoMC_CDE
=============================

If you use CosmoMC_CDE for your scientific work, please cite the following paper:

-   | *Cascading Dark Energy* 

    | Kazem Rezazadeh, Amjad Ashoorioon, Daniel Grin

    | `arXiv:2208.07631 [astro-ph.CO] <https://arxiv.org/pdf/2208.07631>`_

as well as the original CAMB `paper <https://arxiv.org/abs/astro-ph/9911177>`_ and CosmoMC `paper <https://arxiv.org/abs/astro-ph/0205436>`_.




Changes
=============================

The primary changes are focused on `equation_ppf_CDE.f90 <https://github.com/m-khorasani/CosmoMC_CDE/blob/planck2018/camb/equations_ppf_CDE.f90>`_ and `supernovae_JLA.f90 <https://github.com/m-khorasani/CosmoMC_CDE/blob/planck2018/source/supernovae_JLA.f90>`_. The former describes the numerical solutions for the eighth-order Runge-Kutta algorithm and the perturbed Klein-Gordon equation, while the latter has been modified to update the inverse covariance matrix of supernovae to incorporate the Pantheon+ datasets into the code. You can review all changes in these two files, as well as in all other relevant files within the block:

!---CDE Start

!---CDE End

Authors list
=============================
Main Developer:

- Mohsen Khorasani, Email : `<khorasani@ipm.ir>`_

Original Code Developers:

- Kazem Rezazadeh

* Daniel Grin

+ Amjad Ashoorioon

Repo created and maintained by Mohsen Khorasani. If you find any bugs in the code, please contact Mohsen Khorasani at `<khorasani@ipm.ir>`_. 

Branches
=============================

The master branch contains latest changes to the main release version.

.. image:: https://secure.travis-ci.org/cmbant/CosmoMC.png?branch=master
  :target: https://secure.travis-ci.org/cmbant/CosmoMC/builds

This branch has an old CAMB version as used by the Planck 2018 parameter analysis.

=============

.. raw:: html

    <a href="http://www.sussex.ac.uk/astronomy/"><img src="https://cdn.cosmologist.info/antony/Sussex.png" height="170px"></a>
    <a href="http://erc.europa.eu/"><img src="https://erc.europa.eu/sites/default/files/content/erc_banner-vertical.jpg" height="200px"></a>
