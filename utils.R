# %%
library(dplyr)
library(grid)
library(png)
library(readr)


# %%
DEST_FOLDER <- "plots"

SCHOOL_ABBREVS <- c(
  "Acadia University" = "acadia",
  "Carleton University" = "carleton",
  "Mount Saint Vincent University" = "msvu",
  "Mount Allison University" = "mta",
  "Memorial University of Newfoundland" = "mun"
)


# %%
EPSILON <- 0.01
INIT_ALPHA <- 2
INIT_BETA <- 2
INIT_MODE <- 3.6
INIT_TAU <- 0.5


# %%
NUM_CHAINS <- 5
NUM_ADAPT <- 2500
NUM_ITER_JAGS <- 25000
NUM_ITER_CODA <- 50000
PROB <- 0.95


# %%
GRIDPLOT_COLS <- 2
GRIDPLOT_WIDTH <- 10
GRIDPLOT_HEIGHT <- 12
GRIDPLOT_DPI <- 300


# %%
HDR_PLOT_WIDTH <- 2000
HDR_PLOT_HEIGHT <- 1500
HDR_PLOT_DPI <- 300


# %%
process_school_data <- function(df, school) {
  df <- mutate(df, School = school)
  relocate(df, School, 1)
}


# %%
combine_all_csvs <- function(school_abbrevs) {
  dfs <- list()
  
  for (school in names(school_abbrevs)) {
    abbrev <- school_abbrevs[[school]]
    source <- sprintf('data/rmp_%s.csv', abbrev)
    df <- read_csv(source, show_col_types = FALSE)
    df <- process_school_data(df, school)
    dfs <- append(dfs, list(df))
  }
  
  bind_rows(dfs)
}


# %%
get_jags_samples <- function(data, model_string, var_names) {
  jags_model <- jags.model(
    textConnection(model_string),
    data = data,
    n.chains = NUM_CHAINS,
    n.adapt = NUM_ADAPT
  )
  update(jags_model, n.iter = NUM_ITER_JAGS)
  
  coda_samples <- coda.samples(
    jags_model,
    variable.names = var_names,
    n.iter = NUM_ITER_CODA
  )
  do.call(rbind.data.frame, coda_samples)
}


# %%
hdr_result_and_plot <- function(x, prob, title) {
  grid.newpage()
  
  temp_file <- tempfile(fileext = ".png")
  png(
    temp_file,
    width = HDR_PLOT_WIDTH,
    height = HDR_PLOT_HEIGHT,
    res = HDR_PLOT_DPI
  )
  hdr_result <- hdr.den(x, prob = prob, main = title)
  dev.off()
  
  img <- readPNG(temp_file)
  file.remove(temp_file)
  hdr_plot <- rasterGrob(img, interpolate = TRUE)
  
  list(result = hdr_result, plot = hdr_plot)
}


# %%
save_hdr_gridplot <- function(grid_plot, dest) {
  if (!dir.exists(DEST_FOLDER)) {
    dir.create(DEST_FOLDER, recursive = TRUE)
  }
  
  dest <- file.path(DEST_FOLDER, dest)
  ggsave(
    dest,
    plot = grid_plot,
    width = GRIDPLOT_WIDTH,
    height = GRIDPLOT_HEIGHT,
    dpi = GRIDPLOT_DPI
  )
}
