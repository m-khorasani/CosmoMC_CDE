    MODULE JLA
    !Module for handling JLA supernova data
    !Adapted form the SNLS module
    !The differences between this and the supernova_SNLS.f90 module are:
    ! 1) We use the SALT2 X_1 parameter instead of stretch
    ! 2) Intrinsic dispersion is included in the error reported in data files
    ! 3) Dispersion from lensing is also included
    ! 4) Redshift uncertainty is a global 150km/s
    !
    ! Model:
    !  The model for SN magnitudes is
    !   m_obs = 5*log10( D_L ) - alpha*(stretch-1) + beta*colour + scriptm
    !  scriptm is some combination of the absolute luminosity of SNe Ia and
    !  the Hubble constant -- marginalizing over it is equivalent to
    !  marginalizing over the absolute magnitude.  Because the errors on the
    !  individual points don't depend on scriptm, we can do this.  Since they
    !  do depend on alpha and beta, we can't marginalize over them.    Because
    !  cosmomc returns D_L in Mpc, scriptm is M - 25, where M is the magnitude
    !  of a stretch=1, colour=0 SN Ia in whatever band the mag comes in as.
    !  Here we use a flat prior for one or two scriptm values.
    !  Note that the SN data is independend of H_0 -unless- you use
    !   the absdist file.
    ! Covariance matricies:
    !  This code has support for SN-SN covariance matricies.
    !   We write the final covariance
    !  matrix as:
    !     V = D + V_mm + alpha^2 * V_ss + beta^2 + V_cc + 2 alpha V_ms
    !           - 2 beta V_mc - 2 alpha beta V_sc
    !  where, for example, V_ms is the covariance matrix between the
    !  uncorrected magnitude and the stretch of the SN.  D are the diagonal
    !  terms calculated from
    !     D_ii = sigma_m^2 + alpha^2 sigma_s^2 + beta^2 * sigma_c^2
    !                      + 2 alpha cov_m_s - 2 beta cov_m_c
    !                      - 2 alpha beta cov_s_c + intrinsicdisp^2 +
    !                      (5/log 10)^2 sigma_z^2 / z^2
    !  It may seem a little strange that the diagonal term is split off,
    !  but it is convenient in some circumstances, as it allows for
    !  Sherman-Woodbury inversion.  However, we don't implement that here.
    ! Speed:
    !  One might wonder if it is really necessary to explicitly fit for
    !   alpha and beta.  Can't we just internally marginalize over them?
    !  The short answer is, no, you can't, at least not if you want an
    !   unbiased answer.
    !  The long answer is, yes, sure you can internally marginalize over them.
    !   But doing so correctly is actually slower than fitting for them, so
    !   it isn't a great idea.
    !   There are a few things you might consider trying to do the
    !    internal marginalization:
    !     1) Fixing alpha and beta. This is -wrong- and will both underestimate
    !         and bias your results.  This is the way all previous cosmomc
    !         packages work, and so all those papers are -wrong-.
    !     2) Fixing alpha and beta but including some assumed error on them
    !         to make the errors better.  An improvement, but still wrong
    !         because alpha and beta are correlated with the other parameters.
    !         Of course, if other constraints effectively fix the cosmology,
    !         then this works, but that's equivalent to saying that the SN
    !         data is irrelevant to your fit -- so why are you bothering
    !         anyways.
    !     3) Internally minimizing alpha and beta, then plugging these in
    !         to get the chisq.  This is at least interesting, because
    !         this technique usually works, and would make things much
    !         faster.  Sadly, here it doesn't because
    !         this method only applies if the errors are independent of the
    !         parameters you are marginalizing over.  And the errors do depend
    !         on alpha and beta, so this will give you a biased answer.
    !     4) Explicitly making a grid over alpha and beta, computing the
    !         likelihood for each, and then marginalizing.  This finally
    !         actually works.  But, it turns out to be slower than the
    !         alternative.  To get a good result, you really need to have
    !         your grid be 60x60 or larger.  That means inverting the
    !         systematics covariance matrix (which depends on alpha
    !         and beta) > 60^2 times, and it's about
    !         500x500.  Without SNLS, the slowest step in the likelihood
    !         computation is usually the 3000x3000 inversion of the WMAP
    !         pixel space TT cov matrix.  Matrix inversion is N^3, so
    !         that means that this solution for alpha and beta is
    !         60^2*500^3/3000^3 ~ 17 times slower than the WMAP inversion.
    !         For comparison, fitting for alpha and beta explicitly
    !         slows the code down by about 20% for a typical fit.  So,
    !         you can use this method if you want, but it would be kinda
    !         stupid.
    !     5) Comment on the speed topic by MB. The slow step here is
    !         the recomputation of the cholesky decomposition of the
    !         covariance matrix each time alpha or beta changes
    !         (i.e. each step if you are fitting for alpha and
    !         beta). This is about 150MFLOPs for the JLA sample. The
    !         good way to gain a factor 10 is to make this computation
    !         perturbative with respect to a reference alpha,
    !         beta. First order seems accurate enough even for large
    !         departure from my investigation. I did not implement
    !         this here because all those costs are negligible in
    !         regard to the Planck likelihood evaluations. But that
    !         may become interesting for larger SN samples.
    ! Modification History:
    !  Written by Alex Conley, Dec 2006
    !   aconley, Jan 2007: The OpenMP stuff was causing massive slowdowns on
    !      some processors (ones with hyperthreading), so it was removed
    !   aconley, Jul 2009: Added absolute distance support
    !   aconley, May 2010: Added twoscriptm support
    !   aconley, Apr 2011: Fix some non standard F90 usage.  Thanks to
    !                       Zhiqi Huang for catching this.
    !   aconley, April 2011: zhel, zcmb read in wrong order.  Thanks to
    !                       Xiao Dong-Li and Shuang Wang for catching this
    !   mbetoule, Dec 2013: adaptation to the JLA sample
    !   AL, Mar 2014: updates for latest CosmoMC structure
    !   AL, June 2014: updated JLA_marginalize=T handling so it should work (also default JLA.ini)
    USE CosmologyTypes
    USE settings
    use CosmoTheory
    use Calculator_Cosmology
    use Likelihood_Cosmology
    IMPLICIT NONE

    !Modified by AL to have option of internal alpha, beta marginalization
    logical :: JLA_marginalize = .false. 
    logical :: use_Pantheon = .false.
    logical :: use_Pantheon_Plus = .false.
    logical :: use_Pantheon_SH0ES = .false.
    logical :: use_Union3 = .false.
    logical :: use_DES_Y5 = .false.
    REAL(mcp), allocatable :: JLA_marge_grid(:), alpha_grid(:),beta_grid(:)
    integer :: JLA_marge_steps = 0
    real(mcp) JLA_step_width_alpha, JLA_step_width_beta
    real(mcp), parameter :: JLA_alpha_center =  0.14
    real(mcp), parameter :: JLA_beta_center = 3.123
    integer :: JLA_int_points = 1

    type, extends(TCosmoCalcLikelihood) :: JLALikelihood
    contains
    procedure :: LogLike => jla_LnLike
    end type JLALikelihood

    integer, parameter :: dl = mcp

    character(LEN=*), parameter :: JLA_version =  'December_2013'
    logical, parameter :: allow_inv_cache = .false. !AL inverse cache does not work.. have not checked why.

    !Constants
    REAL(dl), PARAMETER, PRIVATE :: inv_twoPI = 1.0_dl / twopi
    CHARACTER, PARAMETER, PRIVATE :: uplo = 'U' !For LAPACK
    INTEGER, PARAMETER, PRIVATE :: max_idisp_datasets = 10
    INTEGER, PARAMETER, PRIVATE :: snnamelen = 12
    REAL(dl), PARAMETER, PRIVATE :: h0cfac = 5*LOG10( 100.0/299792.458 )
    REAL(dl), PARAMETER, PRIVATE :: alphatol = 1E-10_dl, betatol = 1E-10_dl

    !Variables we will try to get from the ini file
    CHARACTER(LEN=30), PRIVATE :: name !Name of data set
    REAL(dl), PRIVATE :: pecz !Peculiar velocity error in z
    REAL(dl), DIMENSION( max_idisp_datasets ) :: intrinsicdisp !In magnitudes

    !Variables having to do with optional two-scripmt fit based
    ! on thirdvar cut
    LOGICAL, PRIVATE :: twoscriptmfit !Carry out two scriptm fit
    LOGICAL, PRIVATE :: has_thirdvar  !Data has third variable
    REAL(dl), PRIVATE :: scriptmcut !Cut in thirdvar between two scriptms

    !Supernova data type
    TYPE, PRIVATE :: supernova
        CHARACTER(LEN=snnamelen) :: name  !The name of the SN
        REAL(dl) :: zhel, zcmb    !The heliocentric and CMB frame redshifts
        REAL(dl) :: z_var         !The variance of the redshift
        REAL(dl) :: mag           !The K-corrected peak magnitude
        REAL(dl) :: mag_var       !The variance of mag
        REAL(dl) :: stretch       !The light-curve fit stretch parameter
        REAL(dl) :: stretch_var   !The variance in the stretch
        REAL(dl) :: colour        !The colour of the SN
        REAL(dl) :: colour_var    !The variance of colour
        REAL(dl) :: thirdvar      !Third variable for scripm split
        REAL(dl) :: thirdvar_var  !Variance in thirdvar
        REAL(dl) :: cov_mag_stretch !Covariance between mag and stretch
        REAL(dl) :: cov_mag_colour  !Covariance between mag and colour
        REAL(dl) :: cov_stretch_colour !Covariance between stretch and colour
        LOGICAL :: has_absdist    !This SN has an absolute distance
        INTEGER  :: dataset       !Subset identifier if subset dependent intrinsic disp is used
    END TYPE supernova

    INTEGER, PUBLIC :: nsn  !Number of supernovae
    TYPE( supernova ), ALLOCATABLE, PRIVATE :: sndata(:)  !Supernova data
    !Stores the parts of the error that can be pre-calculated
    REAL(dl), ALLOCATABLE, PRIVATE :: pre_vars(:)
    !Arrays which have 1 for SN in set 1 (A1) or 2 (A2).  For twoscriptm fit
    REAL(dl), ALLOCATABLE, PRIVATE :: A1(:), A2(:)

    !Covariance matrix stuff
    ! If we have no covariance matrix at all, diag_errors is .TRUE.
    LOGICAL, PRIVATE :: diag_errors =        .TRUE.

    !Which components of the covariance matrix do we have
    LOGICAL, PRIVATE :: has_mag_covmat =            .FALSE.
    LOGICAL, PRIVATE :: has_stretch_covmat =        .FALSE.
    LOGICAL, PRIVATE :: has_colour_covmat =         .FALSE.
    LOGICAL, PRIVATE :: has_mag_stretch_covmat =    .FALSE.
    LOGICAL, PRIVATE :: has_mag_colour_covmat =     .FALSE.
    LOGICAL, PRIVATE :: has_stretch_colour_covmat = .FALSE.
    LOGICAL, PRIVATE :: alphabeta_covmat =          .FALSE.
    REAL(dl), ALLOCATABLE, PRIVATE :: mag_covmat(:,:), stretch_covmat(:,:)
    REAL(dl), ALLOCATABLE, PRIVATE :: colour_covmat(:,:), mag_stretch_covmat(:,:)
    REAL(dl), ALLOCATABLE, PRIVATE :: mag_colour_covmat(:,:)
    REAL(dl), ALLOCATABLE, PRIVATE :: stretch_colour_covmat(:,:)

    !Structure for holding absolute distance information for SN
    LOGICAL, PRIVATE :: has_absdist =     .FALSE.
    INTEGER, PRIVATE :: nabsdist =         0
    TYPE, PRIVATE :: supernova_absdist
        CHARACTER(LEN=snnamelen) :: name  !The name of the SN
        REAL(dl) :: dl             !Distance in Mpc
        INTEGER :: index           !Index into sndata
    END TYPE supernova_absdist
    TYPE( supernova_absdist ), ALLOCATABLE, PRIVATE :: snabsdist(:)

    !Other convenience variables
    REAL(dl), ALLOCATABLE, PRIVATE :: lumdists(:)
    REAL(dl), PRIVATE :: alpha_prev, beta_prev

    LOGICAL, PRIVATE :: first_inversion
    LOGICAL, PUBLIC :: jla_read = .FALSE.
    LOGICAL, PUBLIC :: jla_prepped = .FALSE.

    PRIVATE :: count_lines, read_jla_lc_data, read_cov_matrix
    PRIVATE :: read_jla_absdist_data, match_jla_absdist_indices
    PUBLIC :: jla_prep, jla_LnLike, jla_cleanup, read_jla_dataset,JLALikelihood_Add

    CONTAINS


    subroutine JLALikelihood_Add(LikeList, Ini)
    class(TLikelihoodList) :: LikeList
    class(TIniFile) :: ini
    Type(JLALikelihood), pointer :: this
    character (LEN=:), allocatable:: jla_filename
    integer alpha_i, beta_i

    if (.not. Ini%Read_Logical('use_JLA',.false.)) return

    allocate(this)
    this%LikelihoodType = 'SN'
    this%name='JLA'
    this%needs_background_functions = .true.
    this%version = Ini%Read_String_Default('jla_version',JLA_version)
    JLA_marginalize = Ini%Read_Logical('JLA_marginalize',.false.)
    use_Pantheon = Ini%Read_Logical('use_Pantheon',.false.)
    use_Pantheon_Plus = Ini%Read_Logical('use_Pantheon_Plus',.false.)  
    use_Pantheon_SH0ES = Ini%Read_Logical('use_Pantheon_SH0ES',.false.)
    use_DES_Y5 = Ini%Read_Logical('use_DES_Y5',.false.)
    use_Union3 = Ini%Read_Logical('use_Union3',.false.)
    if (JLA_marginalize) then
        JLA_marge_steps = Ini%Read_Int('JLA_marge_steps',7)
        JLA_step_width_alpha = Ini%Read_Double('JLA_step_width_alpha',0.003d0)
        JLA_step_width_beta = Ini%Read_Double('JLA_step_width_beta',0.04d0)
        JLA_int_points=0
        allocate(alpha_grid((2*JLA_marge_steps+1)**2))
        allocate(beta_grid((2*JLA_marge_steps+1)**2))
        do alpha_i = - JLA_marge_steps, JLA_marge_steps
            do beta_i = - JLA_marge_steps, JLA_marge_steps
                if (alpha_i**2 + beta_i**2 <= JLA_marge_steps**2) then
                    JLA_int_points=JLA_int_points+1
                    alpha_grid(JLA_int_points) = JLA_alpha_center + alpha_i* JLA_step_width_alpha
                    beta_grid(JLA_int_points)  = JLA_beta_center + beta_i* JLA_step_width_beta
                end if
            end do
        end do
        allocate(JLA_marge_grid(JLA_int_points))
    else
        call this%loadParamNames(trim(DataDir)//'JLA.paramnames')
    end if
    call LikeList%Add(this)
    jla_filename = Ini%Read_String_Default('jla_dataset',trim(DataDir)//'jla.dataset')
    CALL read_jla_dataset( jla_filename )
    CALL jla_prep
    If (Feedback>0) WRITE(*,*) 'read jla dataset '//trim(jla_filename)

    end subroutine JLALikelihood_Add

    !Counts the number of lines in an open file attached to lun,
    ! returning the number of lines in lines and the number of
    ! non-comment lines in noncommentlines, where a comment line
    ! is defined to start with a #
    !The file is rewound on exit
    SUBROUTINE count_lines( lun, lines, noncommentlines )
    IMPLICIT NONE
    INTEGER, INTENT(in) :: lun
    INTEGER, INTENT(out) :: lines, noncommentlines
    INTEGER, PARAMETER :: maxlines = 5000 !Maximum number allowed
    INTEGER :: i
    CHARACTER(LEN=80) :: inline, shiftline
    LOGICAL :: opened

    INTRINSIC ADJUSTL

    !Make sure the file is open
    INQUIRE( lun, OPENED=opened )
    IF (.NOT. opened) THEN
        WRITE(*,*) "File is not open in count_lines"
        STOP
    ENDIF

    !Now start reading
    lines = 0
    noncommentlines = 0
    DO i = 1, maxlines
        READ( lun, '(A)', ERR=2, END=100 ) inline
        lines = lines + 1
        shiftline = ADJUSTL( inline )
        IF ( shiftline(1:1) .NE. '#' ) noncommentlines = noncommentlines+1
    ENDDO
    GO TO 100

2   WRITE(*,*) "Error reading input file in count_lines"
    STOP

100 REWIND lun
    END SUBROUTINE count_lines

    !Reads the covariance matrix from a file, given the filename
    ! and the number of elements to expect
    !There are two possible formats supported
    ! These are: as one big block, and then as n by n individual elements
    ! The number of lines has to be the same as the number of SN, and
    ! they have to be in the same order
    !Copied from settings::ReadMatrix
    SUBROUTINE read_cov_matrix(filename, mat, n)
    CHARACTER(LEN=*), INTENT(IN) :: filename
    INTEGER, INTENT(IN) :: n
    REAL(dl), INTENT(OUT) :: mat(n,n)
    INTEGER :: j,k, file_unit, nfile
    REAL(dl) :: tmp

    IF (Feedback > 2) WRITE(*,*) 'reading: '//trim(filename)
    OPEN( newunit=file_unit, FILE=TRIM(filename), FORM='formatted', &
        STATUS='old', ERR = 500 )

    READ (file_unit, '(I5)', END=200, ERR=100) nfile
    IF (nfile /= n) THEN
        WRITE (*,'("For file ",A," expected size ",I5," got ",I5)') &
            TRIM(filename), n, nfile
        STOP
    ENDIF

    DO j=1,n
        READ (file_unit,*, end = 200, err=100) mat(j,1:n)
    ENDDO

    GOTO 120

100 REWIND(file_unit)  !Try other possible format
    READ (file_unit, '(I5)', END=200, ERR=100) nfile

    DO j=1,n
        DO k=1,n
            READ (file_unit,*, end = 200) mat(j,k)
        END DO
    END DO

120 READ (file_unit,*, err = 150, end =150) tmp
    GOTO 200

150 CLOSE(file_unit)
    RETURN

200 WRITE (*,*) 'matrix file '//trim(filename)//' is the wrong size'
    WRITE (*,'("Expected: ",I5," by ",I5)') n,n
    STOP

500 WRITE (*,*) 'Failed to open cov matrix file ' // TRIM(filename)
    STOP

    END SUBROUTINE read_cov_matrix

    !------------------------------------------------------------
    ! Reads in a supernova data file, given knowledge of the number
    !  of lines to expect.  Ignores lines that start with #.
    ! Input arguments:
    !  lun              The lun number of the file to read.  Must be already open
    !  nlines           The number of lines to expect in the file
    !  nnoncommentlines The number of non-comment lines in the file
    ! Output arguments:
    !  sndata           The returned SN data, of length nnoncommentlines
    ! Notes:
    !  The file is not rewound on exit
    !------------------------------------------------------------
    SUBROUTINE read_jla_lc_data( lun, nlines, nnoncommentlines, sndata )
    IMPLICIT NONE
    INTEGER, INTENT(in) :: lun, nlines, nnoncommentlines
    TYPE(supernova), INTENT(out) :: sndata(nnoncommentlines)

    CHARACTER(LEN=80) :: inline, shiftline
    INTEGER:: i,count
    REAL :: dz, dm, ds, dc, dt
    LOGICAL :: opened

    INTRINSIC ADJUSTL

    INQUIRE( lun, OPENED=opened )
    IF (.NOT. opened) THEN
        WRITE(*,*) "File is not open in count_lines"
        STOP
    ENDIF

    count = 1
    has_thirdvar = .FALSE.
    sndata%has_absdist = .FALSE.
    DO i=1,nlines
        !Read in line non-advancing
        READ (lun, '(A)', ERR = 20, END = 20) inline
        shiftline = ADJUSTL( inline )
        IF (shiftline(1:1) .EQ. '#') CYCLE

        BACKSPACE lun

        !We have a few formats to try.  First, there is the very
        ! long format with thirdvar and dataset.  If that fails,
        ! try without data set.  If that fails, try without
        ! thirdvar but with dataset, and finally with neither

        !A further complication is that if one line has thirdvar,
        ! they had better all have them or else ugliness will probably
        ! result
        READ (lun, *, ERR=20, END=20) &
            sndata(count)%name, sndata(count)%zcmb, sndata(count)%zhel,&
            dz, sndata(count)%mag, dm, sndata(count)%stretch, ds, &
            sndata(count)%colour,dc,sndata(count)%thirdvar, dt,&
            sndata(count)%cov_mag_stretch,&
            sndata(count)%cov_mag_colour,sndata(count)%cov_stretch_colour,&
            sndata(count)%dataset    
        IF ( (count .GT. 1) .AND. (.NOT. has_thirdvar) ) THEN
            WRITE(*,*) "Problem with third variable read"
            STOP
        ENDIF
        has_thirdvar = .TRUE.
        GOTO 10  !Success

        !That didn't work. Try without dataset.  First, undo the
        ! previous.  It should be 2 records out of place because
        ! we read over into the next line
20      BACKSPACE lun
        BACKSPACE lun
        READ (lun, *, ERR=30, END=30) &
            sndata(count)%name, sndata(count)%zcmb, sndata(count)%zhel,&
            dz, sndata(count)%mag, dm, sndata(count)%stretch, ds, &
            sndata(count)%colour,dc,sndata(count)%thirdvar,dt,&
            sndata(count)%cov_mag_stretch,&
            sndata(count)%cov_mag_colour,sndata(count)%cov_stretch_colour
        IF ( (count .GT. 1) .AND. (.NOT. has_thirdvar) ) THEN
            WRITE(*,*) "Problem with third variable read"
            STOP
        ENDIF
        has_thirdvar = .TRUE.
        GOTO 10  !Success

        !Ok, maybe there's no thirdvar
30      BACKSPACE lun
        BACKSPACE lun
        READ (lun, *, ERR=40, END=40) &
            sndata(count)%name, sndata(count)%zcmb, sndata(count)%zhel,&
            dz, sndata(count)%mag, dm, sndata(count)%stretch, ds, &
            sndata(count)%colour,dc,sndata(count)%cov_mag_stretch,&
            sndata(count)%cov_mag_colour,sndata(count)%cov_stretch_colour,&
            sndata(count)%dataset    
        IF ( (count .GT. 1) .AND. (has_thirdvar) ) THEN
            WRITE(*,*) "Problem with third variable read"
            STOP
        ENDIF
        sndata(count)%thirdvar = 0.0
        dt = 0.0
        sndata(count)%dataset = 0

        !Still?
        !Ok, maybe there's no thirdvar and no dataset
40      BACKSPACE lun
        BACKSPACE lun
        READ (lun, *, ERR=60, END=50) &
            sndata(count)%name, sndata(count)%zcmb, sndata(count)%zhel,&
            dz, sndata(count)%mag, dm, sndata(count)%stretch, ds, &
            sndata(count)%colour,dc,sndata(count)%cov_mag_stretch,&
            sndata(count)%cov_mag_colour,sndata(count)%cov_stretch_colour,&
            sndata(count)%dataset
        IF ( (count .GT. 1) .AND. (has_thirdvar) ) THEN
            WRITE(*,*) "Problem with third variable read"
            STOP
        ENDIF
        sndata(count)%thirdvar = 0.0
        dt = 0.0
        sndata(count)%dataset = 0

10      sndata(count)%z_var = dz**2
        sndata(count)%mag_var = dm**2
        sndata(count)%stretch_var = ds**2
        sndata(count)%colour_var = dc**2
        sndata(count)%thirdvar_var = dt**2
        !sndata(count)%thirdvar = 6
        count = count+1
    END DO
    RETURN

50  WRITE(*,'("File ended unexpectedly on line ",I3," expecting ",I3)') i,nlines
    STOP

60  WRITE(*,*) 'Error reading in input data with: ',inline
    STOP

    END SUBROUTINE read_jla_lc_data

    !------------------------------------------------------------
    ! Read in absolute distance info, given knowledge of the number
    !  of lines to expect.  Ignores lines that start with #.
    ! Input arguments:
    !  lun              The lun number of the file to read.  Must be already open
    !  nlines           The number of lines to expect in the file
    !  nnoncommentlines The number of non-comment lines in the file
    ! Output arguments:
    !  snabsdist        The absolute distance data, of length nnoncommentlines
    ! Notes:
    !  The file is not rewound on exit
    !------------------------------------------------------------
    SUBROUTINE read_jla_absdist_data( lun, nlines, nnoncommentlines, snabsdist )
    IMPLICIT NONE
    INTEGER, INTENT(in) :: lun, nlines, nnoncommentlines
    TYPE(supernova_absdist), INTENT(out) :: snabsdist(nnoncommentlines)

    CHARACTER(LEN=80) :: inline, shiftline
    INTEGER:: i,count
    LOGICAL :: opened

    INTRINSIC ADJUSTL

    INQUIRE( lun, OPENED=opened )
    IF (.NOT. opened) THEN
        WRITE(*,*) "File is not open in count_lines"
        STOP
    ENDIF

    count = 1
    DO i=1,nlines
        !Read in line non-advancing mode
        READ (lun, '(A)', ERR = 140, END = 130) inline
        shiftline = ADJUSTL( inline )
        IF (shiftline(1:1) .EQ. '#') CYCLE

        BACKSPACE lun

        READ (lun, *, ERR=140, END=130) &
            snabsdist(count)%name, snabsdist(count)%dl
        count = count+1
    END DO
    RETURN

130 WRITE(*,'("File ended unexpectedly on line ",I3," expecting ",I3)') i,nlines
    STOP

140 WRITE(*,*) 'Error reading in input data with: ',inline
    STOP

    END SUBROUTINE read_jla_absdist_data

    !------------------------------------------------------------
    ! Match absdist info into sninfo by searching on names
    ! Arguments:
    !  sndata          supernova data. Modified on output
    !  snabsdist       Absolute distance data.  Modified on output
    !------------------------------------------------------------
    SUBROUTINE match_jla_absdist_indices( sndata, snabsdist )
    IMPLICIT NONE
    TYPE( supernova ), INTENT(INOUT) :: sndata(:)
    TYPE( supernova_absdist ), INTENT(INOUT) :: snabsdist(:)
    CHARACTER(LEN=snnamelen) :: currname
    INTEGER :: nsn, nabsdist, i, j

    nsn = SIZE( sndata )
    nabsdist = SIZE( snabsdist )

    IF (nsn == 0) THEN
        WRITE (*,*) "ERROR -- sndata has zero length"
        STOP
    ENDIF
    IF (nabsdist == 0) THEN
        WRITE (*,*) "ERROR -- snabsdist has zero length"
        STOP
    ENDIF

    !We do this slowly and inefficiently because we only have
    ! to do it once, and because string manipulation is such
    ! a nightmare in Fortran
    snabsdist%index = -1
    oloop:    DO i = 1, nabsdist
        currname = snabsdist(i)%name
        DO j = 1, nsn
            IF ( sndata(j)%name .EQ. currname ) THEN
                sndata(j)%has_absdist = .TRUE.
                snabsdist(i)%index = j
                CYCLE oloop
            ENDIF
        ENDDO
    ENDDO oloop

    !Make sure we found them all
    DO i=1,nabsdist
        IF ( snabsdist(i)%index .LT. 0 ) THEN
            WRITE (*,'("Failed to match ",A," to full SN list")') &
                snabsdist(i)%name
            STOP
        ENDIF
    ENDDO

    END SUBROUTINE match_jla_absdist_indices

    !------------------------------------------------------------
    ! The public interface to reading data files
    ! This gets information from the .ini file and reads the data file
    ! Arguments:
    !  filename        The name of the .ini file specifying the SN dataset
    !------------------------------------------------------------
    SUBROUTINE read_jla_dataset(filename )
    IMPLICIT NONE
    CHARACTER(LEN=*), INTENT(in) :: filename
    CHARACTER(LEN=:), allocatable :: covfile
    CHARACTER(LEN=:), allocatable :: data_file, absdist_file
    INTEGER :: nlines, i
    REAL(dl) :: idisp_zero !Value for unspecified dataset numbers
    LOGICAL, DIMENSION( max_idisp_datasets ) :: idispdataset
    Type(TSettingIni) :: Ini
    integer file_unit

    IF (jla_read) STOP 'Error -- JLA data already read'

    !Process the Ini file
    CALL Ini%Open(filename)

    name = Ini%Read_String( 'name', .FALSE. )
    data_file = Ini%Read_String_Default('data_file',trim(DataDir)//'jla_lcparams.txt')

    has_absdist = Ini%Read_Logical( 'absdist_file',.FALSE.)
    pecz = Ini%Read_Double( 'pecz', 0.001D0 )

    twoscriptmfit = Ini%Read_Logical('twoscriptmfit',.FALSE.)
    IF ( twoscriptmfit ) scriptmcut = Ini%Read_Double('scriptmcut',10.0d0)

    !Handle intrinsic dispersion
    !The individual values are intrinsicdisp0 -- intrinsicdisp9
    idisp_zero = Ini%Read_Double( 'intrinsicdisp', 0.13_dl )
    idispdataset = .FALSE.
    DO i=1, max_idisp_datasets
        intrinsicdisp(i) = Ini%Read_Double(numcat('intrinsicdisp',i-1),&
            idisp_zero)
        IF (intrinsicdisp(i) .NE. idisp_zero) idispdataset(i)=.TRUE.
    END DO

    !Now read the actual SN data
    OPEN( newunit=file_unit, FILE=TRIM(data_file), FORM='formatted', &
        STATUS='old', ERR = 500 )
    !Find the number of lines
    CALL count_lines( file_unit, nlines, nsn )
    ALLOCATE( sndata(nsn) )
    CALL read_jla_lc_data( file_unit, nlines, nsn, sndata )
    CLOSE( file_unit )

    !Make sure we have thirdvar if we need it
    IF ( twoscriptmfit .AND. (.NOT. has_thirdvar) ) THEN
        WRITE(*,*) "twoscriptmfit was set but thirdvar information not present"
        STOP
    ENDIF

    !Absolute distance
    IF ( has_absdist ) THEN
        OPEN( newunit=file_unit, FILE=TRIM(absdist_file), FORM='formatted', &
            STATUS='old', ERR = 500 )
        !Find the number of lines
        CALL count_lines( file_unit, nlines, nabsdist )
        ALLOCATE( snabsdist(nabsdist) )
        CALL read_jla_absdist_data( file_unit, nlines, nabsdist, snabsdist )
        CLOSE( file_unit )
        CALL match_jla_absdist_indices( sndata, snabsdist )
    ENDIF

    !Handle covariance matrix stuff
    has_mag_covmat=Ini%Read_Logical( 'has_mag_covmat', .FALSE. )
    has_stretch_covmat=Ini%Read_Logical( 'has_stretch_covmat', .FALSE. )
    has_colour_covmat=Ini%Read_Logical( 'has_colour_covmat', .FALSE. )
    has_mag_stretch_covmat=Ini%Read_Logical('has_mag_stretch_covmat',.FALSE.)
    has_mag_colour_covmat=Ini%Read_Logical( 'has_mag_colour_covmat',.FALSE. )
    has_stretch_colour_covmat = &
        Ini%Read_Logical( 'has_stretch_colour_covmat',.FALSE. )
    alphabeta_covmat = ( has_stretch_covmat .OR. has_colour_covmat .OR. &
        has_mag_stretch_covmat .OR. has_mag_colour_covmat .OR. &
        has_stretch_colour_covmat )

    !First test for covmat
    IF ( has_mag_covmat .OR. has_stretch_covmat .OR. has_colour_covmat .OR. &
        has_mag_stretch_covmat .OR. has_mag_colour_covmat .OR. &
        has_stretch_colour_covmat ) THEN
        diag_errors = .FALSE.

        !Now Read in the covariance matricies
        IF (has_mag_covmat) THEN
            covfile = Ini%Read_String('mag_covmat_file',.TRUE.)
            ALLOCATE( mag_covmat( nsn, nsn ) )
            CALL read_cov_matrix( covfile, mag_covmat, nsn )
        ENDIF
        IF (has_stretch_covmat) THEN
            covfile = Ini%Read_String('stretch_covmat_file',.TRUE.)
            ALLOCATE( stretch_covmat( nsn, nsn ) )
            CALL read_cov_matrix( covfile, stretch_covmat, nsn )
        ENDIF
        IF (has_colour_covmat) THEN
            covfile = Ini%Read_String('colour_covmat_file',.TRUE.)
            ALLOCATE( colour_covmat( nsn, nsn ) )
            CALL read_cov_matrix( covfile, colour_covmat, nsn )
        ENDIF
        IF (has_mag_stretch_covmat) THEN
            covfile = Ini%Read_String('mag_stretch_covmat_file',.TRUE.)
            ALLOCATE( mag_stretch_covmat( nsn, nsn ) )
            CALL read_cov_matrix( covfile, mag_stretch_covmat, nsn )
        ENDIF
        IF (has_mag_colour_covmat) THEN
            covfile = Ini%Read_String('mag_colour_covmat_file',.TRUE.)
            ALLOCATE( mag_colour_covmat( nsn, nsn ) )
            CALL read_cov_matrix( covfile, mag_colour_covmat, nsn )
        ENDIF
        IF (has_stretch_colour_covmat) THEN
            covfile = Ini%Read_String('stretch_colour_covmat_file',.TRUE.)
            ALLOCATE( stretch_colour_covmat( nsn, nsn ) )
            CALL read_cov_matrix( covfile, stretch_colour_covmat, nsn )
        ENDIF
    ELSE
        diag_errors = .TRUE.
    END IF

    CALL Ini%Close()

    IF (Feedback > 1) THEN
        WRITE(*,'(" JLA dataset name: ",A)') TRIM(name)
        WRITE(*,'(" JLA data file: ",A)') TRIM(data_file)
        WRITE(*,'(" Number of SN read: ",I4)') nsn
    ENDIF

    IF (Feedback > 2) THEN
        WRITE(*,'(" JLA pec z: ",F6.3)') pecz
        WRITE(*,'(" JLA default sigma int: ",F6.3)') idisp_zero
        DO i=1, max_idisp_datasets
            IF ( idispdataset(i)) &
                WRITE(*,'(" JLA sigma int for dataset ",I2,": ",F6.3)') &
                i-1,intrinsicdisp(i)
        END DO
        IF (has_absdist) THEN
            WRITE (*,'(" Number of SN with absolute distances: ",I4)') &
                nabsdist
            IF (Feedback>2 .AND. (nabsdist .LT. 10)) THEN
                DO i=1,nabsdist
                    WRITE(*,'("   Name: ",A12," dist: ",F8.2)') &
                        snabsdist(i)%name,snabsdist(i)%dl
                ENDDO
            ENDIF
        ENDIF
        IF (twoscriptmfit) THEN
            WRITE (*,'("Doing two-scriptm fit with cut: ",F7.3)') scriptmcut
        ENDIF
        IF (has_mag_covmat) WRITE (*,*) " Has mag covariance matrix"
        IF (has_stretch_covmat) WRITE (*,*) " Has stretch covariance matrix"
        IF (has_colour_covmat) WRITE (*,*) " Has colour covariance matrix"
        IF (has_mag_stretch_covmat) &
            WRITE (*,*) " Has mag-stretch covariance matrix"
        IF (has_mag_colour_covmat) &
            WRITE (*,*) " Has mag-colour covariance matrix"
        IF (has_stretch_colour_covmat) &
            WRITE (*,*) " Has stretch_colour covariance matrix"
    ENDIF

    first_inversion = .true.
    jla_read = .TRUE.
    jla_prepped = .FALSE.
    RETURN

500 WRITE(*,*) 'Error reading ' // data_file
    STOP

    END SUBROUTINE read_jla_dataset

    !-------------------------------------------------------------
    !Inverts the covariance matrix.  Assumes all sorts of stuff
    ! is pre-allocated and pre-filled.  Pre_vars must already have
    ! the intrinsic dispersion, redshift error, mag error.
    ! Has a check to see if the previous cov matrix can be reused
    !-------------------------------------------------------------
    SUBROUTINE invert_covariance_matrix(invcovmat, alpha, beta, status )
    IMPLICIT NONE
    CHARACTER(LEN=*), PARAMETER :: cholerrfmt = &
        '("Error computing cholesky decomposition for ",F6.3,2X,F6.3)'
    CHARACTER(LEN=*), PARAMETER :: cholinvfmt = &
        '("Error inverting cov matrix for ",F6.3,2X,F6.3)'
    CHARACTER(LEN=*), PARAMETER :: cholsolfmt = &
        '("Error forming inv matrix product for ",F6.3,2X,F6.3)'

    REAL(dl), INTENT(IN) :: alpha, beta
    INTEGER, INTENT(INOUT) :: status
    REAL(dl) :: invcovmat(:,:)

    INTEGER :: I
    REAL(dl) :: alphasq, betasq, alphabeta

    !Quick exit check
    !Note that first_inversion can't be true if the first one
    ! failed (has status != 0).
    IF (.NOT. first_inversion .and. allow_inv_cache) THEN
        IF (.NOT. alphabeta_covmat) THEN
            !covmatrix doesn't depend on alpha/beta, has already been
            ! inverted once.
            status = 0
            RETURN
        ELSE IF ( (ABS(alpha-alpha_prev) .LT. alphatol) .AND. &
            ( ABS(beta-beta_prev) .LT. betatol ) ) THEN
            !Previous invcovmatrix is close enough
            status = 0
            RETURN
        ENDIF
    ENDIF

    alphasq = alpha * alpha
    betasq = beta * beta
    alphabeta = alpha * beta

    IF (diag_errors) STOP 'Error -- asking to invert with diagonal errors'

    !Build the covariance matrix, then invert it
    IF (has_mag_covmat) THEN
        invcovmat = mag_covmat
    ELSE
        invcovmat = 0.0_dl
    END IF
    IF (has_stretch_covmat) invcovmat = invcovmat + &
        alphasq * stretch_covmat
    IF (has_colour_covmat) invcovmat = invcovmat + &
        betasq * colour_covmat
    IF (has_mag_stretch_covmat) invcovmat = invcovmat + 2.0 * alpha * mag_stretch_covmat
    IF (has_mag_colour_covmat) invcovmat = invcovmat - 2.0 * beta * mag_colour_covmat
    IF (has_stretch_colour_covmat) invcovmat = invcovmat - 2.0 * alphabeta * stretch_colour_covmat

    !Update the diagonal terms
    DO I=1, nsn
        invcovmat(I,I) = invcovmat(I,I) + pre_vars(I) &
            + alphasq * sndata(I)%stretch_var &
            + betasq  * sndata(I)%colour_var &
            + 2.0 * alpha * sndata(I)%cov_mag_stretch &
            - 2.0 * beta * sndata(I)%cov_mag_colour &
            - 2.0 * alphabeta * sndata(I)%cov_stretch_colour
    END DO

    !Factor into Cholesky form, overwriting the input matrix
    CALL DPOTRF(uplo,nsn,invcovmat,nsn,status)
    IF ( status .NE. 0 ) THEN
        WRITE(*,cholerrfmt) alpha, beta
        RETURN
    END IF

    !Now invert
    !If we could get away with the relative chisquare
    ! this could be done faster and more accurately
    ! by solving the system V*x = diffmag for x to get
    ! V^-1 * diffmag.  But, with the introduction of alpha, beta
    ! this _doesn't_ work, so we need the actual elements of
    ! the inverse covariance matrix.  The point is that the
    ! amarg_E parameter depends on the sum of the elements of
    ! the inverse covariance matrix, and therefore is different
    ! for different values of alpha and beta.
    !Note that DPOTRI only makes half of the matrix correct,
    ! so we have to be careful in what follows
    CALL DPOTRI(uplo,nsn,invcovmat,nsn,status)
    IF ( status .NE. 0 ) THEN
        WRITE(*,cholinvfmt) alpha, beta

        RETURN
    END IF

    first_inversion = .FALSE.
    alpha_prev = alpha
    beta_prev  = beta

    END SUBROUTINE invert_covariance_matrix


    !------------------------------------------------------------
    ! Prepares the data for fitting by pre-calculating the parts of
    !  the errors that can be done ahead of time.
    ! ReadJLADataset must have been read before calling this
    !------------------------------------------------------------
    SUBROUTINE jla_prep
    IMPLICIT NONE

    CHARACTER(LEN=*), PARAMETER :: snheadfmt = '(1X,A10,9(1X,A8))'
    CHARACTER(LEN=*), PARAMETER :: sndatfmt = '(1X,A10,9(1X,F8.4))'
    CHARACTER(LEN=*), PARAMETER :: sndatfmt2 = '(1X,A10,11(1X,F8.4))'
    CHARACTER(LEN=*), PARAMETER :: datafile = 'data/jla_data.dat'
    ! dz multiplicative factor
    REAL(dl), PARAMETER :: zfacsq = 25.0/(LOG(10.0))**2
    REAL(dl) ::  intrinsicsq(max_idisp_datasets)
    INTEGER ::  i
    LOGICAL :: has_A1, has_A2

    intrinsicsq = intrinsicdisp**2

    IF (.NOT. jla_read) STOP 'JLA data was not read in'
    IF (nsn < 1) STOP 'No JLA data read'

    IF ( MAXVAL( sndata%dataset ) .GE. max_idisp_datasets ) THEN
        WRITE(*,*) 'Invalid dataset number ',MAXVAL(sndata%dataset)
        WRITE(*,*) ' Maximum allowed is ',max_idisp_datasets
    END IF
    IF ( MINVAL( sndata%dataset ) .LT. 0 ) THEN
        WRITE(*,*) 'Invalid dataset number ',MINVAL(sndata%dataset)
        WRITE(*,*) ' Maximum allowed is 0'
    END IF

    !Pre-calculate errors as much as we can
    !The include the magnitude error, the peculiar velocity
    ! error, and the intrinsic dispersion.
    !We don't treat the pec-z/redshift errors completely correctly,
    ! using the empty-universe expansion.  However, the redshift errors
    ! are really only important at low-z with current samples (where
    ! peculiar velocities dominate) so this is a very good approximation.
    ! If photometric redshifts are ever used, this may have to be
    ! modified
    !The redshift error is irrelevant for SN with absolute distances
    ALLOCATE( pre_vars(nsn) )
    
!---CDE Start
	if (use_Pantheon) then
	    pre_vars = sndata%mag_var + intrinsicsq(sndata%dataset+1)

	else if (use_Pantheon_Plus) then

		if (use_DES_Y5) then 
		    pre_vars = sndata%mag_var

		else if (use_Union3) then 

			pre_vars = 0.0
			
		else if (use_Pantheon_SH0ES) then		

			pre_vars = 0.0

		end if
		
	end if	
	 
    DO i=1,nsn
		    IF (.NOT. sndata(i)%has_absdist) THEN
		        pre_vars(i) = pre_vars(i) + &
		            zfacsq * pecz**2 * &
		            ( (1.0 + sndata(i)%zcmb)/&
		            (sndata(i)%zcmb*(1+0.5*sndata(i)%zcmb)) )**2
		    ENDIF     
    ENDDO
!---CDE End

    ALLOCATE(lumdists(nsn))

    IF (twoscriptmfit) THEN
        ALLOCATE( A1(nsn), A2(nsn) )
        has_A1 = .TRUE.
        has_A2 = .FALSE.
        !Assign A1 and A2 as needed
        DO i=1, nsn
            IF (sndata(i)%thirdvar .LE. scriptmcut ) THEN
                A1(i) = 1.0_dl
                A2(i) = 0.0_dl
                has_A1 = .TRUE.
            ELSE
                A1(i) = 0.0_dl
                A2(i) = 1.0_dl
                has_A2 = .TRUE.
            END IF
        END DO

        IF (.NOT. has_A1) THEN
            !Swap
            A1 = A2
            A2(:) = 0.0_dl
            twoscriptmfit = .FALSE.
            has_A1 = .TRUE.
            has_A2 = .FALSE.
        ENDIF

        IF (.NOT. has_A2) THEN
            IF (Feedback > 2) THEN
                WRITE(*,*) "No SN present in scriptm set 2"
                WRITE(*,*) "De-activating two scriptm fit"
            ENDIF
            twoscriptmfit = .FALSE.
        ENDIF
    ENDIF

    IF (Feedback > 3) THEN
        !Write out summary of SN info
        WRITE(*,*) "Summary of supernova data: "
        IF (twoscriptmfit) THEN
            WRITE(*,snheadfmt) "Name","zhel","dz","mag", "dmag", &
                "s","ds","c","dc","t","dt","pre_err"
            DO i = 1, nsn
                WRITE(*,sndatfmt2) sndata(i)%name,sndata(i)%zhel,&
                    SQRT(sndata(i)%z_var),sndata(i)%mag, SQRT(sndata(i)%mag_var),&
                    sndata(i)%stretch,SQRT(sndata(i)%stretch_var),&
                    sndata(i)%colour,SQRT(sndata(i)%colour_var),&
                    sndata(i)%thirdvar,SQRT(sndata(i)%thirdvar_var),&
                    SQRT(pre_vars(i))
            END DO
        ELSE
            WRITE(*,snheadfmt) "Name","zhel","dz","mag", "dmag", &
                "s","ds","c","dc","pre_err"
            DO i = 1, nsn
                WRITE(*,sndatfmt) sndata(i)%name,sndata(i)%zhel,&
                    SQRT(sndata(i)%z_var),sndata(i)%mag, SQRT(sndata(i)%mag_var),&
                    sndata(i)%stretch,SQRT(sndata(i)%stretch_var),&
                    sndata(i)%colour,&
                    SQRT(sndata(i)%colour_var),SQRT(pre_vars(i))
            END DO
        ENDIF
    ENDIF

    jla_prepped = .TRUE.
    first_inversion = .TRUE.
    RETURN
500 WRITE(*,*) 'Error reading ' // datafile
    STOP
    END SUBROUTINE jla_prep

    !------------------------------------------------------------
    ! Clean up routine -- de-allocates memory
    !------------------------------------------------------------
    SUBROUTINE jla_cleanup
    IF ( ALLOCATED( sndata ) ) DEALLOCATE( sndata )
    IF ( ALLOCATED( pre_vars ) ) DEALLOCATE( pre_vars )
    IF ( ALLOCATED( A1 ) ) DEALLOCATE( A1 )
    IF ( ALLOCATED( A2 ) ) DEALLOCATE( A2 )
    IF ( ALLOCATED( lumdists ) ) DEALLOCATE( lumdists )
    IF ( ALLOCATED( mag_covmat ) ) DEALLOCATE( mag_covmat )
    IF ( ALLOCATED( stretch_covmat ) ) DEALLOCATE( stretch_covmat )
    IF ( ALLOCATED( colour_covmat ) ) DEALLOCATE( colour_covmat )
    IF ( ALLOCATED( mag_stretch_covmat ) ) DEALLOCATE( mag_stretch_covmat )
    IF ( ALLOCATED( mag_colour_covmat ) ) DEALLOCATE( mag_colour_covmat )
    IF ( ALLOCATED( stretch_colour_covmat ) ) &
        DEALLOCATE( stretch_colour_covmat )
    IF ( ALLOCATED( snabsdist ) ) DEALLOCATE( snabsdist )

    jla_prepped = .FALSE.
    END SUBROUTINE jla_cleanup

    !------------------------------------------------------------
    ! Routine for calculating the log-likelihood of the JLA
    ! data.  You _have_ to call this just after calling CAMB
    ! with the model you want to evaluate against.   It's assumed
    ! that you have called read_jla_dataset and jla_prep before
    ! trying this.
    !
    ! Arguments:
    !  CMB             Has the values of alpha and beta
    ! Returns:
    !  The negative of the log likelihood of the SN data with respect
    !  to the current mode
    !------------------------------------------------------------

    FUNCTION  JLA_alpha_beta_like(alpha, beta,  lumdists)
    real(mcp) :: JLA_alpha_beta_like
    CHARACTER(LEN=*), PARAMETER :: invfmt = &
    '("Error inverting cov matrix for ",F6.3,2X,F6.3)'

    INTEGER :: i, j, status
    real(mcp) :: lumdists(nsn)
    REAL(mcp) :: alpha, beta
    !We form an estimate for scriptm to improve numerical
    !accuracy in our marginaliztion
    REAL(mcp) :: estimated_scriptm, wtval
    REAL(mcp) :: chisq, chisq_pantheon, chisq_extra !Utility variables
    REAL(mcp) :: alphasq, betasq, alphabeta !More utility variables
    REAL(mcp) :: amarg_A, amarg_B, amarg_C
    REAL(mcp) :: amarg_D, amarg_E, amarg_F, tempG !Marginalization params
    real(mcp) :: diffmag(nsn),invvars(nsn)
!---CDE Start
	real(mcp), allocatable :: fisher
	real(mcp), allocatable :: diffmag_extra(:)
	real(mcp), allocatable :: deriv_sn(:)
	real(mcp), allocatable :: derivp_sn(:)
	real(mcp), allocatable :: new_diff_mag(:)					
!---CDE End    
    real(mcp), allocatable :: invcovmat(:,:)

    allocate(invcovmat(nsn,nsn))

!---CDE Start    
    allocate(diffmag_extra(nsn))
    allocate(deriv_sn(nsn))
    allocate(derivp_sn(nsn))
    allocate(new_diff_mag(nsn))
!---CDE End

    !    IF (.NOT. diag_errors) THEN
    !        ALLOCATE( invcovmat(nsn,nsn) )
    !    END IF

    alphasq   = alpha*alpha
    betasq    = beta*beta
    alphabeta = alpha*beta

    !We want to get a first guess at scriptm to improve the
    ! numerical precision of the results.  We'll do this ignoring
    ! the covariance matrix and ignoring if there are two scriptms
    ! to deal with

!---CDE Start    
	if (use_pantheon) then 
!---CDE End	
		invvars = 1.0 / ( pre_vars + 0.0*alphasq * sndata%stretch_var &
		+ betasq * sndata%colour_var &
		+ 2.0 * alpha * sndata%cov_mag_stretch &
		- 2.0 * beta * sndata%cov_mag_colour &
		- 2.0 * alphabeta * sndata%cov_stretch_colour )

		wtval = SUM( invvars )
		estimated_scriptm= SUM( (sndata%mag - lumdists)*invvars ) / wtval

		diffmag = sndata%mag - lumdists + alpha*( sndata%stretch - 1.0 ) - beta * sndata%colour - estimated_scriptm

		IF ( diag_errors ) THEN
		    amarg_A = SUM( invvars * diffmag**2 )
		    IF ( twoscriptmfit ) THEN
		        amarg_B = SUM( invvars * diffmag * A1)
		        amarg_C = SUM( invvars * diffmag * A2)
		        amarg_D = 0.0
		        amarg_E = DOT_PRODUCT( invvars, A1 )
		        amarg_F = DOT_PRODUCT( invvars, A2 )
		    ELSE
		        amarg_B = SUM( invvars * diffmag )
		        amarg_E = wtval
		    ENDIF
		ELSE
		    !Unfortunately, we actually need the covariance matrix,
		    ! and can't get away with evaluating terms this
		    ! V^-1 * x = y by solving V * y = x.  This costs us in performance
		    ! and accuracy, but such is life
		    CALL invert_covariance_matrix(invcovmat, alpha,beta,status)
		    IF (status .NE. 0) THEN
		        WRITE (*,invfmt) alpha,beta
		        JLA_alpha_beta_like = logZero
		        !            IF (.NOT. diag_errors) THEN
		        !                DEALLOCATE( invcovmat)
		        ! END IF
		        RETURN
		    ENDIF

		    !Now find the amarg_ parameters
		    !We re-use the invvars variable to hold the intermediate product
		    !which is sort of naughty
		    ! invvars = V^-1 * diffmag (invvars = 1.0*invcovmat*diffmag+0*invvars)
		    CALL DSYMV(uplo,nsn,1.0d0,invcovmat,nsn,diffmag,1,0.0d0,invvars,1)

		    amarg_A = DOT_PRODUCT( diffmag, invvars ) ! diffmag*V^-1*diffmag

		    IF (twoscriptmfit) THEN
		        amarg_B = DOT_PRODUCT( invvars, A1 ) !diffmag*V^-1*A1
		        amarg_C = DOT_PRODUCT( invvars, A2 ) !diffmag*V^-1*A2

		        !Be naughty again and stick V^-1 * A1 in invvars
		        CALL DSYMV(uplo,nsn,1.0d0,invcovmat,nsn,A1,1,0.0d0,invvars,1)
		        amarg_D = DOT_PRODUCT( invvars, A2 ) !A2*V^-1*A2	!---maybe typo : A2*V^-1*A1
		        amarg_E = DOT_PRODUCT( invvars, A1 ) !A1*V^-1*A1
		        ! now V^-1 * A2
		        CALL DSYMV(uplo,nsn,1.0d0,invcovmat,nsn,A2,1,0.0d0,invvars,1)
		        amarg_F = DOT_PRODUCT( invvars, A2 ) !A2*V^-1*A2
		    ELSE
		        amarg_B = SUM( invvars ) !GB = 1 * V^-1 * diffmag
		        !amarg_E requires a little care since only half of the
		        !matrix is correct if we used the full covariance matrix
		        !(which half depends on UPLO)
		        !GE = 1 * V^-1 * 1
		        amarg_C = 0.0_mcp
		        amarg_D = 0.0_mcp
		        amarg_E = 0.0_mcp
		        amarg_F = 0.0_mcp
		        
		        IF ( uplo .EQ. 'U' ) THEN
		            DO I=1,nsn
		                amarg_E = amarg_E + invcovmat(I,I) + 2.0_mcp*SUM(invcovmat(1:I-1,I))
		            END DO
		        ELSE
		            DO I=1,nsn
		                amarg_E = amarg_E + invcovmat(I,I) + 2.0_mcp*SUM(invcovmat(I+1:nsn,I))
		            END DO
		        END IF

		    ENDIF

		END IF

		IF (twoscriptmfit) THEN
		    !Messy case
		    tempG = amarg_F - amarg_D*amarg_D/amarg_E;
		    IF (tempG .LE. 0.0) THEN
		        WRITE(*,*) "Twoscriptm assumption violation"
		        STOP
		    ENDIF
		    chisq = amarg_A + LOG( amarg_E*inv_twopi ) + &
		    LOG( tempG * inv_twopi ) - amarg_C*amarg_C/tempG - &
		    amarg_B*amarg_B*amarg_F / ( amarg_E*tempG ) + 2.0*amarg_B*amarg_C*amarg_D/(amarg_E*tempG )
		ELSE
					
		    	chisq = amarg_A + LOG( amarg_E*inv_twoPI ) - amarg_B**2/amarg_E

		ENDIF
!---CDE Start
	else if (use_Pantheon_Plus) then

		do i=1,nsn		

			if (use_Pantheon_SH0ES) then
			
				if ((sndata(i)%zcmb .le. 0.01000d0) .and. (sndata(i)%thirdvar==0)) then 
			
					deriv_sn(i) = 0 
			
				else 
			
					deriv_sn(i) = 1.d0	
		
				end if 

			else 
			
				deriv_sn(i) = 1.d0
			
			end if
		
		end do
		
		diffmag_extra = sndata%mag - lumdists
		
		call invert_covariance_matrix(invcovmat, alpha, beta, status)

		!derivp_sn = 1.0*invcovmat*deriv_sn + 0*derivp_sn
		call DSYMV(uplo,nsn,1.d0,invcovmat,nsn,deriv_sn,1, 0.d0,derivp_sn,1)

		fisher = dot_product(deriv_sn,derivp_sn)
			
		call DSYRK(uplo, 'N', nsn, 1, -1.d0/fisher, derivp_sn, nsn, 1.d0, invcovmat, nsn)
	
		call DSYMV(uplo, nsn, 1.d0, invcovmat, nsn, diffmag_extra, 1, 0.d0, new_diff_mag, 1)
		
		chisq = dot_product(diffmag_extra, new_diff_mag)

		deallocate(diffmag_extra)
		deallocate(deriv_sn)
		deallocate(derivp_sn)			
		deallocate(new_diff_mag)	
		      
	end if			

!---CDE End    

    JLA_alpha_beta_like = chisq / 2  !Negative log likelihood

    IF (Feedback > 1 .and. .not. JLA_marginalize) THEN
        IF (Feedback > 2) THEN
            IF (twoscriptmfit) THEN
                WRITE(*,'(" JLA alpha: ",F7.4," beta: ",F7.4," scriptm1: ",F9.4, "scriptm2: ",F9.4)') &
                    alpha,beta,(amarg_B*amarg_F-amarg_C*amarg_D)/tempG,&
                    (amarg_C*amarg_E-amarg_B*amarg_D)/tempG
            ELSE
                WRITE(*,'(" JLA alpha: ",F7.4," beta: ",F9.4," scriptm: ",F9.4)') &
                    alpha,beta,-amarg_B/amarg_E
            ENDIF
        END IF
        WRITE(*,'(" JLA chi2: ",F7.2," for ",I5," SN")') chisq,nsn
    ENDIF

    !    IF (.NOT. diag_errors) THEN
    !        DEALLOCATE( invcovmat)
    !    END IF

    end FUNCTION  JLA_alpha_beta_like

    FUNCTION jla_LnLike(this, CMB, Theory, DataParams)
    Class(JLALikelihood) :: this
    Class(CMBParams) CMB
    Class(TCosmoTheoryPredictions), target :: Theory
    real(mcp) DataParams(:)
    ! norm_alpha, norm_beta are the positions of alpha/beta in norm
    REAL(mcp) :: jla_LnLike
    real(dl) grid_best, zhel, zcmb, alpha, beta, ceph_dist, is_calibrator, Mu_SH0ES
    integer grid_i, i

    jla_LnLike = logZero

    !Make sure we're ready to actually do this
    IF (.NOT. jla_read) THEN
        STOP 'JLA data not read in; must be by this point'
    ENDIF
    IF (.NOT. jla_prepped ) THEN
        STOP 'JLA data not prepped; run jla_prep'
    ENDIF

    !Get the luminosity distances.  CAMB doen't understand the
    ! difference between cmb and heliocentric frame redshifts.
    ! Camb gives us the angular diameter distance
    ! D(zcmb)/(1+zcmb) we want (1+zhel)*D(zcmb)
    !These come out in Mpc
    DO i=1,nsn
    	zhel = sndata(i)%zhel
        zcmb = sndata(i)%zcmb
!---CDE Start
        is_calibrator = sndata(i)%thirdvar
        ceph_dist = sndata(i)%colour

    	if (use_Pantheon_SH0ES) then    	

        	if (is_calibrator==1) then 

        		lumdists(i) = ceph_dist - 25.d0

        	else if ((zcmb .le. 0.01000d0) .and. (is_calibrator==0)) then  	

        		lumdists(i) = sndata(i)%mag	

    		else 

    			lumdists(i) = 5.0*LOG10((1.0+zhel)*(1.0+zcmb)*this%Calculator%AngularDiameterDistance(zcmb))

    		end if
    		
    	else 

    		lumdists(i) = 5.0*LOG10((1.0+zhel)*(1.0+zcmb)*this%Calculator%AngularDiameterDistance(zcmb))

    	end if
!---CDE End    	

    ENDDO

    !Handle SN with absolute distances
    IF ( has_absdist ) THEN
        DO i=1,nabsdist
            lumdists( snabsdist(i)%index ) = 5.0*LOG10(snabsdist(i)%dl)
        ENDDO
    ENDIF
    if (JLA_marginalize) then
        !$OMP PARALLEL DO DEFAULT(SHARED),SCHEDULE(STATIC), PRIVATE(alpha,beta, grid_i)
        do grid_i = 1, JLA_int_points
            alpha = alpha_grid(grid_i)
            beta=beta_grid(grid_i)
            JLA_marge_grid(grid_i) = JLA_alpha_beta_like(alpha, beta, lumdists)
        end do

        grid_best = minval(JLA_marge_grid,mask=JLA_marge_grid/=logZero)
        jla_LnLike =  grid_best - log(sum(exp(-JLA_marge_grid + grid_best),  &
            mask=JLA_marge_grid/=logZero)*JLA_step_width_alpha*JLA_step_width_beta)
        IF (Feedback > 1) THEN
            WRITE(*,'(" JLA best logLike ",F7.2,", marge logLike: ",F7.2," for ",I5," SN")') grid_best, jla_LnLike,nsn
        end if
    else
        alpha=DataParams(1)
        beta=DataParams(2)

        jla_LnLike=JLA_alpha_beta_like(alpha, beta, lumdists)
    end if

    END FUNCTION jla_LnLike

    END MODULE JLA
