library(fs)

test_that("list_deps works", {

  f <- new_factory(path = path_temp(), move_in = FALSE)
  on.exit(dir_delete(f))

  # copy test reports over (as this has inline code)
  file_copy(path("test_reports", "package_calls.Rmd"), path(f, "report_sources"))
  file_copy(path("test_reports", "example.R"), path(f, "report_sources"))

  expected_deps_package_calls <- c("purrr", "readxl", "fs", "rmarkdown", "utils", "yaml", "callr", "rprojroot")

  expected_deps_example_report <- c("knitr", "fs", "rmarkdown")
  expected_deps_readme <- "rmarkdown"
  expected_deps <- c(expected_deps_package_calls,
                     expected_deps_example_report,
                     expected_deps_readme)
  deps <- list_deps(f)
  expect_equal(sort(deps), sort(unique(expected_deps)))
})
