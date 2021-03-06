#' Compile one or several R Markdown reports
#'
#' @param reports Either a regular expression (passed directly to `grep()`) that
#'   matches to the report paths you would like to compile or an integer/logical
#'   vector.  If `reports` is an integer or logical vector then a call of
#'   `compile_reports(factory, reports = idx)` is equivalent to
#'   `compile_reports(factory, list_reports(factory)[idx])`.
#' @param factory The path to the report factory or a folder within the desired
#'   factory. Defaults to the current directory.
#' @param params A named list of parameters to be used for compiling reports,
#'   passed to `rmarkdown::render()` as the params argument. Values specified
#'   here will take precedence over default values specified in YAML headers of
#'   the reports. Note that the set of parameter is used for all compiled
#'   reports.
#' @param ignore.case if FALSE (default), the report pattern matching is case
#'   sensitive and if TRUE, case is ignored during matching.
#' @param quiet A logical indicating if messages from R Markdown compilation
#'   should be displayed; `TRUE` by default.
#' @param timestamp A character indicating the date-time format to be used for
#'   timestamps. Timestamps are used in the folder structure of outputs. If
#'   NULL, the format format(Sys.time(), "%Y-%m-%d_T%H-%M-%S") will be used.
#'   Note that the timestamp corresponds to the time of the call to
#'   compile_reports(), so that multiple reports compiled using a single call
#'   to the function will have identical timestamps.
#' @param subfolder Name of subfolder to store results.  Not required but helps
#'   distinguish output if mapping over multiple parameters.  If provided,
#'   "subfolder" will be placed before the timestamp when storing compilation
#'   outputs.
#' @param ... further arguments passed to `rmarkdown::render()`
#'
#' @return Invisble NULL (called for side effects only).
#'
#'
#' @importFrom utils write.table
#' @export
compile_reports <- function(reports = NULL, factory = ".", ignore.case = FALSE,
                            params = NULL, quiet = TRUE, subfolder = NULL,
                            timestamp = format(Sys.time(), "%Y-%m-%d_T%H-%M-%S"),
                            ...) {

  # Added this as Brian Ripley raised issues with portability and solaris
  # Check to see if pandoc is installed
  if(!rmarkdown::pandoc_available()) {
    stop("Pandoc is not installed; please install before proceeding")
  }

  # force timestamp to evaluate as soon as function called - needed due to the
  # `Sys.time` call within the default argument
  force(timestamp)

  # get factory root, report_sources and output folders
  tmp <- validate_factory(factory)
  root <- tmp$root
  report_sources <- tmp$report_sources
  outputs <- tmp$outputs

  # get vector of reports to compile
  report_template_dir <- file.path(root, report_sources)
  report_sources <- file.path(report_template_dir, list_reports(root))

  # error if report folder empty
  if (length(report_sources) == 0) {
    stop(sprintf("No reports found in %s", report_template_dir))
  }

  if (!is.null(reports)) {
    if ((is.numeric(reports) && is.wholenumber(reports)) || is.logical(reports)) {
      report_sources <- report_sources[reports]
      if (any(is.na(report_sources)) || length(report_sources) == 0) {
        stop("Unable to match reports with the given index")
      }
    } else {
      report_sources <- lapply(
        reports,
        grep,
        report_sources,
        value = TRUE,
        ignore.case = ignore.case
      )
      report_sources <- unique(unlist(report_sources))
      if (any(is.na(report_sources)) || length(report_sources) == 0) {
        stop("Unable to find matching reports to compile")
      }
    }
  }

  # create output directory
  report_output_dir <- file.path(root, outputs)
  if (!dir.exists(report_output_dir)) {
    dir.create(report_output_dir)
  }

  params_to_print <- params

  # loop over all reports
  for (r in report_sources) {

    # get files present in report folder and timestamps
    files_at_start <- list_report_folder_files(report_template_dir)
    dirs_at_start <- list_report_folder_files(report_template_dir, directories = TRUE)

    # pull yaml from the report
    yaml <- rmarkdown::yaml_front_matter(r)

    # If params are supplied, these are combined with any default parameters
    # that may be set in the report header.  Where there are overlaps preference
    # is given to those set here.  After much trial and error the current way
    # we facilitate this is to alter the yaml header and save this altered
    # version to a new file which we then compile.
    if (!is.null(params)) {
      p <- yaml$params
      if (is.null(p)) {
        params_input <- params
      } else {
        other_params <- p[!names(p) %in% names(params)]
        params_input <- append(params, other_params)
      }
      out_file <- file.path(report_template_dir, "_reportfactory_tmp_.Rmd")
      on.exit(suppressWarnings(file.remove(out_file)), add = TRUE)
      change_yaml_matter(r, params = params_input, output_file = out_file)
      params_to_print <- params_input
    }

    # display just enough information to be useful
    relative_path <- sub(report_template_dir, "", r)
    relative_path <- sub("\\.[a-zA-Z0-9]*$", "", relative_path)
    relative_path <- sub("^/", "", relative_path)
    message(">>> Compiling report: ", relative_path)
    if (!is.null(names(params_to_print))) {
      message(
          "      - with parameters: ",
          paste(names(params_to_print), params_to_print, sep = " = ", collapse = ", ")
      )
    }

    # create an additional subfolder if desired
    if (is.null(subfolder)) {
      output_folder <- file.path(
        report_output_dir,
        relative_path,
        timestamp
      )
    } else {
      output_folder <- file.path(
        report_output_dir,
        relative_path,
        subfolder,
        timestamp
      )
    }
    #dir.create(output_folder, recursive = TRUE)

    # render a report in a cleaner environment using `callr::r`.
    # the calls below are a little verbose but currently work (can simplify
    # later if we desire)
    if (is.null(params)) {
      callr::r(
        function(input, output_folder, quiet, ...) {
          rmarkdown::render(
            input,
            output_format = "all",
            output_dir = output_folder,
            envir = globalenv(),
            quiet = quiet,
            ...)
        },
        args = list(
          input = r,
          output_folder = output_folder,
          quiet = quiet,
          ...
        )
      )
    } else {
      callr::r(
        function(input, output_folder, out_file, quiet, ...) {
          rmarkdown::render(
            input,
            output_format = "all",
            output_file = out_file,
            output_dir = output_folder,
            params = NULL,
            envir = globalenv(),
            quiet = quiet,
            ...)
        },
        args = list(
          input = out_file,
          output_folder = output_folder,
          out_file = file.path(relative_path),
          quiet = quiet,
          ...
        )
      )
    }

    # remove the temporary outfile if present
    if (!is.null(params)) file.remove(out_file)

    # get files present in report folder and timestamps
    files_at_end <- list_report_folder_files(report_template_dir)

    # work out which files are new
    new_files <- rows_in_x_not_in_y(files_at_end, files_at_start)$files

    # make a copy of the report and the new files
    file.copy(r, output_folder)
    new_locations <- sub(dirname(r), output_folder, new_files)
    for (d in dirname(new_locations))
      if (!dir.exists(d)) {
        dir.create(d, recursive = TRUE)
      }
    file.rename(new_files, new_locations)

    # remove left over folders
    dirs_at_end <- list_report_folder_files(report_template_dir, directories = TRUE)

    # work out which files are new
    new_dirs <- rows_in_x_not_in_y(dirs_at_end, dirs_at_start)$files

    # remove new directories
    unlink(new_dirs, recursive = TRUE)
  }

  message("All done!\n")

  invisible(NULL)
}
