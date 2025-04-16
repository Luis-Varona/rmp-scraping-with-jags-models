# %%
library(coda)
library(ggplot2)
library(gridExtra)
library(hdrcde)
library(rjags)


# %%
source('utils.R')
df <- combine_all_csvs(SCHOOL_ABBREVS)
