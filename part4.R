# %%
library(coda)
library(ggplot2)
library(gridExtra)
library(hdrcde)
library(rjags)


# %%
source('utils.R')


# %%
.internal_MODEL_STRING <- sprintf(
  "model {
    for (i in 1:num_ratings) {
      Rating[i] ~ dnorm(mu[Department[i]], tau)
    }
    
    for (d in 1:num_departments) {
      mu[d] ~ dnorm(mu_pop, tau_pop)
    }
    
    mu_pop ~ dnorm(%f, %f)
    tau ~ dgamma(%f, %f)
    tau_pop ~ dgamma(%f, %f)
  }",
  INIT_MODE, INIT_TAU,
  INIT_ALPHA, INIT_BETA,
  INIT_ALPHA, INIT_BETA
)

.internal_VAR_NAMES <- c("mu", "mu_pop", "tau", "tau_pop")

.internal_DEST <- "part4_hdr.png"


# %%
main <- function() {
  data <- setup_data()
  samples <- get_jags_samples(data, .internal_MODEL_STRING, .internal_VAR_NAMES)
  print_and_saveplot_pop_hdr(samples)
}


# %%
setup_data <- function() {
  df <- combine_all_csvs(SCHOOL_ABBREVS)
  df <- mutate(df, department_factor = factor(Department))
  
  num_ratings <- nrow(df)
  num_departments <- length(levels(df$department_factor))
  
  list(
    Rating = df$Rating,
    Department = df$department_factor,
    num_ratings = num_ratings,
    num_departments = num_departments
  )
}


# %%
print_and_saveplot_pop_hdr <- function(samples) {
  title <- sprintf("Population \u2013 All Schools (%d%% HDR)", PROB * 100)
  dest = file.path(DEST_FOLDER, .internal_DEST)
  
  if (!dir.exists(DEST_FOLDER)) {
    dir.create(DEST_FOLDER)
  }
  
  png(
    dest,
    width = HDR_PLOT_WIDTH,
    height = HDR_PLOT_HEIGHT,
    res = HDR_PLOT_DPI
  )
  hdr_result <- hdr.den(samples$mu_pop, prob = PROB, main = title)
  dev.off()
  
  cat("\nPopulation Estimate (All Schools):\n")
  print(hdr_result)
}


# %%
main()
