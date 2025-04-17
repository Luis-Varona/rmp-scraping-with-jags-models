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
      Rating[i] ~ dnorm(mu[School[i]], tau)
    }
    
    for (s in 1:num_schools) {
      mu[s] ~ dnorm(mu_pop, tau_pop)
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

.internal_DEST <- "part2_hdr.png"


# %%
main <- function() {
  data <- setup_data()
  samples <- get_jags_samples(data, .internal_MODEL_STRING, .internal_VAR_NAMES)
  grid_plot <- print_and_plot_hdrs(samples)
  save_hdr_gridplot(grid_plot, .internal_DEST)
}


# %%
setup_data <- function() {
  df <- combine_all_csvs(SCHOOL_ABBREVS)
  df <- mutate(df, school_factor = match(School, names(SCHOOL_ABBREVS)))
  
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
print_and_plot_hdrs <- function(samples) {
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
main()
