
fast_BSFG_sampler_init_fixedlambda = function(priors,run_parameters,YNew,YOld){
  # require(PEIP)
  require(Matrix)
  
  # data_matrices,run_parameters,priors,current_state,Posterior,simulation = F)
  #   Preps everything for an analysis with the function MA_sampler. 
  #       Loads data from setup.mat
  #       Decides if the data is from a simulation
  #       Uses prior to find initial values for all parameters
  #       Initializes Posterior struct
  #       Saves run parameters
  #
  #   Input file setup.mat should contain:
  #     Y      gene expression data data: n x p
  #     X      fixed-effect design matrix (optional)
  #     Z_1    random effects 1 incidence matrix n x r1
  #     Z_2    random effects 2 incidence matrix n x r2 (optional)
  #     A      kinship matrix of lines: r1 x r1
  #     optional:
  #         U_act
  #         gen_factor_Lambda
  #         error_factor_Lambda
  #         h2_act
  #         G
  #         R
  #         B
  #         factor_h2s
  #         name
  
  # ----------------------- #
  # ------read data-------- #
  # ----------------------- #
  if(file.exists(paste0("../",YNew))) {
    load(paste0("../",YNew))
  } else{
    require(R.matlab)
    setup = readMat('../setup.mat')
    for(i in 1:10) names(setup) = sub('.','_',names(setup),fixed=T)
  }
  Y       = setup$Y
  U_act   = setup$U_act
  E_act   = setup$E_act
  Z_1     = setup$Z_1
  X       = setup$X
  A       = setup$A	
  n       = setup$n	
  r       = setup$r	
  B       = setup$B_act
  traitnames = setup$traitnames
  
  #Determine if 'setup.mat' contains output of a simulation, based on if
  #known factor loadings are included. Affects plotting functions
  simulation = F
  if('gen_factor_Lambda' %in% names(setup)){
    simulation = T
    print('simulated data')
    run_parameters$setup = setup
  }
  run_parameters$simulation = simulation
  
  #normalize Y to have zero mean and unit variances among observed values,
  #allowing for NaNs.
  n = nrow(Y)
  p = ncol(Y)
  r = ncol(Z_1)
  b = ncol(X)
  
  Y_missing = is.na(Y)        # matrix recording missing data in Y
  #standardize Y_new by using mean and var of Y_old
    load(paste0("../",YOld))
    Y_old = setup$Y

    Mean_Y  = colMeans(Y_old,na.rm=T)
    VY      = apply(Y_old,2,var,na.rm=T)
 
  
  # Don't remove the mean and standardize the variance if it's a
  # simulation because this makes comparing to the simulated values more
  # difficult. 
  # Do we want to do this for real data, or let the user do it?
  if(simulation) {
    VY = rep(1,p)
  } else{
    Y = sweep(Y,2,Mean_Y,'-')
    Y = sweep(Y,2,sqrt(VY),'/')
  }
  
  
  #Determine if a second random effects design matrix exists. If not, make a
  #dummy matrix
  if(! 'Z_2' %in% ls()) {
    Z_2=matrix(0,nr = n,nc = 0)
  }
  stopifnot(nrow(Z_2) == n)
  r2 = ncol(Z_2)
  
  
  data_matrices = list(
    Y         = Y,
    Z_1       = Z_1,
    Z_2       = Z_2,
    Y_missing = Y_missing,
    X         = X
  )

  
  # ----------------------------- #
  # -----Initialize variables---- #
  # ----------------------------- # 
  
  # --- transcript-level model
  # p-vector of probe residual precisions. 
  #  Prior: Gamma distribution for each element
  #       shape = resid_Y_prec_shape
  #       rate = resid_Y_prec_rate
  resid_Y_prec_shape  = priors$resid_Y_prec_shape
  resid_Y_prec_rate   = priors$resid_Y_prec_rate
  resid_Y_prec        = rgamma(p,shape = resid_Y_prec_shape,rate = resid_Y_prec_rate)
  
  # Factors:
  #  initial number of factors
  # Lambda is fixed which means k is also fixed
  if (file.exists("BSFG_state.RData")){
    load("BSFG_state.RData")
  }else{
    print("file BSFG_state.RData does not exist")
  }
  
  p = BSFG_state$run_variables$p
  k = nrow(BSFG_state$Posterior$Lambda)/p
  
  
   Lambda = BSFG_state$Posterior$Lambda
   #B should also be random(not fixed)
   #B      = BSFG_state$Posterior$B
   
  
  # g-vector of specific precisions of genetic effects. 
  #  Prior: Gamma distribution for each element
  #       shape = E_a_prec_shape
  #       rate = E_a_prec_rate
  E_a_prec_shape = priors$E_a_prec_shape
  E_a_prec_rate  = priors$E_a_prec_rate
  E_a_prec       = rgamma(p,shape = E_a_prec_shape,rate = E_a_prec_rate)
  
  # Genetic effects not accounted for by factors.
  #   Prior: Normal distribution on each element.
  #       mean = 0
  #       sd = 1./sqrt(E_a_prec)' on each row
  E_a = matrix(rnorm(p*r,0,sqrt(1/E_a_prec)),nr = r,nc = p, byrow = T)
  
  # Latent factor heritabilties. h2 can take h2_divisions values
  #   between 0 and 1.
  #   Prior: 0.5: h2=0, .05: h2 > 0. 
  F_h2 = runif(k)
  
  # Genetic effects on the factor scores.
  #  Prior: Normal distribution for each element
  #       mean = 0
  #       sd = sqrt(F_h2') for each row.
  F_a = matrix(rnorm(k*r,0,sqrt(F_h2)),nr = r,nc = k, byrow = T)
  
  # Full Factor scores. Combination of genetic and residual variation on
  # each factor.
  #  Prior: Normal distribution for each element
  #       mean = Z_1 * F_a
  #       sd = sqrt(1-F_h2') for each row.
  F = Z_1 %*% F_a + matrix(rnorm(k*n,0,sqrt(1-F_h2)),nr = n,nc = k, byrow = T)    
  
  # g-vector of specific precisions of genetic effects. 
  #  Prior: Gamma distribution for each element
  #       shape = E_a_prec_shape
  #       rate = E_a_prec_rate
  W_prec_shape = priors$W_prec_shape
  W_prec_rate  = priors$W_prec_rate
  W_prec       = rgamma(p,shape = W_prec_shape,rate = W_prec_rate)
  
  # Genetic effects not accounted for by factors.
  #   Prior: Normal distribution on each element.
  #       mean = 0
  #       sd = 1./sqrt(E_a_prec)' on each row
  W = matrix(rnorm(p*r2,0,sqrt(1/W_prec)),nr = r2, nc = p, byrow = T)
  
  # Fixed effect coefficients.
  #  Prior: Normal distribution for each element
  #       mean = 0
  #       sd = sqrt(1/fixed_effects_prec)
  B = matrix(rnorm(b*p),nr = b, nc = p)
  
  
  # ----------------------- #
  # -Initialize Posterior-- #
  # ----------------------- #
  
  Posterior = list(
    F_a           = matrix(0,nr=0,nc=0),
    F             = matrix(0,nr=0,nc=0),
    F_h2          = matrix(0,nr=0,nc=0),
    resid_Y_prec  = matrix(0,nr = p,nc = 0),
    E_a_prec      = matrix(0,nr = p,nc = 0),
    W_prec        = matrix(0,nr = p,nc = 0),
    W             = matrix(0,nr = r2,nc = p),
    B             = matrix(0,nr = b,nc = p),
    E_a           = matrix(0,nr = r,nc = p)
  )
  # ----------------------- #
  # ---Save initial values- #
  # ----------------------- #
  current_state = list(
    resid_Y_prec  = resid_Y_prec,
    F_h2          = F_h2,
    E_a_prec      = E_a_prec,
    W_prec        = W_prec,
    F_a           = F_a,
    F             = F,
    B             = B,
    E_a           = E_a,
    W             = W,
    nrun 		  = 0
  )
  
  
  # ------------------------------------ #
  # ----Precalculate some matrices------ #
  # ------------------------------------ #

  # recover()
  #invert the random effect covariance matrices
  Ainv = solve(A)
  A_2_inv = diag(1,r2) #Z_2 random effects are assumed to have covariance proportional to the identity. Can be modified.
  
  #pre-calculate transformation parameters to diagonalize aI + bZAZ for fast
  #inversion: inv(aI + bZAZ) = 1/b*U*diag(1./(s+a/b))*U'
  #uses singular value decomposition of ZAZ for stability when ZAZ is low
  #rank
  #     XZ = [X_f Z_1]
  #     [U,S,~]          = svd(XZ*blkdiag(1e6*eye(b_f),A)*XZ')
  # recover()
  # r = rgamma(nrow(Z_1),1,1)
  # result = GSVD_2_c(cholcov(diag(r)),cholcov(Z_1 %*% A %*% t(Z_1)))
  # r2 = rgamma(nrow(Z_1),1,1)
  # result2 = GSVD_2_c(cholcov(diag(r2)),cholcov(Z_1 %*% A %*% t(Z_1)))
  
  result = svd(Z_1 %*% A %*% t(Z_1))
  invert_aI_bZAZ = list(
    U = result$u,
    s = result$d
  )
 
  #fixed effects + random effects 1
  #diagonalize mixed model equations for fast inversion: 
  #inv(a*bdiag(priors$b_X_prec,Ainv) + b*t(cbind(X,Z_1)) %*% cbind(X,Z_1)) = U %*% diag(1/(a*s1+b*s2)) %*% t(U)
  Design= cbind(Z_1)
  Design2 = t(Design) %*% Design
  result = GSVD_2_c(cholcov(Ainv),cholcov(Design2))
  invert_aPXA_bDesignDesignT = list(
    U = t(solve(result$X)),
    s1 = diag(result$C)^2,
    s2 = diag(result$S)^2
  )
  invert_aPXA_bDesignDesignT$Design_U = Design %*% invert_aPXA_bDesignDesignT$U

  #random effects 2
  #diagonalize mixed model equations for fast inversion: 
  #inv(a*A_2_inv + b*Z_2'Z_2]) = U*diag(1./(a.*s1+b.*s2))*U'
  if(r2 > 0) {
    Design = Z_2
    Design2 = t(Design) %*% Design
    result = GSVD_2_c(cholcov(A_2_inv),cholcov(Design2))
    invert_aPXA_bDesignDesignT_rand2 = list(
      U = t(solve(result$X)),
      s1 = diag(result$C)^2,
      s2 = diag(result$S)^2
    )
    invert_aPXA_bDesignDesignT_rand2$Design_U = Design %*% invert_aPXA_bDesignDesignT_rand2$U
  } else{
    invert_aPXA_bDesignDesignT_rand2 = list()
  }
 
  #genetic effect variances of factor traits
  # diagonalizing a*Z_1'*Z_1 + b*Ainv for fast inversion
  #diagonalize mixed model equations for fast inversion: 
  # inv(a*Z_1'*Z_1 + b*Ainv) = U*diag(1./(a.*s1+b.*s2))*U'
  #similar to fixed effects + random effects 1 above, but no fixed effects.
  ZZt = t(Z_1) %*% Z_1
  result = GSVD_2_c(cholcov(ZZt),cholcov(Ainv))
  invert_aZZt_Ainv = list(
    U = t(solve(result$X)),
    s1 = diag(result$C)^2,
    s2 = diag(result$S)^2
  )
  
  # ----------------------------- #
  # ----Save run parameters------ #
  # ----------------------------- #
  
  run_variables = list(
    p       = p,
    n       = n,
    r       = r,
    r2      = r2,
    b       = b,
    Mean_Y  = Mean_Y,
    VY      = VY,
    Ainv    = Ainv,
    A_2_inv = A_2_inv,
    invert_aI_bZAZ                   = invert_aI_bZAZ,
    invert_aPXA_bDesignDesignT       = invert_aPXA_bDesignDesignT,
    invert_aZZt_Ainv                 = invert_aZZt_Ainv,
    invert_aPXA_bDesignDesignT_rand2 = invert_aPXA_bDesignDesignT_rand2
  )
  
  RNG = list(
    Random.seed = .Random.seed,
    RNGkind = RNGkind()
  )
  
  return(list(
    data_matrices  = data_matrices,
    run_parameters = run_parameters,
    run_variables  = run_variables,
    priors         = priors,
    current_state  = current_state,
    Posterior      = Posterior,
    simulation     = simulation,
    RNG            = RNG,
    traitnames     = traitnames,
    Lambda         = Lambda
  ))
}
