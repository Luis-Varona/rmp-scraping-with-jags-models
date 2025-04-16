# %%
library(coda)
library(ggplot2)
library(gridExtra)
library(hdrcde)
library(rjags)


# %%
source('utils.R')


# %%
.internal_VAR_NAMES <- c("mu", "tau", "mu_pop", "tau_pop")
.internal_MODEL_STRING <- sprintf(
  "model {
    for (i in 1:num_ratings) {
      Rating[i] ~ dnorm(mu[School[i]], tau)
    }
    
    for (j in 1:num_schools) {
      mu[j] ~ dnorm(mu_pop, tau_pop)
    }
    
    tau ~ dgamma(%f, %f)
    mu_pop ~ dnorm(%f, %f)
    tau_pop ~ dgamma(%f, %f)
  }",
  INIT_ALPHA, INIT_BETA,
  INIT_MODE, INIT_TAU,
  INIT_ALPHA, INIT_BETA
)


# %%
main <- function() {
  data <- setup_data()
  samples <- get_jags_samples(data)
  grid_plot <- print_and_plot_hdr(samples)
  save_hdr_gridplot(grid_plot)
}


# %%
setup_data <- function() {
  df <- combine_all_csvs(SCHOOL_ABBREVS)
  num_ratings <- nrow(df)
  num_schools <- length(SCHOOL_ABBREVS)
  
  list(
    Rating = df$Rating,
    School = df$school_factor,
    num_ratings = num_ratings,
    num_schools = num_schools
  )
}


# %%
get_jags_samples <- function(data) {
  jags_model <- jags.model(
    textConnection(.internal_MODEL_STRING),
    data = data,
    n.chains = NUM_CHAINS,
    n.adapt = NUM_ADAPT
  )
  update(jags_model, n.iter = NUM_ITER_JAGS)
  
  coda_samples <- coda.samples(
    jags_model,
    variable.names = .internal_VAR_NAMES,
    n.iter = NUM_ITER_CODA
  )
  do.call(rbind.data.frame, coda_samples)
}


# %%
print_and_plot_hdr <- function(samples) {
  title_pop <- sprintf("Population \u2013 All Schools (%d%% HDR)", PROB * 100)
  hdr_pop_data <- hdr_result_and_plot(
    samples$mu_pop,
    PROB,
    title_pop
  )
  hdr_plots <- list(hdr_pop_data$plot)
  
  cat("\nPopulation Estimate (All Schools):\n")
  print(hdr_pop_data$result)
  
  for (i in 1:length(SCHOOL_ABBREVS)) {
    school <- names(SCHOOL_ABBREVS)[i]
    column <- sprintf("mu[%d]", i)
    title <- sprintf("%s (%d%% HDR)", school, PROB * 100)
    
    hdr_data <- hdr_result_and_plot(samples[[column]], PROB, title)
    hdr_plots <- append(hdr_plots, list(hdr_data$plot))
    
    cat(sprintf("\nEstimate for %s:\n", school))
    print(hdr_data$result)
  }
  
  grid.arrange(grobs = hdr_plots, ncol = GRIDPLOT_COLS)
}


# %%
save_hdr_gridplot <- function(grid_plot) {
  if (!dir.exists(DEST_FOLDER)) {
    dir.create(DEST_FOLDER, recursive = TRUE)
  }
  
  dest <- file.path(DEST_FOLDER, "model1_plots.png")
  ggsave(
    dest,
    plot = grid_plot,
    width = GRIDPLOT_WIDTH,
    height = GRIDPLOT_HEIGHT,
    dpi = GRIDPLOT_DPI
  )
}


# %%
main()
