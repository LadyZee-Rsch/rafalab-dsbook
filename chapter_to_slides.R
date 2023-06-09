#' chapter to slides
#' 
#' Convert a bookdown chapter Rmd file to Rmd slides 
#'
#' The function converts Rmd chapters from the Intro to Data Science book into Rmd ready 
#' to be compiled in slides. It is somewhat hard-wired to the style used in this book.
#' It turns every sentence into an entry in a bullet point with a new page automatically started 
#' after predetermined number o lines or characters is reached. If a section has titled exercise the section is 
#' saved in a separate file and omitted from slides. The R chunks that do not include plotting functions
#' are preserved. Chunks that plot and do not include either eval=FALSE or echo=FALSE are copied twice 
#' so that code shows in one page and the plot in another.
#' 
#' Note that the yml header is hard wired. If you want to change, edit the line where `start` is defined.
#' 
#' @details The output is should be checked before kniting as the output is rarely perfect. In particular,
#' think of the R output that will be generated by the R chunks as these are not seen and therefore not
#' counted when deciding when to start a new page. 
#' 
#' @author Rafael A. Irizarry
#' 
#' @param input Input Rmd file to be converted.
#' @param output Name of output file without extension. Defaults to same as input. 
#' @param output.dir Directory in which to save output file. Defaults to working directory.
#' @param output.exercise Name of output file for exercises. Defaults to -exercise appended to output.
#' @param suffix File extension. Defaults to Rmd
#' @param img.dir Directory to look for images in. Defaults to ./img
#' @param title Title for slides. Defaults to output with dash replaced by spaces and title case. 
#' @param author Author for the slides
#' @param max.lines Number of lines per slide
#' @param chars.per.line Number of characters that define a line.
#' @param max.section.title.length If the section number is bigger than this it gets cut-off. Defaults to infinity.
#' @param save,exercises If true saves a separate file with exercises.
#' @param verbose If TRUE show information about line being processed.
#' 
#' @return A data frame with counts for each group for each date with population sizes, if demo was provided.
#' 
#' @examples
#' \dontrun{
#' rmd_to_slides("dsbood/inference/models.Rmd", "lectures/inference/models")
#' }
#' @export
#' @import stringr

chapter_to_slides <- function(input, 
                          output = NULL, 
                          output.dir = getwd(),
                          output.exercises = NULL,
                          suffix = "Rmd",
                          img.dir = "img",
                          title = NULL,
                          author = "Rafael A. Irizarry",
                          max.lines = 15,
                          chars.per.line = 60,
                          max.section.title.length = NULL,
                          save.exercises = TRUE,
                          verbose=FALSE){
  ## Version: 0.0.1
  ## License: Artistic-2.0
  ## Author: Rafael A. Irizarry
  
  library(stringr)
  
  if(is.null(output)){
    output <- basename(input)
    output <- gsub("\\.[a-z|A-Z|0-9]+$", "", output)
  }
  output <- file.path(output.dir, output)
  file_name <- str_c(output, ".", suffix)
  if(file.exists(file_name)) stop(file_name, " file exists. Pick a different filename or remove the file.")
  
  start_section <- function(start.lines = 0, env = parent.frame()){
    cat("\n\n", env$the_section, "\n\n", sep = "", 
        file = env$file_name, append = TRUE)
    env$lines <- start.lines
    env$page <- env$page + 1
  }
  
  ## define filename for extracted exercises if not provided
  if(is.null(output.exercises)){
    output.exercises <- paste0(output, "-exercises")
  }
  
  ## add suffix to filenames
  exercise_file_name <- str_c(output.exercises, ".", suffix)
  
  ## define title if not provided
  if(is.null(title)){
    title <- str_replace_all(basename(output), "-", " ") |> str_to_title() 
  }
  
  if(is.null(max.section.title.length)) max.section.title.length <- -1L
  ## read-in input line by line
  x <- readLines(input)
  ## Remove empty lines
  x <- x[!str_trim(x)==""]
  ## Remove comments
  x <- x[!str_detect(x, "<!--")]
  x <- x[!str_detect(x, "img_path\\s+<-")]
  ## The following code is only needed for files
  ## that check for knitr format to make tables
  ## this is very specific to files from the book
  
  ### CHECK, knitr::kable is not being inserted
  ### CHECK WITH intro-ml
  ## REMOVE <!---  comments
  ## Sectiong are starting inside latex
  ## inline R should not be now line
  
  ## CHEKC ALSO LATEX... turingin into prose. check confusionmatrix
  table_index <- str_which(x, "if\\(knitr::is_html_output\\(\\)\\)\\{")
  if(length(table_index)>0){
    out <- c()
    for(i in table_index){
      tab_name <- str_match(x[i+1], "kable\\((\\w.*),.*[latex|html].*")[1,2] ## grab name of table object 
      x[i] <- str_c("    knitr::kable(", tab_name, ")")
      out <- c(out,i)
      j <- i
      ends <- 0
      while(ends<1){
        j <- j+1
        out <- c(out,j)
        if(str_detect(x[j], "\\}")) ends <- ends + 1
        if(str_detect(x[j], "\\{")) ends <- ends - 1
      }
    }    
  x <- x[-out]
  }
  
  ##line_type will store, for each line of x, what kind of line it is
  ##options are 
  ## section header
  ## prose
  ## rchunk start inside or end
  ## exercise_start
  ## plot rchunk start inside or end
  ## quotes
  ## latex start inside or end
  ## table
  ## last line
  line_type <- rep("prose", length(x))
  
  ## find section starts
  section_starts <- str_which(x, "^\\#+\\s+")
  
  ## clean up section start names and cut if longer than certain size
  x[section_starts] <- x[section_starts] |> 
    str_remove("\\{.*\\}") |>
    str_replace_all("#+", "##") |>
    str_trim() |>
    str_sub(1L, max.section.title.length)
  
  line_type[section_starts] <- "section"
  
  ## find exercise section starts
  exercise_starts <- str_which(x, "## [Ee]xercise|## [Ee]jercicio")
  line_type[exercise_starts] <- "exercise_start"
  
  ## find the latex start and ends
  latex_inds <- str_which(x, "\\$\\$")
  oneline_latex_inds <- str_which(x, "\\$\\$.+\\$\\$")
  if(length(oneline_latex_inds)){ 
    latex_inds <- setdiff(latex_inds, oneline_latex_inds)
    line_type[oneline_latex_inds] <- "oneline_latex"
  }
  
  if(length(latex_inds) %% 2 > 0){
    warning("Detected unclosed latex on lines. Check output carefully.")
    latex_inds <- c(latex_inds, dplyr::last(latex_inds))
  }
  
  if(length(latex_inds)>0){
    latex_start <-latex_inds[seq(1,length(latex_inds),2)]
    latex_end <- latex_inds[seq(2,length(latex_inds),2)]
    latex_size <- rep(0, length(x)) ## used to decide if start new section
    latex_size[latex_start] <- pmax(1, latex_end - latex_start - 2)
  
  
    ## if start and end in same line make it the end
    line_type[latex_start] <- "latex_start"
    line_type[latex_end] <- "latex_end"
  
    
    ## find the insider of latex
    for(i in seq_along(latex_start)){
      st <- latex_start[i]
      en <- latex_end[i]
      if(st==en){ 
        line_type[st] <- "latex_start_and_end" ## if onle line of latex use this
      } else{
        ind <- (st+1):(en-1)
        if(length(ind)>0){
          line_type[ind] <- "latex_inside"
        }
      }
    }
  }
  
  ## find start of tables
  line_type[str_detect(str_trim(x), "^\\|")] <- "table"
  rchunk_start <- c()
  rchunk_end <- c()
  
  ## find the code chunk start and ends
  start_flag <- TRUE
  for(i in seq_along(x)){
    if(str_detect(x[i], "^```")){
      if(start_flag){
        rchunk_start <- c(rchunk_start, i)
        line_type[i] <- "rchunk_start"
        start_flag <- FALSE
      } else{
        rchunk_end <- c(rchunk_end, i)
        line_type[i] <- "rchunk_end"
        start_flag <- TRUE
      }
    }
  }
  
  no_code <- which(rchunk_end - rchunk_start==1)
  line_type[rchunk_start[no_code]] <- "dont_print"
  line_type[rchunk_end[no_code]] <- "dont_print"
  rchunk_start <- setdiff(rchunk_start, rchunk_start[no_code])
  rchunk_end <- setdiff(rchunk_end, rchunk_end[no_code])
  
  rchunk_size <- rep(0, length(x)) ## used to decide if start new section
  if(length(rchunk_start)){
    rchunk_size[rchunk_start] <- pmax(1, rchunk_end - rchunk_start - 2)
  }
  
  ## Check if R chunk is a plot chunk and change if it is
  if(length(rchunk_start)){
    rchunk_inds <- cbind(rchunk_start, rchunk_end)
    plot_inds <- which(apply(rchunk_inds, 1, function(ind){
      any(str_detect(x[ind[1]:ind[2]], "plot|hist|include_graphics"))
    }))
  } else{
    plot_inds <- NULL
  }
  
  plot_rchunk_start <- rchunk_start[plot_inds]
  plot_rchunk_end <- rchunk_end[plot_inds]
  
  line_type[plot_rchunk_start] <- "plot_rchunk_start"
  line_type[plot_rchunk_end] <- "plot_rchunk_end"
  
  
  ## find quotes
  quote_index <- str_which(x, "^>>.*")
  line_type[quote_index] <- "quote"
  
  ## find the insider of r chunks
  rchunk_size <- rep(0, length(x)) ## used to decide if start new section
  rchunk_size[rchunk_start] <- rchunk_end - rchunk_start
  
  for(i in seq_along(rchunk_start)){
    ind <- (rchunk_start[i]+1):(rchunk_end[i]-1)
    if(length(ind)>0) line_type[ind] <- "rchunk_inside"
  }
  
  ## find the inside of plot r chunks
  for(i in seq_along(plot_rchunk_start)){
    ind <- (plot_rchunk_start[i]+1):(plot_rchunk_end[i]-1)
    if(length(ind)>0) line_type[ind] <- "plot_rchunk_inside"
  }
  
  the_section <- ""
  ## the start is hard wired
  start <- paste0('---\ntitle: "LECTURETITLE"\nauthor: "THEAUTHORNAME"\ndate: "`r lubridate::today()`"\noutput:\n  ioslides_presentation:\n    fig_caption: no\n    fig_height: 5\n    fig_width: 7\n    out_width: "70%"\n  beamer_presentation: default\n  slidy_presentation: default\n---\n\n```{r setup, include=FALSE}\nlibrary(tidyverse)\nlibrary(dslabs)\nlibrary(gridExtra)\nlibrary(ggthemes)\nds_theme_set()\noptions(digits = 3)\nknitr::opts_chunk$set(\n  comment = "#>",\n  collapse = TRUE,\n  cache = TRUE,\n  out.width = "70%",\n  fig.align = "center",\n  fig.width = 6,\n  fig.asp = 0.618,  # 1 / phi\n  fig.show = "hold"\n)\n\nimg_path <- "', img.dir,'"\n```')
  start <- str_replace(start, "LECTURETITLE", title)
  start <- str_replace(start, "THEAUTHORNAME", author)
  
  ## start filling in the file
  cat(start, file = file_name)
  
  ## if there is at lease one exercise section starti filling in file
  if(any(line_type=="exercise_start") & save.exercises) cat("", file = exercise_file_name)
  exercise_flag <- FALSE
  
  table_flag <- FALSE
  table_start <- TRUE
  
  ## make last value a new lines
  x[length(x)+1] <- "\n"
  line_type[length(x)] <- "last_line"
  
  ## initialize values
  chars <- 0
  lines <- 0
  page <- 0
  ## start going line by line
  for(i in seq_along(x)){
    if(verbose) cat("Page: ", page, ", Line: ", lines, ", Type: ", line_type[i], 
                    ", Section: ", the_section, "\n")
    ## if line is start of section, start section and initialize counts
    ## and turn of exercise flag (if previously true, exercise section has ended)
    if(line_type[i]=="section"){
      the_section <- x[i]
      exercise_flag <- FALSE
      start_section()
    } else{
      ## if exercise start, turn on flag and start just printing out exercises to 
      ## new file
      if(line_type[i]=="exercise_start" | exercise_flag){
        exercise_flag <- TRUE
        if(save.exercises) cat(x[i], "\n", file = exercise_file_name, append = TRUE)
      } else{
        if(line_type[i]=="table" | table_flag){
          if(table_start){ 
            cat("\n", x[i], "\n", sep="", file = file_name, append = TRUE)
            table_start <- FALSE
            lines <- lines + 3
          } else{
            if(str_detect(str_trim(x[i+1]), "\\|")){ ##check if next line is table
              cat(x[i], "\n", file = file_name, append = TRUE)
              lines <- lines + 2
            } else{ ##if next line not table, it's the end
              cat(x[i], "\n\n", file = file_name, append = TRUE)
              table_flag <- FALSE
              table_start <- TRUE
              lines <- lines + 3
            }
          }
        } else{
          ## if its a quote add to slides
          if(line_type[i] %in% c("oneline_latex", "quote")){
            lines <- lines + ceiling(nchar(x[i])/chars.per.line) + 1
            cat(x[i], "\n\n", file = file_name, append = TRUE)
          } else{
            ## R chunks that are not plots are just added to output
            if(line_type[i] %in% c("rchunk_end", "rchunk_inside","rchunk_start",
                                   "plot_rchunk_end", "plot_rchunk_inside", 
                                   "latex_inside")){
              if(str_detect(line_type[i], "inside")) lines <- lines + 1
              if(line_type[i] == "latex_inside") lines <- lines + 1 ## add one more for latex
              if(line_type[i] == "rchunk_start"){
                if(lines + rchunk_size[i] > max.lines) start_section()
              }
              cat(x[i], "\n", file = file_name, append = TRUE)
              if(line_type[i] == "rchunk_end") cat("\n", file = file_name, append = TRUE)
              if(line_type[i] == "plot_rchunk_end") start_section()
            } else{
              ## If r chunk includes a plot we will add it twice
              ## one with eval=FALSE and once with echo=FALSE
              ## unless the code already specifies it's echo or eval
              if(line_type[i] == "plot_rchunk_start"){
                ## if echo nor eval are defined
                ## we include the code twice, first with eval=FALSE,
                ## which is what the while lopp does,
                ## then after the while loop it adds a sectio header,
                ##the first line with echo=FALSE, and in the next
                ## iteration of the i for loop will continue adding the lines
                ## to see why, look at the previous if statement
                if(!str_detect(x[i], "echo|eval")){ 
                  y <- str_replace(x[i], "\\}", ", eval=FALSE}")
                  cat(y, "\n", file = file_name, append = TRUE)
                  j <- i
                  while(line_type[j]!="plot_rchunk_end"){
                    j <- j + 1
                    cat(x[j], "\n", file = file_name, append = TRUE)
                  }
                  start_section()
                  y <- str_replace(x[i], "```\\{r,*\\s+([\\w|\\-]+)", "```\\{r \\1-run")
                  y <- str_replace(y, "\\}", ", echo=FALSE}")
                  cat(y, "\n", file = file_name, append = TRUE)
                } else{
                  if(lines>2) start_section()
                  cat(x[i], "\n", file = file_name, append = TRUE)
                }
              } else{
                ## if we entry is a sentnce, we will split by periods
                ## and put each sentences as a bullet point
                ## the first three lines are two avoid spliting
                ## decimals, and abberviated titles.. might need more
                ## the trick is to covert points to commans, then convert back
                ## after the split
                if(line_type[i] == "prose"){
                  x[i] <- str_trim(x[i])
                  x[i] <- str_replace_all(x[i], "^(\\d+)\\.\\s+", "\\1PERIOD ")
                  x[i] <- str_replace_all(x[i], "(\\d)\\.(\\d)", "\\1PERIOD\\2")
                  x[i] <- str_replace_all(x[i], "(Mr|Ms|Dr)\\.", "\\1PERIOD")
                  
                  y <- str_split(x[i], "\\.\\s+")[[1]]
                  
                  for(j in seq_along(y)){
                    ## convert back to periods
                    
                    y[j] <- str_replace_all(y[j], "^(\\d+)PERIOD ", "\\1. ")
                    y[j] <- str_replace_all(y[j], "(\\d)PERIOD(\\d)", "\\1.\\2")
                    y[j] <- str_replace_all(y[j], "(Mr|Ms|Dr)PERIOD", "\\1.")
                    y[j] <- str_trim(y[j])
                    
                    lines <- lines + ceiling(nchar(y[j])/chars.per.line) + 1
                    
                    ## if we have gone past max lines start a new section
                    if(lines > max.lines){
                      start_section(ceiling(nchar(y[j])/chars.per.line) + 1)
                    }
                    ## add a period at end of bullet point unless we already have
                    ## punctuation
                    if(!str_sub(y[j], nchar(y[j]), nchar(y[j])) %in% c(".","?",":",",")){
                      y[j] <- y[j] <- str_c(y[j],".")
                    } 
                    if(str_detect(y[j], "^\\d+\\.")){
                      cat("  ", y[j], "\n\n", sep = "", 
                          file = file_name, append = TRUE)  
                    } else{
                      cat("- ", y[j], "\n\n", sep = "", 
                          file = file_name, append = TRUE)  
                    }
                  }
                } else{
                  if(line_type[i] == "latex_start"){
                    if(lines + latex_size[i]*2 > max.lines) start_section()
                    cat("\n", x[i], "\n", sep = "", file = file_name, append = TRUE)
                    lines <- lines + 1 
                  } else{
                    if(line_type[i] == "latex_end"){
                      cat(x[i], "\n\n", sep = "", file = file_name, append = TRUE)
                      lines <- lines + 1 
                    } else{
                      if(line_type[i] == "latex_start_and_end"){
                        cat("\n", x[i], "\n\n", sep = "", file = file_name, append = TRUE)
                        lines <- lines + 3
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
