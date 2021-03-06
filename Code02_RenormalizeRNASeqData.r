#################################################################################################
##  These scripts take data from the the Aging, Dementia, and TBI website along with supplementary 
##  materials and uses it to perform all analyses for the TBI manuscript 
#################################################################################################

# R version 3.2.5 (2016-04-14) -- "Very, Very Secure Dishes" was used for the analysis, but the code should
# be compatible with most of the recent versions of R.

#################################################################################################
print("***** -------------------------------------------")
print("***** Code #2: Re-normalize RNA-Seq data.")
print("***** -------------------------------------------")

######################################################################################################################
######################################################################################################################
######################################################################################################################
######################################################################################################################
## BEGIN FUNCTIONS

normalizeByTbT <- function(datInput, dexVector){
  # normalizeByTbT - This function performs TbT normalization on RNA-Seq data.  It is a version of the R scripts 
  #  generated by Robinson and Oshlack (Genome Biol., 11:R25, 2010).  Robinson and Oshlack get full credit for 
  #  the TbT normalization algorithm used here.  Note that it requires several R libraries to be installed.

  ## Load libraries and get appropriate input data
  # library(baySeq);  library(edgeR);  library(DESeq);  library(NBPSeq);  library(ROC)  # Libraries loaded in main script
  # source("http://bioinf.wehi.edu.au/folders/tmm_rnaseq/functions.R")
    # R scripts created by Robinson and Oshlack, Genome Biol., 11:R25, 2010, and copied below

  data    <- datInput
  data.cl <- dexVector
  RPM     <- sweep(data, 2, 1000000/colSums(data), "*") # Convert to RPM
  groups  <- list(NDE=rep(1, length(data.cl)), DE=data.cl)

  ##  Generation of initial TMM-normalized data
  d          <- DGEList(counts=data, group=data.cl)
  d          <- calcNormFactors(d)
  norm_f_TMM <- d$samples$norm.factors
  RPM_TMM    <- sweep(RPM, 2, 1/norm_f_TMM, "*")

  ##  TbT normalization
  data <- round(RPM)
  hoge <- new("countData", data=as.matrix(data), replicates=data.cl, libsizes=colSums(data)*norm_f_TMM, groups=groups)
  hoge.NB <- getPriors.NB(hoge, samplesize=2000, estimation="QL", cl=NULL)   # THIS IS A SLOW STEP!
  out <- getLikelihoods.NB(hoge.NB, pET="BIC", cl=NULL)                      # THIS IS A VERY SLOW STEP!
  PDEG <- out@estProps[2]
  rank_bayseq <- rank(-out@posteriors[,2])
  DEGnum <- (nrow(data) * PDEG)

  data <- RPM_TMM                                         # For calculating PA value (legacy code, PA not used)
  meanA <- log2(apply(data[,data.cl==1], 1, mean))        # For calculating PA value (legacy code, PA not used)
  meanB <- log2(apply(data[,data.cl==2], 1, mean))        # For calculating PA value (legacy code, PA not used)
  y_axis <- meanB - meanA                                 # For calculating PA value (legacy code, PA not used)
  PA <- sum(y_axis[rank_bayseq < DEGnum] < 0)/DEGnum      # For calculating PA value (legacy code, PA not used)

  obj_DEGn <- (rank_bayseq >= DEGnum)
  data <- datInput[obj_DEGn,]
  d <- DGEList(counts=data, group=data.cl)
  d <- calcNormFactors(d)
  norm_f_TbT_RAW <- 1000000/(colSums(data)*d$samples$norm.factors)
  norm_f_TbT <- d$samples$norm.factors*colSums(data)/colSums(datInput)
  RPM_TbT <- sweep(RPM, 2, 1/norm_f_TbT, "*")
  return(RPM_TbT)
}

## The scripts below are additional functions required for TbT normlization and are copied 
##   directly from this web link: http://bioinf.wehi.edu.au/folders/tmm_rnaseq/functions.R


plotReverseCumDist <- function(x, xlab="Tag count X", ylab="# tags >= X", add=FALSE, ...) {
  v <- ecdf(x)
  matplot( knots(v), (1-v(knots(v)))*sum(D[,1]), log="xy", xlab=xlab, ylab=ylab, add=add, ... )
}

generateDataset2 <- function(commonTags=15000, uniqueTags=c(1000,3000), group=c(1,2), libLimits=c(.9,1.1)*1e6, 
                            empiricalDist=NULL, lengthDist=NULL, pDifferential=.05, pUp=.5, foldDifference=2, nreps=c(2,2)) {
                            
  # some checks
  stopifnot( length(group) == length(uniqueTags) )
  stopifnot( length(group) == length(nreps) )
  stopifnot( length(empiricalDist) == length(lengthDist) )
  group <- as.factor(rep(group,nreps))
  stopifnot( nlevels(group) == 2 ) 
  
  print(group)

  #exampleCounts <- empiricalDist/lengthDist
  exampleCounts <- empiricalDist
  exampleLambda <- exampleCounts/sum(exampleCounts)
  exampleIds <- seq_len( length(empiricalDist) )
 
  # set up libraries
  nLibraries <- sum( nreps )
  libSizes <- runif(nLibraries, min=libLimits[1], max=libLimits[2] )

  # vector of starts/stops for the unique Tags
  en <- commonTags + cumsum(uniqueTags)
  st <- c(commonTags+1,en[-nLibraries]+1)

  # create matrix of LAMBDA(=relative expression levels)
  LAMBDA <- matrix(0, nrow=max(en), ncol=nLibraries)
  
  ID <- rep(0, max(en))
  ID[1:commonTags] <- sample(exampleIds, commonTags, replace=TRUE)
  LAMBDA[1:commonTags,] <- exampleLambda[ ID[1:commonTags] ]

  # set unique tag totals
  for(i in 1:length(nreps))
    if(uniqueTags[i] > 0) {
      ID[st[i]:en[i]] <- sample(exampleIds, uniqueTags[i], replace=TRUE)
      LAMBDA[st[i]:en[i],group==levels(group)[i]] <- exampleLambda[ ID[st[i]:en[i]] ]
    }
    
  g <- group == levels(group)[1]
  ind <- seq_len(floor(pDifferential*commonTags))
  if(length(ind)>0) {
    fcDir <- sample(c(-1,1), length(ind), prob=c(1-pUp,pUp), replace=TRUE)
    LAMBDA[ind,g] <- LAMBDA[ind,g]*exp(log(foldDifference)/2*fcDir)
    LAMBDA[ind,!g] <- LAMBDA[ind,!g]*exp(log(foldDifference)/2*(-fcDir))
  }

  sampFactors <- colSums(LAMBDA)

  sampFactorsM <- outer( rep(1,max(en)), sampFactors )
  libSizesM <- outer(  rep(1,max(en)), libSizes )

  # create observed means
  MEAN <- LAMBDA / sampFactorsM * libSizesM  # to get the totals to sum to 1

  # sample observed data (column sums will be *close* to set library sizes)
  DATA <- matrix(0, nr=nrow(LAMBDA), ncol=nLibraries)
  DATA <- matrix(rpois(length(MEAN), lambda=MEAN),ncol=nLibraries)

  trueFactors <- colSums(MEAN[1:commonTags,])
  trueFactors <- trueFactors/trueFactors[1]
  
  colnames(DATA) <- paste(paste("group",group,sep=""),1:ncol(DATA),sep=".")
  
  list(DATA=DATA, LAMBDA=LAMBDA, MEAN=MEAN, trueFactors=trueFactors, group=group, libSizes=libSizes,  
       differentialInd=c(ind,(commonTags+1):nrow(DATA)), commonInd=1:commonTags, ID=ID, length=lengthDist[ID])
}

takeSubset <- function(obj, subsetInd) {
  allInd <- 1:nrow(obj$DATA)
  commonInd <- allInd %in% obj$commonInd
  differentialInd <- allInd %in% obj$differentialInd
  list(DATA=obj$DATA[subsetInd,], LAMBDA=obj$LAMBDA[subsetInd,], trueFactors=obj$trueFactors, group=obj$group, 
       libSizes=obj$libSizes, differentialInd=which(differentialInd[subsetInd]), commonInd=which(commonInd[subsetInd]),
   ID=obj$ID[subsetInd], length=obj$length[subsetInd])
}

generateDataset <- function(commonTags=15000, uniqueTags=c(1000,3000), group=c(1,2), libLimits=c(.9,1.1)*1e6, 
                            empiricalDist=NULL, randomRate=1/100, pDifferential=.05, pUp=.5, foldDifference=2) {
                            
  # some checks
  group <- as.factor(group)
  stopifnot( length(group) == length(uniqueTags) )
  #stopifnot( length(group) == 2 ) # code below only works for 2 samples
  stopifnot( nlevels(group) == 2 ) 

  # define where to take random sample from (empirical distribution OR random exponential)
  if(is.null(empiricalDist))
    exampleCounts <- ceiling(rexp(commonTags,rate=randomRate))
  else
    exampleCounts <- empiricalDist
  
  exampleLambda <- exampleCounts/sum(exampleCounts)
 
  # set up libraries
  nLibraries <- length(uniqueTags)
  libSizes <- runif(nLibraries, min=libLimits[1], max=libLimits[2] )

  # vector of starts/stops for the unique Tags
  en <- commonTags + cumsum(uniqueTags)
  st <- c(commonTags+1,en[-nLibraries]+1)

  # create matrix of LAMBDA(=relative expression levels)
  LAMBDA <- matrix(0, nrow=max(en), ncol=nLibraries)
  LAMBDA[1:commonTags,] <- sample(exampleLambda, commonTags, replace=TRUE)

  # set unique tag totals
  for(i in 1:nLibraries)
    if(uniqueTags[i] > 0)
      LAMBDA[st[i]:en[i],i] <- sample(exampleLambda, uniqueTags[i])    
    
  ind <- seq_len(floor(pDifferential*commonTags))
  g <- group == levels(group)[1]
  if(length(ind)>0) {
    fcDir <- sample(c(-1,1), length(ind), prob=c(1-pUp,pUp), replace=TRUE)
    LAMBDA[ind,g] <- LAMBDA[ind,!g]*exp(log(foldDifference)/2*fcDir)
    LAMBDA[ind,!g] <- LAMBDA[ind,!g]*exp(log(foldDifference)/2*(-fcDir))
  }
  
  sampFactors <- colSums(LAMBDA)

  sampFactorsM <- outer( rep(1,max(en)), sampFactors )
  libSizesM <- outer(  rep(1,max(en)), libSizes )

  # create observed means
  MEAN <- LAMBDA / sampFactorsM * libSizesM

  # sample observed data (column sums will be *close* to set library sizes)
  DATA <- matrix(rpois(length(MEAN), lambda=MEAN),ncol=nLibraries)

  trueFactors <- colSums(MEAN[1:commonTags,])
  trueFactors <- trueFactors/trueFactors[1]
  list(DATA=DATA, LAMBDA=LAMBDA, MEAN=MEAN, trueFactors=trueFactors, group=group, libSizes=libSizes,  differentialInd=c(ind,(commonTags+1):nrow(DATA)), 
  commonInd=1:commonTags)
}

calcFactor <- function(obs, ref, trim=.45) {
  logR <- log2(obs/ref)
  fin <- is.finite(logR)
  2^mean(logR[fin],trim=trim)
}

Poisson.model <- function(MA,group1,group2){

  require(limma)
  Poisson.glm.pval <- vector()
  Fold.changes <- vector()
  
  CS <- colSums(MA$M[,c(group1,group2)])

  for (i in 1:(nrow(MA))){
    S1 <- MA$M[i,group1] 
    S2 <- MA$M[i,group2] 
    In <- c(S1,S2)
    sample.f <- factor(c(rep(1,length(group1)),rep(2,length(group2))))
    In <- as.vector(unlist(In))
    GLM.Poisson <- glm(In ~ 1 + sample.f + offset(log(CS)),family=poisson)
    Poisson.glm.pval[i] <- anova(GLM.Poisson,test="Chisq")[5][2,1]
    Fold.changes[i] <- exp(GLM.Poisson$coefficients[1])/(exp(GLM.Poisson$coefficients[1]+GLM.Poisson$coefficients[2]))
  }
  
  output <- matrix(ncol=2,nrow=nrow(MA$M))
  output[,1] <- Poisson.glm.pval
  output[,2] <- Fold.changes
  output <- as.data.frame(output)
  names(output) <- c("pval","FC")
  output
}

Poisson.model.new <- function(countMatrix,group1,group2, ref=1, calcFactor=TRUE){

  Poisson.glm.pval <- vector()
  Fold.changes <- vector()
  
  props <- countMatrix / outer( rep(1,nrow(countMatrix)), colSums(countMatrix) )
  
  refS <- colSums(countMatrix[,c(group1,group2)])
  
  if( calcFactor ) {
    require(edgeR)
  CS <- calcNormFactors(countMatrix[,c(group1,group2)])
  } else {
    CS <- rep(1,length(group1)+length(group2))
  }
  
  offsets <- log(CS)+log(refS)

  sample.f <- factor(c(rep(1,length(group1)),rep(2,length(group2))))
  
  for (i in 1:(nrow(countMatrix))){
    S1 <- countMatrix[i,group1] 
    S2 <- countMatrix[i,group2] 
    In <- c(S1,S2)
    In <- as.vector(unlist(In))
    GLM.Poisson <- glm(In ~ 1 + sample.f + offset(offsets),family=poisson)
    Poisson.glm.pval[i] <- anova(GLM.Poisson,test="Chisq")[5][2,1]
    Fold.changes[i] <- exp(GLM.Poisson$coefficients[1])/(exp(GLM.Poisson$coefficients[1]+GLM.Poisson$coefficients[2]))
    if(i %% 100==0) cat(".")
  }
  cat("\n")
  
  #output <- matrix(ncol=2,nrow=nrow(countMatrix))
  #output[,1] <- Poisson.glm.pval
  #output[,2] <- Fold.changes
  #output <- as.data.frame(output)
  #names(output) <- c("pval","FC")
  
  list(stats=data.frame(pval=Poisson.glm.pval, FC=Fold.changes),offsets=offsets,factors=CS)
}

exactTestPoisson <- function(dataMatrix, meanMatrix, group1Ind, group2Ind, verbose=TRUE) {
  
  y1 <- rowSums(dataMatrix[,group1Ind])
  y2 <- rowSums(dataMatrix[,group2Ind])
  m1 <- rowSums(meanMatrix[,group1Ind])
  m2 <- rowSums(meanMatrix[,group2Ind])
  
  N <- rowSums( dataMatrix[,c(group1Ind,group2Ind)] )
  
  pvals <- rep(NA, nrow(dataMatrix))
  
  for (i in 1:length(pvals)) {
    v <- 0:N[i]
    p.top <- dpois(v, lambda=m1[i]) * dpois(N[i]-v, lambda=m2[i])
    p.obs <- dpois(y1[i], lambda=m1[i]) * dpois(y2[i], lambda=m2[i])
    p.bot <- dpois(N[i], lambda=m1[i]+m2[i])
    keep <- p.top <= p.obs
    pvals[i] <- sum(p.top[keep]/p.bot)
    if (verbose)
        if (i%%1000 == 0)
          cat(".")
  }
  if (verbose)
    cat("\n")
    
  pvals

}

calcFactorRLM <- function(obs, ref, logratioTrim=.20, sumTrim=0.01) {

  if( all(obs==ref) )
    return(1)

  nO <- sum(obs)
  nR <- sum(ref)
  logR <- log2((obs/nO)/(ref/nR))         # log ratio of expression, accounting for library size
  p0 <- obs/nO
  pR <- ref/nR
  
  x <- log2(p0)-log2(pR)
  x <- x[ !is.na(x) & is.finite(x) ]
  
  r <- rlm(x~1, method="MM")
  2^r$coef
  
}

calcFactorWeighted <- function(obs, ref, logratioTrim=.3, sumTrim=0.05) {

  if( all(obs==ref) )
    return(1)

  nO <- sum(obs)
  nR <- sum(ref)
  logR <- log2((obs/nO)/(ref/nR))         # log ratio of expression, accounting for library size
  absE <- log2(obs/nO) + log2(ref/nR)     # absolute expression
  v <- (nO-obs)/nO/obs + (nR-ref)/nR/ref  # estimated asymptotic variance
  
  fin <- is.finite(logR) & is.finite(absE)
  
  logR <- logR[fin]
  absE <- absE[fin]
  v <- v[fin]

  # taken from the original mean() function
  n <- sum(fin)
  loL <- floor(n * logratioTrim) + 1
  hiL <- n + 1 - loL
  loS <- floor(n * sumTrim) + 1
  hiS <- n + 1 - loS
  
  keep <- (rank(logR) %in% loL:hiL) & (rank(absE) %in% loS:hiS)
  2^( sum(logR[keep]/v[keep], na.rm=TRUE) / sum(1/v[keep], na.rm=TRUE) )
  
}

calcFactor2 <- function(obs, ref) {
  logR <- log2(obs/ref)
  fin <- is.finite(logR)
  d<-density(logR,na.rm=TRUE)
  2^d$x[which.max(d$y)]
}


fdPlot <- function( score, indDiff, add=FALSE, xlab="Number of Genes Selected", 
                    ylab="Number of False Discoveries", lwd=4, type="l", ... ) {
  o <- order(score)
  w <- o %in% indDiff
  x <- 1:length(indDiff)
  y <- cumsum(!w[indDiff])
  matplot(x, y, xlab=xlab, ylab=ylab, lwd=lwd, type=type, add=add, ... )
}

## End functions for TbT normalization
######################################################################################################################


getCorrectForRIN_1or2Groups <- function(x,RIN,adjRIN = (RIN-mean(RIN))^2,pThresh=0.0001,minGrp = 5, returnClassification = FALSE, numSD = 3){    

 ## REMOVE ZEROS AND DEFINE OUTLIERS
 nm  = names(x)
 x   = as.numeric(as.character(x))
 names(x) = nm
 is0 = x<=0
 out = !((x<(mean(x[!is0])+numSD*sd(x[!is0])))&(x>(mean(x[!is0])-numSD*sd(x[!is0]))))
 kp2 = (!is0)&(!out)

 ## DETERMINE GROUPS
 classification = -1
 yyy = Mclust(x[kp2],G=1:2,verbose=FALSE)
 if(max(yyy$classification)>1){
  classification = yyy$classification
  tc  = table(classification)
  if(min(tc)>minGrp){
   p = t.test(RIN[kp2][classification==1],RIN[kp2][classification==2])$p.value
   if (p<pThresh){
    classification = -3
   }
  } else {
   out = out|is.element(names(x),names(classification)[classification==which(tc==min(tc))])
   kp2 = (!is0)&(!out)
   classification = -2
  }
 }
 numClass = ifelse(classification[1]<0,classification[1],2)
 if(classification[1]<0) classification = x[kp2]/x[kp2]
 classes = unique(classification)
 if (returnClassification) return(length(classes))
 
 ## ACCOUNT FOR RIN FOR ALL SAMPLES IN A GROUP
 xNew = x
 for (cl in classes){
  kpG = classification==cl
  lmTmp = lm(x[kp2][kpG] ~ RIN[kp2][kpG] + adjRIN[kp2][kpG])
  xNew[kp2][kpG] = mean(x[kp2][kpG]) + lmTmp$residuals
 }
 out = c(xNew,numClass)
 return(out)
}

is0orOutlier = function(x,numSD = 3){
 x   = as.numeric(as.character(x))
 is0 = x<=0
 out = !((x<(mean(x[!is0])+numSD*sd(x[!is0])))&(x>(mean(x[!is0])-numSD*sd(x[!is0]))))
 return((!is0)&(!out))
}

## END FUNCTIONS
######################################################################################################################
######################################################################################################################
######################################################################################################################
######################################################################################################################





#################################################################################################
print("Include only the genes present in the analysis and re-name by gene symbol")

datExprUp = datExprU[isPresent,]
rownames(datExprUp) = geneInfo$gene_symbol[isPresent]
datExprUp = datExprUp[sort(rownames(datExprUp)),]
datExprNp = datExprN[isPresent,]
rownames(datExprNp) = geneInfo$gene_symbol[isPresent]
datExprNp = datExprNp[rownames(datExprUp),]


#################################################################################################
print("Perform the TbT strategy from Kadota et al 2012 on FPKM, comparing cortex vs. HIP/FWM")
print("====== NOTE: to save space, a pre-calculated version of this matrix is loaded by default.")
print("======   To generate your own, please visidt Code02 and uncomment relevant section.")

set.seed(111)     # Seed is set for reproducibility.
regGroup   = is.element(region,c("TCx","PCx"))

## To rerun TbT normalization, uncomment code below and comment 'load(paste0(extraFolder,"TbT_normalization.RData"))' 
#datExprTbt = normalizeByTbT(datExprUp, regGroup)
#scale_Tbt  = mean(as.matrix(datExprUp))/mean(as.matrix(datExprTbt))
#datExprTbt = datExprTbt*scale_Tbt
#save(datExprTbt,scale_Tbt,file="TbT_normalization.RData")  # Code sometimes crashes after this step, so save the normalization!
## End code to uncomment

load(paste0(extraFolder,"TbT_normalization.RData"))  
collectGarbage()


#################################################################################################
print("Take the normalized FPKM values after accounting for RIN.")

# We have changed the normalization strategy from the website as follows:
# 1) No longer correct or batch (which introduces some biases) and instead flag genes with significant batch effects (for batches 9 and 10)
# 2) Correct for RIN + adjusted RIN instead of RIN squared -- note that these produce IDENTICAL results.
# 3) Correct for RIN on log2(expr+1) data rather than linear data.  These lead to very similar results as the linear correction.
# 4) Exclude values that are exactly 0 or are outliers from the RIN correction.  This has a minor effect but can remove leverage points.
# 5) Computationally determine if expression data is best fit by one or two gaussians.  If two, correct for RIN separately for each group.

datExprTb2 = log2(datExprTbt+1)       # USE THIS ONE
pThresh    = 0.05/dim(datExprTb2)[1]  # Bonferroni corrected p=0.05
minGrp     = 0.02*dim(datExprTb2)[2]  # Don't consider groups of less than 2% of total samples (i.e., <8 samples total)
datExprRg  = datExprTb2
numberOfGroups = matrix(1,nrow=dim(datExprTb2)[1],ncol=length(regions))  # This marks the number of groups in the normalization
rownames(numberOfGroups) = rownames(datExprTb2)
colnames(numberOfGroups) = regions
is0 = numberOfGroups  # This marks the number of 0 values or outliers excluded from the normalization
for (r in regions){
 print(r)
 kpR     = region==r
 RIN     = sampleRIN[kpR]
 adjRIN  = (RIN-mean(RIN))^2
 is0[,r] = colSums(!apply(datExprTb2[,kpR],1,is0orOutlier));
 is0[is.na(is0)]    = 
 datExprRg[,kpR]    = t(apply(datExprTb2[,kpR],1,getCorrectForRIN_1or2Groups,RIN,adjRIN,pThresh,minGrp,returnClassification=FALSE))
 numberOfGroups[,r] = apply(datExprTb2[,kpR],1,getCorrectForRIN_1or2Groups,RIN,adjRIN,pThresh,minGrp,returnClassification=TRUE)
 collectGarbage()
}
datExprRg[datExprRg<0] = 0  # Reset any 0 samples that were moved greater than 0 back to 0.
write.csv(datExprRg,"RIN_corrected_FPKM.csv")  # For sharing on GEO
save(datExprRg,file="RIN_corrected_FPKM.RData")

isTwoGroups = apply(numberOfGroups,1,max)>1
print(paste(round(1000*mean(isTwoGroups))/10,"% of genes best fit by two clusters.",sep=""))


#########################################################################################################
# To summarize the above steps:                                                                         #
# 1) Start with RPKM values                                                                             #
# 2) Exclude all genes with FPKM > 2 in <10% of samples in every region                                 #
# 3) TbT normalization to scale RPKM based on gene expression of non-DEX genes                          #
# 4) Correct for RIN and adjusted RIN in one or two groups (separately in each region)                  #
# 5) Test for batch effects                                                                             #
# 6) Moving forward, flag genes with batch effects or that were corrected in 2 groups in any region.    #
#########################################################################################################


#################################################################################################
print("Perform principle component analysis to find the general expression across the data set.")

gnUse  = rownames(datExprRg)
datUse = datExprRg[gnUse,]
pcaUse = prcomp(t(datUse))
varExp = round(1000*(pcaUse$sdev)^2 / sum(pcaUse$sdev^2))/10
px     = pcaUse$rotation[,1]
py     = pcaUse$rotation[,2]
xlc    = paste("-PC 1: ",varExp[1],"% var explained")
ylc    = paste("PC 2: ",varExp[2],"% var explained")
pcFWMc = -pcaUse$x[,1]
pcHIPc = pcaUse$x[,2]

datUse = datExprTb2[gnUse,]
pcaUse = prcomp(t(datUse))
varExp = round(1000*(pcaUse$sdev)^2 / sum(pcaUse$sdev^2))/10
px     = pcaUse$rotation[,1]
py     = pcaUse$rotation[,2]
xlu    = paste("-PC 1: ",varExp[1],"% var explained")
ylu    = paste("PC 2: ",varExp[2],"% var explained")
pcFWMu = -pcaUse$x[,1]
pcHIPu = pcaUse$x[,2]

pdf("SupFigure_XX_PCAplots.pdf") 
plot(pcFWMc,pcHIPc,pch=19,col=regionColors,cex=1,xlab=xlc,ylab=ylc,main="RIN-corrected, color by region")
plot(pcFWMu,pcHIPu,pch=19,col=regionColors,cex=1,xlab=xlu,ylab=ylu,main="Uncorrected, color by region")
plot(pcFWMu,pcHIPu,pch=19,col=numbers2colors(pmax(sampleInfo$RIN,4)),cex=1,xlab=xlu,ylab=ylu,main="Uncorrected, color by RIN")
points(pcFWMu,pcHIPu,pch=19,col="black",cex=0.1)
dev.off()
# There is much less separation by brain region if we don't correct by RNA quality.


#################################################################################################
print("Run MDMR to find the percent of variance explained by each of the variables")

source(paste0(scriptsFolder,"mdmr_r.beta.1.0.1.r"))

mdmrInfo = cbind(sampleRIN,comparisonInfo)
mdmrInfo$apo_e4_allele[mdmrInfo$apo_e4_allele=="N/A"] = NA
mdmrInfo$apo_e4_allele = droplevels(mdmrInfo$apo_e4_allele)
omit = is.element(colnames(mdmrInfo),c("longest_loc_duration","ADorControl"))
mdmrInfo = mdmrInfo[,!omit]

dmatrixCorU <- mdmrOutCorU <- list()
for (r in regions){
 kpS = region==r
 dmatrixCorU[[r]] = as.matrix(dist(1-cor(datUse[,kpS],use="na.or.complete")))
   #t(datUse[,kpS])))  # sqrt(1-cor(datUse[,kpS],use="na.or.complete")^2) # 1-(1+cor(datUse[,kpS]))/2  # 
 set.seed(10)   # For reproducibility  
 mdmrOutCorU[[r]] = MDMR(DMATRIX=dmatrixCorU[[r]], DATA=mdmrInfo[kpS,], PERMS=100, UNIVARIATE=TRUE)$UNIVARIATE
 print(paste("Done with",r))
}

dmatrixCorA  = as.matrix(dist(1-cor(datUse,use="na.or.complete")))
set.seed(10)   # For reproducibility  
mdmrOutCorAa = MDMR(DMATRIX=dmatrixCorA, DATA=cbind(region,mdmrInfo), PERMS=100, UNIVARIATE=TRUE)
mdmrOutCorA  = mdmrOutCorAa$UNIVARIATE
mdmrOutCorU[["All"]] = mdmrOutCorA

getColor <- function(x,cuts=c(Inf,0.05,0.01),col=c("red","lightgreen","green")){
  cols = rep("grey",length(x))
  for (i in 1:length(cuts))  cols[x<cuts[i]] = col[i]
  return(cols)
}

outFracs <- mdmrOutCorU[["All"]][,"PVE"]
outCols  <- getColor(mdmrOutCorU[["All"]][,"PVAL"])
for (r in regions){
  outFracs <- cbind(outFracs,c(0,mdmrOutCorU[[r]][,"PVE"]))
  outCols  <- cbind(outCols,c("black",getColor(mdmrOutCorU[[r]][,"PVAL"])))
}
rownames(outFracs) <- rownames(outCols) <- rownames(mdmrOutCorU[["All"]])
colnames(outFracs) <- colnames(outCols) <- c("All",regions)
l = 1:length(rownames(outFracs))
x = cbind(l,l,l,l,l)
y = cbind(rep(1,max(l)),rep(2,max(l)),rep(3,max(l)),rep(4,max(l)),rep(5,max(l)))

pdf("FiguresSxx_varianceExplained_dotPlot.pdf",height=7,width=18)
plot(x,y[,5:1],type="p",pch=15,col=outCols,ylim=c(-8,5.5),xlim=c(-2,41),cex=3.5)
abline(h=c(0:5)+0.5)
abline(v=c(0.5,l+0.5))
text(l,-3.2,rownames(outFracs),srt=90,cex=1)
text(-0.5,5:1,colnames(outFracs),cex=1)
text(x,y[,5:1],round(outFracs*100),cex=1)
dev.off()
