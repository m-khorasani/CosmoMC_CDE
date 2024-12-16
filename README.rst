===================
CosmoMC_CDE
===================

Description
=============================

CosmoMC_CDE is a fork of `CosmoMC Planck 2018 <https://github.com/cmbant/CosmoMC/tree/planck2018>`_. It utilizes an eighth-order Runge-Kutta algorithm to evaluate the Friedmann equation and incorporates the perturbed Klein-Gordon equation for the Cascading Dark Energy (CDE) model `paper <https://arxiv.org/pdf/2208.07631>`_. Furthermore, DESI BAO and Pantheon+ datasets are incorporated.  


Citing CosmoMC_CDE
=============================

If you use CosmoMC_CDE for your scientific work, please cite the following paper:

-   | *Cascading Dark Energy* 

    | Kazem Rezazadeh, Amjad Ashoorioon, Daniel Grin

    | `ApJ 975 137, 2024 <https://iopscience.iop.org/article/10.3847/1538-4357/ad7b16>`_

as well as the original CAMB `paper <https://arxiv.org/abs/astro-ph/9911177>`_ and CosmoMC `paper <https://arxiv.org/abs/astro-ph/0205436>`_.




Changes
=============================

The main changes are focused on `equation_ppf_CDE.f90 <https://github.com/m-khorasani/CosmoMC_CDE/blob/planck2018/camb/equations_ppf_CDE.f90>`_ and `supernovae_JLA.f90 <https://github.com/m-khorasani/CosmoMC_CDE/blob/planck2018/source/supernovae_JLA.f90>`_. The former describes the numerical solutions for the eighth-order Runge-Kutta algorithm and the perturbed Klein-Gordon equation, and the latter has been modified to update the inverse covariance matrix of supernovae to incorporate the Pantheon+ datasets into the code. You can review all changes in these two files, as well as in all other relevant files within the block:

!---CDE Start

!---CDE End

Authors list
=============================
Main Developer:

- `Mohsen Khorasani <https://ipm.ac.ir/Visitorpage.jsp?VisitsCode=EP2400015>`_, Email : `<khorasani@ipm.ir>`_

Original Code Developers:

- `Kazem Rezazadeh <https://www.ipm.ac.ir/personalinfo.jsp?PeopleCode=IP2000025>`_

* `Daniel Grin <https://www.haverford.edu/users/dgrin>`_

+ `Amjad Ashoorioon <https://www.ipm.ac.ir/personalinfo.jsp?PeopleCode=IP1800021>`_

Repo created and maintained by Mohsen Khorasani. If you find any bugs in the code, please contact Mohsen Khorasani at `<khorasani@ipm.ir>`_. 

=============

.. raw:: html

    <a href="https://physics.ipm.ac.ir/"><img src="https://physics.ipm.ac.ir/images/ipm-logo1.gif" style="height:200px" height="200px"></a>

    <a href="https://www.haverford.edu/physics-and-astronomy/"><img src="https://www.bestdegreeprograms.org/wp-content/uploads/2021/10/Haverford-College-30-Great-Small-Colleges-for-STEM-Degrees-2021.png" style="height:100px" height="100px"></a>




