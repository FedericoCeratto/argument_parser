import
  nake, os, osproc, htmlparser, xmltree, strtabs, times,
  argument_parser, zipfiles, sequtils

const name = "argument_parser"
let
  modules = @[name]
  rst_files = @["docs"/"changes", "docs"/"release_steps",
    "LICENSE", "README"]

proc mangle_idx(filename, prefix: string): string =
  ## Reads `filename` and returns it as a string with `prefix` applied.
  ##
  ## All the paths in the idx file will be prefixed with `prefix`. This is done
  ## adding the prefix to the second *column* which is meant to be the html
  ## file reference.
  result = ""
  for line in filename.lines:
    var cols = to_seq(line.split('\t'))
    if cols.len > 1: cols[1] = prefix/cols[1]
    result.add(cols.join("\t") & "\n")


proc collapse_idx(base_dir: string) =
  ## Walks `base_dir` recursively collapsing idx files.
  ##
  ## The files are collapsed to the base directory using the semi full relative
  ## path replacing path separators with underscores. The contents of the idx
  ## files are modified to contain the relative path.
  let
    base_dir = if base_dir.len < 1: "." else: base_dir
    filter = {pcFile, pcLinkToFile, pcDir, pcLinkToDir}
  for path in base_dir.walk_dir_rec(filter):
    let (dir, name, ext) = path.split_file
    # Ignore files which are not an index.
    if ext != ".idx": continue
    # Ignore files found in the base_dir.
    if dir.same_file(base_dir): continue
    # Ignore paths starting with a dot
    if name[0] == '.': continue
    # Extract the parent paths.
    let dest = base_dir/(name & ext)
    var relative_dir = dir[base_dir.len .. <dir.len]
    if relative_dir[0] == DirSep or relative_dir[0] == AltSep:
      relative_dir.delete(0, 0)
    assert(not relative_dir.is_absolute)

    echo "Flattening ", path, " to ", dest
    dest.write_file(mangle_idx(path, relative_dir))


proc change_rst_links_to_html(html_file: string) =
  ## Opens the file, iterates hrefs and changes them to .html if they are .rst.
  let html = loadHTML(html_file)
  var DID_CHANGE: bool

  for a in html.findAll("a"):
    let href = a.attrs["href"]
    if not href.isNil:
      let (dir, filename, ext) = splitFile(href)
      if cmpIgnoreCase(ext, ".rst") == 0:
        a.attrs["href"] = dir / filename & ".html"
        DID_CHANGE = true

  if DID_CHANGE:
    writeFile(html_file, $html)

proc needs_refresh(target: string, src: varargs[string]): bool =
  assert len(src) > 0, "Pass some parameters to check for"
  var TARGET_TIME: float
  try:
    TARGET_TIME = toSeconds(getLastModificationTime(target))
  except EOS:
    return true

  for s in src:
    let srcTime = toSeconds(getLastModificationTime(s))
    if srcTime > TARGET_TIME:
      return true

proc nim_to_rst(nim_file, rst_file: string) =
  ## Reads nim_file and creates into rst_file a *blocked* nim version for HTML.
  let
    name = nim_file.splitFile.name
    title_symbols = repeatChar(name.len, '=')
  var source = "$1\n$2\n$1\n.. code-block:: nimrod\n  " % [title_symbols, name]
  source.add(readFile(nim_file).replace("\n", "\n  "))
  writeFile(rst_file, source)


iterator all_rst_files(): tuple[src, dest: string] =
  for rst_name in rst_files:
    var R: tuple[src, dest: string]
    R.src = rst_name & ".rst"
    # Ignore files if they don't exist, babel version misses some.
    if not R.src.existsFile:
      echo "Ignoring missing ", R.src
      continue
    R.dest = rst_name & ".html"
    yield R

iterator all_examples(): tuple[src, dest: string] =
  # Generates .nim/.html pairs from source in the examples directory.
  for path in "examples".walkDirRec:
    if path.splitFile().ext != ".nim": continue
    var R: tuple[src, dest: string]
    R.src = path
    R.dest = path.changeFileExt("html")
    yield R


task "babel", "Uses babel to install " & name & " locally":
  direshell("babel install -y")
  echo "Installed."

task "doc", "Generates HTML version of the documentation":
  # Generate documentation for the nim modules.
  for module in modules:
    let
      nim_file = module & ".nim"
      html_file = module & ".html"
    if not html_file.needs_refresh(nim_file): continue
    if not shell("nimrod doc --verbosity:0 --index:on", module):
      quit("Could not generate html doc for " & module)
    else:
      echo "Generated " & html_file

  # Generate html files from the example sources.
  #for nim_file, html_file in all_examples():
  #  if not html_file.needs_refresh(nim_file): continue
  #  # Create temporary rst file.
  #  let rst_file = nim_file.changeFileExt("rst")
  #  nim_to_rst(nim_file, rst_file)
  #  if not shell("nimrod rst2html --verbosity:0 --index:on", rst_file):
  #    quit("Could not generate html doc for " & rst_file)
  #  else:
  #    change_rst_links_to_html(html_file)
  #    echo rst_file & " -> " & html_file
  #  rst_file.removeFile

  # Generate html files from the rst docs.
  for rst_file, html_file in all_rst_files():
    if not html_file.needs_refresh(rst_file): continue
    let
      (dir, name, ext) = rst_file.split_file
      prev_dir = get_current_dir()

    if dir.len > 0: cd(dir)

    if not shell("nimrod rst2html --verbosity:0 --index:on", name & ext):
      quit("Could not generate html doc for " & rst_file)
    else:
      change_rst_links_to_html(html_file.extract_filename)
      echo rst_file & " -> " & html_file

    cd(prev_dir)

  collapse_idx(".")
  direShell nimExe, "buildIndex ."
  echo "All done"

task "check_doc", "Validates rst format for a subset of documentation":
  for rst_file, html_file in all_rst_files():
    echo "Testing ", rst_file
    let (output, exit) = execCmdEx("rst2html.py " & rst_file & " > /dev/null")
    if output.len > 0 or exit != 0:
      echo "Failed python processing of " & rst_file
      echo output

task "clean", "Removes temporal files, mainly":
  removeDir("nimcache")
  for path in walk_dir_rec("."):
    let ext = splitFile(path).ext
    if ext == ".html" or ext == ".idx":
      echo "Removing ", path
      path.removeFile()

task "dist_doc", "Generate zip with documentation":
    runTask "clean"
    runTask "doc"
    let
      dname = name & "-" & VERSION_STR & "-docs"
      zname = dname & ".zip"
    removeFile(name)
    removeFile(zname)
    var Z: TZipArchive
    proc zadd(dest, src: string) =
      echo "Adding '" & src & "' -> '" & dest & "'"
      Z.addFile(dest, src)
    if not Z.open(zname, fmWrite):
      quit("Couldn't open zip " & zname)
    try:
      echo "OPening ", name
      zadd(dname / name & ".html", name & ".html")
      echo "OPening ", name
      for rst_file, html_file in all_rst_files():
        zadd(dname / html_file, html_file)
      echo "OPening ", name
      for nim_file, html_file in all_examples():
        zadd(dname / html_file, html_file)
    finally:
      Z.close
    echo "Built ", zname, " sized ", zname.getFileSize, " bytes."
